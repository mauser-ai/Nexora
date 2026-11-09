<?php
// Endpoint generico per entità semplici:
// vacations, availability, billing_profile, youdox_config, email_signature, ui_state, tickets

require_once __DIR__ . '/../bootstrap.php';

$userId = require_auth();
$scope = scope_filter_sql('user_id', scoped_user_ids($userId));
$method = http_method();
$entity = $_GET['entity'] ?? '';
$id     = $_GET['id']     ?? null;

// ── VACATIONS ─────────────────────────────────────────────────────────────────
if ($entity === 'vacations') {
    if ($method === 'POST') {
        $b = request_body();
        $id = str_val($b['id'] ?? uuid4());
        db()->prepare('INSERT INTO vacation_periods (id,user_id,start_date,end_date,label) VALUES (?,?,?,?,?)')
           ->execute([$id,$userId,to_date($b['startDate']??null)??date('Y-m-d'),to_date($b['endDate']??null)??date('Y-m-d'),str_val($b['label']??'')]);
        json_ok(['id'=>$id],201);
    }
    if ($method === 'DELETE') {
        if (!$id) json_error('id mancante');
        db()->prepare('DELETE FROM vacation_periods WHERE id=? AND user_id=?')->execute([$id,$userId]);
        json_ok(['ok'=>true]);
    }
}

// ── AVAILABILITY ──────────────────────────────────────────────────────────────
if ($entity === 'availability') {
    if ($method === 'POST') {
        $b = request_body();
        db()->prepare(
            'INSERT INTO user_availability (user_id,weekday,hours,is_off) VALUES (?,?,?,?)
             ON DUPLICATE KEY UPDATE hours=VALUES(hours), is_off=VALUES(is_off)'
        )->execute([$userId,(int)($b['weekday']??1),(float)($b['hours']??8),bool_val($b['isOff']??false)?1:0]);
        json_ok(['ok'=>true]);
    }
}

// ── TICKETS ───────────────────────────────────────────────────────────────────
if ($entity === 'tickets') {
    if ($method === 'POST') {
        $b  = request_body();
        $id = str_val($b['id'] ?? uuid4());
        db()->prepare('INSERT INTO tickets (id,user_id,company_id,title,recipient_email,status,entries) VALUES (?,?,?,?,?,?,?)')
           ->execute([$id,$userId,str_val($b['companyId']??''),str_val($b['title']??''),
                      str_val($b['recipientEmail']??''),str_val($b['status']??'newTicket'),
                      json_encode($b['entries']??[])]);
        json_ok(['id'=>$id],201);
    }
    if ($method === 'PUT') {
        if (!$id) json_error('id mancante');
        $b = request_body();
        db()->prepare('UPDATE tickets SET status=?,entries=? WHERE id=? AND ' . $scope['sql'])
           ->execute(array_merge([str_val($b['status']??'newTicket'),json_encode($b['entries']??[]),$id], $scope['params']));
        json_ok(['ok'=>true]);
    }
    if ($method === 'DELETE') {
        if (!$id) json_error('id mancante');
        db()->prepare('DELETE FROM tickets WHERE id=? AND ' . $scope['sql'])
           ->execute(array_merge([$id], $scope['params']));
        json_ok(['ok'=>true]);
    }
}

// ── BILLING PROFILE ───────────────────────────────────────────────────────────
if ($entity === 'billing_profile') {
    if ($method === 'PUT') {
        $b = request_body();
        // Salva nel team se l'utente appartiene a uno, altrimenti nell'utente
        $row = db()->prepare('SELECT team_id FROM users WHERE id=? LIMIT 1');
        $row->execute([$userId]);
        $teamId = $row->fetchColumn();
        if ($teamId) {
            db()->prepare('UPDATE teams SET billing_profile=? WHERE id=?')
               ->execute([json_encode($b),$teamId]);
        } else {
            db()->prepare('UPDATE users SET billing_profile=? WHERE id=?')
               ->execute([json_encode($b),$userId]);
        }
        json_ok(['ok'=>true]);
    }
    if ($method === 'GET') {
        $row = db()->prepare('SELECT billing_profile, team_id FROM users WHERE id=? LIMIT 1');
        $row->execute([$userId]);
        $u = $row->fetch();
        $profile = json_col($u['billing_profile']??'{}', (object)[]);
        if (!empty($u['team_id'])) {
            $t = db()->prepare('SELECT billing_profile FROM teams WHERE id=? LIMIT 1');
            $t->execute([$u['team_id']]);
            $tr = $t->fetch();
            if ($tr) $profile = json_col($tr['billing_profile']??'{}', (object)[]);
        }
        json_ok($profile);
    }
}

// ── YOUDOX CONFIG ─────────────────────────────────────────────────────────────
if ($entity === 'youdox_config') {
    if ($method === 'PUT') {
        $b = request_body();
        $row = db()->prepare('SELECT team_id FROM users WHERE id=? LIMIT 1');
        $row->execute([$userId]);
        $teamId = $row->fetchColumn();
        if ($teamId) {
            db()->prepare('UPDATE teams SET youdox_config=? WHERE id=?')->execute([json_encode($b),$teamId]);
        } else {
            db()->prepare('UPDATE users SET youdox_config=? WHERE id=?')->execute([json_encode($b),$userId]);
        }
        json_ok(['ok'=>true]);
    }
    if ($method === 'GET') {
        $row = db()->prepare('SELECT youdox_config, team_id FROM users WHERE id=? LIMIT 1');
        $row->execute([$userId]);
        $u = $row->fetch();
        $cfg = json_col($u['youdox_config']??'{}', (object)[]);
        if (!empty($u['team_id'])) {
            $t = db()->prepare('SELECT youdox_config FROM teams WHERE id=? LIMIT 1');
            $t->execute([$u['team_id']]);
            $tr = $t->fetch();
            if ($tr) $cfg = json_col($tr['youdox_config']??'{}', (object)[]);
        }
        json_ok($cfg);
    }
}

// ── EMAIL SIGNATURE ───────────────────────────────────────────────────────────
if ($entity === 'email_signature') {
    if ($method === 'PUT') {
        $b = request_body();
        db()->prepare('UPDATE users SET email_signature_html=? WHERE id=?')
           ->execute([str_val($b['html']??''),$userId]);
        json_ok(['ok'=>true]);
    }
}

// ── UI STATE ──────────────────────────────────────────────────────────────────
if ($entity === 'ui_state') {
    if ($method === 'GET') {
        $row = db()->prepare('SELECT ui_state FROM users WHERE id=? LIMIT 1');
        $row->execute([$userId]);
        $u = $row->fetch();
        json_ok(json_col($u['ui_state']??'{}', (object)[]));
    }
    if ($method === 'PUT') {
        $b = request_body();
        db()->prepare('UPDATE users SET ui_state=? WHERE id=?')
           ->execute([json_encode($b),$userId]);
        json_ok(['ok'=>true]);
    }
}

json_error('Entità o metodo non supportato', 400);
