<?php
declare(strict_types=1);

// Gestione team lato piattaforma, solo superadmin.

ob_start();

function admin_json_fail(string $message, int $code = 500): void
{
    while (ob_get_level() > 0) {
        ob_end_clean();
    }
    http_response_code($code);
    header('Content-Type: application/json; charset=utf-8');
    echo json_encode(['error' => $message], JSON_UNESCAPED_UNICODE);
    exit;
}

set_exception_handler(function ($e): void {
    admin_json_fail($e->getMessage(), 500);
});

register_shutdown_function(function (): void {
    $error = error_get_last();
    if ($error === null) {
        return;
    }
    $fatalTypes = [E_ERROR, E_PARSE, E_CORE_ERROR, E_COMPILE_ERROR];
    if (in_array((int)$error['type'], $fatalTypes, true)) {
        admin_json_fail(
            'Errore PHP admin team: ' . ($error['message'] ?? 'fatal error'),
            500
        );
    }
});

try {
    require_once __DIR__ . '/helpers.php';
} catch (Throwable $e) {
    admin_json_fail('Errore caricamento helpers app: ' . $e->getMessage(), 500);
}

header('Content-Type: application/json; charset=utf-8');

$uid = require_auth();
$pdo = db();
app_require_superadmin($pdo, $uid);

$method = $_SERVER['REQUEST_METHOD'];

function admin_json_decode_assoc(?string $raw): array
{
    if ($raw === null || $raw === '') {
        return [];
    }
    $decoded = json_decode($raw, true);
    return is_array($decoded) ? $decoded : [];
}

function admin_allowed_team_modules(): array
{
    return ['nexora_ai', 'team_chat', 'integrations', 'bandi', 'custom_branding', 'nexora_pos'];
}

function admin_json_decode_list(?string $raw): array
{
    if ($raw === null || $raw === '') {
        return [];
    }
    $decoded = json_decode($raw, true);
    return is_array($decoded) ? array_values(array_filter($decoded, 'is_string')) : [];
}

function admin_normalize_team_modules(mixed $value): array
{
    $allowed = array_flip(admin_allowed_team_modules());
    if (!is_array($value)) {
        return [];
    }
    $modules = [];
    foreach ($value as $module) {
        $module = trim((string)$module);
        if ($module !== '' && isset($allowed[$module])) {
            $modules[$module] = true;
        }
    }
    return array_keys($modules);
}

function admin_validate_custom_field_definitions(mixed $value): array
{
    $allowedModules = ['companies', 'contacts', 'opportunities', 'projects'];
    $allowedTypes = ['text', 'textarea', 'select'];
    if (!is_array($value)) {
        return [];
    }
    $counts = [];
    $normalized = [];
    foreach ($value as $item) {
        if (!is_array($item)) {
            continue;
        }
        $id = trim((string)($item['id'] ?? ''));
        $module = trim((string)($item['module'] ?? ''));
        $label = trim((string)($item['label'] ?? ''));
        $type = trim((string)($item['type'] ?? ''));
        if ($id === '' || $label === '') {
            continue;
        }
        if (!in_array($module, $allowedModules, true) || !in_array($type, $allowedTypes, true)) {
            continue;
        }
        $counts[$module] = ($counts[$module] ?? 0) + 1;
        if ($counts[$module] > 10) {
            continue;
        }
        $options = is_array($item['options'] ?? null)
            ? array_values(array_filter(array_map(
                fn($option) => trim((string)$option),
                $item['options']
            ), 'strlen'))
            : [];
        if ($type === 'select' && $options === []) {
            continue;
        }
        $normalized[] = [
            'id' => $id,
            'module' => $module,
            'label' => $label,
            'type' => $type,
            'maxLength' => max(1, min((int)($item['maxLength'] ?? 255), 5000)),
            'options' => $options,
        ];
    }
    return $normalized;
}

function admin_normalize_roles(mixed $value): array
{
    if (!is_array($value)) {
        return [];
    }
    $seen = [];
    $roles = [];
    foreach ($value as $item) {
        $role = trim((string)$item);
        if ($role === '' || strtolower($role) === 'owner') {
            continue;
        }
        $key = strtolower($role);
        if (isset($seen[$key])) {
            continue;
        }
        $seen[$key] = true;
        $roles[] = $role;
    }
    return $roles;
}

