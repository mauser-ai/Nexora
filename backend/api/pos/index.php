<?php
declare(strict_types=1);

require_once dirname(__DIR__) . '/bootstrap.php';

header('Content-Type: application/json; charset=utf-8');

$userId = require_auth();
$pdo = db();
$method = http_method();
$scopeId = current_team_id($userId) ?: $userId;

function pos_json_decode(?string $raw, $fallback = [])
{
    if ($raw === null || $raw === '') {
        return $fallback;
    }
    $decoded = json_decode($raw, true);
    return $decoded === null ? $fallback : $decoded;
}

function pos_iso(?string $value): ?string
{
    if ($value === null || $value === '') {
        return null;
    }
    return str_replace(' ', 'T', $value);
}

function pos_row_to_intent(array $row): array
{
    return [
        'id' => (string)$row['id'],
        'title' => (string)($row['title'] ?? 'Incasso'),
        'description' => (string)($row['description'] ?? ''),
        'amount' => $row['amount'] !== null ? (float)$row['amount'] : 0.0,
        'currency' => (string)($row['currency'] ?? 'EUR'),
        'status' => (string)($row['status'] ?? 'draft'),
        'provider' => (string)($row['provider'] ?? 'manual'),
        'source' => (string)($row['source'] ?? 'desktop'),
        'companyId' => $row['company_id'] ? (string)$row['company_id'] : null,
        'companyName' => $row['company_name'] ? (string)$row['company_name'] : null,
        'invoiceId' => $row['invoice_id'] ? (string)$row['invoice_id'] : null,
        'opportunityId' => $row['opportunity_id'] ? (string)$row['opportunity_id'] : null,
        'createdByUserId' => $row['created_by_user_id'] ? (string)$row['created_by_user_id'] : null,
        'createdAt' => pos_iso($row['created_at'] ?? null),
        'completedAt' => pos_iso($row['completed_at'] ?? null),
        'isDemo' => (int)($row['is_demo'] ?? 1) === 1,
        'paymentMode' => $row['payment_mode'] ? (string)$row['payment_mode'] : null,
        'invoiceNumberSnapshot' => $row['invoice_number_snapshot'] ? (string)$row['invoice_number_snapshot'] : null,
        'stripePaymentIntentId' => $row['stripe_payment_intent_id'] ? (string)$row['stripe_payment_intent_id'] : null,
        'stripeConnectedAccountId' => $row['stripe_connected_account_id'] ? (string)$row['stripe_connected_account_id'] : null,
        'generatedInvoiceId' => $row['generated_invoice_id'] ? (string)$row['generated_invoice_id'] : null,
        'paidAmount' => $row['paid_amount'] !== null ? (float)$row['paid_amount'] : null,
        'paymentMethodLabel' => $row['payment_method_label'] ? (string)$row['payment_method_label'] : null,
        'failureReason' => $row['failure_reason'] ? (string)$row['failure_reason'] : null,
        'metadata' => pos_json_decode($row['metadata_json'] ?? null, []),
    ];
}

function pos_row_to_device(array $row): array
{
    return [
        'id' => (string)$row['id'],
        'label' => (string)($row['label'] ?? ''),
        'platform' => (string)($row['platform'] ?? ''),
        'provider' => (string)($row['provider'] ?? 'manual'),
        'status' => (string)($row['status'] ?? 'offline'),
        'capabilities' => pos_json_decode($row['capabilities_json'] ?? null, []),
        'lastSeenAt' => pos_iso($row['last_seen_at'] ?? null),
        'updatedAt' => pos_iso($row['updated_at'] ?? null),
    ];
}

if ($method === 'GET') {
    $deviceStmt = $pdo->prepare(
        'SELECT * FROM pos_devices WHERE team_id = :team ORDER BY updated_at DESC, created_at DESC'
    );
    $deviceStmt->execute([':team' => $scopeId]);
    $devices = array_map('pos_row_to_device', $deviceStmt->fetchAll(PDO::FETCH_ASSOC) ?: []);

    $intentStmt = $pdo->prepare(
        'SELECT * FROM pos_payment_intents WHERE team_id = :team ORDER BY created_at DESC LIMIT 100'
    );
    $intentStmt->execute([':team' => $scopeId]);
    $intentRows = $intentStmt->fetchAll(PDO::FETCH_ASSOC) ?: [];
    $intents = array_map('pos_row_to_intent', $intentRows);

    $totalSucceededAmount = 0.0;
    $todaySucceededAmount = 0.0;
    $pendingCount = 0;
    $succeededCount = 0;
    $today = date('Y-m-d');

    foreach ($intentRows as $row) {
        $status = (string)($row['status'] ?? '');
        $amount = $row['amount'] !== null ? (float)$row['amount'] : 0.0;
        if ($status === 'succeeded') {
            $succeededCount++;
            $totalSucceededAmount += $amount;
            if (($row['completed_at'] ?? '') !== '' && substr((string)$row['completed_at'], 0, 10) === $today) {
                $todaySucceededAmount += $amount;
            }
        } elseif (in_array($status, ['draft', 'pending', 'prepared', 'processing'], true)) {
            $pendingCount++;
        }
    }

    json_ok([
        'scopeId' => $scopeId,
        'devices' => $devices,
        'intents' => $intents,
        'totalSucceededAmount' => round($totalSucceededAmount, 2),
        'todaySucceededAmount' => round($todaySucceededAmount, 2),
        'pendingCount' => $pendingCount,
        'succeededCount' => $succeededCount,
        'demoMode' => true,
    ]);
}

