<?php
// POST /api/auth/refresh.php
// Body: { "refresh_token": "..." }
// Restituisce un nuovo access_token (e ruota il refresh_token)

require_once __DIR__ . '/../bootstrap.php';

if (http_method() !== 'POST') json_error('Metodo non consentito', 405);

$body  = request_body();
$token = str_val($body['refresh_token'] ?? '');
if (empty($token)) json_error('refresh_token mancante');

// Verifica firma e scadenza del JWT
$payload = verify_refresh_token($token);
if (!$payload) json_error('Refresh token non valido o scaduto', 401);

// Verifica che non sia stato revocato nel DB
if (!is_refresh_token_valid($token)) json_error('Refresh token revocato', 401);

$userId = $payload['sub'];

// Revoca il vecchio refresh token e ne emette uno nuovo (rotation)
revoke_refresh_token($token);
$newRefresh = create_refresh_token($userId);
$newAccess  = create_access_token($userId);
store_refresh_token($userId, $newRefresh);

json_ok([
    'access_token'  => $newAccess,
    'refresh_token' => $newRefresh,
    'expires_in'    => JWT_ACCESS_TTL,
]);
