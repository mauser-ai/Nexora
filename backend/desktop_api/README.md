# Desktop API

Endpoint PHP da pubblicare dentro la tua API principale, ad esempio:

```text
/api/desktop/upload_wallpaper.php
```

## Prerequisiti

Questo file è pensato per riusare il backend PHP già esistente, quindi si aspetta:

- `../bootstrap.php`
- `require_auth()`
- `json_ok()`
- `json_error()`

come già avviene per le altre parti della tua API.

## Upload pubblici

Lo script salva i wallpaper in:

```text
/api/uploads/desktop_wallpapers/<userId>/
```

e restituisce un URL pubblico del file caricato, usando automaticamente il prefisso reale sotto cui vive l'API.

Se sul tuo hosting preferisci una cartella diversa, modifica dentro `upload_wallpaper.php`:

- `$storageDir`
- `$publicPath`

## Formati supportati

- `.jpg`
- `.jpeg`
- `.png`
- `.webp`

Limite attuale:

- `12 MB`
