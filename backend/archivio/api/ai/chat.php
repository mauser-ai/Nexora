<?php
declare(strict_types=1);

require_once __DIR__ . '/common.php';

$payload = request_json_ai();
$messages = $payload['messages'] ?? [];
$workspaceContext = $payload['workspace_context'] ?? [];

if (!is_array($messages) || count($messages) === 0) {
    json_ai_error('Messaggi non validi.', 422);
}

// ── Build system prompt ─────────────────────────────────────
$today = date('d/m/Y');
$companies = '';
if (!empty($workspaceContext['companies'])) {
    $items = array_map(
        fn($c) => "- {$c['name']} (id: {$c['id']})",
        array_slice((array)$workspaceContext['companies'], 0, 40)
    );
    $companies = implode("\n", $items);
}
$deals = '';
if (!empty($workspaceContext['deals'])) {
    $items = array_map(
        fn($d) => "- {$d['title']} [{$d['stage']}] — cliente: {$d['customerName']}",
        array_slice((array)$workspaceContext['deals'], 0, 30)
    );
    $deals = implode("\n", $items);
}
$projects = '';
if (!empty($workspaceContext['projects'])) {
    $items = array_map(
        fn($p) => "- {$p['name']} — cliente: {$p['customerName']}",
        array_slice((array)$workspaceContext['projects'], 0, 30)
    );
    $projects = implode("\n", $items);
}

$systemPrompt = <<<PROMPT
Sei Nexora AI, l'assistente integrato nel gestionale CRM Nexora di Gussoni.
Oggi è {$today}. Rispondi sempre in italiano, in modo conciso e orientato all'azione.

DATI DEL WORKSPACE:
Società clienti:
{$companies}

Opportunità:
{$deals}

Progetti:
{$projects}

CAPACITÀ DISPONIBILI:
Puoi eseguire azioni direttamente nel CRM tramite strumenti. Usali quando l'utente vuole navigare, generare documenti o file.
Quando generi bozze di email, preventivi o testi, mettili nel campo "content" dello strumento generate_document.
Quando generi CSV/Excel, crea dati strutturati e usali in generate_csv.
PROMPT;

// ── Tools definition ────────────────────────────────────────
$tools = [
    [
        'name'        => 'open_crm_section',
        'description' => 'Apre una sezione del CRM (es. "apri le opportunità", "vai ai progetti"). Usa questo quando l\'utente vuole navigare verso una sezione specifica.',
        'input_schema' => [
            'type'       => 'object',
            'properties' => [
                'section' => [
                    'type'        => 'string',
                    'enum'        => ['companies', 'contacts', 'opportunities', 'quotations', 'projects', 'tasks', 'archive', 'finanze', 'segnatempo', 'stats', 'chat'],
                    'description' => 'La sezione da aprire',
                ],
                'label' => [
                    'type'        => 'string',
                    'description' => 'Nome leggibile della sezione per mostrare all\'utente',
                ],
            ],
            'required' => ['section', 'label'],
        ],
    ],
    [
        'name'        => 'open_company',
        'description' => 'Apre la scheda dettaglio di una società cliente specifica.',
        'input_schema' => [
            'type'       => 'object',
            'properties' => [
                'company_id'   => ['type' => 'string', 'description' => 'ID univoco della società'],
                'company_name' => ['type' => 'string', 'description' => 'Nome della società'],
            ],
            'required' => ['company_id', 'company_name'],
        ],
    ],
    [
        'name'        => 'generate_document',
        'description' => 'Genera un documento di testo (bozza email, preventivo narrativo, report, comunicazione). Il contenuto viene mostrato all\'utente come card copiabile.',
        'input_schema' => [
            'type'       => 'object',
            'properties' => [
                'type'    => ['type' => 'string', 'enum' => ['email', 'quote', 'report', 'letter', 'note'], 'description' => 'Tipo di documento'],
                'title'   => ['type' => 'string', 'description' => 'Titolo del documento'],
                'content' => ['type' => 'string', 'description' => 'Contenuto completo del documento'],
                'subject' => ['type' => 'string', 'description' => 'Oggetto (solo per email)'],
            ],
            'required' => ['type', 'title', 'content'],
        ],
    ],
    [
        'name'        => 'generate_csv',
        'description' => 'Genera un file CSV/Excel scaricabile con dati strutturati. Usalo quando l\'utente chiede un foglio Excel, una tabella, una lista strutturata.',
        'input_schema' => [
            'type'       => 'object',
            'properties' => [
                'filename' => ['type' => 'string', 'description' => 'Nome del file senza estensione'],
                'headers'  => ['type' => 'array', 'items' => ['type' => 'string'], 'description' => 'Intestazioni delle colonne'],
                'rows'     => ['type' => 'array', 'items' => ['type' => 'array'], 'description' => 'Righe di dati (array di array)'],
            ],
            'required' => ['filename', 'headers', 'rows'],
        ],
    ],
];

// ── Normalize messages ──────────────────────────────────────
$apiMessages = [];
foreach ($messages as $msg) {
    $role = (string)($msg['role'] ?? '');
    if (!in_array($role, ['user', 'assistant'], true)) {
        continue;
    }
    $content = $msg['content'] ?? '';
    if (is_string($content)) {
        $apiMessages[] = ['role' => $role, 'content' => $content];
    } elseif (is_array($content)) {
        $apiMessages[] = ['role' => $role, 'content' => $content];
    }
}

if (empty($apiMessages)) {
    json_ai_error('Nessun messaggio valido.', 422);
}

// ── Call Anthropic ──────────────────────────────────────────
$config = ai_config();
$response = anthropic_request([
    'model'      => $config['model'] ?? 'claude-sonnet-4-6',
    'max_tokens' => $config['max_tokens'] ?? 4096,
    'system'     => $systemPrompt,
    'tools'      => $tools,
    'messages'   => $apiMessages,
]);

// ── Parse response ──────────────────────────────────────────
$stopReason = (string)($response['stop_reason'] ?? '');
$contentBlocks = (array)($response['content'] ?? []);

$textParts = [];
$toolCalls = [];

foreach ($contentBlocks as $block) {
    $type = (string)($block['type'] ?? '');
    if ($type === 'text') {
        $textParts[] = (string)($block['text'] ?? '');
    } elseif ($type === 'tool_use') {
        $toolCalls[] = [
            'id'    => (string)($block['id'] ?? ''),
            'name'  => (string)($block['name'] ?? ''),
            'input' => $block['input'] ?? [],
        ];
    }
}

json_ai_ok([
    'text'        => implode("\n", $textParts),
    'tool_calls'  => $toolCalls,
    'stop_reason' => $stopReason,
    'usage'       => $response['usage'] ?? [],
]);
