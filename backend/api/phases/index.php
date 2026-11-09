<?php
require_once __DIR__ . '/../bootstrap.php';

$userId = require_auth();
$scope = scope_filter_sql('user_id', scoped_user_ids($userId));
$method = http_method();
$id     = $_GET['id'] ?? null;

if ($method === 'GET') {
    $projectId = $_GET['project_id'] ?? null;
    if ($projectId) {
        $st = db()->prepare('SELECT * FROM project_phases WHERE ' . $scope['sql'] . ' AND project_id=? ORDER BY phase_order');
        $st->execute(array_merge($scope['params'], [$projectId]));
    } else {
        $st = db()->prepare('SELECT * FROM project_phases WHERE ' . $scope['sql'] . ' ORDER BY project_id, phase_order');
        $st->execute($scope['params']);
    }
    json_ok($st->fetchAll());
}

if ($method === 'POST') {
    $b  = request_body();
    $id = str_val($b['id'] ?? uuid4());
    db()->prepare(
        'INSERT INTO project_phases (id,user_id,project_id,name,phase_order,status,assigned_user_id,start_date,deadline,notes,is_custom)
         VALUES (?,?,?,?,?,?,?,?,?,?,?)'
    )->execute([
        $id, $userId,
        str_val($b['projectId'] ?? ''),
        str_val($b['name'] ?? ''),
        (int)($b['order'] ?? 0),
        str_val($b['status'] ?? 'notStarted'),
        $b['assignedUserId'] ?? null,
        to_date($b['startDate'] ?? null),
        to_date($b['deadline'] ?? null),
        str_val($b['notes'] ?? ''),
        bool_val($b['isCustom'] ?? false) ? 1 : 0,
    ]);
    json_ok(['id' => $id], 201);
}

if ($method === 'PUT' || $method === 'PATCH') {
    if (!$id) json_error('id mancante');
    $b   = request_body();
    $map = [
        'name'=>'name','status'=>'status','assignedUserId'=>'assigned_user_id',
        'startDate'=>'start_date','deadline'=>'deadline','notes'=>'notes',
        'order'=>'phase_order',
    ];
    $dateFields = ['start_date','deadline'];
    $sets = []; $vals = [];
    foreach ($b as $k => $v) {
        if (!isset($map[$k])) continue;
        $col = $map[$k];
        $sets[] = "$col = ?";
        if (in_array($col, $dateFields)) $v = to_date($v);
        $vals[] = $v;
    }
    if (empty($sets)) json_error('Nessun campo');
    $vals[] = $id;
    $vals = array_merge($vals, $scope['params']);
    db()->prepare('UPDATE project_phases SET ' . implode(',', $sets) . ' WHERE id=? AND ' . $scope['sql'])
       ->execute($vals);
    json_ok(['ok' => true]);
}

if ($method === 'DELETE') {
    if (!$id) json_error('id mancante');
    db()->prepare('DELETE FROM project_phases WHERE id=? AND ' . $scope['sql'])
       ->execute(array_merge([$id], $scope['params']));
    json_ok(['ok' => true]);
}

json_error('Metodo non consentito', 405);
