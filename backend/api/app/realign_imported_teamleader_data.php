<?php
declare(strict_types=1);

require_once dirname(__DIR__) . '/config.php';

header('Content-Type: application/json; charset=utf-8');
ini_set('memory_limit', '1024M');
set_time_limit(0);

const REALIGN_TEAM_ID = 'team-LECUVITaSJWIyD8xNR79';
const REALIGN_KEY = 'nexora-realign-import-2026-06-16';
const REALIGN_OPERATOR_MAP = [
    'c2a80468-0ae0-0060-b759-e7fdd186ce6b' => 'LkuRs07bTNdPZjGC7Z902cbLy883',
    'ad8760c2-f2fc-0e49-9f5e-ca0397e116ba' => 'JG5oh5q5axVBrtwYHKDwDc4jk7T2',
    '8df54a33-ba6d-0f4a-b549-43198dd2f6e8' => 'JpNmy5BGXLTGbFGqHtaHfKFbM2g2',
    'ba3dfb99-c488-06e9-9246-e095a6c2f6e9' => 'w8yaP4wTJPU65xQ6W7gOEzk7TXw2',
    '9abf09d6-78ad-0acb-b15c-9baafd74d28b' => 'VWNF38LuYbcg4c6LCbYbTWIQ7Gt2',
];

if (((string)($_GET['key'] ?? '')) !== REALIGN_KEY) {
    http_response_code(403);
    echo json_encode(['error' => 'Chiave manutenzione non valida.']);
    exit;
}

function realign_db(): PDO
{
    static $pdo = null;
    if ($pdo instanceof PDO) {
        return $pdo;
    }
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
    return $pdo;
}

function realign_csv_rows(string $path): Generator
{
    if (!is_file($path)) {
        throw new RuntimeException('CSV non trovato: ' . $path);
    }
    $handle = fopen($path, 'rb');
    if ($handle === false) {
        throw new RuntimeException('Impossibile aprire il CSV: ' . $path);
    }
    try {
        $headers = fgetcsv($handle, 0, ';', '"', '\\');
        if (!is_array($headers)) {
            return;
        }
        $headers[0] = preg_replace('/^\xEF\xBB\xBF/', '', (string)$headers[0]) ?? (string)$headers[0];
        while (($row = fgetcsv($handle, 0, ';', '"', '\\')) !== false) {
            if ($row === [null] || $row === []) {
                continue;
            }
            if (count($row) < count($headers)) {
                $row = array_pad($row, count($headers), '');
            } elseif (count($row) > count($headers)) {
                $row = array_slice($row, 0, count($headers));
            }
            yield array_combine($headers, $row) ?: [];
        }
    } finally {
        fclose($handle);
    }
}

function realign_export_dir(): string
{
    $candidates = [
        __DIR__ . '/../../export',
        __DIR__ . '/../export',
        __DIR__ . '/../../../backend/export',
        __DIR__ . '/../../../export',
        dirname(__DIR__, 3) . '/backend/export',
        dirname(__DIR__, 3) . '/export',
        $_SERVER['DOCUMENT_ROOT'] . '/backend/export',
        $_SERVER['DOCUMENT_ROOT'] . '/export',
        $_SERVER['DOCUMENT_ROOT'] . '/api/export',
    ];
    foreach ($candidates as $candidate) {
        if (!is_string($candidate) || trim($candidate) === '') {
            continue;
        }
        $real = realpath($candidate);
        if ($real !== false && is_dir($real)) {
            return $real;
        }
    }
    throw new RuntimeException('Cartella export non trovata.');
}

function realign_team_user_ids(PDO $pdo, string $teamId): array
{
    $stmt = $pdo->prepare('SELECT id FROM users WHERE team_id = ?');
    $stmt->execute([$teamId]);
    return array_values(array_filter(array_map(
        static fn(array $row) => (string)($row['id'] ?? ''),
        $stmt->fetchAll() ?: []
    )));
}

