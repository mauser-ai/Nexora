# Integrazioni Archivio

Questi endpoint collegano sorgenti cloud all'app Archivio.

## Google Drive

1. Copia `config.local.php.example` in `config.local.php`.
2. Inserisci `google_client_id`, `google_client_secret` e una `token_encryption_key` random lunga.
3. Configura il database:
   - se `backend/bootstrap.php` espone gia `db(): PDO`, non serve altro;
   - altrimenti compila `pdo_dsn`, `pdo_user`, `pdo_password`.
4. Importa `schema.sql` nel database, oppure lascia che `common.php` lo crei alla prima chiamata.
5. In Google Cloud OAuth Client aggiungi questo redirect URI:

```text
https://gussoni.sviluppo.host/archivio/api/integrations/oauth_callback.php
```

Endpoint principali:

- `oauth_start.php?provider=google_drive`
- `oauth_callback.php`
- `status.php`
- `list.php?provider=google_drive&path=...`
- `upload.php`
- `create_folder.php`
- `rename.php`
- `move.php`
- `delete.php`
- `list_folders.php`

I token vengono salvati cifrati nella tabella `archive_integrations`.
