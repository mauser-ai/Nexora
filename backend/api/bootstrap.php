<?php
// bootstrap.php — compatibile PHP 7.4+

require_once __DIR__ . '/config.php';
require_once __DIR__ . '/middleware/cors.php';
require_once __DIR__ . '/middleware/auth.php';

// ── Connessione PDO (singleton) ───────────────────────────────────────────────
function db(): PDO {
    static $pdo = null;
    if ($pdo === null) {
        $dsn = sprintf('mysql:host=%s;port=%s;dbname=%s;charset=%s',
            DB_HOST, DB_PORT, DB_NAME, DB_CHARSET);
        $pdo = new PDO($dsn, DB_USER, DB_PASS, [
            PDO::ATTR_ERRMODE            => PDO::ERRMODE_EXCEPTION,
            PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
            PDO::ATTR_EMULATE_PREPARES   => false,
        ]);
    }
    return $pdo;
}

// ── Risposte JSON ─────────────────────────────────────────────────────────────
function json_ok($data, int $code = 200): void {
    http_response_code($code);
    header('Content-Type: application/json; charset=utf-8');
    echo json_encode($data, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
    exit;
}

function json_error(string $message, int $code = 400): void {
    http_response_code($code);
    header('Content-Type: application/json; charset=utf-8');
    echo json_encode(['error' => $message]);
    exit;
}

// ── Body JSON della request ───────────────────────────────────────────────────
function request_body(): array {
    $raw = file_get_contents('php://input');
    if (empty($raw)) return [];
    $data = json_decode($raw, true);
    return is_array($data) ? $data : [];
}

// ── UUID v4 ───────────────────────────────────────────────────────────────────
function uuid4(): string {
    $data    = random_bytes(16);
    $data[6] = chr(ord($data[6]) & 0x0f | 0x40);
    $data[8] = chr(ord($data[8]) & 0x3f | 0x80);
    return vsprintf('%s%s-%s-%s-%s-%s%s%s', str_split(bin2hex($data), 4));
}

// ── Helpers tipo ──────────────────────────────────────────────────────────────
function str_val($v, string $default = ''): string {
    return is_string($v) ? $v : $default;
}

function float_val($v): ?float {
    return $v !== null ? (float)$v : null;
}

function int_val($v): ?int {
    return $v !== null ? (int)$v : null;
}

function bool_val($v, bool $default = false): bool {
    if (is_bool($v)) return $v;
    if (is_int($v))  return $v !== 0;
    return $default;
}

// ── Conversioni date ──────────────────────────────────────────────────────────
function to_dt($v): ?string {
    if (empty($v)) return null;
    if (is_numeric($v)) return date('Y-m-d H:i:s', (int)($v / 1000));
    return substr((string)$v, 0, 19);
}

function to_date($v): ?string {
    $dt = to_dt($v);
    return $dt ? substr($dt, 0, 10) : null;
}

function from_dt(?string $v): ?string {
    if ($v === null || $v === '0000-00-00 00:00:00') return null;
    return str_replace(' ', 'T', $v) . 'Z';
}

function from_date(?string $v): ?string {
    if (empty($v) || $v === '0000-00-00') return null;
    return $v . 'T00:00:00Z';
}

// ── JSON colonna DB ───────────────────────────────────────────────────────────
function json_col(?string $v, $default = []) {
    if (empty($v)) return $default;
    $d = json_decode($v, true);
    return $d ?? $default;
}

// ── Metodo HTTP ───────────────────────────────────────────────────────────────
function http_method(): string {
    return strtoupper($_SERVER['REQUEST_METHOD'] ?? 'GET');
}

// ── Auth guard ────────────────────────────────────────────────────────────────
function require_auth(): string {
    $token = get_bearer_token();
    if (!$token) json_error('Token mancante', 401);
    $payload = verify_access_token($token);
    if (!$payload) json_error('Token non valido o scaduto', 401);
    return $payload['sub'];
}

function current_team_id(string $userId): ?string {
    static $cache = [];
    if (array_key_exists($userId, $cache)) {
        return $cache[$userId];
    }
    try {
        $st = db()->prepare('SELECT team_id FROM users WHERE id = ? LIMIT 1');
        $st->execute([$userId]);
        $teamId = $st->fetchColumn();
        return $cache[$userId] = ($teamId ?: null);
    } catch (Throwable $e) {
        return $cache[$userId] = null;
    }
}

function scoped_user_ids(string $userId): array {
    static $cache = [];
    if (isset($cache[$userId])) {
        return $cache[$userId];
    }
    $teamId = current_team_id($userId);
    if (!$teamId) {
        return $cache[$userId] = [$userId];
    }
    try {
        $st = db()->prepare('SELECT id FROM users WHERE team_id = ?');
        $st->execute([$teamId]);
        $ids = array_values(array_filter(array_map(
            fn($row) => $row['id'] ?? null,
            $st->fetchAll()
        )));
        if (empty($ids)) {
            $ids = [$userId];
        }
        return $cache[$userId] = $ids;
    } catch (Throwable $e) {
        return $cache[$userId] = [$userId];
    }
}

function scope_filter_sql(string $column, array $ids): array {
    if (empty($ids)) {
        $ids = [''];
    }
    $placeholders = implode(',', array_fill(0, count($ids), '?'));
    return [
        'sql' => $column . ' IN (' . $placeholders . ')',
        'params' => array_values($ids),
    ];
}
