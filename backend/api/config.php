<?php
declare(strict_types=1);

$localConfig = __DIR__ . '/config.local.php';
if (is_file($localConfig)) {
    require_once $localConfig;
}

function nexora_env(string $key, string $fallback = ''): string
{
    $value = getenv($key);
    return $value === false ? $fallback : $value;
}

foreach ([
    'DB_HOST' => nexora_env('DB_HOST', 'localhost'),
    'DB_PORT' => nexora_env('DB_PORT', '3306'),
    'DB_NAME' => nexora_env('DB_NAME'),
    'DB_USER' => nexora_env('DB_USER'),
    'DB_PASS' => nexora_env('DB_PASS'),
    'DB_CHARSET' => nexora_env('DB_CHARSET', 'utf8mb4'),
    'JWT_ACCESS_SECRET' => nexora_env('JWT_ACCESS_SECRET'),
    'JWT_REFRESH_SECRET' => nexora_env('JWT_REFRESH_SECRET'),
    'JWT_ACCESS_TTL' => nexora_env('JWT_ACCESS_TTL', '3600'),
    'JWT_REFRESH_TTL' => nexora_env('JWT_REFRESH_TTL', '2592000'),
    'FIREBASE_PROJECT_ID' => nexora_env('FIREBASE_PROJECT_ID', 'gussoni-d3153'),
    'ALLOWED_ORIGINS' => [
        'https://nexora.sviluppo.host',
        'http://localhost:3000',
        'http://localhost:5000',
    ],
    'APP_ENV' => nexora_env('APP_ENV', 'production'),
    'APP_DEBUG' => nexora_env('APP_DEBUG', 'false') === 'true',
] as $name => $value) {
    if (!defined($name)) {
        define($name, $value);
    }
}
