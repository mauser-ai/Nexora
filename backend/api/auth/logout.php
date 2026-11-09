<?php
// POST /api/auth/logout.php
// Body: { "refresh_token": "..." }
// Revoca il refresh token

require_once __DIR__ . '/../bootstrap.php';

if (http_method() !== 'POST') json_error('Metodo non consentito', 405);

$userId = require_auth();
$body   = request_body();
$token  = str_val($body['refresh_token'] ?? '');

if (!empty($token)) {
    revoke_refresh_token($token);
}

// Pulizia token scaduti di questo utente
db()->prepare('DELETE FROM refresh_tokens WHERE user_id = ? AND expires_at < NOW()')
   ->execute([$userId]);

json_ok(['ok' => true]);
