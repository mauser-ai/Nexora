<?php
// CRUD Projects + azione speciale: POST /api/projects/?action=create_with_config

require_once __DIR__ . '/../bootstrap.php';

function projects_has_custom_fields_column(): bool {
    static $hasColumn = null;
    if ($hasColumn !== null) return $hasColumn;
    try {
        $st = db()->query("SHOW COLUMNS FROM projects LIKE 'custom_fields'");
        $hasColumn = (bool)$st->fetch();
    } catch (Throwable $e) {
        $hasColumn = false;
    }
    return $hasColumn;
}

$userId = require_auth();
$scope = scope_filter_sql('user_id', scoped_user_ids($userId));
$method = http_method();
$id     = $_GET['id']     ?? null;
$action = $_GET['action'] ?? null;

// ── CREATE WITH CONFIG (wizard fasi) ─────────────────────────────────────────
if ($method === 'POST' && $action === 'create_with_config') {
    $b = request_body();

    $projectId    = str_val($b['id'] ?? uuid4());
    $companyId    = str_val($b['companyId'] ?? '');
    $name         = str_val($b['name'] ?? '');
    $type         = str_val($b['type'] ?? 'profit');
    $opportunityId= $b['opportunityId'] ?? null;
    $quotationId  = $b['quotationId'] ?? null;
    $phaseConfigs = $b['phaseConfigs'] ?? [];
    $now          = date('Y-m-d H:i:s');

    if (empty($companyId) || empty($name)) json_error('companyId e name richiesti');

    $db = db();
    try {
        $db->beginTransaction();

        // Progetto
        $code = 'GUS-' . date('Y') . '-' . strtoupper(substr($projectId, 0, 4));
        $projectParams = [
            $projectId,
            $userId,
            $companyId,
            $name,
            $code,
            'planning',
            $type,
            $opportunityId,
            $quotationId,
            $now,
        ];
        $projectSql = 'INSERT INTO projects (id,user_id,company_id,name,code,status,type,opportunity_id,quotation_id,created_at';
        $projectPlaceholders = '?,?,?,?,?,?,?,?,?,?';
        if (projects_has_custom_fields_column()) {
            $projectSql .= ',custom_fields';
            $projectPlaceholders .= ',?';
            $projectParams[] = json_encode((object)($b['customFields'] ?? []));
        }
        $projectSql .= ') VALUES (' . $projectPlaceholders . ')';
        $db->prepare($projectSql)->execute($projectParams);

        // Fasi + task
        foreach ($phaseConfigs as $i => $cfg) {
            $phaseId    = uuid4();
            $phaseName  = str_val($cfg['phaseName'] ?? "Fase " . ($i+1));
            $startDate  = to_date($cfg['startDate'] ?? null);
            $endDate    = to_date($cfg['endDate'] ?? null);
            $assigneeId = $cfg['assigneeId'] ?? null;

            $db->prepare(
                'INSERT INTO project_phases (id,user_id,project_id,name,phase_order,status,assigned_user_id,start_date,deadline,is_custom)
                 VALUES (?,?,?,?,?,?,?,?,?,0)'
            )->execute([$phaseId,$userId,$projectId,$phaseName,$i,'notStarted',$assigneeId,$startDate,$endDate]);

            $taskNames = $cfg['taskNames'] ?? [];
            foreach ($taskNames as $taskName) {
                $taskId = uuid4();
                $db->prepare(
                    'INSERT INTO work_tasks (id,user_id,company_id,project_id,phase_id,assignee_id,name,
                     estimated_hours,logged_hours,start_date,deadline,status,billable,created_at)
                     VALUES (?,?,?,?,?,?,?,2,0,?,?,?,1,?)'
                )->execute([
                    $taskId,$userId,$companyId,$projectId,$phaseId,
                    str_val($assigneeId ?? ''),str_val($taskName),
                    $startDate ?? date('Y-m-d'),$endDate ?? date('Y-m-d',strtotime('+14 days')),
                    'planned',$now
                ]);
            }
        }

        // Aggiorna opportunità → presaInCarico
        if ($opportunityId) {
            $db->prepare(
                'UPDATE opportunities SET status=?,presa_in_carico=1 WHERE id=? AND ' . $scope['sql']
            )->execute(array_merge(['presaInCarico', $opportunityId], $scope['params']));
        }

        // Aggiorna preventivo → linked
        if ($quotationId) {
            $db->prepare(
                'UPDATE preventivi SET linked_project_id=? WHERE id=? AND ' . $scope['sql']
            )->execute(array_merge([$projectId, $quotationId], $scope['params']));
        }

        $db->commit();
        json_ok(['id' => $projectId], 201);
    } catch (\Throwable $e) {
        $db->rollBack();
        json_error('Errore transazione: ' . $e->getMessage(), 500);
    }
}

