<?php
declare(strict_types=1);

function tls_get(array $row, string $path, $fallback = null)
{
    foreach (explode('.', $path) as $part) {
        if (!is_array($row) || !array_key_exists($part, $row)) return $fallback;
        $row = $row[$part];
    }
    return $row;
}

function tls_date($value): ?string
{
    if (!$value) return null;
    try { return (new DateTimeImmutable((string)$value))->setTimezone(new DateTimeZone('UTC'))->format('Y-m-d H:i:s'); }
    catch (Throwable $e) { throw new InvalidArgumentException('Data sorgente non valida.'); }
}

function tls_calendar_date($value): ?string
{
    if (!$value) return null;
    $raw = (string)$value;
    if (preg_match('/^\d{4}-\d{2}-\d{2}$/D',$raw)) {
        $date = DateTimeImmutable::createFromFormat('!Y-m-d',$raw);
        if (!$date || $date->format('Y-m-d')!==$raw) throw new InvalidArgumentException('Data calendario non valida.');
        return $raw;
    }
    return (new DateTimeImmutable($raw))->format('Y-m-d');
}

function tls_tables(): array
{
    return ['companies'=>'companies', 'contacts'=>'crm_contacts', 'deals'=>'deals',
        'quotations'=>'quotations', 'projects'=>'projects', 'phases'=>'project_phases',
        'tasks'=>'work_tasks', 'tickets'=>'tickets', 'timetracking'=>'time_tracks',
        'invoices'=>'invoice_drafts', 'credit_notes'=>'credit_notes',
        'products'=>'products', 'subscriptions'=>'subscriptions'];
}

