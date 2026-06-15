<?php
declare(strict_types=1);

// Credenziali integrazioni dell'utente:
//   GET                → mappa {integration_key: payload}
//   PUT  {key, data}   → upsert payload
//   DELETE ?key=       → rimuove l'integrazione

require_once __DIR__ . '/helpers.php';

header('Content-Type: application/json; charset=utf-8');

$uid = require_auth();
$pdo = db();

$method = $_SERVER['REQUEST_METHOD'];

if ($method === 'GET') {
    $stmt = $pdo->prepare(
        'SELECT integration_key, payload FROM user_integrations WHERE user_id = :uid'
    );
    $stmt->execute([':uid' => $uid]);
    $map = [];
    foreach ($stmt->fetchAll(PDO::FETCH_ASSOC) ?: [] as $row) {
        $map[(string)$row['integration_key']] =
            app_json_decode($row['payload'] ?? null, new stdClass());
    }
    json_ok(['integrations' => $map]);
}

if ($method === 'PUT' || $method === 'POST') {
    $payload = request_json();
    $key = trim((string)($payload['key'] ?? ''));
    if ($key === '' || strlen($key) > 60) {
        json_error('Chiave integrazione non valida.', 422);
    }
    $data = $payload['data'] ?? [];
    $pdo->prepare(
        'INSERT INTO user_integrations (user_id, integration_key, payload)
         VALUES (:uid, :k, :payload)
         ON DUPLICATE KEY UPDATE payload = VALUES(payload)'
    )->execute([
        ':uid' => $uid,
        ':k' => $key,
        ':payload' => json_encode($data, JSON_UNESCAPED_UNICODE) ?: '{}',
    ]);
    json_ok(['ok' => true]);
}

if ($method === 'DELETE') {
    $key = trim((string)($_GET['key'] ?? ''));
    if ($key === '') {
        json_error('Parametro key mancante.', 422);
    }
    $pdo->prepare(
        'DELETE FROM user_integrations WHERE user_id = :uid AND integration_key = :k'
    )->execute([':uid' => $uid, ':k' => $key]);
    json_ok(['ok' => true]);
}

json_error('Metodo non consentito.', 405);
