import '../../brand_config.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../models/domain_models.dart';

// ────────────────────────────────────────────────
// Helpers
// ────────────────────────────────────────────────

DateTime _date(dynamic v) {
  if (v is Timestamp) return v.toDate();
  if (v is DateTime) return v;
  return DateTime.now();
}

// ────────────────────────────────────────────────
// Expense
// ────────────────────────────────────────────────

enum ExpenseCategory {
  software,
  hardware,
  travel,
  marketing,
  office,
  consulting,
  other,
}

extension ExpenseCategoryX on ExpenseCategory {
  String get label {
    switch (this) {
      case ExpenseCategory.software: return 'Software';
      case ExpenseCategory.hardware: return 'Hardware';
      case ExpenseCategory.travel: return 'Trasferta';
      case ExpenseCategory.marketing: return 'Marketing';
      case ExpenseCategory.office: return 'Ufficio';
      case ExpenseCategory.consulting: return 'Consulenza';
      case ExpenseCategory.other: return 'Altro';
    }
  }
  Color get color {
    switch (this) {
      case ExpenseCategory.software: return const Color(0xFF0369A1);
      case ExpenseCategory.hardware: return const Color(0xFF7C3AED);
      case ExpenseCategory.travel: return const Color(0xFF0891B2);
      case ExpenseCategory.marketing: return const Color(0xFFD97706);
      case ExpenseCategory.office: return const Color(0xFFB8C0D8);
      case ExpenseCategory.consulting: return GussoniBrand.primary;
      case ExpenseCategory.other: return const Color(0xFF7D89A8);
    }
  }
}

ExpenseCategory parseExpenseCategory(String? raw) => ExpenseCategory.values
    .firstWhere((e) => e.name == raw, orElse: () => ExpenseCategory.other);

class Expense {
  const Expense({
    required this.id,
    required this.title,
    required this.amount,
    required this.category,
    required this.date,
    this.currency = 'EUR',
    this.notes = '',
    this.attachmentPath = '',
    this.companyId,
    this.createdAt,
  });

  final String id;
  final String title;
  final double amount;
  final ExpenseCategory category;
  final DateTime date;
  final String currency;
  final String notes;
  final String attachmentPath;
  final String? companyId;
  final DateTime? createdAt;

  factory Expense.fromMap(String id, Map<String, dynamic> m) => Expense(
    id: id,
    title: m['title'] as String? ?? '',
    amount: (m['amount'] as num? ?? 0).toDouble(),
    category: parseExpenseCategory(m['category'] as String?),
    date: _date(m['date']),
    currency: m['currency'] as String? ?? 'EUR',
    notes: m['notes'] as String? ?? '',
    attachmentPath: m['attachmentPath'] as String? ?? '',
    companyId: m['companyId'] as String?,
    createdAt: m['createdAt'] != null ? _date(m['createdAt']) : null,
  );

  Map<String, dynamic> toMap() => {
    'title': title,
    'amount': amount,
    'category': category.name,
    'date': Timestamp.fromDate(date),
    'currency': currency,
    'notes': notes,
    'attachmentPath': attachmentPath,
    if (companyId != null) 'companyId': companyId,
    'createdAt': createdAt != null ? Timestamp.fromDate(createdAt!) : FieldValue.serverTimestamp(),
  };

  Expense copyWith({String? title, double? amount, ExpenseCategory? category, DateTime? date, String? notes}) => Expense(
    id: id, title: title ?? this.title, amount: amount ?? this.amount,
    category: category ?? this.category, date: date ?? this.date,
    currency: currency, notes: notes ?? this.notes,
    attachmentPath: attachmentPath, companyId: companyId, createdAt: createdAt,
  );
}

// ────────────────────────────────────────────────
// Product
// ────────────────────────────────────────────────

class Product {
  const Product({
    required this.id,
    required this.name,
    required this.price,
    this.sku = '',
    this.description = '',
    this.currency = 'EUR',
    this.unit = 'pz',
    this.category = '',
    this.vatRate = 22.0,
    this.createdAt,
  });

  final String id;
  final String name;
  final String sku;
  final String description;
  final double price;
  final String currency;
  final String unit;
  final String category;
  final double vatRate;
  final DateTime? createdAt;

  double get priceWithVat => price * (1 + vatRate / 100);

  factory Product.fromMap(String id, Map<String, dynamic> m) => Product(
    id: id,
    name: m['name'] as String? ?? '',
    sku: m['sku'] as String? ?? '',
    description: m['description'] as String? ?? '',
    price: (m['price'] as num? ?? 0).toDouble(),
    currency: m['currency'] as String? ?? 'EUR',
    unit: m['unit'] as String? ?? 'pz',
    category: m['category'] as String? ?? '',
    vatRate: (m['vatRate'] as num? ?? 22).toDouble(),
    createdAt: m['createdAt'] != null ? _date(m['createdAt']) : null,
  );