/** Only mapped source fields are updated. Nexora notes, custom fields and document lines are preserved. */
function tls_map(string $module, array $r, string $timeZone = 'Europe/Rome'): array
{
    if (!isset(tls_tables()[$module])) throw new InvalidArgumentException('Modulo non supportato.');
    $m = [];
    $maps = [
        'companies'=>['name'=>'name','vat_number'=>'vat_number','national_identification_number'=>'tax_code','website'=>'website',
            'primary_address.line_1'=>'address_line','primary_address.city'=>'city','primary_address.postal_code'=>'postal_code','primary_address.country'=>'country'],
        'contacts'=>['first_name'=>'first_name','last_name'=>'last_name'],
        'deals'=>['title'=>'title','estimated_value.amount'=>'value','estimated_value.currency'=>'currency',
            'lead.customer.id'=>'customer_id','lead.customer.type'=>'customer_type','current_phase.id'=>'stage_id','estimated_closing_date'=>'expected_closing_date'],
        'quotations'=>['name'=>'number','deal.id'=>'deal_id','customer.id'=>'customer_id','customer.type'=>'customer_type',
            'total.tax_exclusive.currency'=>'currency','valid_until'=>'valid_until'],
        'projects'=>['title'=>'name','reference'=>'code','customer.id'=>'company_id','starts_on'=>'data_inizio_progetto','due_on'=>'data_fine_progetto','start_date'=>'data_inizio_progetto','end_date'=>'data_fine_progetto','status'=>'status'],
        'phases'=>['title'=>'name','name'=>'name','project.id'=>'project_id','starts_on'=>'start_date','due_on'=>'deadline'],
        'tasks'=>['title'=>'name','project.id'=>'project_id','milestone.id'=>'phase_id','due_on'=>'deadline','end_date'=>'deadline','start_date'=>'start_date'],
        'tickets'=>['subject'=>'title','customer.id'=>'company_id','participant.customer.id'=>'company_id'],
        'invoices'=>['invoice_number'=>'number','invoicee.customer.id'=>'company_id','project.id'=>'project_id','total.payable.amount'=>'amount'],
        'credit_notes'=>['credit_note_number'=>'credit_note_number','credit_note_date'=>'credit_note_date','invoice.id'=>'invoice_id',
            'invoicee.customer.id'=>'customer_id','invoicee.customer.type'=>'customer_type','total.payable.currency'=>'currency','paid'=>'paid','paid_at'=>'paid_at'],
        'products'=>['name'=>'name','code'=>'sku','description'=>'description'],
        'subscriptions'=>['title'=>'title','customer.id'=>'customer_id','customer.type'=>'customer_type','starts_on'=>'starts_on','ends_on'=>'ends_on'],
        'timetracking'=>['description'=>'description','started_on'=>'start_at','hourly_rate.amount'=>'hourly_rate'],
    ];
    foreach ($maps[$module] as $path=>$column) {
        $sentinel = new stdClass();
        $value = tls_get($r, $path, $sentinel);
        if ($value !== $sentinel) $m[$column] = $value;
    }
    foreach (['emails'=>'email','telephones'=>'phone'] as $path=>$column) {
        if (in_array($module, ['companies','contacts'], true) && array_key_exists($path, $r)) {
            $items = $r[$path] ?? [];
            $m[$column] = (string)($items[0][$path === 'emails' ? 'email' : 'number'] ?? '');
        }
    }
    if ($module === 'contacts' && isset($r['companies'][0]['company']['id'])) $m['company_id'] = $r['companies'][0]['company']['id'];
    if ($module === 'projects' && !empty($r['customers'])) {
        if (count($r['customers']) > 1) throw new InvalidArgumentException('Progetto multi-cliente: selezionare una societa principale prima della sincronizzazione.');
        if (($r['customers'][0]['type'] ?? '') !== 'company') throw new InvalidArgumentException('Il progetto richiede un cliente societa.');
        $m['company_id'] = $r['customers'][0]['id'];
    }
    if ($module === 'projects' && ($m['status'] ?? '') === 'open') $m['status'] = 'active';
    if ($module === 'phases' && isset($r['status'])) $m['status'] = in_array($r['status'], ['closed','done'], true) ? 'done' : 'inProgress';
    if ($module === 'deals' && isset($r['status'])) $m['status'] = ['won'=>'won','lost'=>'lost','open'=>'open','new'=>'open'][$r['status']] ?? 'open';
    if ($module === 'quotations' && isset($r['status'])) $m['status'] = ['open'=>'sent','accepted'=>'accepted','expired'=>'rejected','draft'=>'draft'][$r['status']] ?? 'draft';
    if ($module === 'tasks' && array_key_exists('completed', $r)) $m['status'] = $r['completed'] ? 'done' : (empty($m['project_id']) ? 'backlog' : 'planned');
    if ($module === 'tasks' && ($r['customer']['type'] ?? '') === 'company') $m['company_id'] = $r['customer']['id'];
    if ($module === 'tasks' && isset($r['status'])) {
        $statuses = ['completed'=>'done','done'=>'done','in_progress'=>'inProgress','not_started'=>'planned','todo'=>'planned'];
        if (isset($statuses[$r['status']])) $m['status'] = $statuses[$r['status']];
    }
    if ($module === 'tasks' && isset($r['estimated_duration']['value'])) {
        $m['estimated_hours'] = (float)$r['estimated_duration']['value'] / (($r['estimated_duration']['unit'] ?? '') === 'min' ? 60 : 1);
    }
    if ($module === 'invoices' && isset($r['status'])) $m['status'] = $r['status'] === 'draft' ? 'draft' : 'exported';
    if ($module === 'credit_notes' && isset($r['status'])) $m['status'] = $r['status'] === 'booked' ? 'booked' : 'draft';
    if ($module === 'timetracking') {
        if (empty($r['started_on']) || !is_numeric($r['duration'] ?? null)) throw new InvalidArgumentException('Segnatempo senza inizio/durata.');
        if ((float)$r['duration'] < 0) throw new InvalidArgumentException('Durata negativa.');
        $zone = new DateTimeZone($timeZone);
        $dateOnly = empty($r['started_at']);
        $start = new DateTimeImmutable($dateOnly ? tls_calendar_date($r['started_on']).'T00:00:00' : $r['started_at'], $zone);
        $end = !$dateOnly && !empty($r['ended_at']) ? new DateTimeImmutable($r['ended_at'], $zone)
            : $start->setTimestamp($start->getTimestamp() + (int)$r['duration']);
        if ($end < $start) throw new InvalidArgumentException('Fine segnatempo precedente all inizio.');
        // Nexora's existing time_tracks API stores local wall times, not UTC strings.
        $m['start_at'] = $start->setTimezone($zone)->format('Y-m-d H:i:s');
        $m['end_at'] = $end->setTimezone($zone)->format('Y-m-d H:i:s');
        $m['tipo'] = $dateOnly ? 'teamleader_duration' : 'teamleader_clock';
        $m['billable'] = (int)(bool)($r['invoiceable'] ?? $r['billable'] ?? false);
        $m['name'] = (string)($r['description'] ?? '');
        if ($m['name']==='' && !empty($r['_sync_event']['title'])) $m['name'] = $r['_sync_event']['title'];
        $m['task_id'] = $m['company_id'] = $m['project_id'] = '';
        foreach (array_merge([$r['subject'] ?? []], $r['_sync_context'] ?? [], $r['relates_to'] ?? []) as $ref) {
            $field = ['todo'=>'task_id','task'=>'task_id','nextgenTask'=>'task_id',
                'company'=>'company_id','project'=>'project_id','nextgenProject'=>'project_id'][$ref['type'] ?? ''] ?? null;
            if ($field && !empty($ref['id'])) {
                if ($m[$field] !== '' && $m[$field] !== $ref['id']) throw new InvalidArgumentException('Relazioni segnatempo ambigue: '.$field);
                $m[$field] = $ref['id'];
            }
        }
        if (($r['subject']['type'] ?? '') === 'event' && !isset($r['_sync_event'])) throw new InvalidArgumentException('Evento collegato non ancora risolto.');
    }
    foreach (['expected_closing_date','valid_until','data_inizio_progetto','data_fine_progetto','start_date','deadline','credit_note_date','starts_on','ends_on'] as $c) {
        if (array_key_exists($c, $m)) $m[$c] = tls_calendar_date($m[$c]);
    }
    foreach (['paid_at'] as $c) if (isset($m[$c])) $m[$c] = tls_date($m[$c]);
    if (isset($r['updated_at'])) $m['updated_at'] = tls_date($r['updated_at']);
    return $m;
}

