<?php
declare(strict_types=1);

require_once __DIR__ . '/common.php';

$payload = request_json();
$provider = integration_provider();
$userId = integration_user_id();
$path = normalize_relative_path((string)($payload['path'] ?? ''));
$name = sanitize_segment((string)($payload['name'] ?? ''));
if ($provider !== INTEGRATION_PROVIDER_GOOGLE || $name === '') {
    json_error('Richiesta non valida.', 422);
}

$token = google_access_token($userId);
$parentId = google_folder_id_for_path($token, $path);
$created = google_api(
    $token,
    'POST',
    'https://www.googleapis.com/drive/v3/files',
    [
        'name' => $name,
        'mimeType' => 'application/vnd.google-apps.folder',
        'parents' => [$parentId],
    ]
);

json_ok(['ok' => true, 'id' => (string)($created['id'] ?? '')]);
