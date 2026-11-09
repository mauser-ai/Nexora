<?php
declare(strict_types=1);

require_once __DIR__ . '/common.php';

$data = request_json();
$path = normalize_relative_path((string)($data['path'] ?? ''));
$name = sanitize_segment((string)($data['name'] ?? ''));

if ($name === '') {
    json_error('Nome cartella obbligatorio.', 422);
}

$parent = full_path($archiveRoot, $path);
if (!is_dir($parent)) {
    json_error('Percorso padre non valido.', 404);
}

$target = $parent . DIRECTORY_SEPARATOR . $name;
if (is_dir($target)) {
    json_error('La cartella esiste gia.', 409);
}

if (!mkdir($target, 0775, true)) {
    json_error('Impossibile creare cartella.', 500);
}

json_ok([
    'ok' => true,
    'path' => relative_from_full($archiveRoot, $target),
]);

