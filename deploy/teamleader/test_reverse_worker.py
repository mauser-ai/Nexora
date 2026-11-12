import copy
import pathlib
import tempfile
import unittest
from unittest.mock import patch

import nexora_reverse as worker


class ReverseWorkerTests(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory();worker.ROOT=pathlib.Path(self.tmp.name)
        self.config={'reverse_enabled':True}
        self.event={'id':1,'lease':'a'*64,'module':'companies','local_id':'local','action':'create',
                    'record':{'id':'local','user_id':'user','name':'New company'},'before':{},'remote_id':None,'remote_type':None}
        self.claims=0;self.writes=0;self.results=[];self.fail_ack=False
        case=self
        class FakeAPI:
            def info(self,module,remote_id,remote_type=None):
                return {'id':remote_id,'name':'Old company'},remote_type or worker.DEFAULT_TYPES[module]
            def write(self,call):
                case.writes+=1
                return {'data':{'id':'remote','type':'company'}}
        self.API=FakeAPI

    def tearDown(self):self.tmp.cleanup()

    def rpc(self,config,payload):
        if payload['action']=='claim':
            self.claims+=1
            return {'ok':True,'event':copy.deepcopy(self.event) if self.claims==1 else None,'operator_map':{}}
        if payload['action']=='lookup':return {'ok':True,'link':{'remote_id':'remote','remote_type':'company','candidate':None}}
        if payload['action']=='finish':
            if self.fail_ack:self.fail_ack=False;raise OSError('Disconnected after remote commit')
            self.results.append(payload['result'])
            return {'ok':True,'result':{'status':payload['result']['status']}}
        self.fail('Unexpected action')

    def run_one(self):return worker.run_once(self.config,self.rpc,self.API)

    def test_disabled_never_polls(self):
        result=worker.run_once({'reverse_enabled':False},lambda *a:self.fail(),self.API)
        self.assertEqual(result['state'],'disabled')

    def test_only_claimed_future_event_is_sent(self):
        self.assertEqual(self.run_one()['state'],'delivered')
        self.assertEqual(self.run_one()['state'],'idle')
        self.assertEqual(self.writes,1)
        self.assertEqual(self.results[0]['remote_id'],'remote')

    def test_ack_retry_does_not_repeat_remote_create(self):
        self.fail_ack=True
        self.assertEqual(self.run_one()['state'],'error')
        self.assertEqual(self.run_one()['state'],'delivered')
        self.assertEqual(self.writes,1);self.assertEqual(self.claims,1)

    def test_timeout_is_uncertain_not_retried(self):
        case=self
        class TimeoutAPI(self.API):
            def write(self,call):case.writes+=1;raise TimeoutError()
        self.API=TimeoutAPI
        self.assertEqual(self.run_one()['state'],'uncertain')
        self.assertEqual(self.run_one()['state'],'idle')
        self.assertEqual(self.writes,1)

    def test_crash_during_dispatch_is_not_resent(self):
        case=self
        class CrashAPI(self.API):
            def write(self,call):case.writes+=1;raise SystemExit()
        self.API=CrashAPI
        with self.assertRaises(SystemExit):self.run_one()
        self.assertEqual(self.run_one()['state'],'uncertain')
        self.assertEqual(self.writes,1)

    def test_update_missing_remote_never_creates_history(self):
        self.event.update(action='update',before={'name':'Old company'})
        class MissingAPI(self.API):
            def info(self,*args):raise worker.MissingRemote()
        self.API=MissingAPI
        self.assertEqual(self.run_one()['state'],'blocked');self.assertEqual(self.writes,0)

    def test_compound_plan_is_rejected_before_any_write(self):
        with patch.object(worker.mapper,'plan',return_value=[{'endpoint':'/companies.add','body':{} }]*2):
            self.assertEqual(self.run_one()['state'],'blocked')
        self.assertEqual(self.writes,0)

    def test_server_conflict_is_reported_not_success(self):
        base=self.rpc
        def rpc(c,p):
            if p['action']=='finish':return {'ok':True,'result':{'status':'conflict'}}
            return base(c,p)
        result=worker.run_once(self.config,rpc,self.API)
        self.assertEqual(result['state'],'conflict')


if __name__=='__main__':unittest.main()
