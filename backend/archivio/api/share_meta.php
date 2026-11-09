<?php
declare(strict_types=1);

require_once __DIR__ . '/common.php';

$token = preg_replace('/[^a-f0-9]/', '', strtolower((string)($_GET['token'] ?? '')));
if ($token === '') {
    json_error('Token non valido.', 422);
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

$path = normalize_relative_path((string)($meta['path'] ?? ''));
$expiresAt = (string)($meta['expiresAt'] ?? '');
$expiresTs = strtotime($expiresAt ?: '') ?: 0;
if ($expiresTs > 0 && time() > $expiresTs) {
    json_error('Link scaduto. La condivisione e valida per 7 giorni.', 410);
}
$full = full_path($archiveRoot, $path);
if (!file_exists($full)) {
    json_error('Elemento condiviso non piu disponibile.', 404);
}

if (is_file($full)) {
    json_ok([
        'token' => $token,
        'path' => $path,
        'name' => basename($full),
        'isDirectory' => false,
        'expiresAt' => $expiresAt,
        'files' => [[
            'name' => basename($full),
            'path' => $path,
            'sizeBytes' => filesize($full) ?: 0,
        ]],
    ]);
}

$files = [];
$iterator = new RecursiveIteratorIterator(
    new RecursiveDirectoryIterator($full, FilesystemIterator::SKIP_DOTS),
    RecursiveIteratorIterator::LEAVES_ONLY
);
foreach ($iterator as $item) {
    if (!$item->isFile()) {
        continue;
    }
    $rel = relative_from_full($archiveRoot, $item->getPathname());
    $files[] = [
        'name' => basename($item->getPathname()),
        'path' => $rel,
        'sizeBytes' => $item->getSize(),
    ];
}
usort($files, fn($a, $b) => strnatcasecmp((string)$a['path'], (string)$b['path']));

json_ok([
    'token' => $token,
    'path' => $path,
    'name' => basename($full),
    'isDirectory' => true,
    'expiresAt' => $expiresAt,
    'files' => $files,
]);
