import '../data/api_client.dart';

class StripeConnectSnapshot {
  const StripeConnectSnapshot({
    required this.configReady,
    required this.teamId,
    required this.teamName,
    required this.connected,
    required this.canAcceptPayments,
    required this.status,
    required this.setupEstimate,
    this.publishableKey,
    this.accountId,
    this.accountEmail,
    this.country = 'IT',
    this.currency = 'eur',
    this.detailsSubmitted = false,
    this.chargesEnabled = false,
    this.payoutsEnabled = false,
    this.currentlyDueCount = 0,
    this.eventuallyDueCount = 0,
    this.pastDueCount = 0,
    this.disabledReason,
  });

  final bool configReady;
  final String? publishableKey;
  final String teamId;
  final String teamName;
  final bool connected;
  final bool canAcceptPayments;
  final String status;
  final String? accountId;
  final String? accountEmail;
  final String country;
  final String currency;
  final bool detailsSubmitted;
  final bool chargesEnabled;
  final bool payoutsEnabled;
  final int currentlyDueCount;
  final int eventuallyDueCount;
  final int pastDueCount;
  final String? disabledReason;
  final String setupEstimate;

  bool get needsAttention =>
      status == 'pending_requirements' ||
      pastDueCount > 0 ||
      currentlyDueCount > 0;

  factory StripeConnectSnapshot.fromMap(Map<String, dynamic> map) {
    return StripeConnectSnapshot(
      configReady: map['configReady'] as bool? ?? false,
      publishableKey: map['publishableKey'] as String?,
      teamId: (map['teamId'] ?? '').toString(),
      teamName: (map['teamName'] ?? '').toString(),
      connected: map['connected'] as bool? ?? false,
      canAcceptPayments: map['canAcceptPayments'] as bool? ?? false,
      status: (map['status'] ?? 'not_connected').toString(),
      accountId: map['accountId'] as String?,
      accountEmail: map['accountEmail'] as String?,
      country: (map['country'] ?? 'IT').toString(),
      currency: (map['currency'] ?? 'eur').toString(),
      detailsSubmitted: map['detailsSubmitted'] as bool? ?? false,
      chargesEnabled: map['chargesEnabled'] as bool? ?? false,
      payoutsEnabled: map['payoutsEnabled'] as bool? ?? false,
      currentlyDueCount: (map['currentlyDueCount'] as num?)?.toInt() ?? 0,
      eventuallyDueCount: (map['eventuallyDueCount'] as num?)?.toInt() ?? 0,
      pastDueCount: (map['pastDueCount'] as num?)?.toInt() ?? 0,
      disabledReason: (map['requirements'] is Map)
          ? (Map<String, dynamic>.from(
                  map['requirements'] as Map,
                )['disabledReason']
                as String?)
          : null,
      setupEstimate: (map['setupEstimate'] ?? '5-10 minuti').toString(),
    );
  }
}

class StripeConnectService {
  StripeConnectService({ApiClient? api}) : _api = api ?? ApiClient.instance;

  final ApiClient _api;

  Future<StripeConnectSnapshot?> fetchStatus() async {
    final raw = await _api.get('/app/stripe_connect.php');
    final connection = raw is Map ? raw['connection'] : null;
    if (connection is Map) {
      return StripeConnectSnapshot.fromMap(
        Map<String, dynamic>.from(connection),
      );
    }
    return null;
  }

  Future<({String url, StripeConnectSnapshot? snapshot})> createOnboardingLink({
    required String originUrl,
  }) async {
    final raw = await _api.post('/app/stripe_connect.php', {
      'action': 'create_onboarding_link',
      'originUrl': originUrl,
    });
    final url = (raw is Map ? raw['url'] : null)?.toString() ?? '';
    final connection = raw is Map ? raw['connection'] : null;
    return (
      url: url,
      snapshot: connection is Map
          ? StripeConnectSnapshot.fromMap(Map<String, dynamic>.from(connection))
          : null,
    );
  }

  Future<({String url, StripeConnectSnapshot? snapshot})> createDashboardLink({
    required String originUrl,
  }) async {
    final raw = await _api.post('/app/stripe_connect.php', {
      'action': 'create_dashboard_link',
      'originUrl': originUrl,
    });
    final url = (raw is Map ? raw['url'] : null)?.toString() ?? '';
    final connection = raw is Map ? raw['connection'] : null;
    return (
      url: url,
      snapshot: connection is Map
          ? StripeConnectSnapshot.fromMap(Map<String, dynamic>.from(connection))
          : null,
    );
  }

  Future<StripeConnectSnapshot?> disconnect() async {
    final raw = await _api.delete('/app/stripe_connect.php');
    final connection = raw is Map ? raw['connection'] : null;
    if (connection is Map) {
      return StripeConnectSnapshot.fromMap(
        Map<String, dynamic>.from(connection),
      );
    }
    return null;
  }
}
