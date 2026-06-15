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
    'SELECT email, display_name, avatar_url FROM user_profiles
     WHERE LOWER(email) = :email LIMIT 1'
);
$stmt->execute([':email' => $email]);
$row = $stmt->fetch(PDO::FETCH_ASSOC);

if (!$row) {
    json_ok(['found' => false]);
}

json_ok([
    'found' => true,
    'email' => (string)$row['email'],
    'displayName' => (string)$row['display_name'],
    'avatarUrl' => (string)$row['avatar_url'],
]);
