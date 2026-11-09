<?php
declare(strict_types=1);

if (!empty($_GET['access_token']) && empty($_SERVER['HTTP_AUTHORIZATION'])) {
    $_SERVER['HTTP_AUTHORIZATION'] = 'Bearer ' . (string)$_GET['access_token'];
}

require_once __DIR__ . '/helpers.php';

header('Content-Type: application/json; charset=utf-8');

try {
    $uid = require_auth();
    $pdo = db();
    app_require_superadmin($pdo, $uid);
} catch (Throwable $e) {
    http_response_code(500);
    echo json_encode([
        'error' => $e->getMessage(),
        'type' => get_class($e),
    ], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
    exit;
}

$teamId = trim((string)($_GET['teamId'] ?? 'team-LECUVITaSJWIyD8xNR79'));
if ($teamId === '') {
    json_error('teamId mancante', 422);
}

try {
    $teamStmt = $pdo->prepare('SELECT id, name FROM teams WHERE id = ? LIMIT 1');
    $teamStmt->execute([$teamId]);
    $team = $teamStmt->fetch(PDO::FETCH_ASSOC);
    if (!$team) {
        json_error('Team non trovato', 404);
    }

    $membersStmt = $pdo->prepare(
        "SELECT user_id, email, display_name, role, status
         FROM team_members
         WHERE team_id = ?
         ORDER BY joined_at ASC"
    );
    $membersStmt->execute([$teamId]);
    $members = $membersStmt->fetchAll(PDO::FETCH_ASSOC) ?: [];

    $updated = 0;
    $missingUsers = [];
    $alreadyOk = 0;

    foreach ($members as $member) {
        $memberId = (string)($member['user_id'] ?? '');
        if ($memberId === '') {
            continue;
        }

        $userStmt = $pdo->prepare('SELECT id, team_id, email, display_name FROM users WHERE id = ? LIMIT 1');
        $userStmt->execute([$memberId]);
        $user = $userStmt->fetch(PDO::FETCH_ASSOC);
        if (!$user) {
            $missingUsers[] = [
                'userId' => $memberId,
                'email' => (string)($member['email'] ?? ''),
                'displayName' => (string)($member['display_name'] ?? ''),
                'status' => (string)($member['status'] ?? ''),
            ];
            continue;
        }

        if ((string)($user['team_id'] ?? '') === $teamId) {
            $alreadyOk++;
            continue;
        }

        $updateStmt = $pdo->prepare('UPDATE users SET team_id = ? WHERE id = ?');
        $updateStmt->execute([$teamId, $memberId]);
        $updated += $updateStmt->rowCount();
    }

    json_ok([
        'ok' => true,
        'team' => [
            'id' => (string)$team['id'],
            'name' => (string)$team['name'],
        ],
        'membersCount' => count($members),
        'updatedUsers' => $updated,
        'alreadyAligned' => $alreadyOk,
        'missingUsers' => $missingUsers,
    ]);
} catch (Throwable $e) {
    http_response_code(500);
    echo json_encode([
        'error' => $e->getMessage(),
        'type' => get_class($e),
        'file' => $e->getFile(),
        'line' => $e->getLine(),
    ], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
    exit;
}
