<?php
declare(strict_types=1);

// Template PDF ed email + scelta template per documento.
//   GET    ?type=document|email           → lista template
//   POST   ?type=...  {id?, ...campi}     → upsert template
//   DELETE ?type=...&id=                  → elimina template
//   GET    ?choice=<docId>                → {templateId} scelto per il documento
//   PUT    {choice: docId, templateId}    → imposta/azzera la scelta

require_once __DIR__ . '/helpers.php';

header('Content-Type: application/json; charset=utf-8');

$uid = require_auth();
$pdo = db();
$method = $_SERVER['REQUEST_METHOD'];

// ── Scelta template per documento ───────────────────────────────────────────

$choiceDoc = trim((string)($_GET['choice'] ?? ''));
if ($method === 'GET' && $choiceDoc !== '') {
    $stmt = $pdo->prepare(
        'SELECT template_id FROM template_choices
         WHERE user_id = :uid AND doc_id = :doc'
    );
    $stmt->execute([':uid' => $uid, ':doc' => $choiceDoc]);
    $templateId = $stmt->fetchColumn();
    json_ok(['templateId' => $templateId === false ? null : (string)$templateId]);
}

if ($method === 'PUT') {
    $payload = request_json();
    if (array_key_exists('choice', $payload)) {
        $docId = trim((string)($payload['choice'] ?? ''));
        $templateId = trim((string)($payload['templateId'] ?? ''));
        if ($docId === '') {
            json_error('Parametro choice (docId) mancante.', 422);
        }
        if ($templateId === '') {
            $pdo->prepare(
                'DELETE FROM template_choices WHERE user_id = :uid AND doc_id = :doc'
            )->execute([':uid' => $uid, ':doc' => $docId]);
        } else {
            $pdo->prepare(
                'INSERT INTO template_choices (user_id, doc_id, template_id)
                 VALUES (:uid, :doc, :tpl)
                 ON DUPLICATE KEY UPDATE template_id = VALUES(template_id)'
            )->execute([':uid' => $uid, ':doc' => $docId, ':tpl' => $templateId]);
        }
        json_ok(['ok' => true]);
    }
    json_error('Payload PUT non riconosciuto.', 422);
}

// ── Template (document | email) ─────────────────────────────────────────────

$type = (string)($_GET['type'] ?? 'document');
if (!in_array($type, ['document', 'email'], true)) {
    json_error('Parametro type non valido (document|email).', 422);
}
$isDocument = $type === 'document';
$table = $isDocument ? 'document_templates' : 'email_templates';

if ($method === 'GET') {
    $category = trim((string)($_GET['category'] ?? ''));
    $sql = "SELECT * FROM $table WHERE user_id = :uid";
    $params = [':uid' => $uid];
    if ($category !== '') {
        $sql .= ' AND category = :cat';
        $params[':cat'] = $category;
    }
    $sql .= ' ORDER BY name ASC';
    $stmt = $pdo->prepare($sql);
    $stmt->execute($params);
    $rows = $stmt->fetchAll(PDO::FETCH_ASSOC) ?: [];

    $templates = array_map(function (array $row) use ($isDocument): array {
        $base = [
            'id' => (string)$row['id'],
            'name' => (string)$row['name'],
            'category' => (string)$row['category'],
            'createdAt' => app_iso((string)$row['created_at']),
        ];
        if ($isDocument) {
            $base['backgroundImageUrl'] =
                ($row['background_image_url'] ?? '') !== ''
                    ? (string)$row['background_image_url'] : null;
            $base['elements'] = app_json_decode($row['elements'] ?? null);
            $base['customFields'] = app_json_decode($row['custom_fields'] ?? null);
        } else {
            $base['subject'] = (string)$row['subject'];
            $base['body'] = (string)($row['body'] ?? '');
        }
        return $base;
    }, $rows);
    json_ok(['templates' => $templates]);
}

if ($method === 'POST') {
    $payload = request_json();
    $id = trim((string)($payload['id'] ?? ''));
    if ($id === '') {
        $id = 'tpl-' . date('YmdHis') . '-' . bin2hex(random_bytes(4));
    }
    $name = trim((string)($payload['name'] ?? ''));
    $category = trim((string)($payload['category'] ?? 'preventivo'));

    if ($isDocument) {
        $pdo->prepare(
            'INSERT INTO document_templates
               (id, user_id, name, category, background_image_url, elements, custom_fields)
             VALUES (:id, :uid, :name, :cat, :bg, :elements, :custom)
             ON DUPLICATE KEY UPDATE
               name = VALUES(name), category = VALUES(category),
               background_image_url = VALUES(background_image_url),
               elements = VALUES(elements), custom_fields = VALUES(custom_fields)'
        )->execute([
            ':id' => $id,
            ':uid' => $uid,
            ':name' => $name,
            ':cat' => $category,
            ':bg' => trim((string)($payload['backgroundImageUrl'] ?? '')) ?: null,
            ':elements' => json_encode(
                $payload['elements'] ?? [],
                JSON_UNESCAPED_UNICODE
            ) ?: '[]',
            ':custom' => json_encode(
                $payload['customFields'] ?? [],
                JSON_UNESCAPED_UNICODE
            ) ?: '[]',
        ]);
    } else {
        $pdo->prepare(
            'INSERT INTO email_templates (id, user_id, name, category, subject, body)
             VALUES (:id, :uid, :name, :cat, :subject, :body)
             ON DUPLICATE KEY UPDATE
               name = VALUES(name), category = VALUES(category),
               subject = VALUES(subject), body = VALUES(body)'
        )->execute([
            ':id' => $id,
            ':uid' => $uid,
            ':name' => $name,
            ':cat' => $category,
            ':subject' => (string)($payload['subject'] ?? ''),
            ':body' => (string)($payload['body'] ?? ''),
        ]);
    }
    json_ok(['ok' => true, 'id' => $id]);
}

if ($method === 'DELETE') {
    $id = trim((string)($_GET['id'] ?? ''));
    if ($id === '') {
        json_error('Parametro id mancante.', 422);
    }
    $pdo->prepare("DELETE FROM $table WHERE id = :id AND user_id = :uid")
        ->execute([':id' => $id, ':uid' => $uid]);
    json_ok(['ok' => true]);
}

json_error('Metodo non consentito.', 405);
