<?php
declare(strict_types=1);

require_once __DIR__ . '/common.php';

$contentType = strtolower((string)($_SERVER['CONTENT_TYPE'] ?? ''));
$provider = (string)($_POST['provider'] ?? $_GET['provider'] ?? '');
$path = normalize_relative_path((string)($_POST['path'] ?? $_GET['path'] ?? ''));
$fileName = '';
$bytes = null;

if (strpos($contentType, 'multipart/form-data') !== false && isset($_FILES['file'])) {
    $fileName = sanitize_segment((string)($_FILES['file']['name'] ?? ''));
    $tmp = (string)($_FILES['file']['tmp_name'] ?? '');
    if ($tmp === '' || $fileName === '') {
        json_error('Upload non valido.', 422);
    }
    $bytes = file_get_contents($tmp);
} else {
    $payload = request_json();
    $provider = (string)($payload['provider'] ?? $provider);
    $path = normalize_relative_path((string)($payload['path'] ?? $path));
    $fileName = sanitize_segment((string)($payload['fileName'] ?? ''));
    $contentBase64 = (string)($payload['contentBase64'] ?? '');
    $bytes = base64_decode($contentBase64, true);
}

if ($provider !== INTEGRATION_PROVIDER_GOOGLE || $fileName === '' || $bytes === false || $bytes === null) {
    json_error('Richiesta upload non valida.', 422);
}

$token = google_access_token(integration_user_id());
$parentId = google_folder_id_for_path($token, $path);
$boundary = 'nexora_' . bin2hex(random_bytes(10));
$metadata = json_encode(['name' => $fileName, 'parents' => [$parentId]], JSON_UNESCAPED_UNICODE);
$body = "--{$boundary}\r\n"
    . "Content-Type: application/json; charset=UTF-8\r\n\r\n"
    . $metadata . "\r\n"
    . "--{$boundary}\r\n"
    . "Content-Type: application/octet-stream\r\n\r\n"
    . $bytes . "\r\n"
    . "--{$boundary}--";

$response = integration_http(
    'POST',
    'https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart&fields=id,name',
    [
        'Authorization: Bearer ' . $token,
        'Content-Type: multipart/related; boundary=' . $boundary,
    ],
    $body
);
if ($response['status'] < 200 || $response['status'] >= 300) {
    json_error('Errore upload Google Drive: ' . ($response['raw'] ?? ''), 502);
}

json_ok(['ok' => true, 'id' => (string)($response['body']['id'] ?? '')]);
