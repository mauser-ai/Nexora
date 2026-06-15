<?php
declare(strict_types=1);

require_once dirname(__DIR__) . '/common.php';

const INTEGRATION_PROVIDER_GOOGLE = 'google_drive';
const GOOGLE_DRIVE_SCOPE = 'https://www.googleapis.com/auth/drive';

function integrations_config(): array
{
    static $config = null;
    if ($config !== null) {
        return $config;
    }

    $example = __DIR__ . '/config.local.php.example';
    $local = __DIR__ . '/config.local.php';
    $config = is_file($local) ? require $local : require $example;
    if (!is_array($config)) {
        json_error('Config integrazioni non valida.', 500);
    }
    return $config;
}

function integration_config_value(string $key): string
{
    $config = integrations_config();
    $value = trim((string)($config[$key] ?? ''));
    if (
        $value === '' ||
        str_starts_with($value, 'INSERISCI_') ||
        str_starts_with($value, 'CAMBIA_')
    ) {
        json_error("Config integrazioni incompleta: {$key}.", 500);
    }
    return $value;
}

function integration_user_id(): string
{
    $header = $_SERVER['HTTP_X_NEXORA_USER_ID'] ?? '';
    $query = $_GET['userId'] ?? '';
    $value = trim((string)($header ?: $query ?: 'default'));
    return preg_replace('/[^A-Za-z0-9_\-@.]/', '', $value) ?: 'default';
}

function integration_provider(): string
{
    $payload = request_json();
    $provider = (string)($_GET['provider'] ?? $payload['provider'] ?? '');
    if ($provider !== INTEGRATION_PROVIDER_GOOGLE) {
        json_error('Provider integrazione non supportato.', 422);
    }
    return $provider;
}

function integrations_pdo(): PDO
{
    static $pdo = null;
    if ($pdo instanceof PDO) {
        return $pdo;
    }

    $bootstrapErrors = [];
    $apiBootstrap = dirname(__DIR__, 3) . '/api/bootstrap.php';
    if (is_file($apiBootstrap)) {
        $apiConfig = integration_parse_api_bootstrap_config($apiBootstrap);
        if ($apiConfig !== null) {
            try {
                $pdo = new PDO(
                    $apiConfig['dsn'],
                    $apiConfig['user'],
                    $apiConfig['password'],
                    [
                        PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
                        PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
                    ]
                );
                integrations_ensure_schema($pdo);
                return $pdo;
            } catch (Throwable $e) {
                $bootstrapErrors[] = $apiBootstrap . ' config letta -> ' . $e->getMessage();
            }
        } else {
            $bootstrapErrors[] = $apiBootstrap . ' trovato, ma config DB non leggibile senza include';
        }
    }

    $config = integrations_config();
    $dsn = $config['pdo_dsn'] ?? null;
    $user = $config['pdo_user'] ?? null;
    $password = $config['pdo_password'] ?? null;

    if (!is_string($dsn) || $dsn === '') {
        $host = env_value('DB_HOST');
        $name = env_value('DB_NAME');
        if ($host !== '' && $name !== '') {
            $charset = env_value('DB_CHARSET') ?: 'utf8mb4';
            $dsn = "mysql:host={$host};dbname={$name};charset={$charset}";
            $user = env_value('DB_USER');
            $password = env_value('DB_PASS');
        }
    }

    if (!is_string($dsn) || $dsn === '') {
        $details = $bootstrapErrors ? ' Dettagli bootstrap: ' . implode(' | ', $bootstrapErrors) : '';
        json_error('Database integrazioni non configurato.' . $details, 500);
    }
    $pdo = new PDO(
        $dsn,
        (string)($user ?? ''),
        (string)($password ?? ''),
        [
            PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
            PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
        ]
    );
    integrations_ensure_schema($pdo);
    return $pdo;
}

