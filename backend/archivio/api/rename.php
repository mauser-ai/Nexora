<?php
declare(strict_types=1);

require_once __DIR__ . '/common.php';

$data = request_json();
$path = normalize_relative_path((string)($data['path'] ?? ''));
$newName = sanitize_segment((string)($data['newName'] ?? ''));

if ($path === '' || $newName === '') {
    json_error('Path o nuovo nome non valido.', 422);
}

$source = full_path($archiveRoot, $path);
if (!file_exists($source)) {
    json_error('Elemento non trovato.', 404);
}

$parent = dirname($source);
$destination = $parent . DIRECTORY_SEPARATOR . $newName;
if (file_exists($destination)) {
    json_error('Esiste gia un elemento con questo nome.', 409);
}

if (!@rename($source, $destination)) {
    json_error('Errore rinomina.', 500);
}

json_ok([
    'ok' => true,
    'path' => relative_from_full($archiveRoot, $destination),
]);

