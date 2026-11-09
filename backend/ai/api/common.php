<?php
declare(strict_types=1);

header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Headers: Content-Type, X-Nexora-User-Id');
header('Access-Control-Allow-Methods: POST, OPTIONS');

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(204);
    exit;
}

function ai_config(): array
{
    static $config = null;
    if ($config !== null) {
        return $config;
    }
    $local = __DIR__ . '/config.local.php';
    $example = __DIR__ . '/config.local.php.example';
    $config = is_file($local) ? require $local : require $example;
    return $config;
}

function ai_config_value(string $key): string
{
    $config = ai_config();
    $value = trim((string)($config[$key] ?? ''));
    if ($value === '' || str_starts_with($value, 'INSERISCI_')) {
        json_ai_error("Configurazione AI mancante: {$key}.", 500);
    }
    return $value;
}

function json_ai_ok(array $payload): void
{
    http_response_code(200);
    echo json_encode($payload, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
    exit;
}

function json_ai_error(string $message, int $status = 400): void
{
    http_response_code($status);
    echo json_encode(['error' => $message], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
    exit;
}

function request_json_ai(): array
{
    $raw = file_get_contents('php://input');
    if ($raw === false || trim($raw) === '') {
        return [];
    }
    $decoded = json_decode($raw, true);
    return is_array($decoded) ? $decoded : [];
}

function anthropic_request(array $body): array
{
    $apiKey = ai_config_value('anthropic_api_key');
    $encoded = json_encode($body, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);

    $curl = curl_init('https://api.anthropic.com/v1/messages');
    curl_setopt_array($curl, [
        CURLOPT_RETURNTRANSFER => true,
        CURLOPT_POST           => true,
        CURLOPT_POSTFIELDS     => $encoded,
        CURLOPT_TIMEOUT        => 90,
        CURLOPT_HTTPHEADER     => [
            'x-api-key: ' . $apiKey,
            'anthropic-version: 2023-06-01',
            'anthropic-beta: prompt-caching-2024-07-31',
            'content-type: application/json',
        ],
    ]);

    $response = curl_exec($curl);
    $status = (int)curl_getinfo($curl, CURLINFO_RESPONSE_CODE);
    $error = curl_error($curl);
    curl_close($curl);

    if ($response === false) {
        json_ai_error('Errore connessione Anthropic: ' . $error, 502);
    }

    $decoded = json_decode((string)$response, true);
    if (!is_array($decoded)) {
        json_ai_error('Risposta Anthropic non valida.', 502);
    }
    if ($status >= 400) {
        $msg = (string)($decoded['error']['message'] ?? 'Errore API Anthropic.');
        json_ai_error($msg, 502);
    }
    return $decoded;
}
