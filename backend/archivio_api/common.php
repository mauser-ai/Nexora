<?php
declare(strict_types=1);

header('Content-Type: application/json; charset=utf-8');

$archiveRoot = __DIR__ . '/../storage';
if (!is_dir($archiveRoot)) {
    @mkdir($archiveRoot, 0775, true);
}
$shareRoot = __DIR__ . '/../shares';
if (!is_dir($shareRoot)) {
    @mkdir($shareRoot, 0775, true);
}

function ensure_directory_exists(string $path): void
{
    if (is_dir($path)) {
        return;
    }
    if (!@mkdir($path, 0775, true) && !is_dir($path)) {
        json_error("Impossibile creare la cartella: {$path}", 500);
    }
}

function json_ok(array $payload = []): void
{
    http_response_code(200);
    echo json_encode($payload, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
    exit;
}

function json_error(string $message, int $status = 400): void
{
    http_response_code($status);
    echo json_encode(['error' => $message], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
    exit;
}

function request_json(): array
{
    $raw = file_get_contents('php://input');
    if ($raw === false || trim($raw) === '') {
        return [];
    }
    $decoded = json_decode($raw, true);
    if (!is_array($decoded)) {
        json_error('Payload JSON non valido.', 422);
    }
    return $decoded;
}

function sanitize_segment(string $segment): string
{
    $segment = trim($segment);
    $segment = preg_replace('/\s+/', ' ', $segment ?? '');
    $segment = preg_replace('/[^A-Za-z0-9 _\-.àèéìòùÀÈÉÌÒÙ]/u', '', $segment ?? '');
    return trim((string)$segment);
}

function normalize_relative_path(string $path): string
{
    $path = str_replace('\\', '/', $path);
    $parts = explode('/', $path);
    $safe = [];
    foreach ($parts as $part) {
        $part = sanitize_segment($part);
        if ($part === '' || $part === '.' || $part === '..') {
            continue;
        }
        $safe[] = $part;
    }
    return implode('/', $safe);
}

function full_path(string $archiveRoot, string $relativePath): string
{
    $relativePath = normalize_relative_path($relativePath);
    if ($relativePath === '') {
        return $archiveRoot;
    }
    return $archiveRoot . DIRECTORY_SEPARATOR . str_replace('/', DIRECTORY_SEPARATOR, $relativePath);
}

function relative_from_full(string $archiveRoot, string $fullPath): string
{
    $archiveRoot = rtrim(str_replace('\\', '/', $archiveRoot), '/');
    $fullPath = str_replace('\\', '/', $fullPath);
    if (strpos($fullPath, $archiveRoot) !== 0) {
        return '';
    }
    return ltrim(substr($fullPath, strlen($archiveRoot)), '/');
}

function request_base_url(): string
{
    $https = (!empty($_SERVER['HTTPS']) && $_SERVER['HTTPS'] !== 'off');
    $scheme = $https ? 'https' : 'http';
    $host = (string)($_SERVER['HTTP_HOST'] ?? 'localhost');
    return $scheme . '://' . $host;
}

function archive_root_folders(): array
{
    return [
        'Clienti',
        'Documenti interni',
    ];
}

function archive_company_subfolders(): array
{
    return [
        'Documentazione',
        'Documentazione/Amministrativa',
        'Documentazione/Identificativa',
    ];
}

function ensure_archive_base_structure(string $archiveRoot): void
{
    foreach (archive_root_folders() as $folderName) {
        $folderPath = full_path($archiveRoot, $folderName);
        ensure_directory_exists($folderPath);
    }
}

function ensure_company_archive_folders(string $archiveRoot, string $companyName): void
{
    $companyName = sanitize_segment($companyName);
    if ($companyName === '') {
        return;
    }

    ensure_archive_base_structure($archiveRoot);

    $companyRoot = full_path($archiveRoot, "Clienti/{$companyName}");
    ensure_directory_exists($companyRoot);

    foreach (archive_company_subfolders() as $subfolderName) {
        ensure_directory_exists($companyRoot . DIRECTORY_SEPARATOR . $subfolderName);
    }
}

function ensure_project_archive_folders(
    string $archiveRoot,
    string $companyName,
    string $projectName,
    array $phaseNames = []
): void {
    $companyName = sanitize_segment($companyName);
    $projectName = sanitize_segment($projectName);
    if ($companyName === '' || $projectName === '') {
        return;
    }

    ensure_company_archive_folders($archiveRoot, $companyName);

    $projectRoot = full_path($archiveRoot, "Clienti/{$companyName}/{$projectName}");
    ensure_directory_exists($projectRoot);

    $uniquePhaseNames = [];
    foreach ($phaseNames as $phaseName) {
        $safePhaseName = sanitize_segment((string)$phaseName);
        if ($safePhaseName === '' || isset($uniquePhaseNames[$safePhaseName])) {
            continue;
        }
        $uniquePhaseNames[$safePhaseName] = true;
        ensure_directory_exists($projectRoot . DIRECTORY_SEPARATOR . $safePhaseName);
    }
}
