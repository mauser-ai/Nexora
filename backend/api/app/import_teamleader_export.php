<?php
declare(strict_types=1);

require_once __DIR__ . '/helpers.php';

header('Content-Type: application/json; charset=utf-8');
ini_set('memory_limit', '1024M');
set_time_limit(0);
error_reporting(E_ALL);
ini_set('display_errors', '1');

const TL_TARGET_TEAM_ID = 'team-LECUVITaSJWIyD8xNR79';
const TL_OPERATOR_MAP = [
    'c2a80468-0ae0-0060-b759-e7fdd186ce6b' => 'LkuRs07bTNdPZjGC7Z902cbLy883',
    'ad8760c2-f2fc-0e49-9f5e-ca0397e116ba' => 'JG5oh5q5axVBrtwYHKDwDc4jk7T2',
    '8df54a33-ba6d-0f4a-b549-43198dd2f6e8' => 'JpNmy5BGXLTGbFGqHtaHfKFbM2g2',
    'ba3dfb99-c488-06e9-9246-e095a6c2f6e9' => 'w8yaP4wTJPU65xQ6W7gOEzk7TXw2',
    '9abf09d6-78ad-0acb-b15c-9baafd74d28b' => 'VWNF38LuYbcg4c6LCbYbTWIQ7Gt2',
];

const TL_SKIPPED_MODULES = [
    'activity_types',
    'business_types',
    'closing_days',
    'commercial_discounts',
    'custom_field_definitions',
    'day_off_types',
    'deal_pipelines',
    'deal_sources',
    'departments',
    'lost_reasons',
    'payment_methods',
    'payment_terms',
    'price_lists',
    'product_categories',
    'tax_rates',
    'teams',
    'users',
    'units_of_measure',
    'webhooks',
    'withholding_tax_rates',
    'calls',
    'meetings',
];

function tl_bool($value): bool
{
    return in_array(trim((string)$value), ['1', 'true', 'yes', 'on'], true);
}

function tl_float($value): ?float
{
    if ($value === null) {
        return null;
    }
    $raw = trim((string)$value);
    if ($raw === '') {
        return null;
    }
    $normalized = str_replace(',', '.', $raw);
    return is_numeric($normalized) ? (float)$normalized : null;
}

function tl_int($value): ?int
{
    $float = tl_float($value);
    return $float === null ? null : (int)round($float);
}

function tl_datetime(?string $value): ?string
{
    $raw = trim((string)$value);
    if ($raw === '') {
        return null;
    }
    try {
        return (new DateTimeImmutable($raw))->format('Y-m-d H:i:s');
    } catch (Throwable $e) {
        return null;
    }
}

function tl_date(?string $value): ?string
{
    $dt = tl_datetime($value);
    return $dt === null ? null : substr($dt, 0, 10);
}

function tl_json_decode(?string $raw, $fallback = [])
{
    $value = trim((string)$raw);
    if ($value === '') {
        return $fallback;
    }
    $decoded = json_decode($value, true);
    return $decoded === null ? $fallback : $decoded;
}

function tl_primary_email(?string $raw): string
{
    $items = tl_json_decode($raw, []);
    if (!is_array($items)) {
        return '';
    }
    foreach ($items as $item) {
        if (!is_array($item)) {
            continue;
        }
        $email = trim((string)($item['email'] ?? ''));
        if ($email !== '') {
            return $email;
        }
    }
    return '';
}

function tl_primary_phone(?string $raw): string
{
    $items = tl_json_decode($raw, []);
    if (!is_array($items)) {
        return '';
    }
    foreach ($items as $item) {
        if (!is_array($item)) {
            continue;
        }
        $phone = trim((string)($item['number'] ?? $item['phone'] ?? ''));
        if ($phone !== '') {
            return $phone;
        }
    }
    return '';
}

function tl_tags(?string $raw): array
{
    $value = trim((string)$raw);
    if ($value === '') {
        return [];
    }
    $parts = preg_split('/\s*,\s*/', $value) ?: [];
    $parts = array_values(array_filter(array_map('trim', $parts), 'strlen'));
    return array_values(array_unique($parts));
}

function tl_status_map(array $map, ?string $raw, string $default): string
{
    $value = trim((string)$raw);
    return $map[$value] ?? $default;
}

function tl_contains(string $haystack, string $needle): bool
{
    return $needle !== '' && strpos($haystack, $needle) !== false;
}

function tl_csv_rows(string $path): Generator
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

function tl_debug_table(PDO $pdo, string $table): array
{
    $result = [
        'table' => $table,
        'createTable' => null,
        'checkConstraints' => [],
    ];

    try {
        $stmt = $pdo->query('SHOW CREATE TABLE `' . str_replace('`', '``', $table) . '`');
        $row = $stmt ? $stmt->fetch(PDO::FETCH_ASSOC) : null;
        if (is_array($row)) {
            $result['createTable'] = $row['Create Table'] ?? null;
        }
    } catch (Throwable $e) {
        $result['createTable'] = 'Errore SHOW CREATE TABLE: ' . $e->getMessage();
    }

    try {
        $stmt = $pdo->prepare(
            'SELECT cc.CONSTRAINT_NAME, cc.CHECK_CLAUSE
             FROM information_schema.CHECK_CONSTRAINTS cc
             INNER JOIN information_schema.TABLE_CONSTRAINTS tc
               ON tc.CONSTRAINT_NAME = cc.CONSTRAINT_NAME
              AND tc.CONSTRAINT_SCHEMA = cc.CONSTRAINT_SCHEMA
             WHERE tc.TABLE_SCHEMA = DATABASE()
               AND tc.TABLE_NAME = ?
               AND tc.CONSTRAINT_TYPE = \'CHECK\''
        );
        $stmt->execute([$table]);
        $result['checkConstraints'] = $stmt->fetchAll(PDO::FETCH_ASSOC) ?: [];
    } catch (Throwable $e) {
        $result['checkConstraints'] = [[
            'error' => 'Errore lettura vincoli: ' . $e->getMessage(),
        ]];
    }

    return $result;
}

function tl_table_columns(PDO $pdo, string $table): array
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

function tl_prepare_upsert(PDO $pdo, string $table, array $columns): PDOStatement
{
    $available = array_flip(tl_table_columns($pdo, $table));
    $filtered = array_values(array_filter($columns, static fn(string $column) => isset($available[$column])));
    if ($filtered === []) {
        throw new RuntimeException('Nessuna colonna valida per la tabella ' . $table);
    }
    $escapedColumns = array_map(
        static fn(string $column) => '`' . str_replace('`', '``', $column) . '`',
        $filtered
    );
    $placeholders = array_map(
        static fn(string $column) => ':' . $column,
        $filtered
    );
    $updates = [];
    foreach ($filtered as $column) {
        if ($column === 'id') {
            continue;
        }
        $escaped = '`' . str_replace('`', '``', $column) . '`';
        $updates[] = $escaped . '=VALUES(' . $escaped . ')';
    }
    $sql = 'INSERT INTO `' . $table . '` (' . implode(',', $escapedColumns) . ') VALUES (' . implode(',', $placeholders) . ')';
    if ($updates !== []) {
        $sql .= ' ON DUPLICATE KEY UPDATE ' . implode(',', $updates);
    }
    return $pdo->prepare($sql);
}

function tl_filter_params(array $params, array $allowedColumns): array
{
    $allowed = array_flip($allowedColumns);
    $filtered = [];
    foreach ($params as $key => $value) {
        $column = ltrim((string)$key, ':');
        if (isset($allowed[$column])) {
            $filtered[':' . $column] = $value;
        }
    }
    return $filtered;
}

function tl_inc(array &$summary, string $bucket, int $amount = 1): void
{
    $summary[$bucket] = ($summary[$bucket] ?? 0) + $amount;
}

function tl_warn(array &$summary, string $code, string $message, int $amount = 1): void
{
    if (!isset($summary['warnings'][$code])) {
        $summary['warnings'][$code] = ['message' => $message, 'count' => 0];
    }
    $summary['warnings'][$code]['count'] += $amount;
}

