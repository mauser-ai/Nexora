<?php
declare(strict_types=1);

require_once dirname(__DIR__) . '/bootstrap.php';

function stripe_config(bool $strict = true): array
{
    static $config = null;
    if (is_array($config)) {
        return $config;
    }

    $local = __DIR__ . '/config.local.php';
    $example = __DIR__ . '/config.local.php.example';
    $file = is_file($local) ? $local : (is_file($example) ? $example : null);

    if ($file === null) {
        if ($strict) {
            json_error('Config Stripe non trovata.', 500);
        }
        return [];
    }

    $loaded = require $file;
    if (!is_array($loaded)) {
        if ($strict) {
            json_error('Config Stripe non valida.', 500);
        }
        return [];
    }

    $config = $loaded;
    return $config;
}

function stripe_is_ready(): bool
{
    $config = stripe_config(false);
    $secret = trim((string)($config['secret_key'] ?? ''));
    $publishable = trim((string)($config['publishable_key'] ?? ''));
    if ($secret === '' || $publishable === '') {
        return false;
    }
    if (stripos($secret, 'xxx') !== false || stripos($publishable, 'xxx') !== false) {
        return false;
    }
    return strpos($secret, 'sk_') === 0 && strpos($publishable, 'pk_') === 0;
}

function stripe_publishable_key(): string
{
    $config = stripe_config();
    $key = trim((string)($config['publishable_key'] ?? ''));
    if ($key === '') {
        json_error('Publishable key Stripe non configurata.', 500);
    }
    return $key;
}

function stripe_platform_url(): string
{
    $config = stripe_config(false);
    $configured = trim((string)($config['platform_url'] ?? ''));
    if ($configured !== '') {
        return rtrim($configured, '/');
    }

    $scheme = (!empty($_SERVER['HTTPS']) && $_SERVER['HTTPS'] !== 'off')
        ? 'https'
        : 'http';
    $host = trim((string)($_SERVER['HTTP_HOST'] ?? ''));
    if ($host === '') {
        return 'https://nexora.sviluppo.host';
    }
    return $scheme . '://' . $host;
}

function stripe_api_request(
    string $method,
    string $path,
    array $params = [],
    array $options = []
): array
{
    $config = stripe_config();
    $secretKey = trim((string)($config['secret_key'] ?? ''));
    if ($secretKey === '') {
        json_error('Secret key Stripe non configurata.', 500);
    }

    $url = 'https://api.stripe.com' . $path;
    $headers = [
        'Authorization: Bearer ' . $secretKey,
        'Stripe-Version: 2025-06-30.basil',
    ];
    $stripeAccount = trim((string)($options['stripe_account'] ?? ''));
    if ($stripeAccount !== '') {
        $headers[] = 'Stripe-Account: ' . $stripeAccount;
    }
    if (!empty($options['headers']) && is_array($options['headers'])) {
        foreach ($options['headers'] as $header) {
            if (is_string($header) && trim($header) !== '') {
                $headers[] = $header;
            }
        }
    }

    $curl = curl_init();
    curl_setopt($curl, CURLOPT_RETURNTRANSFER, true);
    curl_setopt($curl, CURLOPT_TIMEOUT, 45);

    if ($method === 'GET') {
        if ($params !== []) {
            $url .= '?' . http_build_query($params);
        }
    } else {
        $headers[] = 'Content-Type: application/x-www-form-urlencoded';
        curl_setopt($curl, CURLOPT_POSTFIELDS, http_build_query($params));
    }

    curl_setopt($curl, CURLOPT_URL, $url);
    curl_setopt($curl, CURLOPT_CUSTOMREQUEST, $method);
    curl_setopt($curl, CURLOPT_HTTPHEADER, $headers);

    $response = curl_exec($curl);
    $status = (int)curl_getinfo($curl, CURLINFO_RESPONSE_CODE);
    $error = curl_error($curl);
    curl_close($curl);

    if ($response === false) {
        json_error('Errore richiesta Stripe: ' . $error, 502);
    }

    $decoded = json_decode((string)$response, true);
    if ($status < 200 || $status >= 300) {
        $message = is_array($decoded)
            ? (string)($decoded['error']['message'] ?? 'Errore Stripe sconosciuto.')
            : 'Errore Stripe sconosciuto.';
        json_error('Stripe: ' . $message, 502);
    }

    return is_array($decoded) ? $decoded : [];
}
