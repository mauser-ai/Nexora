<?php
declare(strict_types=1);

require_once __DIR__ . '/common.php';

if (($_SERVER['REQUEST_METHOD'] ?? 'GET') !== 'POST') {
    chat_error('Metodo non supportato.', 405);
}

$payload = chat_request_json();
$userId = chat_user_id($payload);
$groupId = trim((string)($payload['groupId'] ?? ''));
if ($groupId === '') {
    chat_error('Gruppo non valido.', 422);
}

$pdo = chat_pdo();
$stmt = $pdo->prepare(
    'UPDATE chat_group_members
     SET last_read_at = NOW()
     WHERE group_id = :groupId AND user_id = :userId'
);
$stmt->execute(['groupId' => $groupId, 'userId' => $userId]);

chat_ok(['ok' => true]);
