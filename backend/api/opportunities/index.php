<?php
// CRUD Opportunities

require_once __DIR__ . '/../bootstrap.php';

function opportunities_has_custom_fields_column(): bool {
    static $hasColumn = null;
    if ($hasColumn !== null) return $hasColumn;
    try {
        $st = db()->query("SHOW COLUMNS FROM opportunities LIKE 'custom_fields'");
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
    $rows = db()->prepare('SELECT * FROM opportunities WHERE ' . $scope['sql'] . ' ORDER BY created_at DESC');
    $rows->execute($scope['params']);
    json_ok($rows->fetchAll());
}

if ($method === 'POST') {
    $b  = request_body();
    $id = str_val($b['id'] ?? uuid4());
    $params = [
        $id, $userId,
        $b['companyId'] ?? null,
        str_val($b['title'] ?? ''),
        str_val($b['status'] ?? 'inAttesa'),
        str_val($b['bandoReference'] ?? ''),
        str_val($b['bandoSource'] ?? ''),
        to_date($b['bandoDeadline'] ?? null),
        float_val($b['estimatedValue'] ?? null),
        str_val($b['notes'] ?? ''),
        $b['assignedAnalystId'] ?? null,
        $b['contactId'] ?? null,
        str_val($b['rifOfferta'] ?? ''),
        str_val($b['contattoCommerciale'] ?? ''),
        bool_val($b['presaInCarico'] ?? false) ? 1 : 0,
        str_val($b['daFaturareA'] ?? ''),
        str_val($b['partnerCommerciale'] ?? ''),
        str_val($b['fornitore'] ?? ''),
        to_date($b['scadenzaPresentazione'] ?? null),
        to_date($b['scadenzaOperativa'] ?? null),
        str_val($b['avanzamentoPratica'] ?? 'none'),
        str_val($b['esitoPratica'] ?? 'none'),
        to_date($b['dataStato'] ?? null),
        float_val($b['totaleProgetto'] ?? null),
        float_val($b['contributoRichiesto'] ?? null),
        float_val($b['finanziamentoRichiesto'] ?? null),
        float_val($b['garanziaRichiesta'] ?? null),
        float_val($b['creditoImpostaRichiesto'] ?? null),
        to_date($b['termineRendicontazione'] ?? null),
        str_val($b['statoRendicontazione'] ?? 'none'),
        str_val($b['noteRendicontazione'] ?? ''),
    ];
    $sql = 'INSERT INTO opportunities (id,user_id,company_id,title,status,bando_reference,bando_source,
         bando_deadline,estimated_value,notes,assigned_analyst_id,contact_id,rif_offerta,
         contatto_commerciale,presa_in_carico,da_faturare_a,partner_commerciale,fornitore,
         scadenza_presentazione,scadenza_operativa,avanzamento_pratica,esito_pratica,data_stato,
         totale_progetto,contributo_richiesto,finanziamento_richiesto,garanzia_richiesta,
         credito_imposta_richiesto,termine_rendicontazione,stato_rendicontazione,note_rendicontazione';
    $placeholders = '?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?';
    if (opportunities_has_custom_fields_column()) {
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
    $b = request_body();
    $map = [
        'companyId'=>'company_id','title'=>'title','status'=>'status',
        'bandoReference'=>'bando_reference','bandoSource'=>'bando_source',
        'bandoDeadline'=>'bando_deadline','estimatedValue'=>'estimated_value','notes'=>'notes',
        'assignedAnalystId'=>'assigned_analyst_id','contactId'=>'contact_id',
        'rifOfferta'=>'rif_offerta','contattoCommerciale'=>'contatto_commerciale',
        'presaInCarico'=>'presa_in_carico','daFaturareA'=>'da_faturare_a',
        'partnerCommerciale'=>'partner_commerciale','fornitore'=>'fornitore',
        'scadenzaPresentazione'=>'scadenza_presentazione','scadenzaOperativa'=>'scadenza_operativa',
        'avanzamentoPratica'=>'avanzamento_pratica','esitoPratica'=>'esito_pratica',
        'dataStato'=>'data_stato','totaleProgetto'=>'totale_progetto',
        'contributoRichiesto'=>'contributo_richiesto','finanziamentoRichiesto'=>'finanziamento_richiesto',
        'garanziaRichiesta'=>'garanzia_richiesta','creditoImpostaRichiesto'=>'credito_imposta_richiesto',
        'totaleProgettoRidefinito'=>'totale_progetto_ridefinito',
        'totaleBeneficioEconomicoRicevuto'=>'totale_beneficio_economico_ricevuto',
        'contributoRicevuto'=>'contributo_ricevuto','finanziamentoRicevuto'=>'finanziamento_ricevuto',
        'garanziaRicevuta'=>'garanzia_ricevuta','creditoImpostaRicevuto'=>'credito_imposta_ricevuto',
        'termineRendicontazione'=>'termine_rendicontazione',
        'statoRendicontazione'=>'stato_rendicontazione','noteRendicontazione'=>'note_rendicontazione',
        'customFields'=>'custom_fields',
    ];
    $dateFields = ['bando_deadline','scadenza_presentazione','scadenza_operativa',
                   'data_stato','termine_rendicontazione'];
    $sets = []; $vals = [];
    foreach ($b as $k => $v) {
        if (!isset($map[$k])) continue;
        $col = $map[$k];
        if ($col === 'custom_fields' && !opportunities_has_custom_fields_column()) continue;
        $sets[] = "$col = ?";
        if (in_array($col, $dateFields)) $v = to_date($v);
        if ($col === 'custom_fields') $v = json_encode((object)($v ?? []));
        $vals[] = $v;
    }
    if (empty($sets)) json_error('Nessun campo');
    $vals[] = $id;
    $vals = array_merge($vals, $scope['params']);
    db()->prepare('UPDATE opportunities SET ' . implode(',', $sets) . ' WHERE id=? AND ' . $scope['sql'])
       ->execute($vals);
    json_ok(['ok' => true]);
}

if ($method === 'DELETE') {
    if (!$id) json_error('id mancante');
    db()->prepare('DELETE FROM opportunities WHERE id=? AND ' . $scope['sql'])
       ->execute(array_merge([$id], $scope['params']));
    json_ok(['ok' => true]);
}

json_error('Metodo non consentito', 405);
