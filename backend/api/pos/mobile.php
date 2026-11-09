<?php
declare(strict_types=1);

require_once dirname(__DIR__) . '/bootstrap.php';
require_once dirname(__DIR__) . '/stripe/common.php';

header('Content-Type: application/json; charset=utf-8');

$userId = require_auth();
$pdo = db();
$method = http_method();
$teamId = current_team_id($userId) ?: $userId;
$scopeUserIds = scoped_user_ids($userId);

function posm_placeholders(array $items): string
{
    return implode(',', array_fill(0, count($items), '?'));
}

function posm_team_stripe_row(PDO $pdo, string $teamId): ?array
{
    $stmt = $pdo->prepare(
        'SELECT * FROM team_stripe_connections WHERE team_id = :team_id LIMIT 1'
    );
    $stmt->execute([':team_id' => $teamId]);
    $row = $stmt->fetch(PDO::FETCH_ASSOC);
    return $row ?: null;
}

function posm_require_connected_account(PDO $pdo, string $teamId): array
{
    $row = posm_team_stripe_row($pdo, $teamId);
    if (!$row) {
        json_error('Stripe Connect non collegato per questo team.', 422);
    }
    if ((int)($row['is_active'] ?? 1) !== 1) {
        json_error('L\'account Stripe del team e scollegato.', 422);
    }
    if ((int)($row['charges_enabled'] ?? 0) !== 1 || (int)($row['payouts_enabled'] ?? 0) !== 1) {
        json_error('Stripe Connect non e ancora attivo per gli incassi.', 422);
    }
    return $row;
}

function posm_company_name(PDO $pdo, array $scopeUserIds, ?string $companyId): ?string
{
    $companyId = trim((string)$companyId);
    if ($companyId === '') {
        return null;
    }
    $sql = 'SELECT name FROM companies WHERE id = ? AND user_id IN (' . posm_placeholders($scopeUserIds) . ') LIMIT 1';
    $stmt = $pdo->prepare($sql);
    $stmt->execute(array_merge([$companyId], $scopeUserIds));
    $name = $stmt->fetchColumn();
    return $name ? (string)$name : null;
}

function posm_invoice_row(PDO $pdo, array $scopeUserIds, string $invoiceId): ?array
{
    $sql = 'SELECT * FROM invoice_drafts WHERE id = ? AND user_id IN (' . posm_placeholders($scopeUserIds) . ') LIMIT 1';
    $stmt = $pdo->prepare($sql);
    $stmt->execute(array_merge([$invoiceId], $scopeUserIds));
    $row = $stmt->fetch(PDO::FETCH_ASSOC);
    return $row ?: null;
}

function posm_invoice_paid_amount(PDO $pdo, string $invoiceId): float
{
    $stmt = $pdo->prepare(
        'SELECT COALESCE(SUM(amount), 0) FROM invoice_payment_allocations WHERE invoice_id = ?'
    );
    $stmt->execute([$invoiceId]);
    return round((float)$stmt->fetchColumn(), 2);
}

function posm_refresh_invoice_payment_status(PDO $pdo, string $invoiceId): array
{
    $invoice = posm_invoice_row($pdo, [db()->query("SELECT user_id FROM invoice_drafts WHERE id = " . db()->quote($invoiceId) . " LIMIT 1")->fetchColumn() ?: ''], $invoiceId);
    if (!$invoice) {
        return ['paidAmount' => 0.0, 'balanceDue' => 0.0, 'paymentStatus' => 'unpaid'];
    }
    $amount = round((float)($invoice['amount'] ?? 0), 2);
    $paidAmount = posm_invoice_paid_amount($pdo, $invoiceId);
    $balanceDue = max(0, round($amount - $paidAmount, 2));
    $paymentStatus = 'unpaid';
    $paidAt = null;
    if ($paidAmount > 0 && $balanceDue <= 0.009) {
        $paymentStatus = 'paid';
        $paidAt = gmdate('Y-m-d H:i:s');
    } elseif ($paidAmount > 0) {
        $paymentStatus = 'partially_paid';
    }
    $stmt = $pdo->prepare(
        'UPDATE invoice_drafts
         SET paid_amount = :paid_amount,
             balance_due = :balance_due,
             payment_status = :payment_status,
             paid_at = :paid_at
         WHERE id = :id'
    );
    $stmt->execute([
        ':paid_amount' => $paidAmount,
        ':balance_due' => $balanceDue,
        ':payment_status' => $paymentStatus,
        ':paid_at' => $paidAt,
        ':id' => $invoiceId,
    ]);
    return [
        'paidAmount' => $paidAmount,
        'balanceDue' => $balanceDue,
        'paymentStatus' => $paymentStatus,
    ];
}

