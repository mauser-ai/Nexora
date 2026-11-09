<?php
declare(strict_types=1);

require_once __DIR__ . '/common.php';

ensure_archive_base_structure($archiveRoot);

$folders = [''];
$iterator = new RecursiveIteratorIterator(
    new RecursiveDirectoryIterator($archiveRoot, FilesystemIterator::SKIP_DOTS),
    RecursiveIteratorIterator::SELF_FIRST
);

foreach ($iterator as $item) {
    if (!$item->isDir()) {
        continue;
    }
    $relative = relative_from_full($archiveRoot, $item->getPathname());
    if ($relative !== '') {
        $folders[] = $relative;
    }
}

sort($folders, SORT_NATURAL | SORT_FLAG_CASE);
json_ok(['folders' => $folders]);
