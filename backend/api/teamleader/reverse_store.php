<?php
declare(strict_types=1);

/**
 * Prospective MySQL 8 reverse outbox. No HTTP, credentials, history import or logging.
 *
 * Schema (InnoDB, case-sensitive keys):
 * teamleader_reverse_outbox: id PK, team_id/module/local_id, action, before_json,
 * after_json, status, lease/claim_deadline, result_json, error_code, timestamps.
 * teamleader_object_links: PK(team_id,module,local_id), UNIQUE(team_id,module,remote_id),
 * remote_type nullable. Never changes CRM identifiers.
 *
 * Install requires an existing teamleader_sync_entities table and TRIGGER privilege.
 * MySQL DDL is not transactional: install/reconfigure with CRM writers paused. Existing
 * identical triggers are retained; changed snapshots require an explicit maintenance
 * removal of the reported trigger before reinstalling. Disabled modules lose triggers.
 * Mutators own their transaction; read helpers can run inside an incoming transaction.
 * A busy check is a guard, not a lock spanning a subsequent incoming write: callers
 * must coordinate concurrent incoming writes with their own source/entity locking.
 */

/** Core module => physical table, deliberately independent of the incoming mapper. */
function tlr_tables(): array
{
    return ['companies'=>'companies', 'contacts'=>'company_contacts', 'deals'=>'deals',
        'projects'=>'projects', 'phases'=>'project_phases', 'tasks'=>'work_tasks',
        'timetracking'=>'time_tracks'];
}

function tlr_ident(string $name): string
{
    return '`' . str_replace('`', '``', $name) . '`';
}

function tlr_key(string $value, int $max = 64): string
{
    if ($value === '' || strlen($value) > $max || preg_match('/[^\x20-\x7e]/', $value)) {
        throw new InvalidArgumentException('Invalid reverse sync identifier.');
    }
    return $value;
}

function tlr_module(string $module): void
{
    if (!isset(tlr_tables()[$module])) throw new InvalidArgumentException('Unsupported reverse module.');
}

function tlr_connection(PDO $pdo): void
{
    if ($pdo->inTransaction()) throw new LogicException('Reverse mutation requires its own transaction.');
    if ($pdo->getAttribute(PDO::ATTR_DRIVER_NAME) !== 'mysql') throw new LogicException('MySQL is required.');
    if ($pdo->getAttribute(PDO::ATTR_ERRMODE) !== PDO::ERRMODE_EXCEPTION) {
        throw new LogicException('PDO exception mode is required.');
    }
}

function tlr_query(PDO $pdo, string $sql, array $params = []): PDOStatement
{
    $st = $pdo->prepare($sql);
    foreach (array_values($params) as $i=>$value) {
        $st->bindValue($i + 1, $value, $value === null ? PDO::PARAM_NULL : (is_int($value) ? PDO::PARAM_INT : PDO::PARAM_STR));
    }
    $st->execute();
    return $st;
}

function tlr_transaction(PDO $pdo, callable $body)
{
    tlr_connection($pdo);
    $pdo->beginTransaction();
    try {
        $value = $body();
        $pdo->commit();
        return $value;
    } catch (Throwable $e) {
        if ($pdo->inTransaction()) $pdo->rollBack();
        throw $e;
    }
}

/**
 * Creates only the two reverse tables and AFTER INSERT/UPDATE/DELETE triggers. No seed.
 * config: team_id required; reverse_modules list of core module keys, default [].
 * Returns {team_id,modules,tables:list<string>,triggers:list<string>,lease_seconds:120}.
 * DDL/privilege failures propagate; partial DDL must be inspected before resuming writes.
 */
