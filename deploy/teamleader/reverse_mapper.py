"""Pure reverse plans against the locally supplied Teamleader API Blueprint.

Records use install.sql column names. Updates may be patches, but `before` must
contain every changed field (and all companions of a changed composite field).
remote_record is an unwrapped .info data object, required for collection edits.
No network, generated IDs, implicit ancestor creation, or response placeholders.
SUPPORTED_MODULES advertises action capabilities, not unrestricted field support.
"""

from copy import deepcopy
import json
from datetime import date, datetime, timezone
from decimal import Decimal, InvalidOperation
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError


class Unsupported(ValueError):
    """The requested operation cannot be expressed safely by this adapter."""


class Conflict(ValueError):
    """Missing, ambiguous or invalid data/dependencies."""


SUPPORTED_MODULES = {
    'companies': frozenset(('create', 'update', 'delete')),
    'contacts': frozenset(('create', 'update', 'delete')),
    'deals': frozenset(('create', 'update', 'delete')),
    'projects': frozenset(('update', 'delete')),
    'phases': frozenset(('create', 'update', 'delete')),
    'tasks': frozenset(('update', 'delete')),
    'timetracking': frozenset(('create', 'update', 'delete')),
}
ALLOWED_ENDPOINTS = frozenset((
    '/companies.add', '/companies.update', '/contacts.add', '/contacts.update',
    '/deals.create', '/deals.update', '/projects.update',
    '/projects-v2/projects.update', '/milestones.create', '/milestones.update',
    '/tasks.update', '/tasks.complete', '/projects-v2/tasks.update',
    '/timeTracking.add', '/timeTracking.update',
    '/companies.delete', '/contacts.delete', '/deals.delete',
    '/projects.delete', '/projects-v2/projects.delete', '/milestones.delete',
    '/tasks.delete', '/projects-v2/tasks.delete', '/timeTracking.delete',
))
INFO_ENDPOINTS = {
    'companies': '/companies.info', 'contacts': '/contacts.info',
    'deals': '/deals.info', 'projects': '/projects.info',
    'phases': '/milestones.info', 'tasks': '/tasks.info',
    'timetracking': '/timeTracking.info',
}


def info_endpoint(module, remote_type=None):
    """Return a catalog path; remote_type is an optional Teamleader type string."""
    if module not in INFO_ENDPOINTS:
        raise Unsupported('Unsupported info module: ' + str(module))
    if remote_type == 'nextgenProject' and module == 'projects':
        return '/projects-v2/projects.info'
    if remote_type == 'nextgenTask' and module == 'tasks':
        return '/projects-v2/tasks.info'
    expected = {'companies': ('company',), 'contacts': ('contact',),
                'deals': ('deal',), 'projects': ('project',),
                'phases': ('milestone',), 'tasks': ('task', 'todo'),
                'timetracking': ('timetracking',)}
    if remote_type is not None and remote_type not in expected[module]:
        raise Unsupported('Unsupported info type')
    return INFO_ENDPOINTS[module]


_META = frozenset(('id', 'user_id', 'created_at', 'updated_at'))
_EMPTY = (None, '', False, 0, [], {})


def _number(value, field):
    try:
        result = Decimal(str(value))
    except (InvalidOperation, ValueError):
        raise Conflict('Invalid number: ' + field) from None
    if not result.is_finite() or result < 0:
        raise Conflict('Invalid nonnegative number: ' + field)
    return float(result)


def _boolean(value):
    if value not in (True, False, 0, 1, '0', '1'):
        raise Conflict('Expected boolean or SQL 0/1')
    return value in (True, 1, '1')


def _day(value):
    if value in (None, ''):
        return None
    try:
        return date.fromisoformat(value).isoformat()
    except (TypeError, ValueError):
        raise Conflict('Expected calendar YYYY-MM-DD') from None


def _instant(value, zone):
    try:
        dt = datetime.fromisoformat(value)
    except (ValueError, TypeError):
        raise Conflict('Invalid SQL datetime') from None
    if dt.tzinfo is not None:
        return dt.astimezone(zone)
    # Reject both nonexistent spring times and ambiguous autumn wall times.
    candidates = {dt.replace(tzinfo=zone, fold=fold).astimezone(timezone.utc)
                  for fold in (0, 1)
                  if dt.replace(tzinfo=zone, fold=fold).astimezone(timezone.utc)
                  .astimezone(zone).replace(tzinfo=None) == dt}
    if len(candidates) != 1:
        raise Conflict('Ambiguous/nonexistent local datetime; supply an offset')
    return candidates.pop().astimezone(zone)


