import importlib.util
import json
import pathlib
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('bridge', pathlib.Path(__file__).with_name('nexora_bridge.py'))
bridge = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bridge)


class BridgeTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        bridge.ROOT = pathlib.Path(self.tmp.name)
        self.config = {'enabled': True, 'modules': ['companies']}

    def tearDown(self):
        self.tmp.cleanup()

    def enqueue(self, id='abc', type='company.updated'):
        return bridge.enqueue({'type': type, 'subject': {'type': 'company', 'id': id}})

    def test_disabled_does_not_fetch(self):
        self.enqueue()
        self.assertFalse(bridge.deliver_one({'enabled': False}))

    def test_success_and_no_duplicate_delivery(self):
        self.enqueue()
        fetch = lambda r,c: {'id': r['source_id'], 'name': 'Test'}
        self.assertTrue(bridge.deliver_one(self.config, fetch, lambda c,r: {'ok':True, 'applied':True}))
        self.assertFalse(bridge.deliver_one(self.config, fetch, lambda c,r: self.fail()))

    def test_retry_keeps_exact_request(self):
        self.enqueue()
        requests = []
        def sender(c,r):
            requests.append(r)
            raise TimeoutError()
        bridge.deliver_one(self.config, lambda r,c: {'id':r['source_id']}, sender)
        with bridge.database() as db:
            db.execute('UPDATE events SET due=0')
        bridge.deliver_one(self.config, lambda r,c: self.fail('must not refetch'), sender)
        self.assertEqual(requests[0], requests[1])

    def test_preview_is_not_acknowledged(self):
        self.enqueue()
        bridge.deliver_one(self.config, lambda r,c: {'id':r['source_id']}, lambda c,r: {'ok':True,'preview':True})
        with bridge.database() as db:
            self.assertEqual(db.execute('SELECT state FROM events').fetchone()[0], 'pending')

    def test_entity_order_does_not_block_other_entities(self):
        self.enqueue('a'); self.enqueue('a'); self.enqueue('b')
        with bridge.database() as db:
            db.execute('UPDATE events SET due=9999999999 WHERE rowid=1')
        seen=[]
        bridge.deliver_one(self.config, lambda r,c: {'id':r['source_id']}, lambda c,r: seen.append(json.loads(r)['source_id']) or {'ok':True,'applied':True})
        self.assertEqual(seen,['b'])

    def test_delete_never_fetches_detail(self):
        self.enqueue(type='company.deleted')
        seen=[]
        bridge.deliver_one(self.config, lambda r,c: self.fail(), lambda c,r: seen.append(json.loads(r)['action']) or {'ok':True,'applied':True})
        self.assertEqual(seen,['delete'])

    def test_unknown_module_is_ignored(self):
        self.assertFalse(bridge.enqueue({'type':'user.updated','subject':{'id':'x'}}))

    def test_dependency_is_delivered_before_task(self):
        bridge.enqueue({'type':'task.updated','subject':{'type':'task','id':'task-1'}})
        c={'enabled':True,'modules':['tasks','projects']}
        seen=[]
        def fetch(r,c):
            return {'id':r['source_id'],**({'project':{'type':'project','id':'project-1'}} if r['module']=='tasks' else {})}
        def send(c,r):
            seen.append(json.loads(r)['module'])
            return {'ok':True,'applied':True}
        self.assertFalse(bridge.deliver_one(c,fetch,send))
        self.assertEqual(seen,[])
        # Even when the child is due now, its blocked edge must not starve its parent.
        with bridge.database() as db: db.execute('UPDATE events SET due=0')
        self.assertTrue(bridge.deliver_one(c,fetch,send))
        with bridge.database() as db: db.execute('UPDATE events SET due=0')
        self.assertTrue(bridge.deliver_one(c,fetch,send))
        self.assertEqual(seen,['projects','tasks'])

    def test_calendar_event_resolves_task_and_company_without_changing_subject(self):
        class Client:
            def post(self,endpoint,params):
                self.endpoint=endpoint
                return {'data':{'id':'event','task':{'id':'task','type':'task'},'links':[{'id':'company','type':'company'}]}}
        source={'id':'time','subject':{'type':'event','id':'event'},'relates_to':[{'type':'project','id':'project'}]}
        record=bridge.enrich_time_record(source,Client())
        self.assertEqual(record['subject'],source['subject'])
        self.assertIn({'type':'task','id':'task'},record['_sync_context'])
        self.assertIn({'type':'project','id':'project'},record['_sync_context'])
        self.assertIn({'type':'company','id':'company'},record['_sync_context'])
        self.assertIn('_sync_event',record)

    def test_company_time_does_not_invent_task(self):
        record=bridge.enrich_time_record({'subject':{'type':'company','id':'company'}},None)
        self.assertEqual(record['_sync_context'],[{'type':'company','id':'company'}])

    def test_milestone_time_waits_for_full_project_chain(self):
        bridge.enqueue({'type':'timetracking.updated','subject':{'type':'timetracking','id':'time'}})
        c={'enabled':True,'modules':['timetracking','phases','projects','companies']}
        def fetch(r,c):
            records={
                'timetracking':{'subject':{'type':'milestone','id':'phase'},'_sync_context':[{'type':'milestone','id':'phase'}]},
                'phases':{'project':{'type':'project','id':'project'}},
                'projects':{'customer':{'type':'company','id':'company'}},'companies':{}}
            return {'id':r['source_id'],**records[r['module']]}
        seen=[]
        def send(c,r):
            seen.append(json.loads(r)['module']);return {'ok':True,'applied':True}
        for _ in range(12):
            with bridge.database() as db:db.execute('UPDATE events SET due=0')
            bridge.deliver_one(c,fetch,send)
        self.assertEqual(seen,['companies','projects','phases','timetracking'])


if __name__ == '__main__':
    unittest.main()
