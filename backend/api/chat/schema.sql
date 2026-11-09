CREATE TABLE IF NOT EXISTS chat_groups (
  id CHAR(36) PRIMARY KEY,
  name VARCHAR(190) NOT NULL,
  description TEXT NULL,
  created_by VARCHAR(128) NOT NULL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS chat_group_members (
  group_id CHAR(36) NOT NULL,
  user_id VARCHAR(128) NOT NULL,
  display_name VARCHAR(190) NOT NULL,
  email VARCHAR(190) NOT NULL DEFAULT '',
  role VARCHAR(100) NOT NULL DEFAULT '',
  joined_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  last_read_message_id CHAR(36) NULL,
  last_read_at DATETIME NULL,
  PRIMARY KEY (group_id, user_id),
  CONSTRAINT fk_chat_member_group
    FOREIGN KEY (group_id) REFERENCES chat_groups(id)
    ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS chat_messages (
  id CHAR(36) PRIMARY KEY,
  group_id CHAR(36) NOT NULL,
  user_id VARCHAR(128) NOT NULL,
  author_name VARCHAR(190) NOT NULL,
  body TEXT NOT NULL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT fk_chat_message_group
    FOREIGN KEY (group_id) REFERENCES chat_groups(id)
    ON DELETE CASCADE
);

CREATE INDEX idx_chat_messages_group_created
  ON chat_messages(group_id, created_at);

CREATE INDEX idx_chat_members_user
  ON chat_group_members(user_id);
