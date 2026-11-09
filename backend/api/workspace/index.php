<?php
// GET /api/workspace/index.php
// Restituisce l'intero WorkspaceSnapshot. Ogni sezione ha il suo try-catch
// per essere resiliente a tabelle mancanti o errori parziali.

require_once __DIR__ . '/../bootstrap.php';

if (http_method() !== 'GET') json_error('Metodo non consentito', 405);

$userId = require_auth();
$scope = scope_filter_sql('user_id', scoped_user_ids($userId));

// Esegue una query e restituisce array vuoto in caso di errore
function safe_fetch(string $sql, array $params = []): array {
    try {
        return db()->prepare($sql)->execute($params) ? db()->prepare($sql)->execute($params)
            ? (function($sql, $params) {
                $st = db()->prepare($sql);
                $st->execute($params);
                return $st->fetchAll();
            })($sql, $params)
            : []
            : [];
    } catch (Throwable $e) {
        return [];
    }
}

// Versione più leggibile
function qry(string $sql, array $params = []): array {
    try {
        $st = db()->prepare($sql);
        $st->execute($params);
        return $st->fetchAll();
    } catch (Throwable $e) {
        // Tabella non trovata o altro errore — restituisce vuoto
        return [];
    }
}

// ── Companies ─────────────────────────────────────────────────────────────────
$companies = array_map(function($r) {
    return [
        'id'                    => $r['id'],
        'name'                  => $r['name'],
        'vatNumber'             => $r['vat_number'],
        'taxCode'               => $r['tax_code'],
        'pec'                   => $r['pec'],
        'sdiCode'               => $r['sdi_code'],
        'email'                 => $r['email'],
        'phone'                 => $r['phone'],
        'website'               => $r['website'],
        'addressLine'           => $r['address_line'],
        'city'                  => $r['city'],
        'postalCode'            => $r['postal_code'],
        'country'               => $r['country'],
        'contactPerson'         => $r['contact_person'],
        'notes'                 => $r['notes'],
        'isNonProfit'           => (bool)$r['is_non_profit'],
        'annualRevenue'         => $r['annual_revenue'] !== null ? (float)$r['annual_revenue'] : null,
        'employeesCount'        => $r['employees_count'] !== null ? (int)$r['employees_count'] : null,
        'legalRepresentative'   => $r['legal_representative'],
        'incorporationDate'     => from_date($r['incorporation_date'] ?? null),
        'companyType'           => $r['company_type'],
        'riferimentoInterno'    => $r['riferimento_interno'],
        'provincia'             => $r['provincia'],
        'regione'               => $r['regione'],
        'sedeOperativaVia'      => $r['sede_operativa_via'],
        'sedeOperativaCap'      => $r['sede_operativa_cap'],
        'sedeOperativaCitta'    => $r['sede_operativa_citta'],
        'sedeOperativaProvincia'=> $r['sede_operativa_provincia'],
        'sedeOperativaRegione'  => $r['sede_operativa_regione'],
        'atecoPrimario'         => $r['ateco_primario'],
        'atecoSecondario'       => $r['ateco_secondario'],
        'atecoTerziario'        => $r['ateco_terziario'],
        'dimensioneImpresa'     => $r['dimensione_impresa'],
        'ula'                   => $r['ula'] !== null ? (int)$r['ula'] : null,
        'export'                => (bool)$r['export_azienda'],
        'controllata'           => (bool)($r['controllata'] ?? 0),
        'controllante'          => (bool)($r['controllante'] ?? 0),
        'areeInvestimento'      => json_col($r['aree_investimento'] ?? null, []),
        'ricaviAnnui'           => (object)(json_col($r['ricavi_annui'] ?? null, []) ?: []),
        'customFields'          => json_col($r['custom_fields'] ?? null, []),
        'createdAt'             => from_dt($r['created_at'] ?? null),
    ];
}, qry('SELECT * FROM companies WHERE ' . $scope['sql'], $scope['params']));

// ── Company Contacts ──────────────────────────────────────────────────────────
$companyContacts = array_map(function($r) {
    return [
        'id'        => $r['id'],
        'companyId' => $r['company_id'] ?? '',
        'name'      => $r['name'],
        'email'     => $r['email'],
        'phone'     => $r['phone'],
        'role'      => $r['role'],
        'customFields' => json_col($r['custom_fields'] ?? null, []),
        'createdAt' => from_dt($r['created_at'] ?? null),
    ];
}, qry('SELECT * FROM company_contacts WHERE ' . $scope['sql'], $scope['params']));

