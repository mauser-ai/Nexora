<?php
declare(strict_types=1);

require_once __DIR__ . '/common.php';

$data = request_json();
$path = normalize_relative_path((string)($data['path'] ?? ''));
$isDirectory = (bool)($data['isDirectory'] ?? false);

if ($path === '') {
    json_error('Path non valido.', 422);
}

$target = full_path($archiveRoot, $path);
if (!file_exists($target)) {
    json_error('Elemento non trovato.', 404);
}

if ($isDirectory) {
    $iterator = new RecursiveIteratorIterator(
        new RecursiveDirectoryIterator($target, FilesystemIterator::SKIP_DOTS),
        RecursiveIteratorIterator::CHILD_FIRST
    );
    foreach ($iterator as $item) {
        $ok = $item->isDir() ? @rmdir($item->getPathname()) : @unlink($item->getPathname());
        if (!$ok) {
            json_error('Errore eliminazione contenuto cartella.', 500);
        }
    }
    if (!@rmdir($target)) {
        json_error('Errore eliminazione cartella.', 500);
    }
} else {
    if (!@unlink($target)) {
        json_error('Errore eliminazione file.', 500);
    }
}

json_ok(['ok' => true]);

