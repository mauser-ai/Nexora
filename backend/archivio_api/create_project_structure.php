<?php
declare(strict_types=1);

require_once __DIR__ . '/common.php';

$data = request_json();
$companyName = sanitize_segment((string)($data['company'] ?? ''));
$projectName = sanitize_segment((string)($data['project'] ?? ''));
$phaseNamesRaw = $data['phases'] ?? [];

if ($companyName === '') {
    json_error('Ragione sociale obbligatoria.', 422);
}

if ($projectName === '') {
    json_error('Nome progetto obbligatorio.', 422);
}

$phaseNames = [];
if (is_array($phaseNamesRaw)) {
    foreach ($phaseNamesRaw as $phaseName) {
        $safePhaseName = sanitize_segment((string)$phaseName);
        if ($safePhaseName !== '') {
            $phaseNames[] = $safePhaseName;
        }
    }
}

ensure_project_archive_folders($archiveRoot, $companyName, $projectName, $phaseNames);

json_ok([
    'ok' => true,
    'company' => $companyName,
    'project' => $projectName,
    'phases' => $phaseNames,
    'path' => "Clienti/{$companyName}/{$projectName}",
]);