  Map<String, dynamic> toMap() => {
    'name': name, 'sku': sku, 'description': description,
    'price': price, 'currency': currency, 'unit': unit,
    'category': category, 'vatRate': vatRate,
    'createdAt': createdAt != null ? Timestamp.fromDate(createdAt!) : FieldValue.serverTimestamp(),
  };

  Product copyWith({String? name, String? sku, double? price, String? description, String? unit, String? category, double? vatRate}) => Product(
    id: id, name: name ?? this.name, sku: sku ?? this.sku,
    description: description ?? this.description, price: price ?? this.price,
    currency: currency, unit: unit ?? this.unit,
    category: category ?? this.category, vatRate: vatRate ?? this.vatRate, createdAt: createdAt,
  );
}

// ────────────────────────────────────────────────
// WorkOrder (Ordine di lavoro)
// ────────────────────────────────────────────────

enum WorkOrderStatus { open, inProgress, done, cancelled }
enum WorkOrderPriority { low, medium, high, urgent }

extension WorkOrderStatusX on WorkOrderStatus {
  String get label {
    switch (this) {
      case WorkOrderStatus.open: return 'Aperto';
      case WorkOrderStatus.inProgress: return 'In corso';
      case WorkOrderStatus.done: return 'Completato';
      case WorkOrderStatus.cancelled: return 'Annullato';
    }
  }
  Color get color {
    switch (this) {
      case WorkOrderStatus.open: return const Color(0xFFB8C0D8);
      case WorkOrderStatus.inProgress: return const Color(0xFF0369A1);
      case WorkOrderStatus.done: return GussoniBrand.primary;
      case WorkOrderStatus.cancelled: return const Color(0xFF7D89A8);
    }
  }
}

extension WorkOrderPriorityX on WorkOrderPriority {
  String get label {
    switch (this) {
      case WorkOrderPriority.low: return 'Bassa';
      case WorkOrderPriority.medium: return 'Media';
      case WorkOrderPriority.high: return 'Alta';
      case WorkOrderPriority.urgent: return 'Urgente';
    }
  }
  Color get color {
    switch (this) {
      case WorkOrderPriority.low: return const Color(0xFF7D89A8);
      case WorkOrderPriority.medium: return const Color(0xFF0369A1);
      case WorkOrderPriority.high: return const Color(0xFFD97706);
      case WorkOrderPriority.urgent: return const Color(0xFFB91C1C);
    }
  }
}

WorkOrderStatus parseWorkOrderStatus(String? raw) => WorkOrderStatus.values
    .firstWhere((e) => e.name == raw, orElse: () => WorkOrderStatus.open);

WorkOrderPriority parseWorkOrderPriority(String? raw) => WorkOrderPriority.values
    .firstWhere((e) => e.name == raw, orElse: () => WorkOrderPriority.medium);