function posm_pick_invoice_template_id(PDO $pdo, array $scopeUserIds): ?string
{
    if ($scopeUserIds === []) {
        return null;
    }
    $placeholders = posm_placeholders($scopeUserIds);
    $stmt = $pdo->prepare(
        'SELECT tc.template_id
         FROM template_choices tc
         INNER JOIN document_templates dt ON dt.id = tc.template_id
         WHERE tc.user_id IN (' . $placeholders . ')
           AND dt.category = ?
         ORDER BY tc.updated_at DESC
         LIMIT 1'
    );
    $params = array_merge($scopeUserIds, ['fattura']);
    $stmt->execute($params);
    $templateId = $stmt->fetchColumn();
    if ($templateId) {
        return (string)$templateId;
    }

    $stmt = $pdo->prepare(
        'SELECT id FROM document_templates
         WHERE user_id IN (' . $placeholders . ')
           AND category = ?
         ORDER BY updated_at DESC, created_at DESC
         LIMIT 1'
    );
    $stmt->execute($params);
    $fallback = $stmt->fetchColumn();
    return $fallback ? (string)$fallback : null;
}

function posm_next_invoice_number(PDO $pdo, array $scopeUserIds): string
{
    $stmt = $pdo->prepare(
        'SELECT COUNT(*) FROM invoice_drafts WHERE user_id IN (' . posm_placeholders($scopeUserIds) . ')'
    );
    $stmt->execute($scopeUserIds);
    $count = (int)$stmt->fetchColumn();
    return 'POS/' . date('Y') . '/' . str_pad((string)($count + 1), 4, '0', STR_PAD_LEFT);
}

function posm_create_spot_invoice(
    PDO $pdo,
    array $scopeUserIds,
    string $userId,
    string $teamId,
    string $paymentIntentId,
    string $companyId,
    string $title,
    string $description,
    float $amount
): ?string {
    if ($companyId === '') {
        return null;
    }

    $invoiceId = 'inv-' . bin2hex(random_bytes(8));
    $number = posm_next_invoice_number($pdo, $scopeUserIds);
    $notes = trim($description);
    if ($notes !== '') {
        $notes .= "\n\n";
    }
    $notes .= 'Fattura generata automaticamente da pagamento POS.';
    $lines = [[
        'description' => $title,
        'quantity' => 1,
        'unitPrice' => $amount,
        'vatPercent' => 22.0,
    ]];

    $stmt = $pdo->prepare(
        'INSERT INTO invoice_drafts (
            id, user_id, company_id, number, amount, status, `lines`,
            is_success_fee, notes, payment_status, paid_amount, balance_due,
            paid_at, pos_origin_payment_id
        ) VALUES (
            :id, :user_id, :company_id, :number, :amount, :status, :lines,
            0, :notes, :payment_status, :paid_amount, :balance_due,
            :paid_at, :pos_origin_payment_id
        )'
    );
    $stmt->execute([
        ':id' => $invoiceId,
        ':user_id' => $userId,
        ':company_id' => $companyId,
        ':number' => $number,
        ':amount' => round($amount, 2),
        ':status' => 'draft',
        ':lines' => json_encode($lines, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES) ?: '[]',
        ':notes' => $notes,
        ':payment_status' => 'paid',
        ':paid_amount' => round($amount, 2),
        ':balance_due' => 0,
        ':paid_at' => gmdate('Y-m-d H:i:s'),
        ':pos_origin_payment_id' => $paymentIntentId,
    ]);

    $templateId = posm_pick_invoice_template_id($pdo, $scopeUserIds);
    if ($templateId !== null) {
        $choiceStmt = $pdo->prepare(
            'INSERT INTO template_choices (user_id, doc_id, template_id)
             VALUES (:user_id, :doc_id, :template_id)
             ON DUPLICATE KEY UPDATE template_id = VALUES(template_id)'
        );
        $choiceStmt->execute([
            ':user_id' => $userId,
            ':doc_id' => $invoiceId,
            ':template_id' => $templateId,
        ]);
    }

    return $invoiceId;
}

