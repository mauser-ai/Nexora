<?php
// ─────────────────────────────────────────────────────────────────────────────
// auth.php  –  JWT HS256 + verifica Firebase ID Token
// ─────────────────────────────────────────────────────────────────────────────

// ── JWT HS256 ─────────────────────────────────────────────────────────────────

function jwt_base64url_encode(string $data): string {
    return rtrim(strtr(base64_encode($data), '+/', '-_'), '=');
}

function jwt_base64url_decode(string $data): string {
    return base64_decode(strtr($data, '-_', '+/') . str_repeat('=', 3 - (3 + strlen($data)) % 4));
}

function jwt_create(array $payload, string $secret, int $ttl): string {
    $header  = jwt_base64url_encode(json_encode(['alg' => 'HS256', 'typ' => 'JWT']));
    $payload['iat'] = time();
    $payload['exp'] = time() + $ttl;
    $body = jwt_base64url_encode(json_encode($payload));
    $sig  = jwt_base64url_encode(hash_hmac('sha256', "$header.$body", $secret, true));
    return "$header.$body.$sig";
}

function jwt_verify(string $token, string $secret): ?array {
    $parts = explode('.', $token);
    if (count($parts) !== 3) return null;
    [$header, $body, $sig] = $parts;

    $expected = jwt_base64url_encode(hash_hmac('sha256', "$header.$body", $secret, true));
    if (!hash_equals($expected, $sig)) return null;

    $payload = json_decode(jwt_base64url_decode($body), true);
    if (!is_array($payload)) return null;
    if (isset($payload['exp']) && $payload['exp'] < time()) return null;

    return $payload;
}

// ── Tokens applicazione ───────────────────────────────────────────────────────

function create_access_token(string $userId): string {
    return jwt_create(['sub' => $userId, 'type' => 'access'], JWT_ACCESS_SECRET, JWT_ACCESS_TTL);
}

function create_refresh_token(string $userId): string {
    return jwt_create(['sub' => $userId, 'type' => 'refresh'], JWT_REFRESH_SECRET, JWT_REFRESH_TTL);
}

function verify_access_token(string $token): ?array {
    $p = jwt_verify($token, JWT_ACCESS_SECRET);
    return ($p && ($p['type'] ?? '') === 'access') ? $p : null;
}

function verify_refresh_token(string $token): ?array {
    $p = jwt_verify($token, JWT_REFRESH_SECRET);
    return ($p && ($p['type'] ?? '') === 'refresh') ? $p : null;
}

// ── Estrae Bearer token dall'header Authorization ─────────────────────────────

function get_bearer_token(): ?string {
    $h = $_SERVER['HTTP_AUTHORIZATION'] ?? '';
    if (preg_match('/^Bearer\s+(.+)$/i', $h, $m)) return $m[1];
    return null;
}

// ── Fetch URL con cURL (fallback su file_get_contents) ────────────────────────
function _fetch_url(string $url): ?string {
    if (function_exists('curl_init')) {
        $ch = curl_init($url);
        curl_setopt_array($ch, [
            CURLOPT_RETURNTRANSFER => true,
            CURLOPT_TIMEOUT        => 10,
            CURLOPT_SSL_VERIFYPEER => true,
            CURLOPT_FOLLOWLOCATION => true,
        ]);
        $body = curl_exec($ch);
        $code = curl_getinfo($ch, CURLINFO_HTTP_CODE);
        curl_close($ch);
        return ($body !== false && $code === 200) ? $body : null;
    }
    // Fallback
    $body = @file_get_contents($url);
    return $body !== false ? $body : null;
}

