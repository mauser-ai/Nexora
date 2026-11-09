<?php
// ── CORS ──────────────────────────────────────────────────────────────────────

$origin = $_SERVER['HTTP_ORIGIN'] ?? '';
$allowed = defined('ALLOWED_ORIGINS') ? ALLOWED_ORIGINS : [];

if (in_array($origin, $allowed, true)) {
    header('Access-Control-Allow-Origin: ' . $origin);
} else {
    header('Access-Control-Allow-Origin: ' . ($allowed[0] ?? '*'));
}

header('Access-Control-Allow-Credentials: true');
header('Access-Control-Allow-Methods: GET, POST, PUT, PATCH, DELETE, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization, X-Requested-With');
header('Access-Control-Max-Age: 3600');

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(204);
    exit;
}
