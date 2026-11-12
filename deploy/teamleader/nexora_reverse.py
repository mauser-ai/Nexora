#!/usr/bin/env python3
"""One prospective Nexora event per n8n tick, with durable write/ack separation."""
from contextlib import contextmanager
import fcntl
import hashlib
import json
import os
from pathlib import Path
import sqlite3
from urllib.parse import urlparse

import nexora_bridge
import reverse_mapper as mapper

ROOT = Path(os.environ.get('NEXORA_REVERSE_DATA',Path.home()/'.local/share/gweb/nexora-reverse'))
DEFAULT_TYPES={'companies':'company','contacts':'contact','deals':'deal','projects':'project',
               'phases':'milestone','tasks':'task','timetracking':'timetracking'}


def rpc(config,payload):
    parsed=urlparse(config['url'])
    endpoint=parsed._replace(path=parsed.path.rsplit('/',1)[0]+'/outgoing.php',query='',fragment='').geturl()
    return nexora_bridge.send({**config,'url':endpoint},json.dumps(payload,separators=(',',':')))


@contextmanager
def journal():
    ROOT.mkdir(parents=True,exist_ok=True,mode=0o700)
    path=ROOT/'journal.sqlite3'
    db=sqlite3.connect(path,timeout=5);path.chmod(0o600);db.row_factory=sqlite3.Row
    db.execute('PRAGMA journal_mode=WAL')
    db.execute('''CREATE TABLE IF NOT EXISTS jobs(id INTEGER PRIMARY KEY,event_json TEXT NOT NULL,
        phase TEXT NOT NULL,plan_hash TEXT,result_json TEXT)''')
    try:
        with db:yield db
    finally:db.close()


class MissingRemote(ValueError):
    pass


class API:
    def __init__(self):
        from teamleader_api_proxy import execute,operations
        self.execute=execute
        self.catalog={r['path']:r['id'] for r in operations().values()}

    def call(self,endpoint,body):
        operation=self.catalog.get(endpoint)
        if not operation:raise mapper.Unsupported('API operation unavailable in local catalog')
        return self.execute(operation,body)[1]

    def info(self,module,remote_id,remote_type=None):
        try:
            result=self.call(mapper.info_endpoint(module,remote_type),{'id':remote_id})
        except Exception as exc:
            if getattr(exc,'status',None)!=404:raise
            if remote_type is None and module in ('projects','tasks'):
                remote_type='nextgenProject' if module=='projects' else 'nextgenTask'
                try:result=self.call(mapper.info_endpoint(module,remote_type),{'id':remote_id})
                except Exception as second:
                    if getattr(second,'status',None)==404:raise MissingRemote('Remote object absent') from None
                    raise
            else:raise MissingRemote('Remote object absent') from None
        record=result.get('data',result) if isinstance(result,dict) else None
        if not isinstance(record,dict) or record.get('id')!=remote_id:raise mapper.Conflict('Remote identity mismatch')
        return record,remote_type or DEFAULT_TYPES[module]

    def write(self,call):
        if call['endpoint'] not in mapper.ALLOWED_ENDPOINTS:raise mapper.Unsupported('Unsafe endpoint')
        # The existing private proxy retries only rejected authentication/rate limits,
        # never network errors or 5xx. Do not add an automatic mutation retry here.
        return self.call(call['endpoint'],call['body'])


def _result(event,result):
    with journal() as db:
        db.execute("UPDATE jobs SET phase='result',result_json=? WHERE id=?",(json.dumps(result),event['id']))


def _ack(config,event,result,rpc_fn):
    reply=rpc_fn(config,{'action':'finish','id':event['id'],'lease':event['lease'],'result':result})
    if not reply.get('ok'):raise RuntimeError('Outgoing acknowledgement refused')
    with journal() as db:db.execute("UPDATE jobs SET phase='acked' WHERE id=?",(event['id'],))
    actual=reply.get('result',{}).get('status',result['status'])
    return {'ok':True,'state':actual,'event_id':event['id'],'module':event['module']}


def run_once(config=None,rpc_fn=rpc,api_factory=API):
    os.umask(0o077)
    config=config if config is not None else json.loads(nexora_bridge.CONFIG.read_text())
    if not config.get('reverse_enabled',False):return {'ok':True,'state':'disabled'}
    ROOT.mkdir(parents=True,exist_ok=True,mode=0o700)
    with (ROOT/'worker.lock').open('a') as lock:
        try:fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
        except BlockingIOError:return {'ok':True,'state':'running'}
        try:return _run(config,rpc_fn,api_factory)
        except Exception as exc:
            # No request payload, OAuth token, key, API response body or URL in n8n history.
            return {'ok':False,'state':'error','error_code':type(exc).__name__}