// ── Opportunities ─────────────────────────────────────────────────────────────
$opportunities = array_map(function($r) {
    return [
        'id'                               => $r['id'],
        'companyId'                        => $r['company_id'] ?? '',
        'title'                            => $r['title'],
        'status'                           => $r['status'],
        'bandoReference'                   => $r['bando_reference'],
        'bandoSource'                      => $r['bando_source'],
        'bandoDeadline'                    => from_date($r['bando_deadline'] ?? null),
        'estimatedValue'                   => $r['estimated_value'] !== null ? (float)$r['estimated_value'] : null,
        'notes'                            => $r['notes'],
        'assignedAnalystId'                => $r['assigned_analyst_id'] ?? null,
        'contactId'                        => $r['contact_id'] ?? null,
        'rifOfferta'                       => $r['rif_offerta'],
        'contattoCommerciale'              => $r['contatto_commerciale'],
        'presaInCarico'                    => (bool)$r['presa_in_carico'],
        'daFaturareA'                      => $r['da_faturare_a'],
        'partnerCommerciale'               => $r['partner_commerciale'],
        'fornitore'                        => $r['fornitore'],
        'scadenzaPresentazione'            => from_date($r['scadenza_presentazione'] ?? null),
        'scadenzaOperativa'                => from_date($r['scadenza_operativa'] ?? null),
        'avanzamentoPratica'               => $r['avanzamento_pratica'],
        'esitoPratica'                     => $r['esito_pratica'],
        'dataStato'                        => from_date($r['data_stato'] ?? null),
        'totaleProgetto'                   => $r['totale_progetto'] !== null ? (float)$r['totale_progetto'] : null,
        'contributoRichiesto'              => $r['contributo_richiesto'] !== null ? (float)$r['contributo_richiesto'] : null,
        'contributoRicevuto'               => $r['contributo_ricevuto'] !== null ? (float)$r['contributo_ricevuto'] : null,
        'finanziamentoRichiesto'           => $r['finanziamento_richiesto'] !== null ? (float)$r['finanziamento_richiesto'] : null,
        'garanziaRichiesta'                => $r['garanzia_richiesta'] !== null ? (float)$r['garanzia_richiesta'] : null,
        'creditoImpostaRichiesto'          => $r['credito_imposta_richiesto'] !== null ? (float)$r['credito_imposta_richiesto'] : null,
        'totaleProgettoRidefinito'         => $r['totale_progetto_ridefinito'] !== null ? (float)$r['totale_progetto_ridefinito'] : null,
        'totaleBeneficioEconomicoRicevuto' => $r['totale_beneficio_economico_ricevuto'] !== null ? (float)$r['totale_beneficio_economico_ricevuto'] : null,
        'termineRendicontazione'           => from_date($r['termine_rendicontazione'] ?? null),
        'statoRendicontazione'             => $r['stato_rendicontazione'],
        'noteRendicontazione'              => $r['note_rendicontazione'],
        'customFields'                     => json_col($r['custom_fields'] ?? null, []),
        'createdAt'                        => from_dt($r['created_at'] ?? null),
        'updatedAt'                        => from_dt($r['updated_at'] ?? null),
    ];
}, qry('SELECT * FROM opportunities WHERE ' . $scope['sql'], $scope['params']));

// ── Preventivi ────────────────────────────────────────────────────────────────
$gussoniQuotations = array_map(function($r) {
    return [
        'id'                => $r['id'],
        'opportunityId'     => $r['opportunity_id'] ?? '',
        'companyId'         => $r['company_id'] ?? '',
        'status'            => $r['status'],
        'lines'             => json_col($r['lines'] ?? null, []),
        'istruttoriaFee'    => (float)$r['istruttoria_fee'],
        'successFeePercent' => $r['success_fee_percent'] !== null ? (float)$r['success_fee_percent'] : null,
        'notes'             => $r['notes'],
        'linkedProjectId'   => $r['linked_project_id'] ?? null,
        'sentAt'            => from_dt($r['sent_at'] ?? null),
        'createdAt'         => from_dt($r['created_at'] ?? null),
    ];
}, qry('SELECT * FROM preventivi WHERE ' . $scope['sql'], $scope['params']));

