<?php
declare(strict_types=1);

require_once __DIR__ . '/common.php';

$data = request_json();
$path = normalize_relative_path((string)($data['path'] ?? ''));
$isDirectory = (bool)($data['isDirectory'] ?? false);

if ($path === '') {
    json_error('Path non valido.', 422);
}

$full = full_path($archiveRoot, $path);
if (!file_exists($full)) {
    json_error('Elemento non trovato.', 404);
}

$token = bin2hex(random_bytes(16));
$expiresAtTs = time() + (7 * 24 * 60 * 60);
$payload = [
    'token' => $token,
    'path' => $path,
    'isDirectory' => $isDirectory,
    'createdAt' => date(DATE_ATOM),
    'expiresAt' => date(DATE_ATOM, $expiresAtTs),
];
$targetFile = $shareRoot . DIRECTORY_SEPARATOR . $token . '.json';
if (@file_put_contents($targetFile, json_encode($payload, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES)) === false) {
    json_error('Errore creazione link condiviso.', 500);
}

$url = request_base_url() . '/archivio/share.php?token=' . urlencode($token);
json_ok([
    'ok' => true,
    'token' => $token,
    'url' => $url,
    'expiresAt' => date(DATE_ATOM, $expiresAtTs),
]);