function admin_merge_custom_fields(array $existing, array $incoming): array
{
    $merged = [];
    foreach ($existing as $field) {
        if (!is_array($field)) {
            continue;
        }
        $id = trim((string)($field['id'] ?? ''));
        if ($id === '') {
            continue;
        }
        $merged[$id] = $field;
    }
    foreach ($incoming as $field) {
        if (!is_array($field)) {
            continue;
        }
        $id = trim((string)($field['id'] ?? ''));
        if ($id === '') {
            continue;
        }
        $merged[$id] = $field;
    }
    return array_values($merged);
}

function admin_fetch_configuration_packages(PDO $pdo): array
{
    try {
        $rows = $pdo->query(
            'SELECT * FROM configuration_packages WHERE is_active = 1 ORDER BY package_type ASC, sort_order ASC, name ASC'
        )->fetchAll(PDO::FETCH_ASSOC) ?: [];
    } catch (Throwable $e) {
        return [];
    }
    return $rows;
}

function admin_package_to_json(array $row): array
{
    return [
        'id' => (string)($row['id'] ?? ''),
        'type' => (string)($row['package_type'] ?? 'custom_fields'),
        'name' => (string)($row['name'] ?? ''),
        'description' => (string)($row['description'] ?? ''),
        'icon' => (string)($row['icon'] ?? ''),
        'color' => (string)($row['color'] ?? ''),
        'enabledModules' => admin_json_decode_list($row['modules_json'] ?? null),
        'teamRoles' => admin_normalize_roles(admin_json_decode_list($row['roles_json'] ?? null)),
        'customFieldDefinitions' => admin_validate_custom_field_definitions(
            admin_json_decode_assoc($row['custom_fields_json'] ?? null)
        ),
        'metadata' => admin_json_decode_assoc($row['metadata_json'] ?? null),
        'active' => (int)($row['is_active'] ?? 1) === 1,
        'system' => (int)($row['is_system'] ?? 1) === 1,
    ];
}

function admin_sanitize_package_icon(string $icon): string
{
    $allowed = ['construction', 'support_agent', 'analytics', 'home_repair_service', 'inventory_2', 'widgets', 'hub', 'palette', 'forum'];
    return in_array($icon, $allowed, true) ? $icon : 'widgets';
}

function admin_save_configuration_package(PDO $pdo, array $package): string
{
    $id = trim((string)($package['id'] ?? ''));
    if ($id === '') {
        $id = 'pkg-' . date('YmdHis') . '-' . bin2hex(random_bytes(3));
    }
    $type = (string)($package['type'] ?? 'custom_fields');
    if (!in_array($type, ['sector', 'custom_fields'], true)) {
        json_error('Tipo pacchetto non valido.', 422);
    }
    $name = trim((string)($package['name'] ?? ''));
    if ($name === '') {
        json_error('Nome pacchetto obbligatorio.', 422);
    }
    $description = trim((string)($package['description'] ?? ''));
    $icon = admin_sanitize_package_icon(trim((string)($package['icon'] ?? 'widgets')));
    $color = strtoupper(trim((string)($package['color'] ?? '#22C55E')));
    if ($color === '' || !preg_match('/^#[0-9A-F]{6}$/', $color)) {
        $color = '#22C55E';
    }
    $modules = admin_normalize_team_modules($package['enabledModules'] ?? []);
    $roles = admin_normalize_roles(is_array($package['teamRoles'] ?? null) ? $package['teamRoles'] : []);
    $customFields = admin_validate_custom_field_definitions(
        is_array($package['customFieldDefinitions'] ?? null) ? $package['customFieldDefinitions'] : []
    );
    $metadata = is_array($package['metadata'] ?? null) ? $package['metadata'] : [];
    $active = ($package['active'] ?? true) ? 1 : 0;
    $system = ($package['system'] ?? false) ? 1 : 0;

    $stmt = $pdo->prepare(
        'INSERT INTO configuration_packages
         (id, package_type, name, description, icon, color, modules_json, roles_json, custom_fields_json, metadata_json, is_system, is_active, sort_order)
         VALUES
         (:id, :package_type, :name, :description, :icon, :color, :modules_json, :roles_json, :custom_fields_json, :metadata_json, :is_system, :is_active, :sort_order)
         ON DUPLICATE KEY UPDATE
           package_type = VALUES(package_type),
           name = VALUES(name),
           description = VALUES(description),
           icon = VALUES(icon),
           color = VALUES(color),
           modules_json = VALUES(modules_json),
           roles_json = VALUES(roles_json),
           custom_fields_json = VALUES(custom_fields_json),
           metadata_json = VALUES(metadata_json),
           is_system = VALUES(is_system),
           is_active = VALUES(is_active),
           sort_order = VALUES(sort_order)'
    );
    $stmt->execute([
        ':id' => $id,
        ':package_type' => $type,
        ':name' => $name,
        ':description' => $description,
        ':icon' => $icon,
        ':color' => $color,
        ':modules_json' => json_encode($modules, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES) ?: '[]',
        ':roles_json' => json_encode($roles, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES) ?: '[]',
        ':custom_fields_json' => json_encode($customFields, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES) ?: '[]',
        ':metadata_json' => json_encode($metadata, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES) ?: '{}',
        ':is_system' => $system,
        ':is_active' => $active,
        ':sort_order' => (int)($package['sortOrder'] ?? 999),
    ]);
    return $id;
}