function integration_parse_api_bootstrap_config(string $path): ?array
{
    $source = file_get_contents($path);
    if ($source === false) {
        return null;
    }
    $vars = [];
    foreach (['DB_HOST', 'DB_NAME', 'DB_USER', 'DB_PASS', 'DB_CHARSET'] as $name) {
        if (preg_match("/define\\(\\s*['\"]{$name}['\"]\\s*,\\s*['\"]([^'\"]*)['\"]\\s*\\)/", $source, $m)) {
            $vars[$name] = $m[1];
            continue;
        }
        if (preg_match("/const\\s+{$name}\\s*=\\s*['\"]([^'\"]*)['\"]\\s*;/", $source, $m)) {
            $vars[$name] = $m[1];
            continue;
        }
        if (preg_match("/\\\${$name}\\s*=\\s*['\"]([^'\"]*)['\"]\\s*;/", $source, $m)) {
            $vars[$name] = $m[1];
            continue;
        }

        $lowerName = strtolower($name);
        $shortName = strtolower(str_replace('DB_', '', $name));
        $patterns = [
            "/['\"]{$name}['\"]\\s*=>\\s*['\"]([^'\"]*)['\"]/",
            "/['\"]{$lowerName}['\"]\\s*=>\\s*['\"]([^'\"]*)['\"]/",
            "/['\"]{$shortName}['\"]\\s*=>\\s*['\"]([^'\"]*)['\"]/",
        ];
        foreach ($patterns as $pattern) {
            if (preg_match($pattern, $source, $m)) {
                $vars[$name] = $m[1];
                break;
            }
        }
    }
    if (empty($vars['DB_HOST']) || empty($vars['DB_NAME'])) {
        return null;
    }
    $charset = $vars['DB_CHARSET'] ?? 'utf8mb4';
    return [
        'dsn' => "mysql:host={$vars['DB_HOST']};dbname={$vars['DB_NAME']};charset={$charset}",
        'user' => $vars['DB_USER'] ?? '',
        'password' => $vars['DB_PASS'] ?? '',
    ];
}

function env_value(string $key): string
{
    $value = $_ENV[$key] ?? $_SERVER[$key] ?? getenv($key);
    return is_string($value) ? trim($value) : '';
}

function integrations_ensure_schema(PDO $pdo): void
{
    $sql = file_get_contents(__DIR__ . '/schema.sql');
    if ($sql === false) {
        json_error('Schema integrazioni non trovato.', 500);
    }
    $pdo->exec($sql);
}

function integration_key(): string
{
    $config = integrations_config();
    $key = (string)($config['token_encryption_key'] ?? '');
    if (strlen($key) < 32) {
        json_error('Chiave cifratura token non configurata.', 500);
    }
    return hash('sha256', $key, true);
}

function encrypt_token(?string $value): ?string
{
    if ($value === null || $value === '') {
        return null;
    }
    $iv = random_bytes(16);
    $cipher = openssl_encrypt($value, 'AES-256-CBC', integration_key(), OPENSSL_RAW_DATA, $iv);
    if ($cipher === false) {
        json_error('Errore cifratura token.', 500);
    }
    return base64_encode($iv . $cipher);
}

function decrypt_token(?string $value): ?string
{
    if ($value === null || $value === '') {
        return null;
    }
    $raw = base64_decode($value, true);
    if ($raw === false || strlen($raw) <= 16) {
        return null;
    }
    $iv = substr($raw, 0, 16);
    $cipher = substr($raw, 16);
    $plain = openssl_decrypt($cipher, 'AES-256-CBC', integration_key(), OPENSSL_RAW_DATA, $iv);
    return $plain === false ? null : $plain;
}