// ── SET ANTICIPO EMESSO ───────────────────────────────────────────────────────
if ($method === 'POST' && $action === 'set_anticipo_emesso') {
    if (!$id) json_error('id mancante');
    db()->prepare('UPDATE projects SET anticipo_emesso=1 WHERE id=? AND ' . $scope['sql'])
       ->execute(array_merge([$id], $scope['params']));
    json_ok(['ok' => true]);
}

// ── GET ───────────────────────────────────────────────────────────────────────
if ($method === 'GET') {
    $rows = db()->prepare('SELECT * FROM projects WHERE ' . $scope['sql'] . ' ORDER BY created_at DESC');
    $rows->execute($scope['params']);
    json_ok($rows->fetchAll());
}

// ── POST (crea progetto semplice) ─────────────────────────────────────────────
if ($method === 'POST') {
    $b  = request_body();
    $id = str_val($b['id'] ?? uuid4());
    $params = [
        $id,$userId,
        $b['companyId'] ?? null,
        str_val($b['name'] ?? ''),
        str_val($b['code'] ?? ''),
        str_val($b['status'] ?? 'planning'),
        str_val($b['type'] ?? 'profit'),
        $b['opportunityId'] ?? null,
        $b['quotationId'] ?? null,
        str_val($b['notes'] ?? ''),
    ];
    $sql = 'INSERT INTO projects (id,user_id,company_id,name,code,status,type,opportunity_id,quotation_id,notes';
    $placeholders = '?,?,?,?,?,?,?,?,?,?';
    if (projects_has_custom_fields_column()) {
        $sql .= ',custom_fields';
        $placeholders .= ',?';
        $params[] = json_encode((object)($b['customFields'] ?? []));
    }
    $sql .= ') VALUES (' . $placeholders . ')';
    db()->prepare($sql)->execute($params);
    json_ok(['id' => $id], 201);
}

// ── PUT ───────────────────────────────────────────────────────────────────────
if ($method === 'PUT' || $method === 'PATCH') {
    if (!$id) json_error('id mancante');
    $b   = request_body();
    $map = [
        'name'=>'name','code'=>'code','status'=>'status','type'=>'type','notes'=>'notes',
        'anticipoEmesso'=>'anticipo_emesso','rifProgetto'=>'rif_progetto',
        'rifCaricamento'=>'rif_caricamento','idProgettoEsterno'=>'id_progetto_esterno',
        'titoloProgetto'=>'titolo_progetto','grantAmount'=>'grant_amount',
        'successFeeAmount'=>'success_fee_amount','daFaturareA'=>'da_faturare_a',
        'contributoRichiesto'=>'contributo_richiesto','contributoRicevuto'=>'contributo_ricevuto',
        'avanzamentoPratica'=>'avanzamento_pratica','esitoPratica'=>'esito_pratica',
        'statoRendicontazione'=>'stato_rendicontazione',
        'termineRendicontazione'=>'termine_rendicontazione',
        'dataInizioProgetto'=>'data_inizio_progetto','dataFineProgetto'=>'data_fine_progetto',
        'customFields'=>'custom_fields',
    ];
    $dateFields = ['termine_rendicontazione','data_inizio_progetto','data_fine_progetto'];
    $sets = []; $vals = [];
    foreach ($b as $k => $v) {
        if (!isset($map[$k])) continue;
        $col = $map[$k];
        if ($col === 'custom_fields' && !projects_has_custom_fields_column()) continue;
        $sets[] = "$col = ?";
        if (in_array($col, $dateFields)) $v = to_date($v);
        if ($col === 'anticipo_emesso') $v = $v ? 1 : 0;
        if ($col === 'custom_fields') $v = json_encode((object)($v ?? []));
        $vals[] = $v;
    }
    if (empty($sets)) json_error('Nessun campo');
    $vals[] = $id;
    $vals = array_merge($vals, $scope['params']);
    db()->prepare('UPDATE projects SET ' . implode(',', $sets) . ' WHERE id=? AND ' . $scope['sql'])
       ->execute($vals);
    json_ok(['ok' => true]);
}

// ── DELETE ────────────────────────────────────────────────────────────────────
if ($method === 'DELETE') {
    if (!$id) json_error('id mancante');
    db()->prepare('DELETE FROM projects WHERE id=? AND ' . $scope['sql'])
       ->execute(array_merge([$id], $scope['params']));
    json_ok(['ok' => true]);
}

json_error('Metodo non consentito', 405);
