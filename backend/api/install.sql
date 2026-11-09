-- ═══════════════════════════════════════════════════════════════════════════
-- Nexora CRM  –  Schema MySQL 8.0+
-- Esegui: mysql -u root -p ucccspov_nexora < install.sql
-- ═══════════════════════════════════════════════════════════════════════════

CREATE DATABASE IF NOT EXISTS ucccspov_nexora
  CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

USE ucccspov_nexora;

SET FOREIGN_KEY_CHECKS = 0;

-- ── users ────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS users (
  id                  CHAR(36)     NOT NULL,
  team_id             CHAR(36)     NULL,
  email               VARCHAR(255) NOT NULL DEFAULT '',
  display_name        VARCHAR(255) NOT NULL DEFAULT '',
  role                VARCHAR(255) NOT NULL DEFAULT '',
  email_signature_html TEXT        NOT NULL DEFAULT '',
  billing_profile     JSON         NOT NULL DEFAULT (JSON_OBJECT()),
  youdox_config       JSON         NOT NULL DEFAULT (JSON_OBJECT()),
  ui_state            JSON         NOT NULL DEFAULT (JSON_OBJECT()),
  created_at          TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at          TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  INDEX idx_team_id (team_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ── refresh_tokens ────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS refresh_tokens (
  id          BIGINT       NOT NULL AUTO_INCREMENT,
  user_id     CHAR(36)     NOT NULL,
  token_hash  CHAR(64)     NOT NULL,
  expires_at  DATETIME     NOT NULL,
  revoked     TINYINT(1)   NOT NULL DEFAULT 0,
  created_at  TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  INDEX idx_token_hash (token_hash),
  INDEX idx_user_id    (user_id),
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ── teams ─────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS teams (
  id              CHAR(36)     NOT NULL,
  name            VARCHAR(255) NOT NULL DEFAULT '',
  owner_id        CHAR(36)     NOT NULL,
  billing_profile JSON         NOT NULL DEFAULT (JSON_OBJECT()),
  youdox_config   JSON         NOT NULL DEFAULT (JSON_OBJECT()),
  brand_logo_url  VARCHAR(500) NULL,
  brand_color     VARCHAR(10)  NULL,
  roles_config    JSON         NULL,
  custom_fields_config JSON    NULL,
  created_at      TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at      TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ── team_members ──────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS team_members (
  team_id      CHAR(36)                      NOT NULL,
  user_id      CHAR(36)                      NOT NULL,
  email        VARCHAR(255)                  NOT NULL DEFAULT '',
  display_name VARCHAR(255)                  NOT NULL DEFAULT '',
  role         VARCHAR(255)                  NOT NULL DEFAULT '',
  status       ENUM('active','deactivated')  NOT NULL DEFAULT 'active',
  joined_at    TIMESTAMP                     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (team_id, user_id),
  INDEX idx_user_id (user_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ── companies ─────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS companies (
  id                      CHAR(36)                              NOT NULL,
  user_id                 CHAR(36)                              NOT NULL,
  name                    VARCHAR(255)                          NOT NULL DEFAULT '',
  vat_number              VARCHAR(50)                           NOT NULL DEFAULT '',
  tax_code                VARCHAR(50)                           NOT NULL DEFAULT '',
  pec                     VARCHAR(255)                          NOT NULL DEFAULT '',
  sdi_code                VARCHAR(20)                           NOT NULL DEFAULT '',
  email                   VARCHAR(255)                          NOT NULL DEFAULT '',
  phone                   VARCHAR(50)                           NOT NULL DEFAULT '',
  website                 VARCHAR(500)                          NOT NULL DEFAULT '',
  address_line            VARCHAR(500)                          NOT NULL DEFAULT '',
  city                    VARCHAR(255)                          NOT NULL DEFAULT '',
  postal_code             VARCHAR(20)                           NOT NULL DEFAULT '',
  country                 VARCHAR(10)                           NOT NULL DEFAULT 'IT',
  contact_person          VARCHAR(255)                          NOT NULL DEFAULT '',
  notes                   TEXT                                  NOT NULL DEFAULT '',
  is_non_profit           TINYINT(1)                            NOT NULL DEFAULT 0,
  annual_revenue          DECIMAL(15,2)                         NULL,
  employees_count         INT                                   NULL,
  legal_representative    VARCHAR(255)                          NOT NULL DEFAULT '',
  incorporation_date      DATE                                  NULL,
  company_type            ENUM('profit','nonProfit','pa','pf')  NOT NULL DEFAULT 'profit',
  riferimento_interno     VARCHAR(255)                          NOT NULL DEFAULT '',
  provincia               VARCHAR(100)                          NOT NULL DEFAULT '',
  regione                 VARCHAR(100)                          NOT NULL DEFAULT '',
  sede_operativa_via      VARCHAR(500)                          NOT NULL DEFAULT '',
  sede_operativa_cap      VARCHAR(20)                           NOT NULL DEFAULT '',
  sede_operativa_citta    VARCHAR(255)                          NOT NULL DEFAULT '',
  sede_operativa_provincia VARCHAR(100)                         NOT NULL DEFAULT '',
  sede_operativa_regione  VARCHAR(100)                          NOT NULL DEFAULT '',
  data_inizio_attivita    DATE                                  NULL,
  lettere_ateco           VARCHAR(20)                           NOT NULL DEFAULT '',
  ateco_primario          VARCHAR(20)                           NOT NULL DEFAULT '',
  ateco_secondario        VARCHAR(20)                           NOT NULL DEFAULT '',
  ateco_terziario         VARCHAR(20)                           NOT NULL DEFAULT '',
  controllata             TINYINT(1)                            NOT NULL DEFAULT 0,
  controllante            TINYINT(1)                            NOT NULL DEFAULT 0,
  dimensione_impresa      ENUM('micro','piccola','media','grande') NULL,
  ula                     INT                                   NULL,
  export_azienda          TINYINT(1)                            NOT NULL DEFAULT 0,
  percentuale_export      DECIMAL(5,2)                          NULL,
  aree_investimento       JSON                                  NOT NULL DEFAULT (JSON_ARRAY()),
  ricavi_annui            JSON                                  NOT NULL DEFAULT (JSON_OBJECT()),
  custom_fields           JSON                                  NULL,
  created_at              TIMESTAMP                             NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at              TIMESTAMP                             NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  INDEX idx_user_id (user_id),
  INDEX idx_name    (user_id, name)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ── company_contacts ──────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS company_contacts (
  id         CHAR(36)     NOT NULL,
  user_id    CHAR(36)     NOT NULL,
  company_id CHAR(36)     NULL,
  name       VARCHAR(255) NOT NULL DEFAULT '',
  email      VARCHAR(255) NOT NULL DEFAULT '',
  phone      VARCHAR(50)  NOT NULL DEFAULT '',
  role       VARCHAR(255) NOT NULL DEFAULT '',
  custom_fields JSON      NULL,
  created_at TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  INDEX idx_user_id    (user_id),
  INDEX idx_company_id (company_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ── opportunities ─────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS opportunities (
  id                                  CHAR(36)     NOT NULL,
  user_id                             CHAR(36)     NOT NULL,
  company_id                          CHAR(36)     NULL,
  title                               VARCHAR(500) NOT NULL DEFAULT '',
  status ENUM('inAttesa','preventivazione','accettata','accettataSenzaFirma',
              'inAttesaRinnovoAutomatico','presaInCarico','persa')
                                                   NOT NULL DEFAULT 'inAttesa',
  created_by_user_id                  CHAR(36)     NULL,
  bando_reference                     VARCHAR(255) NOT NULL DEFAULT '',
  bando_source                        VARCHAR(255) NOT NULL DEFAULT '',
  bando_deadline                      DATE         NULL,
  estimated_value                     DECIMAL(15,2)NULL,
  notes                               TEXT         NOT NULL DEFAULT '',
  assigned_analyst_id                 CHAR(36)     NULL,
  analysis_notes                      TEXT         NOT NULL DEFAULT '',
  contact_id                          CHAR(36)     NULL,
  rif_offerta                         VARCHAR(255) NOT NULL DEFAULT '',
  contatto_commerciale                VARCHAR(255) NOT NULL DEFAULT '',
  presa_in_carico                     TINYINT(1)   NOT NULL DEFAULT 0,
  da_faturare_a                       VARCHAR(255) NOT NULL DEFAULT '',
  partner_commerciale                 VARCHAR(255) NOT NULL DEFAULT '',
  fornitore                           VARCHAR(255) NOT NULL DEFAULT '',
  scadenza_presentazione              DATE         NULL,
  scadenza_operativa                  DATE         NULL,
  avanzamento_pratica ENUM('none','presentata','inEsecuzione','conclusa')
                                                   NOT NULL DEFAULT 'none',
  esito_pratica ENUM('none','accolta','respinta','rinunciata','nonAmmissibile','inAttesa')
                                                   NOT NULL DEFAULT 'none',
  data_stato                          DATE         NULL,
  totale_progetto                     DECIMAL(15,2)NULL,
  totale_beneficio_economico_richiesto DECIMAL(15,2)NULL,
  contributo_richiesto                DECIMAL(15,2)NULL,
  finanziamento_richiesto             DECIMAL(15,2)NULL,
  garanzia_richiesta                  DECIMAL(15,2)NULL,
  credito_imposta_richiesto           DECIMAL(15,2)NULL,
  totale_progetto_ridefinito          DECIMAL(15,2)NULL,
  totale_beneficio_economico_ricevuto DECIMAL(15,2)NULL,
  contributo_ricevuto                 DECIMAL(15,2)NULL,
  finanziamento_ricevuto              DECIMAL(15,2)NULL,
  garanzia_ricevuta                   DECIMAL(15,2)NULL,
  credito_imposta_ricevuto            DECIMAL(15,2)NULL,
  termine_rendicontazione             DATE         NULL,
  stato_rendicontazione ENUM('none','aperta','chiusa')
                                                   NOT NULL DEFAULT 'none',
  note_rendicontazione                TEXT         NOT NULL DEFAULT '',
  custom_fields                       JSON         NULL,
  created_at                          TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at                          TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  INDEX idx_user_id    (user_id),
  INDEX idx_company_id (company_id),
  INDEX idx_status     (user_id, status)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ── preventivi ────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS preventivi (
  id                  CHAR(36)                                  NOT NULL,
  user_id             CHAR(36)                                  NOT NULL,
  opportunity_id      CHAR(36)                                  NULL,
  company_id          CHAR(36)                                  NULL,
  status              ENUM('draft','sent','accepted','rejected') NOT NULL DEFAULT 'draft',
  lines               JSON                                      NOT NULL DEFAULT (JSON_ARRAY()),
  istruttoria_fee     DECIMAL(15,2)                             NOT NULL DEFAULT 0,
  success_fee_percent DECIMAL(5,2)                              NULL,
  notes               TEXT                                      NOT NULL DEFAULT '',
  linked_project_id   CHAR(36)                                  NULL,
  sent_at             DATETIME                                  NULL,
  accepted_at         DATETIME                                  NULL,
  expires_at          DATETIME                                  NULL,
  created_at          TIMESTAMP                                 NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at          TIMESTAMP                                 NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  INDEX idx_user_id        (user_id),
  INDEX idx_opportunity_id (opportunity_id),
  INDEX idx_company_id     (company_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ── projects ──────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS projects (
  id                                  CHAR(36)                         NOT NULL,
  user_id                             CHAR(36)                         NOT NULL,
  company_id                          CHAR(36)                         NULL,
  name                                VARCHAR(500)                     NOT NULL DEFAULT '',
  code                                VARCHAR(100)                     NOT NULL DEFAULT '',
  status                              VARCHAR(50)                      NOT NULL DEFAULT 'planning',
  type                                ENUM('profit','noProfit')        NOT NULL DEFAULT 'profit',
  opportunity_id                      CHAR(36)                         NULL,
  quotation_id                        CHAR(36)                         NULL,
  deal_id                             CHAR(36)                         NULL,
  grant_amount                        DECIMAL(15,2)                    NULL,
  success_fee_amount                  DECIMAL(15,2)                    NULL,
  notes                               TEXT                             NOT NULL DEFAULT '',
  anticipo_emesso                     TINYINT(1)                       NOT NULL DEFAULT 0,
  rif_progetto                        VARCHAR(255)                     NOT NULL DEFAULT '',
  rif_caricamento                     VARCHAR(255)                     NOT NULL DEFAULT '',
  id_progetto_esterno                 VARCHAR(255)                     NOT NULL DEFAULT '',
  titolo_progetto                     VARCHAR(500)                     NOT NULL DEFAULT '',
  data_inizio_progetto                DATE                             NULL,
  data_fine_progetto                  DATE                             NULL,
  da_faturare_a                       VARCHAR(255)                     NOT NULL DEFAULT '',
  totale_progetto                     DECIMAL(15,2)                    NULL,
  totale_beneficio_economico_richiesto DECIMAL(15,2)                   NULL,
  contributo_richiesto                DECIMAL(15,2)                    NULL,
  finanziamento_richiesto             DECIMAL(15,2)                    NULL,
  garanzia_richiesta                  DECIMAL(15,2)                    NULL,
  credito_imposta_richiesto           DECIMAL(15,2)                    NULL,
  avanzamento_pratica ENUM('none','presentata','inEsecuzione','conclusa')
                                                                       NOT NULL DEFAULT 'none',
  esito_pratica ENUM('none','accolta','respinta','rinunciata','nonAmmissibile','inAttesa')
                                                                       NOT NULL DEFAULT 'none',
  data_stato                          DATE                             NULL,
  totale_progetto_ridefinito          DECIMAL(15,2)                    NULL,
  totale_beneficio_economico_ricevuto DECIMAL(15,2)                    NULL,
  contributo_ricevuto                 DECIMAL(15,2)                    NULL,
  finanziamento_ricevuto              DECIMAL(15,2)                    NULL,
  garanzia_ricevuta                   DECIMAL(15,2)                    NULL,
  credito_imposta_ricevuto            DECIMAL(15,2)                    NULL,
  termine_rendicontazione             DATE                             NULL,
  stato_rendicontazione ENUM('none','aperta','chiusa')                 NOT NULL DEFAULT 'none',
  custom_fields                       JSON                             NULL,
  closed_at                           DATETIME                         NULL,
  created_at                          TIMESTAMP                        NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at                          TIMESTAMP                        NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  INDEX idx_user_id        (user_id),
  INDEX idx_company_id     (company_id),
  INDEX idx_opportunity_id (opportunity_id),
  INDEX idx_status         (user_id, status)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ── project_phases ────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS project_phases (
  id               CHAR(36)                            NOT NULL,
  user_id          CHAR(36)                            NOT NULL,
  project_id       CHAR(36)                            NOT NULL,
  name             VARCHAR(255)                        NOT NULL DEFAULT '',
  phase_order      INT                                 NOT NULL DEFAULT 0,
  status           ENUM('notStarted','inProgress','done') NOT NULL DEFAULT 'notStarted',
  assigned_user_id CHAR(36)                            NULL,
  start_date       DATE                                NULL,
  deadline         DATE                                NULL,
  notes            TEXT                                NOT NULL DEFAULT '',
  is_custom        TINYINT(1)                          NOT NULL DEFAULT 0,
  created_at       TIMESTAMP                           NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at       TIMESTAMP                           NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  INDEX idx_user_id    (user_id),
  INDEX idx_project_id (project_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ── work_tasks ────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS work_tasks (
  id              CHAR(36)                                  NOT NULL,
  user_id         CHAR(36)                                  NOT NULL,
  company_id      CHAR(36)                                  NOT NULL DEFAULT '',
  project_id      CHAR(36)                                  NOT NULL DEFAULT '',
  phase_id        CHAR(36)                                  NOT NULL DEFAULT '',
  assignee_id     CHAR(36)                                  NOT NULL DEFAULT '',
  name            VARCHAR(500)                              NOT NULL DEFAULT '',
  estimated_hours DECIMAL(6,2)                              NOT NULL DEFAULT 0,
  logged_hours    DECIMAL(6,2)                              NOT NULL DEFAULT 0,
  start_date      DATE                                      NOT NULL,
  deadline        DATE                                      NOT NULL,
  status          ENUM('backlog','planned','inProgress','done') NOT NULL DEFAULT 'planned',
  billable        TINYINT(1)                                NOT NULL DEFAULT 1,
  description     TEXT                                      NOT NULL DEFAULT '',
  created_at      TIMESTAMP                                 NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at      TIMESTAMP                                 NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  INDEX idx_user_id     (user_id),
  INDEX idx_project_id  (project_id),
  INDEX idx_phase_id    (phase_id),
  INDEX idx_assignee_id (assignee_id),
  INDEX idx_deadline    (user_id, deadline),
  INDEX idx_status      (user_id, status)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ── task_comments ─────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS task_comments (
  id          CHAR(36)     NOT NULL,
  user_id     CHAR(36)     NOT NULL,
  task_id     CHAR(36)     NOT NULL,
  author_id   CHAR(36)     NOT NULL DEFAULT '',
  author_name VARCHAR(255) NOT NULL DEFAULT '',
  body        TEXT         NOT NULL,
  created_at  TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  INDEX idx_task_id (task_id),
  INDEX idx_user_id (user_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ── timeline_slots ────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS timeline_slots (
  id            CHAR(36)     NOT NULL,
  user_id       CHAR(36)     NOT NULL,
  task_id       CHAR(36)     NOT NULL,
  slot_date     DATE         NOT NULL,
  planned_hours DECIMAL(4,2) NOT NULL DEFAULT 0,
  start_hour    DECIMAL(4,2) NOT NULL DEFAULT 8,
  created_at    TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at    TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  INDEX idx_user_id (user_id),
  INDEX idx_task_id (task_id),
  INDEX idx_date    (user_id, slot_date)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ── time_tracks ───────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS time_tracks (
  id              CHAR(36)     NOT NULL,
  user_id         CHAR(36)     NOT NULL,
  task_id         CHAR(36)     NOT NULL DEFAULT '',
  name            VARCHAR(500) NOT NULL DEFAULT '',
  company_id      CHAR(36)     NOT NULL DEFAULT '',
  project_id      CHAR(36)     NOT NULL DEFAULT '',
  start_at        DATETIME     NOT NULL,
  end_at          DATETIME     NOT NULL,
  tracker_user_id CHAR(36)     NOT NULL DEFAULT '',
  description     TEXT         NOT NULL DEFAULT '',
  billable        TINYINT(1)   NOT NULL DEFAULT 1,
  tipo            VARCHAR(100) NOT NULL DEFAULT '',
  hourly_rate     DECIMAL(10,2)NULL,
  created_at      TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at      TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  INDEX idx_user_id    (user_id),
  INDEX idx_task_id    (task_id),
  INDEX idx_project_id (project_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ── invoice_drafts ────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS invoice_drafts (
  id            CHAR(36)                               NOT NULL,
  user_id       CHAR(36)                               NOT NULL,
  company_id    CHAR(36)                               NOT NULL DEFAULT '',
  number        VARCHAR(100)                           NOT NULL DEFAULT '',
  amount        DECIMAL(15,2)                          NOT NULL DEFAULT 0,
  status        ENUM('draft','readyForXml','exported')  NOT NULL DEFAULT 'draft',
  project_id    CHAR(36)                               NULL,
  lines         JSON                                   NOT NULL DEFAULT (JSON_ARRAY()),
  is_success_fee TINYINT(1)                            NOT NULL DEFAULT 0,
  grant_amount  DECIMAL(15,2)                          NULL,
  notes         TEXT                                   NOT NULL DEFAULT '',
  sent_at       DATETIME                               NULL,
  created_at    TIMESTAMP                              NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at    TIMESTAMP                              NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  INDEX idx_user_id    (user_id),
  INDEX idx_company_id (company_id),
  INDEX idx_project_id (project_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ── tickets ───────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS tickets (
  id              CHAR(36)     NOT NULL,
  user_id         CHAR(36)     NOT NULL,
  company_id      CHAR(36)     NOT NULL DEFAULT '',
  title           VARCHAR(500) NOT NULL DEFAULT '',
  recipient_email VARCHAR(255) NOT NULL DEFAULT '',
  status          ENUM('newTicket','open','waitingCustomer','closed') NOT NULL DEFAULT 'newTicket',
  entries         JSON         NOT NULL DEFAULT (JSON_ARRAY()),
  created_at      TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at      TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  INDEX idx_user_id    (user_id),
  INDEX idx_company_id (company_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ── user_availability ─────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS user_availability (
  user_id    CHAR(36)     NOT NULL,
  weekday    TINYINT      NOT NULL,
  hours      DECIMAL(4,2) NOT NULL DEFAULT 8,
  is_off     TINYINT(1)   NOT NULL DEFAULT 0,
  updated_at TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (user_id, weekday)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ── vacation_periods ──────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS vacation_periods (
  id         CHAR(36)     NOT NULL,
  user_id    CHAR(36)     NOT NULL,
  start_date DATE         NOT NULL,
  end_date   DATE         NOT NULL,
  label      VARCHAR(255) NOT NULL DEFAULT '',
  created_at TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  INDEX idx_user_id (user_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ── crm_contacts ──────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS crm_contacts (
  id          CHAR(36)     NOT NULL,
  user_id     CHAR(36)     NOT NULL,
  first_name  VARCHAR(255) NOT NULL DEFAULT '',
  last_name   VARCHAR(255) NOT NULL DEFAULT '',
  company_id  CHAR(36)     NULL,
  email       VARCHAR(255) NOT NULL DEFAULT '',
  phone       VARCHAR(50)  NOT NULL DEFAULT '',
  role        VARCHAR(255) NOT NULL DEFAULT '',
  tags        JSON         NOT NULL DEFAULT (JSON_ARRAY()),
  assigned_to CHAR(36)     NULL,
  notes       TEXT         NOT NULL DEFAULT '',
  created_at  TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at  TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  INDEX idx_user_id (user_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ── deal_stages ───────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS deal_stages (
  id          CHAR(36)     NOT NULL,
  user_id     CHAR(36)     NOT NULL,
  name        VARCHAR(255) NOT NULL DEFAULT '',
  stage_order INT          NOT NULL DEFAULT 0,
  color_hex   VARCHAR(10)  NOT NULL DEFAULT '#6366f1',
  probability INT          NOT NULL DEFAULT 0,
  created_at  TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  INDEX idx_user_id (user_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ── deals ─────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS deals (
  id                    CHAR(36)                    NOT NULL,
  user_id               CHAR(36)                    NOT NULL,
  title                 VARCHAR(500)                NOT NULL DEFAULT '',
  stage_id              CHAR(36)                    NULL,
  status                ENUM('open','won','lost')   NOT NULL DEFAULT 'open',
  value                 DECIMAL(15,2)               NOT NULL DEFAULT 0,
  currency              VARCHAR(10)                 NOT NULL DEFAULT 'EUR',
  customer_id           CHAR(36)                    NULL,
  customer_type         VARCHAR(20)                 NULL,
  probability           INT                         NOT NULL DEFAULT 0,
  expected_closing_date DATE                        NULL,
  assigned_to           CHAR(36)                    NULL,
  notes                 TEXT                        NOT NULL DEFAULT '',
  created_at            TIMESTAMP                   NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at            TIMESTAMP                   NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  INDEX idx_user_id  (user_id),
  INDEX idx_stage_id (stage_id),
  INDEX idx_status   (user_id, status)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ── quotations (CRM module) ───────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS quotations (
  id            CHAR(36)                                  NOT NULL,
  user_id       CHAR(36)                                  NOT NULL,
  number        VARCHAR(100)                              NOT NULL DEFAULT '',
  status        ENUM('draft','sent','accepted','rejected') NOT NULL DEFAULT 'draft',
  lines         JSON                                      NOT NULL DEFAULT (JSON_ARRAY()),
  customer_id   CHAR(36)                                  NULL,
  customer_type VARCHAR(20)                               NULL,
  deal_id       CHAR(36)                                  NULL,
  currency      VARCHAR(10)                               NOT NULL DEFAULT 'EUR',
  valid_until   DATE                                      NULL,
  notes         TEXT                                      NOT NULL DEFAULT '',
  created_at    TIMESTAMP                                 NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at    TIMESTAMP                                 NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  INDEX idx_user_id (user_id),
  INDEX idx_deal_id (deal_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ── expenses ──────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS expenses (
  id              CHAR(36)     NOT NULL,
  user_id         CHAR(36)     NOT NULL,
  title           VARCHAR(500) NOT NULL DEFAULT '',
  amount          DECIMAL(15,2)NOT NULL DEFAULT 0,
  category        ENUM('software','hardware','travel','marketing','office','consulting','other')
                               NOT NULL DEFAULT 'other',
  expense_date    DATE         NOT NULL,
  currency        VARCHAR(10)  NOT NULL DEFAULT 'EUR',
  notes           TEXT         NOT NULL DEFAULT '',
  attachment_path VARCHAR(500) NOT NULL DEFAULT '',
  company_id      CHAR(36)     NULL,
  created_at      TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  INDEX idx_user_id (user_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ── products ──────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS products (
  id          CHAR(36)     NOT NULL,
  user_id     CHAR(36)     NOT NULL,
  name        VARCHAR(255) NOT NULL DEFAULT '',
  sku         VARCHAR(100) NOT NULL DEFAULT '',
  description TEXT         NOT NULL DEFAULT '',
  price       DECIMAL(15,2)NOT NULL DEFAULT 0,
  currency    VARCHAR(10)  NOT NULL DEFAULT 'EUR',
  unit        VARCHAR(50)  NOT NULL DEFAULT 'pz',
  category    VARCHAR(255) NOT NULL DEFAULT '',
  vat_rate    DECIMAL(5,2) NOT NULL DEFAULT 22,
  created_at  TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at  TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  INDEX idx_user_id (user_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ── work_orders ───────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS work_orders (
  id          CHAR(36)                                NOT NULL,
  user_id     CHAR(36)                                NOT NULL,
  title       VARCHAR(500)                            NOT NULL DEFAULT '',
  status      ENUM('open','inProgress','done','cancelled') NOT NULL DEFAULT 'open',
  priority    ENUM('low','medium','high','urgent')    NOT NULL DEFAULT 'medium',
  company_id  CHAR(36)                                NULL,
  assigned_to CHAR(36)                                NULL,
  description TEXT                                    NOT NULL DEFAULT '',
  due_date    DATE                                    NULL,
  created_at  TIMESTAMP                               NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at  TIMESTAMP                               NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  INDEX idx_user_id (user_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ── contact_forms ─────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS contact_forms (
  id         CHAR(36)     NOT NULL,
  user_id    CHAR(36)     NOT NULL,
  name       VARCHAR(255) NOT NULL DEFAULT '',
  email      VARCHAR(255) NOT NULL DEFAULT '',
  phone      VARCHAR(50)  NOT NULL DEFAULT '',
  message    TEXT         NOT NULL DEFAULT '',
  source     VARCHAR(100) NOT NULL DEFAULT '',
  status     ENUM('newLead','contacted','converted','closed') NOT NULL DEFAULT 'newLead',
  created_at TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  INDEX idx_user_id (user_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ── subscriptions ─────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS subscriptions (
  id                CHAR(36)                      NOT NULL,
  user_id           CHAR(36)                      NOT NULL,
  title             VARCHAR(500)                  NOT NULL DEFAULT '',
  note              TEXT                          NOT NULL DEFAULT '',
  status            ENUM('active','deactivated')  NOT NULL DEFAULT 'active',
  billing_cycle     JSON                          NOT NULL DEFAULT (JSON_OBJECT()),
  lines             JSON                          NOT NULL DEFAULT (JSON_ARRAY()),
  customer_id       CHAR(36)                      NULL,
  customer_type     VARCHAR(20)                   NULL,
  currency          VARCHAR(10)                   NOT NULL DEFAULT 'EUR',
  starts_on         DATE                          NULL,
  ends_on           DATE                          NULL,
  next_renewal_date DATE                          NULL,
  created_at        TIMESTAMP                     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at        TIMESTAMP                     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  INDEX idx_user_id (user_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ── credit_notes ──────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS credit_notes (
  id                 CHAR(36)              NOT NULL,
  user_id            CHAR(36)              NOT NULL,
  credit_note_number VARCHAR(100)          NULL,
  credit_note_date   DATE                  NULL,
  status             ENUM('draft','booked') NOT NULL DEFAULT 'draft',
  lines              JSON                  NOT NULL DEFAULT (JSON_ARRAY()),
  customer_id        CHAR(36)              NULL,
  customer_type      VARCHAR(20)           NULL,
  invoice_id         CHAR(36)              NULL,
  currency           VARCHAR(10)           NOT NULL DEFAULT 'EUR',
  paid               TINYINT(1)            NOT NULL DEFAULT 0,
  paid_at            DATETIME              NULL,
  note               TEXT                  NOT NULL DEFAULT '',
  created_at         TIMESTAMP             NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at         TIMESTAMP             NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  INDEX idx_user_id (user_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

SET FOREIGN_KEY_CHECKS = 1;

-- ── Evento di pulizia refresh token scaduti (richiede EVENT SCHEDULER) ────────
-- SET GLOBAL event_scheduler = ON;
-- CREATE EVENT IF NOT EXISTS clean_expired_tokens
--   ON SCHEDULE EVERY 1 DAY
--   DO DELETE FROM refresh_tokens WHERE expires_at < NOW() OR revoked = 1;
