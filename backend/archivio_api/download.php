<?php
declare(strict_types=1);

require_once __DIR__ . '/common.php';

$token = preg_replace('/[^a-f0-9]/', '', strtolower((string)($_GET['token'] ?? '')));
$filePath = normalize_relative_path((string)($_GET['file'] ?? ''));
if ($token === '' || $filePath === '') {
    json_error('Parametri download non validi.', 422);
}

$metaFile = $shareRoot . DIRECTORY_SEPARATOR . $token . '.json';
if (!is_file($metaFile)) {
    json_error('Condivisione non trovata.', 404);
}
$metaRaw = file_get_contents($metaFile);
$meta = is_string($metaRaw) ? json_decode($metaRaw, true) : null;
if (!is_array($meta)) {
    json_error('Condivisione corrotta.', 500);
}

$sharedPath = normalize_relative_path((string)($meta['path'] ?? ''));
$expiresAt = (string)($meta['expiresAt'] ?? '');
$expiresTs = strtotime($expiresAt ?: '') ?: 0;
if ($expiresTs > 0 && time() > $expiresTs) {
    json_error('Link scaduto. La condivisione e valida per 7 giorni.', 410);
}
$sharedFull = full_path($archiveRoot, $sharedPath);
$targetFull = full_path($archiveRoot, $filePath);

if (!is_file($targetFull)) {
    json_error('File non trovato.', 404);
}

$sharedPrefix = rtrim(str_replace('\\', '/', $sharedFull), '/');
$targetNormalized = str_replace('\\', '/', $targetFull);
if (strpos($targetNormalized, $sharedPrefix) !== 0 && $targetNormalized !== $sharedPrefix) {
    json_error('File non autorizzato per questo token.', 403);
}

header('Content-Description: File Transfer');
header('Content-Type: application/octet-stream');
header('Content-Disposition: attachment; filename="' . basename($targetFull) . '"');
header('Content-Length: ' . (string)(filesize($targetFull) ?: 0));
readfile($targetFull);
exit;