function tl_export_user_to_target(?string $exportUserId, string $defaultUserId, array &$summary, string $context): string
{
    $raw = trim((string)$exportUserId);
    if ($raw === '') {
        tl_warn($summary, 'missing_user', 'Record senza operatore sorgente: fallback al proprietario del team.');
        return $defaultUserId;
    }
    if (isset(TL_OPERATOR_MAP[$raw])) {
        $targetUserId = TL_OPERATOR_MAP[$raw];
        $allowedUserIds = $summary['allowedUserIds'] ?? [];
        if ($allowedUserIds !== [] && !in_array($targetUserId, $allowedUserIds, true)) {
            tl_warn(
                $summary,
                'target_user_not_in_team',
                'Alcuni operatori mappati non appartengono al team target: fallback al proprietario del team.'
            );
            if (!isset($summary['missingTargetUsers'][$targetUserId])) {
                $summary['missingTargetUsers'][$targetUserId] = [
                    'exportUsers' => [],
                    'contexts' => [],
                    'count' => 0,
                ];
            }
            $summary['missingTargetUsers'][$targetUserId]['count']++;
            $summary['missingTargetUsers'][$targetUserId]['exportUsers'][$raw] = true;
            $summary['missingTargetUsers'][$targetUserId]['contexts'][$context] = true;
            return $defaultUserId;
        }
        return $targetUserId;
    }
    tl_warn(
        $summary,
        'unknown_export_user',
        'Alcuni record usano operatori export non mappati: fallback al proprietario del team.'
    );
    if (!isset($summary['unknownUsers'][$raw])) {
        $summary['unknownUsers'][$raw] = ['contexts' => [], 'count' => 0];
    }
    $summary['unknownUsers'][$raw]['count']++;
    $summary['unknownUsers'][$raw]['contexts'][$context] = true;
    return $defaultUserId;
}

function tl_phase_color(string $status, string $name): string
{
    $lower = strtolower($name);
    if ($status === 'won' || tl_contains($lower, 'vint') || tl_contains($lower, 'won')) {
        return '#16a34a';
    }
    if ($status === 'lost' || tl_contains($lower, 'pers')) {
        return '#ef4444';
    }
    if ($status === 'quotation_send' || tl_contains($lower, 'preventiv') || tl_contains($lower, 'quot')) {
        return '#3b82f6';
    }
    if ($status === 'new' || tl_contains($lower, 'nuov')) {
        return '#94a3b8';
    }
    return '#0f766e';
}

function tl_build_lines(string $label, ?float $amount, string $currency, array $extra = []): string
{
    $line = array_merge([
        'description' => $label,
        'quantity' => 1,
        'unitPrice' => $amount ?? 0.0,
        'total' => $amount ?? 0.0,
        'currency' => $currency !== '' ? $currency : 'EUR',
    ], $extra);
    return json_encode([$line], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES) ?: '[]';
}

function tl_team_context(PDO $pdo, string $teamId): array
{
    $teamStmt = $pdo->prepare('SELECT id, owner_id, name FROM teams WHERE id = ? LIMIT 1');
    $teamStmt->execute([$teamId]);
    $team = $teamStmt->fetch(PDO::FETCH_ASSOC);
    if (!$team) {
        throw new RuntimeException('Team target non trovato: ' . $teamId);
    }

    $userStmt = $pdo->prepare('SELECT id FROM users WHERE team_id = ?');
    $userStmt->execute([$teamId]);
    $userIds = array_values(array_filter(array_map(
        static fn(array $row) => (string)($row['id'] ?? ''),
        $userStmt->fetchAll(PDO::FETCH_ASSOC) ?: []
    )));

    if ($userIds === []) {
        $memberStmt = $pdo->prepare(
            "SELECT user_id FROM team_members WHERE team_id = ? AND status = 'active'"
        );
        $memberStmt->execute([$teamId]);
        $userIds = array_values(array_filter(array_map(
            static fn(array $row) => (string)($row['user_id'] ?? ''),
            $memberStmt->fetchAll(PDO::FETCH_ASSOC) ?: []
        )));
    }

    if ($userIds === []) {
        throw new RuntimeException('Il team target non ha utenti associati.');
    }

    $defaultUserId = in_array((string)$team['owner_id'], $userIds, true)
        ? (string)$team['owner_id']
        : (array_values(array_unique(array_values(TL_OPERATOR_MAP)))[0] ?? $userIds[0]);

    return [
        'team' => $team,
        'userIds' => $userIds,
        'defaultUserId' => $defaultUserId,
    ];
}

function tl_sync_users_team_id(PDO $pdo, string $teamId, array $userIds): int
{
    if ($userIds === []) {
        return 0;
    }
    $placeholders = implode(',', array_fill(0, count($userIds), '?'));
    $sql = "UPDATE users SET team_id = ? WHERE id IN ($placeholders) AND (team_id IS NULL OR team_id = '')";
    $params = array_merge([$teamId], array_values($userIds));
    $stmt = $pdo->prepare($sql);
    $stmt->execute($params);
    return $stmt->rowCount();
}

function tl_prepare_summary(bool $run, string $teamId, array $teamContext): array
{
    $tables = [];
    foreach ([
        'companies',
        'contacts',
        'deal_stages',
        'deals',
        'quotations',
        'projects',
        'project_phases',
        'tickets',
        'work_tasks',
        'time_tracks',
        'invoice_drafts',
        'credit_notes',
        'products',
        'subscriptions',
    ] as $table) {
        $tables[$table] = ['processed' => 0, 'skipped' => 0];
    }
    return [
        'mode' => $run ? 'run' : 'dry-run',
        'teamId' => $teamId,
        'teamName' => (string)($teamContext['team']['name'] ?? ''),
        'defaultUserId' => (string)$teamContext['defaultUserId'],
        'allowedUserIds' => array_values($teamContext['userIds'] ?? []),
        'operatorMap' => TL_OPERATOR_MAP,
        'skippedModules' => TL_SKIPPED_MODULES,
        'tables' => $tables,
        'warnings' => [],
        'unknownUsers' => [],
        'missingTargetUsers' => [],
    ];
}

function tl_note(array $parts): string
{
    $clean = array_values(array_filter(array_map(
        static fn($item) => trim((string)$item),
        $parts
    ), 'strlen'));
    return implode("\n", $clean);
}

function tl_resolve_export_dir(): string
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

    throw new RuntimeException(
        'Cartella export non trovata. Percorsi provati: ' . implode(' | ', $candidates)
    );
}

$teamId = trim((string)($_GET['teamId'] ?? TL_TARGET_TEAM_ID));
$run = trim((string)($_GET['run'] ?? '')) === 'yes';
$summary = [
    'mode' => $run ? 'run' : 'dry-run',
    'teamId' => $teamId,
];

