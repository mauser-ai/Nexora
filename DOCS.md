# Gussoni CRM — Struttura del progetto

## `lib/`

```
lib/
├── main.dart
├── brand_config.dart
├── firebase_options.dart
│
├── app/
│   ├── mb_workflow_app.dart
│   ├── mobile_workspace_scaffold.dart
│   ├── agenda_calendar.dart
│   ├── archive_manager_card.dart
│   └── ticket_center_card.dart
│
├── models/
│   ├── domain_models.dart
│   ├── roles.dart
│   ├── subscription_models.dart
│   └── template_models.dart
│
├── crm/
│   ├── models/
│   │   ├── crm_models.dart
│   │   └── crm_extra_models.dart
│   ├── data/
│   │   ├── crm_store.dart
│   │   └── firestore_crm_repository.dart
│   └── screens/
│       ├── crm_hub_card.dart
│       ├── societa_card.dart
│       ├── contatti_firestore_card.dart
│       ├── deals_kanban_card.dart
│       ├── preventivi_card.dart
│       ├── ordini_di_lavoro_card.dart
│       ├── finanze_card.dart
│       ├── note_di_credito_card.dart
│       ├── spese_card.dart
│       ├── task_list_card.dart
│       ├── ticket_list_card.dart
│       ├── progetti_card.dart
│       ├── area_commerciale_card.dart
│       ├── carico_card.dart
│       ├── opportunita_card.dart
│       ├── form_di_contatto_card.dart
│       ├── tl_table.dart
│       └── detail/
│           ├── company_detail.dart
│           ├── contact_detail.dart
│           ├── deal_detail.dart
│           ├── quotation_detail.dart
│           ├── simple_details.dart
│           └── detail_widgets.dart
│
├── gussoni/
│   ├── screens/
│   │   ├── societa_screen.dart
│   │   ├── contatti_screen.dart
│   │   ├── opportunita_screen.dart
│   │   ├── preventivo_screen.dart
│   │   ├── progetti_screen.dart
│   │   ├── task_screen.dart
│   │   ├── finanze_screen.dart
│   │   ├── segnatempo_screen.dart
│   │   └── statistiche_screen.dart
│   └── widgets/
│       └── g_table.dart
│
├── data/
│   ├── firestore_workspace_repository.dart
│   ├── team_repository.dart
│   ├── template_repository.dart
│   └── sample_data.dart
│
├── services/
│   ├── analytics_service.dart
│   ├── archive_service.dart
│   ├── google_calendar_service.dart
│   ├── planning_service.dart
│   ├── ticket_mail_service.dart
│   ├── youdox_service.dart
│   ├── push_token_registration_service.dart
│   ├── daily_brief_notification_service.dart
│   ├── brand_bootstrap_cache.dart
│   ├── brand_bootstrap_cache_model.dart
│   ├── brand_bootstrap_cache_web.dart
│   ├── brand_bootstrap_cache_stub.dart
│   ├── web_file_picker.dart
│   ├── web_file_picker_web.dart
│   └── web_file_picker_stub.dart
│
├── settings/
│   ├── settings_page.dart
│   ├── pdf_generator.dart
│   ├── send_email_dialog.dart
│   ├── email_template_editor.dart
│   └── template_builder_page.dart
│
└── admin/
    ├── admin_screen.dart
    └── admin_repository.dart
```

---

## Classi e funzioni principali

### `main.dart`
- `main()` — inizializza Firebase, locale `it_IT`, persistenza offline Firestore, avvia `MbWorkflowApp`

---

### `brand_config.dart`
- `GussoniBrand` — classe astratta con tutte le costanti di colore, font e stile
  - `buildTheme() → ThemeData` — tema Material 3 completo
  - `buildTextTheme() → TextTheme` — Barlow (titoli) + Roboto (corpo)
- `hexToColor(String?) → Color?`
- `colorToHex(Color) → String`

---

### `app/mb_workflow_app.dart`
- `MbWorkflowApp` — `MaterialApp` root, applica `GussoniBrand.buildTheme()`
- `AuthGate` — ascolta `FirebaseAuth.authStateChanges()`, instrada verso `LoginPage`, `AdminPanel` o `DashboardPage`
- `LoginPage` / `_LoginPageState` — login email/password con `signInWithEmailAndPassword`
- `DashboardPage` — scaffold principale con sidebar e area contenuto centrale