// ── Projects ──────────────────────────────────────────────────────────────────
$projects = array_map(function($r) {
    return [
        'id'                    => $r['id'],
        'companyId'             => $r['company_id'] ?? '',
        'name'                  => $r['name'],
        'code'                  => $r['code'],
        'status'                => $r['status'],
        'type'                  => $r['type'],
        'opportunityId'         => $r['opportunity_id'] ?? null,
        'quotationId'           => $r['quotation_id'] ?? null,
        'grantAmount'           => $r['grant_amount'] !== null ? (float)$r['grant_amount'] : null,
        'successFeeAmount'      => $r['success_fee_amount'] !== null ? (float)$r['success_fee_amount'] : null,
        'notes'                 => $r['notes'],
        'anticipoEmesso'        => (bool)$r['anticipo_emesso'],
        'rifProgetto'           => $r['rif_progetto'],
        'rifCaricamento'        => $r['rif_caricamento'],
        'idProgettoEsterno'     => $r['id_progetto_esterno'],
        'titoloProgetto'        => $r['titolo_progetto'],
        'dataInizioProgetto'    => from_date($r['data_inizio_progetto'] ?? null),
        'dataFineProgetto'      => from_date($r['data_fine_progetto'] ?? null),
        'daFaturareA'           => $r['da_faturare_a'],
        'avanzamentoPratica'    => $r['avanzamento_pratica'],
        'esitoPratica'          => $r['esito_pratica'],
        'statoRendicontazione'  => $r['stato_rendicontazione'],
        'termineRendicontazione'=> from_date($r['termine_rendicontazione'] ?? null),
        'customFields'          => json_col($r['custom_fields'] ?? null, []),
        'createdAt'             => from_dt($r['created_at'] ?? null),
        'closedAt'              => from_dt($r['closed_at'] ?? null),
    ];
}, qry('SELECT * FROM projects WHERE ' . $scope['sql'], $scope['params']));

// ── Phases ────────────────────────────────────────────────────────────────────
$phases = array_map(function($r) {
    return [
        'id'             => $r['id'],
        'projectId'      => $r['project_id'],
        'name'           => $r['name'],
        'order'          => (int)$r['phase_order'],
        'status'         => $r['status'],
        'assignedUserId' => $r['assigned_user_id'] ?? null,
        'startDate'      => from_date($r['start_date'] ?? null),
        'deadline'       => from_date($r['deadline'] ?? null),
        'notes'          => $r['notes'],
        'isCustom'       => (bool)$r['is_custom'],
    ];
}, qry('SELECT * FROM project_phases WHERE ' . $scope['sql'] . ' ORDER BY project_id, phase_order', $scope['params']));

// ── Tasks ─────────────────────────────────────────────────────────────────────
$tasks = array_map(function($r) {
    return [
        'id'             => $r['id'],
        'companyId'      => $r['company_id'],
        'projectId'      => $r['project_id'],
        'phaseId'        => $r['phase_id'],
        'assigneeId'     => $r['assignee_id'],
        'name'           => $r['name'],
        'estimatedHours' => (float)$r['estimated_hours'],
        'loggedHours'    => (float)$r['logged_hours'],
        'startDate'      => from_date($r['start_date'] ?? null),
        'deadline'       => from_date($r['deadline'] ?? null),
        'status'         => $r['status'],
        'billable'       => (bool)$r['billable'],
        'description'    => $r['description'] ?? '',
        'createdAt'      => from_dt($r['created_at'] ?? null),
    ];
}, qry('SELECT * FROM work_tasks WHERE ' . $scope['sql'], $scope['params']));

// ── Timeline Slots ────────────────────────────────────────────────────────────
$plannedSlots = array_map(function($r) {
    return [
        'id'           => $r['id'],
        'taskId'       => $r['task_id'],
        'date'         => from_date($r['slot_date'] ?? null),
        'plannedHours' => (float)$r['planned_hours'],
        'startHour'    => (float)$r['start_hour'],
    ];
}, qry('SELECT * FROM timeline_slots WHERE ' . $scope['sql'], $scope['params']));

// ── Time Tracks ───────────────────────────────────────────────────────────────
$timeTracks = array_map(function($r) {
    return [
        'id'          => $r['id'],
        'taskId'      => $r['task_id'],
        'name'        => $r['name'],
        'companyId'   => $r['company_id'],
        'projectId'   => $r['project_id'],
        'startAt'     => from_dt($r['start_at'] ?? null),
        'endAt'       => from_dt($r['end_at'] ?? null),
        'userId'      => $r['tracker_user_id'],
        'description' => $r['description'],
        'billable'    => (bool)$r['billable'],
        'tipo'        => $r['tipo'],
        'hourlyRate'  => $r['hourly_rate'] !== null ? (float)$r['hourly_rate'] : null,
    ];
}, qry('SELECT * FROM time_tracks WHERE ' . $scope['sql'], $scope['params']));

