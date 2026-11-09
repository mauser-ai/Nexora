<?php
declare(strict_types=1);

require_once __DIR__ . '/common.php';

$payload = request_json();
$to = trim((string)($payload['to'] ?? ''));
$subject = trim((string)($payload['subject'] ?? ''));
$body = trim((string)($payload['body'] ?? ''));
$signatureHtml = trim((string)($payload['signatureHtml'] ?? ''));
$attachments = $payload['attachments'] ?? [];
$attachmentsBase64 = $payload['attachmentsBase64'] ?? [];
$fromEmailOverride = trim((string)($payload['fromEmail'] ?? ''));
$fromNameOverride = trim((string)($payload['fromName'] ?? ''));

if ($to === '' || $subject === '' || $body === '' || $fromEmailOverride === '') {
    json_error('Parametri email mancanti (to, subject, body, fromEmail).', 422);
}

if (!filter_var($to, FILTER_VALIDATE_EMAIL)) {
    json_error('Email destinatario non valida.', 422);
}

if (!filter_var($fromEmailOverride, FILTER_VALIDATE_EMAIL)) {
    json_error('Email mittente non valida. Configurala nelle impostazioni.', 422);
}

$fromEmail = $fromEmailOverride;
$fromName = $fromNameOverride !== '' ? $fromNameOverride : $fromEmail;

$headers = [];
$encodedFromName = mb_encode_mimeheader($fromName, 'UTF-8', 'B');
$headers[] = 'From: ' . $encodedFromName . ' <' . $fromEmail . '>';
$headers[] = 'Reply-To: ' . $fromEmail;
$headers[] = 'MIME-Version: 1.0';

$files = [];
if (is_array($attachments)) {
    foreach ($attachments as $item) {
        $relativePath = normalize_relative_path((string)$item);
        if ($relativePath === '') {
            continue;
        }
        $full = full_path($archiveRoot, $relativePath);
        if (!is_file($full)) {
            continue;
        }
        $files[] = [
            'name' => basename($full),
            'path' => $full,
        ];
    }
}

// Allegati inviati direttamente dal client (es. PDF preventivo generato al volo).
$inlineFiles = [];
if (is_array($attachmentsBase64)) {
    foreach ($attachmentsBase64 as $item) {
        if (!is_array($item)) {
            continue;
        }
        $name = preg_replace('/[^a-zA-Z0-9._ -]/', '', (string)($item['filename'] ?? ''));
        $b64 = (string)($item['base64'] ?? '');
        $mime = (string)($item['mimeType'] ?? 'application/octet-stream');
        if ($name === '' || $b64 === '') {
            continue;
        }
        $bytes = base64_decode($b64, true);
        if ($bytes === false || strlen($bytes) > 15 * 1024 * 1024) {
            continue;
        }
        $inlineFiles[] = [
            'name' => $name,
            'mime' => $mime,
            'bytes' => $bytes,
        ];
    }
}

$plainEscapedBody = nl2br(htmlspecialchars($body, ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8'));
$finalHtmlBody = $plainEscapedBody;
if ($signatureHtml !== '') {
    $finalHtmlBody .= "<br><br>" . $signatureHtml;
}

$messageBody = '';
if (count($files) === 0 && count($inlineFiles) === 0) {
    $headers[] = 'Content-Type: text/html; charset=UTF-8';
    $messageBody = $finalHtmlBody;
} else {
    $boundary = 'mbw-' . bin2hex(random_bytes(12));
    $headers[] = 'Content-Type: multipart/mixed; boundary="' . $boundary . '"';

    $parts = [];
    $parts[] = '--' . $boundary;
    $parts[] = 'Content-Type: text/html; charset=UTF-8';
    $parts[] = 'Content-Transfer-Encoding: quoted-printable';
    $parts[] = '';
    $parts[] = quoted_printable_encode($finalHtmlBody);

    foreach ($files as $file) {
        $bytes = @file_get_contents($file['path']);
        if ($bytes === false) {
            continue;
        }
        $encoded = chunk_split(base64_encode($bytes));
        $parts[] = '--' . $boundary;
        $parts[] = 'Content-Type: application/octet-stream; name="' . $file['name'] . '"';
        $parts[] = 'Content-Transfer-Encoding: base64';
        $parts[] = 'Content-Disposition: attachment; filename="' . $file['name'] . '"';
        $parts[] = '';
        $parts[] = $encoded;
    }

    foreach ($inlineFiles as $file) {
        $encoded = chunk_split(base64_encode($file['bytes']));
        $parts[] = '--' . $boundary;
        $parts[] = 'Content-Type: ' . $file['mime'] . '; name="' . $file['name'] . '"';
        $parts[] = 'Content-Transfer-Encoding: base64';
        $parts[] = 'Content-Disposition: attachment; filename="' . $file['name'] . '"';
        $parts[] = '';
        $parts[] = $encoded;
    }

    $parts[] = '--' . $boundary . '--';
    $parts[] = '';
    $messageBody = implode("\r\n", $parts);
}

$ok = @mail($to, $subject, $messageBody, implode("\r\n", $headers));
if (!$ok) {
    json_error('Invio email fallito lato server.', 500);
}

json_ok([
    'sent' => true,
    'to' => $to,
    'attachmentsCount' => count($files) + count($inlineFiles),
]);
