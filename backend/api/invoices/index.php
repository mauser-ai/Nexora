<?php
require_once __DIR__ . '/../bootstrap.php';

$userId = require_auth();
$scope = scope_filter_sql('user_id', scoped_user_ids($userId));
$method = http_method();
$id     = $_GET['id'] ?? null;

if ($method === 'GET') {
    $st = db()->prepare('SELECT * FROM invoice_drafts WHERE ' . $scope['sql'] . ' ORDER BY created_at DESC');
    $st->execute($scope['params']);
    json_ok($st->fetchAll());
}

if ($method === 'POST') {
    $b  = request_body();
    $id = str_val($b['id'] ?? uuid4());
    db()->prepare(
        'INSERT INTO invoice_drafts (
            id,user_id,company_id,number,amount,status,project_id,`lines`,
            is_success_fee,grant_amount,notes,sent_at,
            payment_status,paid_amount,balance_due,paid_at,pos_origin_payment_id
         )
         VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
         ON DUPLICATE KEY UPDATE
           company_id=VALUES(company_id),number=VALUES(number),amount=VALUES(amount),
           status=VALUES(status),project_id=VALUES(project_id),`lines`=VALUES(`lines`),
           is_success_fee=VALUES(is_success_fee),grant_amount=VALUES(grant_amount),
           notes=VALUES(notes),sent_at=VALUES(sent_at),
           payment_status=VALUES(payment_status),paid_amount=VALUES(paid_amount),
           balance_due=VALUES(balance_due),paid_at=VALUES(paid_at),
           pos_origin_payment_id=VALUES(pos_origin_payment_id)'
    )->execute([
        $id, $userId,
        str_val($b['companyId'] ?? ''),
        str_val($b['number'] ?? ''),
        (float)($b['amount'] ?? 0),
        str_val($b['status'] ?? 'draft'),
        $b['projectId'] ?? null,
        json_encode($b['lines'] ?? []),
        bool_val($b['isSuccessFee'] ?? false) ? 1 : 0,
        float_val($b['grantAmount'] ?? null),
        str_val($b['notes'] ?? ''),
        to_dt($b['sentAt'] ?? null),
        str_val($b['paymentStatus'] ?? 'unpaid'),
        float_val($b['paidAmount'] ?? 0),
        array_key_exists('balanceDue', $b) ? float_val($b['balanceDue']) : (float)($b['amount'] ?? 0),
        to_dt($b['paidAt'] ?? null),
        str_val($b['posOriginPaymentId'] ?? '') ?: null,
    ]);
    json_ok(['id' => $id], 201);
}

if ($method === 'PUT' || $method === 'PATCH') {
    if (!$id) json_error('id mancante');
    $b   = request_body();
    $map = [
        'status'=>'status',
        'number'=>'number',
        'amount'=>'amount',
        'notes'=>'notes',
        'sentAt'=>'sent_at',
        'lines'=>'`lines`',
        'paymentStatus'=>'payment_status',
        'paidAmount'=>'paid_amount',
        'balanceDue'=>'balance_due',
        'paidAt'=>'paid_at',
        'posOriginPaymentId'=>'pos_origin_payment_id',
    ];
    $sets = []; $vals = [];
    foreach ($b as $k => $v) {
        if (!isset($map[$k])) continue;
        $col = $map[$k];
        $sets[] = "$col = ?";
        if ($col === 'lines') $v = json_encode($v);
        if ($col === 'sent_at') $v = to_dt($v);
        if ($col === 'paid_at') $v = to_dt($v);
        $vals[] = $v;
    }
    if (empty($sets)) json_error('Nessun campo');
    $vals[] = $id;
    $vals = array_merge($vals, $scope['params']);
    db()->prepare('UPDATE invoice_drafts SET ' . implode(',', $sets) . ' WHERE id=? AND ' . $scope['sql'])
       ->execute($vals);
    json_ok(['ok' => true]);
}

if ($method === 'DELETE') {
    if (!$id) json_error('id mancante');
    db()->prepare('DELETE FROM invoice_drafts WHERE id=? AND ' . $scope['sql'])
       ->execute(array_merge([$id], $scope['params']));
    json_ok(['ok' => true]);
}

json_error('Metodo non consentito', 405);
