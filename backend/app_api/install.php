<?php
declare(strict_types=1);

// ─────────────────────────────────────────────────────────────────────────────
// INSTALLER UNICO — porta su MySQL tutto ciò che prima viveva su Firestore
// (eccetto auth e notifiche push, che restano su Firebase).
//
// Apri nel browser:  /api/app/install.php?run=yes
//
// Idempotente: rilanciabile senza rischi. Crea/aggiorna:
//   • user_profiles       → profili, preferenze e RUOLI piattaforma
//   • user_integrations   → credenziali integrazioni (Drive, Aruba, …)
//   • document_templates  → template PDF (preventivi/fatture)
//   • email_templates     → template email
//   • template_choices    → template scelto per singolo documento
//   • teams, team_members → team, membri e branding
//   • memos               → lavagne memo condivise
//   • bandi               → anagrafica bandi Centro Studi
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
        '<h2>Installer piattaforma (migrazione da Firestore a MySQL)</h2>' .
        '<p>Aggiungi <code>?run=yes</code> all\'URL per creare/aggiornare tutte le tabelle.</p>'
    );
}

if (!function_exists('db')) {
    http_response_code(500);
    die('<h2 style="color:red">bootstrap.php non espone la funzione db(): PDO.</h2>');
}

$statements = [
    // ── Profili utente, preferenze e ruoli piattaforma ────────────────────
    // role: superadmin (gestione completa piattaforma, possono essercene
    // più di uno), admin (gestione team), operatore (uso standard).
    'CREATE TABLE IF NOT EXISTS user_profiles (
      uid VARCHAR(128) NOT NULL PRIMARY KEY,
      email VARCHAR(190) NOT NULL DEFAULT \'\',
      display_name VARCHAR(190) NOT NULL DEFAULT \'\',
      avatar_url VARCHAR(512) NOT NULL DEFAULT \'\',
      role VARCHAR(20) NOT NULL DEFAULT \'operatore\',
      accent_color VARCHAR(9) NOT NULL DEFAULT \'\',
      wallpaper_url VARCHAR(512) NOT NULL DEFAULT \'\',
      desktop_notifications TINYINT(1) NOT NULL DEFAULT 1,
      created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
      updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
      INDEX idx_user_profiles_email (email),
      INDEX idx_user_profiles_role (role)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci',

    // ── Credenziali integrazioni (payload JSON per provider) ──────────────
    'CREATE TABLE IF NOT EXISTS user_integrations (
      id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
      user_id VARCHAR(128) NOT NULL,
      integration_key VARCHAR(60) NOT NULL,
      payload TEXT NULL,
      created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
      updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
      UNIQUE KEY uniq_user_integration (user_id, integration_key),
      INDEX idx_user_integrations_user (user_id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci',

    // ── Template PDF ───────────────────────────────────────────────────────
    'CREATE TABLE IF NOT EXISTS document_templates (
      id VARCHAR(64) NOT NULL PRIMARY KEY,
      user_id VARCHAR(128) NOT NULL,
      name VARCHAR(190) NOT NULL DEFAULT \'\',
      category VARCHAR(30) NOT NULL DEFAULT \'preventivo\',
      background_image_url VARCHAR(512) NULL,
      elements MEDIUMTEXT NULL,
      custom_fields TEXT NULL,
      created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
      updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
      INDEX idx_document_templates_user (user_id),
      INDEX idx_document_templates_cat (user_id, category)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci',

    // ── Template email ─────────────────────────────────────────────────────
    'CREATE TABLE IF NOT EXISTS email_templates (
      id VARCHAR(64) NOT NULL PRIMARY KEY,
      user_id VARCHAR(128) NOT NULL,
      name VARCHAR(190) NOT NULL DEFAULT \'\',
      category VARCHAR(30) NOT NULL DEFAULT \'preventivo\',
      subject VARCHAR(255) NOT NULL DEFAULT \'\',
      body MEDIUMTEXT NULL,
      created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
      updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
      INDEX idx_email_templates_user (user_id),
      INDEX idx_email_templates_cat (user_id, category)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci',

    // ── Template scelto per documento (preventivo/fattura) ────────────────
    'CREATE TABLE IF NOT EXISTS template_choices (
      id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
      user_id VARCHAR(128) NOT NULL,
      doc_id VARCHAR(128) NOT NULL,
      template_id VARCHAR(64) NOT NULL,
      updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
      UNIQUE KEY uniq_template_choice (user_id, doc_id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci',

    // ── Team e membri ──────────────────────────────────────────────────────
    'CREATE TABLE IF NOT EXISTS teams (
      id VARCHAR(64) NOT NULL PRIMARY KEY,
      name VARCHAR(190) NOT NULL DEFAULT \'\',
      owner_id VARCHAR(128) NOT NULL,
      brand_logo_url VARCHAR(512) NOT NULL DEFAULT \'\',
      brand_color VARCHAR(9) NOT NULL DEFAULT \'\',
      created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
      updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
      INDEX idx_teams_owner (owner_id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci',

    'CREATE TABLE IF NOT EXISTS team_members (
      id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
      team_id VARCHAR(64) NOT NULL,
      user_id VARCHAR(128) NOT NULL,
      email VARCHAR(190) NOT NULL DEFAULT \'\',
      display_name VARCHAR(190) NOT NULL DEFAULT \'\',
      role VARCHAR(60) NOT NULL DEFAULT \'\',
      status VARCHAR(20) NOT NULL DEFAULT \'active\',
      joined_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
      UNIQUE KEY uniq_team_member (team_id, user_id),
      INDEX idx_team_members_user (user_id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci',

    // ── Memo condivise (lavagne) ───────────────────────────────────────────
    'CREATE TABLE IF NOT EXISTS memos (
      id VARCHAR(64) NOT NULL PRIMARY KEY,
      scope_id VARCHAR(128) NOT NULL,
      title VARCHAR(255) NOT NULL DEFAULT \'\',
      created_by VARCHAR(128) NOT NULL DEFAULT \'\',
      created_by_name VARCHAR(190) NOT NULL DEFAULT \'\',
      payload MEDIUMTEXT NULL,
      created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
      updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
      INDEX idx_memos_scope (scope_id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci',

    // ── Bandi (Centro Studi) ───────────────────────────────────────────────
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

// Migrazioni additive future (ALTER tolleranti, non bloccanti se già applicate).
$alterStatements = [
    // esempio: "ALTER TABLE user_profiles ADD COLUMN telefono VARCHAR(40) NULL",
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
echo '<title>Install piattaforma</title>';
echo '<style>body{font-family:system-ui,sans-serif;max-width:880px;margin:40px auto;padding:0 16px;color:#1c1d1f}';
echo 'pre{background:#f6f4f1;border:1px solid #e9e5df;border-radius:8px;padding:10px;white-space:pre-wrap;font-size:12px}';
echo '.ok{color:#2e7d4f}.ko{color:#a8332c}</style></head><body>';
echo $allOk
    ? '<h2 class="ok">✓ Schema piattaforma installato/aggiornato correttamente</h2>'
    : '<h2 class="ko">✗ Installazione completata con errori</h2>';
echo '<p>Tabelle: user_profiles, user_integrations, document_templates, email_templates, '
    . 'template_choices, teams, team_members, memos, bandi.</p>'
    . '<p><strong>Nota ruoli:</strong> il primo utente che accede dopo l\'installazione '
    . 'diventa automaticamente <code>superadmin</code>; gli altri nascono '
    . '<code>operatore</code> e si gestiscono da Impostazioni → Profilo → Gestione utenti.</p>';
foreach ($results as $r) {
    echo '<p class="' . ($r['ok'] ? 'ok' : 'ko') . '">' . ($r['ok'] ? '✓' : '✗') . ' ' .
        htmlspecialchars($r['note'], ENT_QUOTES, 'UTF-8') . '</p>';
    echo '<pre>' . htmlspecialchars($r['sql'], ENT_QUOTES, 'UTF-8') . '</pre>';
}
echo '</body></html>';
