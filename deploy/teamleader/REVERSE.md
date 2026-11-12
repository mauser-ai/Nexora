# Nexora -> n8n Raspberry -> Teamleader

## Attivazione verificata (2026-11-11)

Backend caricato e installer firmato eseguito: due tabelle e quattordici trigger
installati, `historicalRowsExported=0`. Configurazioni server/Pi abilitate.
Workflow n8n pubblicato e container riavviato per caricare la versione attiva;
il job privato mostra polling automatico riuscito (`state=idle` con timestamp
aggiornato). Nessuna mutazione sintetica sull'account Teamleader per il collaudo.
La prima consegna reale in uscita resta da verificare su un evento utente successivo
all'installazione: le operazioni precedenti non fanno parte di questa outbox.

Nella direzione entrante sono stati confermati separatamente progetti multi-cliente
rifiutati dal mapper corrente, con task dipendenti in attesa; ticket/fatture non
abilitati. L'attivazione del canale uscente non rimuove questi limiti entranti e
non e una conferma che ogni modulo/campo sia sincronizzato in entrambe le direzioni.

## Solo eventi futuri

Non esiste un import iniziale in questo flusso. L'installer crea tabelle e trigger
ma non legge/accoda le righe CRM preesistenti. Il punto di partenza e l'installazione
dei trigger sul server: non vengono recuperate nemmeno le modifiche avvenute prima
di quell'istante durante la preparazione del collegamento.

Una modifica successiva a un vecchio oggetto viene esportata come modifica, non
come copia dello storico. Gli ID del precedente import CSV vengono verificati
con una lettura `.info`; se l'oggetto remoto non esiste, l'update resta bloccato e
non diventa mai una creazione implicita. Lo stesso vale per le dipendenze storiche.

## Componenti

- `reverse_store.php`: outbox MySQL transazionale tramite AFTER INSERT/UPDATE/DELETE.
- `outgoing.php`: RPC firmato con la chiave dell'integrazione, team fisso.
- `nexora_reverse.py`: una consegna per tick, journal SQLite privato sul Pi.
- `reverse_mapper.py`: sole operazioni/parametri API verificati, nessun URL libero.
- n8n: workflow `nexoraToTeamleader01`, timer 5s -> canale privato gia esistente
  `172.18.0.1:8767/run-nexora-outgoing`. Nessuna nuova porta esposta.

Le credenziali OAuth e il rate limiter restano quelli esistenti sul Raspberry.
La risposta 202 del job n8n indica avvio, non avvenuta modifica Teamleader.
Il risultato del ciclo viene conservato nel journal/outbox; la storia n8n contiene
solo esiti tecnici, non payload CRM o token.

## Backend da caricare

Estrarre il pacchetto backend in `public_html/api/teamleader/`:
`index.php`, `mapper.php`, `reverse_store.php`, `outgoing.php`.
Non sostituire la configurazione privata e non caricare esportazioni o credenziali
su Git. In `config.local.php` esistente aggiungere:

```php
'reverse_enabled' => true,
'reverse_modules' => ['companies','contacts','deals','projects','phases','tasks','timetracking'],
```

Lasciare invariati key/team_id/operator_map/apply. Eseguire poi dal Pi:

```sh
~/agency-briefing/.venv/bin/python ~/agency-briefing/scripts/nexora_reverse.py health
~/agency-briefing/.venv/bin/python ~/agency-briefing/scripts/nexora_reverse.py install-server
```

L'installer e solo POST firmato: non si avvia da browser. Richiede MySQL InnoDB e
privilegio TRIGGER. Se mancano i privilegi non usare un fallback che esporti lo
storico: l'installazione deve fermarsi. Eseguirlo in una breve finestra senza
scritture CRM: il DDL MySQL non e transazionale. Non cambiare manualmente gli ID.
I trigger esistenti identici vengono mantenuti; modifiche strutturali richiedono
manutenzione esplicita. Una lista moduli ridotta rimuove i relativi trigger.

Dopo installazione e test del primo evento, impostare `reverse_enabled=true` nel
JSON privato del Pi e pubblicare il workflow n8n. Nella preparazione iniziale
entrambi restano spenti/draft: nessuna scrittura di prova su Teamleader.

## Copertura esplicita

Il registry cattura eventi per i sette moduli configurati, ma non ogni possibile
campo Nexora ha un equivalente Teamleader. Il mapper applica solo operazioni
esprimibili senza perdere dati; le altre restano in stato blocked/conflict.