try {
    $pdo = db();
    $teamContext = tl_team_context($pdo, $teamId);
    $summary = tl_prepare_summary($run, $teamId, $teamContext);
    $defaultUserId = (string)$teamContext['defaultUserId'];
    $exportDir = tl_resolve_export_dir();
    $summary['exportDir'] = $exportDir;
    $summary['usersTeamIdSynced'] = tl_sync_users_team_id($pdo, $teamId, $teamContext['userIds']);

    $companyOwners = [];
    $contactCompanyMap = [];
    $dealOwners = [];
    $dealCustomerMap = [];
    $dealStageProbability = [];
    $projectInfo = [];
    $phaseInfo = [];
    $ticketCompanyMap = [];
    $taskInfo = [];
    $eventInfo = [];
    $taskLoggedHours = [];
    $invoiceIds = [];

    $pdo->beginTransaction();

    $companyStmt = $pdo->prepare(
        'INSERT INTO companies (
            id,user_id,name,vat_number,tax_code,pec,sdi_code,email,phone,website,address_line,city,postal_code,country,
            contact_person,notes,company_type,aree_investimento,ricavi_annui,created_at,updated_at
        ) VALUES (
            :id,:user_id,:name,:vat_number,:tax_code,:pec,:sdi_code,:email,:phone,:website,:address_line,:city,:postal_code,:country,
            :contact_person,:notes,:company_type,:aree_investimento,:ricavi_annui,:created_at,:updated_at
        ) ON DUPLICATE KEY UPDATE
            user_id=VALUES(user_id),
            name=VALUES(name),
            vat_number=VALUES(vat_number),
            tax_code=VALUES(tax_code),
            pec=VALUES(pec),
            sdi_code=VALUES(sdi_code),
            email=VALUES(email),
            phone=VALUES(phone),
            website=VALUES(website),
            address_line=VALUES(address_line),
            city=VALUES(city),
            postal_code=VALUES(postal_code),
            country=VALUES(country),
            contact_person=VALUES(contact_person),
            notes=VALUES(notes),
            company_type=VALUES(company_type),
            aree_investimento=VALUES(aree_investimento),
            ricavi_annui=VALUES(ricavi_annui),
            updated_at=VALUES(updated_at)'
    );

    foreach (tl_csv_rows($exportDir . '/companies.csv') as $row) {
        $userId = tl_export_user_to_target($row['responsible_user.id'] ?? '', $defaultUserId, $summary, 'companies');
        $companyId = trim((string)($row['id'] ?? ''));
        if ($companyId === '') {
            tl_inc($summary['tables']['companies'], 'skipped');
            continue;
        }
        $notes = tl_note([
            ($row['activity_code'] ?? '') !== '' ? 'Codice attività: ' . $row['activity_code'] : '',
            ($row['status'] ?? '') !== '' && $row['status'] !== 'active' ? 'Stato sorgente: ' . $row['status'] : '',
            ($row['tags'] ?? '') !== '' ? 'Tag: ' . $row['tags'] : '',
            ($row['web_url'] ?? '') !== '' ? 'Sorgente Teamleader: ' . $row['web_url'] : '',
        ]);
        $companyStmt->execute([
            ':id' => $companyId,
            ':user_id' => $userId,
            ':name' => trim((string)($row['name'] ?? '')),
            ':vat_number' => trim((string)($row['vat_number'] ?? '')),
            ':tax_code' => trim((string)($row['national_identification_number'] ?? '')),
            ':pec' => trim((string)($row['invoicing_preferences.electronic_invoicing_address'] ?? '')),
            ':sdi_code' => '',
            ':email' => tl_primary_email($row['emails'] ?? ''),
            ':phone' => tl_primary_phone($row['telephones'] ?? ''),
            ':website' => trim((string)($row['website'] ?? $row['web_url'] ?? '')),
            ':address_line' => trim((string)($row['primary_address.line_1'] ?? '')),
            ':city' => trim((string)($row['primary_address.city'] ?? '')),
            ':postal_code' => trim((string)($row['primary_address.postal_code'] ?? '')),
            ':country' => trim((string)($row['primary_address.country'] ?? '')) ?: 'IT',
            ':contact_person' => '',
            ':notes' => $notes,
            ':company_type' => 'profit',
            ':aree_investimento' => '[]',
            ':ricavi_annui' => '{}',
            ':created_at' => tl_datetime($row['added_at'] ?? '') ?? date('Y-m-d H:i:s'),
            ':updated_at' => tl_datetime($row['updated_at'] ?? '') ?? date('Y-m-d H:i:s'),
        ]);
        $companyOwners[$companyId] = $userId;
        if (!isset($summary['tables']['companies'])) {
            $summary['tables']['companies'] = ['processed' => 0, 'skipped' => 0];
        }
        $summary['tables']['companies']['processed']++;
    }

    $companyContactStmt = $pdo->prepare(
        'INSERT INTO company_contacts (
            id,user_id,company_id,name,email,phone,role,created_at,updated_at
        ) VALUES (
            :id,:user_id,:company_id,:name,:email,:phone,:role,:created_at,:updated_at
        ) ON DUPLICATE KEY UPDATE
            user_id=VALUES(user_id),
            company_id=VALUES(company_id),
            name=VALUES(name),
            email=VALUES(email),
            phone=VALUES(phone),
            role=VALUES(role),
            updated_at=VALUES(updated_at)'
    );
    $crmContactStmt = $pdo->prepare(
        'INSERT INTO crm_contacts (
            id,user_id,first_name,last_name,company_id,email,phone,role,tags,assigned_to,notes,created_at,updated_at
        ) VALUES (
            :id,:user_id,:first_name,:last_name,:company_id,:email,:phone,:role,:tags,:assigned_to,:notes,:created_at,:updated_at
        ) ON DUPLICATE KEY UPDATE
            user_id=VALUES(user_id),
            first_name=VALUES(first_name),
            last_name=VALUES(last_name),
            company_id=VALUES(company_id),
            email=VALUES(email),
            phone=VALUES(phone),
            role=VALUES(role),
            tags=VALUES(tags),
            assigned_to=VALUES(assigned_to),
            notes=VALUES(notes),
            updated_at=VALUES(updated_at)'
    );

    foreach (tl_csv_rows($exportDir . '/contacts.csv') as $row) {
        $contactId = trim((string)($row['id'] ?? ''));
        if ($contactId === '') {
            tl_inc($summary['tables']['contacts'], 'skipped');
            continue;
        }
        $userId = $defaultUserId;
        $firstName = trim((string)($row['first_name'] ?? ''));
        $lastName = trim((string)($row['last_name'] ?? ''));
        $name = trim($firstName . ' ' . $lastName);
        if ($name === '') {
            $name = trim((string)($row['emails'] ?? '')) !== '' ? tl_primary_email($row['emails'] ?? '') : 'Contatto importato';
        }
        $notes = tl_note([
            ($row['status'] ?? '') !== '' && $row['status'] !== 'active' ? 'Stato sorgente: ' . $row['status'] : '',
            ($row['website'] ?? '') !== '' ? 'Website: ' . $row['website'] : '',
            ($row['vat_number'] ?? '') !== '' ? 'P.IVA sorgente: ' . $row['vat_number'] : '',
        ]);
        $email = tl_primary_email($row['emails'] ?? '');
        $phone = tl_primary_phone($row['telephones'] ?? '');
        $companyContactStmt->execute([
            ':id' => $contactId,
            ':user_id' => $userId,
            ':company_id' => null,
            ':name' => $name,
            ':email' => $email,
            ':phone' => $phone,
            ':role' => '',
            ':created_at' => tl_datetime($row['added_at'] ?? '') ?? date('Y-m-d H:i:s'),
            ':updated_at' => tl_datetime($row['updated_at'] ?? '') ?? date('Y-m-d H:i:s'),
        ]);
        $crmContactStmt->execute([
            ':id' => $contactId,
            ':user_id' => $userId,
            ':first_name' => $firstName,
            ':last_name' => $lastName,
            ':company_id' => null,
            ':email' => $email,
            ':phone' => $phone,
            ':role' => '',
            ':tags' => json_encode(tl_tags($row['tags'] ?? ''), JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES) ?: '[]',
            ':assigned_to' => null,
            ':notes' => $notes,
            ':created_at' => tl_datetime($row['added_at'] ?? '') ?? date('Y-m-d H:i:s'),
            ':updated_at' => tl_datetime($row['updated_at'] ?? '') ?? date('Y-m-d H:i:s'),
        ]);
        $contactCompanyMap[$contactId] = null;
        if (!isset($summary['tables']['contacts'])) {
            $summary['tables']['contacts'] = ['processed' => 0, 'skipped' => 0];
        }
        $summary['tables']['contacts']['processed']++;
    }

    $stageStmt = $pdo->prepare(
        'INSERT INTO deal_stages (id,user_id,name,stage_order,color_hex,probability,created_at)
         VALUES (:id,:user_id,:name,:stage_order,:color_hex,:probability,:created_at)
         ON DUPLICATE KEY UPDATE
            user_id=VALUES(user_id),
            name=VALUES(name),
            stage_order=VALUES(stage_order),
            color_hex=VALUES(color_hex),
            probability=VALUES(probability)'
    );
    $stageOrder = 0;
    foreach (tl_csv_rows($exportDir . '/deal_phases.csv') as $row) {
        $stageId = trim((string)($row['id'] ?? ''));
        if ($stageId === '') {
            tl_inc($summary['tables']['deal_stages'], 'skipped');
            continue;
        }
        $probability = (int)round((tl_float($row['probability'] ?? '') ?? 0) * 100);
        $stageStmt->execute([
            ':id' => $stageId,
            ':user_id' => $defaultUserId,
            ':name' => trim((string)($row['name'] ?? 'Fase importata')),
            ':stage_order' => $stageOrder++,
            ':color_hex' => tl_phase_color((string)($row['status'] ?? ''), (string)($row['name'] ?? '')),
            ':probability' => $probability,
            ':created_at' => date('Y-m-d H:i:s'),
        ]);
        $dealStageProbability[$stageId] = $probability;
        if (!isset($summary['tables']['deal_stages'])) {
            $summary['tables']['deal_stages'] = ['processed' => 0, 'skipped' => 0];
        }
        $summary['tables']['deal_stages']['processed']++;
    }

    $dealStmt = $pdo->prepare(
        'INSERT INTO deals (
            id,user_id,title,stage_id,status,value,currency,customer_id,customer_type,probability,expected_closing_date,assigned_to,notes,created_at,updated_at
        ) VALUES (
            :id,:user_id,:title,:stage_id,:status,:value,:currency,:customer_id,:customer_type,:probability,:expected_closing_date,:assigned_to,:notes,:created_at,:updated_at
        ) ON DUPLICATE KEY UPDATE
            user_id=VALUES(user_id),
            title=VALUES(title),
            stage_id=VALUES(stage_id),
            status=VALUES(status),
            value=VALUES(value),
            currency=VALUES(currency),
            customer_id=VALUES(customer_id),
            customer_type=VALUES(customer_type),
            probability=VALUES(probability),
            expected_closing_date=VALUES(expected_closing_date),
            assigned_to=VALUES(assigned_to),
            notes=VALUES(notes),
            updated_at=VALUES(updated_at)'
    );
    foreach (tl_csv_rows($exportDir . '/deals.csv') as $row) {
        $dealId = trim((string)($row['id'] ?? ''));
        if ($dealId === '') {
            tl_inc($summary['tables']['deals'], 'skipped');
            continue;
        }
        $userId = tl_export_user_to_target($row['responsible_user.id'] ?? '', $defaultUserId, $summary, 'deals');
        $stageId = trim((string)($row['current_phase.id'] ?? '')) ?: null;
        $status = tl_status_map([
            'won' => 'won',
            'lost' => 'lost',
            'open' => 'open',
            'new' => 'open',
        ], $row['status'] ?? '', 'open');
        $notes = tl_note([
            ($row['source.id'] ?? '') !== '' ? 'Source ID: ' . $row['source.id'] : '',
            ($row['purchase_order_number'] ?? '') !== '' ? 'PO: ' . $row['purchase_order_number'] : '',
            ($row['weighted_value.amount'] ?? '') !== '' ? 'Valore ponderato: ' . $row['weighted_value.amount'] . ' ' . ($row['weighted_value.currency'] ?? 'EUR') : '',
        ]);
        $dealStmt->execute([
            ':id' => $dealId,
            ':user_id' => $userId,
            ':title' => trim((string)($row['title'] ?? 'Deal importato')),
            ':stage_id' => $stageId,
            ':status' => $status,
            ':value' => tl_float($row['estimated_value.amount'] ?? '') ?? 0.0,
            ':currency' => trim((string)($row['estimated_value.currency'] ?? 'EUR')) ?: 'EUR',
            ':customer_id' => trim((string)($row['lead.customer.id'] ?? '')) ?: null,
            ':customer_type' => trim((string)($row['lead.customer.type'] ?? '')) ?: null,
            ':probability' => $stageId !== null ? ($dealStageProbability[$stageId] ?? 0) : 0,
            ':expected_closing_date' => tl_date($row['estimated_closing_date'] ?? ''),
            ':assigned_to' => $userId,
            ':notes' => $notes,
            ':created_at' => tl_datetime($row['added_at'] ?? '') ?? tl_datetime($row['updated_at'] ?? '') ?? date('Y-m-d H:i:s'),
            ':updated_at' => tl_datetime($row['updated_at'] ?? '') ?? date('Y-m-d H:i:s'),
        ]);
        $dealOwners[$dealId] = $userId;
        $dealCustomerMap[$dealId] = [
            'customer_id' => trim((string)($row['lead.customer.id'] ?? '')) ?: null,
            'customer_type' => trim((string)($row['lead.customer.type'] ?? '')) ?: null,
        ];
        if (!isset($summary['tables']['deals'])) {
            $summary['tables']['deals'] = ['processed' => 0, 'skipped' => 0];
        }
        $summary['tables']['deals']['processed']++;
    }

    $quotationStmt = $pdo->prepare(
        'INSERT INTO quotations (
            id,user_id,number,status,`lines`,customer_id,customer_type,deal_id,currency,valid_until,notes,created_at,updated_at
        ) VALUES (
            :id,:user_id,:number,:status,:lines,:customer_id,:customer_type,:deal_id,:currency,:valid_until,:notes,:created_at,:updated_at
        ) ON DUPLICATE KEY UPDATE
            user_id=VALUES(user_id),
            number=VALUES(number),
            status=VALUES(status),
            `lines`=VALUES(`lines`),
            customer_id=VALUES(customer_id),
            customer_type=VALUES(customer_type),
            deal_id=VALUES(deal_id),
            currency=VALUES(currency),
            valid_until=VALUES(valid_until),
            notes=VALUES(notes),
            updated_at=VALUES(updated_at)'
    );
    foreach (tl_csv_rows($exportDir . '/quotations.csv') as $row) {
        $quotationId = trim((string)($row['id'] ?? ''));
        if ($quotationId === '') {
            tl_inc($summary['tables']['quotations'], 'skipped');
            continue;
        }
        $dealId = trim((string)($row['deal.id'] ?? ''));
        $userId = $dealId !== '' && isset($dealOwners[$dealId]) ? $dealOwners[$dealId] : $defaultUserId;
        $customerInfo = $dealId !== '' && isset($dealCustomerMap[$dealId])
            ? $dealCustomerMap[$dealId]
            : ['customer_id' => null, 'customer_type' => null];
        $currency = trim((string)($row['total.tax_inclusive.currency'] ?? $row['total.tax_exclusive.currency'] ?? 'EUR')) ?: 'EUR';
        $quotationStmt->execute([
            ':id' => $quotationId,
            ':user_id' => $userId,
            ':number' => trim((string)($row['name'] ?? 'Preventivo importato')),
            ':status' => tl_status_map([
                'open' => 'sent',
                'accepted' => 'accepted',
                'expired' => 'rejected',
                'draft' => 'draft',
            ], $row['status'] ?? '', 'draft'),
            ':lines' => tl_build_lines(
                trim((string)($row['name'] ?? 'Preventivo')),
                tl_float($row['total.tax_exclusive.amount'] ?? ''),
                $currency
            ),
            ':customer_id' => $customerInfo['customer_id'],
            ':customer_type' => $customerInfo['customer_type'],
            ':deal_id' => $dealId !== '' ? $dealId : null,
            ':currency' => $currency,
            ':valid_until' => null,
            ':notes' => tl_note([
                ($row['status'] ?? '') !== '' ? 'Stato sorgente: ' . $row['status'] : '',
                ($row['total.tax_inclusive.amount'] ?? '') !== '' ? 'Totale ivato: ' . $row['total.tax_inclusive.amount'] . ' ' . $currency : '',
            ]),
            ':created_at' => tl_datetime($row['created_at'] ?? '') ?? date('Y-m-d H:i:s'),
            ':updated_at' => tl_datetime($row['updated_at'] ?? '') ?? date('Y-m-d H:i:s'),
        ]);
        if (!isset($summary['tables']['quotations'])) {
            $summary['tables']['quotations'] = ['processed' => 0, 'skipped' => 0];
        }
        $summary['tables']['quotations']['processed']++;
    }

    $projectColumns = [
        'id',
        'user_id',
        'company_id',
        'name',
        'code',
        'status',
        'type',
        'deal_id',
        'notes',
        'data_inizio_progetto',
        'data_fine_progetto',
        'created_at',
        'updated_at',
        'closed_at',
    ];
    $projectStmt = tl_prepare_upsert($pdo, 'projects', $projectColumns);
    $projectAllowedColumns = tl_table_columns($pdo, 'projects');
    foreach (tl_csv_rows($exportDir . '/projects_legacy.csv') as $row) {
        $projectId = trim((string)($row['id'] ?? ''));
        if ($projectId === '') {
            tl_inc($summary['tables']['projects'], 'skipped');
            continue;
        }
        $companyId = trim((string)($row['customer.id'] ?? ''));
        $dealId = trim((string)($row['source.id'] ?? ''));
        $userId = $companyId !== '' && isset($companyOwners[$companyId])
            ? $companyOwners[$companyId]
            : ($dealId !== '' && isset($dealOwners[$dealId]) ? $dealOwners[$dealId] : $defaultUserId);
        $status = trim((string)($row['status'] ?? 'planning')) ?: 'planning';
        $projectStmt->execute(tl_filter_params([
            ':id' => $projectId,
            ':user_id' => $userId,
            ':company_id' => $companyId !== '' ? $companyId : null,
            ':name' => trim((string)($row['title'] ?? 'Progetto importato')),
            ':code' => trim((string)($row['reference'] ?? '')),
            ':status' => $status,
            ':type' => 'profit',
            ':deal_id' => $dealId !== '' ? $dealId : null,
            ':notes' => tl_note([
                trim((string)($row['description'] ?? '')),
                ($row['source.id'] ?? '') !== '' ? 'Deal sorgente: ' . $row['source.id'] : '',
            ]),
            ':data_inizio_progetto' => tl_date($row['starts_on'] ?? ''),
            ':data_fine_progetto' => tl_date($row['due_on'] ?? ''),
            ':created_at' => tl_datetime($row['created_at'] ?? '') ?? date('Y-m-d H:i:s'),
            ':updated_at' => tl_datetime($row['created_at'] ?? '') ?? date('Y-m-d H:i:s'),
            ':closed_at' => in_array($status, ['done', 'cancelled'], true)
                ? (tl_datetime($row['due_on'] ?? '') ?? tl_datetime($row['created_at'] ?? ''))
                : null,
        ], $projectAllowedColumns));
        $projectInfo[$projectId] = [
            'company_id' => $companyId,
            'user_id' => $userId,
        ];
        if (!isset($summary['tables']['projects'])) {
            $summary['tables']['projects'] = ['processed' => 0, 'skipped' => 0];
        }
        $summary['tables']['projects']['processed']++;
    }

    $phaseStmt = $pdo->prepare(
        'INSERT INTO project_phases (
            id,user_id,project_id,name,phase_order,status,assigned_user_id,start_date,deadline,notes,is_custom,created_at,updated_at
        ) VALUES (
            :id,:user_id,:project_id,:name,:phase_order,:status,:assigned_user_id,:start_date,:deadline,:notes,:is_custom,:created_at,:updated_at
        ) ON DUPLICATE KEY UPDATE
            user_id=VALUES(user_id),
            project_id=VALUES(project_id),
            name=VALUES(name),
            phase_order=VALUES(phase_order),
            status=VALUES(status),
            assigned_user_id=VALUES(assigned_user_id),
            start_date=VALUES(start_date),
            deadline=VALUES(deadline),
            notes=VALUES(notes),
            is_custom=VALUES(is_custom),
            updated_at=VALUES(updated_at)'
    );
    $phaseOrderByProject = [];
    foreach (tl_csv_rows($exportDir . '/milestones_legacy.csv') as $row) {
        $phaseId = trim((string)($row['id'] ?? ''));
        $projectId = trim((string)($row['project.id'] ?? ''));
        if ($phaseId === '' || $projectId === '' || !isset($projectInfo[$projectId])) {
            tl_inc($summary['tables']['project_phases'], 'skipped');
            continue;
        }
        $projectUserId = $projectInfo[$projectId]['user_id'];
        $assignedUserId = tl_export_user_to_target($row['responsible_user.id'] ?? '', $projectUserId, $summary, 'project_phases');
        $phaseOrderByProject[$projectId] = ($phaseOrderByProject[$projectId] ?? 0) + 1;
        $phaseStmt->execute([
            ':id' => $phaseId,
            ':user_id' => $projectUserId,
            ':project_id' => $projectId,
            ':name' => trim((string)($row['name'] ?? 'Fase importata')),
            ':phase_order' => $phaseOrderByProject[$projectId],
            ':status' => ($row['status'] ?? '') === 'closed' ? 'done' : 'inProgress',
            ':assigned_user_id' => $assignedUserId,
            ':start_date' => tl_date($row['starts_on'] ?? ''),
            ':deadline' => tl_date($row['due_on'] ?? ''),
            ':notes' => tl_note([
                ($row['budget.forecasted.amount'] ?? '') !== '' ? 'Budget previsto: ' . $row['budget.forecasted.amount'] . ' ' . ($row['budget.forecasted.currency'] ?? 'EUR') : '',
                ($row['actuals.billable_amount.amount'] ?? '') !== '' ? 'Consuntivo fatturabile: ' . $row['actuals.billable_amount.amount'] . ' ' . ($row['actuals.billable_amount.currency'] ?? 'EUR') : '',
            ]),
            ':is_custom' => 1,
            ':created_at' => date('Y-m-d H:i:s'),
            ':updated_at' => date('Y-m-d H:i:s'),
        ]);
        $phaseInfo[$phaseId] = [
            'project_id' => $projectId,
            'company_id' => $projectInfo[$projectId]['company_id'],
            'user_id' => $projectUserId,
        ];
        if (!isset($summary['tables']['project_phases'])) {
            $summary['tables']['project_phases'] = ['processed' => 0, 'skipped' => 0];
        }
        $summary['tables']['project_phases']['processed']++;
    }

    $ticketStatusMap = [];
    foreach (tl_csv_rows($exportDir . '/ticket_status.csv') as $row) {
        $ticketStatusMap[trim((string)($row['id'] ?? ''))] = trim((string)($row['status'] ?? ''));
    }

    $ticketStmt = $pdo->prepare(
        'INSERT INTO tickets (
            id,user_id,company_id,title,recipient_email,status,entries,created_at,updated_at
        ) VALUES (
            :id,:user_id,:company_id,:title,:recipient_email,:status,:entries,:created_at,:updated_at
        ) ON DUPLICATE KEY UPDATE
            user_id=VALUES(user_id),
            company_id=VALUES(company_id),
            title=VALUES(title),
            recipient_email=VALUES(recipient_email),
            status=VALUES(status),
            entries=VALUES(entries),
            updated_at=VALUES(updated_at)'
    );
    foreach (tl_csv_rows($exportDir . '/tickets.csv') as $row) {
        $ticketId = trim((string)($row['id'] ?? ''));
        if ($ticketId === '') {
            tl_inc($summary['tables']['tickets'], 'skipped');
            continue;
        }
        $assigneeId = tl_export_user_to_target($row['assignee.id'] ?? '', $defaultUserId, $summary, 'tickets');
        $companyId = '';
        if (($row['participant.customer.type'] ?? '') === 'company') {
            $companyId = trim((string)($row['participant.customer.id'] ?? ''));
        } elseif (($row['customer.type'] ?? '') === 'company') {
            $companyId = trim((string)($row['customer.id'] ?? ''));
        }
        $statusKey = $ticketStatusMap[trim((string)($row['status.id'] ?? ''))] ?? 'open';
        $ticketStmt->execute([
            ':id' => $ticketId,
            ':user_id' => $assigneeId,
            ':company_id' => $companyId,
            ':title' => trim((string)($row['subject'] ?? 'Ticket importato')),
            ':recipient_email' => '',
            ':status' => tl_status_map([
                'new' => 'newTicket',
                'open' => 'open',
                'waiting_for_client' => 'waitingCustomer',
                'escalated_thirdparty' => 'open',
                'closed' => 'closed',
            ], $statusKey, 'open'),
            ':entries' => json_encode([[
                'type' => 'import',
                'reference' => trim((string)($row['reference'] ?? '')),
                'sourceStatus' => $statusKey,
            ]], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES),
            ':created_at' => tl_datetime($row['created_at'] ?? '') ?? date('Y-m-d H:i:s'),
            ':updated_at' => tl_datetime($row['last_message_at'] ?? $row['closed_at'] ?? $row['created_at'] ?? '') ?? date('Y-m-d H:i:s'),
        ]);
        $ticketCompanyMap[$ticketId] = [
            'company_id' => $companyId,
            'user_id' => $assigneeId,
        ];
        if (!isset($summary['tables']['tickets'])) {
            $summary['tables']['tickets'] = ['processed' => 0, 'skipped' => 0];
        }
        $summary['tables']['tickets']['processed']++;
    }

    $taskStmt = $pdo->prepare(
        'INSERT INTO work_tasks (
            id,user_id,company_id,project_id,phase_id,assignee_id,name,estimated_hours,logged_hours,start_date,deadline,status,billable,description,created_at,updated_at
        ) VALUES (
            :id,:user_id,:company_id,:project_id,:phase_id,:assignee_id,:name,:estimated_hours,:logged_hours,:start_date,:deadline,:status,:billable,:description,:created_at,:updated_at
        ) ON DUPLICATE KEY UPDATE
            user_id=VALUES(user_id),
            company_id=VALUES(company_id),
            project_id=VALUES(project_id),
            phase_id=VALUES(phase_id),
            assignee_id=VALUES(assignee_id),
            name=VALUES(name),
            estimated_hours=VALUES(estimated_hours),
            start_date=VALUES(start_date),
            deadline=VALUES(deadline),
            status=VALUES(status),
            billable=VALUES(billable),
            description=VALUES(description),
            updated_at=VALUES(updated_at)'
    );
    foreach (tl_csv_rows($exportDir . '/tasks_legacy.csv') as $row) {
        $taskId = trim((string)($row['id'] ?? ''));
        if ($taskId === '') {
            tl_inc($summary['tables']['work_tasks'], 'skipped');
            continue;
        }
        $projectId = trim((string)($row['project.id'] ?? ''));
        $phaseId = trim((string)($row['milestone.id'] ?? ''));
        $ticketId = trim((string)($row['ticket.id'] ?? ''));
        $projectCompanyId = $projectId !== '' && isset($projectInfo[$projectId])
            ? $projectInfo[$projectId]['company_id']
            : '';
        $companyId = $projectCompanyId;
        if ($companyId === '' && ($row['customer.type'] ?? '') === 'company') {
            $companyId = trim((string)($row['customer.id'] ?? ''));
        }
        if ($companyId === '' && $ticketId !== '' && isset($ticketCompanyMap[$ticketId])) {
            $companyId = $ticketCompanyMap[$ticketId]['company_id'];
        }
        $taskOwner = $projectId !== '' && isset($projectInfo[$projectId])
            ? $projectInfo[$projectId]['user_id']
            : ($ticketId !== '' && isset($ticketCompanyMap[$ticketId])
                ? $ticketCompanyMap[$ticketId]['user_id']
                : $defaultUserId);
        $assigneeId = tl_export_user_to_target($row['assignee.id'] ?? '', $taskOwner, $summary, 'work_tasks');
        $estimatedMinutes = tl_float($row['estimated_duration.value'] ?? '') ?? 0.0;
        $estimatedHours = ($row['estimated_duration.unit'] ?? '') === 'min'
            ? $estimatedMinutes / 60
            : $estimatedMinutes;
        $startDate = tl_date($row['added_at'] ?? '') ?? tl_date($row['due_on'] ?? '') ?? date('Y-m-d');
        $deadline = tl_date($row['due_on'] ?? '') ?? $startDate;
        $status = tl_bool($row['completed'] ?? false)
            ? 'done'
            : ($projectId === '' && $phaseId === '' ? 'backlog' : 'planned');
        $taskStmt->execute([
            ':id' => $taskId,
            ':user_id' => $taskOwner,
            ':company_id' => $companyId,
            ':project_id' => $projectId,
            ':phase_id' => $phaseId,
            ':assignee_id' => $assigneeId,
            ':name' => trim((string)($row['title'] ?? 'Task importato')),
            ':estimated_hours' => round($estimatedHours, 2),
            ':logged_hours' => 0,
            ':start_date' => $startDate,
            ':deadline' => $deadline,
            ':status' => $status,
            ':billable' => 1,
            ':description' => trim((string)($row['description'] ?? '')),
            ':created_at' => tl_datetime($row['added_at'] ?? '') ?? date('Y-m-d H:i:s'),
            ':updated_at' => tl_datetime($row['completed_at'] ?? $row['added_at'] ?? '') ?? date('Y-m-d H:i:s'),
        ]);
        $taskInfo[$taskId] = [
            'company_id' => $companyId,
            'project_id' => $projectId,
            'phase_id' => $phaseId,
            'user_id' => $taskOwner,
            'name' => trim((string)($row['title'] ?? 'Task importato')),
        ];
        if (!isset($summary['tables']['work_tasks'])) {
            $summary['tables']['work_tasks'] = ['processed' => 0, 'skipped' => 0];
        }
        $summary['tables']['work_tasks']['processed']++;
    }

    foreach (tl_csv_rows($exportDir . '/events.csv') as $row) {
        $eventId = trim((string)($row['id'] ?? ''));
        if ($eventId === '') {
            continue;
        }
        $eventInfo[$eventId] = [
            'task_id' => trim((string)($row['task.id'] ?? '')),
            'title' => trim((string)($row['title'] ?? '')),
            'starts_at' => tl_datetime($row['starts_at'] ?? ''),
            'ends_at' => tl_datetime($row['ends_at'] ?? ''),
            'creator_id' => tl_export_user_to_target($row['creator.id'] ?? '', $defaultUserId, $summary, 'events_helper'),
        ];
    }

    $timeTrackStmt = $pdo->prepare(
        'INSERT INTO time_tracks (
            id,user_id,task_id,name,company_id,project_id,start_at,end_at,tracker_user_id,description,billable,tipo,hourly_rate,created_at,updated_at
        ) VALUES (
            :id,:user_id,:task_id,:name,:company_id,:project_id,:start_at,:end_at,:tracker_user_id,:description,:billable,:tipo,:hourly_rate,:created_at,:updated_at
        ) ON DUPLICATE KEY UPDATE
            user_id=VALUES(user_id),
            task_id=VALUES(task_id),
            name=VALUES(name),
            company_id=VALUES(company_id),
            project_id=VALUES(project_id),
            start_at=VALUES(start_at),
            end_at=VALUES(end_at),
            tracker_user_id=VALUES(tracker_user_id),
            description=VALUES(description),
            billable=VALUES(billable),
            tipo=VALUES(tipo),
            hourly_rate=VALUES(hourly_rate),
            updated_at=VALUES(updated_at)'
    );
    foreach (tl_csv_rows($exportDir . '/time_tracking.csv') as $row) {
        $trackId = trim((string)($row['id'] ?? ''));
        if ($trackId === '') {
            tl_inc($summary['tables']['time_tracks'], 'skipped');
            continue;
        }
        $trackerUserId = tl_export_user_to_target($row['user.id'] ?? '', $defaultUserId, $summary, 'time_tracks');
        $subjectType = trim((string)($row['subject.type'] ?? ''));
        $subjectId = trim((string)($row['subject.id'] ?? ''));
        $taskId = '';
        $companyId = '';
        $projectId = '';
        $name = trim((string)($row['description'] ?? ''));

        if ($subjectType === 'todo' && isset($taskInfo[$subjectId])) {
            $taskId = $subjectId;
        } elseif ($subjectType === 'event' && isset($eventInfo[$subjectId])) {
            $taskId = trim((string)($eventInfo[$subjectId]['task_id'] ?? ''));
            if ($name === '') {
                $name = trim((string)($eventInfo[$subjectId]['title'] ?? ''));
            }
        }

        if ($taskId !== '' && isset($taskInfo[$taskId])) {
            $companyId = (string)$taskInfo[$taskId]['company_id'];
            $projectId = (string)$taskInfo[$taskId]['project_id'];
            if ($name === '') {
                $name = (string)$taskInfo[$taskId]['name'];
            }
        } elseif ($subjectType === 'company' && $subjectId !== '') {
            $companyId = $subjectId;
            $projectId = '';
            if ($name === '') {
                $name = 'Attività azienda';
            }
        } elseif ($subjectType === 'milestone' && isset($phaseInfo[$subjectId])) {
            $companyId = (string)$phaseInfo[$subjectId]['company_id'];
            $projectId = (string)$phaseInfo[$subjectId]['project_id'];
            if ($name === '') {
                $name = 'Attività fase';
            }
        } elseif ($subjectType === 'ticket' && isset($ticketCompanyMap[$subjectId])) {
            $companyId = (string)$ticketCompanyMap[$subjectId]['company_id'];
            if ($name === '') {
                $name = 'Attività ticket';
            }
        } elseif ($name === '') {
            $name = 'Segnatempo importato';
        }

        $startAt = tl_datetime($row['started_at'] ?? $row['started_on'] ?? '') ?? date('Y-m-d H:i:s');
        $endAt = tl_datetime($row['ended_at'] ?? '') ?? $startAt;
        $timeTrackStmt->execute([
            ':id' => $trackId,
            ':user_id' => $trackerUserId,
            ':task_id' => $taskId,
            ':name' => $name,
            ':company_id' => $companyId,
            ':project_id' => $projectId,
            ':start_at' => $startAt,
            ':end_at' => $endAt,
            ':tracker_user_id' => $trackerUserId,
            ':description' => trim((string)($row['description'] ?? '')),
            ':billable' => tl_bool($row['invoiceable'] ?? false) ? 1 : 0,
            ':tipo' => trim((string)($row['work_type'] ?? $row['work_type.id'] ?? $subjectType)),
            ':hourly_rate' => tl_float($row['hourly_rate.amount'] ?? ''),
            ':created_at' => $startAt,
            ':updated_at' => $endAt,
        ]);
        if ($taskId !== '') {
            $durationSeconds = tl_float($row['duration'] ?? '') ?? 0.0;
            $taskLoggedHours[$taskId] = ($taskLoggedHours[$taskId] ?? 0.0) + ($durationSeconds / 3600);
        }
        if (!isset($summary['tables']['time_tracks'])) {
            $summary['tables']['time_tracks'] = ['processed' => 0, 'skipped' => 0];
        }
        $summary['tables']['time_tracks']['processed']++;
    }

    if ($taskLoggedHours !== []) {
        $updateLoggedStmt = $pdo->prepare(
            'UPDATE work_tasks SET logged_hours = :logged_hours WHERE id = :id'
        );
        foreach ($taskLoggedHours as $taskId => $loggedHours) {
            $updateLoggedStmt->execute([
                ':logged_hours' => round($loggedHours, 2),
                ':id' => $taskId,
            ]);
        }
    }

    $invoiceStmt = $pdo->prepare(
        'INSERT INTO invoice_drafts (
            id,user_id,company_id,number,amount,status,project_id,`lines`,is_success_fee,grant_amount,notes,sent_at,created_at,updated_at
        ) VALUES (
            :id,:user_id,:company_id,:number,:amount,:status,:project_id,:lines,:is_success_fee,:grant_amount,:notes,:sent_at,:created_at,:updated_at
        ) ON DUPLICATE KEY UPDATE
            user_id=VALUES(user_id),
            company_id=VALUES(company_id),
            number=VALUES(number),
            amount=VALUES(amount),
            status=VALUES(status),
            project_id=VALUES(project_id),
            `lines`=VALUES(`lines`),
            is_success_fee=VALUES(is_success_fee),
            grant_amount=VALUES(grant_amount),
            notes=VALUES(notes),
            sent_at=VALUES(sent_at),
            updated_at=VALUES(updated_at)'
    );
    foreach (tl_csv_rows($exportDir . '/invoices.csv') as $row) {
        $invoiceId = trim((string)($row['id'] ?? ''));
        if ($invoiceId === '') {
            tl_inc($summary['tables']['invoice_drafts'], 'skipped');
            continue;
        }
        $companyId = trim((string)($row['invoicee.customer.id'] ?? ''));
        $projectId = trim((string)($row['project.id'] ?? ''));
        $userId = $projectId !== '' && isset($projectInfo[$projectId])
            ? $projectInfo[$projectId]['user_id']
            : ($companyId !== '' && isset($companyOwners[$companyId]) ? $companyOwners[$companyId] : $defaultUserId);
        $currency = trim((string)($row['total.payable.currency'] ?? $row['total.tax_inclusive.currency'] ?? 'EUR')) ?: 'EUR';
        $invoiceStmt->execute([
            ':id' => $invoiceId,
            ':user_id' => $userId,
            ':company_id' => $companyId,
            ':number' => trim((string)($row['invoice_number'] ?? '')) ?: $invoiceId,
            ':amount' => tl_float($row['total.payable.amount'] ?? $row['total.due.amount'] ?? '') ?? 0.0,
            ':status' => ($row['status'] ?? '') === 'draft' ? 'draft' : 'exported',
            ':project_id' => $projectId !== '' ? $projectId : null,
            ':lines' => tl_build_lines(
                trim((string)($row['invoice_number'] ?? $row['invoicee.name'] ?? 'Fattura importata')),
                tl_float($row['total.tax_exclusive.amount'] ?? ''),
                $currency
            ),
            ':is_success_fee' => 0,
            ':grant_amount' => null,
            ':notes' => tl_note([
                ($row['status'] ?? '') !== '' ? 'Stato sorgente: ' . $row['status'] : '',
                ($row['payment_reference'] ?? '') !== '' ? 'Rif. pagamento: ' . $row['payment_reference'] : '',
                ($row['purchase_order_number'] ?? '') !== '' ? 'PO: ' . $row['purchase_order_number'] : '',
                ($row['invoicee.for_attention_of.name'] ?? '') !== '' ? 'Att.ne: ' . $row['invoicee.for_attention_of.name'] : '',
            ]),
            ':sent_at' => tl_datetime($row['delivery_date'] ?? '') ?? tl_datetime($row['invoice_date'] ?? ''),
            ':created_at' => tl_datetime($row['created_at'] ?? '') ?? date('Y-m-d H:i:s'),
            ':updated_at' => tl_datetime($row['updated_at'] ?? '') ?? date('Y-m-d H:i:s'),
        ]);
        $invoiceIds[$invoiceId] = true;
        if (!isset($summary['tables']['invoice_drafts'])) {
            $summary['tables']['invoice_drafts'] = ['processed' => 0, 'skipped' => 0];
        }
        $summary['tables']['invoice_drafts']['processed']++;
    }

    $creditNoteStmt = $pdo->prepare(
        'INSERT INTO credit_notes (
            id,user_id,credit_note_number,credit_note_date,status,`lines`,customer_id,customer_type,invoice_id,currency,paid,paid_at,note,created_at,updated_at
        ) VALUES (
            :id,:user_id,:credit_note_number,:credit_note_date,:status,:lines,:customer_id,:customer_type,:invoice_id,:currency,:paid,:paid_at,:note,:created_at,:updated_at
        ) ON DUPLICATE KEY UPDATE
            user_id=VALUES(user_id),
            credit_note_number=VALUES(credit_note_number),
            credit_note_date=VALUES(credit_note_date),
            status=VALUES(status),
            `lines`=VALUES(`lines`),
            customer_id=VALUES(customer_id),
            customer_type=VALUES(customer_type),
            invoice_id=VALUES(invoice_id),
            currency=VALUES(currency),
            paid=VALUES(paid),
            paid_at=VALUES(paid_at),
            note=VALUES(note),
            updated_at=VALUES(updated_at)'
    );
    foreach (tl_csv_rows($exportDir . '/credit_notes.csv') as $row) {
        $creditNoteId = trim((string)($row['id'] ?? ''));
        if ($creditNoteId === '') {
            tl_inc($summary['tables']['credit_notes'], 'skipped');
            continue;
        }
        $companyId = trim((string)($row['invoicee.customer.id'] ?? ''));
        $userId = $companyId !== '' && isset($companyOwners[$companyId]) ? $companyOwners[$companyId] : $defaultUserId;
        $currency = trim((string)($row['total.payable.currency'] ?? 'EUR')) ?: 'EUR';
        $invoiceId = trim((string)($row['invoice.id'] ?? ''));
        $creditNoteStmt->execute([
            ':id' => $creditNoteId,
            ':user_id' => $userId,
            ':credit_note_number' => trim((string)($row['credit_note_number'] ?? '')),
            ':credit_note_date' => tl_date($row['credit_note_date'] ?? ''),
            ':status' => ($row['status'] ?? '') === 'booked' ? 'booked' : 'draft',
            ':lines' => tl_build_lines(
                trim((string)($row['credit_note_number'] ?? 'Nota di credito')),
                tl_float($row['total.tax_exclusive.amount'] ?? ''),
                $currency
            ),
            ':customer_id' => $companyId !== '' ? $companyId : null,
            ':customer_type' => trim((string)($row['invoicee.customer.type'] ?? '')) ?: null,
            ':invoice_id' => $invoiceId !== '' && isset($invoiceIds[$invoiceId]) ? $invoiceId : null,
            ':currency' => $currency,
            ':paid' => tl_bool($row['paid'] ?? false) ? 1 : 0,
            ':paid_at' => tl_datetime($row['paid_at'] ?? ''),
            ':note' => tl_note([
                ($row['invoicee.name'] ?? '') !== '' ? 'Intestazione sorgente: ' . $row['invoicee.name'] : '',
                ($row['invoicee.vat_number'] ?? '') !== '' ? 'P.IVA intestazione: ' . $row['invoicee.vat_number'] : '',
            ]),
            ':created_at' => tl_datetime($row['created_at'] ?? '') ?? date('Y-m-d H:i:s'),
            ':updated_at' => tl_datetime($row['updated_at'] ?? '') ?? date('Y-m-d H:i:s'),
        ]);
        if (!isset($summary['tables']['credit_notes'])) {
            $summary['tables']['credit_notes'] = ['processed' => 0, 'skipped' => 0];
        }
        $summary['tables']['credit_notes']['processed']++;
    }

    $productStmt = $pdo->prepare(
        'INSERT INTO products (
            id,user_id,name,sku,description,price,currency,unit,category,vat_rate,created_at,updated_at
        ) VALUES (
            :id,:user_id,:name,:sku,:description,:price,:currency,:unit,:category,:vat_rate,:created_at,:updated_at
        ) ON DUPLICATE KEY UPDATE
            user_id=VALUES(user_id),
            name=VALUES(name),
            sku=VALUES(sku),
            description=VALUES(description),
            price=VALUES(price),
            currency=VALUES(currency),
            unit=VALUES(unit),
            category=VALUES(category),
            vat_rate=VALUES(vat_rate),
            updated_at=VALUES(updated_at)'
    );
    foreach (tl_csv_rows($exportDir . '/products.csv') as $row) {
        $productId = trim((string)($row['id'] ?? ''));
        if ($productId === '') {
            tl_inc($summary['tables']['products'], 'skipped');
            continue;
        }
        $productStmt->execute([
            ':id' => $productId,
            ':user_id' => $defaultUserId,
            ':name' => trim((string)($row['name'] ?? 'Prodotto importato')),
            ':sku' => trim((string)($row['code'] ?? '')),
            ':description' => trim((string)($row['description'] ?? '')),
            ':price' => 0,
            ':currency' => 'EUR',
            ':unit' => trim((string)($row['unit'] ?? '')) ?: 'pz',
            ':category' => '',
            ':vat_rate' => 22,
            ':created_at' => tl_datetime($row['added_at'] ?? '') ?? date('Y-m-d H:i:s'),
            ':updated_at' => tl_datetime($row['updated_at'] ?? '') ?? date('Y-m-d H:i:s'),
        ]);
        if (!isset($summary['tables']['products'])) {
            $summary['tables']['products'] = ['processed' => 0, 'skipped' => 0];
        }
        $summary['tables']['products']['processed']++;
    }

    $subscriptionStmt = $pdo->prepare(
        'INSERT INTO subscriptions (
            id,user_id,title,note,status,billing_cycle,`lines`,customer_id,customer_type,currency,starts_on,ends_on,next_renewal_date,created_at,updated_at
        ) VALUES (
            :id,:user_id,:title,:note,:status,:billing_cycle,:lines,:customer_id,:customer_type,:currency,:starts_on,:ends_on,:next_renewal_date,:created_at,:updated_at
        ) ON DUPLICATE KEY UPDATE
            user_id=VALUES(user_id),
            title=VALUES(title),
            note=VALUES(note),
            status=VALUES(status),
            billing_cycle=VALUES(billing_cycle),
            `lines`=VALUES(`lines`),
            customer_id=VALUES(customer_id),
            customer_type=VALUES(customer_type),
            currency=VALUES(currency),
            starts_on=VALUES(starts_on),
            ends_on=VALUES(ends_on),
            next_renewal_date=VALUES(next_renewal_date),
            updated_at=VALUES(updated_at)'
    );
    foreach (tl_csv_rows($exportDir . '/subscriptions.csv') as $row) {
        $subscriptionId = trim((string)($row['id'] ?? ''));
        if ($subscriptionId === '') {
            tl_inc($summary['tables']['subscriptions'], 'skipped');
            continue;
        }
        $companyId = trim((string)($row['invoicee.customer.id'] ?? ''));
        $projectId = trim((string)($row['project.id'] ?? ''));
        $userId = $projectId !== '' && isset($projectInfo[$projectId])
            ? $projectInfo[$projectId]['user_id']
            : ($companyId !== '' && isset($companyOwners[$companyId]) ? $companyOwners[$companyId] : $defaultUserId);
        $currency = trim((string)($row['total.tax_inclusive.currency'] ?? $row['total.tax_exclusive.currency'] ?? 'EUR')) ?: 'EUR';
        $billingCycle = [
            'daysInAdvance' => tl_int($row['billing_cycle.days_in_advance'] ?? '') ?? 0,
            'period' => tl_int($row['billing_cycle.periodicity.period'] ?? '') ?? 0,
            'unit' => trim((string)($row['billing_cycle.periodicity.unit'] ?? '')),
        ];
        $subscriptionStmt->execute([
            ':id' => $subscriptionId,
            ':user_id' => $userId,
            ':title' => trim((string)($row['title'] ?? 'Abbonamento importato')),
            ':note' => tl_note([
                trim((string)($row['note'] ?? '')),
                ($row['project.id'] ?? '') !== '' ? 'Progetto sorgente: ' . $row['project.id'] : '',
                ($row['purchase_order_number'] ?? '') !== '' ? 'PO: ' . $row['purchase_order_number'] : '',
            ]),
            ':status' => ($row['status'] ?? '') === 'active' ? 'active' : 'deactivated',
            ':billing_cycle' => json_encode($billingCycle, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES) ?: '{}',
            ':lines' => tl_build_lines(
                trim((string)($row['title'] ?? 'Abbonamento')),
                tl_float($row['total.tax_exclusive.amount'] ?? ''),
                $currency
            ),
            ':customer_id' => $companyId !== '' ? $companyId : null,
            ':customer_type' => trim((string)($row['invoicee.customer.type'] ?? '')) ?: null,
            ':currency' => $currency,
            ':starts_on' => tl_date($row['starts_on'] ?? ''),
            ':ends_on' => tl_date($row['ends_on'] ?? ''),
            ':next_renewal_date' => tl_date($row['next_renewal_date'] ?? ''),
            ':created_at' => tl_datetime($row['created_at'] ?? '') ?? date('Y-m-d H:i:s'),
            ':updated_at' => tl_datetime($row['created_at'] ?? '') ?? date('Y-m-d H:i:s'),
        ]);
        if (!isset($summary['tables']['subscriptions'])) {
            $summary['tables']['subscriptions'] = ['processed' => 0, 'skipped' => 0];
        }
        $summary['tables']['subscriptions']['processed']++;
    }

    $summary['unknownUsers'] = array_map(
        static fn(array $item) => [
            'count' => $item['count'],
            'contexts' => array_keys($item['contexts']),
        ],
        $summary['unknownUsers']
    );
    $summary['missingTargetUsers'] = array_map(
        static fn(array $item) => [
            'count' => $item['count'],
            'exportUsers' => array_keys($item['exportUsers']),
            'contexts' => array_keys($item['contexts']),
        ],
        $summary['missingTargetUsers']
    );

    if ($run) {
        $pdo->commit();
    } else {
        $pdo->rollBack();
    }

    json_ok($summary);
} catch (Throwable $e) {
    if (isset($pdo) && $pdo instanceof PDO && $pdo->inTransaction()) {
        $pdo->rollBack();
    }
    $debug = null;
    if (isset($pdo) && $pdo instanceof PDO) {
        $message = $e->getMessage();
        if (stripos($message, 'companies') !== false) {
            $debug = tl_debug_table($pdo, 'companies');
        }
    }
    http_response_code(500);
    echo json_encode([
        'error' => $e->getMessage(),
        'type' => get_class($e),
        'file' => $e->getFile(),
        'line' => $e->getLine(),
        'summary' => $summary,
        'debug' => $debug,
    ], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES | JSON_PRETTY_PRINT);
    exit;
}
