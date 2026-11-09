<?php
declare(strict_types=1);

// Installazione modulo Bandi su MySQL.
// Carica questo file in /api/bandi/install.php e apri:
// /api/bandi/install.php?run=yes
//
// L'installer e idempotente: puo essere rilanciato senza cancellare dati.

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
        '<p>Aggiungi <code>?run=yes</code> all URL per creare o aggiornare la tabella <code>bandi</code>.</p>'
    );
}

if (!function_exists('db')) {
    http_response_code(500);
    die('<h2 style="color:red">bootstrap.php non espone la funzione db(): PDO.</h2>');
}

function install_result(array &$results, bool $ok, string $label, string $detail = ''): void
{
    $results[] = [
        'ok' => $ok,
        'label' => $label,
        'detail' => $detail,
    ];
}

function table_exists(PDO $pdo, string $table): bool
{
    $stmt = $pdo->prepare(
        'SELECT COUNT(*)
         FROM INFORMATION_SCHEMA.TABLES
         WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = :table'
    );
    $stmt->execute([':table' => $table]);
    return (int)$stmt->fetchColumn() > 0;
}

function column_exists(PDO $pdo, string $table, string $column): bool
{
    $stmt = $pdo->prepare(
        'SELECT COUNT(*)
         FROM INFORMATION_SCHEMA.COLUMNS
         WHERE TABLE_SCHEMA = DATABASE()
           AND TABLE_NAME = :table
           AND COLUMN_NAME = :column'
    );
    $stmt->execute([':table' => $table, ':column' => $column]);
    return (int)$stmt->fetchColumn() > 0;
}

function index_exists(PDO $pdo, string $table, string $index): bool
{
    $stmt = $pdo->prepare(
        'SELECT COUNT(*)
         FROM INFORMATION_SCHEMA.STATISTICS
         WHERE TABLE_SCHEMA = DATABASE()
           AND TABLE_NAME = :table
           AND INDEX_NAME = :index_name'
    );
    $stmt->execute([':table' => $table, ':index_name' => $index]);
    return (int)$stmt->fetchColumn() > 0;
}

function add_column_if_missing(PDO $pdo, array &$results, string $column, string $definition): void
{
    if (column_exists($pdo, 'bandi', $column)) {
        install_result($results, true, "Colonna {$column}", 'gia presente');
        return;
    }
    $sql = "ALTER TABLE bandi ADD COLUMN {$column} {$definition}";
    $pdo->exec($sql);
    install_result($results, true, "Colonna {$column}", $sql);
}

function add_index_if_missing(PDO $pdo, array &$results, string $index, string $definition): void
{
    if (index_exists($pdo, 'bandi', $index)) {
        install_result($results, true, "Indice {$index}", 'gia presente');
        return;
    }
    $sql = "ALTER TABLE bandi ADD INDEX {$index} {$definition}";
    $pdo->exec($sql);
    install_result($results, true, "Indice {$index}", $sql);
}

$results = [];

try {
    $pdo = db();
    $pdo->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);

    if (!table_exists($pdo, 'bandi')) {
        $pdo->exec(
            'CREATE TABLE bandi (
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
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci'
        );
        install_result($results, true, 'Tabella bandi', 'creata');
    } else {
        install_result($results, true, 'Tabella bandi', 'gia presente');
    }

    $columns = [
        'id' => 'VARCHAR(64) NOT NULL',
        'scope_id' => 'VARCHAR(128) NOT NULL',
        'titolo' => 'VARCHAR(255) NOT NULL',
        'ente' => 'VARCHAR(255) NOT NULL DEFAULT \'\'',
        'descrizione' => 'TEXT NULL',
        'link' => 'VARCHAR(512) NOT NULL DEFAULT \'\'',
        'note' => 'TEXT NULL',
        'stato' => 'VARCHAR(20) NOT NULL DEFAULT \'aperto\'',
        'apertura' => 'DATE NULL',
        'scadenza' => 'DATE NULL',
        'dotazione' => 'DECIMAL(14,2) NULL',
        'percentuale_contributo' => 'DECIMAL(5,2) NULL',
        'importo_min' => 'DECIMAL(14,2) NULL',
        'importo_max' => 'DECIMAL(14,2) NULL',
        'regioni' => 'TEXT NULL',
        'codici_ateco' => 'TEXT NULL',
        'dimensioni' => 'TEXT NULL',
        'tipi' => 'TEXT NULL',
        'aree_investimento' => 'TEXT NULL',
        'created_at' => 'DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP',
        'updated_at' => 'DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP',
    ];

    foreach ($columns as $column => $definition) {
        if ($column === 'id') {
            continue;
        }
        add_column_if_missing($pdo, $results, $column, $definition);
    }

    add_index_if_missing($pdo, $results, 'idx_bandi_scope', '(scope_id)');
    add_index_if_missing($pdo, $results, 'idx_bandi_stato', '(stato)');
    add_index_if_missing($pdo, $results, 'idx_bandi_scadenza', '(scadenza)');
} catch (Throwable $e) {
    install_result($results, false, 'Errore installazione', $e->getMessage());
}

