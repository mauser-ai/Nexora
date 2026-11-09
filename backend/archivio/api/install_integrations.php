<?php
declare(strict_types=1);

require_once __DIR__ . '/common.php';

if (($_GET['run'] ?? '') !== 'yes') {
    die(
        '<h2>Aggiungi <code>?run=yes</code> all URL per avviare l installazione integrazioni.</h2>'
    );
}

$statements = [
    'CREATE TABLE IF NOT EXISTS archive_integrations (
      id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
      user_id VARCHAR(128) NOT NULL DEFAULT \'default\',
      provider VARCHAR(40) NOT NULL,
      account_email VARCHAR(190) NULL,
      access_token TEXT NOT NULL,
      refresh_token TEXT NULL,
      expires_at DATETIME NULL,
      scope TEXT NULL,
      token_type VARCHAR(40) NULL,
      created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
      updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
      UNIQUE KEY uniq_archive_integrations_user_provider (user_id, provider),
      INDEX idx_archive_integrations_provider (provider),
      INDEX idx_archive_integrations_user_id (user_id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci',
];

$results = [];

try {
    $pdo = integrations_pdo();
    foreach ($statements as $sql) {
        try {
            $pdo->exec($sql);
            $results[] = ['ok' => true, 'sql' => $sql];
        } catch (Throwable $e) {
            $message = $e->getMessage();
            $alreadyExists =
                stripos($message, 'Duplicate key name') !== false ||
                stripos($message, 'already exists') !== false;
            if ($alreadyExists) {
                $results[] = [
                    'ok' => true,
                    'sql' => $sql,
                    'note' => 'Gia presente',
                ];
                continue;
            }
            $results[] = ['ok' => false, 'sql' => $sql, 'error' => $message];
        }
    }
} catch (Throwable $e) {
    die(
        '<h2 style="color:red">Errore installazione integrazioni: ' .
        htmlspecialchars($e->getMessage(), ENT_QUOTES, 'UTF-8') .
        '</h2>'
    );
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
  <title>Installazione Integrazioni Archivio</title>
  <style>
    body { font-family: Arial, sans-serif; background: #eef6fb; color: #111827; padding: 24px; }
    .ok { color: #087443; }
    .err { color: #b42318; }
    .card { background: rgba(255,255,255,.82); border: 1px solid rgba(255,255,255,.9); border-radius: 18px; padding: 22px; max-width: 1100px; box-shadow: 0 18px 50px rgba(15,23,42,.12); }
    code, pre { background: rgba(15,23,42,.06); border-radius: 8px; padding: 2px 6px; }
    pre { padding: 12px; overflow: auto; white-space: pre-wrap; }
    li { margin-bottom: 14px; }
  </style>
</head>
<body>
  <div class="card">
    <h1>Installazione Integrazioni Archivio</h1>
    <p class="<?= $hasErrors ? 'err' : 'ok' ?>">
      <?= $hasErrors ? 'Installazione completata con errori.' : 'Installazione completata con successo.' ?>
    </p>
    <ul>
      <?php foreach ($results as $row): ?>
        <li>
          <div class="<?= ($row['ok'] ?? false) ? 'ok' : 'err' ?>">
            <?= ($row['ok'] ?? false) ? 'OK' : 'ERRORE' ?>
            <?php if (!empty($row['note'])): ?>
              - <?= htmlspecialchars((string)$row['note'], ENT_QUOTES, 'UTF-8') ?>
            <?php endif; ?>
          </div>
          <pre><?= htmlspecialchars((string)$row['sql'], ENT_QUOTES, 'UTF-8') ?></pre>
          <?php if (!empty($row['error'])): ?>
            <pre class="err"><?= htmlspecialchars((string)$row['error'], ENT_QUOTES, 'UTF-8') ?></pre>
          <?php endif; ?>
        </li>
      <?php endforeach; ?>
    </ul>
    <p>Per sicurezza, dopo l uso elimina o rinomina <code>install_integrations.php</code>.</p>
  </div>
</body>
</html>
