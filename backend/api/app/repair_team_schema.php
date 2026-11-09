<?php
declare(strict_types=1);

ini_set('display_errors', '1');
ini_set('display_startup_errors', '1');
error_reporting(E_ALL);

try {
    require_once __DIR__ . '/helpers.php';
    $pdo = db();
} catch (Throwable $e) {
    http_response_code(500);
    header('Content-Type: text/html; charset=utf-8');
    echo '<h2>Errore bootstrap repair</h2><pre>' .
        htmlspecialchars($e->getMessage(), ENT_QUOTES, 'UTF-8') .
        '</pre>';
    exit;
}

$runMode = (string)($_GET['run'] ?? '') === 'yes';

if (!$runMode) {
    try {
        $uid = require_auth();
        app_require_superadmin($pdo, $uid);
    } catch (Throwable $e) {
        http_response_code(401);
        header('Content-Type: text/html; charset=utf-8');
        echo '<h2>Autenticazione richiesta</h2><p>Apri questo URL con <code>?run=yes</code> per eseguire la manutenzione una tantum dal browser, poi rimuovi il file dal server.</p>';
        exit;
    }
}

$statements = [
    "ALTER TABLE teams ADD COLUMN brand_logo_url VARCHAR(512) NOT NULL DEFAULT ''",
    "ALTER TABLE teams ADD COLUMN brand_color VARCHAR(9) NOT NULL DEFAULT ''",
    "ALTER TABLE teams MODIFY COLUMN billing_profile MEDIUMTEXT NULL",
    "ALTER TABLE teams MODIFY COLUMN subscription MEDIUMTEXT NULL",
    "ALTER TABLE teams ADD COLUMN enabled_modules MEDIUMTEXT NULL",
    "ALTER TABLE teams MODIFY COLUMN enabled_modules MEDIUMTEXT NULL",
    "ALTER TABLE teams ADD COLUMN roles_config MEDIUMTEXT NULL",
    "ALTER TABLE teams MODIFY COLUMN roles_config MEDIUMTEXT NULL",
    "ALTER TABLE teams ADD COLUMN custom_fields_config MEDIUMTEXT NULL",
    "ALTER TABLE teams MODIFY COLUMN custom_fields_config MEDIUMTEXT NULL",
    "ALTER TABLE teams MODIFY COLUMN youdox_config MEDIUMTEXT NULL",
    "UPDATE teams SET brand_logo_url = '' WHERE brand_logo_url IS NULL",
    "UPDATE teams SET brand_color = '' WHERE brand_color IS NULL",
    "UPDATE teams SET billing_profile = NULL WHERE billing_profile = ''",
    "UPDATE teams SET subscription = NULL WHERE subscription = ''",
    "UPDATE teams SET enabled_modules = NULL WHERE enabled_modules = ''",
    "UPDATE teams SET roles_config = NULL WHERE roles_config = ''",
    "UPDATE teams SET custom_fields_config = NULL WHERE custom_fields_config = ''",
    "UPDATE teams SET youdox_config = NULL WHERE youdox_config = ''",
];

$results = [];
foreach ($statements as $sql) {
    try {
        $pdo->exec($sql);
        $results[] = ['ok' => true, 'sql' => $sql, 'note' => 'eseguito'];
    } catch (Throwable $e) {
        $results[] = ['ok' => false, 'sql' => $sql, 'note' => $e->getMessage()];
    }
}

header('Content-Type: text/html; charset=utf-8');
echo '<!doctype html><html lang="it"><head><meta charset="utf-8">';
echo '<title>Repair team schema</title>';
echo '<style>body{font-family:system-ui,sans-serif;max-width:900px;margin:40px auto;padding:0 16px;color:#1c1d1f}';
echo 'pre{background:#f6f4f1;border:1px solid #e9e5df;border-radius:8px;padding:10px;white-space:pre-wrap;font-size:12px}';
echo '.ok{color:#2e7d4f}.ko{color:#a8332c}</style></head><body>';
echo '<h2>Repair schema teams</h2>';
echo '<p>Correzione colonne team per branding, moduli, ruoli e custom fields.</p>';
if ($runMode) {
    echo '<p><strong>Modalità manutenzione pubblica attiva.</strong> Rimuovi questo file dal server dopo l\'esecuzione.</p>';
}
foreach ($results as $result) {
    echo '<p class="' . ($result['ok'] ? 'ok' : 'ko') . '">' .
        ($result['ok'] ? '✓ ' : '✗ ') .
        htmlspecialchars($result['note'], ENT_QUOTES, 'UTF-8') .
        '</p><pre>' .
        htmlspecialchars($result['sql'], ENT_QUOTES, 'UTF-8') .
        '</pre>';
}
echo '</body></html>';
