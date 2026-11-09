<?php
declare(strict_types=1);

require_once __DIR__ . '/helpers.php';
require_once dirname(__DIR__) . '/stripe/common.php';

header('Content-Type: application/json; charset=utf-8');

$uid = require_auth();
$pdo = db();
$profile = app_ensure_profile($pdo, $uid);

function stripe_connect_require_schema(PDO $pdo): void
{
    $stmt = $pdo->query("SHOW TABLES LIKE 'team_stripe_connections'");
    $exists = $stmt ? $stmt->fetchColumn() : false;
    if (!$exists) {
        json_error(
            'Schema Stripe Connect non installato. Esegui /api/app/install.php?run=yes e ricarica i file backend.',
            503
        );
    }
}

function stripe_connect_team(PDO $pdo, string $uid): array
{
    $teamId = app_find_active_team_id_for_user($pdo, $uid);
    if ($teamId === null || $teamId === '') {
        json_error('Nessun team attivo associato all\'utente.', 403);
    }

    $stmt = $pdo->prepare(
        "SELECT t.* FROM teams t
         INNER JOIN team_members m ON m.team_id = t.id
         WHERE t.id = :id AND m.user_id = :uid AND m.status = 'active'
         LIMIT 1"
    );
    $stmt->execute([':id' => $teamId, ':uid' => $uid]);
    $team = $stmt->fetch(PDO::FETCH_ASSOC);
    if (!$team) {
        json_error('Team non trovato o accesso non autorizzato.', 403);
    }
    return $team;
}

function stripe_connect_can_manage(array $team, array $profile, string $uid): bool
{
    return (string)($team['owner_id'] ?? '') === $uid ||
        (string)($profile['role'] ?? '') === 'superadmin';
}

function stripe_connect_owner_email(PDO $pdo, array $team, string $fallbackUid): string
{
    $stmt = $pdo->prepare(
        'SELECT email FROM team_members WHERE team_id = :team_id AND user_id = :user_id LIMIT 1'
    );
    $stmt->execute([
        ':team_id' => (string)$team['id'],
        ':user_id' => (string)($team['owner_id'] ?? $fallbackUid),
    ]);
    $email = trim((string)($stmt->fetchColumn() ?: ''));
    if ($email !== '') {
        return $email;
    }

    $stmt = $pdo->prepare('SELECT email FROM user_profiles WHERE uid = :uid LIMIT 1');
    $stmt->execute([':uid' => (string)($team['owner_id'] ?? $fallbackUid)]);
    return trim((string)($stmt->fetchColumn() ?: ''));
}

function stripe_connect_row(PDO $pdo, string $teamId): ?array
{
    $stmt = $pdo->prepare(
        'SELECT * FROM team_stripe_connections WHERE team_id = :team_id LIMIT 1'
    );
    $stmt->execute([':team_id' => $teamId]);
    $row = $stmt->fetch(PDO::FETCH_ASSOC);
    return $row ?: null;
}

function stripe_connect_status_from_account(array $account, bool $isActive): string
{
    if (!$isActive) {
        return 'disconnected';
    }
    $chargesEnabled = !empty($account['charges_enabled']);
    $payoutsEnabled = !empty($account['payouts_enabled']);
    $detailsSubmitted = !empty($account['details_submitted']);
    if ($chargesEnabled && $payoutsEnabled) {
        return 'active';
    }
    if ($detailsSubmitted) {
        return 'pending_requirements';
    }
    return 'onboarding';
}

