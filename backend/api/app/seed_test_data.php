<?php
declare(strict_types=1);

require_once dirname(__DIR__) . '/config.php';

header('Content-Type: application/json; charset=utf-8');

const SEED_TEAM_ID = 'team-Zbcvy7UyFuR2iS1dQR9Z';
const SEED_USER_ID = 'Zbcvy7UyFuR2iS1dQR9ZVi56Ga93';
const SEED_KEY = 'nexora-seed-test-2026-06-16';

if (((string)($_GET['key'] ?? '')) !== SEED_KEY) {
    http_response_code(403);
    echo json_encode(['error' => 'Chiave manutenzione non valida.']);
    exit;
}

function seed_db(): PDO
{
    static $pdo = null;
    if ($pdo instanceof PDO) {
        return $pdo;
    }
    $pdo = new PDO(
        sprintf('mysql:host=%s;port=%s;dbname=%s;charset=%s', DB_HOST, DB_PORT, DB_NAME, DB_CHARSET),
        DB_USER,
        DB_PASS,
        [
            PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
            PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
            PDO::ATTR_EMULATE_PREPARES => false,
        ]
    );
    return $pdo;
}

function seed_table_columns(PDO $pdo, string $table): array
{
    static $cache = [];
    if (isset($cache[$table])) {
        return $cache[$table];
    }
    $stmt = $pdo->query('SHOW COLUMNS FROM `' . str_replace('`', '``', $table) . '`');
    $rows = $stmt ? $stmt->fetchAll(PDO::FETCH_ASSOC) : [];
    return $cache[$table] = array_values(array_filter(array_map(
        static fn(array $row) => (string)($row['Field'] ?? ''),
        $rows
    )));
}

function seed_prepare_upsert(PDO $pdo, string $table, array $columns): PDOStatement
{
    $available = array_flip(seed_table_columns($pdo, $table));
    $filtered = array_values(array_filter($columns, static fn(string $column) => isset($available[$column])));
    if ($filtered === []) {
        throw new RuntimeException('Nessuna colonna valida per la tabella ' . $table);
    }
    $escapedColumns = array_map(
        static fn(string $column) => '`' . str_replace('`', '``', $column) . '`',
        $filtered
    );
    $placeholders = array_map(
        static fn(string $column) => ':' . $column,
        $filtered
    );
    $updates = [];
    foreach ($filtered as $column) {
        if ($column === 'id') {
            continue;
        }
        $escaped = '`' . str_replace('`', '``', $column) . '`';
        $updates[] = $escaped . '=VALUES(' . $escaped . ')';
    }
    $sql = 'INSERT INTO `' . $table . '` (' . implode(',', $escapedColumns) . ') VALUES (' . implode(',', $placeholders) . ')';
    if ($updates !== []) {
        $sql .= ' ON DUPLICATE KEY UPDATE ' . implode(',', $updates);
    }
    return $pdo->prepare($sql);
}

function seed_filter_params(array $params, array $allowedColumns): array
{
    $allowed = array_flip($allowedColumns);
    $filtered = [];
    foreach ($params as $key => $value) {
        $column = ltrim((string)$key, ':');
        if (isset($allowed[$column])) {
            $filtered[':' . $column] = $value;
        }
    }
    return $filtered;
}

function seed_upsert(PDO $pdo, string $table, array $payload): int
{
    $columns = seed_table_columns($pdo, $table);
    $filteredPayload = [];
    foreach ($payload as $key => $value) {
        if (in_array($key, $columns, true)) {
            $filteredPayload[$key] = $value;
        }
    }
    if ($filteredPayload === []) {
        throw new RuntimeException('Nessun campo compatibile per la tabella ' . $table);
    }
    $stmt = seed_prepare_upsert($pdo, $table, array_keys($filteredPayload));
    $params = [];
    foreach ($filteredPayload as $key => $value) {
        $params[':' . $key] = $value;
    }
    $stmt->execute($params);
    return $stmt->rowCount();
}

