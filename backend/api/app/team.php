<?php
declare(strict_types=1);

// Team dell'utente:
//   GET                  → team di appartenenza + membri (creato al volo se
//                          l'utente non appartiene a nessun team)
//   GET ?id=<teamId>     → branding di un team specifico (per logo nei PDF)
//   PUT  {name?, brandLogoUrl?, brandColor?}    → aggiorna il proprio team
//   POST {member:{userId,email,displayName,role,status}} → upsert membro
//   DELETE ?member=<uid> → rimuove un membro (owner/superadmin)

require_once __DIR__ . '/helpers.php';

ob_start();

function team_json_fail(string $message, int $code = 500): void
{
    while (ob_get_level() > 0) {
        ob_end_clean();
    }
    http_response_code($code);
    header('Content-Type: application/json; charset=utf-8');
    echo json_encode(['error' => $message], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
    exit;
}

set_exception_handler(function ($e): void {
    team_json_fail('Errore team API: ' . $e->getMessage(), 500);
});

register_shutdown_function(function (): void {
    $error = error_get_last();
    if ($error === null) {
        return;
    }
    $fatalTypes = [E_ERROR, E_PARSE, E_CORE_ERROR, E_COMPILE_ERROR];
    if (in_array((int)$error['type'], $fatalTypes, true)) {
        team_json_fail(
            'Errore PHP team API: ' . ($error['message'] ?? 'fatal error'),
            500
        );
    }
});

header('Content-Type: application/json; charset=utf-8');

$uid = require_auth();
$pdo = db();
$method = $_SERVER['REQUEST_METHOD'];

function team_json_decode_list(?string $raw): array
{
    if ($raw === null || $raw === '') {
        return [];
    }
    $decoded = json_decode($raw, true);
    return is_array($decoded) ? array_values(array_filter($decoded, 'is_string')) : [];
}

function team_has_module(array $team, string $moduleId): bool
{
    $modules = team_json_decode_list($team['enabled_modules'] ?? null);
    return in_array($moduleId, $modules, true);
}

function team_custom_fields_decode(?string $raw): array
{
    $decoded = app_json_decode($raw, []);
    return is_array($decoded) ? array_values($decoded) : [];
}

function team_roles_decode(?string $raw): array
{
    if ($raw === null || trim($raw) === '') {
        return [];
    }
    $decoded = json_decode($raw, true);
    if (!is_array($decoded)) {
        return [];
    }
    $roles = [];
    $seen = [];
    foreach ($decoded as $value) {
        $role = trim((string)$value);
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

function team_columns(PDO $pdo): array
{
    static $cache = null;
    if (is_array($cache)) {
        return $cache;
    }
    $rows = $pdo->query('SHOW COLUMNS FROM teams')->fetchAll(PDO::FETCH_ASSOC) ?: [];
    $cache = [];
    foreach ($rows as $row) {
        $field = (string)($row['Field'] ?? '');
        if ($field !== '') {
            $cache[$field] = true;
        }
    }
    return $cache;
}

function team_require_columns(PDO $pdo, array $columns, string $featureLabel): void
{
    $available = team_columns($pdo);
    $missing = [];
    foreach ($columns as $column) {
        if (!isset($available[$column])) {
            $missing[] = $column;
        }
    }
    if ($missing !== []) {
        json_error(
            'Schema team non aggiornato per ' . $featureLabel . '. Colonne mancanti: ' . implode(', ', $missing) .
            '. Esegui /api/app/install.php?run=yes e ricarica i file backend.',
            503
        );
    }
}

function validate_custom_field_definitions(array $definitions): array
{
    $allowedModules = ['companies', 'contacts', 'opportunities', 'projects'];
    $allowedTypes = ['text', 'textarea', 'select'];
    $counts = [];
    $normalized = [];

    foreach ($definitions as $index => $item) {
        if (!is_array($item)) {
            json_error('Definizione custom field non valida.', 422);
        }
        $id = trim((string)($item['id'] ?? ''));
        $module = trim((string)($item['module'] ?? ''));
        $label = trim((string)($item['label'] ?? ''));
        $type = trim((string)($item['type'] ?? ''));
        $maxLength = (int)($item['maxLength'] ?? 255);
        $options = is_array($item['options'] ?? null) ? $item['options'] : [];

        if ($id === '' || $label === '') {
            json_error('Ogni custom field deve avere id ed etichetta.', 422);
        }
        if (!in_array($module, $allowedModules, true)) {
            json_error('Modulo custom field non supportato: ' . $module, 422);
        }
        if (!in_array($type, $allowedTypes, true)) {
            json_error('Tipologia custom field non supportata: ' . $type, 422);
        }
        $counts[$module] = ($counts[$module] ?? 0) + 1;
        if ($counts[$module] > 10) {
            json_error('Massimo 10 custom field per modulo.', 422);
        }
        $normalizedOptions = array_values(array_filter(array_map(
            fn($value) => trim((string)$value),
            $options
        ), 'strlen'));
        if ($type === 'select' && $normalizedOptions === []) {
            json_error('Le select devono avere almeno un\'opzione.', 422);
        }
        $normalized[] = [
            'id' => $id,
            'module' => $module,
            'label' => $label,
            'type' => $type,
            'maxLength' => max(1, min($maxLength, 5000)),
            'options' => $normalizedOptions,
        ];
    }

    return $normalized;
}

function validate_team_roles(array $roles): array
{
    $normalized = [];
    $seen = [];
    foreach ($roles as $item) {
        $role = trim((string)$item);
        if ($role === '' || strtolower($role) === 'owner') {
            continue;
        }
        if (strlen($role) > 80) {
            json_error('Ogni ruolo deve restare entro 80 caratteri.', 422);
        }
        $key = strtolower($role);
        if (isset($seen[$key])) {
            continue;
        }
        $seen[$key] = true;
        $normalized[] = $role;
    }
    if (count($normalized) > 20) {
        json_error('Massimo 20 ruoli per team.', 422);
    }
    return $normalized;
}

function team_to_json(PDO $pdo, array $team): array
{
    $stmt = $pdo->prepare(
        'SELECT * FROM team_members WHERE team_id = :id ORDER BY display_name ASC'
    );
    $stmt->execute([':id' => $team['id']]);
    $members = array_map(
        fn(array $m) => [
            'userId' => (string)$m['user_id'],
            'email' => (string)$m['email'],
            'displayName' => (string)$m['display_name'],
            'role' => (string)$m['role'],
            'status' => (string)$m['status'],
            'joinedAt' => app_iso((string)$m['joined_at']),
        ],
        $stmt->fetchAll(PDO::FETCH_ASSOC) ?: []
    );
    return [
        'id' => (string)$team['id'],
        'name' => (string)$team['name'],
        'ownerId' => (string)$team['owner_id'],
        'brandLogoUrl' => (string)($team['brand_logo_url'] ?? ''),
        'brandColor' => (string)($team['brand_color'] ?? ''),
        'enabledModules' => team_json_decode_list($team['enabled_modules'] ?? null),
        'customFieldDefinitions' => team_custom_fields_decode($team['custom_fields_config'] ?? null),
        'teamRoles' => team_roles_decode($team['roles_config'] ?? null),
        'appliedPackageIds' => team_json_decode_list($team['applied_package_ids'] ?? null),
        'createdAt' => app_iso((string)$team['created_at']),
        'members' => $members,
    ];
}

function team_of_user(PDO $pdo, string $uid): ?array
{
    $stmt = $pdo->prepare(
        'SELECT t.* FROM teams t
         INNER JOIN team_members m ON m.team_id = t.id
         WHERE m.user_id = :uid AND m.status = \'active\'
         ORDER BY t.created_at ASC LIMIT 1'
    );
    $stmt->execute([':uid' => $uid]);
    $team = $stmt->fetch(PDO::FETCH_ASSOC);
    return $team ?: null;
}

if ($method === 'GET') {
    $teamId = trim((string)($_GET['id'] ?? ''));
    if ($teamId !== '') {
        $stmt = $pdo->prepare('SELECT * FROM teams WHERE id = :id');
        $stmt->execute([':id' => $teamId]);
        $team = $stmt->fetch(PDO::FETCH_ASSOC);
        if (!$team) {
            json_ok(['team' => null]);
        }
        json_ok(['team' => team_to_json($pdo, $team)]);
    }

    $team = team_of_user($pdo, $uid);
    if ($team === null) {
        // Crea il team personale dell'utente al primo accesso.
        $profile = app_ensure_profile($pdo, $uid);
        $teamId = 'team-' . substr($uid, 0, 20);
        $name = $profile['display_name'] !== ''
            ? $profile['display_name']
            : (explode('@', (string)$profile['email'])[0] ?? 'Il mio team');
        $pdo->prepare(
            'INSERT INTO teams (id, name, owner_id, roles_config) VALUES (:id, :name, :owner, :roles)
             ON DUPLICATE KEY UPDATE id = id'
        )->execute([
            ':id' => $teamId,
            ':name' => $name,
            ':owner' => $uid,
            ':roles' => json_encode([
                'Commerciale',
                'Amministrazione',
                'Responsabile Amministrazione',
                'Operatore',
                'Responsabile Rendiconti',
                'Cliente',
            ], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES),
        ]);
        $pdo->prepare(
            'INSERT INTO team_members (team_id, user_id, email, display_name, role, status)
             VALUES (:team, :uid, :email, :name, \'owner\', \'active\')
             ON DUPLICATE KEY UPDATE status = \'active\''
        )->execute([
            ':team' => $teamId,
            ':uid' => $uid,
            ':email' => (string)$profile['email'],
            ':name' => (string)$profile['display_name'],
        ]);
        $team = team_of_user($pdo, $uid);
    }
    json_ok(['team' => $team ? team_to_json($pdo, $team) : null]);
}

// Per le scritture serve essere owner del team (o superadmin).
$team = team_of_user($pdo, $uid);
if ($team === null) {
    json_error('Nessun team associato all\'utente.', 404);
}
$profile = app_ensure_profile($pdo, $uid);
$canManage = $team['owner_id'] === $uid || ($profile['role'] ?? '') === 'superadmin';
$canManageBranding = $canManage || team_has_module($team, 'custom_branding');

if ($method === 'PUT') {
    $payload = request_json();
    $teamColumns = team_columns($pdo);
    $isBrandingOnly = true;
    foreach (array_keys($payload) as $key) {
        if (!in_array($key, ['brandLogoUrl', 'brandColor'], true)) {
            $isBrandingOnly = false;
            break;
        }
    }
    if ($isBrandingOnly) {
        if (!$canManageBranding) {
            json_error('Branding non abilitato per questo team.', 403);
        }
    } elseif (!$canManage) {
        json_error('Solo il titolare del team può modificarlo.', 403);
    }
    $sets = [];
    $params = [':id' => $team['id']];
    foreach ([
        'name' => 'name',
        'brandLogoUrl' => 'brand_logo_url',
        'brandColor' => 'brand_color',
    ] as $jsonKey => $column) {
        if (array_key_exists($jsonKey, $payload)) {
            if (!isset($teamColumns[$column])) {
                json_error(
                    'Schema team non aggiornato per il campo "' . $jsonKey . '". ' .
                    'Colonna mancante: ' . $column .
                    '. Esegui /api/app/install.php?run=yes e ricarica i file backend.',
                    503
                );
            }
            $sets[] = "$column = :$column";
            $params[":$column"] = (string)($payload[$jsonKey] ?? '');
        }
    }
    if (array_key_exists('customFieldDefinitions', $payload)) {
        if (!$canManage) {
            json_error('Solo il titolare del team può modificare i custom field.', 403);
        }
        team_require_columns($pdo, ['custom_fields_config'], 'custom field');
        $sets[] = 'custom_fields_config = :custom_fields_config';
        $params[':custom_fields_config'] = json_encode(
            validate_custom_field_definitions(
                is_array($payload['customFieldDefinitions'] ?? null)
                    ? $payload['customFieldDefinitions']
                    : []
            ),
            JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES
        ) ?: '[]';
    }
    if (array_key_exists('teamRoles', $payload)) {
        if (!$canManage) {
            json_error('Solo il titolare del team può modificare i ruoli.', 403);
        }
        team_require_columns($pdo, ['roles_config'], 'ruoli team');
        $sets[] = 'roles_config = :roles_config';
        $params[':roles_config'] = json_encode(
            validate_team_roles(
                is_array($payload['teamRoles'] ?? null)
                    ? $payload['teamRoles']
                    : []
            ),
            JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES
        ) ?: '[]';
    }
    if ($sets) {
        $pdo->prepare(
            'UPDATE teams SET ' . implode(', ', $sets) . ' WHERE id = :id'
        )->execute($params);
    }
    json_ok(['ok' => true]);
}

if ($method === 'POST') {
    if (!$canManage) {
        json_error('Solo il titolare del team può gestire i membri.', 403);
    }
    $payload = request_json();
    $member = $payload['member'] ?? null;
    if (!is_array($member) || trim((string)($member['userId'] ?? '')) === '') {
        json_error('Payload member non valido.', 422);
    }
    $pdo->prepare(
        'INSERT INTO team_members (team_id, user_id, email, display_name, role, status)
         VALUES (:team, :uid, :email, :name, :role, :status)
         ON DUPLICATE KEY UPDATE
           email = VALUES(email), display_name = VALUES(display_name),
           role = VALUES(role), status = VALUES(status)'
    )->execute([
        ':team' => $team['id'],
        ':uid' => trim((string)$member['userId']),
        ':email' => trim((string)($member['email'] ?? '')),
        ':name' => trim((string)($member['displayName'] ?? '')),
        ':role' => trim((string)($member['role'] ?? '')),
        ':status' => trim((string)($member['status'] ?? 'active')) ?: 'active',
    ]);
    app_ensure_workspace_user(
        $pdo,
        trim((string)$member['userId']),
        trim((string)($member['email'] ?? '')),
        trim((string)($member['displayName'] ?? '')),
        (string)$team['id'],
        trim((string)($member['role'] ?? ''))
    );
    json_ok(['ok' => true]);
}

if ($method === 'DELETE') {
    if (!$canManage) {
        json_error('Solo il titolare del team può gestire i membri.', 403);
    }
    $memberId = trim((string)($_GET['member'] ?? ''));
    if ($memberId === '' || $memberId === $team['owner_id']) {
        json_error('Membro non valido (il titolare non è rimovibile).', 422);
    }
    $pdo->prepare(
        'DELETE FROM team_members WHERE team_id = :team AND user_id = :uid'
    )->execute([':team' => $team['id'], ':uid' => $memberId]);
    json_ok(['ok' => true]);
}

json_error('Metodo non consentito.', 405);
