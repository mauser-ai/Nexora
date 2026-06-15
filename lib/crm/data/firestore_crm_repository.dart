import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../models/domain_models.dart';
import '../models/crm_extra_models.dart';

// ────────────────────────────────────────────────
// FirestoreCrmRepository
// Legge/scrive tutte le nuove entità CRM sotto
// users/{userId}/ (stessa struttura del workspace esistente)
// ────────────────────────────────────────────────

class FirestoreCrmRepository {
  FirestoreCrmRepository({FirebaseFirestore? firestore})
    : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;
  static final DateTime _epoch = DateTime.fromMillisecondsSinceEpoch(0);

  CollectionReference<Map<String, dynamic>> _c(String userId, String name) =>
      _db.collection('users').doc(userId).collection(name);

  DateTime _recent(DateTime? updatedAt, DateTime? createdAt) =>
      updatedAt ?? createdAt ?? _epoch;

  // ────── Stream combinato CrmData ──────

  Stream<CrmData> watchCrmData(String userId) {
    final ctrl = StreamController<CrmData>();

    var contacts = <CrmFirestoreContact>[];
    var deals = <Deal>[];
    var stages = <DealStage>[];
    var quotations = <Quotation>[];
    var expenses = <Expense>[];
    var products = <Product>[];
    var workOrders = <WorkOrder>[];
    var contactForms = <ContactForm>[];
    var subscriptions = <Subscription>[];
    var creditNotes = <CreditNote>[];

    void emit() {
      if (!ctrl.isClosed) {
        ctrl.add(
          CrmData(
            contacts: [...contacts]
              ..sort(
                (a, b) => _recent(
                  b.updatedAt,
                  b.createdAt,
                ).compareTo(_recent(a.updatedAt, a.createdAt)),
              ),
            deals: [...deals]
              ..sort(
                (a, b) => _recent(
                  b.updatedAt,
                  b.createdAt,
                ).compareTo(_recent(a.updatedAt, a.createdAt)),
              ),
            dealStages: [...stages]..sort((a, b) => a.order.compareTo(b.order)),
            quotations: [...quotations]
              ..sort(
                (a, b) => _recent(
                  b.updatedAt,
                  b.createdAt,
                ).compareTo(_recent(a.updatedAt, a.createdAt)),
              ),
            expenses: [...expenses]
              ..sort(
                (a, b) => _recent(
                  b.createdAt,
                  b.date,
                ).compareTo(_recent(a.createdAt, a.date)),
              ),
            products: [...products]
              ..sort(
                (a, b) => _recent(
                  null,
                  b.createdAt,
                ).compareTo(_recent(null, a.createdAt)),
              ),
            workOrders: [...workOrders]
              ..sort(
                (a, b) => _recent(
                  b.updatedAt,
                  b.createdAt,
                ).compareTo(_recent(a.updatedAt, a.createdAt)),
              ),
            contactForms: [...contactForms]
              ..sort(
                (a, b) => _recent(
                  null,
                  b.createdAt,
                ).compareTo(_recent(null, a.createdAt)),
              ),
            subscriptions: [...subscriptions]
              ..sort(
                (a, b) => _recent(
                  b.updatedAt,
                  b.createdAt,
                ).compareTo(_recent(a.updatedAt, a.createdAt)),
              ),
            creditNotes: [...creditNotes]
              ..sort(
                (a, b) => _recent(
                  b.updatedAt,
                  b.createdAt,
                ).compareTo(_recent(a.updatedAt, a.createdAt)),
              ),
          ),
        );
      }
    }

    emit();

    final subs = <StreamSubscription<dynamic>>[
      _c(userId, 'crmContacts').snapshots().listen((s) {
        contacts = s.docs
            .map((d) => CrmFirestoreContact.fromMap(d.id, d.data()))
            .toList();
        emit();
      }),
      _c(userId, 'deals').snapshots().listen((s) {
        deals = s.docs.map((d) => Deal.fromMap(d.id, d.data())).toList();
        emit();
      }),
      _c(userId, 'pipelineStages').snapshots().listen((s) {
        stages = s.docs.map((d) => DealStage.fromMap(d.id, d.data())).toList();
        emit();
      }),
      _c(userId, 'quotations').snapshots().listen((s) {
        quotations = s.docs
            .map((d) => Quotation.fromMap(d.id, d.data()))
            .toList();
        emit();
      }),
      _c(userId, 'expenses').snapshots().listen((s) {
        expenses = s.docs.map((d) => Expense.fromMap(d.id, d.data())).toList();
        emit();
      }),
      _c(userId, 'products').snapshots().listen((s) {
        products = s.docs.map((d) => Product.fromMap(d.id, d.data())).toList();
        emit();
      }),
      _c(userId, 'workOrders').snapshots().listen((s) {
        workOrders = s.docs
            .map((d) => WorkOrder.fromMap(d.id, d.data()))
            .toList();
        emit();
      }),
      _c(userId, 'contactForms').snapshots().listen((s) {
        contactForms = s.docs
            .map((d) => ContactForm.fromMap(d.id, d.data()))
            .toList();
        emit();
      }),
      _c(userId, 'subscriptions').snapshots().listen((s) {
        subscriptions = s.docs
            .map((d) => Subscription.fromMap(d.id, d.data()))
            .toList();
        emit();
      }),
      _c(userId, 'creditNotes').snapshots().listen((s) {
        creditNotes = s.docs
            .map((d) => CreditNote.fromMap(d.id, d.data()))
            .toList();
        emit();
      }),
    ];

    ctrl.onCancel = () {
      for (final sub in subs) {
        sub.cancel();
      }
    };

    return ctrl.stream;
  }

