class PosDevice {
  const PosDevice({
    required this.id,
    required this.label,
    required this.platform,
    required this.provider,
    required this.status,
    required this.capabilities,
    this.lastSeenAt,
    this.updatedAt,
  });

  final String id;
  final String label;
  final String platform;
  final String provider;
  final String status;
  final List<String> capabilities;
  final DateTime? lastSeenAt;
  final DateTime? updatedAt;

  bool get isOnline => status == 'online';

  factory PosDevice.fromMap(Map<String, dynamic> map) {
    return PosDevice(
      id: (map['id'] ?? '').toString(),
      label: (map['label'] ?? '').toString(),
      platform: (map['platform'] ?? '').toString(),
      provider: (map['provider'] ?? 'manual').toString(),
      status: (map['status'] ?? 'offline').toString(),
      capabilities: ((map['capabilities'] as List?) ?? const [])
          .map((item) => item.toString())
          .where((item) => item.trim().isNotEmpty)
          .toList(),
      lastSeenAt: DateTime.tryParse((map['lastSeenAt'] ?? '').toString()),
      updatedAt: DateTime.tryParse((map['updatedAt'] ?? '').toString()),
    );
  }
}

class PosPaymentIntent {
  const PosPaymentIntent({
    required this.id,
    required this.title,
    required this.amount,
    required this.currency,
    required this.status,
    required this.provider,
    required this.source,
    this.description = '',
    this.companyId,
    this.companyName,
    this.invoiceId,
    this.opportunityId,
    this.createdByUserId,
    this.createdAt,
    this.completedAt,
    this.isDemo = false,
    this.paymentMode,
    this.invoiceNumberSnapshot,
    this.stripePaymentIntentId,
    this.stripeConnectedAccountId,
    this.generatedInvoiceId,
    this.paidAmount,
    this.paymentMethodLabel,
    this.failureReason,
    this.metadata = const {},
  });

  final String id;
  final String title;
  final String description;
  final double amount;
  final String currency;
  final String status;
  final String provider;
  final String source;
  final String? companyId;
  final String? companyName;
  final String? invoiceId;
  final String? opportunityId;
  final String? createdByUserId;
  final DateTime? createdAt;
  final DateTime? completedAt;
  final bool isDemo;
  final String? paymentMode;
  final String? invoiceNumberSnapshot;
  final String? stripePaymentIntentId;
  final String? stripeConnectedAccountId;
  final String? generatedInvoiceId;
  final double? paidAmount;
  final String? paymentMethodLabel;
  final String? failureReason;
  final Map<String, dynamic> metadata;

  bool get isCompleted => status == 'succeeded';
  bool get isDraft => status == 'draft';
  bool get isPending => status == 'pending';

  factory PosPaymentIntent.fromMap(Map<String, dynamic> map) {
    return PosPaymentIntent(
      id: (map['id'] ?? '').toString(),
      title: (map['title'] ?? 'Incasso').toString(),
      description: (map['description'] ?? '').toString(),
      amount: (map['amount'] as num?)?.toDouble() ?? 0,
      currency: (map['currency'] ?? 'EUR').toString(),
      status: (map['status'] ?? 'draft').toString(),
      provider: (map['provider'] ?? 'manual').toString(),
      source: (map['source'] ?? 'desktop').toString(),
      companyId: (map['companyId'] ?? '').toString().trim().isEmpty
          ? null
          : (map['companyId'] ?? '').toString(),
      companyName: (map['companyName'] ?? '').toString().trim().isEmpty
          ? null
          : (map['companyName'] ?? '').toString(),
      invoiceId: (map['invoiceId'] ?? '').toString().trim().isEmpty
          ? null
          : (map['invoiceId'] ?? '').toString(),
      opportunityId: (map['opportunityId'] ?? '').toString().trim().isEmpty
          ? null
          : (map['opportunityId'] ?? '').toString(),
      createdByUserId: (map['createdByUserId'] ?? '').toString().trim().isEmpty
          ? null
          : (map['createdByUserId'] ?? '').toString(),
      createdAt: DateTime.tryParse((map['createdAt'] ?? '').toString()),
      completedAt: DateTime.tryParse((map['completedAt'] ?? '').toString()),
      isDemo: map['isDemo'] == true || map['isDemo'] == 1,
      paymentMode: (map['paymentMode'] ?? '').toString().trim().isEmpty
          ? null
          : (map['paymentMode'] ?? '').toString(),
      invoiceNumberSnapshot:
          (map['invoiceNumberSnapshot'] ?? '').toString().trim().isEmpty
          ? null
          : (map['invoiceNumberSnapshot'] ?? '').toString(),
      stripePaymentIntentId:
          (map['stripePaymentIntentId'] ?? '').toString().trim().isEmpty
          ? null
          : (map['stripePaymentIntentId'] ?? '').toString(),
      stripeConnectedAccountId:
          (map['stripeConnectedAccountId'] ?? '').toString().trim().isEmpty
          ? null
          : (map['stripeConnectedAccountId'] ?? '').toString(),
      generatedInvoiceId:
          (map['generatedInvoiceId'] ?? '').toString().trim().isEmpty
          ? null
          : (map['generatedInvoiceId'] ?? '').toString(),
      paidAmount: (map['paidAmount'] as num?)?.toDouble(),
      paymentMethodLabel:
          (map['paymentMethodLabel'] ?? '').toString().trim().isEmpty
          ? null
          : (map['paymentMethodLabel'] ?? '').toString(),
      failureReason: (map['failureReason'] ?? '').toString().trim().isEmpty
          ? null
          : (map['failureReason'] ?? '').toString(),
      metadata: map['metadata'] is Map
          ? Map<String, dynamic>.from(map['metadata'] as Map)
          : const {},
    );
  }
}

