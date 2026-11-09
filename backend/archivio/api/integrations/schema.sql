CREATE TABLE IF NOT EXISTS archive_integrations (
  id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  user_id VARCHAR(128) NOT NULL DEFAULT 'default',
  provider VARCHAR(40) NOT NULL,
  account_email VARCHAR(190) NULL,
  access_token TEXT NOT NULL,
  refresh_token TEXT NULL,
  expires_at DATETIME NULL,
  scope TEXT NULL,
  token_type VARCHAR(40) NULL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  UNIQUE KEY uniq_archive_integrations_user_provider (user_id, provider)
);