| Modulo | Creazione | Modifica |
| --- | --- | --- |
| Societa | Campi anagrafici compatibili | Campi anagrafici compatibili |
| Contatti | Anagrafica senza associazioni non mappate | Campi compatibili |
| Opportunita CRM (`deals`) | Con cliente/fase compatibili | Campi compatibili, niente lifecycle implicito |
| Progetti | Sospesa: mancano partecipanti/milestone obbligatori nell'evento singolo | Campi compatibili, anche nextgen riconosciuto |
| Fasi legacy | Con progetto e responsabile gia risolti | Campi compatibili, niente chiusure a cascata |
| Task | Sospesa: manca il work_type obbligatorio | Campi compatibili; operazioni composte sospese |
| Segnatempo | Utente mappato, task legacy o societa gia esistenti | Orari/descrizione/fatturabilita; utente non modificabile via API |

Nessuna cancellazione, email, registrazione contabile o gestione fatture/preventivi
e abilitata in uscita. Progetti-only e task nextgen come subject del segnatempo
restano sospesi finche il contratto specifico non e verificato. Note/calcoli locali,
custom fields non mappati, tariffe manuali nonzero e associazioni non traducibili
non vengono scartati silenziosamente: l'evento non viene scritto parzialmente.
`name` del segnatempo e un'etichetta locale e non sostituisce `description`.

## Identita, eco e conflitti

Le nuove identita Teamleader vengono associate in `teamleader_object_links`; gli
ID Nexora non vengono rinominati. I webhook di ritorno usano l'alias prima di
scrivere, inclusi i riferimenti a task/progetto/societa. Il trigger ignora le
scritture dell'import con `@nexora_sync_origin='teamleader'`: niente ping-pong.
L'installer rifiuta di partire se index.php non contiene il guard aggiornato.

Le modifiche locali ancora non risolte proteggono lo stesso record dall'import.
Una creazione remota potenzialmente in corso protegge temporaneamente anche il
modulo dall'arrivo del webhook prima dell'ack/mapping. Le creazioni rifiutate
prima di qualsiasi scrittura non bloccano gli altri record del modulo.
Un ack positivo salva mapping e watermark contro eventi di ritorno piu vecchi.
Un no-op non sposta il watermark. Le letture di mapping/busy usano current reads
nelle transazioni; eventuali deadlock vengono ritentati come ack/import, non come
una nuova creazione remota.

Gli operatori si risolvono con la mappa inversa esplicita. In uscita non si usa
fallback all'owner per inventare un utente Teamleader. Un utente non mappato blocca
l'evento. Il mapper confronta anche lo snapshot remoto prima degli aggiornamenti;
non e un lock/CAS remoto atomico, quindi non elimina ogni possibile race esterna.

## Fallimenti e sospensione

Claim persistito prima della scrittura; journal locale persistito prima dell'ack.
Se l'ack si perde, viene ritentato solo l'ack. Timeout/rete/5xx durante la mutazione
o crash nella finestra di dispatch producono uncertain: nessuna ripetizione cieca.
Una lease scaduta e uncertain, non ritorna automaticamente pending. Il risultato
gia noto puo essere confermato con la stessa lease anche dopo la scadenza.
Blocked/conflict/uncertain richiedono verifica umana; non c'e un comando che li
scarti o forzi tutti in massa. Un vecchio evento irrisolto blocca solo lo stesso
oggetto, salvo il guard sulle creazioni potenzialmente avvenute senza mapping.

Per fermare l'uscita: `reverse_enabled=false` sul Pi o workflow n8n disattivato.
I trigger possono continuare a raccogliere eventi. Non cancellare outbox, mapping
o journal per riprovare: puo provocare duplicati. Gli aggiornamenti entranti sugli
stessi oggetti restano protetti finche il conflitto locale non viene risolto.
La diagnostica firmata `health` di outgoing.php mostra solo conteggi per modulo.

## Verifica

```sh
python3 -m unittest discover -s deploy/teamleader -p 'test_*.py' -v
php deploy/teamleader/test_mapper.php
TLR_TEST_DSN='mysql:unix_socket=/tmp/mysql.sock' TLR_TEST_USER=root php deploy/teamleader/test_reverse_store.php
```

I test MySQL creano ed eliminano un database locale isolato, mai quello configurato
nell'app e mai il database online. Coprono trigger futuri, rollback, guard di
origine, lease, replay ack, isolamento team e mapping. I test Python non chiamano
Teamleader e non creano dati di prova sull'account reale.
