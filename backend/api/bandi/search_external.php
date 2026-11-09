<?php
declare(strict_types=1);

// Ricerca esterna bandi.
// Nexora interroga il motore pubblico usato dalla pagina "Tutti i bandi" e
// normalizza i risultati per la UI interna. Se in futuro Contributi Europa
// fornisce una API ufficiale, questo file e il punto unico da sostituire.

require_once dirname(__DIR__) . '/bootstrap.php';

header('Content-Type: application/json; charset=utf-8');

ob_start();

function bandi_external_json_fail(string $message, int $status = 500): void
{
    if (!headers_sent()) {
        http_response_code($status);
        header('Content-Type: application/json; charset=utf-8');
    }
    while (ob_get_level() > 0) {
        ob_end_clean();
    }
    echo json_encode(
        ['error' => $message],
        JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES
    );
    exit;
}

set_exception_handler(static function (Throwable $e): void {
    bandi_external_json_fail(
        'Errore ricerca bandi: ' . $e->getMessage(),
        500
    );
});

register_shutdown_function(static function (): void {
    $error = error_get_last();
    if ($error === null) {
        return;
    }
    $fatalTypes = [E_ERROR, E_PARSE, E_CORE_ERROR, E_COMPILE_ERROR];
    if (!in_array((int)$error['type'], $fatalTypes, true)) {
        return;
    }
    bandi_external_json_fail(
        'Errore PHP ricerca bandi: ' . $error['message'] .
        ' in ' . $error['file'] . ':' . $error['line'],
        500
    );
});

require_auth();

$payload = request_json();

$query = trim((string)($payload['query'] ?? ''));
$page = max(0, (int)($payload['page'] ?? 0));
$hitsPerPage = min(20, max(1, (int)($payload['hitsPerPage'] ?? 10)));
$onlyOpen = (bool)($payload['onlyOpen'] ?? true);

$filtersInput = is_array($payload['filters'] ?? null) ? $payload['filters'] : [];

function bandi_external_list($value): array
{
    if (!is_array($value)) {
        return [];
    }
    $items = [];
    foreach ($value as $item) {
        $item = trim((string)$item);
        if ($item !== '') {
            $items[] = $item;
        }
    }
    return array_values(array_unique($items));
}

function bandi_external_filter_group(string $attribute, array $values): ?string
{
    if (!$values) {
        return null;
    }
    $parts = [];
    foreach ($values as $value) {
        $safe = str_replace('"', '\"', $value);
        if (strpos($attribute, 'hierarchical') !== false) {
            $parts[] = "{$attribute}.lvl0:\"{$safe}\" OR {$attribute}.lvl1:\"{$safe}\"";
        } else {
            $parts[] = "{$attribute}:\"{$safe}\"";
        }
    }
    return '(' . implode(' OR ', $parts) . ')';
}

function bandi_external_date(?string $value): ?string
{
    $value = trim((string)$value);
    if ($value === '') {
        return null;
    }

    $formats = ['d/m/Y', 'd-m-Y', 'Y-m-d'];
    foreach ($formats as $format) {
        $date = DateTime::createFromFormat($format, $value);
        if ($date instanceof DateTime) {
            return $date->format('Y-m-d') . 'T00:00:00';
        }
    }

    $ts = strtotime($value);
    return $ts === false ? null : date('Y-m-d', $ts) . 'T00:00:00';
}

function bandi_external_taxonomies(array $hit, string $key): array
{
    $tax = $hit['taxonomies'] ?? [];
    $value = is_array($tax) ? ($tax[$key] ?? []) : [];
    return is_array($value) ? array_values(array_map('strval', $value)) : [];
}

$filterGroups = [];
$map = [
    'areaGeografica' => 'taxonomies_hierarchical.area_geografica',
    'beneficiari' => 'taxonomies.beneficiari',
    'settore' => 'taxonomies_hierarchical.settore',
    'agevolazione' => 'taxonomies.agevolazione',
    'speseFinanziate' => 'taxonomies.spese_finanziate',
];

foreach ($map as $payloadKey => $algoliaAttribute) {
    $group = bandi_external_filter_group(
        $algoliaAttribute,
        bandi_external_list($filtersInput[$payloadKey] ?? [])
    );
    if ($group !== null) {
        $filterGroups[] = $group;
    }
}

