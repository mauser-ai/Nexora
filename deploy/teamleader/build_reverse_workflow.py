#!/usr/bin/env python3
"""Reproducible n8n orchestration, using the existing private Raspberry API."""
import json


def build():
    return {
        'id':'nexoraToTeamleader01','name':'Nexora -> Teamleader - Eventi futuri','active':False,
        'settings':{'executionOrder':'v1','saveDataSuccessExecution':'none','saveDataErrorExecution':'all'},
        'nodes':[
            {'id':'timer','name':'Controlla nuovi eventi Nexora','type':'n8n-nodes-base.scheduleTrigger',
             'typeVersion':1.2,'position':[0,0],'parameters':{'rule':{'interval':[{'field':'seconds','secondsInterval':5}]}}},
            {'id':'dispatch','name':'Elabora una modifica','type':'n8n-nodes-base.httpRequest',
             'typeVersion':4.2,'position':[300,0],'parameters':{
                 'method':'POST','url':'http://172.18.0.1:8767/run-nexora-outgoing',
                 'authentication':'genericCredentialType','genericAuthType':'httpHeaderAuth',
                 'options':{'timeout':3000}},
             'credentials':{'httpHeaderAuth':{'id':'gwebEventsHeader01','name':'GWEB eventi Raspberry'}}},
            {'id':'note','name':'Contratto di consegna','type':'n8n-nodes-base.stickyNote','typeVersion':1,
             'position':[0,-300],'parameters':{'width':740,'height':250,'content':
                 '## Solo eventi successivi all attivazione\nNessun import dello storico.\n'
                 'Il Raspberry interroga la coda Nexora firmando le richieste. OAuth resta sul Pi.\n'
                 '202 indica avvio del job, non aggiornamento completato.\n'
                 'Timeout di una scrittura = stato incerto da verificare, non creazione ripetuta.\n'
                 'Nessuna cancellazione, invio email o contabilizzazione automatica.'}},
        ],
        'connections':{'Controlla nuovi eventi Nexora':{'main':[[{'node':'Elabora una modifica','type':'main','index':0}]]}},
    }


if __name__=='__main__':
    print(json.dumps(build(),ensure_ascii=False))
