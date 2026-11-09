<?php
declare(strict_types=1);

require_once __DIR__ . '/common.php';

$data = request_json();
$companyName = sanitize_segment((string)($data['company'] ?? ''));

if ($companyName === '') {
    json_error('Ragione sociale obbligatoria.', 422);
}

ensure_company_archive_folders($archiveRoot, $companyName);

json_ok([
    'ok' => true,
    'company' => $companyName,
    'path' => "Clienti/{$companyName}",
]);
