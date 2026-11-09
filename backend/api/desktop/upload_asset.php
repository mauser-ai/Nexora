<?php
declare(strict_types=1);

// Upload generico di immagini applicative (asset template PDF, logo brand,
// avatar profilo). Stesso flusso di upload_wallpaper.php: file salvato
// sull'hosting, risposta con URL pubblico.

require_once dirname(__DIR__) . '/bootstrap.php';

header('Content-Type: application/json; charset=utf-8');

$userId = require_auth();

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    json_error('Metodo non consentito.', 405);
}

$folder = (string)($_POST['folder'] ?? 'template');
$allowedFolders = ['template', 'brand', 'avatar'];
if (!in_array($folder, $allowedFolders, true)) {
    json_error('Cartella non valida.', 422);
}

if (!isset($_FILES['file']) || !is_array($_FILES['file'])) {
    json_error('File mancante.', 422);
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

$originalName = (string)($file['name'] ?? 'asset');
$extension = strtolower(pathinfo($originalName, PATHINFO_EXTENSION));
$allowed = ['jpg', 'jpeg', 'png', 'webp', 'gif', 'svg'];
if (!in_array($extension, $allowed, true)) {
    json_error('Formato non supportato. Usa JPG, PNG, WEBP, GIF o SVG.', 422);
}

$maxBytes = 8 * 1024 * 1024;
$size = (int)($file['size'] ?? 0);
if ($size <= 0 || $size > $maxBytes) {
    json_error('L\'immagine deve essere inferiore a 8MB.', 422);
}

$safeUser = preg_replace('/[^a-zA-Z0-9_-]/', '', $userId);
$storageDir = dirname(__DIR__) . '/uploads/assets/' . $folder . '/' . $safeUser;
if (!is_dir($storageDir) && !mkdir($storageDir, 0775, true) && !is_dir($storageDir)) {
    json_error('Impossibile creare la cartella di upload.', 500);
}

$fileName = $folder . '_' . date('Ymd_His') . '_' . bin2hex(random_bytes(4)) . '.' . $extension;
$destination = $storageDir . DIRECTORY_SEPARATOR . $fileName;
if (!move_uploaded_file($tmp, $destination)) {
    json_error('Impossibile salvare il file sul server.', 500);
}

$scheme = (!empty($_SERVER['HTTPS']) && $_SERVER['HTTPS'] !== 'off') ? 'https' : 'http';
$host = (string)($_SERVER['HTTP_HOST'] ?? 'localhost');
$scriptName = (string)($_SERVER['SCRIPT_NAME'] ?? '/api/desktop/upload_asset.php');
$basePath = rtrim(str_replace('\\', '/', dirname(dirname($scriptName))), '/');
$publicPath = ($basePath === '' ? '' : $basePath)
    . '/uploads/assets/' . $folder . '/'
    . rawurlencode($safeUser)
    . '/'
    . rawurlencode($fileName);
$url = $scheme . '://' . $host . $publicPath;

json_ok([
    'ok' => true,
    'url' => $url,
    'path' => $publicPath,
]);
