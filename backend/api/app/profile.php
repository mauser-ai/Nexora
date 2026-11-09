<?php
declare(strict_types=1);

// GET  → profilo dell'utente autenticato (creato al volo se mancante;
//        il primo profilo in assoluto diventa superadmin).
// PUT  → aggiorna i campi del proprio profilo (preferenze incluse).

ob_start();

function profile_json_fail(string $message, int $code = 500): void
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
    profile_json_fail('Errore profile API: ' . $e->getMessage(), 500);
});

register_shutdown_function(function (): void {
    $error = error_get_last();
    if ($error === null) {
        return;
    }
    $fatalTypes = [E_ERROR, E_PARSE, E_CORE_ERROR, E_COMPILE_ERROR];
    if (in_array((int)$error['type'], $fatalTypes, true)) {
        profile_json_fail(
            'Errore PHP profile API: ' . ($error['message'] ?? 'fatal error'),
            500
        );
    }
});

try {
    require_once __DIR__ . '/helpers.php';
} catch (Throwable $e) {
    profile_json_fail('Errore caricamento helpers app: ' . $e->getMessage(), 500);
}

header('Content-Type: application/json; charset=utf-8');

$method = $_SERVER['REQUEST_METHOD'];

if ($method === 'GET' && (string)($_GET['probe'] ?? '') === '1') {
    json_ok([
        'ok' => true,
        'service' => 'profile',
        'authRequired' => true,
    ]);
}

$uid = require_auth();
$pdo = db();

if ($method === 'GET') {
    $email = trim((string)($_GET['email'] ?? ''));
    $profile = app_ensure_profile($pdo, $uid, $email);
    // Aggiorna l'email se arrivata dal client e mancante a DB.
    if ($email !== '' && ($profile['email'] ?? '') === '') {
        $pdo->prepare('UPDATE user_profiles SET email = :email WHERE uid = :uid')
            ->execute([':email' => $email, ':uid' => $uid]);
        $profile['email'] = $email;
    }
    json_ok(['profile' => app_profile_to_json($profile)]);
}

if ($method === 'PUT') {
    app_ensure_profile($pdo, $uid);
    $payload = request_json();

    $allowed = [
        'email' => 'email',
        'displayName' => 'display_name',
        'avatarUrl' => 'avatar_url',
        'accentColorHex' => 'accent_color',
        'desktopWallpaperUrl' => 'wallpaper_url',
    ];
    $sets = [];
    $params = [':uid' => $uid];
    foreach ($allowed as $jsonKey => $column) {
        if (array_key_exists($jsonKey, $payload)) {
            $sets[] = "$column = :$column";
            $params[":$column"] = (string)($payload[$jsonKey] ?? '');
        }
    }
    if (array_key_exists('desktopNotificationsEnabled', $payload)) {
        $sets[] = 'desktop_notifications = :notif';
        $params[':notif'] = $payload['desktopNotificationsEnabled'] ? 1 : 0;
    }
    if ($sets) {
        $pdo->prepare(
            'UPDATE user_profiles SET ' . implode(', ', $sets) . ' WHERE uid = :uid'
        )->execute($params);
    }
    $stmt = $pdo->prepare('SELECT * FROM user_profiles WHERE uid = :uid');
    $stmt->execute([':uid' => $uid]);
    json_ok([
        'ok' => true,
        'profile' => app_profile_to_json($stmt->fetch(PDO::FETCH_ASSOC) ?: []),
    ]);
}

json_error('Metodo non consentito.', 405);