function tlr_install(PDO $pdo, array $config): array
{
    tlr_connection($pdo);
    $team = tlr_key((string)($config['team_id'] ?? ''));
    $modules = $config['reverse_modules'] ?? [];
    if (!is_array($modules) || !array_is_list($modules)) throw new InvalidArgumentException('reverse_modules must be a list.');
    foreach ($modules as $module) {
        if (!is_string($module)) throw new InvalidArgumentException('Invalid reverse module.');
        tlr_module($module);
    }
    $modules = array_values(array_unique($modules));
    if (!tlr_query($pdo, 'SELECT 1 FROM `teams` WHERE `id`=?', [$team])->fetchColumn()) {
        throw new InvalidArgumentException('Reverse team not found.');
    }
    // Validate the barrier dependency without creating or migrating incoming tables.
    $pdo->query('SELECT `team_id`,`module`,`source_id`,`observed_at`,`source_json`,`deleted` FROM `teamleader_sync_entities` LIMIT 0');
    $plans = [];
    $literal = static fn(string $s): string => "CONVERT(X'" . bin2hex($s) . "' USING utf8mb4)";
    $t = $literal($team);
    // Compare identifiers as bytes: imported schemas can use different
    // utf8mb4 collations, which otherwise makes MySQL reject trigger writes
    // with error 1267 (Illegal mix of collations).
    $scope = static fn(string $row): string => "(EXISTS (SELECT 1 FROM `teams` WHERE BINARY `id` = BINARY $t AND BINARY `owner_id` = BINARY $row.`user_id`)"
        . " OR EXISTS (SELECT 1 FROM `users` WHERE BINARY `team_id` = BINARY $t AND BINARY `id` = BINARY $row.`user_id`)"
        . " OR EXISTS (SELECT 1 FROM `team_members` WHERE BINARY `team_id` = BINARY $t AND BINARY `user_id` = BINARY $row.`user_id` AND BINARY `status` = BINARY 'active'))";
    foreach ($modules as $module) {
        $table = tlr_tables()[$module];
        $engine = tlr_query($pdo, 'SELECT ENGINE FROM information_schema.TABLES WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME=?', [$table])->fetchColumn();
        if ($engine !== 'InnoDB') throw new RuntimeException('Reverse CRM table must exist and use InnoDB: ' . $table);
        $cols = tlr_query($pdo, 'SELECT COLUMN_NAME FROM information_schema.COLUMNS WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME=? ORDER BY ORDINAL_POSITION', [$table])->fetchAll(PDO::FETCH_COLUMN);
        if (!in_array('id', $cols, true) || !in_array('user_id', $cols, true)) throw new RuntimeException('Missing reverse CRM identity columns.');
        $snapshot = static function (string $row) use ($cols, $literal): string {
            $parts = [];
            foreach ($cols as $col) {
                $parts[] = $literal($col);
                $parts[] = $row . '.' . tlr_ident($col);
            }
            return 'JSON_OBJECT(' . implode(',', $parts) . ')';
        };
        $changes = [];
        foreach ($cols as $col) {
            if ($col !== 'updated_at') $changes[] = 'NOT (CAST(OLD.' . tlr_ident($col) . ' AS BINARY) <=> CAST(NEW.' . tlr_ident($col) . ' AS BINARY))';
        }
        foreach (['INSERT'=>'create', 'UPDATE'=>'update', 'DELETE'=>'delete'] as $verb=>$action) {
            $name = 'tlr_' . substr(hash('sha256', $team), 0, 24) . '_' . $module . '_' . strtolower($verb);
            $rowAlias = $verb === 'DELETE' ? 'OLD' : 'NEW';
            $guard = "NOT (BINARY COALESCE(@nexora_sync_origin,'') = BINARY 'teamleader') AND " . $scope($rowAlias);
            if ($verb === 'UPDATE') $guard .= ' AND ' . $scope('OLD') . ' AND (' . implode(' OR ', $changes) . ')';
            $before = $verb === 'INSERT' ? 'NULL' : $snapshot('OLD');
            $after = $verb === 'DELETE' ? $literal('{}') : $snapshot('NEW');
            $body = "BEGIN IF $guard THEN ";
            if ($verb === 'UPDATE') $body .= "IF NOT (CAST(OLD.`id` AS BINARY) <=> CAST(NEW.`id` AS BINARY)) THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Reverse sync identity is immutable'; END IF; ";
            $body .= 'INSERT INTO `teamleader_reverse_outbox` (`team_id`,`module`,`local_id`,`action`,`before_json`,`after_json`) VALUES ('
                . $t . ',' . $literal($module) . ',' . $rowAlias . '.`id`,' . $literal($action) . ',' . $before . ',' . $after . '); END IF; END';
            $plans[$name] = ['table'=>$table, 'verb'=>$verb, 'body'=>$body];
        }
    }
    $pdo->exec("CREATE TABLE IF NOT EXISTS `teamleader_reverse_outbox` (
        `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
        `team_id` VARCHAR(64) NOT NULL, `module` VARCHAR(32) NOT NULL, `local_id` VARCHAR(64) NOT NULL,
        `action` ENUM('create','update','delete') NOT NULL, `before_json` JSON NULL, `after_json` JSON NOT NULL,
        `status` ENUM('pending','leased','delivered','blocked','conflict','uncertain') NOT NULL DEFAULT 'pending',
        `lease` CHAR(64) NULL, `claim_deadline` DATETIME(6) NULL,
        `result_json` JSON NULL, `error_code` VARCHAR(128) NULL,
        `created_at` DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6), `finished_at` DATETIME(6) NULL,
        KEY `tlr_queue` (`team_id`,`status`,`id`), KEY `tlr_entity` (`team_id`,`module`,`local_id`,`id`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_bin");
    // Existing installations predate delete events; widen the enum in place.
    $pdo->exec("ALTER TABLE `teamleader_reverse_outbox`
        MODIFY `action` ENUM('create','update','delete') NOT NULL");
    $pdo->exec("CREATE TABLE IF NOT EXISTS `teamleader_object_links` (
        `team_id` VARCHAR(64) NOT NULL, `module` VARCHAR(32) NOT NULL,
        `local_id` VARCHAR(64) NOT NULL, `remote_id` VARCHAR(64) NOT NULL, `remote_type` VARCHAR(64) NULL,
        `created_at` DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
        PRIMARY KEY (`team_id`,`module`,`local_id`), UNIQUE KEY `tlr_remote` (`team_id`,`module`,`remote_id`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_bin");
    $prefix = 'tlr_' . substr(hash('sha256', $team), 0, 24) . '_';
    $existing = tlr_query($pdo, 'SELECT TRIGGER_NAME,ACTION_STATEMENT FROM information_schema.TRIGGERS WHERE TRIGGER_SCHEMA=DATABASE()')->fetchAll(PDO::FETCH_KEY_PAIR);
    // Rebuild changed triggers in place. MySQL DDL is not transactional, but
    // replacing one trigger at a time keeps an already installed bridge
    // recoverable after a schema/collation hardening change.
    foreach ($plans as $name=>$plan) {
        if (isset($existing[$name]) && $existing[$name] !== $plan['body']) {
            $pdo->exec('DROP TRIGGER ' . tlr_ident($name));
            unset($existing[$name]);
        }
    }
    foreach ($existing as $name=>$body) {
        if (str_starts_with($name, $prefix) && !isset($plans[$name])) $pdo->exec('DROP TRIGGER ' . tlr_ident($name));
    }
    foreach ($plans as $name=>$plan) {
        if (!isset($existing[$name])) $pdo->exec('CREATE TRIGGER ' . tlr_ident($name) . ' AFTER ' . $plan['verb'] . ' ON ' . tlr_ident($plan['table']) . ' FOR EACH ROW ' . $plan['body']);
    }
    return ['team_id'=>$team, 'modules'=>$modules, 'tables'=>['teamleader_reverse_outbox','teamleader_object_links'], 'triggers'=>array_keys($plans), 'lease_seconds'=>120];
}

/** {remote_id:?string,remote_type:?string,candidate:?string}; candidate is unverified legacy identity. */
function tlr_lookup(PDO $pdo, string $team, string $module, string $localId): array
{
    tlr_key($team); tlr_module($module); tlr_key($localId);
    $link = tlr_query($pdo, 'SELECT `remote_id`,`remote_type` FROM `teamleader_object_links` WHERE `team_id`=? AND `module`=? AND `local_id`=?', [$team,$module,$localId])->fetch(PDO::FETCH_ASSOC);
    if ($link) return $link + ['candidate'=>null];
    // A prospective INSERT is never a legacy identity, even if an incoming race used its ID.
    $prospective = tlr_query($pdo, "SELECT 1 FROM `teamleader_reverse_outbox` WHERE `team_id`=? AND `module`=? AND `local_id`=? AND `action`='create' LIMIT 1", [$team,$module,$localId])->fetchColumn();
    return ['remote_id'=>null, 'remote_type'=>null, 'candidate'=>$prospective ? null : $localId];
}

/** Incoming alias, or remoteId unchanged. No mutation and safe within caller transaction. */
function tlr_incoming_local_id(PDO $pdo, string $team, string $module, string $remoteId): string
{
    tlr_key($team); tlr_module($module); tlr_key($remoteId);
    $id = tlr_query($pdo, 'SELECT `local_id` FROM `teamleader_object_links` WHERE `team_id`=? AND `module`=? AND `remote_id`=? FOR UPDATE', [$team,$module,$remoteId])->fetchColumn();
    return $id === false ? $remoteId : (string)$id;
}

/** Unresolved record edits, or any unmapped create in this module, block incoming writes. */
function tlr_incoming_busy(PDO $pdo, string $team, string $module, string $localId): bool
{
    tlr_key($team); tlr_module($module); tlr_key($localId);
    return (bool)tlr_query($pdo, "SELECT 1 FROM `teamleader_reverse_outbox` o
        LEFT JOIN `teamleader_object_links` l ON l.`team_id`=o.`team_id` AND l.`module`=o.`module` AND l.`local_id`=o.`local_id`
        WHERE o.`team_id`=? AND o.`module`=? AND o.`status`<>'delivered'
        AND (o.`local_id`=? OR (o.`action`='create' AND l.`remote_id` IS NULL
            AND NOT (o.`status` IN ('blocked','conflict') AND COALESCE(JSON_UNQUOTE(JSON_EXTRACT(o.`result_json`,'$.no_mutation')),'false')='true')))
        LIMIT 1 FOR UPDATE", [$team,$module,$localId])->fetchColumn();
}

/**
 * Atomic durable 120s lease of earliest eligible event; null when none.
 * Return {id,module,local_id,action,before:array,record:array,lease,claim_deadline,
 * remote_id:?string,remote_type:?string}. No worker configuration is returned.
 * Expired leases become uncertain, retain tokens and never reenter pending.
 * Earlier unresolved events serialize each record, including across workers.
 */
function tlr_claim(PDO $pdo, string $team): ?array
{
    tlr_key($team);
    return tlr_transaction($pdo, static function () use ($pdo,$team): ?array {
        tlr_query($pdo, "UPDATE `teamleader_reverse_outbox` SET `status`='uncertain',`error_code`='lease_expired'
            WHERE `team_id`=? AND `status`='leased' AND `claim_deadline`<=UTC_TIMESTAMP(6)", [$team]);
        $row = tlr_query($pdo, "SELECT o.* FROM `teamleader_reverse_outbox` o
            WHERE o.`team_id`=? AND o.`status`='pending' AND NOT EXISTS (
                SELECT 1 FROM `teamleader_reverse_outbox` p WHERE p.`team_id`=o.`team_id` AND p.`module`=o.`module`
                AND p.`local_id`=o.`local_id` AND p.`id`<o.`id` AND p.`status`<>'delivered')
            ORDER BY o.`id` LIMIT 1 FOR UPDATE SKIP LOCKED", [$team])->fetch(PDO::FETCH_ASSOC);
        if (!$row) return null;
        $lease = bin2hex(random_bytes(32));
        tlr_query($pdo, "UPDATE `teamleader_reverse_outbox` SET `status`='leased',`lease`=?,`claim_deadline`=DATE_ADD(UTC_TIMESTAMP(6),INTERVAL 120 SECOND) WHERE `id`=? AND `team_id`=?", [$lease,(int)$row['id'],$team]);
        $deadline = tlr_query($pdo, 'SELECT `claim_deadline` FROM `teamleader_reverse_outbox` WHERE `id`=?', [(int)$row['id']])->fetchColumn();
        $link = tlr_lookup($pdo,$team,$row['module'],$row['local_id']);
        return ['id'=>(int)$row['id'], 'module'=>$row['module'], 'local_id'=>$row['local_id'], 'action'=>$row['action'],
            'before'=>$row['before_json'] === null ? [] : json_decode($row['before_json'],true,512,JSON_THROW_ON_ERROR),
            'record'=>json_decode($row['after_json'],true,512,JSON_THROW_ON_ERROR), 'lease'=>$lease,
            'claim_deadline'=>$deadline, 'remote_id'=>$link['remote_id'], 'remote_type'=>$link['remote_type']];
    });
}

/**
 * result: {status:delivered|blocked|conflict|uncertain,remote_id?,remote_type?,error_code?}.
 * Returns {id,status,duplicate,remote_id,remote_type}. Identical ack is idempotent;
 * changed ack/token throws. A retained expired token may acknowledge a late response
 * exactly once (no second call is issued). Delivered requires remote_id or an existing
 * confirmed mapping. Mapping collision settles conflict, never overwrites either link.
 * Ack and UNIX epoch source barrier commit together, preserving existing source_json.
 */
function tlr_finish(PDO $pdo, string $team, int $eventid, string $lease, array $result): array
{
    tlr_key($team);
    if ($eventid < 1 || !preg_match('/^[a-f0-9]{64}$/D', $lease)) throw new InvalidArgumentException('Invalid reverse acknowledgment.');
    $status = $result['status'] ?? '';
    if (!in_array($status,['delivered','blocked','conflict','uncertain'],true)) throw new InvalidArgumentException('Invalid reverse result status.');
    $remote = isset($result['remote_id']) ? tlr_key((string)$result['remote_id']) : null;
    $type = isset($result['remote_type']) ? tlr_key((string)$result['remote_type']) : null;
    $error = $result['error_code'] ?? null;
    if ($error !== null && (!is_string($error) || !preg_match('/^[A-Za-z0-9_.:-]{1,128}$/D', $error))) throw new InvalidArgumentException('error_code must be a machine code, not record data.');
    $noMutation = !empty($result['no_mutation']);
    $json = json_encode(['status'=>$status,'remote_id'=>$remote,'remote_type'=>$type,'error_code'=>$error,'no_mutation'=>$noMutation],JSON_THROW_ON_ERROR);
    return tlr_transaction($pdo, static function () use ($pdo,$team,$eventid,$lease,$status,$remote,$type,$error,$json,$noMutation): array {
        $row = tlr_query($pdo, 'SELECT * FROM `teamleader_reverse_outbox` WHERE `team_id`=? AND `id`=? FOR UPDATE', [$team,$eventid])->fetch(PDO::FETCH_ASSOC);
        if (!$row || !is_string($row['lease']) || !hash_equals($row['lease'],$lease)) throw new LogicException('Reverse lease does not match.');
        $reply = static fn(string $s, bool $duplicate, ?string $r, ?string $t): array => ['id'=>$eventid,'status'=>$s,'duplicate'=>$duplicate,'remote_id'=>$r,'remote_type'=>$t];
        if ($row['result_json'] !== null) {
            if (json_decode($row['result_json'],true,512,JSON_THROW_ON_ERROR) != json_decode($json,true,512,JSON_THROW_ON_ERROR)) throw new LogicException('Reverse acknowledgment differs from committed result.');
            $link = tlr_lookup($pdo,$team,$row['module'],$row['local_id']);
            return $reply($row['status'],true,$link['remote_id'],$link['remote_type']);
        }
        if (!in_array($row['status'],['leased','uncertain'],true)) throw new LogicException('Reverse event is not leased.');
        $link = tlr_query($pdo, 'SELECT `remote_id`,`remote_type` FROM `teamleader_object_links` WHERE `team_id`=? AND `module`=? AND `local_id`=? FOR UPDATE', [$team,$row['module'],$row['local_id']])->fetch(PDO::FETCH_ASSOC);
        $resolved = $remote ?? ($link['remote_id'] ?? null);
        $resolvedType = $type ?? ($link['remote_type'] ?? null);
        if ($status === 'delivered') {
            if ($resolved === null) throw new InvalidArgumentException('Delivered acknowledgment requires remote_id.');
            if ($link && ($link['remote_id'] !== $resolved || ($link['remote_type'] !== null && $type !== null && $link['remote_type'] !== $type))) {
                $status = 'conflict'; $error = 'mapping_conflict';
            } else {
                try {
                    if (!$link) tlr_query($pdo, 'INSERT INTO `teamleader_object_links` (`team_id`,`module`,`local_id`,`remote_id`,`remote_type`) VALUES (?,?,?,?,?)', [$team,$row['module'],$row['local_id'],$resolved,$resolvedType]);
                    elseif ($link['remote_type'] === null && $resolvedType !== null) tlr_query($pdo, 'UPDATE `teamleader_object_links` SET `remote_type`=? WHERE `team_id`=? AND `module`=? AND `local_id`=?', [$resolvedType,$team,$row['module'],$row['local_id']]);
                } catch (PDOException $e) {
                    if ((int)($e->errorInfo[1] ?? 0) !== 1062) throw $e;
                    $status = 'conflict'; $error = 'mapping_conflict';
                }
            }
            if ($status === 'delivered' && !$noMutation) {
                tlr_query($pdo, "INSERT INTO `teamleader_sync_entities` (`team_id`,`module`,`source_id`,`observed_at`,`source_json`,`deleted`)
                    VALUES (?,?,?,UNIX_TIMESTAMP(CURRENT_TIMESTAMP(6)),'{}',0)
                    ON DUPLICATE KEY UPDATE `observed_at`=GREATEST(`observed_at`,UNIX_TIMESTAMP(CURRENT_TIMESTAMP(6)))", [$team,$row['module'],$resolved]);
            }
        }
        tlr_query($pdo, 'UPDATE `teamleader_reverse_outbox` SET `status`=?,`result_json`=?,`error_code`=?,`finished_at`=UTC_TIMESTAMP(6) WHERE `id`=? AND `team_id`=?', [$status,$json,$error,$eventid,$team]);
        $finalLink = tlr_lookup($pdo,$team,$row['module'],$row['local_id']);
        return $reply($status,false,$finalLink['remote_id'],$finalLink['remote_type']);
    });
}
