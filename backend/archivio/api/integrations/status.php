<?php
declare(strict_types=1);

require_once __DIR__ . '/common.php';

$userId = integration_user_id();
$row = integration_row(INTEGRATION_PROVIDER_GOOGLE, $userId);
$googleDriveReady = google_row_has_drive_scope($row);

json_ok([
    'googleDriveConnected' => $googleDriveReady,
    'googleDriveNeedsReconnect' => $row !== null && !$googleDriveReady,
    'dropboxConnected' => false,
    'googleDriveEmail' => $row ? (string)($row['account_email'] ?? '') : '',
]);
