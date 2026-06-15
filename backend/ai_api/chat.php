<?php
declare(strict_types=1);

require_once __DIR__ . '/common.php';

$payload          = request_json_ai();
$messages         = $payload['messages'] ?? [];
$workspaceContext = $payload['workspace_context'] ?? [];

if (!is_array($messages) || count($messages) === 0) {
    json_ai_error('Messaggi non validi.', 422);
}

// ── Static system prompt (cached) ───────────────────────────
$today = date('d/m/Y');

$staticSystem = <<<'PROMPT'
Sei Nexora AI, l'assistente integrato nel gestionale CRM Nexora di Gussoni.
Rispondi sempre in italiano, in modo conciso e orientato all'azione.

Puoi fare QUALSIASI cosa nel CRM: creare, modificare, spostare, collegare, eliminare qualunque entità.
Non dire mai "non posso" — se l'utente chiede un'operazione, usa lo strumento giusto.
Esegui sempre lo strumento senza chiedere conferma.

STRUMENTI DISPONIBILI:
NAVIGAZIONE: open_crm_section, open_company
CREAZIONE: create_company, create_contact, create_opportunity, create_project, create_task, create_quote, create_ticket
MODIFICA (qualsiasi campo, incluso spostare a società/progetto diverso): update_company, update_contact, update_opportunity, update_project, update_task, update_quote
ELIMINAZIONE: delete_contact, delete_opportunity, delete_task, delete_quote
SPECIALE: accept_quote
CALENDARIO: schedule_task — pianifica un task nel calendario indicando data, ora inizio e durata. Supporta più slot (giorni diversi).
DOCUMENTI: generate_document, generate_csv
RICERCA: search_crm

IMPORTANTE: Per operazioni su entità esistenti, chiama prima search_entity per ottenere l'ID.
Per pianificare un task usa schedule_task direttamente con il nome del task — non serve chiamare search_entity prima, il sistema risolve il nome automaticamente.
Se l'utente chiede di CREARE E pianificare un task in una sola frase, chiama create_task e schedule_task NELLO STESSO TURNO (tool call multipli consecutivi).
Se l'utente dice "pianifica il task appena creato" o simili, usa il nome dell'ultimo task creato in questa conversazione.

PROMEMORIA: Se l'utente dice "ricordami", "crea un promemoria", "metti in agenda", "reminder":
- Crea un task con il testo del promemoria come nome, company_id="", nessuna società, notes="Promemoria".
- Calcola deadline_days in base alla data indicata.
- Poi chiama schedule_task per metterlo nel calendario nella data/ora indicata (durata default 0.5h se non specificata).

CONTESTO PINNATO: Se l'utente ha pinnato una sezione, le sue richieste riguardano prevalentemente quella sezione.
- Se la richiesta è chiaramente riferita a un'altra sezione (es. sezione pinnata = Contatti ma l'utente chiede di un preventivo), rispondi testualmente: "Stai visualizzando la sezione [Sezione]. Questa richiesta sembra uscire dal contesto. Vuoi che proceda comunque?" — non eseguire lo strumento finché non conferma.
- Se la richiesta è generica o interpretabile nel contesto attuale, procedi normalmente senza chiedere.
- Se non c'è sezione pinnata, comportati normalmente.
Quando devi collegare un'entità a un'altra (es. contatto → società, task → progetto), usa search_entity
per trovare l'ID della destinazione, poi usa lo strumento di modifica con il campo company_id/project_id.
PROMPT;

// ── Dynamic context: solo conteggi (~20 token) ──────────────
$counts = (array)($workspaceContext['counts'] ?? []);
$countParts = [];
foreach (['companies'=>'società','contacts'=>'contatti','opportunities'=>'opportunità','projects'=>'progetti','tasks'=>'task','quotes'=>'preventivi','tickets'=>'ticket'] as $k => $label) {
    if (!empty($counts[$k])) $countParts[] = "{$counts[$k]} {$label}";
}
$dynamicContext = "Oggi è {$today}. Workspace: " . (implode(', ', $countParts) ?: 'vuoto') . ".";
$pinnedSection      = (string)($workspaceContext['pinned_section'] ?? '');
$pinnedSectionLabel = (string)($workspaceContext['pinned_section_label'] ?? '');
if ($pinnedSection !== '' && $pinnedSectionLabel !== '') {
    $dynamicContext .= " Sezione corrente (pinnata dall'utente): {$pinnedSectionLabel}.";
}