function admin_apply_configuration_packages(PDO $pdo, array $team, array $packageIds): void
{
    $packageIds = array_values(array_unique(array_filter(array_map(
        fn($value) => trim((string)$value),
        $packageIds
    ), 'strlen')));

    $stmt = $pdo->query(
        'SELECT * FROM configuration_packages WHERE is_active = 1 ORDER BY package_type ASC, sort_order ASC, name ASC'
    );
    $catalog = [];
    foreach ($stmt->fetchAll(PDO::FETCH_ASSOC) ?: [] as $row) {
        $catalog[(string)$row['id']] = $row;
    }

    $selected = [];
    foreach ($packageIds as $packageId) {
        if (isset($catalog[$packageId])) {
            $selected[] = $catalog[$packageId];
        }
    }

    $currentModules = admin_json_decode_list($team['enabled_modules'] ?? null);
    $currentRoles = admin_normalize_roles(admin_json_decode_list($team['roles_config'] ?? null));
    $currentFields = admin_validate_custom_field_definitions(
        admin_json_decode_assoc($team['custom_fields_config'] ?? null)
    );

    $nextModules = $currentModules;
    $nextRoles = $currentRoles;
    $nextFields = $currentFields;

    foreach ($selected as $package) {
        $nextModules = array_values(array_unique(array_merge(
            $nextModules,
            admin_normalize_team_modules(admin_json_decode_list($package['modules_json'] ?? null))
        )));
        $nextRoles = admin_normalize_roles(array_merge(
            $nextRoles,
            admin_json_decode_list($package['roles_json'] ?? null)
        ));
        $nextFields = admin_merge_custom_fields(
            $nextFields,
            admin_validate_custom_field_definitions(
                admin_json_decode_assoc($package['custom_fields_json'] ?? null)
            )
        );
    }

    $pdo->prepare(
        'UPDATE teams
         SET enabled_modules = :enabled_modules,
             roles_config = :roles_config,
             custom_fields_config = :custom_fields_config,
             applied_package_ids = :applied_package_ids
         WHERE id = :id'
    )->execute([
        ':enabled_modules' => json_encode($nextModules, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES) ?: '[]',
        ':roles_config' => json_encode($nextRoles, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES) ?: '[]',
        ':custom_fields_config' => json_encode($nextFields, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES) ?: '[]',
        ':applied_package_ids' => json_encode($packageIds, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES) ?: '[]',
        ':id' => (string)$team['id'],
    ]);
}

