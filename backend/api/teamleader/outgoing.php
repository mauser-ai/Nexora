<?php
declare(strict_types=1);

require_once __DIR__ . '/../bootstrap.php';
require_once __DIR__ . '/mapper.php';
require_once __DIR__ . '/reverse_store.php';
header('Cache-Control: no-store');
ini_set('display_errors','0');
set_exception_handler(static function(Throwable $e): void {
    if (isset($GLOBALS['tlr_pdo']) && $GLOBALS['tlr_pdo']->inTransaction()) $GLOBALS['tlr_pdo']->rollBack();
    error_log('Teamleader outgoing: '.$e->getMessage());
    json_error($e instanceof InvalidArgumentException ? $e->getMessage() : 'Coda in uscita non disponibile: verificare installazione e log PHP.', $e instanceof InvalidArgumentException ? 422 : 500);
});
if (($_SERVER['REQUEST_METHOD'] ?? '')!=='POST') json_error('Usare POST firmato.',405);
$config = is_file(__DIR__.'/config.local.php') ? require __DIR__.'/config.local.php' : [];
$key = (string)($config['key'] ?? '');
if (strlen($key)<32) json_error('Collegamento non configurato.',503);
$raw = file_get_contents('php://input');
if (strlen($raw)>1048576) json_error('Payload troppo grande.',413);
$ts = $_SERVER['HTTP_X_NEXORA_TIMESTAMP'] ?? '';
$sig = $_SERVER['HTTP_X_NEXORA_SIGNATURE'] ?? '';
if (!ctype_digit($ts) || abs(time()-(int)$ts)>300 || !hash_equals(hash_hmac('sha256',$ts.'.'.$raw,$key),$sig)) json_error('Firma non valida o scaduta.',401);
$input = json_decode($raw,true,32,JSON_THROW_ON_ERROR);
if (!is_array($input)) throw new InvalidArgumentException('Richiesta non valida.');
$team = (string)($config['team_id'] ?? '');
if ($team==='') json_error('Team non configurato.',503);
$pdo = db();$GLOBALS['tlr_pdo']=$pdo;
$action = $input['action'] ?? '';
if ($action==='install') {
    // Refuse capture without the inbound origin guard: otherwise source webhooks could echo.
    $incoming = file_get_contents(__DIR__.'/index.php');
    if (strpos($incoming,'SET @nexora_sync_origin')===false || strpos($incoming,'tlr_incoming_local_id')===false) json_error('Caricare prima index.php con protezione anti-loop.',503);
    if (empty($config['reverse_modules'])) json_error('Configurare reverse_modules prima dell installazione.',503);
    json_ok(['ok'=>true,'installed'=>tlr_install($pdo,$config),'historicalRowsExported'=>0]);
}
if ($action==='disable') {
    // Emergency pause: preserve the queue and mappings, but stop database
    // triggers while a live write failure is being diagnosed.
    $team = (string)($config['team_id'] ?? '');
    if ($team==='') json_error('Team non configurato.',503);
    $prefix = 'tlr_' . substr(hash('sha256', $team), 0, 24) . '_';
    $st = $pdo->prepare('SELECT TRIGGER_NAME FROM information_schema.TRIGGERS WHERE TRIGGER_SCHEMA=DATABASE() AND TRIGGER_NAME LIKE ?');
    $st->execute([$prefix . '%']);
    $removed = [];
    foreach ($st->fetchAll(PDO::FETCH_COLUMN) as $name) {
        $pdo->exec('DROP TRIGGER ' . tlr_ident((string)$name));
        $removed[] = $name;
    }
    json_ok(['ok'=>true,'paused'=>true,'removedTriggers'=>$removed]);
}
if ($action==='health') {
    $installed=(int)$pdo->query("SELECT COUNT(*) FROM information_schema.TABLES WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME IN ('teamleader_reverse_outbox','teamleader_object_links')")->fetchColumn()===2;
    $counts=[];
    if ($installed) {
        $st=$pdo->prepare('SELECT module,status,COUNT(*) AS total FROM teamleader_reverse_outbox WHERE team_id=? GROUP BY module,status');
        $st->execute([$team]);$counts=$st->fetchAll();
    }
    json_ok(['ok'=>true,'enabled'=>(bool)($config['reverse_enabled'] ?? false),'installed'=>$installed,'modules'=>$config['reverse_modules'] ?? [],'queue'=>$counts]);
}
if ($action==='retry') {
    $id = (int)($input['id'] ?? 0);
    if ($id <= 0) json_error('ID coda non valido.', 422);
    $st = $pdo->prepare("UPDATE `teamleader_reverse_outbox`
        SET `status`='pending', `lease`=NULL, `claim_deadline`=NULL,
            `result_json`=NULL, `error_code`=NULL
        WHERE `id`=? AND `team_id`=? AND `status` IN ('conflict','blocked','uncertain')");
    $st->execute([$id, $team]);
    json_ok(['ok'=>true,'requeued'=>$st->rowCount() === 1,'id'=>$id]);
}
if (!($config['reverse_enabled'] ?? false)) json_ok(['ok'=>true,'enabled'=>false,'event'=>null]);
if ($action==='claim') {
    json_ok(['ok'=>true,'event'=>tlr_claim($pdo,$team),'operator_map'=>$config['operator_map'] ?? [],'time_zone'=>$config['time_zone'] ?? 'Europe/Rome']);
}
if ($action==='finish') {
    if (!is_array($input['result'] ?? null)) throw new InvalidArgumentException('Risultato non valido.');
    json_ok(['ok'=>true,'result'=>tlr_finish($pdo,$team,(int)($input['id'] ?? 0),(string)($input['lease'] ?? ''),$input['result'])]);
}
if ($action==='lookup') {
    $module=(string)($input['module'] ?? '');$id=(string)($input['local_id'] ?? '');
    $table=tls_tables()[$module] ?? null;
    if (!$table || !preg_match('/^[a-zA-Z0-9-]{1,64}$/D',$id)) throw new InvalidArgumentException('Riferimento non valido.');
    $st=$pdo->prepare("SELECT r.user_id FROM `$table` r WHERE r.id=? AND (EXISTS(SELECT 1 FROM users u WHERE u.id=r.user_id AND u.team_id=?) OR EXISTS(SELECT 1 FROM team_members m WHERE m.user_id=r.user_id AND m.team_id=? AND m.status='active') OR EXISTS(SELECT 1 FROM teams t WHERE t.id=? AND t.owner_id=r.user_id))");
    $st->execute([$id,$team,$team,$team]);
    if ($st->fetchColumn()===false) throw new InvalidArgumentException('Dipendenza locale mancante o di un altro team.');
    json_ok(['ok'=>true,'link'=>tlr_lookup($pdo,$team,$module,$id)]);
}
json_error('Azione non supportata.',400);