// ── Tools definition ─────────────────────────────────────────
$tools = [
    // ─ NAVIGATION ──────────────────────────────────────────
    [
        'name'        => 'open_crm_section',
        'description' => 'Apre una sezione del CRM (preventivi, opportunità, progetti, ecc.).',
        'input_schema' => [
            'type' => 'object',
            'properties' => [
                'section' => ['type' => 'string', 'enum' => ['companies','contacts','opportunities','quotations','projects','tasks','archive','finanze','segnatempo','stats','chat']],
                'label'   => ['type' => 'string'],
            ],
            'required' => ['section', 'label'],
        ],
    ],
    [
        'name'        => 'open_company',
        'description' => 'Apre la scheda dettaglio di una società.',
        'input_schema' => [
            'type' => 'object',
            'properties' => [
                'company_id'   => ['type' => 'string'],
                'company_name' => ['type' => 'string'],
            ],
            'required' => ['company_id', 'company_name'],
        ],
    ],

    // ─ CREATE ───────────────────────────────────────────────
    [
        'name'        => 'create_company',
        'description' => 'Crea una nuova società nel CRM.',
        'input_schema' => [
            'type' => 'object',
            'properties' => [
                'name'  => ['type' => 'string'],
                'email' => ['type' => 'string'],
                'phone' => ['type' => 'string'],
                'city'  => ['type' => 'string'],
                'vatNumber' => ['type' => 'string', 'description' => 'Partita IVA'],
                'taxCode'   => ['type' => 'string', 'description' => 'Codice Fiscale'],
                'notes' => ['type' => 'string'],
            ],
            'required' => ['name'],
        ],
    ],
    [
        'name'        => 'create_contact',
        'description' => 'Crea un nuovo contatto/referente per una società.',
        'input_schema' => [
            'type' => 'object',
            'properties' => [
                'name'         => ['type' => 'string'],
                'company_id'   => ['type' => 'string'],
                'company_name' => ['type' => 'string'],
                'email'        => ['type' => 'string'],
                'phone'        => ['type' => 'string'],
                'role'         => ['type' => 'string'],
            ],
            'required' => ['name', 'company_id', 'company_name'],
        ],
    ],
    [
        'name'        => 'create_opportunity',
        'description' => 'Crea una nuova opportunità nel CRM.',
        'input_schema' => [
            'type' => 'object',
            'properties' => [
                'title'           => ['type' => 'string'],
                'company_id'      => ['type' => 'string'],
                'company_name'    => ['type' => 'string'],
                'estimated_value' => ['type' => 'number'],
                'notes'           => ['type' => 'string'],
            ],
            'required' => ['title', 'company_id', 'company_name'],
        ],
    ],
    [
        'name'        => 'create_project',
        'description' => 'Crea un nuovo progetto nel CRM.',
        'input_schema' => [
            'type' => 'object',
            'properties' => [
                'name'         => ['type' => 'string'],
                'company_id'   => ['type' => 'string'],
                'company_name' => ['type' => 'string'],
                'notes'        => ['type' => 'string'],
                'code'         => ['type' => 'string'],
            ],
            'required' => ['name', 'company_id', 'company_name'],
        ],
    ],
    [
        'name'        => 'create_task',
        'description' => 'Crea un nuovo task/attività.',
        'input_schema' => [
            'type' => 'object',
            'properties' => [
                'name'            => ['type' => 'string'],
                'company_id'      => ['type' => 'string'],
                'company_name'    => ['type' => 'string'],
                'estimated_hours' => ['type' => 'number'],
                'deadline_days'   => ['type' => 'integer', 'description' => 'Scadenza in giorni da oggi'],
                'notes'           => ['type' => 'string'],
            ],
            'required' => ['name'],
        ],
    ],
    [
        'name'        => 'create_quote',
        'description' => 'Crea un nuovo preventivo strutturato (crea anche l\'opportunità collegata).',
        'input_schema' => [
            'type' => 'object',
            'properties' => [
                'title'           => ['type' => 'string'],
                'company_id'      => ['type' => 'string'],
                'company_name'    => ['type' => 'string'],
                'estimated_value' => ['type' => 'number'],
                'notes'           => ['type' => 'string'],
                'lines' => [
                    'type'  => 'array',
                    'items' => [
                        'type' => 'object',
                        'properties' => [
                            'description' => ['type' => 'string'],
                            'quantity'    => ['type' => 'number'],
                            'unit_price'  => ['type' => 'number'],
                        ],
                        'required' => ['description', 'quantity', 'unit_price'],
                    ],
                ],
            ],
            'required' => ['title', 'company_id', 'company_name'],
        ],
    ],
    [
        'name'        => 'create_ticket',
        'description' => 'Crea un nuovo ticket di assistenza/attività per una società.',
        'input_schema' => [
            'type' => 'object',
            'properties' => [
                'company_id'   => ['type' => 'string'],
                'company_name' => ['type' => 'string'],
                'title'        => ['type' => 'string'],
                'body'         => ['type' => 'string', 'description' => 'Descrizione dettagliata'],
            ],
            'required' => ['company_id', 'company_name', 'title'],
        ],
    ],

    // ─ UPDATE ───────────────────────────────────────────────
    [
        'name'        => 'update_company',
        'description' => 'Modifica i dati di una società esistente. Usa solo i campi da cambiare.',
        'input_schema' => [
            'type' => 'object',
            'properties' => [
                'company_id'   => ['type' => 'string', 'description' => 'ID dal workspace context'],
                'company_name' => ['type' => 'string', 'description' => 'Nome per conferma'],
                'changes' => [
                    'type' => 'object',
                    'description' => 'Campi da modificare (solo quelli da cambiare)',
                    'properties' => [
                        'name'                => ['type' => 'string'],
                        'vatNumber'           => ['type' => 'string', 'description' => 'Partita IVA'],
                        'taxCode'             => ['type' => 'string', 'description' => 'Codice Fiscale'],
                        'pec'                 => ['type' => 'string'],
                        'sdiCode'             => ['type' => 'string', 'description' => 'Codice SDI'],
                        'email'               => ['type' => 'string'],
                        'phone'               => ['type' => 'string'],
                        'website'             => ['type' => 'string'],
                        'addressLine'         => ['type' => 'string', 'description' => 'Via/indirizzo'],
                        'city'                => ['type' => 'string'],
                        'postalCode'          => ['type' => 'string', 'description' => 'CAP'],
                        'country'             => ['type' => 'string'],
                        'contactPerson'       => ['type' => 'string', 'description' => 'Referente principale'],
                        'notes'               => ['type' => 'string'],
                        'legalRepresentative' => ['type' => 'string', 'description' => 'Legale rappresentante'],
                        'riferimentoInterno'  => ['type' => 'string'],
                        'provincia'           => ['type' => 'string'],
                    ],
                ],
            ],
            'required' => ['company_id', 'company_name', 'changes'],
        ],
    ],
    [
        'name'        => 'update_contact',
        'description' => 'Modifica i dati di un contatto, incluso il collegamento a una società diversa.',
        'input_schema' => [
            'type' => 'object',
            'properties' => [
                'contact_id'   => ['type' => 'string'],
                'contact_name' => ['type' => 'string'],
                'changes' => [
                    'type' => 'object',
                    'properties' => [
                        'name'       => ['type' => 'string'],
                        'email'      => ['type' => 'string'],
                        'phone'      => ['type' => 'string'],
                        'role'       => ['type' => 'string'],
                        'company_id' => ['type' => 'string', 'description' => 'ID della nuova società (da search_entity)'],
                    ],
                ],
            ],
            'required' => ['contact_id', 'contact_name', 'changes'],
        ],
    ],
    [
        'name'        => 'update_opportunity',
        'description' => 'Modifica un\'opportunità esistente: titolo, stato, note, valore, spostamento a società diversa, ecc.',
        'input_schema' => [
            'type' => 'object',
            'properties' => [
                'opportunity_id'    => ['type' => 'string'],
                'opportunity_title' => ['type' => 'string'],
                'changes' => [
                    'type' => 'object',
                    'properties' => [
                        'title'             => ['type' => 'string'],
                        'status'            => ['type' => 'string', 'enum' => ['inAttesa','preventivazione','accettata','accettataSenzaFirma','presaInCarico','persa','inAttesaRinnovoAutomatico']],
                        'notes'             => ['type' => 'string'],
                        'estimatedValue'    => ['type' => 'number'],
                        'rifOfferta'        => ['type' => 'string'],
                        'assignedAnalystId' => ['type' => 'string'],
                        'company_id'        => ['type' => 'string', 'description' => 'Sposta a società diversa (ID da search_entity)'],
                        'bandoDeadline'     => ['type' => 'string', 'description' => 'Scadenza bando ISO 8601 (YYYY-MM-DD)'],
                        'contactId'         => ['type' => 'string', 'description' => 'ID contatto referente'],
                    ],
                ],
            ],
            'required' => ['opportunity_id', 'opportunity_title', 'changes'],
        ],
    ],
    [
        'name'        => 'update_project',
        'description' => 'Modifica un progetto esistente: nome, stato, note, cliente, ecc.',
        'input_schema' => [
            'type' => 'object',
            'properties' => [
                'project_id'   => ['type' => 'string'],
                'project_name' => ['type' => 'string'],
                'changes' => [
                    'type' => 'object',
                    'properties' => [
                        'name'           => ['type' => 'string'],
                        'code'           => ['type' => 'string'],
                        'status'         => ['type' => 'string', 'enum' => ['draft','planning','inProgress','pendingResult','approved','rejected','closed']],
                        'notes'          => ['type' => 'string'],
                        'titoloProgetto' => ['type' => 'string'],
                        'company_id'     => ['type' => 'string', 'description' => 'Sposta a società diversa (ID da search_entity)'],
                    ],
                ],
            ],
            'required' => ['project_id', 'project_name', 'changes'],
        ],
    ],
    [
        'name'        => 'update_task',
        'description' => 'Modifica un task esistente: nome, stato, ore, scadenza, assegnatario, collegamento a progetto/società.',
        'input_schema' => [
            'type' => 'object',
            'properties' => [
                'task_id'   => ['type' => 'string'],
                'task_name' => ['type' => 'string'],
                'changes' => [
                    'type' => 'object',
                    'properties' => [
                        'name'           => ['type' => 'string'],
                        'status'         => ['type' => 'string', 'enum' => ['backlog','planned','inProgress','done']],
                        'estimatedHours' => ['type' => 'number'],
                        'deadline_days'  => ['type' => 'integer', 'description' => 'Nuova scadenza in giorni da oggi'],
                        'billable'       => ['type' => 'boolean'],
                        'company_id'     => ['type' => 'string', 'description' => 'Collega a società (ID da search_entity)'],
                        'project_id'     => ['type' => 'string', 'description' => 'Collega a progetto (ID da search_entity)'],
                        'assignee_id'    => ['type' => 'string', 'description' => 'ID utente assegnatario'],
                    ],
                ],
            ],
            'required' => ['task_id', 'task_name', 'changes'],
        ],
    ],
    [
        'name'        => 'update_quote',
        'description' => 'Modifica un preventivo esistente: note, stato, fee, voci, opportunità collegata.',
        'input_schema' => [
            'type' => 'object',
            'properties' => [
                'quote_id'    => ['type' => 'string'],
                'quote_title' => ['type' => 'string'],
                'changes' => [
                    'type' => 'object',
                    'properties' => [
                        'notes'          => ['type' => 'string'],
                        'istruttoriaFee' => ['type' => 'number'],
                        'status'         => ['type' => 'string', 'enum' => ['draft','sent','accepted','rejected']],
                        'opportunity_id' => ['type' => 'string', 'description' => 'Collega a opportunità diversa'],
                        'lines' => [
                            'type'  => 'array',
                            'description' => 'Sostituisce tutte le voci del preventivo',
                            'items' => [
                                'type'       => 'object',
                                'properties' => [
                                    'description' => ['type' => 'string'],
                                    'quantity'    => ['type' => 'number'],
                                    'unit_price'  => ['type' => 'number'],
                                    'notes'       => ['type' => 'string'],
                                ],
                                'required' => ['description', 'quantity', 'unit_price'],
                            ],
                        ],
                    ],
                ],
            ],
            'required' => ['quote_id', 'quote_title', 'changes'],
        ],
    ],

    // ─ DELETE ───────────────────────────────────────────────
    [
        'name'        => 'delete_contact',
        'description' => 'Elimina un contatto.',
        'input_schema' => [
            'type' => 'object',
            'properties' => [
                'contact_id'   => ['type' => 'string'],
                'contact_name' => ['type' => 'string'],
            ],
            'required' => ['contact_id', 'contact_name'],
        ],
    ],
    [
        'name'        => 'delete_opportunity',
        'description' => 'Elimina un\'opportunità.',
        'input_schema' => [
            'type' => 'object',
            'properties' => [
                'opportunity_id'    => ['type' => 'string'],
                'opportunity_title' => ['type' => 'string'],
            ],
            'required' => ['opportunity_id', 'opportunity_title'],
        ],
    ],
    [
        'name'        => 'delete_task',
        'description' => 'Elimina un task.',
        'input_schema' => [
            'type' => 'object',
            'properties' => [
                'task_id'   => ['type' => 'string'],
                'task_name' => ['type' => 'string'],
            ],
            'required' => ['task_id', 'task_name'],
        ],
    ],
    [
        'name'        => 'delete_quote',
        'description' => 'Elimina un preventivo.',
        'input_schema' => [
            'type' => 'object',
            'properties' => [
                'quote_id'    => ['type' => 'string'],
                'quote_title' => ['type' => 'string'],
            ],
            'required' => ['quote_id', 'quote_title'],
        ],
    ],

    // ─ SPECIAL ACTIONS ──────────────────────────────────────
    [
        'name'        => 'accept_quote',
        'description' => 'Accetta un preventivo (lo segna come accettato e aggiorna l\'opportunità collegata).',
        'input_schema' => [
            'type' => 'object',
            'properties' => [
                'quote_id'       => ['type' => 'string'],
                'opportunity_id' => ['type' => 'string'],
                'quote_title'    => ['type' => 'string'],
            ],
            'required' => ['quote_id', 'opportunity_id', 'quote_title'],
        ],
    ],

    // ─ GENERATION ───────────────────────────────────────────
    [
        'name'        => 'generate_document',
        'description' => 'Genera un documento di testo (email, preventivo narrativo, lettera, report). Contenuto mostrato come card copiabile.',
        'input_schema' => [
            'type' => 'object',
            'properties' => [
                'type'    => ['type' => 'string', 'enum' => ['email','quote','report','letter','note']],
                'title'   => ['type' => 'string'],
                'content' => ['type' => 'string'],
                'subject' => ['type' => 'string'],
            ],
            'required' => ['type', 'title', 'content'],
        ],
    ],
    [
        'name'        => 'generate_csv',
        'description' => 'Genera un file CSV/Excel scaricabile.',
        'input_schema' => [
            'type' => 'object',
            'properties' => [
                'filename' => ['type' => 'string'],
                'headers'  => ['type' => 'array', 'items' => ['type' => 'string']],
                'rows'     => ['type' => 'array', 'items' => ['type' => 'array']],
            ],
            'required' => ['filename', 'headers', 'rows'],
        ],
    ],

    // ─ CALENDAR ─────────────────────────────────────────────
    [
        'name'        => 'schedule_task',
        'description' => 'Pianifica un task esistente nel calendario su uno o più giorni. Passa solo il nome del task come lo dice l\'utente — il sistema lo risolve automaticamente. Non serve cercare l\'ID prima.',
        'input_schema' => [
            'type' => 'object',
            'properties' => [
                'task_name' => ['type' => 'string', 'description' => 'Nome del task esattamente come detto dall\'utente (es. "Test", "Analisi Gweb")'],
                'slots'     => [
                    'type'        => 'array',
                    'description' => 'Uno o più slot da inserire nel calendario',
                    'items'       => [
                        'type' => 'object',
                        'properties' => [
                            'date'           => ['type' => 'string', 'description' => 'Data in formato YYYY-MM-DD'],
                            'start_hour'     => ['type' => 'number', 'description' => 'Ora di inizio decimale (es. 9.0 = 09:00, 14.5 = 14:30)'],
                            'duration_hours' => ['type' => 'number', 'description' => 'Durata in ore (es. 2.0, 1.5)'],
                        ],
                        'required' => ['date', 'start_hour', 'duration_hours'],
                    ],
                ],
            ],
            'required' => ['task_name', 'slots'],
        ],
    ],

    // ─ SEARCH ───────────────────────────────────────────────
    [
        'name'        => 'search_entity',
        'description' => 'Cerca un\'entità nel CRM per nome/testo e restituisce id e dati. Usalo PRIMA di update/delete/open_company quando non conosci l\'ID.',
        'input_schema' => [
            'type' => 'object',
            'properties' => [
                'entity_type' => ['type' => 'string', 'enum' => ['company','contact','opportunity','project','task','quote','ticket']],
                'query'       => ['type' => 'string', 'description' => 'Nome o testo parziale da cercare'],
            ],
            'required' => ['entity_type', 'query'],
        ],
    ],
    [
        'name'        => 'search_crm',
        'description' => 'Cerca nel CRM per testo libero e mostra i risultati all\'utente come card cliccabile. Il client esegue la ricerca localmente.',
        'input_schema' => [
            'type'       => 'object',
            'properties' => ['query' => ['type' => 'string']],
            'required'   => ['query'],
        ],
        'cache_control' => ['type' => 'ephemeral'],
    ],
];