---

### `models/domain_models.dart`

**Enums**
- `TaskStatus` — `backlog, planned, inProgress, done`
- `InvoiceStatus` — `draft, readyForXml, exported`
- `TicketStatus` — `newTicket, open, waitingCustomer, closed`
- `TicketEntryType` — `internalNote, outboundEmail, inboundEmail`
- `OpportunityStatus` — `new_, analysis, quoted, accepted, rejected, lost`
- `ProjectType` — `profit, noProfit`
- `ProjectStatus` — `draft, planning, inProgress, pendingResult, approved, rejected, closed`
- `PhaseStatus` — `notStarted, inProgress, done`
- `PreventivoStatus` — `draft, sent, accepted, rejected`

**Parse helpers** — `parseTaskStatus`, `parseInvoiceStatus`, `parseTicketStatus`, `parseOpportunityStatus`, `parseProjectStatus`, `parsePhaseStatus`, `parsePreventivoStatus`, `parseProjectType`, `parseDate`

**Classi**
- `Company` — anagrafica cliente (`id, name, vatNumber, taxCode, pec, sdiCode, email, phone, addressLine, city, isNonProfit, legalRepresentative`)
- `CompanyContact` — persona fisica collegata a una `Company`
- `Opportunity` — bando/richiesta (`companyId, title, status, bandoReference, bandoSource, bandoDeadline, estimatedValue, assignedAnalystId`)
- `PreventivoLine` — riga preventivo (`description, quantity, unitPrice`); `get total`
- `Preventivo` — preventivo commerciale (`opportunityId, companyId, lines[], istruttoriaFee, successFeePercent`); `get subtotal`, `get total`, `calculateSuccessFee(grantAmount)`
- `Project` — commessa (`companyId, name, code, status, type, grantAmount, successFeeAmount, opportunityId, quotationId`)
- `ProjectPhase` — fase di progetto (`name, status, startDate, endDate`)
- `WorkTask` — attività interna (`title, status, dueDate, assignedUserId, projectId, companyId`)
- `Ticket` — ticket di supporto (`companyId, subject, status, assignedUserId, entries[]`)
- `TicketEntry` — messaggio nel thread ticket (`type, body, authorId, createdAt`)
- `InvoiceDraft` + `InvoiceLine` — bozza fattura elettronica
- `BillingProfile` — dati emittente per FatturaPA
- `YouDoxConfig` — credenziali Youdox (`username, password, clientId`)
- `TimeTrack` — ore lavorate (`userId, projectId, companyId, date, hours`)
- `UserAvailability`, `VacationPeriod` — disponibilità e ferie
- `TimelineSlot` — slot pianificazione
- `TeamMember` — membro del team con ruolo

Ogni classe espone `fromMap(id, Map)`, `toMap()`, `copyWith(...)`.

---

### `crm/models/crm_extra_models.dart`

- `CrmFirestoreContact` — contatto CRM (`companyId, tags[], source`)
- `Deal` + `DealStage` — opportunità in pipeline Kanban
- `Quotation` + `QuotationLine` — preventivo CRM
- `Expense` — spesa aziendale; enum `ExpenseCategory` (`software, hardware, travel, marketing, office, consulting, other`)
- `Product` — catalogo prodotti/servizi
- `WorkOrder` — ordine di lavoro
- `ContactForm` — modulo contatto ricevuto
- `CreditNote` — nota di credito
- `Subscription` — abbonamento (non attivo)
- `CrmData` — contenitore immutabile di tutti i dati sopra, emesso da `FirestoreCrmRepository`

---

### `crm/models/crm_models.dart`

- Enums: `TeamMemberRole, TeamMemberStatus, DealStatus, CrmTaskStatus, CrmTaskPriority, CrmProjectStatus, CrmQuotationStatus, CrmInvoiceStatus, CrmActivityActionType`
- Classi: `CrmTeam, CrmTeamMember, CrmUser, CrmCompany, CrmContact, CrmDeal, CrmPipelineStage, CrmTask, CrmComment, CrmNote, CrmProject, CrmMilestone, CrmQuotation, CrmInvoice, CrmActivityItem`
- Ogni enum ha estensione con `get label` e `get color`

