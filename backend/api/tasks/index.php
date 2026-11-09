<?php
require_once __DIR__ . '/../bootstrap.php';

$userId = require_auth();
$scope = scope_filter_sql('user_id', scoped_user_ids($userId));
$method = http_method();
$id     = $_GET['id']     ?? null;
$action = $_GET['action'] ?? null;

if ($method === 'DELETE' && $action === 'delete_backlog') {
    db()->prepare("DELETE FROM work_tasks WHERE {$scope['sql']} AND status='backlog'")->execute($scope['params']);
    json_ok(['ok'=>true]);
}

if ($method === 'GET') {
    $st = db()->prepare('SELECT * FROM work_tasks WHERE ' . $scope['sql'] . ' ORDER BY deadline DESC');
    $st->execute($scope['params']);
    json_ok($st->fetchAll());
}

if ($method === 'POST') {
    $b  = request_body();
    $id = str_val($b['id'] ?? uuid4());
    db()->prepare(
        'INSERT INTO work_tasks (id,user_id,company_id,project_id,phase_id,assignee_id,name,
         estimated_hours,logged_hours,start_date,deadline,status,billable,description)
         VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?)'
    )->execute([
        $id, $userId,
        str_val($b['companyId'] ?? ''),
        str_val($b['projectId'] ?? ''),
        str_val($b['phaseId'] ?? ''),
        str_val($b['assigneeId'] ?? ''),
        str_val($b['name'] ?? ''),
        (float)($b['estimatedHours'] ?? 2),
        (float)($b['loggedHours'] ?? 0),
        to_date($b['startDate'] ?? null) ?? date('Y-m-d'),
        to_date($b['deadline'] ?? null) ?? date('Y-m-d', strtotime('+7 days')),
        str_val($b['status'] ?? 'planned'),
        bool_val($b['billable'] ?? true) ? 1 : 0,
        str_val($b['description'] ?? ''),
    ]);
    json_ok(['id' => $id], 201);
}

if ($method === 'PUT' || $method === 'PATCH') {
    if (!$id) json_error('id mancante');
    $b   = request_body();
    $map = [
        'name'=>'name','status'=>'status','assigneeId'=>'assignee_id',
        'estimatedHours'=>'estimated_hours','loggedHours'=>'logged_hours',
        'startDate'=>'start_date','deadline'=>'deadline',
        'billable'=>'billable','description'=>'description',
        'phaseId'=>'phase_id','projectId'=>'project_id',
    ];
    $dateFields = ['start_date','deadline'];
    $sets = []; $vals = [];
    foreach ($b as $k => $v) {
        if (!isset($map[$k])) continue;
        $col = $map[$k];
        $sets[] = "$col = ?";
        if (in_array($col, $dateFields)) $v = to_date($v);
        if ($col === 'billable') $v = $v ? 1 : 0;
        $vals[] = $v;
    }
    if (empty($sets)) json_error('Nessun campo');
    $vals[] = $id;
    $vals = array_merge($vals, $scope['params']);
    db()->prepare('UPDATE work_tasks SET ' . implode(',', $sets) . ' WHERE id=? AND ' . $scope['sql'])
       ->execute($vals);
    json_ok(['ok' => true]);
}

if ($method === 'DELETE') {
    if (!$id) json_error('id mancante');
    db()->prepare('DELETE FROM work_tasks WHERE id=? AND ' . $scope['sql'])
       ->execute(array_merge([$id], $scope['params']));
    json_ok(['ok' => true]);
}

json_error('Metodo non consentito', 405);
