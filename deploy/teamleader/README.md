# Teamleader -> Nexora

## Verifica attivazione (2026-11-10)

Endpoint installato sul server e invio Raspberry abilitato dopo le anteprime.
Prime consegne confermate per societa, progetto, fase e task. Il progetto nextgen
multi-cliente e stato messo in stato `held` nella outbox; i suoi task attendono
la dipendenza. Ticket e moduli contabili non sono abilitati e rimangono in coda.
Nessun replay globale dello storico. Gli altri servizi Raspberry restano attivi.
Il selettore del worker esclude i figli con dipendenze non consegnate, evitando
che i retry dei figli impediscano la consegna dei genitori (test di regressione).
La validazione riguarda questa prima tranche, non tutti i moduli della piattaforma.

## Stato e limiti

Sincronizzazione unidirezionale per il team Gweb. Il receiver Raspberry conserva il
flusso originale e aggiunge una copia degli eventi a una nuova outbox SQLite.
Il worker legge i dettagli dalla API Teamleader usando il client/rate limiter
esistente, poi invia il record a Nexora tramite HTTPS e firma HMAC con timestamp.
Nessuna nuova porta sul Raspberry, nessun accesso a Firebase.

Installazione iniziale: worker in esecuzione, invio **disabilitato**. Non viene
reimportato lo storico CSV e non vengono riutilizzate le vecchie code monitor/n8n.
La coda raccoglie solo gli eventi ricevuti dopo l'installazione dell'hook.

Prima tranche configurata: aziende, contatti, opportunita CRM (`deals`), progetti,
fasi, task, segnatempo. Gli altri moduli supportati dall'outbox restano in attesa: le
mappature di fatture, preventivi, note di credito e abbonamenti non sono complete
per righe/totali e non devono essere abilitate prima della loro verifica. Sono
presenti mappature di base, non equivalgono a un'integrazione contabile completa.
Utenti, chiamate, riunioni e altri eventi estranei ai moduli CRM non vengono inviati.

I record usano gli stessi UUID dell'import CSV. Un ID gia presente in un altro
team viene rifiutato. Le associazioni sono controllate sul team; dipendenze mancanti
rimangono da ritentare. Gli operatori vengono mappati solo se membri del team,
altrimenti si usa l'owner. Su record esistenti non si sovrascrivono proprietario,
note, righe documento o custom fields. Lato Nexora non avvengono cancellazioni:
gli eventi delete producono solo un tombstone nella tabella di sincronizzazione.

Le modifiche ai campi gestiti dalla sincronizzazione in Nexora possono essere
sovrascritte dal successivo aggiornamento Teamleader: Teamleader e la fonte master.
## Contratto del segnatempo

