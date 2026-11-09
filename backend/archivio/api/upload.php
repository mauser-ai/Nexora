<?php
declare(strict_types=1);

require_once __DIR__ . '/common.php';

$contentType = strtolower((string)($_SERVER['CONTENT_TYPE'] ?? ''));

function save_bytes_to_target(string $archiveRoot, string $path, string $fileName, string $bytes): array
{
    $targetDir = full_path($archiveRoot, $path);
    if (!is_dir($targetDir)) {
        json_error('Cartella destinazione non trovata.', 404);
    }
    $safeName = sanitize_segment($fileName);
    if ($safeName === '') {
        json_error('Nome file non valido.', 422);
    }
    $destination = $targetDir . DIRECTORY_SEPARATOR . $safeName;
    if (@file_put_contents($destination, $bytes) === false) {
        json_error('Errore salvataggio file (permessi cartella storage).', 500);
    }
    return [
        'ok' => true,
        'path' => relative_from_full($archiveRoot, $destination),
    ];
}

// 1) Multipart form-data.
if (strpos($contentType, 'multipart/form-data') !== false && isset($_FILES['file'])) {
    $path = normalize_relative_path((string)($_POST['path'] ?? ''));
    $tmp = $_FILES['file']['tmp_name'] ?? '';
    $name = sanitize_segment((string)($_FILES['file']['name'] ?? ''));
    $errorCode = (int)($_FILES['file']['error'] ?? UPLOAD_ERR_OK);
    if ($errorCode !== UPLOAD_ERR_OK) {
        $errors = [
            UPLOAD_ERR_INI_SIZE => 'File oltre upload_max_filesize.',
            UPLOAD_ERR_FORM_SIZE => 'File oltre MAX_FILE_SIZE del form.',
            UPLOAD_ERR_PARTIAL => 'Upload parziale.',
            UPLOAD_ERR_NO_FILE => 'Nessun file ricevuto.',
            UPLOAD_ERR_NO_TMP_DIR => 'Cartella temporanea PHP mancante.',
            UPLOAD_ERR_CANT_WRITE => 'PHP non riesce a scrivere su disco.',
            UPLOAD_ERR_EXTENSION => 'Upload bloccato da estensione PHP.',
        ];
        json_error($errors[$errorCode] ?? 'Errore upload sconosciuto.', 422);
    }
    if ($name === '' || $tmp === '') {
        json_error('Upload non valido.', 422);
    }
    $targetDir = full_path($archiveRoot, $path);
    if (!is_dir($targetDir)) {
        json_error('Cartella destinazione non trovata.', 404);
    }
    $destination = $targetDir . DIRECTORY_SEPARATOR . $name;
    if (!move_uploaded_file($tmp, $destination)) {
        if (!@copy($tmp, $destination)) {
            json_error('Errore salvataggio file (permessi cartella storage).', 500);
        }
    }
    json_ok([
        'ok' => true,
        'path' => relative_from_full($archiveRoot, $destination),
    ]);
}

// 2) JSON base64.
if (strpos($contentType, 'application/json') !== false) {
    $data = request_json();
    $path = normalize_relative_path((string)($data['path'] ?? ''));
    $fileName = (string)($data['fileName'] ?? '');
    $contentBase64 = (string)($data['contentBase64'] ?? '');
    if ($fileName === '' || $contentBase64 === '') {
        json_error('Payload upload base64 non valido.', 422);
    }
    $bytes = base64_decode($contentBase64, true);
    if ($bytes === false) {
        json_error('Base64 non valido.', 422);
    }
    json_ok(save_bytes_to_target($archiveRoot, $path, $fileName, $bytes));
}

// 3) Raw octet-stream.
$rawBody = file_get_contents('php://input');
if ($rawBody !== false && $rawBody !== '') {
    $path = normalize_relative_path((string)($_GET['path'] ?? ''));
    $fileName = (string)($_GET['fileName'] ?? '');
    if ($fileName === '') {
        json_error('fileName mancante per upload raw.', 422);
    }
    json_ok(save_bytes_to_target($archiveRoot, $path, $fileName, $rawBody));
}

json_error('Nessun payload upload valido ricevuto.', 422);
