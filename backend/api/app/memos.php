<?php
declare(strict_types=1);

// Lavagne memo condivise del team:
//   GET    ?scope=<id>            → elenco (con payload completo)
//   GET    ?scope=<id>&id=<memo>  → singola lavagna
//   POST   {scope, id?, title, createdBy, createdByName, payload}
//   DELETE ?scope=<id>&id=<memo>

require_once __DIR__ . '/helpers.php';

header('Content-Type: application/json; charset=utf-8');

require_auth();
$pdo = db();
$method = $_SERVER['REQUEST_METHOD'];

function memo_row_to_json(array $row): array
{
    return [
        'id' => (string)$row['id'],
        'title' => (string)$row['title'],
        'createdBy' => (string)$row['created_by'],
        'createdByName' => (string)$row['created_by_name'],
        'createdAt' => app_iso((string)$row['created_at']),
        'updatedAt' => app_iso((string)$row['updated_at']),
        'payload' => app_json_decode($row['payload'] ?? null, new stdClass()),
    ];
}

if ($method === 'GET') {
    $scope = trim((string)($_GET['scope'] ?? ''));
    if ($scope === '') {
        json_error('Parametro scope mancante.', 422);
    }
    $id = trim((string)($_GET['id'] ?? ''));
    if ($id !== '') {
        $stmt = $pdo->prepare(
            'SELECT * FROM memos WHERE scope_id = :scope AND id = :id'
        );
        $stmt->execute([':scope' => $scope, ':id' => $id]);
        $row = $stmt->fetch(PDO::FETCH_ASSOC);
        json_ok(['memo' => $row ? memo_row_to_json($row) : null]);
    }
    $stmt = $pdo->prepare(
        'SELECT * FROM memos WHERE scope_id = :scope ORDER BY updated_at DESC'
    );
    $stmt->execute([':scope' => $scope]);
    json_ok([
        'memos' => array_map(
            'memo_row_to_json',
            $stmt->fetchAll(PDO::FETCH_ASSOC) ?: []
        ),
    ]);
}

if ($method === 'POST') {
    $payload = request_json();
    $scope = trim((string)($payload['scope'] ?? ''));
    if ($scope === '') {
        json_error('Parametro scope mancante.', 422);
    }
    $id = trim((string)($payload['id'] ?? ''));
    if ($id === '') {
        $id = 'memo-' . date('YmdHis') . '-' . bin2hex(random_bytes(4));
    }
    $pdo->prepare(
        'INSERT INTO memos (id, scope_id, title, created_by, created_by_name, payload)
         VALUES (:id, :scope, :title, :by, :by_name, :payload)
         ON DUPLICATE KEY UPDATE
           title = VALUES(title), payload = VALUES(payload)'
    )->execute([
        ':id' => $id,
        ':scope' => $scope,
        ':title' => trim((string)($payload['title'] ?? '')),
        ':by' => trim((string)($payload['createdBy'] ?? '')),
        ':by_name' => trim((string)($payload['createdByName'] ?? '')),
        ':payload' => json_encode(
            $payload['payload'] ?? new stdClass(),
            JSON_UNESCAPED_UNICODE
        ) ?: '{}',
    ]);
    json_ok(['ok' => true, 'id' => $id]);
}

if ($method === 'DELETE') {
    $scope = trim((string)($_GET['scope'] ?? ''));
    $id = trim((string)($_GET['id'] ?? ''));
    if ($scope === '' || $id === '') {
        json_error('Parametri scope e id obbligatori.', 422);
    }
    $pdo->prepare('DELETE FROM memos WHERE scope_id = :scope AND id = :id')
        ->execute([':scope' => $scope, ':id' => $id]);
    json_ok(['ok' => true]);
}

json_error('Metodo non consentito.', 405);