function integration_http(string $method, string $url, array $headers = [], ?string $body = null): array
{
    $curl = curl_init($url);
    curl_setopt_array($curl, [
        CURLOPT_RETURNTRANSFER => true,
        CURLOPT_CUSTOMREQUEST => $method,
        CURLOPT_HTTPHEADER => $headers,
        CURLOPT_TIMEOUT => 45,
    ]);
    if ($body !== null) {
        curl_setopt($curl, CURLOPT_POSTFIELDS, $body);
    }
    $response = curl_exec($curl);
    $status = (int)curl_getinfo($curl, CURLINFO_RESPONSE_CODE);
    $error = curl_error($curl);
    curl_close($curl);
    if ($response === false) {
        json_error('Errore richiesta cloud: ' . $error, 502);
    }
    $decoded = json_decode((string)$response, true);
    return [
        'status' => $status,
        'body' => is_array($decoded) ? $decoded : [],
        'raw' => (string)$response,
    ];
}

function google_token_request(array $fields): array
{
    $response = integration_http(
        'POST',
        'https://oauth2.googleapis.com/token',
        ['Content-Type: application/x-www-form-urlencoded'],
        http_build_query($fields)
    );
    if ($response['status'] < 200 || $response['status'] >= 300) {
        json_error('Errore token Google: ' . ($response['raw'] ?? ''), 502);
    }
    return $response['body'];
}

function save_google_tokens(string $userId, array $tokenPayload): void
{
    $pdo = integrations_pdo();
    $accessToken = (string)($tokenPayload['access_token'] ?? '');
    if ($accessToken === '') {
        json_error('Access token Google mancante.', 502);
    }

    $profile = google_api(
        $accessToken,
        'GET',
        'https://www.googleapis.com/oauth2/v2/userinfo'
    );
    $email = (string)($profile['email'] ?? '');
    $expiresIn = (int)($tokenPayload['expires_in'] ?? 3600);
    $expiresAt = gmdate('Y-m-d H:i:s', time() + max(60, $expiresIn - 60));

    $stmt = $pdo->prepare(
        'INSERT INTO archive_integrations
          (user_id, provider, account_email, access_token, refresh_token, expires_at, scope, token_type)
         VALUES
          (:user_id, :provider, :account_email, :access_token, :refresh_token, :expires_at, :scope, :token_type)
         ON DUPLICATE KEY UPDATE
          account_email = VALUES(account_email),
          access_token = VALUES(access_token),
          refresh_token = COALESCE(VALUES(refresh_token), refresh_token),
          expires_at = VALUES(expires_at),
          scope = VALUES(scope),
          token_type = VALUES(token_type)'
    );
    $stmt->execute([
        'user_id' => $userId,
        'provider' => INTEGRATION_PROVIDER_GOOGLE,
        'account_email' => $email,
        'access_token' => encrypt_token($accessToken),
        'refresh_token' => encrypt_token((string)($tokenPayload['refresh_token'] ?? '')),
        'expires_at' => $expiresAt,
        'scope' => (string)($tokenPayload['scope'] ?? GOOGLE_DRIVE_SCOPE),
        'token_type' => (string)($tokenPayload['token_type'] ?? 'Bearer'),
    ]);
}

function integration_row(string $provider, string $userId): ?array
{
    $stmt = integrations_pdo()->prepare(
        'SELECT * FROM archive_integrations WHERE user_id = :user_id AND provider = :provider LIMIT 1'
    );
    $stmt->execute(['user_id' => $userId, 'provider' => $provider]);
    $row = $stmt->fetch();
    return is_array($row) ? $row : null;
}

function google_row_has_drive_scope(?array $row): bool
{
    if (!$row) {
        return false;
    }
    $scope = (string)($row['scope'] ?? '');
    if ($scope === '') {
        return false;
    }
    $scopes = preg_split('/\s+/', trim($scope)) ?: [];
    return in_array(GOOGLE_DRIVE_SCOPE, $scopes, true);
}

