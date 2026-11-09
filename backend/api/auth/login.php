<?php
// POST /api/auth/login.php
// Body: { "firebase_token": "..." }
// Verifica il Firebase ID Token e restituisce access_token + refresh_token

require_once __DIR__ . '/../bootstrap.php';

if (http_method() !== 'POST') json_error('Metodo non consentito', 405);

$body        = request_body();
$firebaseJwt = str_val($body['firebase_token'] ?? '');
if (empty($firebaseJwt)) json_error('firebase_token mancante');

// Verifica token Firebase
$fbPayload = verify_firebase_token($firebaseJwt);
if (!$fbPayload) {
    // Debug: decodifica il payload senza verificare la firma per vedere cosa c'è
    $parts   = explode('.', $firebaseJwt);
    $rawPay  = count($parts) === 3 ? json_decode(base64_decode(strtr($parts[1], '-_', '+/')), true) : [];
    $debug   = APP_DEBUG ? [
        'project_id_configured' => FIREBASE_PROJECT_ID,
        'token_aud'  => $rawPay['aud']  ?? 'N/A',
        'token_iss'  => $rawPay['iss']  ?? 'N/A',
        'token_exp'  => isset($rawPay['exp']) ? date('c', $rawPay['exp']) : 'N/A',
        'server_time'=> date('c'),
    ] : [];
    json_error('Firebase token non valido o scaduto', 401);
}

$userId      = $fbPayload['sub'];
$email       = $fbPayload['email']        ?? '';
$displayName = $fbPayload['name']         ?? '';

// Upsert utente nel DB locale
upsert_user($userId, $email, $displayName);

// Genera tokens
$accessToken  = create_access_token($userId);
$refreshToken = create_refresh_token($userId);

// Salva refresh token nel DB
store_refresh_token($userId, $refreshToken);

json_ok([
    'access_token'  => $accessToken,
    'refresh_token' => $refreshToken,
    'expires_in'    => JWT_ACCESS_TTL,
    'user_id'       => $userId,
    'email'         => $email,
    'display_name'  => $displayName,
]);
