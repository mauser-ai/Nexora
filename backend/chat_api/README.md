# Chat API

Backend PHP per chat di gruppo con:
- persistenza `SQL` tramite `PDO`
- eventi realtime e notify hook tramite `Redis`

## Deploy suggerito

Pubblica i file sotto:

```text
/api/chat/
  common.php
  read.php
  schema.sql
  groups/index.php
  messages/index.php
```

## Configurazione

Questa chat è pensata per stare dentro la tua API esistente e riusare:
- `../config.php`
- `../bootstrap.php`
- `../middleware/auth.php`

Quindi:
- database MySQL: usa già `DB_HOST`, `DB_NAME`, `DB_USER`, `DB_PASS`
- auth JWT: usa già `JWT_ACCESS_SECRET` e il middleware `require_auth()`

Non devi duplicare le credenziali del DB né i segreti JWT dentro `chat_api`.

## Variabili Redis opzionali

```text
CHAT_REDIS_HOST="127.0.0.1"
CHAT_REDIS_PORT="6379"
CHAT_REDIS_PASSWORD=""
CHAT_REDIS_DB="0"
CHAT_REDIS_TIMEOUT="1.5"
```

Se Redis non è disponibile, la chat continua a funzionare su SQL.

## Endpoints

- `GET /api/chat/groups/index.php?userId=<uid>`
- `POST /api/chat/groups/index.php`
- `GET /api/chat/messages/index.php?groupId=<groupId>&userId=<uid>`
- `POST /api/chat/messages/index.php`
- `POST /api/chat/read.php`

## Nota auth

Il client invia il tuo `Authorization: Bearer <jwt>` e la chat usa direttamente `require_auth()` dal backend principale.
