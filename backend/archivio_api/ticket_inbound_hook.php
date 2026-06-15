<?php
declare(strict_types=1);

require_once __DIR__ . '/common.php';

$inboundRoot = __DIR__ . '/../inbound_mail';
if (!is_dir($inboundRoot)) {
    @mkdir($inboundRoot, 0775, true);
}
$queueFile = $inboundRoot . '/queue.jsonl';

$envKey = trim((string)getenv('MBW_TICKET_HOOK_KEY'));
$headerKey = trim((string)($_SERVER['HTTP_X_WEBHOOK_KEY'] ?? ''));

$payload = request_json();
$key = trim((string)($payload['key'] ?? $headerKey));

if ($envKey !== '' && $key !== $envKey) {
    json_error('Chiave webhook non valida.', 401);
}

$from = trim((string)($payload['from'] ?? $payload['sender'] ?? $payload['email'] ?? ''));
$fromName = trim((string)($payload['fromName'] ?? $payload['senderName'] ?? ''));
$subject = trim((string)($payload['subject'] ?? ''));
$body = trim((string)($payload['body'] ?? $payload['text'] ?? $payload['plain'] ?? $payload['textBody'] ?? ''));
$receivedAtRaw = trim((string)($payload['receivedAt'] ?? $payload['date'] ?? ''));

if ($from === '' || $subject === '' || $body === '') {
    json_error('Parametri mancanti: from, subject, body.', 422);
}

if (!filter_var($from, FILTER_VALIDATE_EMAIL)) {
    json_error('Email mittente non valida.', 422);
}

$receivedAt = null;
if ($receivedAtRaw !== '') {
    $ts = strtotime($receivedAtRaw);
    if ($ts !== false) {
        $receivedAt = gmdate('c', $ts);
    }
}
if ($receivedAt === null) {
    $receivedAt = gmdate('c');
}

$record = [
    'id' => 'in-' . bin2hex(random_bytes(8)),
    'from' => strtolower($from),
    'fromName' => $fromName,
    'subject' => $subject,
    'body' => $body,
    'receivedAt' => $receivedAt,
    'queuedAt' => gmdate('c'),
];

$line = json_encode($record, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES) . "\n";
$written = @file_put_contents($queueFile, $line, FILE_APPEND | LOCK_EX);
if ($written === false) {
    json_error('Impossibile accodare la mail inbound.', 500);
}

json_ok([
    'queued' => true,
    'id' => $record['id'],
]);