function seed_dt(string $modifier): string
{
    return (new DateTimeImmutable($modifier))->format('Y-m-d H:i:s');
}

function seed_d(string $modifier): string
{
    return (new DateTimeImmutable($modifier))->format('Y-m-d');
}

function seed_json($value): string
{
    return json_encode($value, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES) ?: '{}';
}

try {
    $pdo = seed_db();

    $teamStmt = $pdo->prepare('SELECT id, name FROM teams WHERE id = ? LIMIT 1');
    $teamStmt->execute([SEED_TEAM_ID]);
    $team = $teamStmt->fetch();
    if (!$team) {
        throw new RuntimeException('Team non trovato: ' . SEED_TEAM_ID);
    }

    $userStmt = $pdo->prepare('SELECT id, email, display_name FROM users WHERE id = ? LIMIT 1');
    $userStmt->execute([SEED_USER_ID]);
    $user = $userStmt->fetch();
    if (!$user) {
        throw new RuntimeException('Utente non trovato in users: ' . SEED_USER_ID);
    }

    $memberStmt = $pdo->prepare(
        "SELECT user_id FROM team_members
         WHERE team_id = ? AND user_id = ? AND status = 'active'
         LIMIT 1"
    );
    $memberStmt->execute([SEED_TEAM_ID, SEED_USER_ID]);
    if (!$memberStmt->fetchColumn()) {
        throw new RuntimeException('L’utente non risulta membro attivo del team indicato.');
    }

    $summary = [
        'ok' => true,
        'team' => [
            'id' => SEED_TEAM_ID,
            'name' => (string)($team['name'] ?? ''),
        ],
        'user' => [
            'id' => SEED_USER_ID,
            'email' => (string)($user['email'] ?? ''),
            'displayName' => (string)($user['display_name'] ?? ''),
        ],
        'tables' => [
            'companies' => 0,
            'company_contacts' => 0,
            'crm_contacts' => 0,
            'opportunities' => 0,
            'preventivi' => 0,
            'projects' => 0,
            'project_phases' => 0,
            'work_tasks' => 0,
            'time_tracks' => 0,
            'document_templates' => 0,
            'email_templates' => 0,
            'template_choices' => 0,
            'memos' => 0,
        ],
    ];

    $pdo->beginTransaction();

    $companyA = 'a1000000-0000-4000-8000-000000000001';
    $companyB = 'a1000000-0000-4000-8000-000000000002';
    $companyC = 'a1000000-0000-4000-8000-000000000003';

    $summary['tables']['companies'] += seed_upsert($pdo, 'companies', [
        'id' => $companyA,
        'user_id' => SEED_USER_ID,
        'name' => 'Alpine Growth SRL',
        'vat_number' => 'IT03124570987',
        'email' => 'operations@alpinegrowth.it',
        'phone' => '+39 02 8295 4401',
        'website' => 'https://alpinegrowth.it',
        'address_line' => 'Via San Marco 21',
        'city' => 'Milano',
        'postal_code' => '20121',
        'country' => 'IT',
        'notes' => 'Cliente B2B focalizzato su innovazione e incentivi.',
        'company_type' => 'profit',
        'provincia' => 'MI',
        'regione' => 'Lombardia',
        'dimensione_impresa' => 'media',
        'export_azienda' => 0,
        'aree_investimento' => seed_json(['Digitalizzazione', 'Ricerca', 'Marketing']),
        'ricavi_annui' => seed_json(['2024' => 1280000, '2025' => 1540000]),
    ]);
    $summary['tables']['companies'] += seed_upsert($pdo, 'companies', [
        'id' => $companyB,
        'user_id' => SEED_USER_ID,
        'name' => 'Verde Quota Studio',
        'vat_number' => 'IT02841230964',
        'email' => 'amministrazione@verdequota.it',
        'phone' => '+39 049 782 1102',
        'website' => 'https://verdequota.it',
        'address_line' => 'Via Altinate 88',
        'city' => 'Padova',
        'postal_code' => '35121',
        'country' => 'IT',
        'notes' => 'Studio professionale con focus finanza agevolata.',
        'company_type' => 'profit',
        'provincia' => 'PD',
        'regione' => 'Veneto',
        'dimensione_impresa' => 'piccola',
        'export_azienda' => 0,
        'aree_investimento' => seed_json(['Consulenza', 'Bandi', 'Operatività']),
        'ricavi_annui' => seed_json(['2024' => 420000, '2025' => 510000]),
    ]);
    $summary['tables']['companies'] += seed_upsert($pdo, 'companies', [
        'id' => $companyC,
        'user_id' => SEED_USER_ID,
        'name' => 'Northwind Labs SPA',
        'vat_number' => 'IT01764550211',
        'email' => 'hello@northwindlabs.eu',
        'phone' => '+39 045 1112 330',
        'website' => 'https://northwindlabs.eu',
        'address_line' => 'Piazza Bra 12',
        'city' => 'Verona',
        'postal_code' => '37121',
        'country' => 'IT',
        'notes' => 'Azienda tech con pipeline commerciale rapida.',
        'company_type' => 'profit',
        'provincia' => 'VR',
        'regione' => 'Veneto',
        'dimensione_impresa' => 'grande',
        'export_azienda' => 1,
        'aree_investimento' => seed_json(['AI', 'SaaS', 'Espansione']),
        'ricavi_annui' => seed_json(['2024' => 2800000, '2025' => 3360000]),
    ]);

    $contacts = [
        [
            'id' => 'b1000000-0000-4000-8000-000000000001',
            'company_id' => $companyA,
            'name' => 'Lucia Ferri',
            'email' => 'lucia.ferri@alpinegrowth.it',
            'phone' => '+39 348 880 1101',
            'role' => 'Operations Lead',
            'first_name' => 'Lucia',
            'last_name' => 'Ferri',
        ],
        [
            'id' => 'b1000000-0000-4000-8000-000000000002',
            'company_id' => $companyB,
            'name' => 'Marco Valenti',
            'email' => 'marco.valenti@verdequota.it',
            'phone' => '+39 349 220 4402',
            'role' => 'Founder',
            'first_name' => 'Marco',
            'last_name' => 'Valenti',
        ],
        [
            'id' => 'b1000000-0000-4000-8000-000000000003',
            'company_id' => $companyC,
            'name' => 'Elena Gori',
            'email' => 'elena.gori@northwindlabs.eu',
            'phone' => '+39 340 552 7788',
            'role' => 'Chief Innovation Officer',
            'first_name' => 'Elena',
            'last_name' => 'Gori',
        ],
    ];

    foreach ($contacts as $contact) {
        $summary['tables']['company_contacts'] += seed_upsert($pdo, 'company_contacts', [
            'id' => $contact['id'],
            'user_id' => SEED_USER_ID,
            'company_id' => $contact['company_id'],
            'name' => $contact['name'],
            'email' => $contact['email'],
            'phone' => $contact['phone'],
            'role' => $contact['role'],
        ]);
        $summary['tables']['crm_contacts'] += seed_upsert($pdo, 'crm_contacts', [
            'id' => $contact['id'],
            'user_id' => SEED_USER_ID,
            'first_name' => $contact['first_name'],
            'last_name' => $contact['last_name'],
            'company_id' => $contact['company_id'],
            'email' => $contact['email'],
            'phone' => $contact['phone'],
            'role' => $contact['role'],
            'tags' => seed_json(['test', 'seed']),
            'assigned_to' => SEED_USER_ID,
            'notes' => 'Contatto demo creato automaticamente.',
        ]);
    }

    $oppA = 'c1000000-0000-4000-8000-000000000001';
    $oppB = 'c1000000-0000-4000-8000-000000000002';
    $oppC = 'c1000000-0000-4000-8000-000000000003';

    $summary['tables']['opportunities'] += seed_upsert($pdo, 'opportunities', [
        'id' => $oppA,
        'user_id' => SEED_USER_ID,
        'company_id' => $companyA,
        'title' => 'Voucher digitale 2026 - Alpine Growth',
        'status' => 'preventivazione',
        'created_by_user_id' => SEED_USER_ID,
        'bando_reference' => 'BND-ALP-2026',
        'bando_source' => 'Unioncamere Lombardia',
        'bando_deadline' => seed_d('+25 days'),
        'estimated_value' => 18000.00,
        'notes' => 'Opportunità demo con focus su CRM e automazioni.',
        'assigned_analyst_id' => SEED_USER_ID,
        'contact_id' => $contacts[0]['id'],
        'rif_offerta' => 'OFF-ALP-01',
        'contatto_commerciale' => 'Lucia Ferri',
        'presa_in_carico' => 1,
        'scadenza_presentazione' => seed_d('+18 days'),
        'avanzamento_pratica' => 'presentata',
        'esito_pratica' => 'inAttesa',
    ]);
    $summary['tables']['opportunities'] += seed_upsert($pdo, 'opportunities', [
        'id' => $oppB,
        'user_id' => SEED_USER_ID,
        'company_id' => $companyB,
        'title' => 'Bando sostenibilità operativa - Verde Quota',
        'status' => 'inAttesa',
        'created_by_user_id' => SEED_USER_ID,
        'bando_reference' => 'BND-VQS-2026',
        'bando_source' => 'Regione Veneto',
        'bando_deadline' => seed_d('+42 days'),
        'estimated_value' => 9600.00,
        'notes' => 'Lead appena qualificato.',
        'assigned_analyst_id' => SEED_USER_ID,
        'contact_id' => $contacts[1]['id'],
        'rif_offerta' => 'OFF-VQS-01',
        'contatto_commerciale' => 'Marco Valenti',
        'presa_in_carico' => 0,
        'avanzamento_pratica' => 'none',
        'esito_pratica' => 'none',
    ]);
    $summary['tables']['opportunities'] += seed_upsert($pdo, 'opportunities', [
        'id' => $oppC,
        'user_id' => SEED_USER_ID,
        'company_id' => $companyC,
        'title' => 'Scale-up advisory 2026 - Northwind Labs',
        'status' => 'presaInCarico',
        'created_by_user_id' => SEED_USER_ID,
        'bando_reference' => 'BND-NWL-2026',
        'bando_source' => 'MIMIT',
        'bando_deadline' => seed_d('+60 days'),
        'estimated_value' => 32500.00,
        'notes' => 'Pipeline strategica enterprise.',
        'assigned_analyst_id' => SEED_USER_ID,
        'contact_id' => $contacts[2]['id'],
        'rif_offerta' => 'OFF-NWL-01',
        'contatto_commerciale' => 'Elena Gori',
        'presa_in_carico' => 1,
        'avanzamento_pratica' => 'inEsecuzione',
        'esito_pratica' => 'inAttesa',
    ]);

    $quoteA = 'd1000000-0000-4000-8000-000000000001';
    $quoteB = 'd1000000-0000-4000-8000-000000000002';
    $quoteC = 'd1000000-0000-4000-8000-000000000003';

    $summary['tables']['preventivi'] += seed_upsert($pdo, 'preventivi', [
        'id' => $quoteA,
        'user_id' => SEED_USER_ID,
        'opportunity_id' => $oppA,
        'company_id' => $companyA,
        'status' => 'sent',
        'lines' => seed_json([
            ['description' => 'Analisi bando e eligibility check', 'qty' => 1, 'price' => 1200],
            ['description' => 'Setup progetto e supporto presentazione', 'qty' => 1, 'price' => 4800],
        ]),
        'istruttoria_fee' => 4800,
        'success_fee_percent' => 6.5,
        'notes' => 'Preventivo demo già inviato.',
        'sent_at' => seed_dt('-2 days'),
        'expires_at' => seed_dt('+20 days'),
    ]);
    $summary['tables']['preventivi'] += seed_upsert($pdo, 'preventivi', [
        'id' => $quoteB,
        'user_id' => SEED_USER_ID,
        'opportunity_id' => $oppB,
        'company_id' => $companyB,
        'status' => 'draft',
        'lines' => seed_json([
            ['description' => 'Kickoff strategico', 'qty' => 1, 'price' => 900],
            ['description' => 'Redazione pratica completa', 'qty' => 1, 'price' => 2900],
        ]),
        'istruttoria_fee' => 2900,
        'success_fee_percent' => 5.0,
        'notes' => 'Bozza pronta da rifinire.',
    ]);
    $summary['tables']['preventivi'] += seed_upsert($pdo, 'preventivi', [
        'id' => $quoteC,
        'user_id' => SEED_USER_ID,
        'opportunity_id' => $oppC,
        'company_id' => $companyC,
        'status' => 'accepted',
        'lines' => seed_json([
            ['description' => 'Program management', 'qty' => 1, 'price' => 6500],
            ['description' => 'Supporto operativo trimestrale', 'qty' => 1, 'price' => 4200],
        ]),
        'istruttoria_fee' => 6500,
        'success_fee_percent' => 8.0,
        'notes' => 'Accettato, pronto a generare progetto.',
        'sent_at' => seed_dt('-10 days'),
        'accepted_at' => seed_dt('-6 days'),
    ]);

    $projectA = 'e1000000-0000-4000-8000-000000000001';
    $projectB = 'e1000000-0000-4000-8000-000000000002';

    $summary['tables']['projects'] += seed_upsert($pdo, 'projects', [
        'id' => $projectA,
        'user_id' => SEED_USER_ID,
        'company_id' => $companyA,
        'name' => 'Implementazione CRM Alpine Growth',
        'code' => 'NEX-ALP-26',
        'status' => 'active',
        'type' => 'profit',
        'opportunity_id' => $oppA,
        'quotation_id' => $quoteA,
        'grant_amount' => 12000.00,
        'notes' => 'Progetto seed attivo con piano task già popolato.',
        'titolo_progetto' => 'Digital CRM Enablement',
        'data_inizio_progetto' => seed_d('-14 days'),
        'data_fine_progetto' => seed_d('+90 days'),
        'totale_progetto' => 18000.00,
        'avanzamento_pratica' => 'inEsecuzione',
        'esito_pratica' => 'inAttesa',
    ]);
    $summary['tables']['projects'] += seed_upsert($pdo, 'projects', [
        'id' => $projectB,
        'user_id' => SEED_USER_ID,
        'company_id' => $companyC,
        'name' => 'Northwind Scale Program',
        'code' => 'NEX-NWL-26',
        'status' => 'planning',
        'type' => 'profit',
        'opportunity_id' => $oppC,
        'quotation_id' => $quoteC,
        'grant_amount' => 22500.00,
        'notes' => 'Programma enterprise in onboarding.',
        'titolo_progetto' => 'Scale-up Advisory Framework',
        'data_inizio_progetto' => seed_d('-5 days'),
        'data_fine_progetto' => seed_d('+120 days'),
        'totale_progetto' => 32500.00,
        'avanzamento_pratica' => 'presentata',
        'esito_pratica' => 'inAttesa',
    ]);

    $phases = [
        ['id' => 'f1000000-0000-4000-8000-000000000001', 'project_id' => $projectA, 'name' => 'Kickoff', 'phase_order' => 1, 'status' => 'done'],
        ['id' => 'f1000000-0000-4000-8000-000000000002', 'project_id' => $projectA, 'name' => 'Setup operativo', 'phase_order' => 2, 'status' => 'inProgress'],
        ['id' => 'f1000000-0000-4000-8000-000000000003', 'project_id' => $projectA, 'name' => 'Go-live', 'phase_order' => 3, 'status' => 'notStarted'],
        ['id' => 'f1000000-0000-4000-8000-000000000004', 'project_id' => $projectB, 'name' => 'Assessment', 'phase_order' => 1, 'status' => 'inProgress'],
        ['id' => 'f1000000-0000-4000-8000-000000000005', 'project_id' => $projectB, 'name' => 'Roadmap', 'phase_order' => 2, 'status' => 'notStarted'],
    ];
    foreach ($phases as $index => $phase) {
        $summary['tables']['project_phases'] += seed_upsert($pdo, 'project_phases', [
            'id' => $phase['id'],
            'user_id' => SEED_USER_ID,
            'project_id' => $phase['project_id'],
            'name' => $phase['name'],
            'phase_order' => $phase['phase_order'],
            'status' => $phase['status'],
            'assigned_user_id' => SEED_USER_ID,
            'start_date' => seed_d('+' . ($index * 3 - 10) . ' days'),
            'deadline' => seed_d('+' . ($index * 7 + 7) . ' days'),
            'notes' => 'Fase demo popolata automaticamente.',
            'is_custom' => 0,
        ]);
    }

    $tasks = [
        ['id' => '11000000-0000-4000-8000-000000000001', 'project_id' => $projectA, 'phase_id' => $phases[1]['id'], 'company_id' => $companyA, 'name' => 'Mappatura processi commerciali', 'status' => 'inProgress', 'estimated_hours' => 12, 'logged_hours' => 4],
        ['id' => '11000000-0000-4000-8000-000000000002', 'project_id' => $projectA, 'phase_id' => $phases[1]['id'], 'company_id' => $companyA, 'name' => 'Settaggio pipeline e automazioni', 'status' => 'planned', 'estimated_hours' => 18, 'logged_hours' => 0],
        ['id' => '11000000-0000-4000-8000-000000000003', 'project_id' => $projectB, 'phase_id' => $phases[3]['id'], 'company_id' => $companyC, 'name' => 'Analisi baseline KPI', 'status' => 'done', 'estimated_hours' => 6, 'logged_hours' => 6],
        ['id' => '11000000-0000-4000-8000-000000000004', 'project_id' => $projectB, 'phase_id' => $phases[4]['id'], 'company_id' => $companyC, 'name' => 'Roadmap espansione Q4', 'status' => 'backlog', 'estimated_hours' => 10, 'logged_hours' => 0],
    ];
    foreach ($tasks as $index => $task) {
        $summary['tables']['work_tasks'] += seed_upsert($pdo, 'work_tasks', [
            'id' => $task['id'],
            'user_id' => SEED_USER_ID,
            'company_id' => $task['company_id'],
            'project_id' => $task['project_id'],
            'phase_id' => $task['phase_id'],
            'assignee_id' => SEED_USER_ID,
            'name' => $task['name'],
            'estimated_hours' => $task['estimated_hours'],
            'logged_hours' => $task['logged_hours'],
            'start_date' => seed_d('+' . ($index - 7) . ' days'),
            'deadline' => seed_d('+' . ($index + 7) . ' days'),
            'status' => $task['status'],
            'billable' => 1,
            'description' => 'Task demo per verificare planning, listing e segnatempo.',
        ]);
    }

    $timeTracks = [
        ['id' => '12000000-0000-4000-8000-000000000001', 'task_id' => $tasks[0]['id'], 'project_id' => $projectA, 'company_id' => $companyA, 'name' => 'Analisi processi', 'start' => '-1 day 09:00', 'end' => '-1 day 11:15', 'billable' => 1],
        ['id' => '12000000-0000-4000-8000-000000000002', 'task_id' => $tasks[0]['id'], 'project_id' => $projectA, 'company_id' => $companyA, 'name' => 'Workshop interno', 'start' => '-1 day 14:00', 'end' => '-1 day 15:30', 'billable' => 1],
        ['id' => '12000000-0000-4000-8000-000000000003', 'task_id' => $tasks[2]['id'], 'project_id' => $projectB, 'company_id' => $companyC, 'name' => 'Raccolta KPI', 'start' => '-3 day 10:00', 'end' => '-3 day 12:00', 'billable' => 1],
    ];
    foreach ($timeTracks as $track) {
        $summary['tables']['time_tracks'] += seed_upsert($pdo, 'time_tracks', [
            'id' => $track['id'],
            'user_id' => SEED_USER_ID,
            'task_id' => $track['task_id'],
            'name' => $track['name'],
            'company_id' => $track['company_id'],
            'project_id' => $track['project_id'],
            'start_at' => seed_dt($track['start']),
            'end_at' => seed_dt($track['end']),
            'tracker_user_id' => SEED_USER_ID,
            'description' => 'Segnatempo demo auto-generato.',
            'billable' => $track['billable'],
            'tipo' => 'operativo',
            'hourly_rate' => 85.00,
        ]);
    }

    $docTemplateId = 'tpl-doc-seed-20260616-01';
    $mailTemplateId = 'tpl-mail-seed-20260616-01';
    $summary['tables']['document_templates'] += seed_upsert($pdo, 'document_templates', [
        'id' => $docTemplateId,
        'user_id' => SEED_USER_ID,
        'name' => 'Preventivo Nexora Demo',
        'category' => 'preventivo',
        'background_image_url' => '',
        'elements' => seed_json([
            ['type' => 'heading', 'label' => 'Preventivo demo Nexora'],
            ['type' => 'company', 'label' => 'Cliente'],
            ['type' => 'lines', 'label' => 'Voci economiche'],
        ]),
        'custom_fields' => seed_json([
            ['key' => 'project_owner', 'label' => 'Project owner'],
        ]),
    ]);
    $summary['tables']['email_templates'] += seed_upsert($pdo, 'email_templates', [
        'id' => $mailTemplateId,
        'user_id' => SEED_USER_ID,
        'name' => 'Invio preventivo demo',
        'category' => 'preventivo',
        'subject' => 'Preventivo {{company_name}} - Nexora',
        'body' => "Ciao {{contact_name}},\n\nin allegato trovi il preventivo demo preparato dal team Nexora.\n\nA disposizione per un confronto operativo.",
    ]);

    $pdo->prepare('DELETE FROM template_choices WHERE user_id = ? AND doc_id IN (?, ?)')
        ->execute([SEED_USER_ID, $quoteA, $quoteC]);
    $pdo->prepare(
        'INSERT INTO template_choices (user_id, doc_id, template_id) VALUES (?, ?, ?), (?, ?, ?)'
    )->execute([
        SEED_USER_ID, $quoteA, $docTemplateId,
        SEED_USER_ID, $quoteC, $docTemplateId,
    ]);
    $summary['tables']['template_choices'] += 2;

    $summary['tables']['memos'] += seed_upsert($pdo, 'memos', [
        'id' => 'memo-seed-20260616-team-01',
        'scope_id' => SEED_TEAM_ID,
        'title' => 'Recap operativo demo',
        'created_by' => SEED_USER_ID,
        'created_by_name' => (string)($user['display_name'] ?? 'Utente demo'),
        'payload' => seed_json([
            'blocks' => [
                ['type' => 'title', 'text' => 'Todo giornata'],
                ['type' => 'check', 'text' => 'Chiamare Alpine Growth', 'done' => false],
                ['type' => 'check', 'text' => 'Chiudere preventivo Northwind', 'done' => true],
                ['type' => 'note', 'text' => 'Questo memo serve per testare la condivisione team.'],
            ],
        ]),
    ]);

    $pdo->commit();

    echo json_encode($summary, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES | JSON_PRETTY_PRINT);
} catch (Throwable $e) {
    if (isset($pdo) && $pdo instanceof PDO && $pdo->inTransaction()) {
        $pdo->rollBack();
    }
    http_response_code(500);
    echo json_encode([
        'error' => $e->getMessage(),
        'type' => get_class($e),
        'file' => $e->getFile(),
        'line' => $e->getLine(),
    ], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES | JSON_PRETTY_PRINT);
}
