<?php
declare(strict_types=1);

require_once __DIR__ . '/common.php';

$payload = request_json();
$provider = integration_provider();
$userId = integration_user_id();
$path = normalize_relative_path((string)($payload['path'] ?? ''));
$newName = sanitize_segment((string)($payload['newName'] ?? ''));
if ($provider !== INTEGRATION_PROVIDER_GOOGLE || $path === '' || $newName === '') {
    json_error('Richiesta non valida.', 422);
}

$token = google_access_token($userId);
$fileId = google_file_id_for_path($token, $path);
google_api(
    $token,
    'PATCH',
    'https://www.googleapis.com/drive/v3/files/' . rawurlencode($fileId),
    ['name' => $newName]
);

json_ok(['ok' => true]);