  // ────── Deal CRUD ──────

  Future<void> createDeal(String userId, Deal deal) =>
      _c(userId, 'deals').doc(deal.id).set(deal.toMap());

  Future<void> updateDeal(String userId, Deal deal) => _c(
    userId,
    'deals',
  ).doc(deal.id).set(deal.toMap(), SetOptions(merge: true));

  Future<void> deleteDeal(String userId, String dealId) =>
      _c(userId, 'deals').doc(dealId).delete();

  // ────── DealStage CRUD ──────

  Future<void> createStage(String userId, DealStage stage) =>
      _c(userId, 'pipelineStages').doc(stage.id).set(stage.toMap());

  // ────── CrmContact CRUD ──────

  Future<void> createContact(String userId, CrmFirestoreContact contact) =>
      _c(userId, 'crmContacts').doc(contact.id).set(contact.toMap());

  Future<void> updateContact(String userId, CrmFirestoreContact contact) => _c(
    userId,
    'crmContacts',
  ).doc(contact.id).set(contact.toMap(), SetOptions(merge: true));

  Future<void> deleteContact(String userId, String contactId) =>
      _c(userId, 'crmContacts').doc(contactId).delete();

  // ────── Quotation CRUD ──────

  Future<void> createQuotation(String userId, Quotation q) =>
      _c(userId, 'quotations').doc(q.id).set(q.toMap());

  Future<void> updateQuotation(String userId, Quotation q) => _c(
    userId,
    'quotations',
  ).doc(q.id).set(q.toMap(), SetOptions(merge: true));

  Future<void> deleteQuotation(String userId, String id) =>
      _c(userId, 'quotations').doc(id).delete();

  // ────── Expense CRUD ──────

  Future<void> createExpense(String userId, Expense e) =>
      _c(userId, 'expenses').doc(e.id).set(e.toMap());

  Future<void> updateExpense(String userId, Expense e) =>
      _c(userId, 'expenses').doc(e.id).set(e.toMap(), SetOptions(merge: true));

  Future<void> deleteExpense(String userId, String id) =>
      _c(userId, 'expenses').doc(id).delete();

  // ────── Product CRUD ──────

  Future<void> createProduct(String userId, Product p) =>
      _c(userId, 'products').doc(p.id).set(p.toMap());

  Future<void> updateProduct(String userId, Product p) =>
      _c(userId, 'products').doc(p.id).set(p.toMap(), SetOptions(merge: true));

  Future<void> deleteProduct(String userId, String id) =>
      _c(userId, 'products').doc(id).delete();

  // ────── WorkOrder CRUD ──────

  Future<void> createWorkOrder(String userId, WorkOrder w) =>
      _c(userId, 'workOrders').doc(w.id).set(w.toMap());

  Future<void> updateWorkOrder(String userId, WorkOrder w) => _c(
    userId,
    'workOrders',
  ).doc(w.id).set(w.toMap(), SetOptions(merge: true));

