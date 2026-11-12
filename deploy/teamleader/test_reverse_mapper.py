"""Offline unittest contracts transcribed from the supplied API Blueprint."""

from copy import deepcopy
import importlib.util
from pathlib import Path
import unittest

_spec = importlib.util.spec_from_file_location('reverse_mapper', Path(__file__).with_name('reverse_mapper.py'))
mapper = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(mapper)
plan, Conflict, Unsupported = mapper.plan, mapper.Conflict, mapper.Unsupported


class ReverseMapperTests(unittest.TestCase):
    def setUp(self):
        self.refs = {
            ('companies', 'c'): {'id': 'remote-company', 'type': 'company'},
            ('contacts', 'p'): {'id': 'remote-person', 'type': 'contact'},
            ('projects', 'p'): {'id': 'remote-project', 'type': 'project'},
            ('phases', 'f'): {'id': 'remote-phase', 'type': 'milestone'},
            ('tasks', 't'): {'id': 'remote-task', 'type': 'task'},
            ('deal_stages', 's'): {'id': 'remote-stage', 'type': 'dealPhase'},
        }
        self.users = {'u': 'remote-user'}
        self.track = {'start_at': '2026-07-01 09:00:00', 'end_at': '2026-07-01 10:30:00',
                      'tracker_user_id': 'u', 'tipo': 'teamleader_clock',
                      'billable': '0', 'description': 'Work', 'task_id': 't',
                      'company_id': 'c', 'project_id': 'p'}

    def resolve(self, module, local_id):
        return self.refs.get((module, local_id))

    def call(self, module, record, before=None, remote=None, action='update', rid='remote', **kwargs):
        return plan(module, action, record, before, None if action == 'create' else rid,
                    self.users, self.resolve, remote_record=remote, **kwargs)

    def test_info_public_contract(self):
        self.assertEqual(mapper.info_endpoint('projects', 'nextgenProject'), '/projects-v2/projects.info')
        self.assertEqual(mapper.info_endpoint('tasks', 'nextgenTask'), '/projects-v2/tasks.info')
        self.assertEqual(mapper.INFO_ENDPOINTS['timetracking'], '/timeTracking.info')
        with self.assertRaises(Unsupported):
            mapper.info_endpoint('projects', 'nextgenTask')

    def test_registry_and_forbidden_operations(self):
        self.assertEqual(set(mapper.SUPPORTED_MODULES), {'companies', 'contacts', 'deals', 'projects', 'phases', 'tasks', 'timetracking'})
        for module in mapper.SUPPORTED_MODULES:
            for action in ('delete', 'book', 'send', 'complete', '../companies.add'):
                with self.subTest(module=module, action=action), self.assertRaises(Unsupported):
                    self.call(module, {}, {}, action=action)
        for module in ('invoices', 'quotations', 'bookings', 'tickets', 'products'):
            with self.assertRaises(Unsupported):
                self.call(module, {}, {}, action='create')

    def test_no_invented_create_prerequisites(self):
        for module in ('projects', 'tasks'):
            with self.assertRaises(Unsupported):
                self.call(module, {'name': 'X'}, action='create')

    def test_company_create_ids_and_scalar_names(self):
        result = self.call('companies', {'id': 'local', 'user_id': 'owner', 'name': 'Acme',
                           'tax_code': '123', 'notes': 'Text'}, action='create')
        self.assertEqual(result, [{'endpoint': '/companies.add', 'body': {
            'name': 'Acme', 'national_identification_number': '123', 'remarks': 'Text'}}])
        with self.assertRaises(Conflict):
            plan('companies', 'create', {'name': 'A'}, None, 'local', {}, self.resolve)

    def test_update_only_changed_and_patch_semantics(self):
        self.assertEqual(self.call('companies', {'name': 'New'}, {'name': 'Old', 'notes': 'keep'}),
                         [{'endpoint': '/companies.update', 'body': {'id': 'remote', 'name': 'New'}}])
        self.assertEqual(self.call('companies', {'name': 'Same'}, {'name': 'Same'}), [])
        with self.assertRaises(Conflict):
            self.call('companies', {'name': 'New'}, {})
        with self.assertRaises(Conflict):
            self.call('companies', {}, {}, rid='')

    def test_unknown_nonempty_and_unsupported_clear(self):
        with self.assertRaises(Unsupported):
            self.call('companies', {'name': 'Acme', 'pec': 'x'}, action='create')
        with self.assertRaises(Unsupported):
            self.call('companies', {'pec': ''}, {'pec': 'old'})
        self.call('companies', {'name': 'Acme', 'pec': '', 'custom_fields': {}}, action='create')

    def test_contact_link_not_silently_discarded(self):
        self.call('contacts', {'last_name': 'Smith', 'first_name': 'John'}, action='create')
        with self.assertRaises(Unsupported):
            self.call('contacts', {'last_name': 'Smith', 'company_id': 'c'}, action='create')

    def test_collection_preservation_and_preconditions(self):
        remote = {'emails': [{'type': 'primary', 'email': 'old'}, {'type': 'invoicing', 'email': 'billing'}]}
        original = deepcopy(remote)
        result = self.call('companies', {'email': 'new'}, {'email': 'old'}, remote)
        self.assertEqual(result[0]['body']['emails'], [remote['emails'][1], {'type': 'primary', 'email': 'new'}])
        self.assertEqual(remote, original)
        with self.assertRaises(Conflict):
            self.call('companies', {'email': 'new'}, {'email': 'old'})
        with self.assertRaises(Conflict):
            self.call('companies', {'email': 'new'}, {'email': 'stale'}, remote)
        remote['emails'].append({'type': 'primary', 'email': 'duplicate'})
        with self.assertRaises(Conflict):
            self.call('companies', {'email': 'new'}, {'email': 'old'}, remote)

    def test_phone_and_email_clear_preserve_other_types(self):
        remote = {'telephones': [{'type': 'phone', 'number': 'old'}, {'type': 'mobile', 'number': 'mobile'}]}
        result = self.call('contacts', {'phone': ''}, {'phone': 'old'}, remote)
        self.assertEqual(result[0]['body']['telephones'], [{'type': 'mobile', 'number': 'mobile'}])

    def test_address_contract(self):
        record = {'name': 'A', 'address_line': 'Via Uno', 'city': 'Roma', 'postal_code': '00100', 'country': 'IT'}
        body = self.call('companies', record, action='create')[0]['body']
        self.assertEqual(body['addresses'], [{'type': 'primary', 'address': {
            'line_1': 'Via Uno', 'city': 'Roma', 'postal_code': '00100', 'country': 'IT'}}])
        with self.assertRaises(Conflict):
            self.call('companies', {'city': 'New'}, {'city': 'Old'})

    def test_deal_contract_and_resolution(self):
        body = self.call('deals', {'title': 'Sale', 'customer_type': 'company', 'customer_id': 'c',
                         'value': '123.45', 'currency': 'EUR', 'probability': 25,
                         'stage_id': 's', 'status': 'open'}, action='create')[0]['body']
        self.assertEqual(body['lead'], {'customer': {'type': 'company', 'id': 'remote-company'}})
        self.assertEqual(body['phase_id'], 'remote-stage')
        self.assertEqual(body['estimated_probability'], .25)
        self.assertEqual(body['estimated_value'], {'amount': 123.45, 'currency': 'EUR'})
        self.assertNotIn('status', body)
        with self.assertRaises(Conflict):
            self.call('deals', {'title': 'Sale', 'customer_type': 'company', 'customer_id': 'missing'}, action='create')

    def test_deal_unsafe_stage_and_status(self):
        for record, before in (({'stage_id': 's'}, {'stage_id': 'old'}),
                               ({'status': 'won'}, {'status': 'open'})):
            with self.assertRaises(Unsupported):
                self.call('deals', record, before)
        with self.assertRaises(Conflict):
            self.call('deals', {'value': 'nan'}, {'value': 10, 'currency': 'EUR'})

    def test_legacy_project_update_and_v2_selection(self):
        self.assertEqual(self.call('projects', {'name': 'New'}, {'name': 'Old'})[0]['endpoint'], '/projects.update')
        self.refs['projects', 'p']['type'] = 'nextgenProject'
        result = self.call('projects', {'id': 'p', 'name': 'New', 'data_fine_progetto': '2026-11-30'},
                           {'id': 'p', 'name': 'Old', 'data_fine_progetto': None}, rid='remote-project')
        self.assertEqual(result[0], {'endpoint': '/projects-v2/projects.update',
                         'body': {'id': 'remote-project', 'title': 'New', 'end_date': '2026-11-30'}})
        with self.assertRaises(Conflict):
            self.call('projects', {'id': 'p', 'name': 'New'}, {'name': 'Old'})
        for field, value, old in (('status', 'done', 'active'), ('data_fine_progetto', '2026-11-30', None)):
            with self.assertRaises(Unsupported):
                self.call('projects', {field: value}, {field: old})

    def test_phase_create_required_fields_and_legacy_parent(self):
        record = {'project_id': 'p', 'name': 'Phase', 'deadline': '2026-12-01', 'assigned_user_id': 'u'}
        body = self.call('phases', record, action='create')[0]['body']
        self.assertEqual(body, {'project_id': 'remote-project', 'name': 'Phase', 'due_on': '2026-12-01', 'responsible_user_id': 'remote-user'})
        for field in record:
            with self.subTest(field=field), self.assertRaises(Conflict):
                self.call('phases', {k: v for k, v in record.items() if k != field}, action='create')
        self.refs['projects', 'p']['type'] = 'nextgenProject'
        with self.assertRaises(Unsupported):
            self.call('phases', record, action='create')

    def test_phase_update_no_unsafe_close(self):
        with self.assertRaises(Unsupported):
            self.call('phases', {'status': 'done'}, {'status': 'inProgress'})

    def test_legacy_task_update_then_complete(self):
        result = self.call('tasks', {'name': 'New', 'status': 'done', 'estimated_hours': 1.5},
                           {'name': 'Old', 'status': 'planned', 'estimated_hours': 0})
        self.assertEqual(result, [{'endpoint': '/tasks.update', 'body': {'id': 'remote', 'title': 'New',
                          'estimated_duration': {'unit': 'min', 'value': 90}}},
                         {'endpoint': '/tasks.complete', 'body': {'id': 'remote'}}])
        self.assertEqual(self.call('tasks', {'status': 'done'}, {'status': 'planned'}),
                         [{'endpoint': '/tasks.complete', 'body': {'id': 'remote'}}])
        for status in ('planned', 'inProgress'):
            with self.assertRaises(Unsupported):
                self.call('tasks', {'status': status}, {'status': 'done'})

    def test_task_phase_reference_is_string_not_object(self):
        body = self.call('tasks', {'phase_id': 'f'}, {'phase_id': ''})[0]['body']
        self.assertEqual(body['milestone_id'], 'remote-phase')
        self.assertIsNone(self.call('tasks', {'phase_id': ''}, {'phase_id': 'f'})[0]['body']['milestone_id'])

    def test_nextgen_task_update_contract(self):
        result = self.call('tasks', {'status': 'done', 'estimated_hours': 2, 'start_date': '2026-11-01'},
                           {'status': 'planned', 'estimated_hours': 0, 'start_date': None},
                           rid={'id': 'remote', 'type': 'nextgenTask'})
        self.assertEqual(result, [{'endpoint': '/projects-v2/tasks.update', 'body': {
            'id': 'remote', 'status': 'done', 'time_estimated': {'value': 2, 'unit': 'hours'}, 'start_date': '2026-11-01'}}])
        with self.assertRaises(Unsupported):
            self.call('tasks', {'assignee_id': 'u'}, {'assignee_id': ''}, rid={'id': 'remote', 'type': 'nextgenTask'})

    def test_time_create_actual_contract_and_purity(self):
        before = deepcopy(self.track)
        body = self.call('timetracking', self.track, action='create')[0]['body']
        self.assertEqual(body, {'started_on': '2026-07-01', 'started_at': '2026-07-01T09:00:00+02:00',
                         'ended_at': '2026-07-01T10:30:00+02:00', 'duration': 5400,
                         'invoiceable': False, 'user_id': 'remote-user', 'description': 'Work',
                         'subject': {'type': 'todo', 'id': 'remote-task'}})
        self.assertNotIn('work_type_id', body)
        self.assertEqual(self.track, before)

    def test_full_default_time_row_with_local_display_and_tipo(self):
        expected = self.call('timetracking', self.track, action='create')
        for hourly_rate in (0, None, '0.00'):
            record = {**self.track, 'id': 'local-track', 'user_id': 'local-owner',
                      'name': 'Task title shown in the form', 'hourly_rate': hourly_rate,
                      'tipo': 'Consulenza', 'created_at': '2026-07-01 09:00:00',
                      'updated_at': '2026-07-01 10:30:00'}
            with self.subTest(hourly_rate=hourly_rate):
                self.assertEqual(self.call('timetracking', record, action='create'), expected)
                self.assertEqual(self.call('timetracking', {'description': 'New'}, record),
                                 self.call('timetracking', {'description': 'New'}, self.track))

    def test_time_display_name_only_update_is_noop(self):
        self.assertEqual(self.call('timetracking', {'name': 'New task title'},
                                   {**self.track, 'name': 'Old task title'}), [])
        # Display-only patches need neither timing companions nor a name baseline.
        self.assertEqual(self.call('timetracking', {'name': 'New task title'}, {}), [])
        self.assertEqual(self.call('timetracking', {'name': 'New task title'},
                                   {'name': 'Old task title'}, {'locked': True}), [])

    def test_time_free_text_tipo_uses_clock_not_date_only(self):
        for tipo in ('', 'Consulenza', 'teamleader_clock', 'teamleader_duration_extra'):
            with self.subTest(tipo=tipo):
                body = self.call('timetracking', {**self.track, 'tipo': tipo}, action='create')[0]['body']
                self.assertIn('started_at', body)
                self.assertIn('started_on', body)
                self.assertIn('ended_at', body)
        with self.assertRaises(Conflict):
            self.call('timetracking', {**self.track, 'tipo': []}, action='create')

    def test_time_nonzero_hourly_rate_still_rejected(self):
        with self.assertRaises(Unsupported):
            self.call('timetracking', {**self.track, 'name': 'Task title', 'hourly_rate': 50}, action='create')

    def test_time_winter_duration_and_company_fallback(self):
        record = {**self.track, 'task_id': '', 'tipo': 'teamleader_duration',
                  'start_at': '2026-01-02 00:00:00', 'end_at': '2026-01-02 02:00:00'}
        body = self.call('timetracking', record, action='create')[0]['body']
        self.assertEqual(body['started_on'], '2026-01-02')
        self.assertEqual(body['duration'], 7200)
        self.assertIn('started_at', body)
        self.assertIn('ended_at', body)
        self.assertEqual(body['subject']['type'], 'company')
        record['tipo'] = 'teamleader_clock'
        self.assertTrue(self.call('timetracking', record, action='create')[0]['body']['started_at'].endswith('+01:00'))

    def test_time_project_only_and_nextgen_subject_rejected(self):
        with self.assertRaises(Unsupported):
            self.call('timetracking', {**self.track, 'task_id': '', 'company_id': ''}, action='create')
        self.refs['tasks', 't']['type'] = 'nextgenTask'
        with self.assertRaises(Unsupported):
            self.call('timetracking', self.track, action='create')

    def test_time_update_required_pair_and_no_user_id(self):
        body = self.call('timetracking', {'description': 'New'}, self.track)[0]['body']
        self.assertEqual(body, {'id': 'remote', 'description': 'New', 'started_on': '2026-07-01',
                                'started_at': '2026-07-01T09:00:00+02:00',
                                'ended_at': '2026-07-01T10:30:00+02:00', 'duration': 5400})
        with self.assertRaises(Unsupported):
            self.call('timetracking', {'tracker_user_id': 'other'}, self.track)
        with self.assertRaises(Conflict):
            self.call('timetracking', {'description': 'New'}, {'description': 'Old'})

    def test_time_remote_preconditions(self):
        remote = {'started_at': '2026-07-01T07:00:00Z', 'duration': 5400, 'description': 'Work',
                  'invoiceable': False, 'user': {'id': 'remote-user'}}
        self.call('timetracking', {'description': 'New', 'billable': 1}, self.track, remote)
        for field, value in (('duration', 30), ('started_at', '2026-07-01T07:01:00Z'),
                             ('description', 'Concurrent'), ('invoiceable', True),
                             ('user', {'id': 'someone-else'})):
            with self.subTest(field=field), self.assertRaises(Conflict):
                self.call('timetracking', {'description': 'New', 'billable': 1}, self.track, {**remote, field: value})

    def test_time_subject_precondition(self):
        with self.assertRaises(Conflict):
            self.call('timetracking', {'task_id': ''}, self.track,
                      {'subject': {'type': 'todo', 'id': 'concurrent'}})

    def test_sql_dates_dst_and_validation(self):
        for start in ('2026-03-29 02:30:00', '2026-10-25 02:30:00', 'bad'):
            with self.subTest(start=start), self.assertRaises(Conflict):
                self.call('timetracking', {**self.track, 'start_at': start}, action='create')
        record = {**self.track, 'start_at': '2026-03-29 01:30:00', 'end_at': '2026-03-29 03:30:00'}
        self.assertEqual(self.call('timetracking', record, action='create')[0]['body']['duration'], 3600)
        with self.assertRaises(Conflict):
            self.call('timetracking', {**self.track, 'end_at': '2026-07-01 08:00:00'}, action='create')
        with self.assertRaises(Conflict):
            self.call('phases', {'deadline': '2026-02-30'}, {'deadline': None})

    def test_unmapped_users_and_string_resolution(self):
        self.refs['companies', 'c'] = 'existing-remote'
        record = {**self.track, 'task_id': ''}
        self.assertEqual(self.call('timetracking', record, action='create')[0]['body']['subject']['id'], 'existing-remote')
        with self.assertRaises(Conflict):
            self.call('timetracking', {**record, 'tracker_user_id': 'missing'}, action='create')

    def test_scalar_remote_conflict_and_identity(self):
        with self.assertRaises(Conflict):
            self.call('companies', {'name': 'New'}, {'name': 'Old'}, {'name': 'Concurrent'})
        with self.assertRaises(Conflict):
            self.call('companies', {'name': 'New'}, {'name': 'Old'}, {'id': 'different'})

    def test_nonnullable_dates_and_task_completion_precondition(self):
        for module, field in (('tasks', 'deadline'), ('phases', 'deadline'),
                              ('projects', 'data_inizio_progetto')):
            with self.subTest(module=module), self.assertRaises(Conflict):
                self.call(module, {field: None}, {field: '2026-11-01'})
        with self.assertRaises(Conflict):
            self.call('tasks', {'status': 'done'}, {'status': 'planned'}, {'completed': True})

    def test_locked_or_billed_time_not_written(self):
        for remote in ({'locked': True}, {'billing_info': {'type': 'invoice'}}):
            with self.assertRaises(Unsupported):
                self.call('timetracking', {'description': 'New'}, self.track, remote)

    def test_endpoint_and_body_parameter_contracts(self):
        contracts = {
            '/companies.add': {'name', 'national_identification_number', 'remarks'},
            '/contacts.add': {'last_name'},
            '/milestones.create': {'project_id', 'name', 'due_on', 'responsible_user_id'},
            '/timeTracking.add': {'started_on', 'started_at', 'ended_at', 'duration', 'description', 'subject', 'invoiceable', 'user_id'},
            '/timeTracking.update': {'id', 'started_on', 'started_at', 'ended_at', 'duration', 'description'},
            '/projects-v2/tasks.update': {'id', 'title'},
        }
        cases = [
            self.call('companies', {'name': 'A', 'tax_code': 'T', 'notes': 'N'}, action='create'),
            self.call('contacts', {'last_name': 'Smith'}, action='create'),
            self.call('phases', {'project_id': 'p', 'name': 'F', 'deadline': '2026-12-01', 'assigned_user_id': 'u'}, action='create'),
            self.call('timetracking', self.track, action='create'),
            self.call('timetracking', {'description': 'New'}, self.track),
            self.call('tasks', {'name': 'New'}, {'name': 'Old'}, rid={'id': 'remote', 'type': 'nextgenTask'}),
        ]
        for calls in cases:
            for call in calls:
                self.assertIn(call['endpoint'], mapper.ALLOWED_ENDPOINTS)
                self.assertEqual(set(call['body']), contracts[call['endpoint']])


    def test_legacy_longtext_empty_json_is_not_a_fake_custom_change(self):
        calls=self.call('companies',{'name':'A','aree_investimento':'[]','ricavi_annui':'{}','custom_fields':'{}'},action='create')
        self.assertEqual(calls[0]['body'],{'name':'A'})
        with self.assertRaises(mapper.Unsupported):
            self.call('contacts',{'last_name':'A','tags':'["important"]'},action='create')


if __name__ == '__main__':
    unittest.main()