/** Resolve ancestors through scoped DB reads; never manufacture a task for company-only entries. */
function tls_inherit_links(array $data, array $source, callable $load): array
{
    $phaseIds = [];
    $merge = static function (array $parent) use (&$data): void {
        foreach (['company_id','project_id'] as $field) {
            if (empty($parent[$field])) continue;
            if (!empty($data[$field]) && $data[$field] !== $parent[$field]) throw new InvalidArgumentException('Associazioni sorgente non coerenti: '.$field);
            $data[$field] = $parent[$field];
        }
    };
    if (!empty($data['task_id'])) {
        $task = $load('work_tasks',$data['task_id']);
        $merge($task);
        if (!empty($task['phase_id'])) $phaseIds[] = $task['phase_id'];
        if (empty($data['name'])) $data['name'] = $task['name'] ?? '';
    }
    if (!empty($data['phase_id'])) $phaseIds[] = $data['phase_id'];
    foreach (array_merge([$source['subject'] ?? []], $source['_sync_context'] ?? [], $source['relates_to'] ?? []) as $ref) {
        if (($ref['type'] ?? '') === 'milestone' && !empty($ref['id'])) $phaseIds[] = $ref['id'];
    }
    foreach (array_unique($phaseIds) as $id) {
        $phase = $load('project_phases',$id);
        $merge($phase);
        if (array_key_exists('name',$data) && empty($data['name'])) $data['name'] = $phase['name'] ?? '';
    }
    if (!empty($data['project_id'])) $merge($load('projects',$data['project_id']));
    if (empty($data['company_id'])) {
        $contacts = [];
        foreach (array_merge([$source['subject'] ?? []],$source['_sync_context'] ?? []) as $ref) {
            if (($ref['type'] ?? '')==='contact') $contacts[$ref['id']] = true;
        }
        if (count($contacts)===1) $merge($load('crm_contacts',array_keys($contacts)[0]));
    }
    if (!empty($data['company_id'])) $load('companies',$data['company_id']);
    return $data;
}
