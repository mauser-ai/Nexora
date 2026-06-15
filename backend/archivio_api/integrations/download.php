<?php
declare(strict_types=1);

require_once __DIR__ . '/common.php';

$provider = preg_replace('/[^a-z_]/', '', strtolower((string)($_GET['provider'] ?? '')));
$userId = integration_user_id();
$path = normalize_relative_path((string)($_GET['path'] ?? ''));

if ($path === '') {
    http_response_code(422);
    exit('Percorso non valido.');
}
if ($provider !== INTEGRATION_PROVIDER_GOOGLE) {
    http_response_code(422);
    exit('Provider non supportato.');
}

$token = google_access_token($userId);
$fileId = google_file_id_for_path($token, $path);

$meta = google_api(
    $token,
    'GET',
    'https://www.googleapis.com/drive/v3/files/' . urlencode($fileId) . '?fields=name,mimeType'
);
$mimeType = (string)($meta['mimeType'] ?? 'application/octet-stream');
$name = (string)($meta['name'] ?? 'file');

$googleNativeExport = [
    'application/vnd.google-apps.document'     => 'application/pdf',
    'application/vnd.google-apps.spreadsheet'  => 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    'application/vnd.google-apps.presentation' => 'application/pdf',
    'application/vnd.google-apps.drawing'      => 'application/pdf',
];

if (isset($googleNativeExport[$mimeType])) {
    $exportMime = $googleNativeExport[$mimeType];
    $downloadUrl = 'https://www.googleapis.com/drive/v3/files/'
        . urlencode($fileId) . '/export?mimeType=' . urlencode($exportMime);
    $mimeType = $exportMime;
} else {
    $downloadUrl = 'https://www.googleapis.com/drive/v3/files/' . urlencode($fileId) . '?alt=media';
}

$curl = curl_init($downloadUrl);
curl_setopt_array($curl, [
    CURLOPT_RETURNTRANSFER => true,
    CURLOPT_HTTPHEADER => ['Authorization: Bearer ' . $token],
    CURLOPT_FOLLOWLOCATION => true,
    CURLOPT_TIMEOUT => 120,
]);
$body = curl_exec($curl);
$status = (int)curl_getinfo($curl, CURLINFO_RESPONSE_CODE);
curl_close($curl);

if ($body === false || $status < 200 || $status >= 300) {
    http_response_code(502);
    exit('Errore download Google Drive.');
}

$safeName = str_replace(['"', '\\', "\r", "\n"], '', $name);
header('Content-Type: ' . $mimeType);
header('Content-Disposition: inline; filename="' . $safeName . '"');
header('Content-Length: ' . strlen($body));
header('X-Frame-Options: SAMEORIGIN');
echo $body;
