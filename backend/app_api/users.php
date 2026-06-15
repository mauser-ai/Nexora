<?php
declare(strict_types=1);

// Gestione utenti piattaforma (solo superadmin):
//   GET → elenco profili con ruolo
//   PUT → {uid, role} cambia il ruolo (superadmin | admin | operatore).
//         Possono esistere più superadmin; l'ultimo non è degradabile.

require_once __DIR__ . '/helpers.php';

header('Content-Type: application/json; charset=utf-8');

$uid = require_auth();
$pdo = db();
app_require_superadmin($pdo, $uid);

$method = $_SERVER['REQUEST_METHOD'];

if ($method === 'GET') {
    $rows = $pdo->query(
        'SELECT * FROM user_profiles ORDER BY role = \'superadmin\' DESC, email ASC'
    )->fetchAll(PDO::FETCH_ASSOC) ?: [];
    json_ok(['users' => array_map('app_profile_to_json', $rows)]);
}

if ($method === 'PUT') {
    $payload = request_json();
    $targetUid = trim((string)($payload['uid'] ?? ''));
    $role = trim((string)($payload['role'] ?? ''));
    if ($targetUid === '' || !in_array($role, ['superadmin', 'admin', 'operatore'], true)) {
        json_error('Parametri non validi (uid, role).', 422);
    }

    // Protezione: non lasciare la piattaforma senza superadmin.
    if ($role !== 'superadmin') {
        $stmt = $pdo->prepare(
            'SELECT COUNT(*) FROM user_profiles
             WHERE role = \'superadmin\' AND uid <> :uid'
        );
        $stmt->execute([':uid' => $targetUid]);
        if ((int)$stmt->fetchColumn() === 0) {
            json_error('Deve restare almeno un superadmin.', 422);
        }
    }

    $pdo->prepare('UPDATE user_profiles SET role = :role WHERE uid = :uid')
        ->execute([':role' => $role, ':uid' => $targetUid]);
    json_ok(['ok' => true]);
}

json_error('Metodo non consentito.', 405);