function stripe_connect_upsert(PDO $pdo, string $teamId, string $userId, array $values): void
{
    $stmt = $pdo->prepare(
        'INSERT INTO team_stripe_connections (
            team_id,
            stripe_account_id,
            account_type,
            onboarding_status,
            account_email,
            country,
            default_currency,
            details_submitted,
            charges_enabled,
            payouts_enabled,
            requirements_json,
            metadata_json,
            is_active,
            created_by_user_id,
            connected_at,
            last_synced_at
        ) VALUES (
            :team_id,
            :stripe_account_id,
            :account_type,
            :onboarding_status,
            :account_email,
            :country,
            :default_currency,
            :details_submitted,
            :charges_enabled,
            :payouts_enabled,
            :requirements_json,
            :metadata_json,
            :is_active,
            :created_by_user_id,
            :connected_at,
            :last_synced_at
        )
        ON DUPLICATE KEY UPDATE
            stripe_account_id = VALUES(stripe_account_id),
            account_type = VALUES(account_type),
            onboarding_status = VALUES(onboarding_status),
            account_email = VALUES(account_email),
            country = VALUES(country),
            default_currency = VALUES(default_currency),
            details_submitted = VALUES(details_submitted),
            charges_enabled = VALUES(charges_enabled),
            payouts_enabled = VALUES(payouts_enabled),
            requirements_json = VALUES(requirements_json),
            metadata_json = VALUES(metadata_json),
            is_active = VALUES(is_active),
            created_by_user_id = VALUES(created_by_user_id),
            connected_at = COALESCE(VALUES(connected_at), connected_at),
            last_synced_at = VALUES(last_synced_at)'
    );
    $stmt->execute([
        ':team_id' => $teamId,
        ':stripe_account_id' => (string)($values['stripe_account_id'] ?? ''),
        ':account_type' => (string)($values['account_type'] ?? 'express'),
        ':onboarding_status' => (string)($values['onboarding_status'] ?? 'not_connected'),
        ':account_email' => (string)($values['account_email'] ?? ''),
        ':country' => (string)($values['country'] ?? 'IT'),
        ':default_currency' => (string)($values['default_currency'] ?? 'eur'),
        ':details_submitted' => !empty($values['details_submitted']) ? 1 : 0,
        ':charges_enabled' => !empty($values['charges_enabled']) ? 1 : 0,
        ':payouts_enabled' => !empty($values['payouts_enabled']) ? 1 : 0,
        ':requirements_json' => json_encode($values['requirements'] ?? new stdClass(), JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES) ?: '{}',
        ':metadata_json' => json_encode($values['metadata'] ?? new stdClass(), JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES) ?: '{}',
        ':is_active' => array_key_exists('is_active', $values) ? (!empty($values['is_active']) ? 1 : 0) : 1,
        ':created_by_user_id' => $userId,
        ':connected_at' => $values['connected_at'] ?? null,
        ':last_synced_at' => $values['last_synced_at'] ?? gmdate('Y-m-d H:i:s'),
    ]);
}

function stripe_connect_sync(PDO $pdo, array $team, string $uid): ?array
{
    $row = stripe_connect_row($pdo, (string)$team['id']);
    if (!$row) {
        return null;
    }
    if (!stripe_is_ready()) {
        return $row;
    }

    $accountId = trim((string)($row['stripe_account_id'] ?? ''));
    if ($accountId === '') {
        return $row;
    }

    $account = stripe_api_request('GET', '/v1/accounts/' . rawurlencode($accountId));
    $isActive = (int)($row['is_active'] ?? 1) === 1;
    $status = stripe_connect_status_from_account($account, $isActive);
    $connectedAt = null;
    if ($status === 'active') {
        $connectedAt = ($row['connected_at'] ?? '') !== ''
            ? (string)$row['connected_at']
            : gmdate('Y-m-d H:i:s');
    }

    stripe_connect_upsert($pdo, (string)$team['id'], $uid, [
        'stripe_account_id' => $accountId,
        'account_type' => (string)($row['account_type'] ?? 'express'),
        'onboarding_status' => $status,
        'account_email' => (string)($account['email'] ?? ''),
        'country' => (string)($account['country'] ?? 'IT'),
        'default_currency' => strtolower((string)($account['default_currency'] ?? 'eur')),
        'details_submitted' => !empty($account['details_submitted']),
        'charges_enabled' => !empty($account['charges_enabled']),
        'payouts_enabled' => !empty($account['payouts_enabled']),
        'requirements' => $account['requirements'] ?? [],
        'metadata' => $account['metadata'] ?? [],
        'is_active' => $isActive,
        'connected_at' => $connectedAt,
        'last_synced_at' => gmdate('Y-m-d H:i:s'),
    ]);

    return stripe_connect_row($pdo, (string)$team['id']);
}

