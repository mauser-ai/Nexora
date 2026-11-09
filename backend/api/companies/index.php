<?php
// GET    /api/companies/        → lista
// POST   /api/companies/        → crea
// PUT    /api/companies/?id=... → aggiorna
// DELETE /api/companies/?id=... → elimina

require_once __DIR__ . '/../bootstrap.php';

ob_start();

function companies_json_fail(string $message, int $code = 500): void {
    while (ob_get_level() > 0) {
        ob_end_clean();
    }
    http_response_code($code);
    header('Content-Type: application/json; charset=utf-8');
    echo json_encode(['error' => $message], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
    exit;
}

set_exception_handler(function ($e): void {
    companies_json_fail('Errore companies API: ' . $e->getMessage(), 500);
});

register_shutdown_function(function (): void {
    $error = error_get_last();
    if ($error === null) {
        return;
    }
    $fatalTypes = [E_ERROR, E_PARSE, E_CORE_ERROR, E_COMPILE_ERROR];
    if (in_array((int)$error['type'], $fatalTypes, true)) {
        companies_json_fail(
            'Errore PHP companies API: ' . ($error['message'] ?? 'fatal error'),
            500
        );
    }
});

function companies_has_custom_fields_column(): bool {
    static $hasColumn = null;
    if ($hasColumn !== null) return $hasColumn;
    try {
        $st = db()->query("SHOW COLUMNS FROM companies LIKE 'custom_fields'");
        $hasColumn = (bool)$st->fetch();
    } catch (Throwable $e) {
        $hasColumn = false;
    }
    return $hasColumn;
}

function companies_columns(): array {
    static $columns = null;
    if ($columns !== null) return $columns;
    $columns = [];
    try {
        $rows = db()->query('SHOW COLUMNS FROM companies')->fetchAll();
        foreach ($rows as $row) {
            $field = $row['Field'] ?? null;
            if (is_string($field) && $field !== '') {
                $columns[$field] = true;
            }
        }
    } catch (Throwable $e) {
        $columns = [];
    }
    return $columns;
}

$userId = require_auth();
$scope = scope_filter_sql('user_id', scoped_user_ids($userId));
$method = http_method();
$id     = $_GET['id'] ?? null;

if ($method === 'GET') {
    $rows = db()->prepare('SELECT * FROM companies WHERE ' . $scope['sql'] . ' ORDER BY name');
    $rows->execute($scope['params']);
    json_ok($rows->fetchAll());
}

if ($method === 'POST') {
    $b  = request_body();
    $id = str_val($b['id'] ?? uuid4());
    $payloadMap = [
        'id' => $id,
        'user_id' => $userId,
        'name' => str_val($b['name'] ?? ''),
        'vat_number' => str_val($b['vatNumber'] ?? ''),
        'tax_code' => str_val($b['taxCode'] ?? ''),
        'pec' => str_val($b['pec'] ?? ''),
        'sdi_code' => str_val($b['sdiCode'] ?? ''),
        'email' => str_val($b['email'] ?? ''),
        'phone' => str_val($b['phone'] ?? ''),
        'website' => str_val($b['website'] ?? ''),
        'address_line' => str_val($b['addressLine'] ?? ''),
        'city' => str_val($b['city'] ?? ''),
        'postal_code' => str_val($b['postalCode'] ?? ''),
        'country' => str_val($b['country'] ?? 'IT'),
        'contact_person' => str_val($b['contactPerson'] ?? ''),
        'notes' => str_val($b['notes'] ?? ''),
        'is_non_profit' => bool_val($b['isNonProfit'] ?? false) ? 1 : 0,
        'annual_revenue' => float_val($b['annualRevenue'] ?? null),
        'employees_count' => int_val($b['employeesCount'] ?? null),
        'legal_representative' => str_val($b['legalRepresentative'] ?? ''),
        'company_type' => str_val($b['companyType'] ?? 'profit'),
        'riferimento_interno' => str_val($b['riferimentoInterno'] ?? ''),
        'provincia' => str_val($b['provincia'] ?? ''),
        'regione' => str_val($b['regione'] ?? ''),
        'sede_operativa_via' => str_val($b['sedeOperativaVia'] ?? ''),
        'sede_operativa_cap' => str_val($b['sedeOperativaCap'] ?? ''),
        'sede_operativa_citta' => str_val($b['sedeOperativaCitta'] ?? ''),
        'sede_operativa_provincia' => str_val($b['sedeOperativaProvincia'] ?? ''),
        'sede_operativa_regione' => str_val($b['sedeOperativaRegione'] ?? ''),
        'ateco_primario' => str_val($b['atecoPrimario'] ?? ''),
        'ateco_secondario' => str_val($b['atecoSecondario'] ?? ''),
        'ateco_terziario' => str_val($b['atecoTerziario'] ?? ''),
        'dimensione_impresa' => ($b['dimensioneImpresa'] ?? null),
        'ula' => int_val($b['ula'] ?? null),
        'export_azienda' => bool_val($b['export'] ?? false) ? 1 : 0,
        'aree_investimento' => json_encode($b['areeInvestimento'] ?? []),
        'ricavi_annui' => json_encode((object)($b['ricaviAnnui'] ?? [])),
        'custom_fields' => json_encode((object)($b['customFields'] ?? [])),
    ];
    $available = companies_columns();
    $columns = [];
    $params = [];
    foreach ($payloadMap as $column => $value) {
        if (!isset($available[$column])) continue;
        if ($column === 'custom_fields' && !companies_has_custom_fields_column()) continue;
        $columns[] = $column;
        $params[] = $value;
    }
    if (empty($columns)) {
        json_error('Schema companies non leggibile o non compatibile.', 500);
    }
    $placeholders = implode(',', array_fill(0, count($columns), '?'));
    $sql = 'INSERT INTO companies (' . implode(',', $columns) . ') VALUES (' . $placeholders . ')';
    db()->prepare($sql)->execute($params);
    json_ok(['id' => $id], 201);
}

if ($method === 'PUT' || $method === 'PATCH') {
    if (!$id) json_error('id mancante');
    $b = request_body();
    // Aggiornamento dinamico solo dei campi inviati
    $allowed = ['name','vat_number','tax_code','pec','sdi_code','email','phone','website',
                 'address_line','city','postal_code','country','contact_person','notes',
                 'is_non_profit','annual_revenue','employees_count','legal_representative',
                 'company_type','riferimento_interno','provincia','regione',
                 'sede_operativa_via','sede_operativa_cap','sede_operativa_citta',
                 'sede_operativa_provincia','sede_operativa_regione',
                 'ateco_primario','ateco_secondario','ateco_terziario',
                 'dimensione_impresa','ula','export_azienda','aree_investimento','ricavi_annui',
                 'custom_fields'];
    // Mappa camelCase → snake_case
    $camelMap = ['vatNumber'=>'vat_number','taxCode'=>'tax_code','sdiCode'=>'sdi_code',
                  'addressLine'=>'address_line','postalCode'=>'postal_code','contactPerson'=>'contact_person',
                  'isNonProfit'=>'is_non_profit','annualRevenue'=>'annual_revenue','employeesCount'=>'employees_count',
                  'legalRepresentative'=>'legal_representative','companyType'=>'company_type',
                  'riferimentoInterno'=>'riferimento_interno','sedeOperativaVia'=>'sede_operativa_via',
                  'sedeOperativaCap'=>'sede_operativa_cap','sedeOperativaCitta'=>'sede_operativa_citta',
                  'sedeOperativaProvincia'=>'sede_operativa_provincia','sedeOperativaRegione'=>'sede_operativa_regione',
                  'atecoPrimario'=>'ateco_primario','atecoSecondario'=>'ateco_secondario','atecoTerziario'=>'ateco_terziario',
                  'dimensioneImpresa'=>'dimensione_impresa','exportAzienda'=>'export_azienda',
                  'areeInvestimento'=>'aree_investimento','ricaviAnnui'=>'ricavi_annui',
                  'customFields'=>'custom_fields'];
    $sets = []; $vals = [];
    foreach ($b as $k => $v) {
        $col = $camelMap[$k] ?? $k;
        if (!in_array($col, $allowed)) continue;
        if ($col === 'custom_fields' && !companies_has_custom_fields_column()) continue;
        $sets[] = "$col = ?";
        if ($col === 'aree_investimento') $v = json_encode(array_values((array)$v));
        elseif ($col === 'ricavi_annui' || $col === 'custom_fields') $v = json_encode((object)$v);
        $vals[] = $v;
    }
    if (empty($sets)) json_error('Nessun campo da aggiornare');
    $vals[] = $id;
    $vals = array_merge($vals, $scope['params']);
    db()->prepare('UPDATE companies SET ' . implode(',', $sets) . ' WHERE id=? AND ' . $scope['sql'])
       ->execute($vals);
    json_ok(['ok' => true]);
}

if ($method === 'DELETE') {
    if (!$id) json_error('id mancante');
    db()->prepare('DELETE FROM companies WHERE id=? AND ' . $scope['sql'])
       ->execute(array_merge([$id], $scope['params']));
    json_ok(['ok' => true]);
}

json_error('Metodo non consentito', 405);