class PosMobilePaymentSession {
  const PosMobilePaymentSession({
    required this.localIntentId,
    required this.stripePaymentIntentId,
    required this.clientSecret,
    required this.connectedAccountId,
    required this.amount,
    required this.currency,
    required this.companyId,
    required this.companyName,
    required this.paymentMode,
    required this.autoInvoiceAfterPayment,
    required this.title,
    required this.description,
    this.terminalLocationId,
    this.invoiceId,
    this.invoiceNumber,
  });

  final String localIntentId;
  final String stripePaymentIntentId;
  final String clientSecret;
  final String connectedAccountId;
  final String? terminalLocationId;
  final double amount;
  final String currency;
  final String companyId;
  final String companyName;
  final String? invoiceId;
  final String? invoiceNumber;
  final String paymentMode;
  final bool autoInvoiceAfterPayment;
  final String title;
  final String description;

  factory PosMobilePaymentSession.fromMap(Map<String, dynamic> map) {
    return PosMobilePaymentSession(
      localIntentId: (map['localIntentId'] ?? '').toString(),
      stripePaymentIntentId: (map['stripePaymentIntentId'] ?? '').toString(),
      clientSecret: (map['clientSecret'] ?? '').toString(),
      connectedAccountId: (map['connectedAccountId'] ?? '').toString(),
      terminalLocationId:
          (map['terminalLocationId'] ?? '').toString().trim().isEmpty
          ? null
          : (map['terminalLocationId'] ?? '').toString(),
      amount: (map['amount'] as num? ?? 0).toDouble(),
      currency: (map['currency'] ?? 'EUR').toString(),
      companyId: (map['companyId'] ?? '').toString(),
      companyName: (map['companyName'] ?? '').toString(),
      invoiceId: (map['invoiceId'] ?? '').toString().trim().isEmpty
          ? null
          : (map['invoiceId'] ?? '').toString(),
      invoiceNumber: (map['invoiceNumber'] ?? '').toString().trim().isEmpty
          ? null
          : (map['invoiceNumber'] ?? '').toString(),
      paymentMode: (map['paymentMode'] ?? 'spot').toString(),
      autoInvoiceAfterPayment:
          map['autoInvoiceAfterPayment'] == true ||
          map['autoInvoiceAfterPayment'] == 1,
      title: (map['title'] ?? '').toString(),
      description: (map['description'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toMap() => {
    'localIntentId': localIntentId,
    'stripePaymentIntentId': stripePaymentIntentId,
    'clientSecret': clientSecret,
    'connectedAccountId': connectedAccountId,
    'terminalLocationId': terminalLocationId,
    'amount': amount,
    'currency': currency,
    'companyId': companyId,
    'companyName': companyName,
    'invoiceId': invoiceId,
    'invoiceNumber': invoiceNumber,
    'paymentMode': paymentMode,
    'autoInvoiceAfterPayment': autoInvoiceAfterPayment,
    'title': title,
    'description': description,
  };
}

class PosMobilePaymentResult {
  const PosMobilePaymentResult({
    required this.localIntentId,
    required this.status,
    required this.paidAmount,
    this.generatedInvoiceId,
    this.invoiceId,
  });

  final String localIntentId;
  final String status;
  final double paidAmount;
  final String? generatedInvoiceId;
  final String? invoiceId;

  factory PosMobilePaymentResult.fromMap(Map<String, dynamic> map) {
    return PosMobilePaymentResult(
      localIntentId: (map['localIntentId'] ?? '').toString(),
      status: (map['status'] ?? '').toString(),
      paidAmount: (map['paidAmount'] as num? ?? 0).toDouble(),
      generatedInvoiceId:
          (map['generatedInvoiceId'] ?? '').toString().trim().isEmpty
          ? null
          : (map['generatedInvoiceId'] ?? '').toString(),
      invoiceId: (map['invoiceId'] ?? '').toString().trim().isEmpty
          ? null
          : (map['invoiceId'] ?? '').toString(),
    );
  }
}

class PosOverview {
  const PosOverview({
    required this.scopeId,
    required this.devices,
    required this.intents,
    required this.totalSucceededAmount,
    required this.todaySucceededAmount,
    required this.pendingCount,
    required this.succeededCount,
    required this.demoMode,
  });

  final String scopeId;
  final List<PosDevice> devices;
  final List<PosPaymentIntent> intents;
  final double totalSucceededAmount;
  final double todaySucceededAmount;
  final int pendingCount;
  final int succeededCount;
  final bool demoMode;

  List<PosPaymentIntent> get recentIntents => intents.take(20).toList();

  factory PosOverview.fromMap(Map<String, dynamic> map) {
    return PosOverview(
      scopeId: (map['scopeId'] ?? '').toString(),
      devices: ((map['devices'] as List?) ?? const [])
          .whereType<Map>()
          .map((item) => PosDevice.fromMap(Map<String, dynamic>.from(item)))
          .toList(),
      intents: ((map['intents'] as List?) ?? const [])
          .whereType<Map>()
          .map(
            (item) => PosPaymentIntent.fromMap(Map<String, dynamic>.from(item)),
          )
          .toList(),
      totalSucceededAmount:
          (map['totalSucceededAmount'] as num?)?.toDouble() ?? 0,
      todaySucceededAmount:
          (map['todaySucceededAmount'] as num?)?.toDouble() ?? 0,
      pendingCount: (map['pendingCount'] as num?)?.toInt() ?? 0,
      succeededCount: (map['succeededCount'] as num?)?.toInt() ?? 0,
      demoMode: map['demoMode'] == true || map['demoMode'] == 1,
    );
  }
}