function posm_payment_label(array $paymentIntent): string
{
    $latestCharge = $paymentIntent['latest_charge'] ?? null;
    if (!is_array($latestCharge)) {
        return 'card_present';
    }
    $details = $latestCharge['payment_method_details']['card_present'] ?? [];
    if (!is_array($details)) {
        return 'card_present';
    }
    $brand = strtoupper((string)($details['brand'] ?? 'CARD'));
    $last4 = trim((string)($details['last4'] ?? ''));
    return $last4 !== '' ? $brand . ' •••• ' . $last4 : $brand;
}

function posm_metadata_decode(?string $raw): array
{
    if ($raw === null || trim($raw) === '') {
        return [];
    }
    $decoded = json_decode($raw, true);
    return is_array($decoded) ? $decoded : [];
}

function posm_team_row(PDO $pdo, string $teamId): ?array
{
    $stmt = $pdo->prepare('SELECT id, name, billing_profile FROM teams WHERE id = :id LIMIT 1');
    $stmt->execute([':id' => $teamId]);
    $row = $stmt->fetch(PDO::FETCH_ASSOC);
    return $row ?: null;
}

function posm_store_terminal_location_id(PDO $pdo, string $teamId, string $locationId): void
{
    $row = posm_team_stripe_row($pdo, $teamId);
    if (!$row) {
        return;
    }
    $metadata = posm_metadata_decode($row['metadata_json'] ?? null);
    $metadata['terminalLocationId'] = $locationId;
    $metadata['terminalLocationSavedAt'] = gmdate('c');
    $stmt = $pdo->prepare(
        'UPDATE team_stripe_connections
         SET metadata_json = :metadata_json, last_synced_at = NOW()
         WHERE team_id = :team_id'
    );
    $stmt->execute([
        ':metadata_json' => json_encode($metadata, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES) ?: '{}',
        ':team_id' => $teamId,
    ]);
}

