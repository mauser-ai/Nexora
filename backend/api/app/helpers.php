<?php
declare(strict_types=1);

// Helper condivisi degli endpoint app_api. Richiede il bootstrap dell'API
// principale (require_auth(), db(): PDO, json_ok, json_error, request_json).

require_once dirname(__DIR__) . '/bootstrap.php';

if (!function_exists('db')) {
    json_error('bootstrap.php non espone db(): PDO.', 500);
}

if (!function_exists('request_json')) {
    function request_json(): array
    {
        $raw = file_get_contents('php://input');
        if ($raw === false || trim($raw) === '') {
            return [];
        }
        $data = json_decode($raw, true);
        if (!is_array($data)) {
            json_error('Payload JSON non valido.', 400);
        }
        return $data;
    }
}

/** Codifica una lista come JSON per colonna TEXT. */
function app_list_encode($value): string
{
    $items = is_array($value)
        ? array_values(array_filter(array_map('strval', $value), 'strlen'))
        : [];
    return json_encode($items, JSON_UNESCAPED_UNICODE) ?: '[]';
}

/** Decodifica una colonna TEXT contenente JSON (array o oggetto). */
function app_json_decode(?string $raw, $fallback = [])
{
    if ($raw === null || $raw === '') {
        return $fallback;
    }
    $decoded = json_decode($raw, true);
    return $decoded === null ? $fallback : $decoded;
}

/** Datetime DB → ISO 8601 (o null). */
function app_iso(?string $dbDateTime): ?string
{
    if ($dbDateTime === null || $dbDateTime === '') {
        return null;
    }
    return str_replace(' ', 'T', $dbDateTime);
}

/**
 * Garantisce la riga profilo per l'utente autenticato e la ritorna.
 * Il primo profilo creato in assoluto diventa superadmin.
 */
function app_ensure_profile(PDO $pdo, string $uid, string $email = ''): array
{
    $stmt = $pdo->prepare('SELECT * FROM user_profiles WHERE uid = :uid');
    $stmt->execute([':uid' => $uid]);
    $row = $stmt->fetch(PDO::FETCH_ASSOC);
    if ($row) {
        app_ensure_workspace_user(
            $pdo,
            $uid,
            (string)($row['email'] ?? $email),
            (string)($row['display_name'] ?? '')
        );
        return $row;
    }

    $count = (int)$pdo->query('SELECT COUNT(*) FROM user_profiles')->fetchColumn();
    $role = $count === 0 ? 'superadmin' : 'operatore';

    $pdo->prepare(
        'INSERT INTO user_profiles (uid, email, role) VALUES (:uid, :email, :role)
         ON DUPLICATE KEY UPDATE uid = uid'
    )->execute([':uid' => $uid, ':email' => $email, ':role' => $role]);

    app_ensure_workspace_user($pdo, $uid, $email, '', null, '');

    $stmt->execute([':uid' => $uid]);
    return $stmt->fetch(PDO::FETCH_ASSOC) ?: [];
}

/** Profilo → payload API. */
function app_profile_to_json(array $row): array
{
    return [
        'uid' => (string)$row['uid'],
        'email' => (string)($row['email'] ?? ''),
        'displayName' => (string)($row['display_name'] ?? ''),
        'avatarUrl' => (string)($row['avatar_url'] ?? ''),
        'role' => (string)($row['role'] ?? 'operatore'),
        'accentColorHex' => (string)($row['accent_color'] ?? ''),
        'desktopWallpaperUrl' => (string)($row['wallpaper_url'] ?? ''),
        'desktopNotificationsEnabled' => (int)($row['desktop_notifications'] ?? 1) === 1,
    ];
}

function app_find_active_team_id_for_user(PDO $pdo, string $uid): ?string
{
    $stmt = $pdo->prepare(
        "SELECT team_id
         FROM team_members
         WHERE user_id = :uid AND status = 'active'
         ORDER BY joined_at ASC
         LIMIT 1"
    );
    $stmt->execute([':uid' => $uid]);
    $teamId = $stmt->fetchColumn();
    return $teamId ? (string)$teamId : null;
}

function app_ensure_workspace_user(
    PDO $pdo,
    string $uid,
    string $email = '',
    string $displayName = '',
    ?string $teamId = null,
    string $role = ''
): void {
    $resolvedTeamId = $teamId;
    if ($resolvedTeamId === null || $resolvedTeamId === '') {
        $resolvedTeamId = app_find_active_team_id_for_user($pdo, $uid);
    }

    $stmt = $pdo->prepare('SELECT id, team_id FROM users WHERE id = :id LIMIT 1');
    $stmt->execute([':id' => $uid]);
    $existing = $stmt->fetch(PDO::FETCH_ASSOC);

    if ($existing) {
        $sets = [];
        $params = [':id' => $uid];

        if ($email !== '') {
            $sets[] = 'email = :email';
            $params[':email'] = $email;
        }
        if ($displayName !== '') {
            $sets[] = 'display_name = :display_name';
            $params[':display_name'] = $displayName;
        }
        if ($role !== '') {
            $sets[] = 'role = :role';
            $params[':role'] = $role;
        }
        if ($resolvedTeamId !== null && $resolvedTeamId !== '' && (string)($existing['team_id'] ?? '') !== $resolvedTeamId) {
            $sets[] = 'team_id = :team_id';
            $params[':team_id'] = $resolvedTeamId;
        }

        if ($sets !== []) {
            $pdo->prepare(
                'UPDATE users SET ' . implode(', ', $sets) . ' WHERE id = :id'
            )->execute($params);
        }
        return;
    }

    $pdo->prepare(
        'INSERT INTO users (id, team_id, email, display_name, role, billing_profile, youdox_config, ui_state)
         VALUES (:id, :team_id, :email, :display_name, :role, :billing_profile, :youdox_config, :ui_state)'
    )->execute([
        ':id' => $uid,
        ':team_id' => $resolvedTeamId,
        ':email' => $email,
        ':display_name' => $displayName !== '' ? $displayName : $email,
        ':role' => $role,
        ':billing_profile' => '{}',
        ':youdox_config' => '{}',
        ':ui_state' => '{}',
    ]);
}

/** Esige il ruolo superadmin per l'utente corrente. */
function app_require_superadmin(PDO $pdo, string $uid): void
{
    $profile = app_ensure_profile($pdo, $uid);
    if (($profile['role'] ?? '') !== 'superadmin') {
        json_error('Operazione riservata ai superadmin.', 403);
    }
}
