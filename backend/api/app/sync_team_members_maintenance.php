<?php
declare(strict_types=1);

require_once dirname(__DIR__) . '/config.php';

header('Content-Type: application/json; charset=utf-8');

const MAINT_TEAM_ID = 'team-LECUVITaSJWIyD8xNR79';
const MAINT_KEY = 'nexora-sync-team-2026-06-16';

if (((string)($_GET['key'] ?? '')) !== MAINT_KEY) {
    http_response_code(403);
    echo json_encode(['error' => 'Chiave manutenzione non valida.']);
    exit;
}

try {
    $pdo = new PDO(
        sprintf('mysql:host=%s;port=%s;dbname=%s;charset=%s', DB_HOST, DB_PORT, DB_NAME, DB_CHARSET),
        DB_USER,
        DB_PASS,
        [
            PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
            PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
            PDO::ATTR_EMULATE_PREPARES => false,
        ]
    );

    $teamStmt = $pdo->prepare('SELECT id, name FROM teams WHERE id = ? LIMIT 1');
    $teamStmt->execute([MAINT_TEAM_ID]);
    $team = $teamStmt->fetch();
    if (!$team) {
        throw new RuntimeException('Team non trovato: ' . MAINT_TEAM_ID);
    }

    $membersStmt = $pdo->prepare(
        "SELECT user_id, email, display_name, role, status
         FROM team_members
         WHERE team_id = ?
         ORDER BY joined_at ASC"
    );
    $membersStmt->execute([MAINT_TEAM_ID]);
    $members = $membersStmt->fetchAll() ?: [];

    $updated = 0;
    $alreadyAligned = 0;
    $createdUsers = 0;
    $missingUsers = [];

    $selectUserStmt = $pdo->prepare('SELECT id, team_id, email, display_name FROM users WHERE id = ? LIMIT 1');
    $selectProfileStmt = $pdo->prepare('SELECT uid, email, display_name FROM user_profiles WHERE uid = ? LIMIT 1');
    $updateUserStmt = $pdo->prepare('UPDATE users SET team_id = ? WHERE id = ?');
    $insertUserStmt = $pdo->prepare(
        'INSERT INTO users (id, team_id, email, display_name, role, billing_profile, youdox_config, ui_state)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?)'
    );

    foreach ($members as $member) {
        $memberId = (string)($member['user_id'] ?? '');
        if ($memberId === '') {
            continue;
        }

        $selectUserStmt->execute([$memberId]);
        $user = $selectUserStmt->fetch();
        if (!$user) {
            $selectProfileStmt->execute([$memberId]);
            $profile = $selectProfileStmt->fetch();
            if (!$profile) {
                $missingUsers[] = [
                    'userId' => $memberId,
                    'email' => (string)($member['email'] ?? ''),
                    'displayName' => (string)($member['display_name'] ?? ''),
                    'status' => (string)($member['status'] ?? ''),
                    'reason' => 'missing_in_users_and_user_profiles',
                ];
                continue;
            }

            $insertUserStmt->execute([
                $memberId,
                MAINT_TEAM_ID,
                (string)($profile['email'] ?? $member['email'] ?? ''),
                (string)($profile['display_name'] ?? $member['display_name'] ?? ''),
                (string)($member['role'] ?? ''),
                '{}',
                '{}',
                '{}',
            ]);
            $createdUsers++;
            continue;
        }

        if ((string)($user['team_id'] ?? '') === MAINT_TEAM_ID) {
            $alreadyAligned++;
            continue;
        }

        $updateUserStmt->execute([MAINT_TEAM_ID, $memberId]);
        $updated += $updateUserStmt->rowCount();
    }

    echo json_encode([
        'ok' => true,
        'team' => [
            'id' => (string)$team['id'],
            'name' => (string)$team['name'],
        ],
        'membersCount' => count($members),
        'createdUsers' => $createdUsers,
        'updatedUsers' => $updated,
        'alreadyAligned' => $alreadyAligned,
        'missingUsers' => $missingUsers,
        'maintenanceFile' => basename(__FILE__),
        'removeAfterUse' => true,
    ], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES | JSON_PRETTY_PRINT);
} catch (Throwable $e) {
    http_response_code(500);
    echo json_encode([
        'error' => $e->getMessage(),
        'type' => get_class($e),
        'file' => $e->getFile(),
        'line' => $e->getLine(),
    ], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES | JSON_PRETTY_PRINT);
}
