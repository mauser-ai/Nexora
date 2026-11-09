<?php
declare(strict_types=1);

require_once __DIR__ . '/common.php';

$provider = integration_provider();
$userId = integration_user_id();

$clientId = integration_config_value('google_client_id');
$redirectUri = integration_config_value('google_redirect_uri');
if ($provider !== INTEGRATION_PROVIDER_GOOGLE) {
    json_error('OAuth Google non configurato.', 500);
}

$state = base64_encode(json_encode([
    'provider' => $provider,
    'userId' => $userId,
    'nonce' => bin2hex(random_bytes(12)),
], JSON_UNESCAPED_SLASHES));

$url = 'https://accounts.google.com/o/oauth2/v2/auth?' . http_build_query([
    'client_id' => $clientId,
    'redirect_uri' => $redirectUri,
    'response_type' => 'code',
    'scope' => GOOGLE_DRIVE_SCOPE . ' https://www.googleapis.com/auth/userinfo.email',
    'access_type' => 'offline',
    'include_granted_scopes' => 'false',
    'prompt' => 'consent',
    'state' => $state,
]);

if (($_GET['debug'] ?? '') === '1') {
    json_ok([
        'clientId' => $clientId,
        'redirectUri' => $redirectUri,
        'authUrl' => $url,
    ]);
}

header('Location: ' . $url, true, 302);
exit;