// ── Normalize and trim messages ───────────────────────────────
$apiMessages = [];
foreach ($messages as $msg) {
    $role = (string)($msg['role'] ?? '');
    if (!in_array($role, ['user', 'assistant'], true)) continue;
    $content = $msg['content'] ?? '';
    if (is_string($content) || is_array($content)) {
        $apiMessages[] = ['role' => $role, 'content' => $content];
    }
}

if (empty($apiMessages)) {
    json_ai_error('Nessun messaggio valido.', 422);
}

$maxHistory = 14;
if (count($apiMessages) > $maxHistory) {
    $apiMessages = array_slice($apiMessages, -$maxHistory);
    while (count($apiMessages) > 1) {
        $first = $apiMessages[0];
        if ($first['role'] === 'user') {
            $c = $first['content'];
            if (is_string($c)) break;
            if (is_array($c) && ($c[0]['type'] ?? '') !== 'tool_result') break;
        }
        array_shift($apiMessages);
    }
}

// ── Build API payload ─────────────────────────────────────────
$config     = ai_config();
$apiPayload = [
    'model'      => $config['model'] ?? 'claude-haiku-4-5-20251001',
    'max_tokens' => $config['max_tokens'] ?? 2048,
    'system'     => [
        ['type' => 'text', 'text' => $staticSystem, 'cache_control' => ['type' => 'ephemeral']],
        ['type' => 'text', 'text' => $dynamicContext],
    ],
    'tools'    => $tools,
    'messages' => $apiMessages,
];

