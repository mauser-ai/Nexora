<?php
declare(strict_types=1);

if (!empty($_GET['access_token']) && empty($_SERVER['HTTP_AUTHORIZATION'])) {
    $_SERVER['HTTP_AUTHORIZATION'] = 'Bearer ' . (string)$_GET['access_token'];
}

require_once __DIR__ . '/common.php';

$userId = chat_user_id();
$redis = chat_redis();

header('Content-Type: text/event-stream; charset=utf-8');
header('Cache-Control: no-cache, no-transform');
header('Connection: keep-alive');
header('X-Accel-Buffering: no');

@ini_set('output_buffering', 'off');
@ini_set('zlib.output_compression', '0');
@ini_set('implicit_flush', '1');
@set_time_limit(0);

while (ob_get_level() > 0) {
    @ob_end_flush();
}
ob_implicit_flush(true);

function stream_event(string $event, array $payload): void
{
    echo "event: {$event}\n";
    echo 'data: ' . json_encode(
        $payload,
        JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES
    ) . "\n\n";
    @flush();
}

stream_event('connected', [
    'type' => 'connected',
    'userId' => $userId,
    'connectedAt' => gmdate(DATE_ATOM),
]);

if (!$redis instanceof Redis) {
    stream_event('error', [
        'type' => 'redis_unavailable',
        'message' => 'Redis non disponibile per lo stream chat.',
    ]);
    exit;
}

$queueKey = "chat:queue:user:{$userId}";

while (!connection_aborted()) {
    try {
        $item = $redis->brPop([$queueKey], 15);
        if (is_array($item) && isset($item[1]) && $item[1] !== '') {
            $decoded = json_decode((string)$item[1], true);
            if (is_array($decoded)) {
                stream_event('chat', $decoded);
                continue;
            }
        }
        echo ": keepalive\n\n";
        @flush();
    } catch (Throwable $e) {
        stream_event('error', [
            'type' => 'stream_error',
            'message' => $e->getMessage(),
        ]);
        break;
    }
}
