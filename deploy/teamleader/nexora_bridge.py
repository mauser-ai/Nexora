#!/usr/bin/env python3
"""Independent Teamleader -> Nexora outbox. No network inside enqueue()."""
from __future__ import annotations

import argparse
from contextlib import contextmanager
import fcntl
import hashlib
import hmac
import json
import os
from pathlib import Path
import random
import sqlite3
import sys
import time
import urllib.request
from urllib.parse import urlparse
import uuid

ROOT = Path(os.environ.get('NEXORA_BRIDGE_DATA', Path.home() / '.local/share/gweb/nexora'))
CONFIG = Path(os.environ.get('NEXORA_BRIDGE_CONFIG', Path.home() / '.config/gweb/nexora-bridge.json'))
MODULES = {
    'company': ('companies', 'companies.info'), 'contact': ('contacts', 'contacts.info'),
    'deal': ('deals', 'deals.info'), 'opportunity': ('deals', 'deals.info'),
    'quotation': ('quotations', 'quotations.info'), 'invoice': ('invoices', 'invoices.info'),
    'creditnote': ('credit_notes', 'creditNotes.info'), 'project': ('projects', 'projects.info'),
    'nextgenproject': ('projects', 'projects-v2/projects.info'),
    'phase': ('phases', 'phases.info'), 'milestone': ('phases', 'milestones.info'),
    'task': ('tasks', 'tasks.info'), 'nextgentask': ('tasks', 'projects-v2/tasks.info'),
    'ticket': ('tickets', 'tickets.info'), 'timetracking': ('timetracking', 'timeTracking.info'),
    'product': ('products', 'products.info'), 'subscription': ('subscriptions', 'subscriptions.info'),
}


@contextmanager
def database():
    ROOT.mkdir(parents=True, exist_ok=True, mode=0o700)
    db = sqlite3.connect(ROOT / 'outbox.sqlite3', timeout=2)
    (ROOT / 'outbox.sqlite3').chmod(0o600)
    db.row_factory = sqlite3.Row
    db.execute('PRAGMA journal_mode=WAL')
    db.execute('''CREATE TABLE IF NOT EXISTS events (
        id TEXT PRIMARY KEY, module TEXT NOT NULL, source_id TEXT NOT NULL,
        endpoint TEXT NOT NULL, payload TEXT NOT NULL, observed REAL NOT NULL,
        request TEXT, state TEXT NOT NULL DEFAULT 'pending', attempts INTEGER NOT NULL DEFAULT 0,
        due REAL NOT NULL DEFAULT 0, error TEXT, delivered REAL)''')
    db.execute('CREATE INDEX IF NOT EXISTS pending ON events(state,due)')
    db.execute('CREATE INDEX IF NOT EXISTS entity_order ON events(module,source_id)')
    db.execute('CREATE TABLE IF NOT EXISTS dependencies(child TEXT NOT NULL,parent TEXT NOT NULL,PRIMARY KEY(child,parent))')
    try:
        with db:
            yield db
    finally:
        db.close()


def enqueue(payload):
    subject = payload.get('subject') or payload.get('data') or {}
    if not isinstance(subject, dict):
        return False
    event_type = str(payload.get('type') or payload.get('event') or '')
    kind = str(subject.get('type') or event_type.split('.')[0]).lower().replace('_', '').replace('-', '')
    if kind not in MODULES or not subject.get('id'):
        return False
    module, endpoint = MODULES[kind]
    with database() as db:
        db.execute('INSERT INTO events(id,module,source_id,endpoint,payload,observed) VALUES(?,?,?,?,?,?)',
                   (str(uuid.uuid4()), module, str(subject['id']), endpoint, json.dumps(payload), time.time()))
    return True


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


