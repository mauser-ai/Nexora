<?php
declare(strict_types=1);

/**
 * Local-only integration test. Creates/drops a random isolated database, never the
 * database in the DSN. Requires CREATE/DROP DATABASE and TRIGGER privileges.
 * TLR_TEST_DSN='mysql:unix_socket=/tmp/mysql.sock' TLR_TEST_USER=root php deploy/teamleader/test_reverse_store.php
 * Without TLR_TEST_DSN, runs pure validation checks and reports integration skipped.
 */
require_once __DIR__ . '/../../backend/api/teamleader/reverse_store.php';

$checks = 0;
function tlrt_check(bool $ok, string $message): void
{
    global $checks;
    if (!$ok) throw new RuntimeException('FAIL: ' . $message);
    ++$checks;
}
function tlrt_throws(callable $fn, string $class): void
{
    try { $fn(); } catch (Throwable $e) {
        tlrt_check($e instanceof $class, 'exception type: ' . get_class($e));
        return;
    }
    throw new RuntimeException('FAIL: expected ' . $class);
}
tlrt_check(tlr_tables()['contacts'] === 'crm_contacts', 'physical module mapping');
tlrt_check(tlr_ident('a`b') === '`a``b`', 'identifier quoting');
tlrt_throws(static fn()=>tlr_module('users'), InvalidArgumentException::class);
tlrt_throws(static fn()=>tlr_key(''), InvalidArgumentException::class);
$dsn = getenv('TLR_TEST_DSN');
if (!$dsn) {
    echo "PASS $checks validation checks; MySQL integration SKIPPED (set TLR_TEST_DSN).\n";
    exit(0);
}
if (!str_starts_with($dsn, 'mysql:') || preg_match('/(?:host|port)=/i', $dsn)) {
    throw new RuntimeException('Tests require a local Unix-socket MySQL DSN (no network).');
}
$user = getenv('TLR_TEST_USER') ?: 'root';
$password = getenv('TLR_TEST_PASSWORD') ?: '';
$options = [PDO::ATTR_ERRMODE=>PDO::ERRMODE_EXCEPTION, PDO::ATTR_EMULATE_PREPARES=>false];
$pdo = new PDO($dsn,$user,$password,$options);
$db = 'tlr_test_' . bin2hex(random_bytes(8));
$pdo->exec('CREATE DATABASE ' . tlr_ident($db) . ' CHARACTER SET utf8mb4 COLLATE utf8mb4_bin');
try {
    $pdo->exec('USE ' . tlr_ident($db));
    $pdo->exec("CREATE TABLE teams (id VARCHAR(64) PRIMARY KEY,owner_id VARCHAR(64)) ENGINE=InnoDB");
    $pdo->exec("CREATE TABLE users (id VARCHAR(64) PRIMARY KEY,team_id VARCHAR(64)) ENGINE=InnoDB");
    $pdo->exec("CREATE TABLE team_members (team_id VARCHAR(64),user_id VARCHAR(64),status VARCHAR(20)) ENGINE=InnoDB");
    $pdo->exec("CREATE TABLE teamleader_sync_entities (team_id VARCHAR(64),module VARCHAR(32),source_id VARCHAR(64),observed_at DOUBLE NOT NULL DEFAULT 0,source_json LONGTEXT NOT NULL,deleted TINYINT NOT NULL DEFAULT 0,PRIMARY KEY(team_id,module,source_id)) ENGINE=InnoDB");
    foreach (tlr_tables() as $table) $pdo->exec('CREATE TABLE ' . tlr_ident($table) . ' (id VARCHAR(64) PRIMARY KEY,user_id VARCHAR(64),name VARCHAR(255),details JSON,updated_at DATETIME(6)) ENGINE=InnoDB');
    $pdo->exec("INSERT INTO teams VALUES ('A','owner'),('B','other')");
    $pdo->exec("INSERT INTO users VALUES ('owner','A'),('member','A'),('other','B'),('guest','B'),('inactive','B')");
    $pdo->exec("INSERT INTO team_members VALUES ('A','guest','active'),('A','inactive','deactivated')");
    $insert = static function (string $id, string $owner='owner', string $module='companies') use ($pdo): void {
        tlr_query($pdo, 'INSERT INTO ' . tlr_ident(tlr_tables()[$module]) . ' (id,user_id,name,details,updated_at) VALUES (?,?,?,JSON_OBJECT(\'x\',1),NOW(6))', [$id,$owner,'Original']);
    };
    $insert('legacy');
    $config = ['team_id'=>'A','reverse_modules'=>array_keys(tlr_tables())];
    $off = tlr_install($pdo,['team_id'=>'A']);
    tlrt_check($off['triggers'] === [], 'default disabled');
    tlrt_check(tlr_claim($pdo,'A') === null, 'no seed with defaults');
    $installed = tlr_install($pdo,$config);
    tlrt_check(count($installed['triggers']) === 14, 'two triggers per core module');
    tlrt_check(tlr_install($pdo,$config) === $installed, 'idempotent install');
    tlrt_check(tlr_claim($pdo,'A') === null, 'existing rows never seeded');
    tlrt_check(tlr_lookup($pdo,'A','companies','legacy')['candidate'] === 'legacy', 'CSV identity candidate without incoming history');
    tlrt_throws(static fn()=>tlr_install($pdo,['team_id'=>'A','reverse_modules'=>['users']]), InvalidArgumentException::class);
    $pdo->beginTransaction();
    $insert('rolledback');
    tlrt_throws(static fn()=>tlr_claim($pdo,'A'), LogicException::class);
    tlrt_throws(static fn()=>tlr_install($pdo,$config), LogicException::class);
    $pdo->rollBack();
    tlrt_check(tlr_claim($pdo,'A') === null, 'trigger is transactional');
    $insert('foreign','other'); $insert('disabled','inactive');
    $pdo->exec("SET @nexora_sync_origin='teamleader'");
    $insert('incoming');
    $pdo->exec("UPDATE companies SET name='Inbound' WHERE id='legacy'");
    $pdo->exec('SET @nexora_sync_origin=NULL');
    $pdo->exec("UPDATE companies SET updated_at='2020-01-01' WHERE id='legacy'");
    tlrt_check(tlr_claim($pdo,'A') === null, 'origin, team, timestamp-only guards');
    $pdo->exec("UPDATE companies SET name='inbound' WHERE id='legacy'");
    $legacy = tlr_claim($pdo,'A');
    tlrt_check($legacy['action'] === 'update' && $legacy['before']['name'] === 'Inbound' && $legacy['record']['name'] === 'inbound', 'case-sensitive update and full snapshots');
    tlrt_check($legacy['record']['details'] === ['x'=>1], 'JSON snapshot embeds objects');
    tlr_query($pdo,"INSERT INTO teamleader_sync_entities VALUES ('A','companies','legacy',1,?,0)", ['{"preserved":true}']);
    $pdo->exec("SET time_zone='+05:30'");
    $ack = ['status'=>'delivered','remote_id'=>'legacy','remote_type'=>'company'];
    $finished = tlr_finish($pdo,'A',$legacy['id'],$legacy['lease'],$ack);
    tlrt_check($finished['status'] === 'delivered' && !$finished['duplicate'], 'successful acknowledgment');
    tlrt_check(tlr_finish($pdo,'A',$legacy['id'],$legacy['lease'],$ack)['duplicate'], 'duplicate ack despite MySQL JSON key ordering');
    $barrier = $pdo->query("SELECT * FROM teamleader_sync_entities WHERE source_id='legacy'")->fetch(PDO::FETCH_ASSOC);
    tlrt_check(abs((float)$barrier['observed_at'] - microtime(true)) < 5, 'epoch barrier independent of session timezone');
    tlrt_check($barrier['source_json'] === '{"preserved":true}', 'preserves incoming source JSON');
    tlrt_throws(static fn()=>tlr_finish($pdo,'A',$legacy['id'],$legacy['lease'],['status'=>'blocked']), LogicException::class);
    $insert('fresh');
    tlrt_check(tlr_lookup($pdo,'A','companies','fresh')['candidate'] === null, 'prospective create never legacy candidate');
    tlrt_check(tlr_incoming_busy($pdo,'A','companies','unknown'), 'module fence on unknown create');
    tlrt_check(!tlr_incoming_busy($pdo,'B','companies','unknown'), 'team-scoped fence');
    tlrt_check(!tlr_incoming_busy($pdo,'A','contacts','unknown'), 'module-scoped fence');
    $first = tlr_claim($pdo,'A');
    $pdo->exec("UPDATE companies SET name='Second' WHERE id='fresh'");
    tlrt_check(tlr_claim($pdo,'A') === null, 'no parallel dispatch on same record');
    tlrt_throws(static fn()=>tlr_finish($pdo,'B',$first['id'],$first['lease'],['status'=>'blocked']), LogicException::class);
    tlr_query($pdo,"UPDATE teamleader_reverse_outbox SET claim_deadline=DATE_SUB(UTC_TIMESTAMP(6),INTERVAL 1 SECOND) WHERE id=?", [$first['id']]);
    tlrt_check(tlr_claim($pdo,'A') === null, 'expired lease never redispatched');
    tlrt_check($pdo->query('SELECT status FROM teamleader_reverse_outbox WHERE id=' . $first['id'])->fetchColumn() === 'uncertain', 'expiration persisted uncertain');
    tlrt_check(tlr_incoming_busy($pdo,'A','companies','unrelated'), 'uncertain create still fences module');
    tlr_finish($pdo,'A',$first['id'],$first['lease'],['status'=>'delivered','remote_id'=>'remote-new']);
    tlrt_check(tlr_incoming_local_id($pdo,'A','companies','remote-new') === 'fresh', 'ack creates incoming alias');
    tlrt_check(tlr_incoming_local_id($pdo,'B','companies','remote-new') === 'remote-new', 'alias team isolation');
    tlrt_check(!tlr_incoming_busy($pdo,'A','companies','unrelated'), 'mapping releases module gate');
    tlrt_check(tlr_incoming_busy($pdo,'A','companies','fresh'), 'pending second edit protects record');
    $second = tlr_claim($pdo,'A');
    tlrt_check($second['action'] === 'update' && $second['remote_id'] === 'remote-new', 'next claim includes mapping');
    tlr_finish($pdo,'A',$second['id'],$second['lease'],['status'=>'delivered']);
    tlrt_check(!tlr_incoming_busy($pdo,'A','companies','fresh'), 'delivered releases record');
    $insert('collision');
    $event = tlr_claim($pdo,'A');
    $collision = ['status'=>'delivered','remote_id'=>'remote-new'];
    tlrt_check(tlr_finish($pdo,'A',$event['id'],$event['lease'],$collision)['status'] === 'conflict', 'remote mapping collision');
    tlrt_check(tlr_finish($pdo,'A',$event['id'],$event['lease'],$collision)['duplicate'], 'collision ack idempotent');
    tlrt_check(tlr_lookup($pdo,'A','companies','collision')['remote_id'] === null, 'collision never overwrites link');
    tlrt_check(tlr_incoming_busy($pdo,'A','companies','unknown'), 'conflicting create keeps module fence');
    foreach (['blocked','conflict','uncertain'] as $status) {
        $insert('failure-' . $status,'guest','contacts');
        $event = tlr_claim($pdo,'A');
        tlrt_check($event['module'] === 'contacts', 'active external member captured');
        tlr_finish($pdo,'A',$event['id'],$event['lease'],['status'=>$status,'error_code'=>'test_failure']);
        tlrt_check(tlr_claim($pdo,'A') === null, 'failure is terminal, no retry');
        tlrt_check(tlr_incoming_busy($pdo,'A','contacts','unknown'), 'failed unmapped create fences incoming');
    }
    // Independent durable leases from separate connections; no duplicate dispatch.
    $other = new PDO($dsn,$user,$password,$options);
    $other->exec('USE ' . tlr_ident($db));
    $insert('parallel-one','member','tasks');
    $insert('parallel-two','member','tasks');
    $one = tlr_claim($pdo,'A'); $two = tlr_claim($other,'A');
    tlrt_check($one['id'] !== $two['id'] && $one['lease'] !== $two['lease'], 'separate connections claim different events');
    tlrt_check(tlr_claim($other,'A') === null, 'both leases persist before return');
    tlr_finish($pdo,'A',$one['id'],$one['lease'],['status'=>'blocked']);
    tlr_finish($other,'A',$two['id'],$two['lease'],['status'=>'blocked']);
    // Native and emulated prepares both support identifiers containing quotes.
    $pdo->setAttribute(PDO::ATTR_EMULATE_PREPARES,true);
    $insert("quoted'id",'owner','projects');
    $event = tlr_claim($pdo,'A');
    tlrt_check($event['local_id'] === "quoted'id", 'parameter binding with quoted identifiers');
    tlr_finish($pdo,'A',$event['id'],$event['lease'],['status'=>'delivered','remote_id'=>"remote'quoted"]);
    tlrt_check(tlr_incoming_local_id($pdo,'A','projects',"remote'quoted") === "quoted'id", 'bound alias lookup');
    tlr_install($pdo,['team_id'=>'A']);
    $insert('after-disable');
    tlrt_check(tlr_claim($pdo,'A') === null, 'empty configuration disables capture without backfill');
    echo "PASS $checks checks (local MySQL " . $pdo->getAttribute(PDO::ATTR_SERVER_VERSION) . ").\n";
} finally {
    if ($pdo->inTransaction()) $pdo->rollBack();
    $pdo->exec('DROP DATABASE ' . tlr_ident($db));
}
