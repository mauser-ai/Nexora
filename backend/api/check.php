<?php
// ── Diagnostica rapida — apri nel browser: /api/check.php
// Elimina questo file dopo aver risolto i problemi.
require_once __DIR__ . '/config.php';

$checks = [];

// 1. Connessione DB
try {
    $pdo = new PDO(
        "mysql:host=" . DB_HOST . ";port=" . DB_PORT . ";dbname=" . DB_NAME . ";charset=" . DB_CHARSET,
        DB_USER, DB_PASS, [PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION]
    );
    $tables = $pdo->query("SHOW TABLES")->fetchAll(PDO::FETCH_COLUMN);
    $checks[] = ['ok', 'Database connesso — ' . count($tables) . ' tabelle trovate: ' . implode(', ', array_slice($tables, 0, 5)) . (count($tables) > 5 ? '...' : '')];
} catch (Exception $e) {
    $checks[] = ['err', 'Database: ' . $e->getMessage()];
}

// 2. Firebase Project ID
if (str_contains(FIREBASE_PROJECT_ID, 'INSERISCI')) {
    $checks[] = ['err', 'FIREBASE_PROJECT_ID non configurato in config.php'];
} else {
    $checks[] = ['ok', 'Firebase Project ID: ' . FIREBASE_PROJECT_ID];
}

// 3. JWT secrets
if (str_contains(JWT_ACCESS_SECRET, 'INSERISCI')) {
    $checks[] = ['err', 'JWT_ACCESS_SECRET non configurato'];
} else {
    $checks[] = ['ok', 'JWT secrets configurati'];
}

// 4. cURL disponibile
if (function_exists('curl_init')) {
    $checks[] = ['ok', 'cURL disponibile'];
} else {
    $checks[] = ['warn', 'cURL non disponibile — userà file_get_contents'];
}

// 5. allow_url_fopen
if (ini_get('allow_url_fopen')) {
    $checks[] = ['ok', 'allow_url_fopen abilitato'];
} else {
    $checks[] = ['warn', 'allow_url_fopen disabilitato (OK se cURL è disponibile)'];
}

// 6. OpenSSL
if (function_exists('openssl_verify')) {
    $checks[] = ['ok', 'OpenSSL disponibile'];
} else {
    $checks[] = ['err', 'OpenSSL non disponibile — necessario per verificare Firebase tokens'];
}

// 7. Raggiungibilità Google (per chiavi pubbliche Firebase)
require_once __DIR__ . '/middleware/auth.php';
$raw = _fetch_url('https://www.googleapis.com/robot/v1/metadata/x509/securetoken@system.gserviceaccount.com');
if ($raw) {
    $keys = json_decode($raw, true);
    $checks[] = ['ok', 'Chiavi Firebase Google raggiungibili — ' . count($keys) . ' chiavi trovate'];
} else {
    $checks[] = ['err', 'Impossibile raggiungere Google per le chiavi Firebase (problema di rete o firewall)'];
}

// 8. Tabella users
try {
    $count = $pdo->query("SELECT COUNT(*) FROM users")->fetchColumn();
    $checks[] = ['ok', "Tabella users: $count utenti registrati"];
} catch (Exception $e) {
    $checks[] = ['err', 'Tabella users: ' . $e->getMessage()];
}

// ── Output HTML ───────────────────────────────────────────────────────────────
?><!DOCTYPE html>
<html lang="it">
<head>
<meta charset="utf-8">
<title>Nexora — Diagnostica</title>
<style>
  body { font-family: system-ui; max-width: 800px; margin: 40px auto; padding: 0 20px; background:#f5f5f0; }
  h1   { font-size: 20px; }
  .row { display:flex; gap:12px; align-items:flex-start; padding:8px 12px; border-radius:6px; margin:4px 0; font-size:13px; }
  .ok   { background:#f0fdf4; } .err { background:#fff1f2; } .warn { background:#fefce8; }
  .tag  { font-weight:700; flex-shrink:0; width:16px; }
  .fix  { margin-top:20px; background:#fef9c3; border:1px solid #fde047; padding:14px 16px; border-radius:8px; font-size:13px; }
  code  { background:#e5e7eb; padding:2px 6px; border-radius:4px; font-size:12px; }
</style>
</head>
<body>
<h1>🔍 Nexora — Diagnostica API</h1>
<?php foreach ($checks as [$type, $msg]): ?>
<div class="row <?= $type ?>">
  <span class="tag"><?= $type === 'ok' ? '✓' : ($type === 'err' ? '✗' : '⚠') ?></span>
  <?= htmlspecialchars($msg) ?>
</div>
<?php endforeach; ?>

<?php if (str_contains(FIREBASE_PROJECT_ID, 'INSERISCI')): ?>
<div class="fix">
  <strong>⚠️ Azione richiesta:</strong><br><br>
  Apri <code>api/config.php</code> e imposta:<br><br>
  <code>define('FIREBASE_PROJECT_ID', 'il-tuo-project-id');</code><br><br>
  Trovalo in: <a href="https://console.firebase.google.com" target="_blank">console.firebase.google.com</a>
  → clicca sull'ingranaggio (⚙️) → <em>Impostazioni progetto</em> → campo <strong>ID progetto</strong>
</div>
<?php endif; ?>

<p style="margin-top:20px;font-size:12px;color:#888;">
  Elimina <code>check.php</code> dal server dopo aver risolto tutti gli errori.
</p>
</body>
</html>
