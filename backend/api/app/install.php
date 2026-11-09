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
//   • configuration_packages → catalogo preset settore e pacchetti custom field
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

    'CREATE TABLE IF NOT EXISTS invoice_payment_allocations (
      id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
      team_id VARCHAR(128) NOT NULL,
      payment_intent_id VARCHAR(64) NOT NULL,
      invoice_id VARCHAR(64) NOT NULL,
      company_id VARCHAR(64) NOT NULL,
      amount DECIMAL(14,2) NOT NULL DEFAULT 0,
      allocation_type VARCHAR(32) NOT NULL DEFAULT \'invoice_partial\',
      created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
      INDEX idx_invoice_payment_allocations_invoice (invoice_id),
      INDEX idx_invoice_payment_allocations_payment (payment_intent_id),
      INDEX idx_invoice_payment_allocations_team (team_id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci',

    // ── Team e membri ──────────────────────────────────────────────────────
    'CREATE TABLE IF NOT EXISTS teams (
      id VARCHAR(64) NOT NULL PRIMARY KEY,
      name VARCHAR(190) NOT NULL DEFAULT \'\',
      owner_id VARCHAR(128) NOT NULL,
      brand_logo_url VARCHAR(512) NOT NULL DEFAULT \'\',
      brand_color VARCHAR(9) NOT NULL DEFAULT \'\',
      billing_profile MEDIUMTEXT NULL,
      subscription MEDIUMTEXT NULL,
      enabled_modules MEDIUMTEXT NULL,
      roles_config MEDIUMTEXT NULL,
      custom_fields_config MEDIUMTEXT NULL,
      applied_package_ids MEDIUMTEXT NULL,
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

    'CREATE TABLE IF NOT EXISTS configuration_packages (
      id VARCHAR(64) NOT NULL PRIMARY KEY,
      package_type VARCHAR(32) NOT NULL DEFAULT \'custom_fields\',
      name VARCHAR(190) NOT NULL DEFAULT \'\',
      description TEXT NULL,
      icon VARCHAR(48) NOT NULL DEFAULT \'\',
      color VARCHAR(16) NOT NULL DEFAULT \'\',
      modules_json MEDIUMTEXT NULL,
      roles_json MEDIUMTEXT NULL,
      custom_fields_json MEDIUMTEXT NULL,
      metadata_json MEDIUMTEXT NULL,
      is_system TINYINT(1) NOT NULL DEFAULT 1,
      is_active TINYINT(1) NOT NULL DEFAULT 1,
      sort_order INT NOT NULL DEFAULT 0,
      created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
      updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
      INDEX idx_configuration_packages_type (package_type),
      INDEX idx_configuration_packages_active (is_active, sort_order)
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

    'CREATE TABLE IF NOT EXISTS pos_devices (
      id VARCHAR(64) NOT NULL PRIMARY KEY,
      team_id VARCHAR(128) NOT NULL,
      user_id VARCHAR(128) NOT NULL,
      label VARCHAR(190) NOT NULL DEFAULT \'\',
      platform VARCHAR(40) NOT NULL DEFAULT \'flutter\',
      provider VARCHAR(60) NOT NULL DEFAULT \'manual\',
      status VARCHAR(32) NOT NULL DEFAULT \'ready\',
      capabilities_json MEDIUMTEXT NULL,
      last_seen_at DATETIME NULL,
      created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
      updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
      INDEX idx_pos_devices_team (team_id),
      INDEX idx_pos_devices_user (user_id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci',

    'CREATE TABLE IF NOT EXISTS pos_payment_intents (
      id VARCHAR(64) NOT NULL PRIMARY KEY,
      team_id VARCHAR(128) NOT NULL,
      created_by_user_id VARCHAR(128) NOT NULL,
      company_id VARCHAR(64) NULL,
      company_name VARCHAR(255) NULL,
      invoice_id VARCHAR(64) NULL,
      opportunity_id VARCHAR(64) NULL,
      title VARCHAR(255) NOT NULL DEFAULT \'\',
      description TEXT NULL,
      amount DECIMAL(14,2) NOT NULL DEFAULT 0,
      currency VARCHAR(8) NOT NULL DEFAULT \'EUR\',
      status VARCHAR(32) NOT NULL DEFAULT \'draft\',
      provider VARCHAR(60) NOT NULL DEFAULT \'manual\',
      source VARCHAR(40) NOT NULL DEFAULT \'desktop\',
      is_demo TINYINT(1) NOT NULL DEFAULT 1,
      payment_mode VARCHAR(32) NOT NULL DEFAULT \'spot\',
      invoice_number_snapshot VARCHAR(128) NULL,
      stripe_payment_intent_id VARCHAR(128) NULL,
      stripe_client_secret VARCHAR(255) NULL,
      stripe_connected_account_id VARCHAR(128) NULL,
      terminal_location_id VARCHAR(128) NULL,
      generated_invoice_id VARCHAR(64) NULL,
      auto_generated_invoice TINYINT(1) NOT NULL DEFAULT 0,
      paid_amount DECIMAL(14,2) NULL,
      payment_method_label VARCHAR(120) NULL,
      failure_reason TEXT NULL,
      mobile_checkout_json MEDIUMTEXT NULL,
      metadata_json MEDIUMTEXT NULL,
      completed_at DATETIME NULL,
      created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
      updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
      INDEX idx_pos_payment_intents_team (team_id, created_at),
      INDEX idx_pos_payment_intents_status (team_id, status)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci',

    'CREATE TABLE IF NOT EXISTS team_stripe_connections (
      team_id VARCHAR(64) NOT NULL PRIMARY KEY,
      stripe_account_id VARCHAR(128) NOT NULL,
      account_type VARCHAR(32) NOT NULL DEFAULT \'express\',
      onboarding_status VARCHAR(40) NOT NULL DEFAULT \'not_connected\',
      account_email VARCHAR(190) NOT NULL DEFAULT \'\',
      country VARCHAR(8) NOT NULL DEFAULT \'IT\',
      default_currency VARCHAR(8) NOT NULL DEFAULT \'eur\',
      details_submitted TINYINT(1) NOT NULL DEFAULT 0,
      charges_enabled TINYINT(1) NOT NULL DEFAULT 0,
      payouts_enabled TINYINT(1) NOT NULL DEFAULT 0,
      requirements_json MEDIUMTEXT NULL,
      metadata_json MEDIUMTEXT NULL,
      is_active TINYINT(1) NOT NULL DEFAULT 1,
      created_by_user_id VARCHAR(128) NOT NULL,
      connected_at DATETIME NULL,
      last_synced_at DATETIME NULL,
      created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
      updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
      UNIQUE KEY uniq_team_stripe_account (stripe_account_id),
      INDEX idx_team_stripe_status (onboarding_status),
      INDEX idx_team_stripe_active (is_active)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci',
];

// Migrazioni additive future (ALTER tolleranti, non bloccanti se già applicate).
$alterStatements = [
    "ALTER TABLE teams ADD COLUMN billing_profile MEDIUMTEXT NULL",
    "ALTER TABLE teams ADD COLUMN subscription MEDIUMTEXT NULL",
    "ALTER TABLE teams ADD COLUMN enabled_modules MEDIUMTEXT NULL",
    "ALTER TABLE teams ADD COLUMN roles_config MEDIUMTEXT NULL",
    "ALTER TABLE teams ADD COLUMN custom_fields_config MEDIUMTEXT NULL",
    "ALTER TABLE teams ADD COLUMN applied_package_ids MEDIUMTEXT NULL",
    "ALTER TABLE teams MODIFY COLUMN billing_profile MEDIUMTEXT NULL",
    "ALTER TABLE teams MODIFY COLUMN subscription MEDIUMTEXT NULL",
    "ALTER TABLE teams MODIFY COLUMN enabled_modules MEDIUMTEXT NULL",
    "ALTER TABLE teams MODIFY COLUMN roles_config MEDIUMTEXT NULL",
    "ALTER TABLE teams MODIFY COLUMN custom_fields_config MEDIUMTEXT NULL",
    "ALTER TABLE teams MODIFY COLUMN applied_package_ids MEDIUMTEXT NULL",
    "ALTER TABLE teams MODIFY COLUMN youdox_config MEDIUMTEXT NULL",
    "UPDATE teams SET enabled_modules = NULL WHERE enabled_modules = ''",
    "UPDATE teams SET roles_config = NULL WHERE roles_config = ''",
    "UPDATE teams SET custom_fields_config = NULL WHERE custom_fields_config = ''",
    "UPDATE teams SET applied_package_ids = NULL WHERE applied_package_ids = ''",
    "UPDATE teams SET youdox_config = NULL WHERE youdox_config = ''",
    "ALTER TABLE companies ADD COLUMN custom_fields JSON NULL",
    "ALTER TABLE company_contacts ADD COLUMN custom_fields JSON NULL",
    "ALTER TABLE opportunities ADD COLUMN custom_fields JSON NULL",
    "ALTER TABLE projects ADD COLUMN custom_fields JSON NULL",
    "ALTER TABLE invoice_drafts ADD COLUMN payment_status VARCHAR(32) NOT NULL DEFAULT 'unpaid'",
    "ALTER TABLE invoice_drafts ADD COLUMN paid_amount DECIMAL(14,2) NOT NULL DEFAULT 0",
    "ALTER TABLE invoice_drafts ADD COLUMN balance_due DECIMAL(14,2) NOT NULL DEFAULT 0",
    "ALTER TABLE invoice_drafts ADD COLUMN paid_at DATETIME NULL",
    "ALTER TABLE invoice_drafts ADD COLUMN pos_origin_payment_id VARCHAR(64) NULL",
    "UPDATE invoice_drafts SET balance_due = amount WHERE balance_due = 0 AND paid_amount = 0",
    "ALTER TABLE pos_payment_intents ADD COLUMN payment_mode VARCHAR(32) NOT NULL DEFAULT 'spot'",
    "ALTER TABLE pos_payment_intents ADD COLUMN invoice_number_snapshot VARCHAR(128) NULL",
    "ALTER TABLE pos_payment_intents ADD COLUMN stripe_payment_intent_id VARCHAR(128) NULL",
    "ALTER TABLE pos_payment_intents ADD COLUMN stripe_client_secret VARCHAR(255) NULL",
    "ALTER TABLE pos_payment_intents ADD COLUMN stripe_connected_account_id VARCHAR(128) NULL",
    "ALTER TABLE pos_payment_intents ADD COLUMN terminal_location_id VARCHAR(128) NULL",
    "ALTER TABLE pos_payment_intents ADD COLUMN generated_invoice_id VARCHAR(64) NULL",
    "ALTER TABLE pos_payment_intents ADD COLUMN auto_generated_invoice TINYINT(1) NOT NULL DEFAULT 0",
    "ALTER TABLE pos_payment_intents ADD COLUMN paid_amount DECIMAL(14,2) NULL",
    "ALTER TABLE pos_payment_intents ADD COLUMN payment_method_label VARCHAR(120) NULL",
    "ALTER TABLE pos_payment_intents ADD COLUMN failure_reason TEXT NULL",
    "ALTER TABLE pos_payment_intents ADD COLUMN mobile_checkout_json MEDIUMTEXT NULL",
    "ALTER TABLE team_stripe_connections ADD COLUMN account_email VARCHAR(190) NOT NULL DEFAULT ''",
    "ALTER TABLE team_stripe_connections ADD COLUMN country VARCHAR(8) NOT NULL DEFAULT 'IT'",
    "ALTER TABLE team_stripe_connections ADD COLUMN default_currency VARCHAR(8) NOT NULL DEFAULT 'eur'",
    "ALTER TABLE team_stripe_connections ADD COLUMN details_submitted TINYINT(1) NOT NULL DEFAULT 0",
    "ALTER TABLE team_stripe_connections ADD COLUMN charges_enabled TINYINT(1) NOT NULL DEFAULT 0",
    "ALTER TABLE team_stripe_connections ADD COLUMN payouts_enabled TINYINT(1) NOT NULL DEFAULT 0",
    "ALTER TABLE team_stripe_connections ADD COLUMN requirements_json MEDIUMTEXT NULL",
    "ALTER TABLE team_stripe_connections ADD COLUMN metadata_json MEDIUMTEXT NULL",
    "ALTER TABLE team_stripe_connections ADD COLUMN is_active TINYINT(1) NOT NULL DEFAULT 1",
    "ALTER TABLE team_stripe_connections ADD COLUMN connected_at DATETIME NULL",
    "ALTER TABLE team_stripe_connections ADD COLUMN last_synced_at DATETIME NULL",
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

    $packageSeeds = [
        [
            'id' => 'sector_artigiani',
            'type' => 'sector',
            'name' => 'Artigiani & Squadre',
            'description' => 'Preset per realtà operative che lavorano su sopralluoghi, cantieri e interventi ricorrenti.',
            'icon' => 'construction',
            'color' => '#F59E0B',
            'modules' => ['integrations', 'custom_branding', 'nexora_pos'],
            'roles' => ['Capo squadra', 'Tecnico operativo', 'Back office', 'Commerciale'],
            'customFields' => [
                ['id' => 'artigiani_company_ref_code', 'module' => 'companies', 'label' => 'Codice cliente interno', 'type' => 'text', 'maxLength' => 60, 'options' => []],
                ['id' => 'artigiani_company_site_type', 'module' => 'companies', 'label' => 'Tipologia immobile', 'type' => 'select', 'maxLength' => 120, 'options' => ['Appartamento', 'Condominio', 'Capannone', 'Ufficio', 'Negozio']],
                ['id' => 'artigiani_opportunity_job_type', 'module' => 'opportunities', 'label' => 'Tipo intervento', 'type' => 'select', 'maxLength' => 120, 'options' => ['Imbiancatura', 'Ripristino', 'Manutenzione', 'Installazione', 'Sopralluogo']],
                ['id' => 'artigiani_project_site_address', 'module' => 'projects', 'label' => 'Indirizzo cantiere', 'type' => 'text', 'maxLength' => 255, 'options' => []],
                ['id' => 'artigiani_project_notes', 'module' => 'projects', 'label' => 'Note operative cantiere', 'type' => 'textarea', 'maxLength' => 1500, 'options' => []],
            ],
            'metadata' => ['industry' => 'artigiani', 'focus' => ['cantieri', 'sopralluoghi', 'squadre']],
            'sortOrder' => 10,
        ],
        [
            'id' => 'sector_service_ops',
            'type' => 'sector',
            'name' => 'Assistenza Tecnica',
            'description' => 'Preset per team che gestiscono ticket, manutenzioni, riparazioni e visite tecniche.',
            'icon' => 'support_agent',
            'color' => '#38BDF8',
            'modules' => ['team_chat', 'integrations', 'nexora_pos'],
            'roles' => ['Responsabile assistenza', 'Tecnico sul campo', 'Dispatcher', 'Back office'],
            'customFields' => [
                ['id' => 'service_company_contract_code', 'module' => 'companies', 'label' => 'Codice contratto assistenza', 'type' => 'text', 'maxLength' => 80, 'options' => []],
                ['id' => 'service_contact_reference_slot', 'module' => 'contacts', 'label' => 'Fascia contatto preferita', 'type' => 'select', 'maxLength' => 80, 'options' => ['Mattina', 'Pomeriggio', 'Sempre disponibile']],
                ['id' => 'service_opportunity_priority', 'module' => 'opportunities', 'label' => 'Priorita intervento', 'type' => 'select', 'maxLength' => 80, 'options' => ['Bassa', 'Media', 'Alta', 'Urgente']],
                ['id' => 'service_project_serial', 'module' => 'projects', 'label' => 'Seriale apparato/impianto', 'type' => 'text', 'maxLength' => 120, 'options' => []],
            ],
            'metadata' => ['industry' => 'assistenza_tecnica', 'focus' => ['ticket', 'riparazioni', 'manutenzione']],
            'sortOrder' => 20,
        ],
        [
            'id' => 'sector_consulenza',
            'type' => 'sector',
            'name' => 'Consulenza & Advisory',
            'description' => 'Preset per team che lavorano su analisi, documentazione, opportunita commerciali e deliverable.',
            'icon' => 'analytics',
            'color' => '#8B5CF6',
            'modules' => ['nexora_ai', 'integrations', 'bandi'],
            'roles' => ['Consulente', 'Project lead', 'Account manager', 'Amministrazione'],
            'customFields' => [
                ['id' => 'consulting_company_segment', 'module' => 'companies', 'label' => 'Segmento cliente', 'type' => 'select', 'maxLength' => 120, 'options' => ['Startup', 'PMI', 'Mid-market', 'Enterprise', 'PA']],
                ['id' => 'consulting_opportunity_service_line', 'module' => 'opportunities', 'label' => 'Linea di servizio', 'type' => 'select', 'maxLength' => 120, 'options' => ['Consulenza', 'Bandi', 'Innovazione', 'Rendicontazione', 'Formazione']],
                ['id' => 'consulting_project_deliverable', 'module' => 'projects', 'label' => 'Deliverable principale', 'type' => 'text', 'maxLength' => 255, 'options' => []],
            ],
            'metadata' => ['industry' => 'consulenza', 'focus' => ['deliverable', 'documentazione', 'advisory']],
            'sortOrder' => 30,
        ],
        [
            'id' => 'cf_site_survey',
            'type' => 'custom_fields',
            'name' => 'Pacchetto Sopralluoghi',
            'description' => 'Campi pronti per gestire rilievi, accessi, referenti e note di sopralluogo.',
            'icon' => 'home_repair_service',
            'color' => '#14B8A6',
            'modules' => [],
            'roles' => [],
            'customFields' => [
                ['id' => 'survey_company_access', 'module' => 'companies', 'label' => 'Modalita accesso', 'type' => 'select', 'maxLength' => 120, 'options' => ['Libero', 'Appuntamento', 'Portineria', 'Chiavi da ritirare']],
                ['id' => 'survey_contact_role', 'module' => 'contacts', 'label' => 'Ruolo sul sito', 'type' => 'text', 'maxLength' => 120, 'options' => []],
                ['id' => 'survey_project_scope', 'module' => 'projects', 'label' => 'Perimetro sopralluogo', 'type' => 'textarea', 'maxLength' => 1200, 'options' => []],
            ],
            'metadata' => ['group' => 'operazioni'],
            'sortOrder' => 110,
        ],
        [
            'id' => 'cf_administration_plus',
            'type' => 'custom_fields',
            'name' => 'Pacchetto Amministrazione Plus',
            'description' => 'Campi aggiuntivi per dati amministrativi, referenze e classificazione interna.',
            'icon' => 'inventory_2',
            'color' => '#22C55E',
            'modules' => [],
            'roles' => [],
            'customFields' => [
                ['id' => 'admin_company_payment_cluster', 'module' => 'companies', 'label' => 'Cluster pagamenti', 'type' => 'select', 'maxLength' => 80, 'options' => ['Standard', 'Attenzione', 'Premium']],
                ['id' => 'admin_opportunity_margin_notes', 'module' => 'opportunities', 'label' => 'Note marginalita', 'type' => 'textarea', 'maxLength' => 1200, 'options' => []],
                ['id' => 'admin_project_internal_owner', 'module' => 'projects', 'label' => 'Referente interno operativo', 'type' => 'text', 'maxLength' => 120, 'options' => []],
            ],
            'metadata' => ['group' => 'amministrazione'],
            'sortOrder' => 120,
        ],
    ];

    $packageStmt = $pdo->prepare(
        'INSERT INTO configuration_packages
         (id, package_type, name, description, icon, color, modules_json, roles_json, custom_fields_json, metadata_json, is_system, is_active, sort_order)
         VALUES
         (:id, :package_type, :name, :description, :icon, :color, :modules_json, :roles_json, :custom_fields_json, :metadata_json, 1, 1, :sort_order)
         ON DUPLICATE KEY UPDATE
           package_type = VALUES(package_type),
           name = VALUES(name),
           description = VALUES(description),
           icon = VALUES(icon),
           color = VALUES(color),
           modules_json = VALUES(modules_json),
           roles_json = VALUES(roles_json),
           custom_fields_json = VALUES(custom_fields_json),
           metadata_json = VALUES(metadata_json),
           is_active = VALUES(is_active),
           sort_order = VALUES(sort_order)'
    );
    foreach ($packageSeeds as $seed) {
        $packageStmt->execute([
            ':id' => $seed['id'],
            ':package_type' => $seed['type'],
            ':name' => $seed['name'],
            ':description' => $seed['description'],
            ':icon' => $seed['icon'],
            ':color' => $seed['color'],
            ':modules_json' => json_encode($seed['modules'], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES) ?: '[]',
            ':roles_json' => json_encode($seed['roles'], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES) ?: '[]',
            ':custom_fields_json' => json_encode($seed['customFields'], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES) ?: '[]',
            ':metadata_json' => json_encode($seed['metadata'], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES) ?: '{}',
            ':sort_order' => (int)$seed['sortOrder'],
        ]);
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
    . 'template_choices, teams, team_members, configuration_packages, memos, bandi, team_stripe_connections.</p>'
    . '<p><strong>Nota ruoli:</strong> il primo utente che accede dopo l\'installazione '
    . 'diventa automaticamente <code>superadmin</code>; gli altri nascono '
    . '<code>operatore</code> e si gestiscono da Impostazioni → Profilo → Gestione utenti.</p>';
foreach ($results as $r) {
    echo '<p class="' . ($r['ok'] ? 'ok' : 'ko') . '">' . ($r['ok'] ? '✓' : '✗') . ' ' .
        htmlspecialchars($r['note'], ENT_QUOTES, 'UTF-8') . '</p>';
    echo '<pre>' . htmlspecialchars($r['sql'], ENT_QUOTES, 'UTF-8') . '</pre>';
}
echo '</body></html>';