  Future<void> deleteWorkOrder(String userId, String id) =>
      _c(userId, 'workOrders').doc(id).delete();

  // ────── ContactForm CRUD ──────

  Future<void> createContactForm(String userId, ContactForm f) =>
      _c(userId, 'contactForms').doc(f.id).set(f.toMap());

  Future<void> updateContactForm(String userId, ContactForm f) => _c(
    userId,
    'contactForms',
  ).doc(f.id).set(f.toMap(), SetOptions(merge: true));

  // ────── Subscription CRUD ──────

  Future<void> createSubscription(String userId, Subscription s) =>
      _c(userId, 'subscriptions').doc(s.id).set(s.toMap());

  Future<void> updateSubscription(String userId, Subscription s) => _c(
    userId,
    'subscriptions',
  ).doc(s.id).set(s.toMap(), SetOptions(merge: true));

  Future<void> deactivateSubscription(String userId, String id) =>
      _c(userId, 'subscriptions').doc(id).update({
        'status': 'deactivated',
        'updatedAt': FieldValue.serverTimestamp(),
      });

  Future<void> deleteSubscription(String userId, String id) =>
      _c(userId, 'subscriptions').doc(id).delete();

  // ────── CreditNote CRUD ──────

  Future<void> createCreditNote(String userId, CreditNote cn) =>
      _c(userId, 'creditNotes').doc(cn.id).set(cn.toMap());

  Future<void> updateCreditNote(String userId, CreditNote cn) => _c(
    userId,
    'creditNotes',
  ).doc(cn.id).set(cn.toMap(), SetOptions(merge: true));

  Future<void> bookCreditNote(String userId, String id) =>
      _c(userId, 'creditNotes').doc(id).update({
        'status': 'booked',
        'updatedAt': FieldValue.serverTimestamp(),
      });

  Future<void> deleteCreditNote(String userId, String id) =>
      _c(userId, 'creditNotes').doc(id).delete();

  // ────────────────────────────────────────────────
  // SEEDER – popola Firestore con dati demo realistici
  // ────────────────────────────────────────────────

