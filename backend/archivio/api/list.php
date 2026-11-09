<?php
declare(strict_types=1);

require_once __DIR__ . '/common.php';

ensure_archive_base_structure($archiveRoot);

$path = isset($_GET['path']) ? (string)$_GET['path'] : '';
$relative = normalize_relative_path($path);
$target = full_path($archiveRoot, $relative);

if (!is_dir($target)) {
    json_error('Cartella non trovata.', 404);
}

$folders = [];
$files = [];
$items = scandir($target);
if ($items === false) {
    json_error('Impossibile leggere la cartella.', 500);
}

foreach ($items as $item) {
    if ($item === '.' || $item === '..') {
        continue;
    }
    $itemPath = $target . DIRECTORY_SEPARATOR . $item;
    $rel = relative_from_full($archiveRoot, $itemPath);
    $entry = [
        'name' => $item,
        'path' => $rel,
        'isDirectory' => is_dir($itemPath),
        'sizeBytes' => is_file($itemPath) ? filesize($itemPath) : null,
        'modifiedAt' => date(DATE_ATOM, filemtime($itemPath) ?: time()),
    ];
    if (is_dir($itemPath)) {
        $folders[] = $entry;
    } else {
        $files[] = $entry;
    }
}

usort($folders, fn($a, $b) => strnatcasecmp((string)$a['name'], (string)$b['name']));
usort($files, fn($a, $b) => strnatcasecmp((string)$a['name'], (string)$b['name']));

json_ok([
    'currentPath' => $relative,
    'folders' => $folders,
    'files' => $files,
]);
