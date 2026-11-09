<?php
declare(strict_types=1);

require_once dirname(__DIR__) . '/bootstrap.php';

function chat_ok(array $payload = [], int $code = 200): void
{
    json_ok($payload, $code);
}

function chat_error(string $message, int $status = 400): void
{
    json_error($message, $status);
}

function chat_fail(string $message, Throwable $e, int $status = 500): void
{
    if (defined('APP_DEBUG') && APP_DEBUG) {
        json_error($message . ': ' . $e->getMessage(), $status);
    }
    json_error($message . ': ' . $e->getMessage(), $status);
}

function chat_request_json(): array
{
    return request_body();
}

function chat_user_id(array $payload = []): string
{
    return require_auth();
}

function chat_pdo(): PDO
{
    return db();
}

function chat_redis(): ?Redis
{
    static $redisChecked = false;
    static $redis = null;
    if ($redisChecked) {
        return $redis;
    }
    $redisChecked = true;

    if (!class_exists('Redis')) {
        return null;
    }

    $host = $_ENV['CHAT_REDIS_HOST'] ?? $_SERVER['CHAT_REDIS_HOST'] ?? getenv('CHAT_REDIS_HOST');
    if (!$host) {
        return null;
    }

    try {
        $client = new Redis();
        $port = (int)($_ENV['CHAT_REDIS_PORT'] ?? $_SERVER['CHAT_REDIS_PORT'] ?? getenv('CHAT_REDIS_PORT') ?: 6379);
        $timeout = (float)($_ENV['CHAT_REDIS_TIMEOUT'] ?? $_SERVER['CHAT_REDIS_TIMEOUT'] ?? getenv('CHAT_REDIS_TIMEOUT') ?: 1.5);
        $client->connect((string)$host, $port, $timeout);
        $password = $_ENV['CHAT_REDIS_PASSWORD'] ?? $_SERVER['CHAT_REDIS_PASSWORD'] ?? getenv('CHAT_REDIS_PASSWORD');
        if (is_string($password) && $password !== '') {
            $client->auth($password);
        }
        $dbIndex = (int)($_ENV['CHAT_REDIS_DB'] ?? $_SERVER['CHAT_REDIS_DB'] ?? getenv('CHAT_REDIS_DB') ?: 0);
        if ($dbIndex > 0) {
            $client->select($dbIndex);
        }
        $redis = $client;
        return $redis;
    } catch (Throwable $e) {
        return null;
    }
}

function chat_publish_event(string $userId, array $payload): void
{
    $redis = chat_redis();
    if (!$redis instanceof Redis) {
        return;
    }
    try {
        $encoded = json_encode(
            $payload,
            JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES
        );
        $queueKey = "chat:queue:user:{$userId}";
        $redis->lPush($queueKey, $encoded);
        $redis->lTrim($queueKey, 0, 199);
        $redis->expire($queueKey, 3600);
        $redis->publish(
            "chat:user:{$userId}",
            $encoded
        );
    } catch (Throwable $e) {
        // La chat continua a funzionare su SQL anche senza publish realtime.
    }
}

function chat_now_iso(?string $value): ?string
{
    if ($value === null || $value === '' || $value === '0000-00-00 00:00:00') {
        return null;
    }
    return str_replace(' ', 'T', $value) . 'Z';
}

function chat_uuid(): string
{
    return uuid4();
}

function chat_group_row(PDO $pdo, array $groupRow, string $userId): array
{
    $membersStmt = $pdo->prepare(
        'SELECT gm.user_id, gm.display_name, gm.email, gm.role
         FROM chat_group_members gm
         WHERE gm.group_id = :groupId
         ORDER BY gm.display_name ASC'
    );
    $membersStmt->execute(['groupId' => $groupRow['id']]);
    $members = [];
    foreach ($membersStmt->fetchAll() as $member) {
        $members[] = [
            'userId' => (string)$member['user_id'],
            'displayName' => (string)$member['display_name'],
            'email' => (string)$member['email'],
            'role' => (string)($member['role'] ?? ''),
            'isOnline' => false,
        ];
    }

    return [
        'id' => (string)$groupRow['id'],
        'name' => (string)$groupRow['name'],
        'description' => (string)($groupRow['description'] ?? ''),
        'createdAt' => chat_now_iso((string)($groupRow['created_at'] ?? '')) ?? gmdate(DATE_ATOM),
        'lastMessageSnippet' => (string)($groupRow['last_message_body'] ?? ''),
        'lastMessageAt' => chat_now_iso((string)($groupRow['last_message_at'] ?? '')),
        'unreadCount' => (int)($groupRow['unread_count'] ?? 0),
        'members' => $members,
    ];
}