if ($onlyOpen) {
    $filterGroups[] = '(scadenza_testo:"Bandi aperti" OR scadenza_testo:"Aperto")';
}

$algoliaPayload = [
    'query' => $query,
    'hitsPerPage' => $hitsPerPage,
    'page' => $page,
    'filters' => implode(' AND ', $filterGroups),
    'facets' => ['*'],
    'maxValuesPerFacet' => 1000,
];

$algoliaBody = json_encode($algoliaPayload, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
if ($algoliaBody === false) {
    json_error('Payload ricerca bandi non valido.', 500);
}

$algoliaUrl = 'https://LHI8XKBFMN-dsn.algolia.net/1/indexes/ceu_searchable_posts/query';
$headers = [
    'Content-Type: application/json',
    'X-Algolia-Application-Id: LHI8XKBFMN',
    'X-Algolia-API-Key: f55131344ae840ea7f27c6dcb0782654',
];

$raw = false;
$status = 0;
$error = '';

if (function_exists('curl_init')) {
    $curl = curl_init($algoliaUrl);
    curl_setopt_array($curl, [
        CURLOPT_RETURNTRANSFER => true,
        CURLOPT_POST => true,
        CURLOPT_HTTPHEADER => $headers,
        CURLOPT_POSTFIELDS => $algoliaBody,
        CURLOPT_TIMEOUT => 20,
    ]);

    $raw = curl_exec($curl);
    $status = (int)curl_getinfo($curl, CURLINFO_RESPONSE_CODE);
    $error = curl_error($curl);
    curl_close($curl);
} else {
    $context = stream_context_create([
        'http' => [
            'method' => 'POST',
            'header' => implode("\r\n", $headers),
            'content' => $algoliaBody,
            'timeout' => 20,
            'ignore_errors' => true,
        ],
    ]);
    $raw = @file_get_contents($algoliaUrl, false, $context);
    $statusLine = $http_response_header[0] ?? '';
    if (preg_match('/\s(\d{3})\s/', $statusLine, $m)) {
        $status = (int)$m[1];
    }
    if ($raw === false) {
        $error = 'Estensione curl non disponibile e richiesta HTTP alternativa fallita.';
    }
}

if ($raw === false || $status < 200 || $status >= 300) {
    json_error('Ricerca bandi esterna non disponibile: ' . ($error ?: (string)$raw), 502);
}

$decoded = json_decode((string)$raw, true);
if (!is_array($decoded)) {
    json_error('Risposta ricerca bandi non valida.', 502);
}

$items = [];
foreach (($decoded['hits'] ?? []) as $hit) {
    if (!is_array($hit)) {
        continue;
    }

    $title = trim((string)($hit['post_title'] ?? $hit['title'] ?? ''));
    if ($title === '') {
        continue;
    }

    $permalink = trim((string)($hit['permalink'] ?? ''));
    if ($permalink !== '' && strpos($permalink, '/') === 0) {
        $permalink = 'https://www.contributieuropa.com' . $permalink;
    }

    $scadenzaRaw = (string)($hit['scadenza'] ?? '');
    $scadenzaText = trim((string)($hit['scadenza_testo'] ?? $scadenzaRaw));
    $excerpt = trim(strip_tags((string)($hit['post_excerpt'] ?? $hit['content'] ?? '')));

    $items[] = [
        'externalId' => (string)($hit['objectID'] ?? $hit['post_id'] ?? ''),
        'titolo' => $title,
        'ente' => 'Contributi Europa',
        'descrizione' => $excerpt,
        'link' => $permalink,
        'scadenza' => bandi_external_date($scadenzaRaw),
        'scadenzaTesto' => $scadenzaText,
        'regioni' => bandi_external_taxonomies($hit, 'area_geografica'),
        'beneficiari' => bandi_external_taxonomies($hit, 'beneficiari'),
        'settori' => bandi_external_taxonomies($hit, 'settore'),
        'agevolazioni' => bandi_external_taxonomies($hit, 'agevolazione'),
        'speseFinanziate' => bandi_external_taxonomies($hit, 'spese_finanziate'),
        'source' => 'Contributi Europa',
    ];
}

json_ok([
    'source' => 'Contributi Europa',
    'page' => (int)($decoded['page'] ?? $page),
    'nbPages' => (int)($decoded['nbPages'] ?? 0),
    'nbHits' => (int)($decoded['nbHits'] ?? count($items)),
    'items' => $items,
]);