def _run(config,rpc_fn,api_factory):
    with journal() as db:
        pending=db.execute("SELECT * FROM jobs WHERE phase!='acked' ORDER BY id LIMIT 1").fetchone()
    if pending:
        event=json.loads(pending['event_json'])
        if pending['phase']=='result':return _ack(config,event,json.loads(pending['result_json']),rpc_fn)
        # A process died between durable preparation and durable result. Never repeat a write.
        result={'status':'uncertain','error_code':'interrupted_dispatch'}
        _result(event,result)
        return _ack(config,event,result,rpc_fn)
    response=rpc_fn(config,{'action':'claim'})
    event=response.get('event')
    if not event:return {'ok':True,'state':'idle' if response.get('enabled',True) else 'disabled'}
    if not isinstance(event,dict) or not isinstance(event.get('id'),int) or not event.get('lease'):raise ValueError('Invalid lease')
    with journal() as db:
        # A retry reuses the outbox ID. Replace its old journal row so a
        # previously acknowledged conflict can be dispatched again safely.
        db.execute("""INSERT INTO jobs(id,event_json,phase,plan_hash,result_json)
            VALUES(?,?,'claimed',NULL,NULL)
            ON CONFLICT(id) DO UPDATE SET event_json=excluded.event_json,
                phase='claimed', plan_hash=NULL, result_json=NULL""",
            (event['id'],json.dumps(event)))
    wrote=False
    remote_id=event.get('remote_id');remote_type=event.get('remote_type')
    try:
        api=api_factory();cache={}
        def resolve(module,local_id):
            cache_key=(module,local_id)
            if cache_key in cache:return cache[cache_key]
            link=rpc_fn(config,{'action':'lookup','module':module,'local_id':local_id})['link']
            rid=link.get('remote_id') or link.get('candidate')
            if not rid:raise MissingRemote('Local dependency has not been exported')
            record,typ=api.info(module,rid,link.get('remote_type'))
            cache[cache_key]={'id':rid,'type':typ,'_record':record}
            return cache[cache_key]
        remote_record=None
        if event['action']=='update':
            target=resolve(event['module'],event['local_id'])
            remote_id,remote_type=target['id'],target['type'];remote_record=target['_record']
        elif event['action']=='create':
            if remote_id:raise mapper.Conflict('Create already has a remote mapping')
        elif event['action']=='delete':
            if not remote_id:
                raise mapper.Conflict('Delete requires a confirmed remote mapping')
        else:raise mapper.Unsupported('Unsupported reverse action')
        user_map={}
        for source,user in response.get('operator_map',{}).items():
            if user in user_map and user_map[user]!=source:raise mapper.Conflict('Ambiguous user mapping')
            user_map[user]=source
        calls=mapper.plan(event['module'],event['action'],event['record'],event.get('before') or {},
            {'id':remote_id,'type':remote_type} if remote_id else None,user_map,resolve,
            time_zone=response.get('time_zone','Europe/Rome'),remote_record=remote_record)
        if len(calls)>1:raise mapper.Unsupported('Compound mutation requires manual review')
        for call in calls:
            if call.get('endpoint') not in mapper.ALLOWED_ENDPOINTS or not isinstance(call.get('body'),dict):
                raise mapper.Unsupported('Invalid mutation plan')
        plan_hash=hashlib.sha256(json.dumps(calls,sort_keys=True).encode()).hexdigest()
        with journal() as db:db.execute("UPDATE jobs SET phase='dispatching',plan_hash=? WHERE id=?",(plan_hash,event['id']))
        for call in calls:
            wrote=True
            reply=api.write(call)
            if event['action']=='create':
                data=reply.get('data') if isinstance(reply,dict) else None
                if not isinstance(data,dict) or not isinstance(data.get('id'),str) or not data['id']:
                    raise RuntimeError('Create result without remote identity')
                remote_id=data['id'];remote_type=data.get('type') or DEFAULT_TYPES[event['module']]
                if event['module']=='timetracking':remote_type='timetracking'
        result={'status':'delivered','remote_id':remote_id,'remote_type':remote_type,'no_mutation':not calls}
    except Exception as exc:
        if wrote:
            # A 4xx rejection is unambiguous; timeout/5xx/unreadable result may have committed.
            status=getattr(exc,'status',None)
            state='blocked' if isinstance(status,int) and 400<=status<500 else 'uncertain'
        else:state='conflict' if isinstance(exc,mapper.Conflict) else 'blocked'
        result={'status':state,'error_code':type(exc).__name__,'no_mutation':not wrote or state=='blocked'}
        if remote_id:result.update(remote_id=remote_id,remote_type=remote_type)
    _result(event,result)
    return _ack(config,event,result,rpc_fn)


if __name__=='__main__':
    import argparse
    parser=argparse.ArgumentParser()
    parser.add_argument('command',nargs='?',default='once',choices=['once','health','install-server'])
    args=parser.parse_args()
    if args.command=='once':print(json.dumps(run_once()))
    else:
        config=json.loads(nexora_bridge.CONFIG.read_text())
        print(json.dumps(rpc(config,{'action':'health' if args.command=='health' else 'install'})))
