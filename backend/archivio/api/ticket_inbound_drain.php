<?php
declare(strict_types=1);

require_once __DIR__ . '/common.php';

$inboundRoot = __DIR__ . '/../inbound_mail';
if (!is_dir($inboundRoot)) {
    @mkdir($inboundRoot, 0775, true);
}
$queueFile = $inboundRoot . '/queue.jsonl';

$envKey = trim((string)getenv('MBW_TICKET_HOOK_KEY'));
$queryKey = trim((string)($_GET['key'] ?? ''));
$headerKey = trim((string)($_SERVER['HTTP_X_WEBHOOK_KEY'] ?? ''));
$key = $queryKey !== '' ? $queryKey : $headerKey;

if ($envKey !== '' && $key !== $envKey) {
    json_error('Chiave inbound non valida.', 401);
}

if (!is_file($queueFile)) {
    json_ok(['items' => []]);
}

$fp = @fopen($queueFile, 'c+');
if ($fp === false) {
    json_error('Impossibile leggere la coda inbound.', 500);
}

if (!flock($fp, LOCK_EX)) {
    fclose($fp);
    json_error('Impossibile bloccare la coda inbound.', 500);
}

$contents = stream_get_contents($fp);
if ($contents === false) {
    $contents = '';
}

ftruncate($fp, 0);
rewind($fp);
flock($fp, LOCK_UN);
fclose($fp);

$lines = preg_split('/\r\n|\r|\n/', $contents ?? '') ?: [];
$items = [];

foreach ($lines as $line) {
    $line = trim($line);
    if ($line === '') {
        continue;
    }
    $decoded = json_decode($line, true);
    if (!is_array($decoded)) {
        continue;
    }
    $items[] = [
        'id' => (string)($decoded['id'] ?? ''),
        'from' => trim((string)($decoded['from'] ?? '')),
        'fromName' => trim((string)($decoded['fromName'] ?? '')),
        'subject' => trim((string)($decoded['subject'] ?? '')),
        'body' => trim((string)($decoded['body'] ?? '')),
        'receivedAt' => trim((string)($decoded['receivedAt'] ?? gmdate('c'))),
        'messageId' => trim((string)($decoded['messageId'] ?? '')),
        'inReplyTo' => trim((string)($decoded['inReplyTo'] ?? '')),
        'references' => trim((string)($decoded['references'] ?? '')),
        'conversationKey' => trim((string)($decoded['conversationKey'] ?? '')),
        'attachments' => is_array($decoded['attachments'] ?? null) ? $decoded['attachments'] : [],
    ];
}

json_ok([
    'items' => $items,
    'count' => count($items),
]);
