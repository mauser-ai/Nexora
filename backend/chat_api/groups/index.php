<?php
declare(strict_types=1);

require_once __DIR__ . '/../common.php';

$pdo = chat_pdo();
$method = $_SERVER['REQUEST_METHOD'] ?? 'GET';

if ($method === 'GET') {
    try {
        $userId = chat_user_id();
        $stmt = $pdo->prepare(
            'SELECT g.id, g.name, g.description, g.created_at, gm.last_read_at
             FROM chat_groups g
             INNER JOIN chat_group_members gm
               ON gm.group_id = g.id
             WHERE gm.user_id = :userId
             ORDER BY g.created_at DESC'
        );
        $stmt->execute(['userId' => $userId]);
        $groups = [];
        foreach ($stmt->fetchAll() as $row) {
            $lastMessageStmt = $pdo->prepare(
                'SELECT body, created_at
                 FROM chat_messages
                 WHERE group_id = :groupId
                 ORDER BY created_at DESC
                 LIMIT 1'
            );
            $lastMessageStmt->execute(['groupId' => $row['id']]);
            $lastMessage = $lastMessageStmt->fetch() ?: null;

            $lastReadAt = $row['last_read_at'] ?? null;
            if ($lastReadAt === null || $lastReadAt === '') {
                $unreadStmt = $pdo->prepare(
                    'SELECT COUNT(*)
                     FROM chat_messages
                     WHERE group_id = :groupId
                       AND user_id <> :userId'
                );
                $unreadStmt->execute([
                    'groupId' => $row['id'],
                    'userId' => $userId,
                ]);
            } else {
                $unreadStmt = $pdo->prepare(
                    'SELECT COUNT(*)
                     FROM chat_messages
                     WHERE group_id = :groupId
                       AND user_id <> :userId
                       AND created_at > :lastReadAt'
                );
                $unreadStmt->execute([
                    'groupId' => $row['id'],
                    'userId' => $userId,
                    'lastReadAt' => $lastReadAt,
                ]);
            }

            $row['last_message_body'] = $lastMessage['body'] ?? '';
            $row['last_message_at'] = $lastMessage['created_at'] ?? null;
            $row['unread_count'] = (int)$unreadStmt->fetchColumn();
            $groups[] = chat_group_row($pdo, $row, $userId);
        }
        chat_ok(['groups' => $groups]);
    } catch (Throwable $e) {
        chat_fail('Caricamento gruppi fallito', $e, 500);
    }
}

if ($method === 'POST') {
    $payload = chat_request_json();
    $userId = chat_user_id($payload);
    $name = trim((string)($payload['name'] ?? ''));
    $description = trim((string)($payload['description'] ?? ''));
    $members = $payload['members'] ?? [];

    if ($name === '') {
        chat_error('Nome gruppo obbligatorio.', 422);
    }
    if (!is_array($members) || count($members) === 0) {
        chat_error('Seleziona almeno un membro.', 422);
    }

    $groupId = function_exists('uuid_create')
        ? uuid_create(UUID_TYPE_RANDOM)
        : sprintf(
            '%04x%04x-%04x-%04x-%04x-%04x%04x%04x',
            mt_rand(0, 0xffff), mt_rand(0, 0xffff),
            mt_rand(0, 0xffff),
            mt_rand(0, 0x0fff) | 0x4000,
            mt_rand(0, 0x3fff) | 0x8000,
            mt_rand(0, 0xffff), mt_rand(0, 0xffff), mt_rand(0, 0xffff)
        );

    $normalizedMembers = [];
    foreach ($members as $member) {
        if (!is_array($member)) {
            continue;
        }
        $memberId = trim((string)($member['userId'] ?? ''));
        if ($memberId === '') {
            continue;
        }
        $normalizedMembers[$memberId] = [
            'userId' => $memberId,
            'displayName' => trim((string)($member['displayName'] ?? $memberId)),
            'email' => trim((string)($member['email'] ?? '')),
            'role' => trim((string)($member['role'] ?? '')),
        ];
    }

    if (!isset($normalizedMembers[$userId])) {
        $normalizedMembers[$userId] = [
            'userId' => $userId,
            'displayName' => trim((string)($payload['authorName'] ?? $userId)),
            'email' => '',
            'role' => '',
        ];
    }

    $pdo->beginTransaction();
    try {
        $insertGroup = $pdo->prepare(
            'INSERT INTO chat_groups (id, name, description, created_by)
             VALUES (:id, :name, :description, :createdBy)'
        );
        $insertGroup->execute([
            'id' => $groupId,
            'name' => $name,
            'description' => $description,
            'createdBy' => $userId,
        ]);

        $insertMember = $pdo->prepare(
            'INSERT INTO chat_group_members
             (group_id, user_id, display_name, email, role)
             VALUES (:groupId, :userId, :displayName, :email, :role)'
        );
        foreach ($normalizedMembers as $member) {
            $insertMember->execute([
                'groupId' => $groupId,
                'userId' => $member['userId'],
                'displayName' => $member['displayName'],
                'email' => $member['email'],
                'role' => $member['role'],
            ]);
            chat_publish_event($member['userId'], [
                'type' => 'group_created',
                'groupId' => $groupId,
            ]);
        }
        $pdo->commit();
    } catch (Throwable $e) {
        $pdo->rollBack();
        chat_fail('Impossibile creare il gruppo chat', $e, 500);
    }

    $row = [
        'id' => $groupId,
        'name' => $name,
        'description' => $description,
        'created_at' => gmdate(DATE_ATOM),
        'last_message_body' => '',
        'last_message_at' => null,
        'unread_count' => 0,
    ];
    chat_ok(['group' => chat_group_row($pdo, $row, $userId)]);
}

chat_error('Metodo non supportato.', 405);