Fonte verificata: [API Blueprint ufficiale Teamleader](https://github.com/teamleadercrm/api/blob/master/apiary.apib),
sezioni `timeTracking.info`, `events.info`, `tasks.info`, `milestones.info` e
`TimeTrackingRelatesToTypes`. La richiesta include `relates_to`.

- `started_on` e una data; per gli orari si usano `started_at` e `ended_at`.
- La durata e in secondi; in assenza di `ended_at` si deriva la fine dalla durata.
- I valori di time_tracks seguono la convenzione esistente Nexora: orari locali
  senza offset SQL, nel fuso `time_zone` dell'integrazione (default Europe/Rome).
- Le date calendario pure non vengono convertite in UTC, evitando il giorno precedente.
- Senza orari reali il record usa `tipo=teamleader_duration`; la UI mostra solo
  la durata, non orari fittizi. La modifica UI richiede una successiva build app/web.
- Il flag sorgente di fatturabilita e `invoiceable`, non `billable`.
- `subject` resta originale. `relates_to` e `_sync_context` forniscono le relazioni;
  gli eventi vengono risolti tramite `events.info.task` e `events.info.links`.
- Le dipendenze task/fase/progetto/societa vengono accodate prima del segnatempo.
  Si ereditano gli antenati con controlli di team e coerenza; non si inventa un
  task quando il record Teamleader e associato solo a una societa.
- I dettagli di eventi, ticket, contatti e gruppi usati nel resolver restano come
  provenienza nel payload di sincronizzazione. Non si crea un modulo calendario o
  ticket nuovo per poter leggere queste relazioni.
- Relazioni incompatibili o ambigue restano da verificare, senza sceglierne una a caso.

`reconcile-time` accoda nuovi eventi per gli ID segnatempo gia consegnati, senza
cancellare ricevute o creare nuovi ID oggetto. Non invia direttamente: serve per
riparare anche i valori gia importati dopo il caricamento dei PHP corretti.
Durante l'aggiornamento del 2026-11-10 solo il modulo timetracking e stato rimosso
temporaneamente dai moduli abilitati del Raspberry; gli altri invii continuano.
Riabilitato dopo la prova del mapper aggiornato sul server: anteprime e consegne
confermate del segnatempo 13:50-14:10 (riallineamento) e del nuovo 14:10-15:00
collegato a task, societa, progetto e milestone. Nessun fallback operatore nelle
anteprime; il reinvio del nuovo evento e riconosciuto come duplicato dal server.

I riferimenti a societa, progetti e milestone producono eventi dipendenza nella
stessa outbox. Le dipendenze devono essere confermate dal server prima dei figli.
`prepare` scarica solo i dettagli e prepara il grafo locale, senza inviare dati a
Nexora; non esegue un import globale. I task e progetti nextgen usano gli endpoint
`projects-v2`. I progetti nextgen multi-cliente restano sospesi: il modello Nexora
attuale prevede una sola societa e non viene scelta automaticamente la prima.

## File sul server

Caricare il contenuto di `backend/api/teamleader/` in `public_html/api/teamleader/`.
Includere **config.local.php**, preparato privatamente sul computer: contiene la
chiave condivisa gia configurata sul Raspberry. Non mettere il file su Git.
Non sovrascrivere `api/config.php` ne le credenziali del database esistenti.

L'endpoint usa il bootstrap API esistente. `config.local.php` restituisce la
configurazione della sola integrazione, non quella generale del DB.

## Installazione e anteprima

Sul Raspberry, dopo il caricamento PHP:

```sh
cd ~/agency-briefing
.venv/bin/python scripts/nexora_bridge.py health
.venv/bin/python scripts/nexora_bridge.py install-server
.venv/bin/python scripts/nexora_bridge.py status
```

`install-server` crea solo `teamleader_sync_events` e `teamleader_sync_entities`,
senza cambiare lo schema dei moduli CRM. Tutte le chiamate sono POST firmate;
aprire l'URL nel browser non esegue l'installer.

Per un'anteprima: lasciare `apply=false` sul server e abilitare `enabled=true` nel
file `~/.config/gweb/nexora-bridge.json` del Raspberry. Il worker esegue il mapping
e le query in transazione, poi il server effettua rollback. Un'anteprima **non**
conferma la consegna: l'evento rimane in coda. Verificare prima un singolo evento
aziendale reale e controllare schema, associazioni e operatori. Non abilitare
l'applicazione in produzione prima di questa verifica.

Per applicare gli eventi gia verificati, impostare `apply=true` sul server;
`enabled=true` sul Raspberry. Il worker rilegge la configurazione ogni ciclo.
La stessa richiesta viene mantenuta per tutti i retry: il server riconosce i
duplicati per ID evento e scarta gli eventi osservati prima dell'ultimo applicato.
Non eseguire contemporaneamente il vecchio import CSV e la sincronizzazione live.

## Diagnostica e arresto

```sh
systemctl --user status nexora-bridge.service
~/agency-briefing/.venv/bin/python ~/agency-briefing/scripts/nexora_bridge.py status
journalctl --user -u nexora-bridge.service --since today
```

Impostare `enabled=false` ferma gli invii senza fermare la raccolta. In alternativa
`systemctl --user stop nexora-bridge.service`. Non eliminare la outbox:
`~/.local/share/gweb/nexora/outbox.sqlite3` contiene eventi e conferme di consegna.
Dopo 12 errori l'evento e `failed`; blocca solo eventi successivi dello stesso
oggetto. Correggere il problema, poi usare `retry-failed`.
Il codice errore locale non contiene il corpo HTTP o dati del record.

Per rimuovere anche la raccolta: ripristinare il receiver dal backup
`teamleader_webhook.py.before-nexora-*` e riavviare solo `teamleader-webhook.service`.
Non toccare la coda n8n/monitor. I suoi 81 eventi falliti preesistenti non sono stati
consumati o riprodotti da questa integrazione.

Non e una copia integrale dello storico: l'eventuale riconciliazione iniziale deve
essere un'operazione separata, dopo confronto degli ID e dei periodi filtrati.

## Test

```sh
python3 -m unittest discover -s deploy/teamleader -p 'test_*.py' -v
php deploy/teamleader/test_mapper.php
```

Test unita della coda e mapper eseguiti; il test MySQL/hosting completo richiede
il caricamento dell'endpoint e una prima anteprima autenticata.
