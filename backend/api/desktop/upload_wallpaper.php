<?php
declare(strict_types=1);

require_once dirname(__DIR__) . '/bootstrap.php';

header('Content-Type: application/json; charset=utf-8');

$userId = require_auth();

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    json_error('Metodo non consentito.', 405);
}

if (!isset($_FILES['file']) || !is_array($_FILES['file'])) {
    json_error('File wallpaper mancante.', 422);
}

$file = $_FILES['file'];
$errorCode = (int)($file['error'] ?? UPLOAD_ERR_NO_FILE);
if ($errorCode !== UPLOAD_ERR_OK) {
    $errors = [
        UPLOAD_ERR_INI_SIZE => 'File oltre il limite upload_max_filesize.',
        UPLOAD_ERR_FORM_SIZE => 'File oltre il limite MAX_FILE_SIZE.',
        UPLOAD_ERR_PARTIAL => 'Upload interrotto prima del completamento.',
        UPLOAD_ERR_NO_FILE => 'Nessun file ricevuto.',
    ];
    json_error($errors[$errorCode] ?? 'Errore upload sconosciuto.', 422);
}

$tmp = (string)($file['tmp_name'] ?? '');
if ($tmp === '' || !is_uploaded_file($tmp)) {
    json_error('Upload non valido.', 422);
}

$originalName = (string)($file['name'] ?? 'wallpaper');
$extension = strtolower(pathinfo($originalName, PATHINFO_EXTENSION));
$allowed = ['jpg', 'jpeg', 'png', 'webp'];
if (!in_array($extension, $allowed, true)) {
    json_error('Formato non supportato. Usa JPG, PNG o WEBP.', 422);
}

$maxBytes = 12 * 1024 * 1024;
$size = (int)($file['size'] ?? 0);
if ($size <= 0 || $size > $maxBytes) {
    json_error('Il wallpaper deve essere inferiore a 12MB.', 422);
}

$storageDir = dirname(__DIR__) . '/uploads/desktop_wallpapers/' . preg_replace('/[^a-zA-Z0-9_-]/', '', $userId);
if (!is_dir($storageDir) && !mkdir($storageDir, 0775, true) && !is_dir($storageDir)) {
    json_error('Impossibile creare la cartella di upload.', 500);
}

$fileName = 'wallpaper_' . date('Ymd_His') . '_' . bin2hex(random_bytes(4)) . '.' . $extension;
$destination = $storageDir . DIRECTORY_SEPARATOR . $fileName;
if (!move_uploaded_file($tmp, $destination)) {
    json_error('Impossibile salvare il wallpaper sul server.', 500);
}

$scheme = (!empty($_SERVER['HTTPS']) && $_SERVER['HTTPS'] !== 'off') ? 'https' : 'http';
$host = (string)($_SERVER['HTTP_HOST'] ?? 'localhost');
$scriptName = (string)($_SERVER['SCRIPT_NAME'] ?? '/api/desktop/upload_wallpaper.php');
$basePath = rtrim(str_replace('\\', '/', dirname(dirname($scriptName))), '/');
$publicPath = ($basePath === '' ? '' : $basePath)
    . '/uploads/desktop_wallpapers/'
    . rawurlencode(preg_replace('/[^a-zA-Z0-9_-]/', '', $userId))
    . '/'
    . rawurlencode($fileName);
$url = $scheme . '://' . $host . $publicPath;

json_ok([
    'ok' => true,
    'url' => $url,
    'path' => $publicPath,
]);