$hasErrors = false;
foreach ($results as $row) {
    if (($row['ok'] ?? false) !== true) {
        $hasErrors = true;
        break;
    }
}
?>
<!doctype html>
<html lang="it">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Installazione Bandi Nexora</title>
  <style>
    :root {
      color-scheme: dark;
      --bg: #06111d;
      --panel: rgba(255, 255, 255, .12);
      --line: rgba(255, 255, 255, .22);
      --text: #f5fbff;
      --muted: rgba(245, 251, 255, .68);
      --ok: #5ff0bf;
      --err: #ff7b7b;
    }
    * { box-sizing: border-box; }
    body {
      margin: 0;
      min-height: 100vh;
      padding: 32px;
      font-family: Inter, ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
      background:
        radial-gradient(circle at 18% 10%, rgba(64, 222, 255, .28), transparent 30%),
        radial-gradient(circle at 85% 20%, rgba(74, 255, 198, .20), transparent 28%),
        linear-gradient(135deg, #06111d 0%, #0c1f35 54%, #08141f 100%);
      color: var(--text);
    }
    .shell {
      width: min(1120px, 100%);
      margin: 0 auto;
      border: 1px solid var(--line);
      border-radius: 28px;
      background: var(--panel);
      box-shadow: 0 30px 90px rgba(0, 0, 0, .34);
      backdrop-filter: blur(24px);
      overflow: hidden;
    }
    header {
      padding: 28px 30px 22px;
      border-bottom: 1px solid var(--line);
      background: rgba(255, 255, 255, .08);
    }
    h1 { margin: 0 0 8px; font-size: clamp(28px, 4vw, 44px); letter-spacing: 0; }
    p { margin: 0; color: var(--muted); line-height: 1.45; }
    .status {
      display: inline-flex;
      align-items: center;
      gap: 10px;
      margin-top: 18px;
      padding: 10px 14px;
      border-radius: 999px;
      border: 1px solid var(--line);
      background: rgba(255, 255, 255, .10);
      color: <?= $hasErrors ? 'var(--err)' : 'var(--ok)' ?>;
      font-weight: 700;
    }
    main { padding: 22px; }
    ul { list-style: none; padding: 0; margin: 0; display: grid; gap: 12px; }
    li {
      padding: 14px 16px;
      border: 1px solid rgba(255, 255, 255, .14);
      border-radius: 18px;
      background: rgba(255, 255, 255, .08);
    }
    .row { display: flex; justify-content: space-between; gap: 18px; align-items: flex-start; }
    .label { font-weight: 800; }
    .ok { color: var(--ok); }
    .err { color: var(--err); }
    code {
      display: inline-block;
      margin-top: 8px;
      padding: 8px 10px;
      max-width: 100%;
      overflow: auto;
      border-radius: 12px;
      color: var(--muted);
      background: rgba(0, 0, 0, .22);
      font-size: 12px;
    }
  </style>
</head>
<body>
  <section class="shell">
    <header>
      <h1>Bandi su MySQL</h1>
      <p>Installer Nexora per usare il modulo bandi tramite API PHP/MySQL, senza Firestore come storage principale.</p>
      <div class="status">
        <?= $hasErrors ? 'Installazione completata con errori' : 'Installazione completata con successo' ?>
      </div>
    </header>
    <main>
      <ul>
        <?php foreach ($results as $row): ?>
          <li>
            <div class="row">
              <span class="label"><?= htmlspecialchars((string)$row['label'], ENT_QUOTES, 'UTF-8') ?></span>
              <strong class="<?= ($row['ok'] ?? false) ? 'ok' : 'err' ?>">
                <?= ($row['ok'] ?? false) ? 'OK' : 'ERRORE' ?>
              </strong>
            </div>
            <?php if (($row['detail'] ?? '') !== ''): ?>
              <code><?= htmlspecialchars((string)$row['detail'], ENT_QUOTES, 'UTF-8') ?></code>
            <?php endif; ?>
          </li>
        <?php endforeach; ?>
      </ul>
      <p style="margin-top:22px">Endpoint operativo: <code>/api/bandi/index.php</code></p>
      <p style="margin-top:10px">Dopo l installazione elimina o rinomina questo file dal server.</p>
    </main>
  </section>
</body>
</html>
