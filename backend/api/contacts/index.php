<?php
require_once __DIR__ . '/../bootstrap.php';

function contacts_has_custom_fields_column(): bool {
    static $hasColumn = null;
    if ($hasColumn !== null) return $hasColumn;
    try {
        $st = db()->query("SHOW COLUMNS FROM company_contacts LIKE 'custom_fields'");
        $hasColumn = (bool)$st->fetch();
    } catch (Throwable $e) {
        $hasColumn = false;
    }
    return $hasColumn;
}

$userId = require_auth();
$scope = scope_filter_sql('user_id', scoped_user_ids($userId));
$method = http_method();
$id     = $_GET['id'] ?? null;

if ($method === 'GET') {
    $st = db()->prepare('SELECT * FROM company_contacts WHERE ' . $scope['sql'] . ' ORDER BY name');
    $st->execute($scope['params']);
    json_ok($st->fetchAll());
}

if ($method === 'POST') {
    $b  = request_body();
    $id = str_val($b['id'] ?? uuid4());
    $params = [
        $id, $userId,
        $b['companyId'] ?? null,
        str_val($b['name'] ?? ''),
        str_val($b['email'] ?? ''),
        str_val($b['phone'] ?? ''),
        str_val($b['role'] ?? ''),
    ];
    $sql = 'INSERT INTO company_contacts (id,user_id,company_id,name,email,phone,role';
    $placeholders = '?,?,?,?,?,?,?';
    if (contacts_has_custom_fields_column()) {
        $sql .= ',custom_fields';
        $placeholders .= ',?';
        $params[] = json_encode((object)($b['customFields'] ?? []));
    }
    $sql .= ') VALUES (' . $placeholders . ')';
    db()->prepare($sql)->execute($params);
    json_ok(['id' => $id], 201);
}

if ($method === 'PUT' || $method === 'PATCH') {
    if (!$id) json_error('id mancante');
    $b   = request_body();
    $map = ['name'=>'name','email'=>'email','phone'=>'phone','role'=>'role','companyId'=>'company_id','customFields'=>'custom_fields'];
    $sets = []; $vals = [];
    foreach ($b as $k => $v) {
        if (!isset($map[$k])) continue;
        if ($map[$k] === 'custom_fields' && !contacts_has_custom_fields_column()) continue;
        $sets[] = $map[$k] . ' = ?';
        if ($map[$k] === 'custom_fields') {
            $v = json_encode((object)($v ?? []));
        }
        $vals[] = $v;
    }
    if (empty($sets)) json_error('Nessun campo');
    $vals[] = $id;
    $vals = array_merge($vals, $scope['params']);
    db()->prepare('UPDATE company_contacts SET ' . implode(',', $sets) . ' WHERE id=? AND ' . $scope['sql'])
       ->execute($vals);
    json_ok(['ok' => true]);
}

if ($method === 'DELETE') {
    if (!$id) json_error('id mancante');
    db()->prepare('DELETE FROM company_contacts WHERE id=? AND ' . $scope['sql'])
       ->execute(array_merge([$id], $scope['params']));
    json_ok(['ok' => true]);
}

json_error('Metodo non consentito', 405);
