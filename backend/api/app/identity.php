<?php
declare(strict_types=1);

// Lookup identità per il prefill della schermata di login (PRIMA dell'auth):
// dato un indirizzo email esatto ritorna solo nome visualizzato e avatar.
// Stessa esposizione che aveva la collection `users` su Firestore.

require_once dirname(__DIR__) . '/bootstrap.php';

header('Content-Type: application/json; charset=utf-8');

if (!function_exists('db')) {
    json_error('bootstrap.php non espone db(): PDO.', 500);
}

$email = strtolower(trim((string)($_GET['email'] ?? '')));
if ($email === '' || !filter_var($email, FILTER_VALIDATE_EMAIL)) {
    json_error('Email non valida.', 422);
}

$stmt = db()->prepare(
    'SELECT
        p.uid,
        p.email,
        p.display_name,
        p.avatar_url,
        t.brand_logo_url,
        t.brand_color,
        t.enabled_modules
     FROM user_profiles p
     LEFT JOIN team_members m ON m.user_id = p.uid AND m.status = \'active\'
     LEFT JOIN teams t ON t.id = m.team_id
     WHERE LOWER(p.email) = :email
     LIMIT 1'
);
$stmt->execute([':email' => $email]);
$row = $stmt->fetch(PDO::FETCH_ASSOC);

function identity_has_branding(?string $raw): bool
{
    if ($raw === null || $raw === '') {
        return false;
    }
    $decoded = json_decode($raw, true);
    if (!is_array($decoded)) {
        return false;
    }
    return in_array('custom_branding', $decoded, true);
}

if (!$row) {
    json_ok(['found' => false]);
}

$brandingEnabled = identity_has_branding($row['enabled_modules'] ?? null);

json_ok([
    'found' => true,
    'email' => (string)$row['email'],
    'displayName' => (string)$row['display_name'],
    'avatarUrl' => (string)$row['avatar_url'],
    'brandLogoUrl' => $brandingEnabled ? (string)($row['brand_logo_url'] ?? '') : '',
    'brandColor' => $brandingEnabled ? (string)($row['brand_color'] ?? '') : '',
    'brandingEnabled' => $brandingEnabled,
]);
