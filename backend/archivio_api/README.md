# Deploy Archivio API (PHP)

Carica questa struttura sul tuo hosting sotto `/archivio/`:

- `/archivio/api/common.php`
- `/archivio/api/list.php`
- `/archivio/api/create_folder.php`
- `/archivio/api/upload.php`
- `/archivio/api/upload_base64.php`
- `/archivio/api/delete.php`
- `/archivio/api/ensure_companies.php`
- `/archivio/api/rename.php`
- `/archivio/api/move.php`
- `/archivio/api/list_folders.php`
- `/archivio/api/share_create.php`
- `/archivio/api/share_meta.php`
- `/archivio/api/download.php`
- `/archivio/api/send_ticket.php`
- `/archivio/api/ticket_inbound_drain.php`
- `/archivio/api/ticket_inbound_hook.php`
- `/archivio/api/make_ticket_ingest.php`
- `/archivio/share.php`

e crea anche queste cartelle scrivibili dal web server:

- `/archivio/storage/`
- `/archivio/shares/`
- `/archivio/inbound_mail/`

## Struttura iniziale creata automaticamente

Il backend ora inizializza questa struttura:

- `Clienti/`
- `Clienti/<Cliente>/`
- `Clienti/<Cliente>/Carta D'identita/`
- `Clienti/<Cliente>/Visura Camerale/`
- `Documenti interni/`

Le cartelle cliente vengono create quando l'app sincronizza le aziende presenti.

## URL usato dall'app

L'app Flutter usa ora di default:

- `https://business.gweb.agency/archivio/api`

Per override esplicito:

```bash
flutter build web \
  --base-href /gussoni/app/ \
  --dart-define=ARCHIVE_API_BASE=/archivio/api \
  --dart-define=ARCHIVE_API_ORIGIN=https://business.gweb.agency
```

## Note sicurezza minime

- Gli script bloccano path traversal (`..`) e normalizzano i path.
- Consigliato proteggere `/archivio/api` con auth lato server.
- Imposta limiti upload in `php.ini` coerenti con i file che carichi.

## Webhook mail inbound

- Endpoint ingest: `/archivio/api/ticket_inbound_hook.php`
- Endpoint lettura lato app: `/archivio/api/ticket_inbound_drain.php`
- Se imposti `MBW_TICKET_HOOK_KEY` lato server, invia la stessa chiave nel payload (`key`) o header `X-Webhook-Key`.
