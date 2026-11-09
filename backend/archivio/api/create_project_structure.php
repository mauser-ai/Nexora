<?php
declare(strict_types=1);

require_once __DIR__ . '/common.php';

$data = request_json();
$companyName = sanitize_segment((string)($data['company'] ?? ''));
$projectName = sanitize_segment((string)($data['project'] ?? ''));

if ($companyName === '') {
    json_error('Ragione sociale obbligatoria.', 422);
}

if ($projectName === '') {
    json_error('Nome progetto obbligatorio.', 422);
}

ensure_project_archive_folders($archiveRoot, $companyName, $projectName);

json_ok([
    'ok' => true,
    'company' => $companyName,
    'project' => $projectName,
    'path' => "Clienti/{$companyName}/{$projectName}",
]);