def send(config, request):
    url = config['url']
    parsed = urlparse(url)
    if parsed.scheme != 'https' or parsed.username or parsed.password or parsed.fragment:
        raise ValueError('Endpoint HTTPS richiesto, senza credenziali URL')
    if len(config.get('key', '')) < 32:
        raise ValueError('Chiave Nexora non configurata')
    timestamp = str(int(time.time()))
    signature = hmac.new(config['key'].encode(), timestamp.encode() + b'.' + request.encode(), hashlib.sha256).hexdigest()
    req = urllib.request.Request(url, data=request.encode(), method='POST', headers={
        'Content-Type': 'application/json', 'X-Nexora-Timestamp': timestamp, 'X-Nexora-Signature': signature})
    with urllib.request.build_opener(NoRedirect()).open(req, timeout=30) as response:
        result = json.load(response)
    if not isinstance(result, dict) or not result.get('ok'):
        raise RuntimeError('Risposta Nexora non valida')
    return result


def fetch_record(row, config):
    sys.path.insert(0, config.get('teamleader_scripts', str(Path.home() / 'agency-briefing/scripts')))
    from teamleader_monitor_sync import Client
    from teamleader_oauth import paths, read_json
    config_path, token_path = paths()
    client = Client(read_json(config_path), read_json(token_path), token_path)
    payload = json.loads(row['payload'])
    subject = payload.get('subject') or payload.get('data') or {}
    kind = str(subject.get('type') or str(payload.get('type') or payload.get('event') or '').split('.')[0]).lower().replace('_', '').replace('-', '')
    # Recompute for already queued events written by earlier bridge versions.
    endpoint = MODULES.get(kind, (None, row['endpoint']))[1]
    params = {'id': row['source_id']}
    if row['module'] == 'timetracking':
        params['includes'] = 'relates_to'
    record = client.post(endpoint, params).get('data')
    if not isinstance(record, dict) or record.get('id') != row['source_id']:
        raise RuntimeError('Dettaglio Teamleader incompleto')
    return enrich_time_record(record,client) if row['module']=='timetracking' else record


def enrich_time_record(record, client):
    """Resolve API relationships, preserving the unmodified subject and all fetched provenance."""
    record = dict(record)
    context = []
    def add(ref, default_type=None):
        if not isinstance(ref,dict) or not ref.get('id'):
            return
        kind = ref.get('type') or default_type
        kind = {'todo':'task','nextgentask':'nextgenTask','nextgenproject':'nextgenProject'}.get(kind,kind)
        if kind in ('task','nextgenTask','project','nextgenProject','company','contact','milestone'):
            value={'type':kind,'id':ref['id']}
            if value not in context:
                context.append(value)
    subject=record.get('subject') or {}
    kind=subject.get('type')
    add(subject)
    for ref in record.get('relates_to') or []:
        add(ref)
        if ref.get('type')=='nextgenProjectGroup':
            group=client.post('projects-v2/projectGroups.info',{'id':ref['id']})['data']
            record.setdefault('_sync_groups',[]).append(group)
            add(group.get('project'),'nextgenProject')
    if kind=='event':
        event=client.post('events.info',{'id':subject['id']})['data']
        record['_sync_event']=event
        add(event.get('task'),'task')
        for ref in event.get('links') or []:
            add(ref)
    elif kind=='ticket':
        ticket=client.post('tickets.info',{'id':subject['id']})['data']
        record['_sync_ticket']=ticket
        add(ticket.get('customer') or (ticket.get('participant') or {}).get('customer'))
        add(ticket.get('project'),'project')
        add(ticket.get('milestone'),'milestone')
    elif kind=='contact':
        contact=client.post('contacts.info',{'id':subject['id']})['data']
        record['_sync_contact']=contact
        companies=contact.get('companies') or []
        if len(companies)==1:
            add(companies[0].get('company') or companies[0],'company')
        elif len(companies)>1 and not any(r['type']=='company' for r in context):
            raise ValueError('Contatto multi-societa senza relazione principale')
    elif kind not in (None,'company','todo','task','nextgenTask','milestone','project','nextgenProject'):
        raise ValueError('Tipo segnatempo non risolto')
    record['_sync_context']=context
    return record


