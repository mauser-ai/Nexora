<?php
require_once __DIR__ . '/../bootstrap.php';

$userId = require_auth();
$scope = scope_filter_sql('user_id', scoped_user_ids($userId));
$method = http_method();
$id     = $_GET['id']     ?? null;
$action = $_GET['action'] ?? null;

// ── Accetta preventivo ────────────────────────────────────────────────────────
if ($method === 'POST' && $action === 'accept') {
    if (!$id) json_error('id mancante');
    $b = request_body();
    $opportunityId = $b['opportunityId'] ?? null;
    $db = db();
    $db->beginTransaction();
    try {
        $db->prepare("UPDATE preventivi SET status='accepted', accepted_at=NOW() WHERE id=? AND {$scope['sql']}")
           ->execute(array_merge([$id], $scope['params']));
        if ($opportunityId) {
            $db->prepare("UPDATE opportunities SET status='accettata' WHERE id=? AND {$scope['sql']}")
               ->execute(array_merge([$opportunityId], $scope['params']));
        }
        $db->commit();
        json_ok(['ok' => true]);
    } catch (\Throwable $e) {
        $db->rollBack();
        json_error($e->getMessage(), 500);
    }
}

if ($method === 'GET') {
    $st = db()->prepare('SELECT * FROM preventivi WHERE ' . $scope['sql'] . ' ORDER BY created_at DESC');
    $st->execute($scope['params']);
    json_ok($st->fetchAll());
}

if ($method === 'POST') {
    $b  = request_body();
    $id = str_val($b['id'] ?? uuid4());
    db()->prepare(
        'INSERT INTO preventivi (id,user_id,opportunity_id,company_id,status,`lines`,istruttoria_fee,success_fee_percent,notes,sent_at)
         VALUES (?,?,?,?,?,?,?,?,?,?)'
    )->execute([
        $id, $userId,
        $b['opportunityId'] ?? null,
        $b['companyId'] ?? null,
        str_val($b['status'] ?? 'draft'),
        json_encode($b['lines'] ?? []),
        (float)($b['istruttoriaFee'] ?? 0),
        float_val($b['successFeePercent'] ?? null),
        str_val($b['notes'] ?? ''),
        to_dt($b['sentAt'] ?? null),
    ]);
    json_ok(['id' => $id], 201);
}

if ($method === 'PUT' || $method === 'PATCH') {
    if (!$id) json_error('id mancante');
    $b   = request_body();
    $map = ['status'=>'status','notes'=>'notes','lines'=>'`lines`',
            'istruttoriaFee'=>'istruttoria_fee','successFeePercent'=>'success_fee_percent',
            'sentAt'=>'sent_at','linkedProjectId'=>'linked_project_id'];
    $sets = []; $vals = [];
    foreach ($b as $k => $v) {
        if (!isset($map[$k])) continue;
        $col = $map[$k];
        $sets[] = "$col = ?";
        if ($col === 'lines') $v = json_encode($v);
        $vals[] = $v;
    }
    if (empty($sets)) json_error('Nessun campo');
    $vals[] = $id;
    $vals = array_merge($vals, $scope['params']);
    db()->prepare('UPDATE preventivi SET ' . implode(',', $sets) . ' WHERE id=? AND ' . $scope['sql'])
       ->execute($vals);
    json_ok(['ok' => true]);
}

if ($method === 'DELETE') {
    if (!$id) json_error('id mancante');
    db()->prepare('DELETE FROM preventivi WHERE id=? AND ' . $scope['sql'])
       ->execute(array_merge([$id], $scope['params']));
    json_ok(['ok' => true]);
}

json_error('Metodo non consentito', 405);
