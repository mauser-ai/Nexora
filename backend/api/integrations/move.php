<?php
declare(strict_types=1);

require_once __DIR__ . '/common.php';

$payload = request_json();
$provider = integration_provider();
$userId = integration_user_id();
$sourcePath = normalize_relative_path((string)($payload['sourcePath'] ?? ''));
$destinationPath = normalize_relative_path((string)($payload['destinationPath'] ?? ''));
if ($provider !== INTEGRATION_PROVIDER_GOOGLE || $sourcePath === '') {
    json_error('Richiesta non valida.', 422);
}

$token = google_access_token($userId);
$fileId = google_file_id_for_path($token, $sourcePath);
$destinationId = google_folder_id_for_path($token, $destinationPath);
$meta = google_api(
    $token,
    'GET',
    'https://www.googleapis.com/drive/v3/files/' . rawurlencode($fileId) . '?fields=parents'
);
$previousParents = implode(',', array_map('strval', $meta['parents'] ?? []));
$url = 'https://www.googleapis.com/drive/v3/files/' . rawurlencode($fileId) . '?' . http_build_query([
    'addParents' => $destinationId,
    'removeParents' => $previousParents,
    'fields' => 'id,parents',
]);
google_api($token, 'PATCH', $url);

json_ok(['ok' => true]);