def ensure_dependencies(row, request):
    """Persist parent events and edges before allowing the child onto the network."""
    event = json.loads(request)
    if event['action'] == 'delete':
        return True
    record = event['record']
    refs = []
    def add(value, default_kind):
        if isinstance(value, dict) and value.get('id'):
            kind = str(value.get('type') or default_kind).lower().replace('_','').replace('-','')
            if kind not in MODULES:
                raise ValueError('Tipo di dipendenza non supportato')
            refs.append((kind,str(value['id'])))
    if row['module'] in ('tasks','phases','invoices'):
        add(record.get('project'),'project')
    if row['module'] == 'tasks':
        add(record.get('milestone'),'milestone')
    if row['module'] in ('projects','deals','subscriptions','contacts','tasks'):
        customer = record.get('customer') or (record.get('lead') or {}).get('customer')
        if row['module'] == 'projects' and not customer and len(record.get('customers') or []) == 1:
            customer = record['customers'][0]
        add(customer,'company')
    if row['module'] == 'timetracking':
        subject = record.get('subject') or {}
        aliases = {'todo':'task','nextgenTask':'nextgentask'}
        kind = aliases.get(subject.get('type'),subject.get('type'))
        if kind in ('task','nextgentask','company','project','nextgenProject'):
            add({**subject,'type':kind},kind)
        for ref in record.get('_sync_context') or []:
            add(ref,ref['type'])
    with database() as db:
        for kind, source_id in refs:
            module, endpoint = MODULES[kind]
            if module == row['module'] and source_id == row['source_id']:
                continue
            parent = db.execute('SELECT id FROM events WHERE module=? AND source_id=? ORDER BY rowid DESC LIMIT 1', (module,source_id)).fetchone()
            if parent is None:
                parent_id = str(uuid.uuid4())
                payload = json.dumps({'type':kind+'.dependency','subject':{'type':kind,'id':source_id}})
                db.execute('INSERT INTO events(id,module,source_id,endpoint,payload,observed) VALUES(?,?,?,?,?,?)', (parent_id,module,source_id,endpoint,payload,time.time()))
            else:
                parent_id = parent['id']
            db.execute('INSERT OR IGNORE INTO dependencies(child,parent) VALUES(?,?)',(row['id'],parent_id))
        blocked = db.execute("SELECT 1 FROM dependencies d JOIN events p ON p.id=d.parent WHERE d.child=? AND p.state!='delivered' LIMIT 1",(row['id'],)).fetchone()
        if blocked:
            db.execute("UPDATE events SET due=?,error='In attesa di dipendenze' WHERE id=?",(time.time()+5,row['id']))
    return blocked is None


def prepare_request(row, config, fetcher=fetch_record):
    request = row['request']
    if request is None:
        payload = json.loads(row['payload'])
        event_type = str(payload.get('type') or payload.get('event') or '').lower()
        deleted = any(word in event_type for word in ('deleted', 'removed'))
        request = json.dumps({'event_id':row['id'], 'module':row['module'], 'source_id':row['source_id'],
            'observed_at':row['observed'], 'action':'delete' if deleted else 'upsert',
            'record':{} if deleted else fetcher(row,config)}, separators=(',',':'))
        with database() as db:
            db.execute('UPDATE events SET request=? WHERE id=?', (request,row['id']))
    return request