function posm_terminal_location_id(PDO $pdo, array $stripe, string $teamId): string
{
    $metadata = posm_metadata_decode($stripe['metadata_json'] ?? null);
    $cachedId = trim((string)($metadata['terminalLocationId'] ?? ''));
    if ($cachedId !== '') {
        return $cachedId;
    }

    $stripeAccountId = trim((string)($stripe['stripe_account_id'] ?? ''));
    if ($stripeAccountId === '') {
        json_error('Account Stripe Connect mancante per il team.', 422);
    }

    $locations = stripe_api_request(
        'GET',
        '/v1/terminal/locations',
        ['limit' => 1],
        ['stripe_account' => $stripeAccountId]
    );
    $existing = $locations['data'][0]['id'] ?? '';
    if (is_string($existing) && trim($existing) !== '') {
        $existing = trim($existing);
        posm_store_terminal_location_id($pdo, $teamId, $existing);
        return $existing;
    }

    $team = posm_team_row($pdo, $teamId);
    $billing = json_decode((string)($team['billing_profile'] ?? '{}'), true);
    $billing = is_array($billing) ? $billing : [];
    $displayName = trim((string)($billing['businessName'] ?? $team['name'] ?? 'Nexora POS'));
    $addressLine = trim((string)($billing['addressLine'] ?? ''));
    $postalCode = trim((string)($billing['postalCode'] ?? ''));
    $city = trim((string)($billing['city'] ?? ''));
    $country = strtoupper(trim((string)($billing['countryCode'] ?? 'IT')));

    if ($displayName === '' || $addressLine === '' || $postalCode === '' || $city === '' || $country === '') {
        json_error(
            'Per attivare Tap to Pay serve almeno una location Stripe Terminal. Completa i dati emittente del team oppure crea una location nel conto Stripe collegato.',
            422
        );
    }

    $created = stripe_api_request(
        'POST',
        '/v1/terminal/locations',
        [
            'display_name' => $displayName,
            'address[line1]' => $addressLine,
            'address[postal_code]' => $postalCode,
            'address[city]' => $city,
            'address[country]' => $country,
        ],
        ['stripe_account' => $stripeAccountId]
    );
    $createdId = trim((string)($created['id'] ?? ''));
    if ($createdId === '') {
        json_error('Stripe non ha restituito una location valida per Tap to Pay.', 502);
    }
    posm_store_terminal_location_id($pdo, $teamId, $createdId);
    return $createdId;
}

if ($method !== 'POST') {
    json_error('Metodo non consentito.', 405);
}

$payload = request_body();
$action = trim((string)($payload['action'] ?? ''));

