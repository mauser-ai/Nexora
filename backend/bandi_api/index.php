<?php
declare(strict_types=1);

// ─────────────────────────────────────────────────────────────────────────────
// API modulo Bandi (Centro Studi).
//   GET    /api/bandi/index.php?scope=<scopeId>          → lista bandi
//   POST   /api/bandi/index.php                          → crea/aggiorna (body JSON)
//   PUT    /api/bandi/index.php?id=<id>                  → aggiorna (body JSON)
//   DELETE /api/bandi/index.php?id=<id>&scope=<scopeId>  → elimina
// Le chiavi del JSON corrispondono al modello Flutter (camelCase).
// ─────────────────────────────────────────────────────────────────────────────

require_once dirname(__DIR__) . '/bootstrap.php';

header('Content-Type: application/json; charset=utf-8');

require_auth();

if (!function_exists('db')) {
    json_error('bootstrap.php non espone db(): PDO.', 500);
}
$pdo = db();

/** Decodifica una colonna TEXT contenente un array JSON. */
function bandi_list_decode(?string $raw): array
{
    if ($raw === null || $raw === '') {
        return [];
    }
    $decoded = json_decode($raw, true);
    return is_array($decoded) ? array_values($decoded) : [];
}

/** Riga DB → payload API (camelCase, date ISO). */
function bandi_row_to_json(array $row): array
{
    return [
        'id' => (string)$row['id'],
        'titolo' => (string)$row['titolo'],
        'ente' => (string)$row['ente'],
        'descrizione' => (string)($row['descrizione'] ?? ''),
        'link' => (string)$row['link'],
        'note' => (string)($row['note'] ?? ''),
        'stato' => (string)$row['stato'],
        'apertura' => $row['apertura'] !== null ? $row['apertura'] . 'T00:00:00' : null,
        'scadenza' => $row['scadenza'] !== null ? $row['scadenza'] . 'T00:00:00' : null,
        'dotazione' => $row['dotazione'] !== null ? (float)$row['dotazione'] : null,
        'percentualeContributo' => $row['percentuale_contributo'] !== null
            ? (float)$row['percentuale_contributo'] : null,
        'importoMin' => $row['importo_min'] !== null ? (float)$row['importo_min'] : null,
        'importoMax' => $row['importo_max'] !== null ? (float)$row['importo_max'] : null,
        'regioni' => bandi_list_decode($row['regioni'] ?? null),
        'codiciAteco' => bandi_list_decode($row['codici_ateco'] ?? null),
        'dimensioni' => bandi_list_decode($row['dimensioni'] ?? null),
        'tipi' => bandi_list_decode($row['tipi'] ?? null),
        'areeInvestimento' => bandi_list_decode($row['aree_investimento'] ?? null),
        'createdAt' => str_replace(' ', 'T', (string)$row['created_at']),
    ];
}

/** Estrae una data "YYYY-MM-DD" da un valore ISO o null. */
function bandi_date_or_null($value): ?string
{
    if (!is_string($value) || trim($value) === '') {
        return null;
    }
    $ts = strtotime($value);
    return $ts === false ? null : date('Y-m-d', $ts);
}

