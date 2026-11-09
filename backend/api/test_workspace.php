<?php
// Apri nel browser per vedere cosa ritorna il workspace per il tuo utente.
// Richiede che tu sia loggato e abbia un JWT valido in mano.
// Elimina dopo il debug.
//
// Uso: /api/test_workspace.php?token=IL_TUO_ACCESS_TOKEN

require_once __DIR__ . '/bootstrap.php';

$token = $_GET['token'] ?? '';
if (empty($token)) {
    die('<b>Passa il token come parametro: /api/test_workspace.php?token=...</b><br>
         Puoi trovarlo nella console del browser → Application → Local Storage → nexora_access_token');
}

$payload = verify_access_token($token);
if (!$payload) die('<b>Token non valido o scaduto</b>');

$userId = $payload['sub'];

function qry(string $sql, array $p = []): array {
    try { $st = db()->prepare($sql); $st->execute($p); return $st->fetchAll(); }
    catch (Throwable $e) { return ['ERROR' => $e->getMessage()]; }
}

$results = [
    'userId'           => $userId,
    'companies_count'  => count(qry('SELECT id FROM companies WHERE user_id = ?', [$userId])),
    'companies_first'  => qry('SELECT * FROM companies WHERE user_id = ? LIMIT 1', [$userId]),
    'tables_existing'  => [],
    'tables_missing'   => [],
];

$tables = ['companies','company_contacts','opportunities','preventivi','projects',
           'project_phases','work_tasks','invoice_drafts','tickets',
           'user_availability','vacation_periods','time_tracks','timeline_slots','users'];

foreach ($tables as $t) {
    try {
        db()->query("SELECT 1 FROM $t LIMIT 1");
        $results['tables_existing'][] = $t;
    } catch (Throwable $e) {
        $results['tables_missing'][] = $t . ': ' . $e->getMessage();
    }
}

header('Content-Type: application/json');
echo json_encode($results, JSON_PRETTY_PRINT | JSON_UNESCAPED_UNICODE);