function google_access_token(string $userId): string
{
    $row = integration_row(INTEGRATION_PROVIDER_GOOGLE, $userId);
    if (!$row) {
        json_error('Google Drive non collegato.', 401);
    }
    if (!google_row_has_drive_scope($row)) {
        json_error('Permessi Google Drive insufficienti. Ricollega Drive dalle Impostazioni > Integrazioni.', 401);
    }
    $accessToken = decrypt_token((string)$row['access_token']);
    $expiresAt = strtotime((string)($row['expires_at'] ?? ''));
    if ($accessToken && $expiresAt !== false && $expiresAt > time() + 30) {
        return $accessToken;
    }

    $refreshToken = decrypt_token((string)($row['refresh_token'] ?? ''));
    if (!$refreshToken) {
        json_error('Refresh token Google mancante. Ricollega Drive.', 401);
    }
    $payload = google_token_request([
        'client_id' => integration_config_value('google_client_id'),
        'client_secret' => integration_config_value('google_client_secret'),
        'refresh_token' => $refreshToken,
        'grant_type' => 'refresh_token',
    ]);
    if (empty($payload['refresh_token'])) {
        $payload['refresh_token'] = $refreshToken;
    }
    save_google_tokens($userId, $payload);
    return (string)$payload['access_token'];
}

function google_api(string $accessToken, string $method, string $url, ?array $json = null): array
{
    $headers = ['Authorization: Bearer ' . $accessToken];
    $body = null;
    if ($json !== null) {
        $headers[] = 'Content-Type: application/json; charset=utf-8';
        $body = json_encode($json, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
    }
    $response = integration_http($method, $url, $headers, $body);
    if ($response['status'] < 200 || $response['status'] >= 300) {
        json_error('Errore Google Drive: ' . ($response['raw'] ?? ''), 502);
    }
    return $response['body'];
}

function google_path_parts(string $path): array
{
    $path = trim(str_replace('\\', '/', $path), '/');
    if ($path === '') {
        return [];
    }
    return array_values(array_filter(array_map('sanitize_segment', explode('/', $path))));
}

function google_find_child(string $accessToken, string $parentId, string $name): ?array
{
    $query = sprintf(
        "'%s' in parents and name = '%s' and trashed = false",
        addslashes($parentId),
        addslashes($name)
    );
    $url = 'https://www.googleapis.com/drive/v3/files?' . http_build_query([
        'q' => $query,
        'fields' => 'files(id,name,mimeType,size,modifiedTime)',
        'pageSize' => '1',
    ]);
    $result = google_api($accessToken, 'GET', $url);
    $files = $result['files'] ?? [];
    return isset($files[0]) && is_array($files[0]) ? $files[0] : null;
}

function google_folder_id_for_path(string $accessToken, string $path): string
{
    $parent = 'root';
    foreach (google_path_parts($path) as $part) {
        $child = google_find_child($accessToken, $parent, $part);
        if (!$child || ($child['mimeType'] ?? '') !== 'application/vnd.google-apps.folder') {
            json_error('Cartella Google Drive non trovata.', 404);
        }
        $parent = (string)$child['id'];
    }
    return $parent;
}

function google_file_id_for_path(string $accessToken, string $path): string
{
    $parts = google_path_parts($path);
    $name = array_pop($parts);
    if (!$name) {
        json_error('Percorso file non valido.', 422);
    }
    $parent = google_folder_id_for_path($accessToken, implode('/', $parts));
    $child = google_find_child($accessToken, $parent, $name);
    if (!$child) {
        json_error('Elemento Google Drive non trovato.', 404);
    }
    return (string)$child['id'];
}

function google_entry_from_file(array $file, string $basePath): array
{
    $name = (string)($file['name'] ?? '');
    $isFolder = ($file['mimeType'] ?? '') === 'application/vnd.google-apps.folder';
    $path = trim($basePath . '/' . $name, '/');
    return [
        'name' => $name,
        'path' => $path,
        'isDirectory' => $isFolder,
        'sizeBytes' => isset($file['size']) ? (int)$file['size'] : null,
        'modifiedAt' => (string)($file['modifiedTime'] ?? gmdate(DATE_ATOM)),
    ];
}
