<?php
declare(strict_types=1);

// Team dell'utente:
//   GET                  → team di appartenenza + membri (creato al volo se
//                          l'utente non appartiene a nessun team)
//   GET ?id=<teamId>     → branding di un team specifico (per logo nei PDF)
//   PUT  {name?, brandLogoUrl?, brandColor?}    → aggiorna il proprio team
//   POST {member:{userId,email,displayName,role,status}} → upsert membro
//   DELETE ?member=<uid> → rimuove un membro (owner/superadmin)

require_once __DIR__ . '/helpers.php';

header('Content-Type: application/json; charset=utf-8');

$uid = require_auth();
$pdo = db();
$method = $_SERVER['REQUEST_METHOD'];

function team_to_json(PDO $pdo, array $team): array
{
    $stmt = $pdo->prepare(
        'SELECT * FROM team_members WHERE team_id = :id ORDER BY display_name ASC'
    );
    $stmt->execute([':id' => $team['id']]);
    $members = array_map(
        fn(array $m) => [
            'userId' => (string)$m['user_id'],
            'email' => (string)$m['email'],
            'displayName' => (string)$m['display_name'],
            'role' => (string)$m['role'],
            'status' => (string)$m['status'],
            'joinedAt' => app_iso((string)$m['joined_at']),
        ],
        $stmt->fetchAll(PDO::FETCH_ASSOC) ?: []
    );
    return [
        'id' => (string)$team['id'],
        'name' => (string)$team['name'],
        'ownerId' => (string)$team['owner_id'],
        'brandLogoUrl' => (string)($team['brand_logo_url'] ?? ''),
        'brandColor' => (string)($team['brand_color'] ?? ''),
        'createdAt' => app_iso((string)$team['created_at']),
        'members' => $members,
    ];
}

function team_of_user(PDO $pdo, string $uid): ?array
{
    $stmt = $pdo->prepare(
        'SELECT t.* FROM teams t
         INNER JOIN team_members m ON m.team_id = t.id
         WHERE m.user_id = :uid AND m.status = \'active\'
         ORDER BY t.created_at ASC LIMIT 1'
    );
    $stmt->execute([':uid' => $uid]);
    $team = $stmt->fetch(PDO::FETCH_ASSOC);
    return $team ?: null;
}

if ($method === 'GET') {
    $teamId = trim((string)($_GET['id'] ?? ''));
    if ($teamId !== '') {
        $stmt = $pdo->prepare('SELECT * FROM teams WHERE id = :id');
        $stmt->execute([':id' => $teamId]);
        $team = $stmt->fetch(PDO::FETCH_ASSOC);
        if (!$team) {
            json_ok(['team' => null]);
        }
        json_ok(['team' => team_to_json($pdo, $team)]);
    }

    $team = team_of_user($pdo, $uid);
    if ($team === null) {
        // Crea il team personale dell'utente al primo accesso.
        $profile = app_ensure_profile($pdo, $uid);
        $teamId = 'team-' . substr($uid, 0, 20);
        $name = $profile['display_name'] !== ''
            ? $profile['display_name']
            : (explode('@', (string)$profile['email'])[0] ?? 'Il mio team');
        $pdo->prepare(
            'INSERT INTO teams (id, name, owner_id) VALUES (:id, :name, :owner)
             ON DUPLICATE KEY UPDATE id = id'
        )->execute([':id' => $teamId, ':name' => $name, ':owner' => $uid]);
        $pdo->prepare(
            'INSERT INTO team_members (team_id, user_id, email, display_name, role, status)
             VALUES (:team, :uid, :email, :name, \'owner\', \'active\')
             ON DUPLICATE KEY UPDATE status = \'active\''
        )->execute([
            ':team' => $teamId,
            ':uid' => $uid,
            ':email' => (string)$profile['email'],
            ':name' => (string)$profile['display_name'],
        ]);
        $team = team_of_user($pdo, $uid);
    }
    json_ok(['team' => $team ? team_to_json($pdo, $team) : null]);
}

// Per le scritture serve essere owner del team (o superadmin).
$team = team_of_user($pdo, $uid);
if ($team === null) {
    json_error('Nessun team associato all\'utente.', 404);
}
$profile = app_ensure_profile($pdo, $uid);
$canManage = $team['owner_id'] === $uid || ($profile['role'] ?? '') === 'superadmin';

if ($method === 'PUT') {
    if (!$canManage) {
        json_error('Solo il titolare del team può modificarlo.', 403);
    }
    $payload = request_json();
    $sets = [];
    $params = [':id' => $team['id']];
    foreach ([
        'name' => 'name',
        'brandLogoUrl' => 'brand_logo_url',
        'brandColor' => 'brand_color',
    ] as $jsonKey => $column) {
        if (array_key_exists($jsonKey, $payload)) {
            $sets[] = "$column = :$column";
            $params[":$column"] = (string)($payload[$jsonKey] ?? '');
        }
    }
    if ($sets) {
        $pdo->prepare(
            'UPDATE teams SET ' . implode(', ', $sets) . ' WHERE id = :id'
        )->execute($params);
    }
    json_ok(['ok' => true]);
}

if ($method === 'POST') {
    if (!$canManage) {
        json_error('Solo il titolare del team può gestire i membri.', 403);
    }
    $payload = request_json();
    $member = $payload['member'] ?? null;
    if (!is_array($member) || trim((string)($member['userId'] ?? '')) === '') {
        json_error('Payload member non valido.', 422);
    }
    $pdo->prepare(
        'INSERT INTO team_members (team_id, user_id, email, display_name, role, status)
         VALUES (:team, :uid, :email, :name, :role, :status)
         ON DUPLICATE KEY UPDATE
           email = VALUES(email), display_name = VALUES(display_name),
           role = VALUES(role), status = VALUES(status)'
    )->execute([
        ':team' => $team['id'],
        ':uid' => trim((string)$member['userId']),
        ':email' => trim((string)($member['email'] ?? '')),
        ':name' => trim((string)($member['displayName'] ?? '')),
        ':role' => trim((string)($member['role'] ?? '')),
        ':status' => trim((string)($member['status'] ?? 'active')) ?: 'active',
    ]);
    json_ok(['ok' => true]);
}

if ($method === 'DELETE') {
    if (!$canManage) {
        json_error('Solo il titolare del team può gestire i membri.', 403);
    }
    $memberId = trim((string)($_GET['member'] ?? ''));
    if ($memberId === '' || $memberId === $team['owner_id']) {
        json_error('Membro non valido (il titolare non è rimovibile).', 422);
    }
    $pdo->prepare(
        'DELETE FROM team_members WHERE team_id = :team AND user_id = :uid'
    )->execute([':team' => $team['id'], ':uid' => $memberId]);
    json_ok(['ok' => true]);
}

json_error('Metodo non consentito.', 405);
