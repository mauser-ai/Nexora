<?php
declare(strict_types=1);

require_once __DIR__ . '/../bootstrap.php';
require_once __DIR__ . '/mapper.php';
require_once __DIR__ . '/reverse_store.php';
ini_set('display_errors', '0');
header('Cache-Control: no-store');

set_exception_handler(function (Throwable $e): void {
    if (isset($GLOBALS['tls_pdo']) && $GLOBALS['tls_pdo']->inTransaction()) $GLOBALS['tls_pdo']->rollBack();
    error_log('Teamleader sync: ' . $e->getMessage());
    $details = [];
    if (!empty($GLOBALS['tls_authenticated'])) {
        if ($e instanceof PDOException) {
            $details['sqlState'] = $e->errorInfo[0] ?? (string)$e->getCode();
            $details['dbCode'] = $e->errorInfo[1] ?? null;
            if (preg_match("/Unknown column '([a-zA-Z0-9_.]+)'/", $e->getMessage(), $match)) $details['missingColumn'] = $match[1];
        }
        if (preg_match('/^(Dipendenza ancora da sincronizzare: [a-z_]+|Campo obbligatorio non mappato: [a-z_.]+|Schema non aggiornato: [a-z_.]+|Team target non trovato\.)$/D', $e->getMessage())) $details['reason'] = $e->getMessage();
        $details['phase'] = $GLOBALS['tls_phase'] ?? 'initialization';
    }
    json_ok(['error'=>$e instanceof InvalidArgumentException ? $e->getMessage() : 'Sincronizzazione non applicata.','diagnostic'=>$details], $e instanceof InvalidArgumentException ? 422 : 500);
});

if (($_SERVER['REQUEST_METHOD'] ?? '') !== 'POST') json_error('Usare POST autenticato.', 405);
$config = is_file(__DIR__ . '/config.local.php') ? require __DIR__ . '/config.local.php' : [];
$key = (string)($config['key'] ?? '');
if (strlen($key) < 32) json_error('Collegamento Teamleader non configurato.', 503);
$raw = file_get_contents('php://input');
if (strlen($raw) > 2097152) json_error('Payload troppo grande.', 413);
$timestamp = $_SERVER['HTTP_X_NEXORA_TIMESTAMP'] ?? '';
$signature = $_SERVER['HTTP_X_NEXORA_SIGNATURE'] ?? '';
if (!ctype_digit($timestamp) || abs(time() - (int)$timestamp) > 300 || !hash_equals(hash_hmac('sha256', $timestamp . '.' . $raw, $key), $signature)) json_error('Firma non valida o scaduta.', 401);
$GLOBALS['tls_authenticated'] = true;
$event = json_decode($raw, true, 64, JSON_THROW_ON_ERROR);
if (!is_array($event)) throw new InvalidArgumentException('Evento non valido.');
$pdo = db();
$GLOBALS['tls_pdo'] = $pdo;