switch ($action) {
    case 'create_connection_token':
        $stripe = posm_require_connected_account($pdo, $teamId);
        $token = stripe_api_request(
            'POST',
            '/v1/terminal/connection_tokens',
            [],
            ['stripe_account' => (string)$stripe['stripe_account_id']]
        );
        json_ok([
            'secret' => (string)($token['secret'] ?? ''),
            'connectedAccountId' => (string)$stripe['stripe_account_id'],
        ]);
        break;

    case 'prepare_mobile_payment':
        $stripe = posm_require_connected_account($pdo, $teamId);
        $terminalLocationId = posm_terminal_location_id($pdo, $stripe, $teamId);
        $paymentMode = trim((string)($payload['paymentMode'] ?? 'spot'));
        $allowedModes = ['invoice_full', 'invoice_partial', 'deposit', 'spot'];
        if (!in_array($paymentMode, $allowedModes, true)) {
            json_error('Modalita pagamento non supportata.', 422);
        }
        $amount = round((float)($payload['amount'] ?? 0), 2);
        if ($amount <= 0) {
            json_error('Importo non valido.', 422);
        }
        $invoiceId = trim((string)($payload['invoiceId'] ?? ''));
        $companyId = trim((string)($payload['companyId'] ?? ''));
        $companyName = trim((string)($payload['companyName'] ?? ''));
        $title = trim((string)($payload['title'] ?? 'Incasso mobile'));
        $description = trim((string)($payload['description'] ?? ''));
        $currency = strtolower(trim((string)($payload['currency'] ?? 'eur')));
        $autoInvoiceAfterPayment = ($payload['autoInvoiceAfterPayment'] ?? true) !== false;
        $invoiceNumberSnapshot = null;

        if ($invoiceId !== '') {
            $invoice = posm_invoice_row($pdo, $scopeUserIds, $invoiceId);
            if (!$invoice) {
                json_error('Fattura non trovata.', 404);
            }
            $invoiceNumberSnapshot = (string)($invoice['number'] ?? '');
            $companyId = (string)($invoice['company_id'] ?? $companyId);
            $paidAmount = posm_invoice_paid_amount($pdo, $invoiceId);
            $invoiceTotal = round((float)($invoice['amount'] ?? 0), 2);
            $remaining = max(0, round($invoiceTotal - $paidAmount, 2));
            if ($amount - $remaining > 0.009) {
                json_error('L\'importo supera il residuo della fattura.', 422);
            }
            if ($title === 'Incasso mobile') {
                $title = $paymentMode === 'invoice_full'
                    ? 'Saldo fattura ' . ($invoiceNumberSnapshot !== '' ? $invoiceNumberSnapshot : $invoiceId)
                    : 'Pagamento fattura ' . ($invoiceNumberSnapshot !== '' ? $invoiceNumberSnapshot : $invoiceId);
            }
        }

        if ($companyId === '') {
            json_error('Cliente obbligatorio per il pagamento mobile.', 422);
        }

        if ($companyName === '') {
            $companyName = posm_company_name($pdo, $scopeUserIds, $companyId) ?? '';
        }

        $localId = 'posint-' . bin2hex(random_bytes(8));
        $intent = stripe_api_request(
            'POST',
            '/v1/payment_intents',
            [
                'amount' => (string)max(1, (int)round($amount * 100)),
                'currency' => $currency,
                'capture_method' => 'automatic',
                'payment_method_types[]' => 'card_present',
                'description' => $title,
                'metadata[nexora_pos_intent_id]' => $localId,
                'metadata[nexora_team_id]' => $teamId,
                'metadata[nexora_company_id]' => $companyId,
                'metadata[nexora_invoice_id]' => $invoiceId,
                'metadata[nexora_payment_mode]' => $paymentMode,
            ],
            ['stripe_account' => (string)$stripe['stripe_account_id']]
        );

        $stmt = $pdo->prepare(
            'INSERT INTO pos_payment_intents (
                id, team_id, created_by_user_id, company_id, company_name, invoice_id,
                opportunity_id, title, description, amount, currency, status, provider,
                source, is_demo, payment_mode, invoice_number_snapshot,
                stripe_payment_intent_id, stripe_client_secret, stripe_connected_account_id,
                terminal_location_id, auto_generated_invoice, mobile_checkout_json, metadata_json
            ) VALUES (
                :id, :team_id, :created_by_user_id, :company_id, :company_name, :invoice_id,
                NULL, :title, :description, :amount, :currency, :status, :provider,
                :source, 0, :payment_mode, :invoice_number_snapshot,
                :stripe_payment_intent_id, :stripe_client_secret, :stripe_connected_account_id,
                :terminal_location_id, :auto_generated_invoice, :mobile_checkout_json, :metadata_json
            )'
        );
        $mobilePayload = [
            'platform' => 'mobile',
            'tapToPayRequested' => true,
            'autoInvoiceAfterPayment' => $autoInvoiceAfterPayment,
        ];
        $stmt->execute([
            ':id' => $localId,
            ':team_id' => $teamId,
            ':created_by_user_id' => $userId,
            ':company_id' => $companyId,
            ':company_name' => $companyName !== '' ? $companyName : null,
            ':invoice_id' => $invoiceId !== '' ? $invoiceId : null,
            ':title' => $title,
            ':description' => $description,
            ':amount' => $amount,
            ':currency' => strtoupper($currency),
            ':status' => 'prepared',
            ':provider' => 'stripe_terminal',
            ':source' => 'mobile',
            ':payment_mode' => $paymentMode,
            ':invoice_number_snapshot' => $invoiceNumberSnapshot,
            ':stripe_payment_intent_id' => (string)($intent['id'] ?? ''),
            ':stripe_client_secret' => (string)($intent['client_secret'] ?? ''),
            ':stripe_connected_account_id' => (string)$stripe['stripe_account_id'],
            ':terminal_location_id' => $terminalLocationId,
            ':auto_generated_invoice' => $autoInvoiceAfterPayment ? 1 : 0,
            ':mobile_checkout_json' => json_encode($mobilePayload, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES) ?: '{}',
            ':metadata_json' => json_encode([
                'stage' => 'prepared_mobile',
                'bridge' => 'tap_to_pay_native',
            ], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES) ?: '{}',
        ]);

        json_ok([
            'session' => [
                'localIntentId' => $localId,
                'stripePaymentIntentId' => (string)($intent['id'] ?? ''),
                'clientSecret' => (string)($intent['client_secret'] ?? ''),
                'connectedAccountId' => (string)$stripe['stripe_account_id'],
                'terminalLocationId' => $terminalLocationId,
                'amount' => $amount,
                'currency' => strtoupper($currency),
                'companyId' => $companyId,
                'companyName' => $companyName,
                'invoiceId' => $invoiceId !== '' ? $invoiceId : null,
                'invoiceNumber' => $invoiceNumberSnapshot,
                'paymentMode' => $paymentMode,
                'autoInvoiceAfterPayment' => $autoInvoiceAfterPayment,
                'title' => $title,
                'description' => $description,
            ],
        ], 201);
        break;

    case 'complete_mobile_payment':
        $localIntentId = trim((string)($payload['localIntentId'] ?? ''));
        if ($localIntentId === '') {
            json_error('Intent locale mancante.', 422);
        }
        $stmt = $pdo->prepare(
            'SELECT * FROM pos_payment_intents WHERE id = :id AND team_id = :team_id LIMIT 1'
        );
        $stmt->execute([':id' => $localIntentId, ':team_id' => $teamId]);
        $row = $stmt->fetch(PDO::FETCH_ASSOC);
        if (!$row) {
            json_error('Pagamento mobile non trovato.', 404);
        }
        $stripeAccountId = (string)($row['stripe_connected_account_id'] ?? '');
        $stripePaymentIntentId = trim((string)($row['stripe_payment_intent_id'] ?? ''));
        if ($stripeAccountId === '' || $stripePaymentIntentId === '') {
            json_error('Dati Stripe del pagamento mancanti.', 422);
        }
        $paymentIntent = stripe_api_request(
            'GET',
            '/v1/payment_intents/' . rawurlencode($stripePaymentIntentId),
            ['expand[]' => 'latest_charge'],
            ['stripe_account' => $stripeAccountId]
        );
        $stripeStatus = (string)($paymentIntent['status'] ?? '');
        if (!in_array($stripeStatus, ['succeeded', 'requires_capture', 'processing'], true)) {
            json_error('Il pagamento Stripe non risulta completato. Stato: ' . $stripeStatus, 422);
        }
        $capturedAmount = round(((float)($paymentIntent['amount_received'] ?? 0)) / 100, 2);
        if ($capturedAmount <= 0) {
            $capturedAmount = round((float)($row['amount'] ?? 0), 2);
        }
        $generatedInvoiceId = null;
        $invoiceId = trim((string)($row['invoice_id'] ?? ''));

        $update = $pdo->prepare(
            'UPDATE pos_payment_intents
             SET status = :status,
                 completed_at = NOW(),
                 paid_amount = :paid_amount,
                 payment_method_label = :payment_method_label,
                 failure_reason = NULL
             WHERE id = :id AND team_id = :team_id'
        );
        $update->execute([
            ':status' => $stripeStatus === 'succeeded' ? 'succeeded' : 'processing',
            ':paid_amount' => $capturedAmount,
            ':payment_method_label' => posm_payment_label($paymentIntent),
            ':id' => $localIntentId,
            ':team_id' => $teamId,
        ]);

        if ($stripeStatus === 'succeeded') {
            if ($invoiceId !== '') {
                $existsStmt = $pdo->prepare(
                    'SELECT COUNT(*) FROM invoice_payment_allocations
                     WHERE payment_intent_id = :payment_intent_id AND invoice_id = :invoice_id'
                );
                $existsStmt->execute([
                    ':payment_intent_id' => $localIntentId,
                    ':invoice_id' => $invoiceId,
                ]);
                if ((int)$existsStmt->fetchColumn() === 0) {
                    $alloc = $pdo->prepare(
                        'INSERT INTO invoice_payment_allocations (
                            team_id, payment_intent_id, invoice_id, company_id, amount, allocation_type
                        ) VALUES (
                            :team_id, :payment_intent_id, :invoice_id, :company_id, :amount, :allocation_type
                        )'
                    );
                    $alloc->execute([
                        ':team_id' => $teamId,
                        ':payment_intent_id' => $localIntentId,
                        ':invoice_id' => $invoiceId,
                        ':company_id' => (string)($row['company_id'] ?? ''),
                        ':amount' => $capturedAmount,
                        ':allocation_type' => (string)($row['payment_mode'] ?? 'invoice_partial'),
                    ]);
                }
                posm_refresh_invoice_payment_status($pdo, $invoiceId);
            } else {
                $mobileCheckout = posm_metadata_decode($row['mobile_checkout_json'] ?? null);
                $autoInvoice = !empty($row['auto_generated_invoice']) || !empty($mobileCheckout['autoInvoiceAfterPayment']);
                if ($autoInvoice) {
                    $generatedInvoiceId = posm_create_spot_invoice(
                        $pdo,
                        $scopeUserIds,
                        $userId,
                        $teamId,
                        $localIntentId,
                        (string)($row['company_id'] ?? ''),
                        (string)($row['title'] ?? 'Pagamento POS'),
                        (string)($row['description'] ?? ''),
                        $capturedAmount
                    );
                    if ($generatedInvoiceId !== null) {
                        $alloc = $pdo->prepare(
                            'INSERT INTO invoice_payment_allocations (
                                team_id, payment_intent_id, invoice_id, company_id, amount, allocation_type
                            ) VALUES (
                                :team_id, :payment_intent_id, :invoice_id, :company_id, :amount, :allocation_type
                            )'
                        );
                        $alloc->execute([
                            ':team_id' => $teamId,
                            ':payment_intent_id' => $localIntentId,
                            ':invoice_id' => $generatedInvoiceId,
                            ':company_id' => (string)($row['company_id'] ?? ''),
                            ':amount' => $capturedAmount,
                            ':allocation_type' => 'spot_auto_invoice',
                        ]);
                    }
                }
            }
        }

        if ($generatedInvoiceId !== null) {
            $updGenerated = $pdo->prepare(
                'UPDATE pos_payment_intents SET generated_invoice_id = :generated_invoice_id WHERE id = :id'
            );
            $updGenerated->execute([
                ':generated_invoice_id' => $generatedInvoiceId,
                ':id' => $localIntentId,
            ]);
        }

        json_ok([
            'ok' => true,
            'localIntentId' => $localIntentId,
            'status' => $stripeStatus === 'succeeded' ? 'succeeded' : 'processing',
            'paidAmount' => $capturedAmount,
            'generatedInvoiceId' => $generatedInvoiceId,
            'invoiceId' => $invoiceId !== '' ? $invoiceId : $generatedInvoiceId,
        ]);
        break;

    case 'mark_mobile_payment_failed':
        $localIntentId = trim((string)($payload['localIntentId'] ?? ''));
        if ($localIntentId === '') {
            json_error('Intent locale mancante.', 422);
        }
        $reason = trim((string)($payload['reason'] ?? 'Pagamento annullato o non completato.'));
        $stmt = $pdo->prepare(
            'UPDATE pos_payment_intents
             SET status = :status,
                 failure_reason = :failure_reason
             WHERE id = :id AND team_id = :team_id'
        );
        $stmt->execute([
            ':status' => 'failed',
            ':failure_reason' => $reason,
            ':id' => $localIntentId,
            ':team_id' => $teamId,
        ]);
        json_ok(['ok' => true]);
        break;
}

json_error('Azione POS mobile non valida.', 422);