function admin_team_to_json(PDO $pdo, array $team): array
{
    $stmt = $pdo->prepare(
        'SELECT * FROM team_members WHERE team_id = :id ORDER BY display_name ASC, email ASC'
    );
    $stmt->execute([':id' => $team['id']]);
    $members = array_map(
        function (array $m): array {
            return [
            'userId' => (string)$m['user_id'],
            'email' => (string)$m['email'],
            'displayName' => (string)$m['display_name'],
            'role' => (string)$m['role'],
            'status' => (string)$m['status'],
            'joinedAt' => app_iso((string)$m['joined_at']),
            ];
        },
        $stmt->fetchAll(PDO::FETCH_ASSOC) ?: []
    );

    return [
        'id' => (string)$team['id'],
        'name' => (string)$team['name'],
        'ownerId' => (string)$team['owner_id'],
        'brandLogoUrl' => (string)($team['brand_logo_url'] ?? ''),
        'brandColor' => (string)($team['brand_color'] ?? ''),
        'createdAt' => app_iso((string)$team['created_at']),
        'memberCount' => count($members),
        'members' => $members,
        'billingProfile' => admin_json_decode_assoc($team['billing_profile'] ?? null),
        'subscription' => admin_json_decode_assoc($team['subscription'] ?? null),
        'enabledModules' => admin_json_decode_list($team['enabled_modules'] ?? null),
        'appliedPackageIds' => admin_json_decode_list($team['applied_package_ids'] ?? null),
    ];
}

function admin_fetch_team(PDO $pdo, string $teamId): ?array
{
    $stmt = $pdo->prepare('SELECT * FROM teams WHERE id = :id');
    $stmt->execute([':id' => $teamId]);
    $team = $stmt->fetch(PDO::FETCH_ASSOC);
    return $team ?: null;
}