function realign_team_member_ids(PDO $pdo, string $teamId): array
{
    $stmt = $pdo->prepare(
        "SELECT user_id
         FROM team_members
         WHERE team_id = ? AND status = 'active'"
    );
    $stmt->execute([$teamId]);
    return array_values(array_filter(array_map(
        static fn(array $row) => (string)($row['user_id'] ?? ''),
        $stmt->fetchAll() ?: []
    )));
}

function realign_table_columns(PDO $pdo, string $table): array
{
    static $cache = [];
    if (isset($cache[$table])) {
        return $cache[$table];
    }
    $stmt = $pdo->query('SHOW COLUMNS FROM `' . str_replace('`', '``', $table) . '`');
    $rows = $stmt ? $stmt->fetchAll(PDO::FETCH_ASSOC) : [];
    return $cache[$table] = array_values(array_filter(array_map(
        static fn(array $row) => (string)($row['Field'] ?? ''),
        $rows
    )));
}

function realign_existing_columns(PDO $pdo, string $table, array $columns): array
{
    $available = array_flip(realign_table_columns($pdo, $table));
    return array_values(array_filter(
        $columns,
        static fn(string $column) => isset($available[$column])
    ));
}

function realign_select_all(PDO $pdo, string $table, array $columns): array
{
    $existing = realign_existing_columns($pdo, $table, $columns);
    if ($existing === []) {
        throw new RuntimeException('Nessuna colonna valida disponibile per ' . $table);
    }
    $escaped = array_map(
        static fn(string $column) => '`' . str_replace('`', '``', $column) . '`',
        $existing
    );
    $stmt = $pdo->query('SELECT ' . implode(', ', $escaped) . ' FROM `' . str_replace('`', '``', $table) . '`');
    return $stmt ? ($stmt->fetchAll() ?: []) : [];
}

function realign_prepare_update(PDO $pdo, string $table, array $columns, string $idColumn = 'id'): ?PDOStatement
{
    $existing = realign_existing_columns($pdo, $table, $columns);
    $existing = array_values(array_filter($existing, static fn(string $column) => $column !== $idColumn));
    if ($existing === []) {
        return null;
    }
    $sets = array_map(
        static fn(string $column) => '`' . str_replace('`', '``', $column) . '` = ?',
        $existing
    );
    $sql = 'UPDATE `' . str_replace('`', '``', $table) . '` SET ' . implode(', ', $sets)
        . ' WHERE `' . str_replace('`', '``', $idColumn) . '` = ?';
    return $pdo->prepare($sql);
}

function realign_target_user(?string $exportUserId, array $allowedUserIds, array &$summary, string $context): ?string
{
    $raw = trim((string)$exportUserId);
    if ($raw === '') {
        $summary['warnings']['missing_export_user'][$context] = ($summary['warnings']['missing_export_user'][$context] ?? 0) + 1;
        return null;
    }
    $target = REALIGN_OPERATOR_MAP[$raw] ?? null;
    if ($target === null) {
        $summary['warnings']['unknown_export_user'][$raw] = ($summary['warnings']['unknown_export_user'][$raw] ?? 0) + 1;
        return null;
    }
    if (!in_array($target, $allowedUserIds, true)) {
        $summary['warnings']['missing_target_user'][$target] = ($summary['warnings']['missing_target_user'][$target] ?? 0) + 1;
        return null;
    }
    return $target;
}

function realign_inc(array &$bucket, string $key, int $amount = 1): void
{
    $bucket[$key] = ($bucket[$key] ?? 0) + $amount;
}

