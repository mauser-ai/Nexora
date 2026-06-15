<?php
declare(strict_types=1);

require_once dirname(__DIR__) . '/bootstrap.php';

if (($_GET['run'] ?? '') !== 'yes') {
    die(
        '<h2>Aggiungi <code>?run=yes</code> all\'URL per avviare l\'installazione chat.</h2>'
    );
}

$statements = [
    'CREATE TABLE IF NOT EXISTS chat_groups (
      id CHAR(36) PRIMARY KEY,
      name VARCHAR(190) NOT NULL,
      description TEXT NULL,
      created_by VARCHAR(128) NOT NULL,
      created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4',

    'CREATE TABLE IF NOT EXISTS chat_group_members (
      group_id CHAR(36) NOT NULL,
      user_id VARCHAR(128) NOT NULL,
      display_name VARCHAR(190) NOT NULL,
      email VARCHAR(190) NOT NULL DEFAULT \'\',
      role VARCHAR(100) NOT NULL DEFAULT \'\',
      joined_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
      last_read_message_id CHAR(36) NULL,
      last_read_at DATETIME NULL,
      PRIMARY KEY (group_id, user_id),
      CONSTRAINT fk_chat_member_group
        FOREIGN KEY (group_id) REFERENCES chat_groups(id)
        ON DELETE CASCADE
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4',

    'CREATE TABLE IF NOT EXISTS chat_messages (
      id CHAR(36) PRIMARY KEY,
      group_id CHAR(36) NOT NULL,
      user_id VARCHAR(128) NOT NULL,
      author_name VARCHAR(190) NOT NULL,
      body TEXT NOT NULL,
      created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
      CONSTRAINT fk_chat_message_group
        FOREIGN KEY (group_id) REFERENCES chat_groups(id)
        ON DELETE CASCADE
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4',

    'CREATE INDEX idx_chat_messages_group_created
      ON chat_messages(group_id, created_at)',

    'CREATE INDEX idx_chat_members_user
      ON chat_group_members(user_id)',
];

$results = [];

try {
    $pdo = db();
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
                $results[] = ['ok' => true, 'sql' => $sql, 'note' => 'Già presente'];
                continue;
            }
            $results[] = ['ok' => false, 'sql' => $sql, 'error' => $message];
        }
    }
} catch (Throwable $e) {
    die('<h2 style="color:red">Errore installazione chat: ' . htmlspecialchars($e->getMessage(), ENT_QUOTES, 'UTF-8') . '</h2>');
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
  <title>Installazione Chat</title>
  <style>
    body { font-family: Arial, sans-serif; background: #f7f5f2; color: #24160f; padding: 24px; }
    .ok { color: #0f7a44; }
    .err { color: #b42318; }
    .card { background: #fff; border: 1px solid #ddd5c8; border-radius: 12px; padding: 20px; max-width: 1100px; }
    code, pre { background: #f3eee7; border-radius: 8px; padding: 2px 6px; }
    pre { padding: 12px; overflow: auto; white-space: pre-wrap; }
    li { margin-bottom: 14px; }
  </style>
</head>
<body>
  <div class="card">
    <h1>Installazione Chat</h1>
    <p class="<?= $hasErrors ? 'err' : 'ok' ?>">
      <?= $hasErrors ? 'Installazione completata con errori.' : 'Installazione completata con successo.' ?>
    </p>
    <ul>
      <?php foreach ($results as $row): ?>
        <li>
          <div class="<?= ($row['ok'] ?? false) ? 'ok' : 'err' ?>">
            <?= ($row['ok'] ?? false) ? 'OK' : 'ERRORE' ?>
            <?php if (!empty($row['note'])): ?>
              — <?= htmlspecialchars((string)$row['note'], ENT_QUOTES, 'UTF-8') ?>
            <?php endif; ?>
          </div>
          <pre><?= htmlspecialchars((string)$row['sql'], ENT_QUOTES, 'UTF-8') ?></pre>
          <?php if (!empty($row['error'])): ?>
            <pre class="err"><?= htmlspecialchars((string)$row['error'], ENT_QUOTES, 'UTF-8') ?></pre>
          <?php endif; ?>
        </li>
      <?php endforeach; ?>
    </ul>
    <p>Per sicurezza, dopo l'uso elimina o rinomina <code>install_chat.php</code>.</p>
  </div>
</body>
</html>