---

### `crm/data/crm_store.dart`
- `CrmStore extends ChangeNotifier` — stato in memoria per i dati CRM legacy
  - Getter filtrati per `teamId`: `companies, contacts, deals, tasks, projects, quotations, ...`
  - Metodi `add/update/remove` per ogni entità → scrivono su Firestore + `notifyListeners()`

---

### `crm/data/firestore_crm_repository.dart`
- `FirestoreCrmRepository`
  - `watchCrmData(userId) → Stream<CrmData>` — stream combinato che ascolta tutte le sotto-collezioni CRM e riemette `CrmData` ad ogni cambiamento

---

### `data/firestore_workspace_repository.dart`
- `WorkspaceSnapshot` — oggetto immutabile con tutti i dati del workspace (`companies, tickets, projects, phases, tasks, invoiceDrafts, opportunities, gussoniQuotations, ...`)
- `FirestoreWorkspaceRepository`
  - `watchSnapshot(userId) → Stream<WorkspaceSnapshot>` — stream principale dell'app
  - Metodi CRUD per ogni entità (`saveCompany`, `deleteTicket`, `upsertTask`, ecc.)

---

### `data/team_repository.dart`
- `TeamRepository`
  - `watchTeam(teamId) → Stream<Team>`
  - `addMember`, `removeMember`, `updateMemberRole`

---

### `services/archive_service.dart`
- `ArchiveEntry` — `name, path, isDirectory, sizeBytes, modifiedAt`
- `ArchiveListResponse` — `currentPath, folders[], files[]`
- `ArchiveService`
  - `listEntries(path) → Future<ArchiveListResponse>`
  - `listFolders() → Future<List<ArchiveEntry>>`
  - `upload(path, bytes, filename)`
  - `uploadBase64(path, base64, filename)`
  - `download(path) → Future<Uint8List>`
  - `delete(path)`, `rename(old, new)`, `move(src, dst)`
  - `createFolder(path)`
  - `createShareLink(path) → Future<String>`
  - `ensureCompanyFolders(companies[])`

---

### `services/youdox_service.dart`
- `YoudoxDraftResult` — `filename, message`
- `YoudoxService`
  - `createDraftFromXml({xml, filename, credentials}) → Future<YoudoxDraftResult>` — chiama la Cloud Function HTTP con `Authorization: Bearer <Firebase ID Token>`

---

### `services/analytics_service.dart`
- `AnalyticsService` — singleton (`instance`)
  - `logAppOpened()`, `logLogin(method)`
  - `observer` — `NavigatorObserver` per tracciare navigazioni

---

### `services/google_calendar_service.dart`
- `GoogleCalendarService` — sincronizza task/scadenze con Google Calendar via API v3 + OAuth

---

### `services/planning_service.dart`
- `PlanningService` — calcola disponibilità del team considerando `UserAvailability` e `VacationPeriod`

---

### `services/push_token_registration_service.dart`
- `PushTokenRegistrationService`
  - `register(userId)` — salva il token FCM su `users/{userId}/pushTokens`

---

### `services/ticket_mail_service.dart`
- `TicketMailService` — invia email di risposta ai ticket tramite backend PHP (`send_ticket.php`)

---

### `settings/pdf_generator.dart`
- `PdfGenerator`
  - `generatePreventivoPdf(preventivo, company, ...) → Future<Uint8List>`
  - `generateInvoiceXml(invoice, billingProfile, ...) → String` — XML FatturaPA per Youdox

---

### `settings/settings_page.dart`
- `SettingsPage` — impostazioni utente: profilo fatturazione, credenziali Youdox, firma email, template

---

### `admin/admin_repository.dart`
- `kAdminUid` — UID dell'unico utente admin (costante da aggiornare su Firebase Console)
- `AdminRepository`
  - `watchAllTeams() → Stream<List<AdminTeam>>`

---

### `admin/admin_screen.dart`
- `AdminPanel` — dashboard admin: lista tutti i team con membri e profili di fatturazione