// ── Streaming mode ────────────────────────────────────────────
if (!empty($payload['stream'])) {
    header('Content-Type: application/x-ndjson; charset=utf-8');
    header('Cache-Control: no-cache');
    header('X-Accel-Buffering: no');
    while (ob_get_level() > 0) ob_end_clean();

    $apiKey = ai_config_value('anthropic_api_key');
    $body   = json_encode(
        array_merge($apiPayload, ['stream' => true]),
        JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES
    );

    $toolBuffers   = [];
    $currentToolId = null;
    $lineBuf       = '';

    $emit = static function (array $data): void {
        echo json_encode($data, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES) . "\n";
        if (ob_get_level() > 0) ob_flush();
        flush();
    };

    $curl = curl_init('https://api.anthropic.com/v1/messages');
    curl_setopt_array($curl, [
        CURLOPT_RETURNTRANSFER => false,
        CURLOPT_POST           => true,
        CURLOPT_POSTFIELDS     => $body,
        CURLOPT_TIMEOUT        => 120,
        CURLOPT_HTTPHEADER     => [
            'x-api-key: ' . $apiKey,
            'anthropic-version: 2023-06-01',
            'anthropic-beta: prompt-caching-2024-07-31',
            'content-type: application/json',
        ],
        CURLOPT_WRITEFUNCTION => static function ($ch, $data) use (&$lineBuf, &$toolBuffers, &$currentToolId, $emit): int {
            $lineBuf .= $data;
            while (($pos = strpos($lineBuf, "\n")) !== false) {
                $line    = trim(substr($lineBuf, 0, $pos));
                $lineBuf = substr($lineBuf, $pos + 1);
                if (!$line || !str_starts_with($line, 'data: ')) continue;
                $raw = substr($line, 6);
                if ($raw === '[DONE]') continue;
                $event = json_decode($raw, true);
                if (!is_array($event)) continue;
                switch ($event['type'] ?? '') {
                    case 'content_block_start':
                        $blk = $event['content_block'] ?? [];
                        if (($blk['type'] ?? '') === 'tool_use') {
                            $currentToolId                  = $blk['id'];
                            $toolBuffers[$currentToolId]    = ['id' => $blk['id'], 'name' => $blk['name'], 'json' => ''];
                        }
                        break;
                    case 'content_block_delta':
                        $delta = $event['delta'] ?? [];
                        if ($delta['type'] === 'text_delta') {
                            $emit(['type' => 'text', 'delta' => (string)($delta['text'] ?? '')]);
                        } elseif ($delta['type'] === 'input_json_delta' && $currentToolId) {
                            $toolBuffers[$currentToolId]['json'] .= (string)($delta['partial_json'] ?? '');
                        }
                        break;
                    case 'content_block_stop':
                        $currentToolId = null;
                        break;
                    case 'message_delta':
                        $stopReason = (string)($event['delta']['stop_reason'] ?? '');
                        foreach ($toolBuffers as $tool) {
                            $input = json_decode($tool['json'], true);
                            $emit([
                                'type'  => 'tool_use',
                                'id'    => $tool['id'],
                                'name'  => $tool['name'],
                                'input' => is_array($input) ? $input : (object) [],
                            ]);
                        }
                        $emit(['type' => 'done', 'stop_reason' => $stopReason]);
                        break;
                    case 'error':
                        $emit(['type' => 'error', 'message' => (string)($event['error']['message'] ?? 'Errore Anthropic')]);
                        break;
                }
            }
            return strlen($data);
        },
    ]);

    curl_exec($curl);
    curl_close($curl);
    exit;
}

// ── Non-streaming (fallback) ─────────────────────────────────
$response      = anthropic_request($apiPayload);
$stopReason    = (string)($response['stop_reason'] ?? '');
$contentBlocks = (array)($response['content'] ?? []);
$textParts     = [];
$toolCalls     = [];

foreach ($contentBlocks as $block) {
    $type = (string)($block['type'] ?? '');
    if ($type === 'text') {
        $textParts[] = (string)($block['text'] ?? '');
    } elseif ($type === 'tool_use') {
        $toolCalls[] = ['id' => (string)($block['id'] ?? ''), 'name' => (string)($block['name'] ?? ''), 'input' => $block['input'] ?? []];
    }
}

json_ai_ok([
    'text'        => implode("\n", $textParts),
    'tool_calls'  => $toolCalls,
    'stop_reason' => $stopReason,
    'usage'       => $response['usage'] ?? [],
]);
