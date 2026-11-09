<?php
declare(strict_types=1);

require_once __DIR__ . '/common.php';

$userId = integration_user_id();
$row = integration_row(INTEGRATION_PROVIDER_GOOGLE, $userId);

json_ok([
    'googleDriveConnected' => $row !== null,
    'dropboxConnected' => false,
    'googleDriveEmail' => $row ? (string)($row['account_email'] ?? '') : '',
]);