if ($method !== 'POST') {
    json_error('Metodo non consentito.', 405);
}

$payload = request_body();
$action = trim((string)($payload['action'] ?? ''));

switch ($action) {
    case 'save_device':
        $label = trim((string)($payload['label'] ?? ''));
        if ($label === '') {
            json_error('Label dispositivo obbligatoria.', 422);
        }
        $id = trim((string)($payload['id'] ?? ''));
        if ($id === '') {
            $id = 'posdev-' . bin2hex(random_bytes(8));
        }
        $capabilities = is_array($payload['capabilities'] ?? null)
            ? array_values(array_filter(array_map(
                fn($item) => trim((string)$item),
                $payload['capabilities']
            ), 'strlen'))
            : [];
        $stmt = $pdo->prepare(
            'INSERT INTO pos_devices (
                id, team_id, user_id, label, platform, provider, status,
                capabilities_json, last_seen_at
            ) VALUES (
                :id, :team_id, :user_id, :label, :platform, :provider, :status,
                :capabilities_json, NOW()
            )
            ON DUPLICATE KEY UPDATE
                label = VALUES(label),
                platform = VALUES(platform),
                provider = VALUES(provider),
                status = VALUES(status),
                capabilities_json = VALUES(capabilities_json),
                last_seen_at = NOW()'
        );
        $stmt->execute([
            ':id' => $id,
            ':team_id' => $scopeId,
            ':user_id' => $userId,
            ':label' => $label,
            ':platform' => trim((string)($payload['platform'] ?? 'flutter')),
            ':provider' => trim((string)($payload['provider'] ?? 'manual')),
            ':status' => trim((string)($payload['status'] ?? 'ready')),
            ':capabilities_json' => json_encode($capabilities, JSON_UNESCAPED_UNICODE) ?: '[]',
        ]);
        json_ok(['ok' => true, 'id' => $id]);
        break;

    case 'create_intent':
        $title = trim((string)($payload['title'] ?? ''));
        $amount = is_numeric($payload['amount'] ?? null) ? (float)$payload['amount'] : 0.0;
        if ($title === '' || $amount <= 0) {
            json_error('Titolo e importo sono obbligatori.', 422);
        }
        $id = 'posint-' . bin2hex(random_bytes(8));
        $stmt = $pdo->prepare(
            'INSERT INTO pos_payment_intents (
                id, team_id, created_by_user_id, company_id, company_name, invoice_id,
                opportunity_id, title, description, amount, currency, status, provider,
                source, is_demo, metadata_json
            ) VALUES (
                :id, :team_id, :created_by_user_id, :company_id, :company_name, :invoice_id,
                :opportunity_id, :title, :description, :amount, :currency, :status, :provider,
                :source, :is_demo, :metadata_json
            )'
        );
        $stmt->execute([
            ':id' => $id,
            ':team_id' => $scopeId,
            ':created_by_user_id' => $userId,
            ':company_id' => trim((string)($payload['companyId'] ?? '')) ?: null,
            ':company_name' => trim((string)($payload['companyName'] ?? '')) ?: null,
            ':invoice_id' => trim((string)($payload['invoiceId'] ?? '')) ?: null,
            ':opportunity_id' => trim((string)($payload['opportunityId'] ?? '')) ?: null,
            ':title' => $title,
            ':description' => trim((string)($payload['description'] ?? '')),
            ':amount' => round($amount, 2),
            ':currency' => strtoupper(trim((string)($payload['currency'] ?? 'EUR'))),
            ':status' => 'draft',
            ':provider' => trim((string)($payload['provider'] ?? 'manual')),
            ':source' => trim((string)($payload['source'] ?? 'desktop')),
            ':is_demo' => (($payload['isDemo'] ?? true) === false || (int)($payload['isDemo'] ?? 1) === 0) ? 0 : 1,
            ':metadata_json' => json_encode([
                'stage' => 'prepared',
                'bridge' => 'flutter_scaffold',
            ], JSON_UNESCAPED_UNICODE) ?: '{}',
        ]);
        json_ok(['ok' => true, 'id' => $id], 201);
        break;

    case 'mark_demo_paid':
        $intentId = trim((string)($payload['intentId'] ?? ''));
        if ($intentId === '') {
            json_error('Intent ID mancante.', 422);
        }
        $stmt = $pdo->prepare(
            'UPDATE pos_payment_intents
             SET status = :status, completed_at = NOW()
             WHERE id = :id AND team_id = :team_id'
        );
        $stmt->execute([
            ':status' => 'succeeded',
            ':id' => $intentId,
            ':team_id' => $scopeId,
        ]);
        json_ok(['ok' => true]);
        break;

    case 'cancel_intent':
        $intentId = trim((string)($payload['intentId'] ?? ''));
        if ($intentId === '') {
            json_error('Intent ID mancante.', 422);
        }
        $stmt = $pdo->prepare(
            'UPDATE pos_payment_intents
             SET status = :status
             WHERE id = :id AND team_id = :team_id'
        );
        $stmt->execute([
            ':status' => 'cancelled',
            ':id' => $intentId,
            ':team_id' => $scopeId,
        ]);
        json_ok(['ok' => true]);
        break;
}

json_error('Azione POS non valida.', 422);
