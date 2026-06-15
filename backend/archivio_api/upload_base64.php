<?php
declare(strict_types=1);

require_once __DIR__ . '/common.php';

$data = request_json();
$path = normalize_relative_path((string)($data['path'] ?? ''));
$fileName = sanitize_segment((string)($data['fileName'] ?? ''));
$contentBase64 = (string)($data['contentBase64'] ?? '');

if ($fileName === '' || $contentBase64 === '') {
    json_error('Payload upload base64 non valido.', 422);
}

$targetDir = full_path($archiveRoot, $path);
if (!is_dir($targetDir)) {
    json_error('Cartella destinazione non trovata.', 404);
}

$bytes = base64_decode($contentBase64, true);
if ($bytes === false) {
    json_error('Base64 non valido.', 422);
}

$destination = $targetDir . DIRECTORY_SEPARATOR . $fileName;
if (@file_put_contents($destination, $bytes) === false) {
    json_error('Errore salvataggio file (permessi cartella storage).', 500);
}

json_ok([
    'ok' => true,
    'path' => relative_from_full($archiveRoot, $destination),
]);

