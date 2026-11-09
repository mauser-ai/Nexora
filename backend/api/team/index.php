<?php
require_once __DIR__ . '/../bootstrap.php';

$userId = require_auth();
$method = http_method();

if ($method === 'GET') {
    // Restituisce il team dell'utente + i membri attivi
    $userStmt = db()->prepare('SELECT team_id FROM users WHERE id=? LIMIT 1');
    $userStmt->execute([$userId]);
    $userRow = $userStmt->fetch();
    $teamId  = $userRow['team_id'] ?? null;

    if (!$teamId) {
        json_ok(['team' => null, 'members' => []]);
    }

    $teamStmt = db()->prepare('SELECT * FROM teams WHERE id=? LIMIT 1');
    $teamStmt->execute([$teamId]);
    $team = $teamStmt->fetch() ?: null;

    $membersStmt = db()->prepare("SELECT * FROM team_members WHERE team_id=? AND status='active'");
    $membersStmt->execute([$teamId]);
    $members = $membersStmt->fetchAll();

    json_ok(['team' => $team, 'members' => $members]);
}

json_error('Metodo non consentito', 405);
