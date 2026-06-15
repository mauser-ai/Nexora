<?php
declare(strict_types=1);

// GET  → profilo dell'utente autenticato (creato al volo se mancante;
//        il primo profilo in assoluto diventa superadmin).
// PUT  → aggiorna i campi del proprio profilo (preferenze incluse).

require_once __DIR__ . '/helpers.php';

header('Content-Type: application/json; charset=utf-8');

$uid = require_auth();
$pdo = db();

$method = $_SERVER['REQUEST_METHOD'];

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