function stripe_connect_payload(?array $row, array $team): array
{
    $requirements = app_json_decode($row['requirements_json'] ?? null, []);
    $currentlyDue = is_array($requirements['currently_due'] ?? null)
        ? array_values($requirements['currently_due'])
        : [];
    $eventuallyDue = is_array($requirements['eventually_due'] ?? null)
        ? array_values($requirements['eventually_due'])
        : [];
    $pastDue = is_array($requirements['past_due'] ?? null)
        ? array_values($requirements['past_due'])
        : [];

    return [
        'configReady' => stripe_is_ready(),
        'publishableKey' => stripe_is_ready() ? stripe_publishable_key() : null,
        'teamId' => (string)$team['id'],
        'teamName' => (string)$team['name'],
        'connected' => $row !== null &&
            (int)($row['is_active'] ?? 1) === 1 &&
            (string)($row['onboarding_status'] ?? '') === 'active',
        'canAcceptPayments' => $row !== null &&
            (int)($row['is_active'] ?? 1) === 1 &&
            (int)($row['charges_enabled'] ?? 0) === 1 &&
            (int)($row['payouts_enabled'] ?? 0) === 1,
        'status' => $row === null
            ? 'not_connected'
            : (string)($row['onboarding_status'] ?? 'not_connected'),
        'accountId' => $row === null ? null : (string)($row['stripe_account_id'] ?? ''),
        'accountEmail' => $row === null ? null : (string)($row['account_email'] ?? ''),
        'country' => $row === null ? 'IT' : (string)($row['country'] ?? 'IT'),
        'currency' => $row === null ? 'eur' : (string)($row['default_currency'] ?? 'eur'),
        'detailsSubmitted' => $row !== null && (int)($row['details_submitted'] ?? 0) === 1,
        'chargesEnabled' => $row !== null && (int)($row['charges_enabled'] ?? 0) === 1,
        'payoutsEnabled' => $row !== null && (int)($row['payouts_enabled'] ?? 0) === 1,
        'currentlyDueCount' => count($currentlyDue),
        'eventuallyDueCount' => count($eventuallyDue),
        'pastDueCount' => count($pastDue),
        'requirements' => [
            'currentlyDue' => $currentlyDue,
            'eventuallyDue' => $eventuallyDue,
            'pastDue' => $pastDue,
            'disabledReason' => $requirements['disabled_reason'] ?? null,
        ],
        'setupEstimate' => '5-10 minuti',
        'connectedAt' => app_iso((string)($row['connected_at'] ?? '')),
        'lastSyncedAt' => app_iso((string)($row['last_synced_at'] ?? '')),
    ];
}

function stripe_connect_origin(array $payload): string
{
    $origin = trim((string)($payload['originUrl'] ?? ''));
    if ($origin === '' || !preg_match('/^https?:\\/\\//i', $origin)) {
        return stripe_platform_url();
    }
    return rtrim($origin, '/');
}

function stripe_connect_ensure_account(PDO $pdo, array $team, string $uid, string $origin): array
{
    $row = stripe_connect_row($pdo, (string)$team['id']);
    if ($row && trim((string)($row['stripe_account_id'] ?? '')) !== '') {
        if ((int)($row['is_active'] ?? 1) !== 1) {
            stripe_connect_upsert($pdo, (string)$team['id'], $uid, [
                'stripe_account_id' => (string)$row['stripe_account_id'],
                'account_type' => (string)($row['account_type'] ?? 'express'),
                'onboarding_status' => 'onboarding',
                'account_email' => (string)($row['account_email'] ?? ''),
                'country' => (string)($row['country'] ?? 'IT'),
                'default_currency' => (string)($row['default_currency'] ?? 'eur'),
                'details_submitted' => (int)($row['details_submitted'] ?? 0) === 1,
                'charges_enabled' => (int)($row['charges_enabled'] ?? 0) === 1,
                'payouts_enabled' => (int)($row['payouts_enabled'] ?? 0) === 1,
                'requirements' => app_json_decode($row['requirements_json'] ?? null, []),
                'metadata' => app_json_decode($row['metadata_json'] ?? null, []),
                'is_active' => true,
                'connected_at' => ($row['connected_at'] ?? '') !== '' ? (string)$row['connected_at'] : null,
            ]);
        }
        return stripe_connect_sync($pdo, $team, $uid) ?? stripe_connect_row($pdo, (string)$team['id']);
    }

    $config = stripe_config();
    $country = strtoupper(trim((string)($config['default_country'] ?? 'IT')));
    $ownerEmail = stripe_connect_owner_email($pdo, $team, $uid);
    $account = stripe_api_request('POST', '/v1/accounts', [
        'type' => 'express',
        'country' => $country,
        'email' => $ownerEmail,
        'capabilities[card_payments][requested]' => 'true',
        'capabilities[transfers][requested]' => 'true',
        'business_profile[name]' => (string)$team['name'],
        'business_profile[url]' => $origin,
        'metadata[nexora_team_id]' => (string)$team['id'],
        'metadata[nexora_team_name]' => (string)$team['name'],
        'metadata[nexora_owner_id]' => (string)($team['owner_id'] ?? $uid),
    ]);

    stripe_connect_upsert($pdo, (string)$team['id'], $uid, [
        'stripe_account_id' => (string)($account['id'] ?? ''),
        'account_type' => 'express',
        'onboarding_status' => 'onboarding',
        'account_email' => (string)($account['email'] ?? $ownerEmail),
        'country' => (string)($account['country'] ?? $country),
        'default_currency' => strtolower((string)($account['default_currency'] ?? 'eur')),
        'details_submitted' => !empty($account['details_submitted']),
        'charges_enabled' => !empty($account['charges_enabled']),
        'payouts_enabled' => !empty($account['payouts_enabled']),
        'requirements' => $account['requirements'] ?? [],
        'metadata' => $account['metadata'] ?? [],
        'is_active' => true,
    ]);

    return stripe_connect_row($pdo, (string)$team['id']) ?? [];
}

