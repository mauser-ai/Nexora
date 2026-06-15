<?php
declare(strict_types=1);

// Helper condivisi degli endpoint app_api. Richiede il bootstrap dell'API
// principale (require_auth(), db(): PDO, json_ok, json_error, request_json).

require_once dirname(__DIR__) . '/bootstrap.php';

if (!function_exists('db')) {
    json_error('bootstrap.php non espone db(): PDO.', 500);
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
        return $row;
    }

    $count = (int)$pdo->query('SELECT COUNT(*) FROM user_profiles')->fetchColumn();
    $role = $count === 0 ? 'superadmin' : 'operatore';

    $pdo->prepare(
        'INSERT INTO user_profiles (uid, email, role) VALUES (:uid, :email, :role)
         ON DUPLICATE KEY UPDATE uid = uid'
    )->execute([':uid' => $uid, ':email' => $email, ':role' => $role]);

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

/** Esige il ruolo superadmin per l'utente corrente. */
function app_require_superadmin(PDO $pdo, string $uid): void
{
    $profile = app_ensure_profile($pdo, $uid);
    if (($profile['role'] ?? '') !== 'superadmin') {
        json_error('Operazione riservata ai superadmin.', 403);
    }
}
