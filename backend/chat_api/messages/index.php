<?php
declare(strict_types=1);

require_once __DIR__ . '/../common.php';

$pdo = chat_pdo();
$method = $_SERVER['REQUEST_METHOD'] ?? 'GET';

if ($method === 'GET') {
    $userId = chat_user_id();
    $groupId = trim((string)($_GET['groupId'] ?? ''));
    if ($groupId === '') {
        chat_error('Gruppo non valido.', 422);
    }

    $membership = $pdo->prepare(
        'SELECT COUNT(*) FROM chat_group_members WHERE group_id = :groupId AND user_id = :userId'
    );
    $membership->execute(['groupId' => $groupId, 'userId' => $userId]);
    if ((int)$membership->fetchColumn() === 0) {
        chat_error('Accesso al gruppo negato.', 403);
    }

    $stmt = $pdo->prepare(
        'SELECT id, group_id, user_id, author_name, body, created_at
         FROM chat_messages
         WHERE group_id = :groupId
         ORDER BY created_at ASC
         LIMIT 250'
    );
    $stmt->execute(['groupId' => $groupId]);
    $messages = [];
    foreach ($stmt->fetchAll() as $row) {
        $messages[] = [
            'id' => (string)$row['id'],
            'groupId' => (string)$row['group_id'],
            'userId' => (string)$row['user_id'],
            'authorName' => (string)$row['author_name'],
            'body' => (string)$row['body'],
            'createdAt' => chat_now_iso((string)$row['created_at']) ?? gmdate(DATE_ATOM),
        ];
    }
    chat_ok(['messages' => $messages]);
}

if ($method === 'POST') {
    $payload = chat_request_json();
    $userId = chat_user_id($payload);
    $groupId = trim((string)($payload['groupId'] ?? ''));
    $body = trim((string)($payload['body'] ?? ''));
    if ($groupId === '' || $body === '') {
        chat_error('Gruppo e messaggio sono obbligatori.', 422);
    }

    $memberStmt = $pdo->prepare(
        'SELECT display_name FROM chat_group_members WHERE group_id = :groupId AND user_id = :userId LIMIT 1'
    );
    $memberStmt->execute(['groupId' => $groupId, 'userId' => $userId]);
    $member = $memberStmt->fetch();
    if (!$member) {
        chat_error('Accesso al gruppo negato.', 403);
    }

    $messageId = function_exists('uuid_create')
        ? uuid_create(UUID_TYPE_RANDOM)
        : sprintf(
            '%04x%04x-%04x-%04x-%04x-%04x%04x%04x',
            mt_rand(0, 0xffff), mt_rand(0, 0xffff),
            mt_rand(0, 0xffff),
            mt_rand(0, 0x0fff) | 0x4000,
            mt_rand(0, 0x3fff) | 0x8000,
            mt_rand(0, 0xffff), mt_rand(0, 0xffff), mt_rand(0, 0xffff)
        );

    $stmt = $pdo->prepare(
        'INSERT INTO chat_messages (id, group_id, user_id, author_name, body)
         VALUES (:id, :groupId, :userId, :authorName, :body)'
    );
    $stmt->execute([
        'id' => $messageId,
        'groupId' => $groupId,
        'userId' => $userId,
        'authorName' => (string)$member['display_name'],
        'body' => $body,
    ]);

    $touchRead = $pdo->prepare(
        'UPDATE chat_group_members
         SET last_read_message_id = :messageId, last_read_at = NOW()
         WHERE group_id = :groupId AND user_id = :userId'
    );
    $touchRead->execute([
        'messageId' => $messageId,
        'groupId' => $groupId,
        'userId' => $userId,
    ]);

    $membersStmt = $pdo->prepare(
        'SELECT user_id FROM chat_group_members WHERE group_id = :groupId'
    );
    $membersStmt->execute(['groupId' => $groupId]);
    foreach ($membersStmt->fetchAll() as $groupMember) {
        $targetUserId = (string)$groupMember['user_id'];
        if ($targetUserId === $userId) {
            continue;
        }
        chat_publish_event($targetUserId, [
            'type' => 'message_created',
            'groupId' => $groupId,
            'messageId' => $messageId,
        ]);
    }

    chat_ok([
        'message' => [
            'id' => $messageId,
            'groupId' => $groupId,
            'userId' => $userId,
            'authorName' => (string)$member['display_name'],
            'body' => $body,
            'createdAt' => gmdate(DATE_ATOM),
        ],
    ]);
}

chat_error('Metodo non supportato.', 405);