def deliver_one(config, fetcher=fetch_record, sender=send):
    if not config.get('enabled'):
        return False
    with database() as db:
        # A failed/late event blocks only the same entity, never other modules.
        row = db.execute('''SELECT e.* FROM events e WHERE e.state='pending' AND e.due<=?
            AND NOT EXISTS (SELECT 1 FROM events older WHERE older.module=e.module
                AND older.source_id=e.source_id AND older.rowid<e.rowid AND older.state!='delivered')
            AND NOT EXISTS (SELECT 1 FROM dependencies d JOIN events p ON p.id=d.parent
                WHERE d.child=e.id AND p.state!='delivered')
            ORDER BY e.rowid LIMIT 1''', (time.time(),)).fetchone()
    if row is None:
        return False
    if row['module'] not in config.get('modules', []):
        with database() as db:
            db.execute("UPDATE events SET due=?,error='Modulo sospeso nella configurazione' WHERE id=?", (time.time()+300,row['id']))
        return False
    try:
        request = prepare_request(row,config,fetcher)
        if not ensure_dependencies(row,request):
            return False
        result = sender(config, request)
        if result.get('preview') or not result.get('applied'):
            raise RuntimeError('Nexora in anteprima: nessuna modifica applicata')
        with database() as db:
            db.execute("UPDATE events SET state='delivered',delivered=?,error=NULL WHERE id=?", (time.time(),row['id']))
        return True
    except Exception as exc:
        attempts = row['attempts'] + 1
        # Store only the exception class: HTTP bodies/URLs can contain confidential data.
        error = 'Anteprima' if isinstance(exc, RuntimeError) and str(exc).startswith('Nexora in anteprima') else type(exc).__name__
        with database() as db:
            db.execute('UPDATE events SET attempts=?,due=?,state=?,error=? WHERE id=?',
                (attempts,time.time()+min(5*2**min(attempts,6),300)+random.random(),
                 'failed' if attempts>=12 else 'pending',error,row['id']))
        return False


def main():
    os.umask(0o077)
    parser = argparse.ArgumentParser()
    parser.add_argument('command', choices=['run','once','status','health','install-server','retry-failed','prepare','reconcile-time'])
    args = parser.parse_args()
    if args.command == 'status':
        with database() as db:
            print(json.dumps({row[0]:row[1] for row in db.execute('SELECT state,count(*) FROM events GROUP BY state')}))
        return
    config = json.loads(CONFIG.read_text())
    if args.command == 'reconcile-time':
        with database() as db:
            ids=[r[0] for r in db.execute("SELECT DISTINCT source_id FROM events WHERE module='timetracking' AND state='delivered'")]
        added=0
        for source_id in ids:
            with database() as db:
                pending=db.execute("SELECT 1 FROM events WHERE module='timetracking' AND source_id=? AND state='pending' LIMIT 1",(source_id,)).fetchone()
            if not pending:
                enqueue({'type':'timetracking.reconcile','subject':{'type':'timetracking','id':source_id}})
                added+=1
        print(json.dumps({'queued':added,'sent':0}))
        return
    if args.command == 'prepare':
        # Fetch and queue prerequisites only: no Nexora requests and no delivery acknowledgements.
        for _ in range(100):
            with database() as db:
                row = next((r for r in db.execute("SELECT * FROM events WHERE state='pending' AND request IS NULL ORDER BY rowid") if r['module'] in config.get('modules',[])), None)
            if row is None:
                return
            ensure_dependencies(row,prepare_request(row,config))
        raise RuntimeError('Limite di preparazione raggiunto: controllare la coda prima di continuare')
    if args.command in ('health','install-server'):
        print(json.dumps(send(config,json.dumps({'action':'health' if args.command=='health' else 'install'}))))
        return
    if args.command == 'retry-failed':
        with database() as db:
            db.execute("UPDATE events SET state='pending',attempts=0,due=0,error=NULL WHERE state='failed'")
        return
    ROOT.mkdir(parents=True, exist_ok=True, mode=0o700)
    with (ROOT / 'worker.lock').open('a') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        while True:
            config = json.loads(CONFIG.read_text())
            delivered = deliver_one(config)
            if args.command == 'once':
                return
            time.sleep(0.2 if delivered else 2)


if __name__ == '__main__':
    main()