stripe_connect_require_schema($pdo);
$team = stripe_connect_team($pdo, $uid);
$method = strtoupper($_SERVER['REQUEST_METHOD'] ?? 'GET');

if ($method === 'GET') {
    $row = stripe_connect_sync($pdo, $team, $uid) ?? stripe_connect_row($pdo, (string)$team['id']);
    json_ok(['connection' => stripe_connect_payload($row, $team)]);
}

if ($method === 'POST') {
    if (!stripe_connect_can_manage($team, $profile, $uid)) {
        json_error('Solo owner del team o superadmin possono gestire Stripe.', 403);
    }
    if (!stripe_is_ready()) {
        json_error('Config Stripe mancante. Carica /api/stripe/config.local.php sul server.', 503);
    }

    $payload = request_json();
    $action = trim((string)($payload['action'] ?? ''));
    $origin = stripe_connect_origin($payload);
    $row = stripe_connect_ensure_account($pdo, $team, $uid, $origin);
    $accountId = trim((string)($row['stripe_account_id'] ?? ''));
    if ($accountId === '') {
        json_error('Account Stripe non creato correttamente.', 500);
    }

    if ($action === 'create_dashboard_link') {
        $login = stripe_api_request('POST', '/v1/accounts/' . rawurlencode($accountId) . '/login_links');
        $synced = stripe_connect_sync($pdo, $team, $uid) ?? stripe_connect_row($pdo, (string)$team['id']);
        json_ok([
            'url' => (string)($login['url'] ?? ''),
            'connection' => stripe_connect_payload($synced, $team),
        ]);
    }

    $link = stripe_api_request('POST', '/v1/account_links', [
        'account' => $accountId,
        'refresh_url' => $origin . '/?settings=integrations&stripe=refresh',
        'return_url' => $origin . '/?settings=integrations&stripe=connected',
        'type' => 'account_onboarding',
    ]);

    stripe_connect_upsert($pdo, (string)$team['id'], $uid, [
        'stripe_account_id' => $accountId,
        'account_type' => (string)($row['account_type'] ?? 'express'),
        'onboarding_status' => 'onboarding',
        'account_email' => (string)($row['account_email'] ?? ''),
        'country' => (string)($row['country'] ?? 'IT'),
        'default_currency' => (string)($row['default_currency'] ?? 'eur'),
        'details_submitted' => (int)($row['details_submitted'] ?? 0) === 1,
        'charges_enabled' => (int)($row['charges_enabled'] ?? 0) === 1,
        'payouts_enabled' => (int)($row['payouts_enabled'] ?? 0) === 1,
        'requirements' => app_json_decode($row['requirements_json'] ?? null, []),
        'metadata' => app_json_decode($row['metadata_json'] ?? null, []),
        'is_active' => true,
        'connected_at' => ($row['connected_at'] ?? '') !== '' ? (string)$row['connected_at'] : null,
    ]);

    $synced = stripe_connect_sync($pdo, $team, $uid) ?? stripe_connect_row($pdo, (string)$team['id']);
    json_ok([
        'url' => (string)($link['url'] ?? ''),
        'connection' => stripe_connect_payload($synced, $team),
    ]);
}

if ($method === 'DELETE') {
    if (!stripe_connect_can_manage($team, $profile, $uid)) {
        json_error('Solo owner del team o superadmin possono gestire Stripe.', 403);
    }
    $row = stripe_connect_row($pdo, (string)$team['id']);
    if (!$row) {
        json_ok(['ok' => true, 'connection' => stripe_connect_payload(null, $team)]);
    }

    stripe_connect_upsert($pdo, (string)$team['id'], $uid, [
        'stripe_account_id' => (string)($row['stripe_account_id'] ?? ''),
        'account_type' => (string)($row['account_type'] ?? 'express'),
        'onboarding_status' => 'disconnected',
        'account_email' => (string)($row['account_email'] ?? ''),
        'country' => (string)($row['country'] ?? 'IT'),
        'default_currency' => (string)($row['default_currency'] ?? 'eur'),
        'details_submitted' => (int)($row['details_submitted'] ?? 0) === 1,
        'charges_enabled' => false,
        'payouts_enabled' => false,
        'requirements' => app_json_decode($row['requirements_json'] ?? null, []),
        'metadata' => app_json_decode($row['metadata_json'] ?? null, []),
        'is_active' => false,
        'connected_at' => null,
    ]);
    json_ok([
        'ok' => true,
        'connection' => stripe_connect_payload(
            stripe_connect_row($pdo, (string)$team['id']),
            $team
        ),
    ]);
}

json_error('Metodo non consentito.', 405);
