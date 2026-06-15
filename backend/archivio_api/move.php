<?php
declare(strict_types=1);

require_once __DIR__ . '/common.php';

$data = request_json();
$sourcePath = normalize_relative_path((string)($data['sourcePath'] ?? ''));
$destinationPath = normalize_relative_path((string)($data['destinationPath'] ?? ''));

if ($sourcePath === '') {
    json_error('Sorgente non valida.', 422);
}

$source = full_path($archiveRoot, $sourcePath);
if (!file_exists($source)) {
    json_error('Elemento sorgente non trovato.', 404);
}

$destinationDir = full_path($archiveRoot, $destinationPath);
if (!is_dir($destinationDir)) {
    json_error('Cartella destinazione non trovata.', 404);
}

$name = basename($source);
$destination = $destinationDir . DIRECTORY_SEPARATOR . $name;
if (file_exists($destination)) {
    json_error('In destinazione esiste gia un elemento con lo stesso nome.', 409);
}

if (!@rename($source, $destination)) {
    json_error('Errore spostamento.', 500);
}

json_ok([
    'ok' => true,
    'path' => relative_from_full($archiveRoot, $destination),
]);