  Future<void> seedCrmData(
    String userId,
    List<Company> existingCompanies,
  ) async {
    // Seed solo se le pipeline stages non esistono ancora
    final stagesSnap = await _c(userId, 'pipelineStages').limit(1).get();
    final needsSeed = stagesSnap.docs.isEmpty;
    if (!needsSeed) return;

    final batch = _db.batch();
    final now = DateTime.now();

    // Ordine di seeding: stages → contacts → deals → quotations → expenses → products → workOrders → contactForms

    // ── 1. Pipeline stages ──
    final stageData = [
      ('stage-lead', 'Lead', 1, '#6B7280', 10),
      ('stage-qual', 'Qualificazione', 2, '#0369A1', 30),
      ('stage-prop', 'Proposta', 3, '#7C3AED', 60),
      ('stage-neg', 'Trattativa', 4, '#D97706', 80),
      ('stage-won', 'Vinto', 5, '#034F3B', 100),
    ];
    for (final (id, name, order, color, prob) in stageData) {
      batch.set(_c(userId, 'pipelineStages').doc(id), {
        'name': name,
        'order': order,
        'colorHex': color,
        'probability': prob,
      });
    }

    // ── 2. CRM Contacts (linkati alle aziende esistenti) ──
    final companyIds = existingCompanies.map((c) => c.id).toList();
    final contactSeed =
        <(String, String, String, String, String, String, String?)>[
          (
            'cnt-fs-1',
            'Luca',
            'Rossi',
            'l.rossi@innovatech.it',
            '+39 335 111 2233',
            'CTO',
            companyIds.isNotEmpty ? companyIds[0] : null,
          ),
          (
            'cnt-fs-2',
            'Giulia',
            'Ferrari',
            'g.ferrari@innovatech.it',
            '+39 347 444 5566',
            'Marketing Manager',
            companyIds.isNotEmpty ? companyIds[0] : null,
          ),
          (
            'cnt-fs-3',
            'Avv. Andrea',
            'Romani',
            'a.romani@studioromani.it',
            '+39 339 777 8899',
            'Titolare',
            companyIds.length > 1 ? companyIds[1] : null,
          ),
          (
            'cnt-fs-4',
            'Paolo',
            'Mancini',
            'p.mancini@acmesrl.it',
            '+39 340 000 1112',
            'Proprietario',
            companyIds.length > 2 ? companyIds[2] : null,
          ),
          (
            'cnt-fs-5',
            'Dott.ssa Elena',
            'Marinelli',
            'e.marinelli@medgroup.it',
            '+39 338 222 3334',
            'Direttore Generale',
            companyIds.length > 3 ? companyIds[3] : null,
          ),
          (
            'cnt-fs-6',
            'Roberto',
            'Verdi',
            'r.verdi@edilgroup.it',
            '+39 344 555 6667',
            'CEO',
            companyIds.length > 4 ? companyIds[4] : null,
          ),
          (
            'cnt-fs-7',
            'Chiara',
            'Esposito',
            'chiara.esposito@gmail.com',
            '+39 320 999 0011',
            'Freelance Designer',
            null,
          ),
        ];
    for (final (id, fn, ln, email, phone, role, cid) in contactSeed) {
      batch.set(_c(userId, 'crmContacts').doc(id), {
        'firstName': fn,
        'lastName': ln,
        'email': email,
        'phone': phone,
        'role': role,
        'tags': <String>[],
        'notes': '',
        if (cid != null) 'companyId': cid,
        'createdAt': Timestamp.fromDate(
          now.subtract(const Duration(days: 120)),
        ),
        'updatedAt': Timestamp.fromDate(now.subtract(const Duration(days: 5))),
      });
    }

    // ── 3. Deals (linkati alle aziende esistenti) ──
    final dealSeed = <Map<String, dynamic>>[
      {
        'id': 'deal-fs-1',
        'title': 'Sito web istituzionale',
        'stageId': 'stage-lead',
        'status': 'open',
        'value': 3500.0,
        'probability': 15,
        'currency': 'EUR',
        if (companyIds.length > 2) 'customerId': companyIds[2],
        'customerType': 'company',
        'notes': 'Cliente interessato a restyling completo',
        'daysAgo': 20,
      },
      {
        'id': 'deal-fs-2',
        'title': 'CRM aziendale personalizzato',
        'stageId': 'stage-qual',
        'status': 'open',
        'value': 12000.0,
        'probability': 35,
        'currency': 'EUR',
        if (companyIds.isNotEmpty) 'customerId': companyIds[0],
        'customerType': 'company',
        'notes': 'Richiesta integrazione con sistema legacy',
        'daysAgo': 35,
      },
      {
        'id': 'deal-fs-3',
        'title': 'App mobile prenotazioni',
        'stageId': 'stage-prop',
        'status': 'open',
        'value': 18500.0,
        'probability': 65,
        'currency': 'EUR',
        if (companyIds.length > 3) 'customerId': companyIds[3],
        'customerType': 'company',
        'notes': 'Demo approvata, in attesa del legale',
        'daysAgo': 50,
      },
      {
        'id': 'deal-fs-4',
        'title': 'Portale clienti',
        'stageId': 'stage-neg',
        'status': 'open',
        'value': 7200.0,
        'probability': 82,
        'currency': 'EUR',
        if (companyIds.length > 1) 'customerId': companyIds[1],
        'customerType': 'company',
        'notes': 'Contratto quasi pronto',
        'daysAgo': 60,
      },
      {
        'id': 'deal-fs-5',
        'title': 'E-commerce B2B',
        'stageId': 'stage-qual',
        'status': 'open',
        'value': 9800.0,
        'probability': 30,
        'currency': 'EUR',
        if (companyIds.length > 4) 'customerId': companyIds[4],
        'customerType': 'company',
        'notes': 'Primo incontro promettente',
        'daysAgo': 10,
      },
      {
        'id': 'deal-fs-6',
        'title': 'Newsletter automation',
        'stageId': 'stage-won',
        'status': 'won',
        'value': 2400.0,
        'probability': 100,
        'currency': 'EUR',
        if (companyIds.isNotEmpty) 'customerId': companyIds[0],
        'customerType': 'company',
        'notes': '',
        'daysAgo': 90,
      },
    ];
    for (final d in dealSeed) {
      final daysAgo = d['daysAgo'] as int? ?? 0;
      batch.set(_c(userId, 'deals').doc(d['id'] as String), {
        'title': d['title'],
        'stageId': d['stageId'],
        'status': d['status'],
        'value': d['value'],
        'probability': d['probability'],
        'currency': d['currency'],
        if (d['customerId'] != null) 'customerId': d['customerId'],
        if (d['customerType'] != null) 'customerType': d['customerType'],
        'notes': d['notes'],
        'expectedClosingDate': Timestamp.fromDate(
          now.add(Duration(days: 30 - daysAgo)),
        ),
        'createdAt': Timestamp.fromDate(now.subtract(Duration(days: daysAgo))),
        'updatedAt': Timestamp.fromDate(now.subtract(const Duration(days: 1))),
      });
    }

    // ── 4. Quotations (Preventivi) ──
    final quotSeed = <Map<String, dynamic>>[
      {
        // PRV-001 → deal-fs-1 (Sito web Morelli), riga con productId → prod-fs-7
        'id': 'quot-fs-1', 'number': 'PRV-2025-001', 'status': 'sent',
        'dealId': 'deal-fs-1',
        if (companyIds.length > 2) 'customerId': companyIds[2],
        'customerType': 'company',
        'currency': 'EUR',
        'lines': [
          {
            'description': 'Sito web vetrina – pacchetto',
            'quantity': 1.0,
            'unitPrice': 1800.0,
            'vatRate': 22.0,
            'productId': 'prod-fs-7',
          },
          {
            'description': 'Hosting annuale – base',
            'quantity': 1.0,
            'unitPrice': 120.0,
            'vatRate': 22.0,
            'productId': 'prod-fs-4',
          },
          {
            'description': 'Dominio .it – registrazione',
            'quantity': 1.0,
            'unitPrice': 15.0,
            'vatRate': 22.0,
            'productId': 'prod-fs-6',
          },
        ],
        'notes': 'Valido 30 giorni dalla data di emissione.',
        'daysAgo': 15,
      },
      {
        // PRV-002 → deal-fs-5 (E-commerce Edilgreen), riga con productId → prod-fs-8
        'id': 'quot-fs-2', 'number': 'PRV-2025-002', 'status': 'accepted',
        'dealId': 'deal-fs-5',
        if (companyIds.length > 4) 'customerId': companyIds[4],
        'customerType': 'company',
        'currency': 'EUR',
        'lines': [
          {
            'description': 'E-commerce – pacchetto base',
            'quantity': 1.0,
            'unitPrice': 4500.0,
            'vatRate': 22.0,
            'productId': 'prod-fs-8',
          },
          {
            'description': 'Integrazione gateway pagamento',
            'quantity': 1.0,
            'unitPrice': 800.0,
            'vatRate': 22.0,
          },
          {
            'description': 'Formazione team (ore)',
            'quantity': 4.0,
            'unitPrice': 125.0,
            'vatRate': 22.0,
            'productId': 'prod-fs-3',
          },
        ],
        'notes': '',
        'daysAgo': 30,
      },
      {
        // PRV-003 → deal-fs-3 (App MedGroup)
        'id': 'quot-fs-3', 'number': 'PRV-2025-003', 'status': 'draft',
        'dealId': 'deal-fs-3',
        if (companyIds.length > 3) 'customerId': companyIds[3],
        'customerType': 'company',
        'currency': 'EUR',
        'lines': [
          {
            'description': 'Sviluppo app mobile iOS/Android – fase 1',
            'quantity': 120.0,
            'unitPrice': 95.0,
            'vatRate': 22.0,
            'productId': 'prod-fs-1',
          },
          {
            'description': 'Design UX/UI',
            'quantity': 40.0,
            'unitPrice': 80.0,
            'vatRate': 22.0,
            'productId': 'prod-fs-2',
          },
          {
            'description': 'Consulenza strategica',
            'quantity': 8.0,
            'unitPrice': 120.0,
            'vatRate': 22.0,
            'productId': 'prod-fs-3',
          },
        ],
        'notes': 'In attesa di approvazione budget cliente.',
        'daysAgo': 5,
      },
    ];
    for (final q in quotSeed) {
      final daysAgo = q['daysAgo'] as int? ?? 0;
      batch.set(_c(userId, 'quotations').doc(q['id'] as String), {
        'number': q['number'],
        'status': q['status'],
        if (q['customerId'] != null) 'customerId': q['customerId'],
        if (q['customerType'] != null) 'customerType': q['customerType'],
        if (q['dealId'] != null) 'dealId': q['dealId'],
        'currency': q['currency'],
        'lines': q['lines'],
        'notes': q['notes'],
        'validUntil': Timestamp.fromDate(now.add(const Duration(days: 15))),
        'createdAt': Timestamp.fromDate(now.subtract(Duration(days: daysAgo))),
        'updatedAt': Timestamp.fromDate(now.subtract(Duration(days: daysAgo))),
      });
    }

    // ── 5. Expenses (Spese) ──
    final expenseSeed = [
      ('exp-fs-1', 'Abbonamento Figma – mensile', 45.0, 'software', 30),
      ('exp-fs-2', 'Abbonamento ChatGPT Plus', 20.0, 'software', 28),
      ('exp-fs-3', 'Google Workspace Business', 12.0, 'software', 25),
      ('exp-fs-4', 'Trasferta Milano – treno', 58.0, 'travel', 20),
      ('exp-fs-5', 'Pranzo di lavoro', 65.0, 'office', 18),
      ('exp-fs-6', 'Stampa materiali promozionali', 220.0, 'marketing', 15),
      ('exp-fs-7', 'Server VPS – mensile', 35.0, 'software', 10),
      ('exp-fs-8', 'Cancelleria ufficio', 48.0, 'office', 5),
    ];
    for (final (id, title, amount, cat, daysAgo) in expenseSeed) {
      batch.set(_c(userId, 'expenses').doc(id), {
        'title': title,
        'amount': amount,
        'category': cat,
        'currency': 'EUR',
        'notes': '',
        'attachmentPath': '',
        'date': Timestamp.fromDate(now.subtract(Duration(days: daysAgo))),
        'createdAt': Timestamp.fromDate(now.subtract(Duration(days: daysAgo))),
      });
    }

    // ── 6. Products (Prodotti / Servizi) ──
    final productSeed = [
      (
        'prod-fs-1',
        'Sviluppo web – ora',
        'DEV-WEB-01',
        'Ora di sviluppo frontend/backend',
        95.0,
        'ora',
        'servizi',
      ),
      (
        'prod-fs-2',
        'Design UX/UI – ora',
        'DES-UX-01',
        'Ora di design interfacce',
        80.0,
        'ora',
        'servizi',
      ),
      (
        'prod-fs-3',
        'Consulenza strategica – ora',
        'CON-STR-01',
        'Consulenza business e digital strategy',
        120.0,
        'ora',
        'servizi',
      ),
      (
        'prod-fs-4',
        'Hosting annuale – base',
        'HOST-BASE-01',
        'Hosting web SSD, SSL incluso',
        120.0,
        'anno',
        'infrastruttura',
      ),
      (
        'prod-fs-5',
        'Hosting annuale – pro',
        'HOST-PRO-01',
        'Hosting web dedicato, CDN + backup',
        360.0,
        'anno',
        'infrastruttura',
      ),
      (
        'prod-fs-6',
        'Dominio .it – annuale',
        'DOM-IT-01',
        'Registrazione/rinnovo dominio .it',
        15.0,
        'anno',
        'infrastruttura',
      ),
      (
        'prod-fs-7',
        'Sito web vetrina – pacchetto',
        'WEB-VET-01',
        'Sito informativo 5 pagine incluso design',
        1800.0,
        'pz',
        'prodotti',
      ),
      (
        'prod-fs-8',
        'E-commerce – pacchetto base',
        'WEB-ECO-01',
        'Shop online fino a 100 prodotti',
        4500.0,
        'pz',
        'prodotti',
      ),
    ];
    for (final (id, name, sku, desc, price, unit, cat) in productSeed) {
      batch.set(_c(userId, 'products').doc(id), {
        'name': name,
        'sku': sku,
        'description': desc,
        'price': price,
        'currency': 'EUR',
        'unit': unit,
        'category': cat,
        'vatRate': 22.0,
        'createdAt': Timestamp.fromDate(
          now.subtract(const Duration(days: 180)),
        ),
      });
    }

    // ── 7. Work Orders (Ordini di lavoro) ──
    final woSeed = [
      (
        'wo-fs-1',
        'Aggiornamento WordPress + plugin',
        'open',
        'medium',
        companyIds.length > 2 ? companyIds[2] : null,
        3,
      ),
      (
        'wo-fs-2',
        'Backup manuale DB produzione',
        'done',
        'high',
        companyIds.isNotEmpty ? companyIds[0] : null,
        10,
      ),
      (
        'wo-fs-3',
        'Fix bug pagina checkout',
        'inProgress',
        'urgent',
        companyIds.length > 4 ? companyIds[4] : null,
        1,
      ),
      (
        'wo-fs-4',
        'Configurazione server staging',
        'open',
        'medium',
        companyIds.length > 3 ? companyIds[3] : null,
        7,
      ),
      (
        'wo-fs-5',
        'Monitoraggio performance sito',
        'open',
        'low',
        companyIds.length > 1 ? companyIds[1] : null,
        14,
      ),
    ];
    for (final (id, title, status, priority, cid, dueDays) in woSeed) {
      batch.set(_c(userId, 'workOrders').doc(id), {
        'title': title,
        'status': status,
        'priority': priority,
        if (cid != null) 'companyId': cid,
        'description': '',
        'dueDate': Timestamp.fromDate(now.add(Duration(days: dueDays))),
        'createdAt': Timestamp.fromDate(now.subtract(const Duration(days: 5))),
        'updatedAt': Timestamp.fromDate(now.subtract(const Duration(days: 1))),
      });
    }

    // ── 8. Contact Forms (Lead) ──
    final formSeed = [
      (
        'form-fs-1',
        'Mario Bianchi',
        'mario.bianchi@gmail.com',
        '+39 349 100 2233',
        'Vorrei informazioni per un sito web aziendale.',
        'website',
        'newLead',
        2,
      ),
      (
        'form-fs-2',
        'Studio Dentistico Fusaro',
        'info@studiofusaro.it',
        '081 456 7890',
        'Abbiamo bisogno di un sito con prenotazioni online.',
        'google_ads',
        'contacted',
        5,
      ),
      (
        'form-fs-3',
        'Laura Conti',
        'laura.conti@libero.it',
        '+39 336 788 9900',
        'Cerco qualcuno che gestisca i miei social media.',
        'instagram',
        'newLead',
        1,
      ),
      (
        'form-fs-4',
        'Arredamenti Pellegrini',
        'info@pellegrini.it',
        '055 234 5678',
        'Interessati a un catalogo prodotti online con preventivi.',
        'passaparola',
        'converted',
        20,
      ),
    ];
    for (final (id, name, email, phone, msg, source, status, daysAgo)
        in formSeed) {
      batch.set(_c(userId, 'contactForms').doc(id), {
        'name': name,
        'email': email,
        'phone': phone,
        'message': msg,
        'source': source,
        'status': status,
        'createdAt': Timestamp.fromDate(now.subtract(Duration(days: daysAgo))),
      });
    }

    // ── 9. Subscriptions (Abbonamenti) ──
    // Teamleader: status active|deactivated, billing_cycle, invoicee.customer
    final subSeed = [
      {
        'id': 'sub-fs-1',
        'title': 'Assistenza tecnica mensile',
        'note': 'Supporto prioritario 8-18',
        'status': 'active',
        'currency': 'EUR',
        if (companyIds.isNotEmpty) 'customerId': companyIds[0],
        'customerType': 'company',
        'billingCycle': {'unit': 'month', 'period': 1, 'daysInAdvance': 5},
        'lines': [
          {
            'description': 'Assistenza tecnica – canone mensile',
            'quantity': 1.0,
            'unitPrice': 150.0,
            'vatRate': 22.0,
          },
        ],
        'startsOn': Timestamp.fromDate(DateTime(2025, 1, 1)),
      },
      {
        'id': 'sub-fs-2',
        'title': 'Hosting e manutenzione siti',
        'note': 'Include backup giornaliero',
        'status': 'active',
        'currency': 'EUR',
        if (companyIds.length > 1) 'customerId': companyIds[1],
        'customerType': 'company',
        'billingCycle': {'unit': 'year', 'period': 1, 'daysInAdvance': 30},
        'lines': [
          {
            'description': 'Hosting annuale – pro',
            'quantity': 1.0,
            'unitPrice': 360.0,
            'vatRate': 22.0,
            'productId': 'prod-fs-5',
          },
          {
            'description': 'Dominio .it',
            'quantity': 1.0,
            'unitPrice': 15.0,
            'vatRate': 22.0,
            'productId': 'prod-fs-6',
          },
        ],
        'startsOn': Timestamp.fromDate(DateTime(2025, 3, 1)),
        'nextRenewalDate': Timestamp.fromDate(DateTime(2026, 3, 1)),
      },
      {
        'id': 'sub-fs-3',
        'title': 'Newsletter mensile – gestione',
        'note': '',
        'status': 'deactivated',
        'currency': 'EUR',
        if (companyIds.length > 2) 'customerId': companyIds[2],
        'customerType': 'company',
        'billingCycle': {'unit': 'month', 'period': 1, 'daysInAdvance': 3},
        'lines': [
          {
            'description': 'Gestione newsletter mensile',
            'quantity': 1.0,
            'unitPrice': 80.0,
            'vatRate': 22.0,
          },
        ],
        'startsOn': Timestamp.fromDate(DateTime(2024, 6, 1)),
        'endsOn': Timestamp.fromDate(DateTime(2025, 1, 31)),
      },
    ];
    for (final s in subSeed) {
      batch.set(_c(userId, 'subscriptions').doc(s['id'] as String), {
        'title': s['title'],
        'note': s['note'],
        'status': s['status'],
        'currency': s['currency'],
        if (s['customerId'] != null) 'customerId': s['customerId'],
        if (s['customerType'] != null) 'customerType': s['customerType'],
        'billingCycle': s['billingCycle'],
        'lines': s['lines'],
        if (s['startsOn'] != null) 'startsOn': s['startsOn'],
        if (s['endsOn'] != null) 'endsOn': s['endsOn'],
        if (s['nextRenewalDate'] != null)
          'nextRenewalDate': s['nextRenewalDate'],
        'createdAt': Timestamp.fromDate(now.subtract(const Duration(days: 90))),
        'updatedAt': Timestamp.fromDate(now.subtract(const Duration(days: 30))),
      });
    }

    // ── 10. Credit Notes (Note di credito) ──
    // Teamleader: credit_note_number, status, invoice (original ref), invoicee.customer
    final cnSeed = [
      {
        'id': 'cn-fs-1',
        'creditNoteNumber': 'NC-2025-001',
        'creditNoteDate': Timestamp.fromDate(DateTime(2025, 2, 15)),
        'status': 'booked',
        'invoiceId': 'inv-1', // fattura originale stornata
        if (companyIds.isNotEmpty) 'customerId': companyIds[0],
        'customerType': 'company',
        'currency': 'EUR', 'paid': true,
        'paidAt': Timestamp.fromDate(DateTime(2025, 2, 20)),
        'note': 'Storno parziale per servizio non erogato.',
        'lines': [
          {
            'description': 'Storno parziale – setup newsletter',
            'quantity': 1.0,
            'unitPrice': 500.0,
            'vatRate': 22.0,
          },
        ],
      },
      {
        'id': 'cn-fs-2',
        'creditNoteNumber': 'NC-2025-002',
        'creditNoteDate': Timestamp.fromDate(
          now.subtract(const Duration(days: 15)),
        ),
        'status': 'draft',
        if (companyIds.length > 3) 'customerId': companyIds[3],
        'customerType': 'company',
        'currency': 'EUR',
        'paid': false,
        'note': 'In attesa di approvazione contabilità.',
        'lines': [
          {
            'description': 'Rettifica importo acconto app mobile',
            'quantity': 1.0,
            'unitPrice': 1000.0,
            'vatRate': 22.0,
          },
        ],
      },
    ];
    for (final cn in cnSeed) {
      batch.set(_c(userId, 'creditNotes').doc(cn['id'] as String), {
        if (cn['creditNoteNumber'] != null)
          'creditNoteNumber': cn['creditNoteNumber'],
        if (cn['creditNoteDate'] != null)
          'creditNoteDate': cn['creditNoteDate'],
        'status': cn['status'],
        'currency': cn['currency'],
        'paid': cn['paid'],
        'note': cn['note'],
        if (cn['customerId'] != null) 'customerId': cn['customerId'],
        if (cn['customerType'] != null) 'customerType': cn['customerType'],
        if (cn['invoiceId'] != null) 'invoiceId': cn['invoiceId'],
        if (cn['paidAt'] != null) 'paidAt': cn['paidAt'],
        'lines': cn['lines'],
        'createdAt': Timestamp.fromDate(now.subtract(const Duration(days: 20))),
        'updatedAt': Timestamp.fromDate(now.subtract(const Duration(days: 10))),
      });
    }

    await batch.commit();
  }
}