function bandi_save(PDO $pdo, array $payload): array
{
    $scope = trim((string)($payload['scope'] ?? ''));
    $titolo = trim((string)($payload['titolo'] ?? ''));
    if ($scope === '' || $titolo === '') {
        json_error('Parametri mancanti (scope, titolo).', 422);
    }

    $id = trim((string)($payload['id'] ?? ''));
    if ($id === '') {
        $id = 'bnd-' . date('YmdHis') . '-' . bin2hex(random_bytes(4));
    }

    $stato = (string)($payload['stato'] ?? 'aperto');
    if (!in_array($stato, ['aperto', 'chiuso', 'archiviato'], true)) {
        $stato = 'aperto';
    }

    $listJson = static function ($value): string {
        $items = is_array($value)
            ? array_values(array_filter(array_map('strval', $value), 'strlen'))
            : [];
        return json_encode($items, JSON_UNESCAPED_UNICODE) ?: '[]';
    };
    $numOrNull = static fn($v) => is_numeric($v) ? (float)$v : null;

    $sql = 'INSERT INTO bandi (
              id, scope_id, titolo, ente, descrizione, link, note, stato,
              apertura, scadenza, dotazione, percentuale_contributo,
              importo_min, importo_max, regioni, codici_ateco, dimensioni,
              tipi, aree_investimento
            ) VALUES (
              :id, :scope_id, :titolo, :ente, :descrizione, :link, :note,
              :stato, :apertura, :scadenza, :dotazione,
              :percentuale_contributo, :importo_min, :importo_max, :regioni,
              :codici_ateco, :dimensioni, :tipi, :aree_investimento
            )
            ON DUPLICATE KEY UPDATE
              titolo = VALUES(titolo), ente = VALUES(ente),
              descrizione = VALUES(descrizione), link = VALUES(link),
              note = VALUES(note), stato = VALUES(stato),
              apertura = VALUES(apertura), scadenza = VALUES(scadenza),
              dotazione = VALUES(dotazione),
              percentuale_contributo = VALUES(percentuale_contributo),
              importo_min = VALUES(importo_min),
              importo_max = VALUES(importo_max),
              regioni = VALUES(regioni), codici_ateco = VALUES(codici_ateco),
              dimensioni = VALUES(dimensioni), tipi = VALUES(tipi),
              aree_investimento = VALUES(aree_investimento)';

    $stmt = $pdo->prepare($sql);
    $stmt->execute([
        ':id' => $id,
        ':scope_id' => $scope,
        ':titolo' => $titolo,
        ':ente' => trim((string)($payload['ente'] ?? '')),
        ':descrizione' => (string)($payload['descrizione'] ?? ''),
        ':link' => trim((string)($payload['link'] ?? '')),
        ':note' => (string)($payload['note'] ?? ''),
        ':stato' => $stato,
        ':apertura' => bandi_date_or_null($payload['apertura'] ?? null),
        ':scadenza' => bandi_date_or_null($payload['scadenza'] ?? null),
        ':dotazione' => $numOrNull($payload['dotazione'] ?? null),
        ':percentuale_contributo' => $numOrNull($payload['percentualeContributo'] ?? null),
        ':importo_min' => $numOrNull($payload['importoMin'] ?? null),
        ':importo_max' => $numOrNull($payload['importoMax'] ?? null),
        ':regioni' => $listJson($payload['regioni'] ?? null),
        ':codici_ateco' => $listJson($payload['codiciAteco'] ?? null),
        ':dimensioni' => $listJson($payload['dimensioni'] ?? null),
        ':tipi' => $listJson($payload['tipi'] ?? null),
        ':aree_investimento' => $listJson($payload['areeInvestimento'] ?? null),
    ]);

    return ['id' => $id];
}

$method = $_SERVER['REQUEST_METHOD'];

switch ($method) {
    case 'GET':
        $scope = trim((string)($_GET['scope'] ?? ''));
        if ($scope === '') {
            json_error('Parametro scope mancante.', 422);
        }
        $stmt = $pdo->prepare(
            'SELECT * FROM bandi WHERE scope_id = :scope ORDER BY
               FIELD(stato, \'aperto\', \'chiuso\', \'archiviato\'),
               scadenza IS NULL, scadenza ASC, titolo ASC'
        );
        $stmt->execute([':scope' => $scope]);
        $rows = $stmt->fetchAll(PDO::FETCH_ASSOC) ?: [];
        json_ok(['bandi' => array_map('bandi_row_to_json', $rows)]);
        break;

    case 'POST':
        $payload = request_json();
        $result = bandi_save($pdo, $payload);
        json_ok(['ok' => true, 'id' => $result['id']]);
        break;

    case 'PUT':
        $payload = request_json();
        $id = trim((string)($_GET['id'] ?? ($payload['id'] ?? '')));
        if ($id === '') {
            json_error('Parametro id mancante.', 422);
        }
        $payload['id'] = $id;
        $result = bandi_save($pdo, $payload);
        json_ok(['ok' => true, 'id' => $result['id']]);
        break;

    case 'DELETE':
        $id = trim((string)($_GET['id'] ?? ''));
        $scope = trim((string)($_GET['scope'] ?? ''));
        if ($id === '' || $scope === '') {
            json_error('Parametri id e scope obbligatori.', 422);
        }
        $stmt = $pdo->prepare(
            'DELETE FROM bandi WHERE id = :id AND scope_id = :scope'
        );
        $stmt->execute([':id' => $id, ':scope' => $scope]);
        json_ok(['ok' => true]);
        break;

    default:
        json_error('Metodo non consentito.', 405);
}
