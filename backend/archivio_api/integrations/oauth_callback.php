<?php
declare(strict_types=1);

require_once __DIR__ . '/common.php';

$code = (string)($_GET['code'] ?? '');
$stateRaw = (string)($_GET['state'] ?? '');
if ($code === '' || $stateRaw === '') {
    json_error('Callback OAuth non valida.', 422);
}

$stateJson = base64_decode($stateRaw, true);
$state = is_string($stateJson) ? json_decode($stateJson, true) : null;
if (!is_array($state) || ($state['provider'] ?? '') !== INTEGRATION_PROVIDER_GOOGLE) {
    json_error('State OAuth non valido.', 422);
}

$userId = preg_replace('/[^A-Za-z0-9_\-@.]/', '', (string)($state['userId'] ?? 'default')) ?: 'default';
$tokenPayload = google_token_request([
    'client_id' => integration_config_value('google_client_id'),
    'client_secret' => integration_config_value('google_client_secret'),
    'redirect_uri' => integration_config_value('google_redirect_uri'),
    'code' => $code,
    'grant_type' => 'authorization_code',
]);
save_google_tokens($userId, $tokenPayload);

header('Content-Type: text/html; charset=utf-8');
?>
<!doctype html>
<html lang="it">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Google Drive collegato</title>
  <style>
    body{margin:0;min-height:100vh;display:grid;place-items:center;font-family:system-ui,-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;background:linear-gradient(135deg,#07111d,#13395b 55%,#26d9c7);color:white}
    .card{width:min(520px,calc(100vw - 32px));padding:32px;border:1px solid rgba(255,255,255,.36);border-radius:28px;background:rgba(255,255,255,.14);box-shadow:0 24px 70px rgba(0,0,0,.32);backdrop-filter:blur(24px)}
    h1{margin:0 0 8px;font-size:30px}
    p{margin:0;color:rgba(255,255,255,.78);line-height:1.45}
  </style>
</head>
<body>
  <div class="card">
    <h1>Drive collegato</h1>
    <p>Puoi chiudere questa scheda e tornare a Nexora. Google Drive sara disponibile nell Archivio.</p>
  </div>
</body>
</html>