// ── Invoices ──────────────────────────────────────────────────────────────────
$invoiceDrafts = array_map(function($r) {
    return [
        'id'          => $r['id'],
        'companyId'   => $r['company_id'],
        'number'      => $r['number'],
        'amount'      => (float)$r['amount'],
        'status'      => $r['status'],
        'projectId'   => $r['project_id'] ?? null,
        'lines'       => json_col($r['lines'] ?? null, []),
        'isSuccessFee'=> (bool)$r['is_success_fee'],
        'grantAmount' => $r['grant_amount'] !== null ? (float)$r['grant_amount'] : null,
        'notes'       => $r['notes'],
        'sentAt'      => from_dt($r['sent_at'] ?? null),
        'createdAt'   => from_dt($r['created_at'] ?? null),
    ];
}, qry('SELECT * FROM invoice_drafts WHERE ' . $scope['sql'], $scope['params']));

// ── Tickets ───────────────────────────────────────────────────────────────────
$tickets = array_map(function($r) {
    return [
        'id'             => $r['id'],
        'companyId'      => $r['company_id'],
        'title'          => $r['title'],
        'recipientEmail' => $r['recipient_email'],
        'status'         => $r['status'],
        'entries'        => json_col($r['entries'] ?? null, []),
        'createdAt'      => from_dt($r['created_at'] ?? null),
        'updatedAt'      => from_dt($r['updated_at'] ?? null),
    ];
}, qry('SELECT * FROM tickets WHERE ' . $scope['sql'], $scope['params']));

// ── Availability ──────────────────────────────────────────────────────────────
$availability = array_map(function($r) {
    return [
        'weekday' => (int)$r['weekday'],
        'hours'   => (float)$r['hours'],
        'isOff'   => (bool)$r['is_off'],
    ];
}, qry('SELECT * FROM user_availability WHERE user_id = ? ORDER BY weekday', [$userId]));

// ── Vacations ─────────────────────────────────────────────────────────────────
$vacations = array_map(function($r) {
    return [
        'id'        => $r['id'],
        'startDate' => from_date($r['start_date'] ?? null),
        'endDate'   => from_date($r['end_date'] ?? null),
        'label'     => $r['label'],
    ];
}, qry('SELECT * FROM vacation_periods WHERE user_id = ?', [$userId]));

// ── User / Billing ────────────────────────────────────────────────────────────
$billingProfile     = (object)[];
$youdoxConfig       = (object)[];
$emailSignatureHtml = '';

try {
    $userStmt = db()->prepare('SELECT * FROM users WHERE id = ? LIMIT 1');
    $userStmt->execute([$userId]);
    $userRow = $userStmt->fetch() ?: [];

    $billingProfile     = (object)(json_col($userRow['billing_profile'] ?? null, []) ?: []);
    $youdoxConfig       = (object)(json_col($userRow['youdox_config'] ?? null, []) ?: []);
    $emailSignatureHtml = $userRow['email_signature_html'] ?? '';

    $teamId = $userRow['team_id'] ?? null;
    if ($teamId) {
        $teamStmt = db()->prepare('SELECT billing_profile, youdox_config FROM teams WHERE id = ? LIMIT 1');
        $teamStmt->execute([$teamId]);
        $teamRow = $teamStmt->fetch() ?: [];
        if (!empty($teamRow['billing_profile']))
            $billingProfile = (object)(json_col($teamRow['billing_profile'], []) ?: []);
        if (!empty($teamRow['youdox_config']))
            $youdoxConfig = (object)(json_col($teamRow['youdox_config'], []) ?: []);
    }
} catch (Throwable $e) {
    // fallback valori vuoti
}

// ── Risposta ──────────────────────────────────────────────────────────────────
json_ok([
    'companies'         => $companies,
    'companyContacts'   => $companyContacts,
    'opportunities'     => $opportunities,
    'gussoniQuotations' => $gussoniQuotations,
    'projects'          => $projects,
    'phases'            => $phases,
    'tasks'             => $tasks,
    'plannedSlots'      => $plannedSlots,
    'timeTracks'        => $timeTracks,
    'invoiceDrafts'     => $invoiceDrafts,
    'tickets'           => $tickets,
    'availability'      => $availability,
    'vacations'         => $vacations,
    'billingProfile'    => $billingProfile,
    'youdoxConfig'      => $youdoxConfig,
    'emailSignatureHtml'=> $emailSignatureHtml,
]);
