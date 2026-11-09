<?php
require_once __DIR__ . '/../bootstrap.php';

$userId = require_auth();
$scope = scope_filter_sql('user_id', scoped_user_ids($userId));
$method = http_method();
$action = $_GET['action'] ?? null;
$id     = $_GET['id']     ?? null;
$taskId = $_GET['task_id']?? null;

if ($method === 'PUT') {
    if (!$id) json_error('id mancante');
    $b = request_body();
    db()->prepare(
        'INSERT INTO timeline_slots (id,user_id,task_id,slot_date,planned_hours,start_hour)
         VALUES (?,?,?,?,?,?)
         ON DUPLICATE KEY UPDATE slot_date=VALUES(slot_date),planned_hours=VALUES(planned_hours),start_hour=VALUES(start_hour)'
    )->execute([
        $id,$userId,
        str_val($b['taskId']??''),
        to_date($b['slotDate']??null)??date('Y-m-d'),
        (float)($b['plannedHours']??0),
        (float)($b['startHour']??8),
    ]);
    json_ok(['ok'=>true]);
}

if ($method === 'DELETE') {
    if ($taskId) {
        db()->prepare('DELETE FROM timeline_slots WHERE ' . $scope['sql'] . ' AND task_id=?')
           ->execute(array_merge($scope['params'], [$taskId]));
    } elseif ($id) {
        db()->prepare('DELETE FROM timeline_slots WHERE id=? AND ' . $scope['sql'])
           ->execute(array_merge([$id], $scope['params']));
    } else {
        json_error('id o task_id richiesto');
    }
    json_ok(['ok'=>true]);
}

if ($method === 'POST') {
    $b = request_body();
    $slots = $b['slots'] ?? [];
    $db = db();
    $db->beginTransaction();
    try {
        if ($action === 'replace_for_task') {
            $tId = str_val($b['taskId']??'');
            $db->prepare('DELETE FROM timeline_slots WHERE ' . $scope['sql'] . ' AND task_id=?')
               ->execute(array_merge($scope['params'], [$tId]));
        } elseif ($action === 'replace_all') {
            $db->prepare('DELETE FROM timeline_slots WHERE ' . $scope['sql'])->execute($scope['params']);
        }
        foreach ($slots as $s) {
            $db->prepare(
                'INSERT INTO timeline_slots (id,user_id,task_id,slot_date,planned_hours,start_hour)
                 VALUES (?,?,?,?,?,?)
                 ON DUPLICATE KEY UPDATE slot_date=VALUES(slot_date),planned_hours=VALUES(planned_hours),start_hour=VALUES(start_hour)'
            )->execute([
                str_val($s['id']??uuid4()),$userId,str_val($s['taskId']??''),
                to_date($s['slotDate']??null)??date('Y-m-d'),
                (float)($s['plannedHours']??0),(float)($s['startHour']??8),
            ]);
        }
        $db->commit();
        json_ok(['ok'=>true]);
    } catch (\Throwable $e) {
        $db->rollBack();
        json_error($e->getMessage(),500);
    }
}

json_error('Metodo non consentito',405);