function admin_ensure_profile(
    PDO $pdo,
    string $userId,
    string $email,
    string $displayName,
    string $platformRole = 'operatore'
): void {
    $pdo->prepare(
        'INSERT INTO user_profiles (uid, email, display_name, role)
         VALUES (:uid, :email, :display_name, :role)
         ON DUPLICATE KEY UPDATE
          email = VALUES(email),
          display_name = IF(VALUES(display_name) <> \'\', VALUES(display_name), display_name)'
    )->execute([
        ':uid' => $userId,
        ':email' => $email,
        ':display_name' => $displayName,
        ':role' => $platformRole,
    ]);

    app_ensure_workspace_user($pdo, $userId, $email, $displayName, null, '');
}

if ($method === 'GET') {
    if (((string)($_GET['packages'] ?? '')) === '1') {
        json_ok([
            'packages' => array_map(
                'admin_package_to_json',
                admin_fetch_configuration_packages($pdo)
            ),
        ]);
    }

    $activityUserId = trim((string)($_GET['activityUserId'] ?? ''));
    if ($activityUserId !== '') {
        // Finché tutte le tabelle workspace non sono migrate qui ritorniamo
        // una struttura valida, evitando letture Firestore dal pannello admin.
        json_ok([
            'activity' => [
                'timeTracksCount' => 0,
                'totalHours' => 0.0,
                'tasksCount' => 0,
                'invoicesCount' => 0,
                'lastActivity' => null,
            ],
        ]);
    }

    $teamId = trim((string)($_GET['id'] ?? ''));
    if ($teamId !== '') {
        $team = admin_fetch_team($pdo, $teamId);
        json_ok(['team' => $team ? admin_team_to_json($pdo, $team) : null]);
    }

    $teams = $pdo->query(
        'SELECT * FROM teams ORDER BY created_at DESC'
    )->fetchAll(PDO::FETCH_ASSOC) ?: [];
    json_ok([
        'teams' => array_map(
            function (array $team) use ($pdo): array {
                return admin_team_to_json($pdo, $team);
            },
            $teams
        ),
    ]);
}

if ($method === 'POST') {
    $payload = request_json();
    $action = trim((string)($payload['action'] ?? ''));

    if ($action === 'createTeam') {
        $teamName = trim((string)($payload['teamName'] ?? ''));
        $owner = $payload['owner'] ?? null;
        if ($teamName === '' || !is_array($owner)) {
            json_error('Payload createTeam non valido.', 422);
        }

        $ownerId = trim((string)($owner['userId'] ?? ''));
        $email = trim((string)($owner['email'] ?? ''));
        $displayName = trim((string)($owner['displayName'] ?? ''));
        if ($ownerId === '' || $email === '') {
            json_error('Owner non valido.', 422);
        }

        $teamId = 'team-' . substr(preg_replace('/[^a-zA-Z0-9_-]/', '', $ownerId), 0, 20);
        $initialBillingProfile = [
            'businessName' => $teamName,
            'vatNumber' => '',
            'taxCode' => '',
            'addressLine' => '',
            'postalCode' => '',
            'city' => '',
            'countryCode' => 'IT',
            'regimeFiscale' => '',
            'reaOffice' => '',
            'reaNumber' => '',
            'email' => $email,
            'pec' => '',
            'phone' => '',
        ];

        $pdo->beginTransaction();
        try {
            admin_ensure_profile($pdo, $ownerId, $email, $displayName);
            $pdo->prepare(
                'INSERT INTO teams (id, name, owner_id, billing_profile)
                 VALUES (:id, :name, :owner_id, :billing_profile)
                 ON DUPLICATE KEY UPDATE
                   name = VALUES(name),
                   owner_id = VALUES(owner_id),
                   billing_profile = IF(
                     billing_profile IS NULL OR billing_profile = \'\',
                     VALUES(billing_profile),
                     billing_profile
                   )'
            )->execute([
                ':id' => $teamId,
                ':name' => $teamName,
                ':owner_id' => $ownerId,
                ':billing_profile' => json_encode($initialBillingProfile, JSON_UNESCAPED_UNICODE) ?: '{}',
            ]);
            $pdo->prepare(
                'INSERT INTO team_members (team_id, user_id, email, display_name, role, status)
                 VALUES (:team_id, :user_id, :email, :display_name, \'owner\', \'active\')
                 ON DUPLICATE KEY UPDATE
                   email = VALUES(email),
                   display_name = VALUES(display_name),
                   role = VALUES(role),
                   status = VALUES(status)'
            )->execute([
                ':team_id' => $teamId,
                ':user_id' => $ownerId,
                ':email' => $email,
                ':display_name' => $displayName,
            ]);
            app_ensure_workspace_user($pdo, $ownerId, $email, $displayName, $teamId, 'owner');
            $pdo->commit();
        } catch (Throwable $e) {
            $pdo->rollBack();
            throw $e;
        }

        json_ok(['ok' => true, 'teamId' => $teamId]);
    }

    if ($action === 'addMember') {
        $teamId = trim((string)($payload['teamId'] ?? ''));
        $member = $payload['member'] ?? null;
        if ($teamId === '' || !is_array($member)) {
            json_error('Payload addMember non valido.', 422);
        }

        $userId = trim((string)($member['userId'] ?? ''));
        $email = trim((string)($member['email'] ?? ''));
        $displayName = trim((string)($member['displayName'] ?? ''));
        $role = trim((string)($member['role'] ?? ''));
        $status = trim((string)($member['status'] ?? 'active')) ?: 'active';
        if ($userId === '' || $email === '') {
            json_error('Membro non valido.', 422);
        }

        if (!admin_fetch_team($pdo, $teamId)) {
            json_error('Team non trovato.', 404);
        }

        $pdo->beginTransaction();
        try {
            admin_ensure_profile($pdo, $userId, $email, $displayName);
            $pdo->prepare(
                'INSERT INTO team_members (team_id, user_id, email, display_name, role, status)
                 VALUES (:team_id, :user_id, :email, :display_name, :role, :status)
                 ON DUPLICATE KEY UPDATE
                   email = VALUES(email),
                   display_name = VALUES(display_name),
                   role = VALUES(role),
                   status = VALUES(status)'
            )->execute([
                ':team_id' => $teamId,
                ':user_id' => $userId,
                ':email' => $email,
                ':display_name' => $displayName,
                ':role' => $role,
                ':status' => $status,
            ]);
            app_ensure_workspace_user($pdo, $userId, $email, $displayName, $teamId, $role);
            $pdo->commit();
        } catch (Throwable $e) {
            $pdo->rollBack();
            throw $e;
        }

        json_ok(['ok' => true]);
    }

    if ($action === 'savePackage') {
        $package = $payload['package'] ?? null;
        if (!is_array($package)) {
            json_error('Payload pacchetto non valido.', 422);
        }
        $packageId = admin_save_configuration_package($pdo, $package);
        json_ok(['ok' => true, 'packageId' => $packageId]);
    }

    if ($action === 'deletePackage') {
        $packageId = trim((string)($payload['packageId'] ?? ''));
        if ($packageId === '') {
            json_error('packageId obbligatorio.', 422);
        }
        $pdo->prepare('DELETE FROM configuration_packages WHERE id = :id')->execute([
            ':id' => $packageId,
        ]);
        json_ok(['ok' => true]);
    }

    json_error('Azione non valida.', 422);
}

if ($method === 'PUT') {
    $payload = request_json();
    $teamId = trim((string)($payload['teamId'] ?? ''));
    if ($teamId === '') {
        json_error('teamId obbligatorio.', 422);
    }
    if (!admin_fetch_team($pdo, $teamId)) {
        json_error('Team non trovato.', 404);
    }

    $sets = [];
    $params = [':id' => $teamId];
    if (array_key_exists('name', $payload)) {
        $sets[] = 'name = :name';
        $params[':name'] = trim((string)$payload['name']);
    }
    if (array_key_exists('billingProfile', $payload)) {
        $sets[] = 'billing_profile = :billing';
        $params[':billing'] = json_encode($payload['billingProfile'], JSON_UNESCAPED_UNICODE) ?: '{}';
    }
    if (array_key_exists('subscription', $payload)) {
        $sets[] = 'subscription = :subscription';
        $params[':subscription'] = json_encode($payload['subscription'], JSON_UNESCAPED_UNICODE) ?: '{}';
    }
    if (array_key_exists('enabledModules', $payload)) {
        $sets[] = 'enabled_modules = :enabled_modules';
        $modules = admin_normalize_team_modules($payload['enabledModules']);
        $params[':enabled_modules'] = json_encode($modules, JSON_UNESCAPED_UNICODE) ?: '[]';
    }
    if (array_key_exists('appliedPackageIds', $payload)) {
        admin_apply_configuration_packages(
            $pdo,
            admin_fetch_team($pdo, $teamId) ?: [],
            is_array($payload['appliedPackageIds'] ?? null)
                ? $payload['appliedPackageIds']
                : []
        );
        json_ok(['ok' => true]);
    }
    if (!$sets) {
        json_ok(['ok' => true]);
    }

    $pdo->prepare('UPDATE teams SET ' . implode(', ', $sets) . ' WHERE id = :id')
        ->execute($params);
    json_ok(['ok' => true]);
}

if ($method === 'DELETE') {
    $teamId = trim((string)($_GET['teamId'] ?? ''));
    if ($teamId === '') {
        json_error('teamId obbligatorio.', 422);
    }

    $memberId = trim((string)($_GET['member'] ?? ''));
    if ($memberId !== '') {
        $team = admin_fetch_team($pdo, $teamId);
        if (!$team) {
            json_error('Team non trovato.', 404);
        }
        if ($memberId === (string)$team['owner_id']) {
            json_error('Il proprietario non può essere rimosso dal team.', 422);
        }
        $pdo->prepare(
            'DELETE FROM team_members WHERE team_id = :team_id AND user_id = :user_id'
        )->execute([':team_id' => $teamId, ':user_id' => $memberId]);
        json_ok(['ok' => true]);
    }

    $pdo->beginTransaction();
    try {
        $pdo->prepare('DELETE FROM team_members WHERE team_id = :team_id')
            ->execute([':team_id' => $teamId]);
        $pdo->prepare('DELETE FROM teams WHERE id = :team_id')
            ->execute([':team_id' => $teamId]);
        $pdo->commit();
    } catch (Throwable $e) {
        $pdo->rollBack();
        throw $e;
    }
    json_ok(['ok' => true]);
}

json_error('Metodo non consentito.', 405);