class WorkOrder {
  const WorkOrder({
    required this.id,
    required this.title,
    required this.status,
    required this.priority,
    this.companyId,
    this.assignedTo,
    this.description = '',
    this.dueDate,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String title;
  final WorkOrderStatus status;
  final WorkOrderPriority priority;
  final String? companyId;
  final String? assignedTo;
  final String description;
  final DateTime? dueDate;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  bool get isOverdue => dueDate != null && dueDate!.isBefore(DateTime.now()) && status != WorkOrderStatus.done;

  factory WorkOrder.fromMap(String id, Map<String, dynamic> m) => WorkOrder(
    id: id,
    title: m['title'] as String? ?? '',
    status: parseWorkOrderStatus(m['status'] as String?),
    priority: parseWorkOrderPriority(m['priority'] as String?),
    companyId: m['companyId'] as String?,
    assignedTo: m['assignedTo'] as String?,
    description: m['description'] as String? ?? '',
    dueDate: m['dueDate'] != null ? _date(m['dueDate']) : null,
    createdAt: m['createdAt'] != null ? _date(m['createdAt']) : null,
    updatedAt: m['updatedAt'] != null ? _date(m['updatedAt']) : null,
  );

  Map<String, dynamic> toMap() => {
    'title': title, 'status': status.name, 'priority': priority.name,
    if (companyId != null) 'companyId': companyId,
    if (assignedTo != null) 'assignedTo': assignedTo,
    'description': description,
    if (dueDate != null) 'dueDate': Timestamp.fromDate(dueDate!),
    'createdAt': createdAt != null ? Timestamp.fromDate(createdAt!) : FieldValue.serverTimestamp(),
    'updatedAt': FieldValue.serverTimestamp(),
  };

  WorkOrder copyWith({String? title, WorkOrderStatus? status, WorkOrderPriority? priority, String? description, DateTime? dueDate, String? assignedTo}) => WorkOrder(
    id: id, title: title ?? this.title, status: status ?? this.status,
    priority: priority ?? this.priority, companyId: companyId,
    assignedTo: assignedTo ?? this.assignedTo,
    description: description ?? this.description, dueDate: dueDate ?? this.dueDate,
    createdAt: createdAt, updatedAt: DateTime.now(),
  );
}

// ────────────────────────────────────────────────
// ContactForm (Form di contatto / Lead)
// ────────────────────────────────────────────────

enum ContactFormStatus { newLead, contacted, converted, closed }

extension ContactFormStatusX on ContactFormStatus {
  String get label {
    switch (this) {
      case ContactFormStatus.newLead: return 'Nuovo';
      case ContactFormStatus.contacted: return 'Contattato';
      case ContactFormStatus.converted: return 'Convertito';
      case ContactFormStatus.closed: return 'Chiuso';
    }
  }
  Color get color {
    switch (this) {
      case ContactFormStatus.newLead: return const Color(0xFF0369A1);
      case ContactFormStatus.contacted: return const Color(0xFFD97706);
      case ContactFormStatus.converted: return GussoniBrand.primary;
      case ContactFormStatus.closed: return const Color(0xFF7D89A8);
    }
  }
}

ContactFormStatus parseContactFormStatus(String? raw) => ContactFormStatus.values
    .firstWhere((e) => e.name == raw, orElse: () => ContactFormStatus.newLead);

class ContactForm {
  const ContactForm({
    required this.id,
    required this.name,
    required this.email,
    required this.status,
    this.phone = '',
    this.message = '',
    this.source = 'website',
    this.createdAt,
  });

  final String id;
  final String name;
  final String email;
  final String phone;
  final String message;
  final String source;
  final ContactFormStatus status;
  final DateTime? createdAt;

  factory ContactForm.fromMap(String id, Map<String, dynamic> m) => ContactForm(
    id: id,
    name: m['name'] as String? ?? '',
    email: m['email'] as String? ?? '',
    phone: m['phone'] as String? ?? '',
    message: m['message'] as String? ?? '',
    source: m['source'] as String? ?? 'website',
    status: parseContactFormStatus(m['status'] as String?),
    createdAt: m['createdAt'] != null ? _date(m['createdAt']) : null,
  );

  Map<String, dynamic> toMap() => {
    'name': name, 'email': email, 'phone': phone,
    'message': message, 'source': source, 'status': status.name,
    'createdAt': createdAt != null ? Timestamp.fromDate(createdAt!) : FieldValue.serverTimestamp(),
  };

  ContactForm copyWith({ContactFormStatus? status}) => ContactForm(
    id: id, name: name, email: email, phone: phone,
    message: message, source: source,
    status: status ?? this.status, createdAt: createdAt,
  );
}

// ────────────────────────────────────────────────
// CrmContact (Firestore version)
// ────────────────────────────────────────────────

class CrmFirestoreContact {
  const CrmFirestoreContact({
    required this.id,
    required this.firstName,
    required this.lastName,
    this.companyId,
    this.email = '',
    this.phone = '',
    this.role = '',
    this.tags = const [],
    this.assignedTo,
    this.notes = '',
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String firstName;
  final String lastName;
  final String? companyId;
  final String email;
  final String phone;
  final String role;
  final List<String> tags;
  final String? assignedTo;
  final String notes;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  String get fullName => '$firstName $lastName';
  String get initials {
    final f = firstName.isNotEmpty ? firstName[0].toUpperCase() : '';
    final l = lastName.isNotEmpty ? lastName[0].toUpperCase() : '';
    return '$f$l';
  }

  factory CrmFirestoreContact.fromMap(String id, Map<String, dynamic> m) => CrmFirestoreContact(
    id: id,
    firstName: m['firstName'] as String? ?? '',
    lastName: m['lastName'] as String? ?? '',
    companyId: m['companyId'] as String?,
    email: m['email'] as String? ?? '',
    phone: m['phone'] as String? ?? '',
    role: m['role'] as String? ?? '',
    tags: (m['tags'] as List<dynamic>?)?.cast<String>() ?? [],
    assignedTo: m['assignedTo'] as String?,
    notes: m['notes'] as String? ?? '',
    createdAt: m['createdAt'] != null ? _date(m['createdAt']) : null,
    updatedAt: m['updatedAt'] != null ? _date(m['updatedAt']) : null,
  );

  Map<String, dynamic> toMap() => {
    'firstName': firstName, 'lastName': lastName,
    if (companyId != null) 'companyId': companyId,
    'email': email, 'phone': phone, 'role': role,
    'tags': tags,
    if (assignedTo != null) 'assignedTo': assignedTo,
    'notes': notes,
    'createdAt': createdAt != null ? Timestamp.fromDate(createdAt!) : FieldValue.serverTimestamp(),
    'updatedAt': FieldValue.serverTimestamp(),
  };

  CrmFirestoreContact copyWith({String? firstName, String? lastName, String? email, String? phone, String? role, String? companyId, String? notes}) => CrmFirestoreContact(
    id: id, firstName: firstName ?? this.firstName, lastName: lastName ?? this.lastName,
    companyId: companyId ?? this.companyId, email: email ?? this.email,
    phone: phone ?? this.phone, role: role ?? this.role, tags: tags,
    assignedTo: assignedTo, notes: notes ?? this.notes,
    createdAt: createdAt, updatedAt: DateTime.now(),
  );
}

// ────────────────────────────────────────────────
// Deal (Firestore version – Opportunità)
// ────────────────────────────────────────────────

enum DealFirestoreStatus { open, won, lost }

extension DealFirestoreStatusX on DealFirestoreStatus {
  String get label { switch(this) { case DealFirestoreStatus.open: return 'Aperto'; case DealFirestoreStatus.won: return 'Vinto'; case DealFirestoreStatus.lost: return 'Perso'; } }
  Color get color { switch(this) { case DealFirestoreStatus.open: return const Color(0xFF0369A1); case DealFirestoreStatus.won: return GussoniBrand.primary; case DealFirestoreStatus.lost: return const Color(0xFFB91C1C); } }
}

DealFirestoreStatus parseDealStatus(String? raw) => DealFirestoreStatus.values
    .firstWhere((e) => e.name == raw, orElse: () => DealFirestoreStatus.open);

class DealStage {
  const DealStage({required this.id, required this.name, required this.order, required this.colorHex, this.probability = 0});

  final String id;
  final String name;
  final int order;
  final String colorHex;
  final int probability;

  Color get color => Color(int.parse('FF${colorHex.replaceAll('#', '')}', radix: 16));

  factory DealStage.fromMap(String id, Map<String, dynamic> m) => DealStage(
    id: id,
    name: m['name'] as String? ?? '',
    order: m['order'] as int? ?? 0,
    colorHex: m['colorHex'] as String? ?? '#6B7280',
    probability: m['probability'] as int? ?? 0,
  );

  Map<String, dynamic> toMap() => {
    'name': name, 'order': order, 'colorHex': colorHex, 'probability': probability,
  };
}

class Deal {
  const Deal({
    required this.id,
    required this.title,
    required this.stageId,
    required this.status,
    required this.value,
    this.currency = 'EUR',
    this.customerId,
    this.customerType,
    this.probability = 0,
    this.expectedClosingDate,
    this.assignedTo,
    this.notes = '',
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String title;
  final String stageId;
  final DealFirestoreStatus status;
  final double value;
  final String currency;
  final String? customerId;
  final String? customerType;
  final int probability;
  final DateTime? expectedClosingDate;
  final String? assignedTo;
  final String notes;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  bool get isOverdue => expectedClosingDate != null && expectedClosingDate!.isBefore(DateTime.now()) && status == DealFirestoreStatus.open;

  factory Deal.fromMap(String id, Map<String, dynamic> m) => Deal(
    id: id,
    title: m['title'] as String? ?? '',
    stageId: m['stageId'] as String? ?? '',
    status: parseDealStatus(m['status'] as String?),
    value: (m['value'] as num? ?? 0).toDouble(),
    currency: m['currency'] as String? ?? 'EUR',
    customerId: m['customerId'] as String?,
    customerType: m['customerType'] as String?,
    probability: m['probability'] as int? ?? 0,
    expectedClosingDate: m['expectedClosingDate'] != null ? _date(m['expectedClosingDate']) : null,
    assignedTo: m['assignedTo'] as String?,
    notes: m['notes'] as String? ?? '',
    createdAt: m['createdAt'] != null ? _date(m['createdAt']) : null,
    updatedAt: m['updatedAt'] != null ? _date(m['updatedAt']) : null,
  );

  Map<String, dynamic> toMap() => {
    'title': title, 'stageId': stageId, 'status': status.name,
    'value': value, 'currency': currency,
    if (customerId != null) 'customerId': customerId,
    if (customerType != null) 'customerType': customerType,
    'probability': probability,
    if (expectedClosingDate != null) 'expectedClosingDate': Timestamp.fromDate(expectedClosingDate!),
    if (assignedTo != null) 'assignedTo': assignedTo,
    'notes': notes,
    'createdAt': createdAt != null ? Timestamp.fromDate(createdAt!) : FieldValue.serverTimestamp(),
    'updatedAt': FieldValue.serverTimestamp(),
  };

  Deal copyWith({String? title, String? stageId, DealFirestoreStatus? status, double? value, int? probability, String? assignedTo, String? notes, DateTime? expectedClosingDate}) => Deal(
    id: id, title: title ?? this.title, stageId: stageId ?? this.stageId,
    status: status ?? this.status, value: value ?? this.value, currency: currency,
    customerId: customerId, customerType: customerType,
    probability: probability ?? this.probability,
    expectedClosingDate: expectedClosingDate ?? this.expectedClosingDate,
    assignedTo: assignedTo ?? this.assignedTo, notes: notes ?? this.notes,
    createdAt: createdAt, updatedAt: DateTime.now(),
  );
}

// ────────────────────────────────────────────────
// Quotation (Preventivo - Firestore)
// ────────────────────────────────────────────────

enum QuotationStatus { draft, sent, accepted, rejected }

extension QuotationStatusX on QuotationStatus {
  String get label { switch(this) { case QuotationStatus.draft: return 'Bozza'; case QuotationStatus.sent: return 'Inviato'; case QuotationStatus.accepted: return 'Accettato'; case QuotationStatus.rejected: return 'Rifiutato'; } }
  Color get color { switch(this) { case QuotationStatus.draft: return const Color(0xFF7D89A8); case QuotationStatus.sent: return const Color(0xFF0369A1); case QuotationStatus.accepted: return GussoniBrand.primary; case QuotationStatus.rejected: return const Color(0xFFB91C1C); } }
}

QuotationStatus parseQuotationStatus(String? raw) => QuotationStatus.values
    .firstWhere((e) => e.name == raw, orElse: () => QuotationStatus.draft);

class QuotationLine {
  const QuotationLine({
    required this.description,
    required this.quantity,
    required this.unitPrice,
    this.vatRate = 22.0,
    this.productId,   // → link a Product dal catalogo
  });

  final String description;
  final double quantity;
  final double unitPrice;
  final double vatRate;
  final String? productId;

  double get net => quantity * unitPrice;
  double get vat => net * (vatRate / 100);
  double get total => net + vat;

  factory QuotationLine.fromMap(Map<String, dynamic> m) => QuotationLine(
    description: m['description'] as String? ?? '',
    quantity: (m['quantity'] as num? ?? 1).toDouble(),
    unitPrice: (m['unitPrice'] as num? ?? 0).toDouble(),
    vatRate: (m['vatRate'] as num? ?? 22).toDouble(),
    productId: m['productId'] as String?,
  );

  Map<String, dynamic> toMap() => {
    'description': description, 'quantity': quantity,
    'unitPrice': unitPrice, 'vatRate': vatRate,
    if (productId != null) 'productId': productId,
  };
}

class Quotation {
  const Quotation({
    required this.id,
    required this.number,
    required this.status,
    required this.lines,
    this.customerId,
    this.customerType,
    this.dealId,      // → link a Deal (Opportunità sorgente)
    this.currency = 'EUR',
    this.validUntil,
    this.notes = '',
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String number;
  final QuotationStatus status;
  final List<QuotationLine> lines;
  final String? customerId;
  final String? customerType;
  final String? dealId;     // Teamleader: quotation.deal.id
  final String currency;
  final DateTime? validUntil;
  final String notes;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  double get subtotal => lines.fold(0, (s, l) => s + l.net);
  double get vatTotal => lines.fold(0, (s, l) => s + l.vat);
  double get total => lines.fold(0, (s, l) => s + l.total);

  factory Quotation.fromMap(String id, Map<String, dynamic> m) => Quotation(
    id: id,
    number: m['number'] as String? ?? '',
    status: parseQuotationStatus(m['status'] as String?),
    lines: (m['lines'] as List<dynamic>? ?? []).whereType<Map>().map((l) => QuotationLine.fromMap(Map<String, dynamic>.from(l))).toList(),
    customerId: m['customerId'] as String?,
    customerType: m['customerType'] as String?,
    dealId: m['dealId'] as String?,
    currency: m['currency'] as String? ?? 'EUR',
    validUntil: m['validUntil'] != null ? _date(m['validUntil']) : null,
    notes: m['notes'] as String? ?? '',
    createdAt: m['createdAt'] != null ? _date(m['createdAt']) : null,
    updatedAt: m['updatedAt'] != null ? _date(m['updatedAt']) : null,
  );

  Map<String, dynamic> toMap() => {
    'number': number, 'status': status.name,
    'lines': lines.map((l) => l.toMap()).toList(),
    if (customerId != null) 'customerId': customerId,
    if (customerType != null) 'customerType': customerType,
    if (dealId != null) 'dealId': dealId,
    'currency': currency,
    if (validUntil != null) 'validUntil': Timestamp.fromDate(validUntil!),
    'notes': notes,
    'createdAt': createdAt != null ? Timestamp.fromDate(createdAt!) : FieldValue.serverTimestamp(),
    'updatedAt': FieldValue.serverTimestamp(),
  };

  Quotation copyWith({QuotationStatus? status, List<QuotationLine>? lines, String? notes, String? dealId}) => Quotation(
    id: id, number: number, status: status ?? this.status,
    lines: lines ?? this.lines, customerId: customerId, customerType: customerType,
    dealId: dealId ?? this.dealId,
    currency: currency, validUntil: validUntil, notes: notes ?? this.notes,
    createdAt: createdAt, updatedAt: DateTime.now(),
  );
}

// ────────────────────────────────────────────────
// CrmData – aggregate of all real CRM collections
// ────────────────────────────────────────────────

class CrmData {
  const CrmData({
    required this.contacts,
    required this.deals,
    required this.dealStages,
    required this.quotations,
    required this.expenses,
    required this.products,
    required this.workOrders,
    required this.contactForms,
    this.subscriptions = const [],
    this.creditNotes = const [],
  });

  final List<CrmFirestoreContact> contacts;
  final List<Deal> deals;
  final List<DealStage> dealStages;
  final List<Quotation> quotations;
  final List<Expense> expenses;
  final List<Product> products;
  final List<WorkOrder> workOrders;
  final List<ContactForm> contactForms;
  final List<Subscription> subscriptions;   // Abbonamenti
  final List<CreditNote> creditNotes;       // Note di credito

  static const empty = CrmData(
    contacts: [], deals: [], dealStages: [], quotations: [],
    expenses: [], products: [], workOrders: [], contactForms: [],
    subscriptions: [], creditNotes: [],
  );

  // ── Relationship helpers (mirrors Teamleader's sideloading) ──

  List<Deal> dealsInStage(String stageId) =>
      deals.where((d) => d.stageId == stageId && d.status == DealFirestoreStatus.open).toList();

  /// Tutti i preventivi collegati a un deal (deal.quotations[] in TL)
  List<Quotation> quotationsForDeal(String dealId) =>
      quotations.where((q) => q.dealId == dealId).toList();

  /// Tutti i contatti collegati a un'azienda (company.related_contacts in TL)
  List<CrmFirestoreContact> contactsForCompany(String companyId) =>
      contacts.where((c) => c.companyId == companyId).toList();

  /// Tutti i deal legati a un cliente (company o contact)
  List<Deal> dealsForCustomer(String customerId) =>
      deals.where((d) => d.customerId == customerId).toList();

  /// Tutti i preventivi collegati a un cliente
  List<Quotation> quotationsForCustomer(String customerId) =>
      quotations.where((q) => q.customerId == customerId).toList();

  /// Tutti gli ordini di lavoro per un'azienda
  List<WorkOrder> workOrdersForCompany(String companyId) =>
      workOrders.where((w) => w.companyId == companyId).toList();

  /// Abbonamenti attivi
  List<Subscription> get activeSubscriptions =>
      subscriptions.where((s) => s.status == SubscriptionStatus.active).toList();

  /// Note di credito legate a una fattura originale
  List<CreditNote> creditNotesForInvoice(String invoiceId) =>
      creditNotes.where((cn) => cn.invoiceId == invoiceId).toList();

  /// Abbonamenti per cliente
  List<Subscription> subscriptionsForCustomer(String customerId) =>
      subscriptions.where((s) => s.customerId == customerId).toList();

  List<DealStage> get sortedStages => [...dealStages]..sort((a, b) => a.order.compareTo(b.order));

  double get totalOpenPipeline => deals.where((d) => d.status == DealFirestoreStatus.open).fold(0, (s, d) => s + d.value);
  int get openDealsCount => deals.where((d) => d.status == DealFirestoreStatus.open).length;
  double get totalExpenses => expenses.fold(0, (s, e) => s + e.amount);
  int get newLeadsCount => contactForms.where((f) => f.status == ContactFormStatus.newLead).length;

  // ── By-ID lookups ──
  DealStage? stageById(String? id) => id == null ? null : dealStages.where((s) => s.id == id).firstOrNull;
  CrmFirestoreContact? contactById(String? id) => id == null ? null : contacts.where((c) => c.id == id).firstOrNull;
  Deal? dealById(String? id) => id == null ? null : deals.where((d) => d.id == id).firstOrNull;
  Product? productById(String? id) => id == null ? null : products.where((p) => p.id == id).firstOrNull;
  Company? companyFromList(List<Company> companies, String? id) => id == null ? null : companies.where((c) => c.id == id).firstOrNull;

  /// Risolve il nome del cliente (company o contact) dato tipo e id
  String customerName(List<Company> companies, String? customerId, String? customerType) {
    if (customerId == null) return '—';
    if (customerType == 'contact') return contactById(customerId)?.fullName ?? '—';
    return companyFromList(companies, customerId)?.name ?? '—';
  }

  CrmData copyWith({
    List<CrmFirestoreContact>? contacts,
    List<Deal>? deals,
    List<DealStage>? dealStages,
    List<Quotation>? quotations,
    List<Expense>? expenses,
    List<Product>? products,
    List<WorkOrder>? workOrders,
    List<ContactForm>? contactForms,
  }) => CrmData(
    contacts: contacts ?? this.contacts,
    deals: deals ?? this.deals,
    dealStages: dealStages ?? this.dealStages,
    quotations: quotations ?? this.quotations,
    expenses: expenses ?? this.expenses,
    products: products ?? this.products,
    workOrders: workOrders ?? this.workOrders,
    contactForms: contactForms ?? this.contactForms,
    subscriptions: subscriptions ?? this.subscriptions,
    creditNotes: creditNotes ?? this.creditNotes,
  );
}

// ────────────────────────────────────────────────
// Subscription (Abbonamento)
// Teamleader: status active|deactivated, billing_cycle, invoicee.customer
// ────────────────────────────────────────────────

enum SubscriptionStatus { active, deactivated }

extension SubscriptionStatusX on SubscriptionStatus {
  String get label => this == SubscriptionStatus.active ? 'Attivo' : 'Disattivato';
  Color get color => this == SubscriptionStatus.active ? GussoniBrand.primary : const Color(0xFF7D89A8);
}

SubscriptionStatus parseSubscriptionStatus(String? raw) => SubscriptionStatus.values
    .firstWhere((e) => e.name == raw, orElse: () => SubscriptionStatus.active);

class BillingCycle {
  const BillingCycle({required this.unit, required this.period, this.daysInAdvance = 0});
  final String unit;   // week | month | year
  final int period;    // ogni N unità
  final int daysInAdvance; // giorni prima per generare la fattura

  String get label {
    final unitLabel = switch(unit) { 'week' => period == 1 ? 'settimana' : 'settimane', 'month' => period == 1 ? 'mese' : 'mesi', _ => period == 1 ? 'anno' : 'anni' };
    return 'Ogni $period $unitLabel';
  }

  factory BillingCycle.fromMap(Map<String, dynamic> m) => BillingCycle(
    unit: m['unit'] as String? ?? 'month',
    period: m['period'] as int? ?? 1,
    daysInAdvance: m['daysInAdvance'] as int? ?? 0,
  );

  Map<String, dynamic> toMap() => {'unit': unit, 'period': period, 'daysInAdvance': daysInAdvance};
}

class Subscription {
  const Subscription({
    required this.id,
    required this.title,
    required this.status,
    required this.billingCycle,
    required this.lines,
    this.note = '',
    this.customerId,
    this.customerType,
    this.currency = 'EUR',
    this.startsOn,
    this.endsOn,
    this.nextRenewalDate,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String title;
  final String note;
  final SubscriptionStatus status;
  final BillingCycle billingCycle;
  final List<QuotationLine> lines;
  final String? customerId;
  final String? customerType;
  final String currency;
  final DateTime? startsOn;
  final DateTime? endsOn;
  final DateTime? nextRenewalDate;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  double get total => lines.fold(0, (s, l) => s + l.total);

  factory Subscription.fromMap(String id, Map<String, dynamic> m) => Subscription(
    id: id,
    title: m['title'] as String? ?? '',
    note: m['note'] as String? ?? '',
    status: parseSubscriptionStatus(m['status'] as String?),
    billingCycle: BillingCycle.fromMap(m['billingCycle'] as Map<String, dynamic>? ?? {}),
    lines: (m['lines'] as List<dynamic>? ?? []).whereType<Map>().map((l) => QuotationLine.fromMap(Map<String, dynamic>.from(l))).toList(),
    customerId: m['customerId'] as String?,
    customerType: m['customerType'] as String?,
    currency: m['currency'] as String? ?? 'EUR',
    startsOn: m['startsOn'] != null ? _date(m['startsOn']) : null,
    endsOn: m['endsOn'] != null ? _date(m['endsOn']) : null,
    nextRenewalDate: m['nextRenewalDate'] != null ? _date(m['nextRenewalDate']) : null,
    createdAt: m['createdAt'] != null ? _date(m['createdAt']) : null,
    updatedAt: m['updatedAt'] != null ? _date(m['updatedAt']) : null,
  );

  Map<String, dynamic> toMap() => {
    'title': title, 'note': note, 'status': status.name,
    'billingCycle': billingCycle.toMap(),
    'lines': lines.map((l) => l.toMap()).toList(),
    if (customerId != null) 'customerId': customerId,
    if (customerType != null) 'customerType': customerType,
    'currency': currency,
    if (startsOn != null) 'startsOn': Timestamp.fromDate(startsOn!),
    if (endsOn != null) 'endsOn': Timestamp.fromDate(endsOn!),
    if (nextRenewalDate != null) 'nextRenewalDate': Timestamp.fromDate(nextRenewalDate!),
    'createdAt': createdAt != null ? Timestamp.fromDate(createdAt!) : FieldValue.serverTimestamp(),
    'updatedAt': FieldValue.serverTimestamp(),
  };

  Subscription copyWith({SubscriptionStatus? status, String? title, String? note}) => Subscription(
    id: id, title: title ?? this.title, note: note ?? this.note,
    status: status ?? this.status, billingCycle: billingCycle, lines: lines,
    customerId: customerId, customerType: customerType, currency: currency,
    startsOn: startsOn, endsOn: endsOn, nextRenewalDate: nextRenewalDate,
    createdAt: createdAt, updatedAt: DateTime.now(),
  );
}

// ────────────────────────────────────────────────
// CreditNote (Nota di credito)
// Teamleader: credit_note_number, status booked, invoice (original ref)
// ────────────────────────────────────────────────

enum CreditNoteStatus { draft, booked }

extension CreditNoteStatusX on CreditNoteStatus {
  String get label => this == CreditNoteStatus.draft ? 'Bozza' : 'Registrata';
  Color get color => this == CreditNoteStatus.draft ? const Color(0xFF7D89A8) : const Color(0xFF7C3AED);
}

CreditNoteStatus parseCreditNoteStatus(String? raw) => CreditNoteStatus.values
    .firstWhere((e) => e.name == raw, orElse: () => CreditNoteStatus.draft);

class CreditNote {
  const CreditNote({
    required this.id,
    required this.status,
    required this.lines,
    this.creditNoteNumber,
    this.creditNoteDate,
    this.customerId,
    this.customerType,
    this.invoiceId,     // Teamleader: original invoice reference
    this.currency = 'EUR',
    this.paid = false,
    this.paidAt,
    this.note = '',
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String? creditNoteNumber;
  final DateTime? creditNoteDate;
  final CreditNoteStatus status;
  final List<QuotationLine> lines;
  final String? customerId;
  final String? customerType;
  final String? invoiceId;  // fattura originale stornata
  final String currency;
  final bool paid;
  final DateTime? paidAt;
  final String note;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  double get subtotal => lines.fold(0, (s, l) => s + l.net);
  double get vatTotal => lines.fold(0, (s, l) => s + l.vat);
  double get total => lines.fold(0, (s, l) => s + l.total);

  factory CreditNote.fromMap(String id, Map<String, dynamic> m) => CreditNote(
    id: id,
    creditNoteNumber: m['creditNoteNumber'] as String?,
    creditNoteDate: m['creditNoteDate'] != null ? _date(m['creditNoteDate']) : null,
    status: parseCreditNoteStatus(m['status'] as String?),
    lines: (m['lines'] as List<dynamic>? ?? []).whereType<Map>().map((l) => QuotationLine.fromMap(Map<String, dynamic>.from(l))).toList(),
    customerId: m['customerId'] as String?,
    customerType: m['customerType'] as String?,
    invoiceId: m['invoiceId'] as String?,
    currency: m['currency'] as String? ?? 'EUR',
    paid: m['paid'] as bool? ?? false,
    paidAt: m['paidAt'] != null ? _date(m['paidAt']) : null,
    note: m['note'] as String? ?? '',
    createdAt: m['createdAt'] != null ? _date(m['createdAt']) : null,
    updatedAt: m['updatedAt'] != null ? _date(m['updatedAt']) : null,
  );

  Map<String, dynamic> toMap() => {
    if (creditNoteNumber != null) 'creditNoteNumber': creditNoteNumber,
    if (creditNoteDate != null) 'creditNoteDate': Timestamp.fromDate(creditNoteDate!),
    'status': status.name,
    'lines': lines.map((l) => l.toMap()).toList(),
    if (customerId != null) 'customerId': customerId,
    if (customerType != null) 'customerType': customerType,
    if (invoiceId != null) 'invoiceId': invoiceId,
    'currency': currency, 'paid': paid,
    if (paidAt != null) 'paidAt': Timestamp.fromDate(paidAt!),
    'note': note,
    'createdAt': createdAt != null ? Timestamp.fromDate(createdAt!) : FieldValue.serverTimestamp(),
    'updatedAt': FieldValue.serverTimestamp(),
  };

  CreditNote copyWith({CreditNoteStatus? status, bool? paid, DateTime? paidAt}) => CreditNote(
    id: id, creditNoteNumber: creditNoteNumber, creditNoteDate: creditNoteDate,
    status: status ?? this.status, lines: lines,
    customerId: customerId, customerType: customerType, invoiceId: invoiceId,
    currency: currency, paid: paid ?? this.paid, paidAt: paidAt ?? this.paidAt,
    note: note, createdAt: createdAt, updatedAt: DateTime.now(),
  );
}
