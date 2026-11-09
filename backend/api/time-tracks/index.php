<?php
require_once __DIR__ . '/../bootstrap.php';

$userId = require_auth();
$scope = scope_filter_sql('user_id', scoped_user_ids($userId));
$method = http_method();
$id     = $_GET['id'] ?? null;

if ($method === 'GET') {
    $st = db()->prepare('SELECT * FROM time_tracks WHERE ' . $scope['sql'] . ' ORDER BY start_at DESC');
    $st->execute($scope['params']);
    json_ok($st->fetchAll());
}

if ($method === 'POST') {
    $b  = request_body();
    $id = str_val($b['id'] ?? uuid4());
    db()->prepare(
        'INSERT INTO time_tracks (id,user_id,task_id,name,company_id,project_id,start_at,end_at,
         tracker_user_id,description,billable,tipo,hourly_rate)
         VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)'
    )->execute([
        $id, $userId,
        str_val($b['taskId'] ?? ''),
        str_val($b['name'] ?? ''),
        str_val($b['companyId'] ?? ''),
        str_val($b['projectId'] ?? ''),
        to_dt($b['startAt'] ?? null) ?? date('Y-m-d H:i:s'),
        to_dt($b['endAt'] ?? null) ?? date('Y-m-d H:i:s'),
        str_val($b['userId'] ?? $userId),
        str_val($b['description'] ?? ''),
        bool_val($b['billable'] ?? true) ? 1 : 0,
        str_val($b['tipo'] ?? ''),
        float_val($b['hourlyRate'] ?? null),
    ]);
    json_ok(['id' => $id], 201);
}

if ($method === 'PUT' || $method === 'PATCH') {
    if (!$id) json_error('id mancante');
    $b   = request_body();
    $map = ['name'=>'name','description'=>'description','billable'=>'billable',
            'tipo'=>'tipo','hourlyRate'=>'hourly_rate',
            'startAt'=>'start_at','endAt'=>'end_at'];
    $dtFields = ['start_at','end_at'];
    $sets = []; $vals = [];
    foreach ($b as $k => $v) {
        if (!isset($map[$k])) continue;
        $col = $map[$k];
        $sets[] = "$col = ?";
        if (in_array($col, $dtFields)) $v = to_dt($v);
        if ($col === 'billable') $v = $v ? 1 : 0;
        $vals[] = $v;
    }
    if (empty($sets)) json_error('Nessun campo');
    $vals[] = $id;
    $vals = array_merge($vals, $scope['params']);
    db()->prepare('UPDATE time_tracks SET ' . implode(',', $sets) . ' WHERE id=? AND ' . $scope['sql'])
       ->execute($vals);
    json_ok(['ok' => true]);
}

if ($method === 'DELETE') {
    if (!$id) json_error('id mancante');
    db()->prepare('DELETE FROM time_tracks WHERE id=? AND ' . $scope['sql'])
       ->execute(array_merge([$id], $scope['params']));
    json_ok(['ok' => true]);
}

json_error('Metodo non consentito', 405);