// ── Verifica Firebase ID Token ────────────────────────────────────────────────
function verify_firebase_token(string $idToken): ?array {
    $parts = explode('.', $idToken);
    if (count($parts) !== 3) return null;
    [$headerB64, $payloadB64, $sigB64] = $parts;

    $header  = json_decode(jwt_base64url_decode($headerB64), true);
    $payload = json_decode(jwt_base64url_decode($payloadB64), true);

    if (!is_array($header) || !is_array($payload)) return null;

    $now       = time();
    $projectId = FIREBASE_PROJECT_ID;

    // Controlli payload — con tolleranza clock skew ±5 min
    if (($payload['exp'] ?? 0)  < $now - 300)          return null; // scaduto
    if (($payload['iat'] ?? 0)  > $now + 300)           return null; // emesso nel futuro
    if (($payload['aud'] ?? '') !== $projectId)          return null; // progetto sbagliato
    if (($payload['iss'] ?? '') !== "https://securetoken.google.com/$projectId") return null;
    if (empty($payload['sub']))                          return null;
    if (($header['alg'] ?? '')  !== 'RS256')             return null;

    $kid = $header['kid'] ?? '';
    if (empty($kid)) return null;

    // Chiavi pubbliche Google con cache file 1h
    $cacheFile = sys_get_temp_dir() . '/firebase_keys_' . md5($projectId) . '.json';
    $keys = [];

    if (file_exists($cacheFile) && (time() - filemtime($cacheFile)) < 3600) {
        $keys = json_decode(file_get_contents($cacheFile), true) ?? [];
    }

    if (empty($keys) || !isset($keys[$kid])) {
        $raw = _fetch_url('https://www.googleapis.com/robot/v1/metadata/x509/securetoken@system.gserviceaccount.com');
        if (!$raw) return null;
        $keys = json_decode($raw, true) ?? [];
        @file_put_contents($cacheFile, $raw);
    }

    if (!isset($keys[$kid])) return null;

    // Verifica firma RS256
    $pubKey = openssl_pkey_get_public($keys[$kid]);
    if (!$pubKey) return null;

    $result = openssl_verify(
        "$headerB64.$payloadB64",
        jwt_base64url_decode($sigB64),
        $pubKey,
        OPENSSL_ALGO_SHA256
    );

    return $result === 1 ? $payload : null;
}

// ── Gestione refresh token nel DB ─────────────────────────────────────────────

function store_refresh_token(string $userId, string $token): void {
    $hash      = hash('sha256', $token);
    $expiresAt = date('Y-m-d H:i:s', time() + JWT_REFRESH_TTL);
    db()->prepare(
        'INSERT INTO refresh_tokens (user_id, token_hash, expires_at) VALUES (?, ?, ?)'
    )->execute([$userId, $hash, $expiresAt]);
}

function revoke_refresh_token(string $token): void {
    $hash = hash('sha256', $token);
    db()->prepare('UPDATE refresh_tokens SET revoked=1 WHERE token_hash=?')->execute([$hash]);
}

function is_refresh_token_valid(string $token): bool {
    $hash = hash('sha256', $token);
    $stmt = db()->prepare(
        'SELECT id FROM refresh_tokens WHERE token_hash=? AND revoked=0 AND expires_at > NOW() LIMIT 1'
    );
    $stmt->execute([$hash]);
    return (bool)$stmt->fetch();
}

// ── Upsert utente al primo login ──────────────────────────────────────────────

function upsert_user(string $uid, string $email, string $displayName): void {
    $pdo = db();
    $teamId = null;
    try {
        $stmt = $pdo->prepare(
            "SELECT team_id
             FROM team_members
             WHERE user_id = ? AND status = 'active'
             ORDER BY joined_at ASC
             LIMIT 1"
        );
        $stmt->execute([$uid]);
        $value = $stmt->fetchColumn();
        $teamId = $value ? (string)$value : null;
    } catch (Throwable $e) {
        $teamId = null;
    }

    $stmt = $pdo->prepare('SELECT id, team_id FROM users WHERE id = ? LIMIT 1');
    $stmt->execute([$uid]);
    $existing = $stmt->fetch();

    if ($existing) {
        $sets = ['display_name = ?', 'email = ?'];
        $params = [$displayName ?: $email, $email];
        if ($teamId !== null && $teamId !== '' && (($existing['team_id'] ?? '') !== $teamId)) {
            $sets[] = 'team_id = ?';
            $params[] = $teamId;
        }
        $params[] = $uid;
        $pdo->prepare(
            'UPDATE users SET ' . implode(', ', $sets) . ' WHERE id = ?'
        )->execute($params);
        return;
    }

    $pdo->prepare(
        'INSERT INTO users (id, team_id, display_name, email, billing_profile, youdox_config, ui_state)
         VALUES (?, ?, ?, ?, ?, ?, ?)'
    )->execute([
        $uid,
        $teamId,
        $displayName ?: $email,
        $email,
        '{}',
        '{}',
        '{}',
    ]);
}
