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

function normalize_subject_for_thread(string $subject): string
{
    $next = trim(mb_strtolower($subject));
    $next = preg_replace('/^(re|fw|fwd)\s*:\s*/iu', '', $next ?? '');
    $next = preg_replace('/\s+/u', ' ', $next ?? '');
    return trim((string)$next);
}

function parse_iso_date_or_now(?string $raw): string
{
    $raw = trim((string)$raw);
    if ($raw !== '') {
        $ts = strtotime($raw);
        if ($ts !== false) {
            return gmdate('c', $ts);
        }
    }
    return gmdate('c');
}

function extract_email_string($from): string
{
    if (is_array($from)) {
        $value = (string)($from['address'] ?? $from['email'] ?? '');
        return trim(strtolower($value));
    }
    return trim(strtolower((string)$from));
}

function extract_name_string($from): string
{
    if (is_array($from)) {
        return trim((string)($from['name'] ?? ''));
    }
    return '';
}

function extract_body_text(array $item): string
{
    $plain = trim((string)($item['text'] ?? $item['body'] ?? ''));
    if ($plain !== '') {
        return $plain;
    }
    $html = trim((string)($item['html'] ?? ''));
    if ($html === '') {
        return '';
    }
    $stripped = trim((string)preg_replace('/\s+/u', ' ', strip_tags($html)));
    return $stripped;
}

function normalize_make_attachment(array $raw): ?array
{
    $fileName = trim((string)($raw['file_name'] ?? $raw['filename'] ?? $raw['name'] ?? ''));
    $mimeType = trim((string)($raw['mime_type'] ?? $raw['content_type'] ?? 'application/octet-stream'));
    $contentId = trim((string)($raw['content_id'] ?? ''));
    $dataRaw = $raw['data'] ?? '';
    if (is_array($dataRaw)) {
        $candidate = $dataRaw['base64'] ?? $dataRaw['data'] ?? $dataRaw['content'] ?? '';
        if (is_string($candidate)) {
            $dataRaw = $candidate;
        } else {
            $dataRaw = '';
        }
    }
    $data = trim((string)$dataRaw);
    if ($fileName === '' || $data === '') {
        return null;
    }

    $base64 = '';
    if (preg_match('/^data:[^;]+;base64,(.+)$/is', $data, $m)) {
        $candidate = preg_replace('/\\s+/', '', (string)($m[1] ?? ''));
        $decoded = base64_decode($candidate, true);
        if ($decoded !== false) {
            $base64 = $candidate;
        }
    } elseif (preg_match('/^IMTBuffer\\([^)]*\\):\\s*([0-9a-fA-F]+)$/', $data, $m)) {
        $hex = $m[1] ?? '';
        if ($hex !== '') {
            $bin = @hex2bin($hex);
            if ($bin !== false) {
                $base64 = base64_encode($bin);
            }
        }
    } else {
        $candidate = preg_replace('/\\s+/', '', $data);
        $decoded = base64_decode($candidate, true);
        if ($decoded !== false) {
            $base64 = $candidate;
        }
    }

    if ($base64 === '') {
        return null;
    }

    return [
        'fileName' => $fileName,
        'mimeType' => $mimeType === '' ? 'application/octet-stream' : $mimeType,
        'contentId' => $contentId,
        'base64' => $base64,
    ];
}

$items = [];
if (array_is_list($payload)) {
    $items = $payload;
} elseif (isset($payload['items']) && is_array($payload['items'])) {
    $items = $payload['items'];
} elseif (isset($payload[0]) && is_array($payload[0])) {
    $items = $payload;
} else {
    $items = [$payload];
}

$records = [];
foreach ($items as $item) {
    if (!is_array($item)) {
        continue;
    }

    $from = extract_email_string($item['from'] ?? '');
    $fromName = extract_name_string($item['from'] ?? []);
    $subject = trim((string)($item['subject'] ?? ''));
    $body = extract_body_text($item);

    if ($from === '' || $subject === '' || $body === '') {
        continue;
    }
    if (!filter_var($from, FILTER_VALIDATE_EMAIL)) {
        continue;
    }

    $receivedAt = parse_iso_date_or_now((string)($item['date'] ?? $item['receivedAt'] ?? ''));

    $messageId = '';
    $inReplyTo = '';
    $references = '';
    $headers = [];
    if (isset($item['headers'])) {
        if (is_array($item['headers'])) {
            $headers = $item['headers'];
        } else {
            $decodedHeaders = json_decode((string)$item['headers'], true);
            if (is_array($decodedHeaders)) {
                $headers = $decodedHeaders;
            }
        }
    }
    if (is_array($headers) && count($headers) > 0) {
        $messageId = trim((string)($headers['message-id'] ?? $headers['message_id'] ?? ''));
        $inReplyTo = trim((string)($headers['in-reply-to'] ?? $headers['in_reply_to'] ?? ''));
        $references = trim((string)($headers['references'] ?? ''));
    }

    $threadBase = normalize_subject_for_thread($subject);
    $conversationKey = sha1($from . '|' . $threadBase);
    $attachments = [];
    if (isset($item['attachments']) && is_array($item['attachments'])) {
        foreach ($item['attachments'] as $attachment) {
            if (!is_array($attachment)) {
                continue;
            }
            $normalizedAttachment = normalize_make_attachment($attachment);
            if ($normalizedAttachment !== null) {
                $attachments[] = $normalizedAttachment;
            }
        }
    }

    $records[] = [
        'id' => 'in-' . bin2hex(random_bytes(8)),
        'from' => $from,
        'fromName' => $fromName,
        'subject' => $subject,
        'body' => $body,
        'receivedAt' => $receivedAt,
        'messageId' => $messageId,
        'inReplyTo' => $inReplyTo,
        'references' => $references,
        'conversationKey' => $conversationKey,
        'attachments' => $attachments,
        'queuedAt' => gmdate('c'),
    ];
}

if (count($records) === 0) {
    json_ok(['queued' => 0]);
}

$lines = [];
foreach ($records as $record) {
    $lines[] = json_encode($record, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
}
$payloadLines = implode("\n", $lines) . "\n";

$written = @file_put_contents($queueFile, $payloadLines, FILE_APPEND | LOCK_EX);
if ($written === false) {
    json_error('Impossibile accodare i messaggi Make.', 500);
}

json_ok([
    'queued' => count($records),
]);
