<?php
// GET    /api/tasks/comments.php?task_id=...  → lista commenti
// POST   /api/tasks/comments.php              → crea commento
// DELETE /api/tasks/comments.php?id=...       → elimina commento

require_once __DIR__ . '/../bootstrap.php';

$userId = require_auth();
$scope = scope_filter_sql('user_id', scoped_user_ids($userId));
$method = http_method();
$id     = $_GET['id']      ?? null;
$taskId = $_GET['task_id'] ?? null;

if ($method === 'GET') {
    if (!$taskId) json_error('task_id mancante');
    $st = db()->prepare('SELECT * FROM task_comments WHERE ' . $scope['sql'] . ' AND task_id=? ORDER BY created_at ASC');
    $st->execute(array_merge($scope['params'], [$taskId]));
    json_ok($st->fetchAll());
}

if ($method === 'POST') {
    $b      = request_body();
    $id     = str_val($b['id'] ?? uuid4());
    $taskId = str_val($b['taskId'] ?? '');
    if (empty($taskId)) json_error('taskId mancante');
    db()->prepare(
        'INSERT INTO task_comments (id,user_id,task_id,author_id,author_name,body)
         VALUES (?,?,?,?,?,?)'
    )->execute([
        $id, $userId, $taskId,
        str_val($b['authorId'] ?? $userId),
        str_val($b['authorName'] ?? ''),
        str_val($b['body'] ?? ''),
    ]);
    json_ok(['id' => $id], 201);
}

if ($method === 'DELETE') {
    if (!$id) json_error('id mancante');
    db()->prepare('DELETE FROM task_comments WHERE id=? AND ' . $scope['sql'])
       ->execute(array_merge([$id], $scope['params']));
    json_ok(['ok' => true]);
}

json_error('Metodo non consentito', 405);
