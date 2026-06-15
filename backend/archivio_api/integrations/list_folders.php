<?php
declare(strict_types=1);

require_once __DIR__ . '/common.php';

$provider = integration_provider();
$userId = integration_user_id();
if ($provider !== INTEGRATION_PROVIDER_GOOGLE) {
    json_error('Provider non supportato.', 422);
}

$token = google_access_token($userId);
$folders = [];

function collect_google_folders(string $token, string $parentId, string $prefix, array &$folders, int $depth = 0): void
{
    if ($depth > 8) {
        return;
    }
    $query = sprintf(
        "'%s' in parents and mimeType = 'application/vnd.google-apps.folder' and trashed = false",
        addslashes($parentId)
    );
    $url = 'https://www.googleapis.com/drive/v3/files?' . http_build_query([
        'q' => $query,
        'fields' => 'files(id,name)',
        'pageSize' => '1000',
        'orderBy' => 'name_natural',
    ]);
    $result = google_api($token, 'GET', $url);
    foreach (($result['files'] ?? []) as $file) {
        if (!is_array($file)) {
            continue;
        }
        $name = sanitize_segment((string)($file['name'] ?? ''));
        if ($name === '') {
            continue;
        }
        $path = trim($prefix . '/' . $name, '/');
        $folders[] = $path;
        collect_google_folders($token, (string)$file['id'], $path, $folders, $depth + 1);
    }
}

collect_google_folders($token, 'root', '', $folders);
json_ok(['folders' => $folders]);
