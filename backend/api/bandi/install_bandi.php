<?php
declare(strict_types=1);

// ─────────────────────────────────────────────────────────────────────────────
// Installazione modulo Bandi (Centro Studi).
// Apri nel browser:  /api/bandi/install_bandi.php?run=yes
// Crea (o aggiorna) la tabella `bandi` in modo idempotente: si può rilanciare
// senza rischi. Richiede il bootstrap dell'API che espone db(): PDO.
// ─────────────────────────────────────────────────────────────────────────────

ini_set('display_errors', '1');
ini_set('display_startup_errors', '1');
error_reporting(E_ALL);

try {
    require_once dirname(__DIR__) . '/bootstrap.php';
} catch (Throwable $e) {
    http_response_code(500);
    die(
        '<h2 style="color:red">Errore caricamento bootstrap.php</h2><pre>' .
        htmlspecialchars($e->getMessage(), ENT_QUOTES, 'UTF-8') .
        '</pre>'
    );
}

if (($_GET['run'] ?? '') !== 'yes') {
    die(
        '<h2>Installazione modulo Bandi</h2>' .
        '<p>Aggiungi <code>?run=yes</code> all\'URL per creare/aggiornare la tabella <code>bandi</code>.</p>'
    );
}

if (!function_exists('db')) {
    http_response_code(500);
    die('<h2 style="color:red">bootstrap.php non espone la funzione db(): PDO.</h2>');
}

$statements = [
    // Tabella principale. Le liste (regioni, ATECO, dimensioni, tipi, aree
    // investimento) sono salvate come JSON in colonne TEXT per massima
    // compatibilità con MySQL/MariaDB datati.
    'CREATE TABLE IF NOT EXISTS bandi (
      id VARCHAR(64) NOT NULL PRIMARY KEY,
      scope_id VARCHAR(128) NOT NULL,
      titolo VARCHAR(255) NOT NULL,
      ente VARCHAR(255) NOT NULL DEFAULT \'\',
      descrizione TEXT NULL,
      link VARCHAR(512) NOT NULL DEFAULT \'\',
      note TEXT NULL,
      stato VARCHAR(20) NOT NULL DEFAULT \'aperto\',
      apertura DATE NULL,
      scadenza DATE NULL,
      dotazione DECIMAL(14,2) NULL,
      percentuale_contributo DECIMAL(5,2) NULL,
      importo_min DECIMAL(14,2) NULL,
      importo_max DECIMAL(14,2) NULL,
      regioni TEXT NULL,
      codici_ateco TEXT NULL,
      dimensioni TEXT NULL,
      tipi TEXT NULL,
      aree_investimento TEXT NULL,
      created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
      updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
      INDEX idx_bandi_scope (scope_id),
      INDEX idx_bandi_stato (stato),
      INDEX idx_bandi_scadenza (scadenza)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci',
];

// Migrazioni additive future: ALTER tollerante se la colonna esiste già.
$alterStatements = [
    // esempio: "ALTER TABLE bandi ADD COLUMN nuovo_campo VARCHAR(64) NULL",
];

$results = [];

try {
    $pdo = db();
    foreach ($statements as $sql) {
        try {
            $pdo->exec($sql);
            $results[] = ['ok' => true, 'sql' => $sql, 'note' => 'eseguito'];
        } catch (Throwable $e) {
            $results[] = ['ok' => false, 'sql' => $sql, 'note' => $e->getMessage()];
        }
    }
    foreach ($alterStatements as $sql) {
        try {
            $pdo->exec($sql);
            $results[] = ['ok' => true, 'sql' => $sql, 'note' => 'eseguito'];
        } catch (Throwable $e) {
            // Colonna già presente o simili: non bloccante.
            $results[] = ['ok' => true, 'sql' => $sql, 'note' => 'saltato: ' . $e->getMessage()];
        }
    }
} catch (Throwable $e) {
    http_response_code(500);
    die(
        '<h2 style="color:red">Connessione database fallita</h2><pre>' .
        htmlspecialchars($e->getMessage(), ENT_QUOTES, 'UTF-8') .
        '</pre>'
    );
}

$allOk = true;
foreach ($results as $r) {
    if (!$r['ok']) {
        $allOk = false;
    }
}

echo '<!doctype html><html lang="it"><head><meta charset="utf-8">';
echo '<title>Install Bandi</title>';
echo '<style>body{font-family:system-ui,sans-serif;max-width:860px;margin:40px auto;padding:0 16px;color:#1c1d1f}';
echo 'pre{background:#f6f4f1;border:1px solid #e9e5df;border-radius:8px;padding:10px;white-space:pre-wrap;font-size:12px}';
echo '.ok{color:#2e7d4f}.ko{color:#a8332c}</style></head><body>';
echo $allOk
    ? '<h2 class="ok">✓ Modulo Bandi installato/aggiornato correttamente</h2>'
    : '<h2 class="ko">✗ Installazione completata con errori</h2>';
foreach ($results as $r) {
    echo '<p class="' . ($r['ok'] ? 'ok' : 'ko') . '">' . ($r['ok'] ? '✓' : '✗') . ' ' .
        htmlspecialchars($r['note'], ENT_QUOTES, 'UTF-8') . '</p>';
    echo '<pre>' . htmlspecialchars($r['sql'], ENT_QUOTES, 'UTF-8') . '</pre>';
}
echo '<p>Endpoint dati: <code>/api/bandi/index.php</code></p>';
echo '</body></html>';
