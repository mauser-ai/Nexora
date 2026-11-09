<?php
declare(strict_types=1);

require_once __DIR__ . '/common.php';

$provider = integration_provider();
$userId = integration_user_id();
$path = normalize_relative_path((string)($_GET['path'] ?? ''));

if ($provider !== INTEGRATION_PROVIDER_GOOGLE) {
    json_error('Provider non supportato.', 422);
}

$token = google_access_token($userId);
$folderId = google_folder_id_for_path($token, $path);
$query = sprintf("'%s' in parents and trashed = false", addslashes($folderId));
$url = 'https://www.googleapis.com/drive/v3/files?' . http_build_query([
    'q' => $query,
    'fields' => 'files(id,name,mimeType,size,modifiedTime)',
    'pageSize' => '1000',
    'orderBy' => 'folder,name_natural',
]);
$result = google_api($token, 'GET', $url);

$folders = [];
$files = [];
foreach (($result['files'] ?? []) as $file) {
    if (!is_array($file)) {
        continue;
    }
    $entry = google_entry_from_file($file, $path);
    if ($entry['isDirectory']) {
        $folders[] = $entry;
    } else {
        $files[] = $entry;
    }
}

json_ok([
    'currentPath' => $path,
    'folders' => $folders,
    'files' => $files,
]);
