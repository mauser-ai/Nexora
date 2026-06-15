<?php
declare(strict_types=1);

require_once __DIR__ . '/common.php';

$data = request_json();
$companies = $data['companies'] ?? [];
if (!is_array($companies)) {
    json_error('Lista aziende non valida.', 422);
}

ensure_archive_base_structure($archiveRoot);

$created = [];
foreach ($companies as $rawName) {
    $name = sanitize_segment((string)$rawName);
    if ($name === '') {
        continue;
    }
    $folder = full_path($archiveRoot, "Clienti/{$name}");
    $wasMissing = !is_dir($folder);
    ensure_company_archive_folders($archiveRoot, $name);
    if ($wasMissing) {
        $created[] = $name;
    }
}

json_ok([
    'ok' => true,
    'created' => $created,
]);