if (($event['action'] ?? '') === 'install') {
    $pdo->exec('CREATE TABLE IF NOT EXISTS teamleader_sync_events (
        team_id VARCHAR(64) NOT NULL, event_id VARCHAR(64) NOT NULL, body_hash CHAR(64) NOT NULL,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP, PRIMARY KEY(team_id,event_id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4');
    $pdo->exec('CREATE TABLE IF NOT EXISTS teamleader_sync_entities (
        team_id VARCHAR(64) NOT NULL, module VARCHAR(32) NOT NULL, source_id VARCHAR(64) NOT NULL,
        observed_at DOUBLE NOT NULL DEFAULT 0, source_json LONGTEXT NOT NULL,
        deleted TINYINT NOT NULL DEFAULT 0, updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        PRIMARY KEY(team_id,module,source_id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4');
    json_ok(['ok'=>true,'installed'=>true,'apply'=>(bool)($config['apply'] ?? false)]);
}
if (($event['action'] ?? '') === 'health') json_ok(['ok'=>true,'apply'=>(bool)($config['apply'] ?? false)]);
$module = (string)($event['module'] ?? '');
$id = (string)($event['source_id'] ?? '');
$eventId = (string)($event['event_id'] ?? '');
$row = $event['record'] ?? [];
$observed = $event['observed_at'] ?? null;
if (!isset(tls_tables()[$module]) || !preg_match('/^[a-zA-Z0-9-]{1,64}$/D', $id) || !preg_match('/^[a-zA-Z0-9-]{1,64}$/D', $eventId) || !is_array($row) || !is_numeric($observed) || $observed < 0 || $observed > time() + 300) throw new InvalidArgumentException('Identificativi/modulo/evento non validi.');
$allowedModules = $config['modules'] ?? [];
if (in_array('tasks',$allowedModules,true)) $allowedModules[] = 'phases';
if (!in_array($module, $allowedModules, true)) json_error('Modulo sospeso: richiede verifica della mappatura.', 409);
if (!empty($row) && ($row['id'] ?? null) !== $id) throw new InvalidArgumentException('ID record diverso da ID evento.');
$deleted = ($event['action'] ?? '') === 'delete';
if (!$deleted && ($event['action'] ?? '') !== 'upsert') throw new InvalidArgumentException('Azione non supportata.');
$teamId = (string)($config['team_id'] ?? '');
$GLOBALS['tls_phase'] = 'team-context';
$st = $pdo->prepare('SELECT owner_id FROM teams WHERE id=?');
$st->execute([$teamId]);
$owner = (string)$st->fetchColumn();
if ($owner === '') throw new RuntimeException('Team target non trovato.');
$st = $pdo->prepare("SELECT user_id FROM team_members WHERE team_id=? AND status='active' UNION SELECT id FROM users WHERE team_id=?");
$st->execute([$teamId,$teamId]);
$members = array_unique(array_merge([$owner], $st->fetchAll(PDO::FETCH_COLUMN)));
$sourceUser = $row['responsible_user']['id'] ?? $row['assignee']['id'] ?? $row['user']['id'] ?? '';
$user = (string)($config['operator_map'][$sourceUser] ?? $owner);
$fallback = !in_array($user, $members, true);
if ($fallback) $user = $owner;
$data = $deleted ? [] : tls_map($module, $row, (string)($config['time_zone'] ?? 'Europe/Rome'));
$table = tls_tables()[$module];
$sourceId = $id;
$reverseInstalled = (int)$pdo->query("SELECT COUNT(*) FROM information_schema.TABLES WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME IN ('teamleader_reverse_outbox','teamleader_object_links')")->fetchColumn() === 2;
$GLOBALS['tls_phase'] = 'sync-transaction';

$pdo->beginTransaction();
$pdo->exec("SET @nexora_sync_origin = 'teamleader'");
$st = $pdo->prepare('SELECT body_hash FROM teamleader_sync_events WHERE team_id=? AND event_id=?');
$st->execute([$teamId,$eventId]);
$previous = $st->fetchColumn();
$bodyHash = hash('sha256', $raw);
if ($previous !== false) {
    $pdo->rollBack();
    if (!hash_equals($previous, $bodyHash)) json_error('Evento riutilizzato con contenuto diverso.',409);
    json_ok(['ok'=>true,'applied'=>true,'duplicate'=>true]);
}
// A single row lock serializes updates for this source entity.
$pdo->prepare("INSERT IGNORE INTO teamleader_sync_entities(team_id,module,source_id,source_json) VALUES(?,?,?,'{}')")->execute([$teamId,$module,$sourceId]);
$st = $pdo->prepare('SELECT observed_at FROM teamleader_sync_entities WHERE team_id=? AND module=? AND source_id=? FOR UPDATE');
$st->execute([$teamId,$module,$sourceId]);
$lastObserved = (float)$st->fetchColumn();
$stale = (float)$observed < $lastObserved;
if ($reverseInstalled && isset(tlr_tables()[$module])) $id = tlr_incoming_local_id($pdo,$teamId,$module,$sourceId);
$st = $pdo->prepare("SELECT user_id FROM `$table` WHERE id=? FOR UPDATE");
$st->execute([$id]);
$existingOwner = $st->fetchColumn();
if ($existingOwner !== false && !in_array($existingOwner, $members, true)) throw new InvalidArgumentException('Record appartenente a un altro team: invio rifiutato.');
if ($reverseInstalled && !$stale && isset(tlr_tables()[$module]) && tlr_incoming_busy($pdo,$teamId,$module,$id)) {
    $pdo->rollBack();
    json_error('Modifica locale in attesa: webhook conservato per il prossimo tentativo.',409);
}

$preview = !($config['apply'] ?? false) || !empty($event['preview']);
if (!$stale && !$deleted) {
    $GLOBALS['tls_phase'] = 'dependencies';
    $references = ['company_id'=>'companies','project_id'=>'projects','phase_id'=>'project_phases',
        'deal_id'=>'deals','stage_id'=>'deal_stages','task_id'=>'work_tasks','invoice_id'=>'invoice_drafts'];
    if (!empty($data['customer_id'])) {
        $type = $data['customer_type'] ?? $row['customer']['type'] ?? $row['lead']['customer']['type'] ?? '';
        if (!in_array($type,['company','contact'],true)) throw new InvalidArgumentException('Tipo cliente sorgente non valido.');
        $references['customer_id'] = $type === 'company' ? 'companies' : 'crm_contacts';
    }
    if ($reverseInstalled) {
        $byTable = array_flip(tlr_tables());
        foreach ($references as $column=>$refTable) {
            if (!empty($data[$column]) && isset($byTable[$refTable])) $data[$column] = tlr_incoming_local_id($pdo,$teamId,$byTable[$refTable],(string)$data[$column]);
        }
    }
    foreach ($references as $column=>$refTable) {
        if (empty($data[$column])) continue;
        $ref = $pdo->prepare("SELECT user_id FROM `$refTable` WHERE id=?");
        $ref->execute([$data[$column]]);
        $refOwner = $ref->fetchColumn();
        if ($refOwner === false) throw new RuntimeException('Dipendenza ancora da sincronizzare: '.$refTable);
        if (!in_array($refOwner,$members,true)) throw new InvalidArgumentException('Associazione appartenente a un altro team.');
    }
    if (in_array($module,['tasks','timetracking'],true)) {
        $data = tls_inherit_links($data,$row,static function(string $parentTable,string $parentId) use ($pdo,$members,$reverseInstalled,$teamId): array {
            $parentModule = array_flip(tlr_tables())[$parentTable] ?? null;
            if ($reverseInstalled && $parentModule) $parentId = tlr_incoming_local_id($pdo,$teamId,$parentModule,$parentId);
            $ref = $pdo->prepare("SELECT * FROM `$parentTable` WHERE id=?");
            $ref->execute([$parentId]);
            $parent = $ref->fetch();
            if (!$parent) throw new RuntimeException('Dipendenza ancora da sincronizzare: '.$parentTable);
            if (!in_array($parent['user_id'],$members,true)) throw new InvalidArgumentException('Dipendenza appartenente a un altro team.');
            return $parent;
        });
    }
    $columns = [];
    $GLOBALS['tls_phase'] = 'mapping-schema';
    foreach ($pdo->query("SHOW COLUMNS FROM `$table`")->fetchAll() as $column) $columns[$column['Field']] = $column;
    foreach ($data as $column=>$value) {
        if (!isset($columns[$column])) throw new RuntimeException('Schema non aggiornato: '.$table.'.'.$column);
        if ($value === null && $columns[$column]['Null'] === 'NO') {
            if (strpos($columns[$column]['Type'],'date') !== false) unset($data[$column]);
            else $data[$column] = '';
        }
    }
    if ($module === 'tasks' && isset($row['assignee']['id'])) $data['assignee_id'] = $user;
    if ($module === 'deals' && isset($row['responsible_user']['id'])) $data['assigned_to'] = $user;
    if ($module === 'timetracking') $data['tracker_user_id'] = $user;
    if ($existingOwner === false) {
        $defaults = ['id'=>$id,'user_id'=>$user,'notes'=>'','note'=>'','description'=>'','entries'=>'[]','tags'=>'[]',
            'aree_investimento'=>'[]','ricavi_annui'=>'{}','lines'=>'[]','created_at'=>tls_date($row['added_at'] ?? $row['created_at'] ?? null) ?? gmdate('Y-m-d H:i:s')];
        $data += array_intersect_key($defaults, $columns);
        if ($module === 'tasks') {
            $data['start_date'] = ($data['start_date'] ?? null) ?: (tls_calendar_date($row['added_at'] ?? null) ?? gmdate('Y-m-d'));
            $data['deadline'] = ($data['deadline'] ?? null) ?: $data['start_date'];
        }
        foreach ($columns as $c=>$info) {
            if (!array_key_exists($c,$data) && $info['Null']==='NO' && $info['Default']===null && strpos($info['Extra'],'auto_increment')===false) throw new RuntimeException('Campo obbligatorio non mappato: '.$table.'.'.$c);
        }
    }
    if ($existingOwner !== false && $data) {
        $GLOBALS['tls_phase'] = 'update-'.$table;
        $sql = "UPDATE `$table` SET ".implode(',',array_map(static fn($c)=>"`$c`=?",array_keys($data))).' WHERE id=?';
        $pdo->prepare($sql)->execute(array_merge(array_values($data),[$id]));
    } elseif ($existingOwner === false) {
        $GLOBALS['tls_phase'] = 'insert-'.$table;
        $sql = "INSERT INTO `$table` (`".implode('`,`',array_keys($data)).'`) VALUES ('.implode(',',array_fill(0,count($data),'?')).')';
        $pdo->prepare($sql)->execute(array_values($data));
    }
    if ($module === 'contacts') {
        $ref = $pdo->prepare('SELECT user_id FROM company_contacts WHERE id=? FOR UPDATE');
        $ref->execute([$id]);
        $refOwner = $ref->fetchColumn();
        if ($refOwner !== false && !in_array($refOwner,$members,true)) throw new InvalidArgumentException('Contatto collegato a un altro team.');
        $ref = $pdo->prepare('SELECT * FROM crm_contacts WHERE id=?');
        $ref->execute([$id]);
        $contact = $ref->fetch();
        $pdo->prepare('INSERT INTO company_contacts(id,user_id,company_id,name,email,phone,role) VALUES(?,?,?,?,?,?,?) ON DUPLICATE KEY UPDATE company_id=VALUES(company_id),name=VALUES(name),email=VALUES(email),phone=VALUES(phone)')
            ->execute([$id,$contact['user_id'],$contact['company_id'],trim($contact['first_name'].' '.$contact['last_name']),$contact['email'],$contact['phone'],$contact['role']]);
    }
}
if ($preview) {
    $pdo->rollBack();
    json_ok(['ok'=>true,'applied'=>false,'preview'=>true,'module'=>$module,'exists'=>$existingOwner!==false,'fields'=>array_keys($data),'operatorFallback'=>$fallback,'deletionHeld'=>$deleted]);
}
if (!$stale && $deleted) {
    // Teamleader delete events are authoritative. The origin guard prevents
    // this local delete from creating a reverse event back to Teamleader.
    if ($module === 'contacts') {
        $pdo->prepare('DELETE FROM company_contacts WHERE id=?')->execute([$id]);
        $pdo->prepare('DELETE FROM crm_contacts WHERE id=?')->execute([$id]);
    } else {
        $pdo->prepare("DELETE FROM `$table` WHERE id=?")->execute([$id]);
    }
}
// Keep the source tombstone for replay/order protection after the local delete.
if (!$stale) $pdo->prepare('UPDATE teamleader_sync_entities SET observed_at=?,source_json=?,deleted=? WHERE team_id=? AND module=? AND source_id=?')->execute([(float)$observed,json_encode($row,JSON_THROW_ON_ERROR),$deleted?1:0,$teamId,$module,$sourceId]);
$pdo->prepare('INSERT INTO teamleader_sync_events(team_id,event_id,body_hash) VALUES(?,?,?)')->execute([$teamId,$eventId,$bodyHash]);
$pdo->commit();
json_ok(['ok'=>true,'applied'=>true,'stale'=>$stale,'deletionHeld'=>$deleted,'operatorFallback'=>$fallback]);