def _ref(resolve, module, local_id, allowed):
    if local_id in (None, ''):
        raise Conflict('Missing dependency: ' + module)
    result = resolve(module, local_id)
    result = {'id': result} if isinstance(result, str) else result
    if not isinstance(result, dict) or not isinstance(result.get('id'), str) or not result['id']:
        raise Conflict('Unresolved dependency: ' + module)
    if result.get('type') is not None and result['type'] not in allowed:
        raise Unsupported('Incompatible dependency type: ' + module)
    return deepcopy(result)


def plan(module, action, record, before, remote_id, user_map, resolve_ref,
         time_zone='Europe/Rome', remote_record=None):
    """Return ordered {endpoint, body} calls, or fail atomically with no effects.

    Projects/tasks are update-only: local rows lack legacy create prerequisites.
    Pass a typed remote_id dict or a typed self resolve_ref result for v2 updates.
    Untyped IDs default to legacy. User mappings are explicit local -> remote IDs.
    """
    if action not in SUPPORTED_MODULES.get(module, ()):
        raise Unsupported('Unsupported module/action: %s/%s' % (module, action))
    if not isinstance(record, dict) or (action == 'update' and not isinstance(before, dict)):
        raise Conflict('Record and update before snapshot must be dictionaries')
    create = action == 'create'
    record = deepcopy(record)
    before = deepcopy(before or {})
    # Older MySQL schemas use LONGTEXT+JSON_VALID; trigger snapshots then contain
    # JSON strings instead of native JSON values. Normalize only known columns.
    for snapshot in (record,before):
        for field in ('custom_fields','aree_investimento','ricavi_annui','tags'):
            if isinstance(snapshot.get(field),str):
                try:snapshot[field]=json.loads(snapshot[field])
                except json.JSONDecodeError:raise Conflict('Invalid SQL JSON field: '+field) from None
    # Older Nexora clients stored the visible timer text only in `name`.
    # Teamleader exposes that value as `description`, so normalize the legacy
    # shape before computing the changed fields and building the request body.
    if module == 'timetracking':
        for snapshot in (record, before):
            if snapshot.get('description') in (None, '') and snapshot.get('name') not in (None, ''):
                snapshot['description'] = snapshot['name']
    current = {**before, **record}
    changed = set(record) if create else {k for k in record if k not in before or record[k] != before[k]}
    changed -= _META
    if action == 'delete':
        target = {'id': remote_id} if isinstance(remote_id, str) else remote_id
        if not isinstance(target, dict) or not isinstance(target.get('id'), str) or not target['id']:
            raise Conflict('Delete requires remote ID')
        rid, kind = target['id'], target.get('type')
        if module == 'projects':
            endpoint = '/projects-v2/projects.delete' if kind == 'nextgenProject' else '/projects.delete'
            body = {'id': rid}
            if endpoint == '/projects-v2/projects.delete': body['delete_strategy'] = 'unlink_tasks_and_time_trackings'
        elif module == 'tasks':
            endpoint = '/projects-v2/tasks.delete' if kind == 'nextgenTask' else '/tasks.delete'
            body = {'id': rid}
            if endpoint == '/projects-v2/tasks.delete': body['delete_strategy'] = 'delete_time_tracking'
        else:
            endpoint = {'companies':'/companies.delete','contacts':'/contacts.delete',
                        'deals':'/deals.delete','phases':'/milestones.delete',
                        'timetracking':'/timeTracking.delete'}[module]
            body = {'id': rid}
        return [{'endpoint': endpoint, 'body': body}]
    if module == 'timetracking':
        # The form stores the task/display label separately from description.
        changed.discard('name')
    if not create and any(k not in before for k in changed):
        raise Conflict('Before snapshot missing changed fields')
    try:
        zone = ZoneInfo(time_zone)
    except (ZoneInfoNotFoundError, TypeError, ValueError):
        raise Conflict('Invalid timezone') from None
    rid = None
    kind = None
    if create:
        if remote_id is not None:
            raise Conflict('Create cannot target an existing remote ID')
    else:
        target = {'id': remote_id} if isinstance(remote_id, str) else remote_id
        if not isinstance(target, dict) or not isinstance(target.get('id'), str) or not target['id']:
            raise Conflict('Update requires remote ID')
        rid, kind = target['id'], target.get('type')
        if module in ('projects', 'tasks') and current.get('id'):
            resolved = _ref(resolve_ref, module, current['id'],
                            ('project', 'nextgenProject') if module == 'projects' else ('task', 'todo', 'nextgenTask'))
            if resolved['id'] != rid or (kind and resolved.get('type') and kind != resolved['type']):
                raise Conflict('Remote identity mismatch')
            kind = kind or resolved.get('type')
        allowed = {'projects': ('project', 'nextgenProject'),
                   'tasks': ('task', 'todo', 'nextgenTask')}.get(module)
        if allowed and kind is not None and kind not in allowed:
            raise Unsupported('Unsupported target type')
    body = {} if create else {'id': rid}
    handled = set()
    extra = []

    def take(field, target=None, convert=lambda x: x):
        handled.add(field)
        if field in changed:
            body[target or field] = convert(current[field])

    def require(field):
        if current.get(field) in (None, ''):
            raise Conflict('Required field: ' + field)
        return current[field]

    def user(value):
        mapped = user_map.get(value)
        if not isinstance(mapped, str) or not mapped:
            raise Conflict('Unmapped user: ' + str(value))
        return mapped

    def relation(field, mod, types, target, nullable=False):
        handled.add(field)
        if field in changed:
            if current[field] in (None, '') and nullable:
                body[target] = None
            else:
                ref = _ref(resolve_ref, mod, current[field], types)
                body[target] = {'id': ref['id'], 'type': types[0]}

    def inactive(field, defaults):
        handled.add(field)
        if field in changed and (not create or current[field] not in defaults):
            raise Unsupported('Unsupported change: ' + field)

    if module in ('companies', 'contacts'):
        endpoint = '/' + module + ('.add' if create else '.update')
        for field in (('name', 'vat_number', 'website') if module == 'companies' else ('first_name', 'last_name')):
            take(field)
        if create:
            require('name' if module == 'companies' else 'last_name')
        for field in ('name', 'last_name'):
            if field in body and not body[field]:
                raise Conflict('Empty required name')
        take('notes', 'remarks')
        if module == 'companies':
            take('tax_code', 'national_identification_number')
            inactive('company_type', ('profit', None, ''))
        # Collections replace wholesale, so preserve every unrelated remote item.
        for field, collection, item_type, value_key in (
                ('email', 'emails', 'primary', 'email'),
                ('phone', 'telephones', 'phone', 'number')):
            handled.add(field)
            if field not in changed or (create and not current[field]):
                continue
            if not create and (not isinstance(remote_record, dict) or collection not in remote_record):
                raise Conflict('Collection snapshot required: ' + collection)
            items = deepcopy(remote_record[collection]) if not create else []
            if not isinstance(items, list) or any(not isinstance(i, dict) for i in items):
                raise Conflict('Invalid collection snapshot')
            if sum(i.get('type') == item_type for i in items) > 1:
                raise Conflict('Ambiguous primary collection item')
            items = [i for i in items if i.get('type') != item_type]
            if current[field]:
                items.append({'type': item_type, value_key: current[field]})
            body[collection] = items
        address_fields = ('address_line', 'postal_code', 'city', 'country')
        handled.update(address_fields if module == 'companies' else ())
        if module == 'companies' and changed.intersection(address_fields):
            if not create and (not isinstance(remote_record, dict) or 'addresses' not in remote_record):
                raise Conflict('Address snapshot required')
            items = deepcopy(remote_record['addresses']) if not create else []
            if not isinstance(items, list) or any(not isinstance(i, dict) for i in items):
                raise Conflict('Invalid addresses snapshot')
            primary = [i for i in items if i.get('type') == 'primary']
            if len(primary) > 1:
                raise Conflict('Ambiguous primary address')
            address = deepcopy(primary[0]['address']) if primary else {}
            for local, remote in zip(address_fields, ('line_1', 'postal_code', 'city', 'country')):
                if local in changed:
                    address[remote] = current[local] or None
            if not address.get('country') or any(k not in address for k in ('line_1', 'postal_code', 'city')):
                raise Conflict('Incomplete primary address')
            # Response-only area_level_two must never leak into request bodies.
            area = address.pop('area_level_two', None)
            if area:
                address['area_level_two_id'] = area['id']
            body['addresses'] = [i for i in items if i.get('type') != 'primary'] + [
                {'type': 'primary', 'address': address}]
    elif module == 'deals':
        endpoint = '/deals.' + ('create' if create else 'update')
        take('title')
        if create:
            require('title')
        take('notes', 'summary')
        take('assigned_to', 'responsible_user_id', lambda v: user(v) if v else None)
        take('expected_closing_date', 'estimated_closing_date', _day)
        take('probability', 'estimated_probability', lambda v: _number(v, 'probability') / 100)
        if body.get('estimated_probability', 0) > 1:
            raise Conflict('Probability must be 0..100')
        handled.update(('customer_id', 'customer_type', 'value', 'currency', 'stage_id'))
        if create or changed.intersection(('customer_id', 'customer_type')):
            typ = require('customer_type')
            if typ not in ('company', 'contact'):
                raise Unsupported('Unsupported deal customer type')
            ref = _ref(resolve_ref, 'companies' if typ == 'company' else 'contacts', require('customer_id'), (typ,))
            body['lead'] = {'customer': {'type': typ, 'id': ref['id']}}
        if changed.intersection(('value', 'currency')):
            body['estimated_value'] = {'amount': _number(require('value'), 'value'), 'currency': require('currency')}
        if 'stage_id' in changed and current['stage_id']:
            if not create:
                raise Unsupported('Deal phase changes require deals.move')
            body['phase_id'] = _ref(resolve_ref, 'deal_stages', current['stage_id'], ('dealPhase',))['id']
        elif 'stage_id' in changed and not create:
            raise Unsupported('Cannot clear deal phase')
        inactive('status', ('open', None, ''))
    elif module == 'projects':
        v2 = kind == 'nextgenProject'
        endpoint = '/projects-v2/projects.update' if v2 else '/projects.update'
        take('name', 'title')
        take('notes', 'description')
        take('data_inizio_progetto', 'start_date' if v2 else 'starts_on', _day)
        if v2:
            take('data_fine_progetto', 'end_date', _day)
        else:
            relation('company_id', 'companies', ('company',), 'customer', True)
        # Even documented legacy status writes can cascade lifecycle behavior.
    elif module == 'phases':
        endpoint = '/milestones.' + ('create' if create else 'update')
        take('name')
        take('notes', 'description')
        take('start_date', 'starts_on', _day)
        take('deadline', 'due_on', _day)
        take('assigned_user_id', 'responsible_user_id', user)
        if create:
            require('name'); require('deadline'); require('assigned_user_id')
            ref = _ref(resolve_ref, 'projects', require('project_id'), ('project',))
            body['project_id'] = ref['id']
            handled.add('project_id')
        inactive('status', ('notStarted', 'inProgress', None, ''))
        inactive('phase_order', (0, None))
    elif module == 'tasks':
        v2 = kind == 'nextgenTask'
        endpoint = '/projects-v2/tasks.update' if v2 else '/tasks.update'
        take('name', 'title')
        take('description')
        take('deadline', 'end_date' if v2 else 'due_on', _day)
        take('estimated_hours', 'time_estimated' if v2 else 'estimated_duration',
             lambda v: {'value': _number(v, 'estimated_hours') * (1 if v2 else 60),
                        'unit': 'hours' if v2 else 'min'})
        if v2:
            take('start_date', convert=_day)
            take('status', convert=lambda v: {'backlog': 'to_do', 'planned': 'to_do',
                                            'inProgress': 'in_progress', 'done': 'done'}.get(v))
            if 'status' in body and body['status'] is None:
                raise Unsupported('Unknown task status')
        else:
            take('assignee_id', 'assignee', lambda v: {'type': 'user', 'id': user(v)} if v else None)
            relation('company_id', 'companies', ('company',), 'customer')
            relation('phase_id', 'phases', ('milestone',), 'milestone_id', True)
            if 'milestone_id' in body and body['milestone_id'] is not None:
                body['milestone_id'] = body['milestone_id']['id']
            handled.add('status')
            if 'status' in changed:
                if current['status'] == 'done' and before['status'] != 'done':
                    extra.append({'endpoint': '/tasks.complete', 'body': {'id': rid}})
                else:
                    raise Unsupported('Legacy task status requires unsupported lifecycle/scheduling')
        # Parent moves, billing modes and v2 assignment require separate endpoints.
    else:
        endpoint = '/timeTracking.' + ('add' if create else 'update')
        handled.update(('start_at', 'end_at', 'tipo', 'tracker_user_id', 'task_id', 'company_id', 'project_id'))
        if create and 'hourly_rate' in changed:
            rate = current['hourly_rate']
            if rate not in (None, '') and _number(rate, 'hourly_rate') != 0:
                raise Unsupported('Nonzero hourly_rate is not writable')
            handled.add('hourly_rate')
        if not create and 'tracker_user_id' in changed:
            raise Unsupported('timeTracking.update does not accept user_id')
        if create:
            # Nexora-created rows may leave tracker_user_id empty while the
            # owning user_id is still the correct Teamleader operator.
            tracker_id = current.get('tracker_user_id') or current.get('user_id')
            body['user_id'] = user(tracker_id)
        # Both update variants REQUIRE a start and duration, even for note edits.
        if create or changed:
            start = _instant(require('start_at'), zone)
            end = _instant(require('end_at'), zone)
            seconds = (end.astimezone(timezone.utc) - start.astimezone(timezone.utc)).total_seconds()
            if seconds < 0 or not seconds.is_integer():
                raise Conflict('Invalid duration in seconds')
            tipo = current.get('tipo', '')
            if not isinstance(tipo, str):
                raise Conflict('Timetracking tipo must be a string')
            if tipo == 'teamleader_duration':
                body['started_on'] = start.date().isoformat()
                body['duration'] = int(seconds)
            else:
                # Clock tracking accepts the start/end pair. Do not mix it
                # with the duration-only started_on variant.
                body['started_at'] = start.isoformat()
                body['ended_at'] = end.isoformat()
            handled.add('start_at')
            handled.add('end_at')
            handled.add('tipo')
            handled.add('hourly_rate')
            if tipo == 'teamleader_duration':
                handled.add('duration')
        if current.get('description') in (None, ''):
            handled.add('description')
        else:
            take('description')
        take('billable', 'invoiceable', _boolean)
        if create or changed.intersection(('task_id', 'company_id', 'project_id')):
            if current.get('task_id'):
                ref = _ref(resolve_ref, 'tasks', current['task_id'], ('task', 'todo'))
                body['subject'] = {'type': 'todo', 'id': ref['id']}
            elif current.get('company_id'):
                ref = _ref(resolve_ref, 'companies', current['company_id'], ('company',))
                body['subject'] = {'type': 'company', 'id': ref['id']}
            elif current.get('project_id'):
                raise Unsupported('Project is not a documented timeTracking subject')
            elif not create:
                body['subject'] = None

    for field in changed - handled:
        if not create or current[field] not in _EMPTY:
            raise Unsupported('Unmapped field: ' + field)
    nonnullable = {
        '/companies.add': ('name',), '/companies.update': ('name', 'website'),
        '/contacts.add': ('last_name',), '/contacts.update': ('last_name',),
        '/deals.create': ('title',), '/deals.update': ('title',),
        '/projects.update': ('title', 'starts_on', 'description'),
        '/projects-v2/projects.update': ('title',),
        '/milestones.create': ('name', 'due_on', 'responsible_user_id'),
        '/milestones.update': ('name', 'due_on', 'description', 'responsible_user_id'),
        '/tasks.update': ('title', 'due_on', 'description'),
        '/projects-v2/tasks.update': ('title',),
    }
    for field in nonnullable.get(endpoint, ()):
        if field in body and (body[field] is None or (field in ('title', 'name', 'last_name', 'due_on', 'starts_on') and body[field] == '')):
            raise Conflict('Cannot clear required/nonnullable field: ' + field)
    if not create and remote_record is not None:
        if not isinstance(remote_record, dict):
            raise Conflict('Remote snapshot must be an unwrapped info object')
        if remote_record.get('id', rid) != rid:
            raise Conflict('Remote snapshot identity mismatch')

        def check(remote_field, expected):
            if remote_field in remote_record and remote_record[remote_field] != expected:
                raise Conflict('Remote changed since before: ' + remote_field)

        scalar_maps = {
            'companies': {'name': 'name', 'vat_number': 'vat_number', 'tax_code': 'national_identification_number', 'website': 'website', 'notes': 'remarks'},
            'contacts': {'first_name': 'first_name', 'last_name': 'last_name', 'notes': 'remarks'},
            'deals': {'title': 'title', 'notes': 'summary', 'expected_closing_date': 'estimated_closing_date'},
            'projects': {'name': 'title', 'notes': 'description', 'data_inizio_progetto': 'start_date' if kind == 'nextgenProject' else 'starts_on', 'data_fine_progetto': 'end_date'},
            'phases': {'name': 'name', 'notes': 'description', 'start_date': 'starts_on', 'deadline': 'due_on'},
            'tasks': {'name': 'title', 'description': 'description', 'deadline': 'end_date' if kind == 'nextgenTask' else 'due_on'},
            'timetracking': {'description': 'description'},
        }
        for local, remote in scalar_maps[module].items():
            if local in changed:
                check(remote, before[local])
        if module in ('companies', 'contacts'):
            for local, collection, typ, key in (('email', 'emails', 'primary', 'email'), ('phone', 'telephones', 'phone', 'number')):
                if local in changed:
                    old = [item[key] for item in remote_record.get(collection, []) if item.get('type') == typ]
                    if old != ([before[local]] if before[local] else []):
                        raise Conflict('Remote collection changed: ' + collection)
            if module == 'companies' and changed.intersection(address_fields):
                primary = [item for item in remote_record['addresses'] if item.get('type') == 'primary']
                old_address = primary[0]['address'] if primary else {}
                for local, remote in zip(address_fields, ('line_1', 'postal_code', 'city', 'country')):
                    if local in changed and (old_address.get(remote) or '') != (before[local] or ''):
                        raise Conflict('Remote address changed: ' + remote)
        if module == 'tasks' and 'status' in changed:
            if kind == 'nextgenTask':
                check('status', {'backlog': 'to_do', 'planned': 'to_do',
                                 'inProgress': 'in_progress', 'done': 'done'}[before['status']])
            else:
                check('completed', before['status'] == 'done')
        if module == 'timetracking' and changed:
            if remote_record.get('locked') or remote_record.get('billing_info'):
                raise Unsupported('Locked or billed timetracking requires manual review')
            if 'billable' in changed:
                check('invoiceable', _boolean(before['billable']))
            if 'user' in remote_record and before.get('tracker_user_id'):
                if remote_record['user']['id'] != user(before['tracker_user_id']):
                    raise Conflict('Remote tracker changed')
            old_start = _instant(before['start_at'], zone)
            old_end = _instant(before['end_at'], zone)
            check('duration', int((old_end.astimezone(timezone.utc) - old_start.astimezone(timezone.utc)).total_seconds()))
            if before.get('tipo') == 'teamleader_duration':
                check('started_on', old_start.date().isoformat())
            elif remote_record.get('started_at'):
                if _instant(remote_record['started_at'], zone) != old_start:
                    raise Conflict('Remote start changed')
            if changed.intersection(('task_id', 'company_id', 'project_id')):
                old_subject = None
                for local, mod, types, typ in (('task_id', 'tasks', ('task', 'todo'), 'todo'), ('company_id', 'companies', ('company',), 'company')):
                    if before.get(local):
                        ref = _ref(resolve_ref, mod, before[local], types)
                        old_subject = {'type': typ, 'id': ref['id']}
                        break
                check('subject', old_subject)
    if endpoint not in ALLOWED_ENDPOINTS:
        raise Unsupported('Endpoint is not whitelisted')
    if not create and not changed:
        return []
    calls = ([{'endpoint': endpoint, 'body': body}] if create or len(body) > 1 else []) + extra
    return deepcopy(calls)