try {
    $pdo = realign_db();
    $exportDir = realign_export_dir();
    $allowedUserIds = realign_team_user_ids($pdo, REALIGN_TEAM_ID);
    $teamMemberIds = realign_team_member_ids($pdo, REALIGN_TEAM_ID);
    if ($allowedUserIds === []) {
        throw new RuntimeException('Nessun utente trovato in users.team_id per il team target.');
    }
    if ($teamMemberIds === []) {
        throw new RuntimeException('Nessun membro attivo trovato in team_members per il team target.');
    }
    $defaultUserId = $allowedUserIds[0];

    $summary = [
        'ok' => true,
        'teamId' => REALIGN_TEAM_ID,
        'exportDir' => $exportDir,
        'allowedUserIds' => $allowedUserIds,
        'teamMemberIds' => $teamMemberIds,
        'defaultUserId' => $defaultUserId,
        'tables' => [
            'companies' => ['updated' => 0, 'skipped' => 0],
            'deals' => ['updated' => 0, 'skipped' => 0],
            'quotations' => ['updated' => 0, 'skipped' => 0],
            'projects' => ['updated' => 0, 'skipped' => 0],
            'project_phases' => ['updated' => 0, 'skipped' => 0],
            'tickets' => ['updated' => 0, 'skipped' => 0],
            'work_tasks' => ['updated' => 0, 'skipped' => 0],
            'time_tracks' => ['updated' => 0, 'skipped' => 0],
            'invoice_drafts' => ['updated' => 0, 'skipped' => 0],
            'credit_notes' => ['updated' => 0, 'skipped' => 0],
            'subscriptions' => ['updated' => 0, 'skipped' => 0],
            'opportunities' => ['updated' => 0, 'skipped' => 0],
            'preventivi' => ['updated' => 0, 'skipped' => 0],
            'document_templates' => ['updated' => 0, 'skipped' => 0],
            'email_templates' => ['updated' => 0, 'skipped' => 0],
            'template_choices' => ['updated' => 0, 'deleted' => 0, 'skipped' => 0],
        ],
        'warnings' => [],
    ];

    $pdo->beginTransaction();

    $companyOwnerByExportId = [];
    $companyStmt = $pdo->prepare('UPDATE companies SET user_id = ? WHERE id = ?');
    foreach (realign_csv_rows($exportDir . '/companies.csv') as $row) {
        $companyId = trim((string)($row['id'] ?? ''));
        if ($companyId === '') {
            realign_inc($summary['tables']['companies'], 'skipped');
            continue;
        }
        $target = realign_target_user($row['responsible_user.id'] ?? '', $allowedUserIds, $summary, 'companies');
        if ($target === null) {
            realign_inc($summary['tables']['companies'], 'skipped');
            continue;
        }
        $companyStmt->execute([$target, $companyId]);
        $companyOwnerByExportId[$companyId] = $target;
        realign_inc($summary['tables']['companies'], 'updated', $companyStmt->rowCount());
    }

    $dealOwnerByExportId = [];
    $dealStmt = $pdo->prepare('UPDATE deals SET user_id = ?, assigned_to = ? WHERE id = ?');
    foreach (realign_csv_rows($exportDir . '/deals.csv') as $row) {
        $dealId = trim((string)($row['id'] ?? ''));
        if ($dealId === '') {
            realign_inc($summary['tables']['deals'], 'skipped');
            continue;
        }
        $target = realign_target_user($row['responsible_user.id'] ?? '', $allowedUserIds, $summary, 'deals');
        if ($target === null) {
            realign_inc($summary['tables']['deals'], 'skipped');
            continue;
        }
        $dealStmt->execute([$target, $target, $dealId]);
        $dealOwnerByExportId[$dealId] = $target;
        realign_inc($summary['tables']['deals'], 'updated', $dealStmt->rowCount());
    }

    $quotationStmt = $pdo->prepare('UPDATE quotations SET user_id = ? WHERE id = ?');
    foreach (realign_csv_rows($exportDir . '/quotations.csv') as $row) {
        $quotationId = trim((string)($row['id'] ?? ''));
        $dealId = trim((string)($row['deal.id'] ?? ''));
        if ($quotationId === '' || $dealId === '' || !isset($dealOwnerByExportId[$dealId])) {
            realign_inc($summary['tables']['quotations'], 'skipped');
            continue;
        }
        $quotationStmt->execute([$dealOwnerByExportId[$dealId], $quotationId]);
        realign_inc($summary['tables']['quotations'], 'updated', $quotationStmt->rowCount());
    }

    $projectOwnerByExportId = [];
    $projectStmt = $pdo->prepare('UPDATE projects SET user_id = ? WHERE id = ?');
    foreach (realign_csv_rows($exportDir . '/projects_legacy.csv') as $row) {
        $projectId = trim((string)($row['id'] ?? ''));
        if ($projectId === '') {
            realign_inc($summary['tables']['projects'], 'skipped');
            continue;
        }
        $companyId = trim((string)($row['customer.id'] ?? ''));
        $dealId = trim((string)($row['source.id'] ?? ''));
        $target = $companyOwnerByExportId[$companyId] ?? $dealOwnerByExportId[$dealId] ?? null;
        if ($target === null) {
            realign_inc($summary['tables']['projects'], 'skipped');
            continue;
        }
        $projectStmt->execute([$target, $projectId]);
        $projectOwnerByExportId[$projectId] = $target;
        realign_inc($summary['tables']['projects'], 'updated', $projectStmt->rowCount());
    }

    $phaseStmt = $pdo->prepare('UPDATE project_phases SET user_id = ?, assigned_user_id = ? WHERE id = ?');
    foreach (realign_csv_rows($exportDir . '/milestones_legacy.csv') as $row) {
        $phaseId = trim((string)($row['id'] ?? ''));
        $projectId = trim((string)($row['project.id'] ?? ''));
        if ($phaseId === '' || $projectId === '' || !isset($projectOwnerByExportId[$projectId])) {
            realign_inc($summary['tables']['project_phases'], 'skipped');
            continue;
        }
        $projectOwner = $projectOwnerByExportId[$projectId];
        $assignedUser = realign_target_user($row['responsible_user.id'] ?? '', $allowedUserIds, $summary, 'project_phases') ?? $projectOwner;
        $phaseStmt->execute([$projectOwner, $assignedUser, $phaseId]);
        realign_inc($summary['tables']['project_phases'], 'updated', $phaseStmt->rowCount());
    }

    $ticketOwnerByExportId = [];
    $ticketStmt = $pdo->prepare('UPDATE tickets SET user_id = ? WHERE id = ?');
    foreach (realign_csv_rows($exportDir . '/tickets.csv') as $row) {
        $ticketId = trim((string)($row['id'] ?? ''));
        if ($ticketId === '') {
            realign_inc($summary['tables']['tickets'], 'skipped');
            continue;
        }
        $target = realign_target_user($row['assignee.id'] ?? '', $allowedUserIds, $summary, 'tickets');
        if ($target === null) {
            realign_inc($summary['tables']['tickets'], 'skipped');
            continue;
        }
        $ticketStmt->execute([$target, $ticketId]);
        $ticketOwnerByExportId[$ticketId] = $target;
        realign_inc($summary['tables']['tickets'], 'updated', $ticketStmt->rowCount());
    }

    $taskStmt = $pdo->prepare('UPDATE work_tasks SET user_id = ?, assignee_id = ? WHERE id = ?');
    foreach (realign_csv_rows($exportDir . '/tasks_legacy.csv') as $row) {
        $taskId = trim((string)($row['id'] ?? ''));
        if ($taskId === '') {
            realign_inc($summary['tables']['work_tasks'], 'skipped');
            continue;
        }
        $projectId = trim((string)($row['project.id'] ?? ''));
        $ticketId = trim((string)($row['ticket.id'] ?? ''));
        $owner = $projectOwnerByExportId[$projectId] ?? $ticketOwnerByExportId[$ticketId] ?? null;
        $assignee = realign_target_user($row['assignee.id'] ?? '', $allowedUserIds, $summary, 'work_tasks') ?? $owner;
        if ($owner === null && $assignee === null) {
            realign_inc($summary['tables']['work_tasks'], 'skipped');
            continue;
        }
        $owner = $owner ?? $assignee;
        $assignee = $assignee ?? $owner;
        $taskStmt->execute([$owner, $assignee, $taskId]);
        realign_inc($summary['tables']['work_tasks'], 'updated', $taskStmt->rowCount());
    }

    $timeTrackStmt = $pdo->prepare('UPDATE time_tracks SET user_id = ?, tracker_user_id = ? WHERE id = ?');
    foreach (realign_csv_rows($exportDir . '/time_tracking.csv') as $row) {
        $trackId = trim((string)($row['id'] ?? ''));
        if ($trackId === '') {
            realign_inc($summary['tables']['time_tracks'], 'skipped');
            continue;
        }
        $target = realign_target_user($row['user.id'] ?? '', $allowedUserIds, $summary, 'time_tracks');
        if ($target === null) {
            realign_inc($summary['tables']['time_tracks'], 'skipped');
            continue;
        }
        $timeTrackStmt->execute([$target, $target, $trackId]);
        realign_inc($summary['tables']['time_tracks'], 'updated', $timeTrackStmt->rowCount());
    }

    $invoiceStmt = $pdo->prepare('UPDATE invoice_drafts SET user_id = ? WHERE id = ?');
    foreach (realign_csv_rows($exportDir . '/invoices.csv') as $row) {
        $invoiceId = trim((string)($row['id'] ?? ''));
        if ($invoiceId === '') {
            realign_inc($summary['tables']['invoice_drafts'], 'skipped');
            continue;
        }
        $companyId = trim((string)($row['invoicee.customer.id'] ?? ''));
        $projectId = trim((string)($row['project.id'] ?? ''));
        $target = $projectOwnerByExportId[$projectId] ?? $companyOwnerByExportId[$companyId] ?? null;
        if ($target === null) {
            realign_inc($summary['tables']['invoice_drafts'], 'skipped');
            continue;
        }
        $invoiceStmt->execute([$target, $invoiceId]);
        realign_inc($summary['tables']['invoice_drafts'], 'updated', $invoiceStmt->rowCount());
    }

    $creditStmt = $pdo->prepare('UPDATE credit_notes SET user_id = ? WHERE id = ?');
    foreach (realign_csv_rows($exportDir . '/credit_notes.csv') as $row) {
        $creditNoteId = trim((string)($row['id'] ?? ''));
        $companyId = trim((string)($row['invoicee.customer.id'] ?? ''));
        if ($creditNoteId === '' || !isset($companyOwnerByExportId[$companyId])) {
            realign_inc($summary['tables']['credit_notes'], 'skipped');
            continue;
        }
        $creditStmt->execute([$companyOwnerByExportId[$companyId], $creditNoteId]);
        realign_inc($summary['tables']['credit_notes'], 'updated', $creditStmt->rowCount());
    }

    $subscriptionStmt = $pdo->prepare('UPDATE subscriptions SET user_id = ? WHERE id = ?');
    foreach (realign_csv_rows($exportDir . '/subscriptions.csv') as $row) {
        $subscriptionId = trim((string)($row['id'] ?? ''));
        $companyId = trim((string)($row['invoicee.customer.id'] ?? ''));
        $projectId = trim((string)($row['project.id'] ?? ''));
        if ($subscriptionId === '') {
            realign_inc($summary['tables']['subscriptions'], 'skipped');
            continue;
        }
        $target = $projectOwnerByExportId[$projectId] ?? $companyOwnerByExportId[$companyId] ?? null;
        if ($target === null) {
            realign_inc($summary['tables']['subscriptions'], 'skipped');
            continue;
        }
        $subscriptionStmt->execute([$target, $subscriptionId]);
        realign_inc($summary['tables']['subscriptions'], 'updated', $subscriptionStmt->rowCount());
    }

    // Riallinea anche i moduli già nativi di Nexora: serve per rendere davvero
    // condivisi tra membri del team i record creati quando users/team_members
    // non erano ancora sincronizzati bene.
    $companyOwnerById = [];
    $companyOwnerRows = $pdo->query('SELECT id, user_id FROM companies')->fetchAll() ?: [];
    foreach ($companyOwnerRows as $companyRow) {
        $companyId = trim((string)($companyRow['id'] ?? ''));
        $companyUserId = trim((string)($companyRow['user_id'] ?? ''));
        if ($companyId !== '' && $companyUserId !== '') {
            $companyOwnerById[$companyId] = $companyUserId;
        }
    }

    $allowedLookup = array_fill_keys($allowedUserIds, true);
    $teamMemberLookup = array_fill_keys($teamMemberIds, true);

    $opportunityOwnerById = [];
    $opportunityReadColumns = realign_existing_columns(
        $pdo,
        'opportunities',
        ['id', 'company_id', 'user_id', 'created_by_user_id', 'assigned_analyst_id']
    );
    $opportunityRows = realign_select_all($pdo, 'opportunities', $opportunityReadColumns);
    $opportunityWriteColumns = realign_existing_columns(
        $pdo,
        'opportunities',
        ['user_id', 'created_by_user_id', 'assigned_analyst_id']
    );
    $opportunityStmt = realign_prepare_update($pdo, 'opportunities', $opportunityWriteColumns);
    foreach ($opportunityRows as $row) {
        $opportunityId = trim((string)($row['id'] ?? ''));
        if ($opportunityId === '') {
            realign_inc($summary['tables']['opportunities'], 'skipped');
            continue;
        }
        $currentUserId = trim((string)($row['user_id'] ?? ''));
        $creatorUserId = trim((string)($row['created_by_user_id'] ?? ''));
        $assignedUserId = trim((string)($row['assigned_analyst_id'] ?? ''));
        $companyId = trim((string)($row['company_id'] ?? ''));

        $touchesTeam =
            isset($teamMemberLookup[$currentUserId]) ||
            isset($teamMemberLookup[$creatorUserId]) ||
            isset($teamMemberLookup[$assignedUserId]) ||
            isset($allowedLookup[$currentUserId]) ||
            isset($allowedLookup[$creatorUserId]) ||
            isset($allowedLookup[$assignedUserId]) ||
            ($companyId !== '' && isset($companyOwnerById[$companyId]) && isset($allowedLookup[$companyOwnerById[$companyId]]));

        if (!$touchesTeam) {
            realign_inc($summary['tables']['opportunities'], 'skipped');
            continue;
        }

        $owner = $companyOwnerById[$companyId] ?? null;
        if ($owner === null || !isset($allowedLookup[$owner])) {
            $owner = isset($allowedLookup[$currentUserId]) ? $currentUserId : $defaultUserId;
        }
        $creator = isset($allowedLookup[$creatorUserId]) ? $creatorUserId : $owner;
        $assignee = isset($allowedLookup[$assignedUserId]) ? $assignedUserId : $owner;
        if ($opportunityStmt instanceof PDOStatement) {
            $params = [];
            foreach ($opportunityWriteColumns as $column) {
                if ($column === 'user_id') {
                    $params[] = $owner;
                } elseif ($column === 'created_by_user_id') {
                    $params[] = $creator;
                } elseif ($column === 'assigned_analyst_id') {
                    $params[] = $assignee;
                }
            }
            $params[] = $opportunityId;
            $opportunityStmt->execute($params);
            realign_inc($summary['tables']['opportunities'], 'updated', $opportunityStmt->rowCount());
        } else {
            realign_inc($summary['tables']['opportunities'], 'skipped');
        }
        $opportunityOwnerById[$opportunityId] = $owner;
    }

    $preventivoRows = $pdo->query(
        'SELECT id, user_id, company_id, opportunity_id FROM preventivi'
    )->fetchAll() ?: [];
    $preventivoStmt = $pdo->prepare('UPDATE preventivi SET user_id = ? WHERE id = ?');
    foreach ($preventivoRows as $row) {
        $preventivoId = trim((string)($row['id'] ?? ''));
        if ($preventivoId === '') {
            realign_inc($summary['tables']['preventivi'], 'skipped');
            continue;
        }
        $currentUserId = trim((string)($row['user_id'] ?? ''));
        $companyId = trim((string)($row['company_id'] ?? ''));
        $opportunityId = trim((string)($row['opportunity_id'] ?? ''));

        $touchesTeam =
            isset($teamMemberLookup[$currentUserId]) ||
            isset($allowedLookup[$currentUserId]) ||
            ($companyId !== '' && isset($companyOwnerById[$companyId]) && isset($allowedLookup[$companyOwnerById[$companyId]])) ||
            ($opportunityId !== '' && isset($opportunityOwnerById[$opportunityId]));

        if (!$touchesTeam) {
            realign_inc($summary['tables']['preventivi'], 'skipped');
            continue;
        }

        $owner = $opportunityOwnerById[$opportunityId]
            ?? $companyOwnerById[$companyId]
            ?? (isset($allowedLookup[$currentUserId]) ? $currentUserId : $defaultUserId);

        $preventivoStmt->execute([$owner, $preventivoId]);
        realign_inc($summary['tables']['preventivi'], 'updated', $preventivoStmt->rowCount());
    }

    foreach (['document_templates', 'email_templates'] as $templateTable) {
        $selectStmt = $pdo->query("SELECT id, user_id FROM {$templateTable}");
        $updateStmt = $pdo->prepare("UPDATE {$templateTable} SET user_id = ? WHERE id = ?");
        foreach ($selectStmt->fetchAll() ?: [] as $row) {
            $templateId = trim((string)($row['id'] ?? ''));
            $templateUserId = trim((string)($row['user_id'] ?? ''));
            if ($templateId === '') {
                realign_inc($summary['tables'][$templateTable], 'skipped');
                continue;
            }
            if (!isset($teamMemberLookup[$templateUserId]) && !isset($allowedLookup[$templateUserId])) {
                realign_inc($summary['tables'][$templateTable], 'skipped');
                continue;
            }
            $targetUserId = isset($allowedLookup[$templateUserId]) ? $templateUserId : $defaultUserId;
            $updateStmt->execute([$targetUserId, $templateId]);
            realign_inc($summary['tables'][$templateTable], 'updated', $updateStmt->rowCount());
        }
    }

    $choiceRows = $pdo->query(
        'SELECT id, user_id, doc_id, updated_at
         FROM template_choices
         ORDER BY doc_id ASC, updated_at DESC, id DESC'
    )->fetchAll() ?: [];
    $choiceGroups = [];
    foreach ($choiceRows as $row) {
        $choiceUserId = trim((string)($row['user_id'] ?? ''));
        $docId = trim((string)($row['doc_id'] ?? ''));
        if ($docId === '') {
            realign_inc($summary['tables']['template_choices'], 'skipped');
            continue;
        }
        if (!isset($teamMemberLookup[$choiceUserId]) && !isset($allowedLookup[$choiceUserId])) {
            realign_inc($summary['tables']['template_choices'], 'skipped');
            continue;
        }
        $choiceGroups[$docId][] = $row;
    }

    $choiceUpdateStmt = $pdo->prepare('UPDATE template_choices SET user_id = ? WHERE id = ?');
    $choiceDeleteStmt = $pdo->prepare('DELETE FROM template_choices WHERE id = ?');
    foreach ($choiceGroups as $docId => $rows) {
        $kept = false;
        foreach ($rows as $row) {
            $choiceId = (int)($row['id'] ?? 0);
            if ($choiceId <= 0) {
                realign_inc($summary['tables']['template_choices'], 'skipped');
                continue;
            }
            if (!$kept) {
                $choiceUpdateStmt->execute([$defaultUserId, $choiceId]);
                realign_inc($summary['tables']['template_choices'], 'updated', $choiceUpdateStmt->rowCount());
                $kept = true;
                continue;
            }
            $choiceDeleteStmt->execute([$choiceId]);
            realign_inc($summary['tables']['template_choices'], 'deleted', $choiceDeleteStmt->rowCount());
        }
    }

    $pdo->commit();
    echo json_encode($summary, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES | JSON_PRETTY_PRINT);
} catch (Throwable $e) {
    if (isset($pdo) && $pdo instanceof PDO && $pdo->inTransaction()) {
        $pdo->rollBack();
    }
    http_response_code(500);
    echo json_encode([
        'error' => $e->getMessage(),
        'type' => get_class($e),
        'file' => $e->getFile(),
        'line' => $e->getLine(),
    ], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES | JSON_PRETTY_PRINT);
}
