import 'api_client.dart';
import '../models/pos_models.dart';

class PosRepository {
  PosRepository({ApiClient? api}) : _api = api ?? ApiClient.instance;

  final ApiClient _api;

  Future<PosOverview> load() async {
    final raw = await _api.get('/pos/index.php');
    if (raw is! Map) {
      throw const ApiException('Risposta POS non valida.');
    }
    return PosOverview.fromMap(Map<String, dynamic>.from(raw));
  }

  Future<void> saveDevice({
    required String label,
    required String platform,
    required String provider,
    required List<String> capabilities,
    String status = 'ready',
  }) async {
    await _api.post('/pos/index.php', {
      'action': 'save_device',
      'label': label,
      'platform': platform,
      'provider': provider,
      'status': status,
      'capabilities': capabilities,
    });
  }

  Future<void> createIntent({
    required String title,
    required double amount,
    required String currency,
    String description = '',
    String provider = 'manual',
    String source = 'desktop',
    String? companyId,
    String? companyName,
    String? invoiceId,
    String? opportunityId,
    bool isDemo = true,
  }) async {
    await _api.post('/pos/index.php', {
      'action': 'create_intent',
      'title': title,
      'description': description,
      'amount': amount,
      'currency': currency,
      'provider': provider,
      'source': source,
      'companyId': companyId,
      'companyName': companyName,
      'invoiceId': invoiceId,
      'opportunityId': opportunityId,
      'isDemo': isDemo,
    });
  }

  Future<void> markDemoPaid(String intentId) async {
    await _api.post('/pos/index.php', {
      'action': 'mark_demo_paid',
      'intentId': intentId,
    });
  }

  Future<void> cancelIntent(String intentId) async {
    await _api.post('/pos/index.php', {
      'action': 'cancel_intent',
      'intentId': intentId,
    });
  }

  Future<PosMobilePaymentSession> prepareMobilePayment({
    required String paymentMode,
    required double amount,
    required String companyId,
    required String companyName,
    String? invoiceId,
    String? title,
    String description = '',
    String currency = 'EUR',
    bool autoInvoiceAfterPayment = true,
  }) async {
    final raw = await _api.post('/pos/mobile.php', {
      'action': 'prepare_mobile_payment',
      'paymentMode': paymentMode,
      'amount': amount,
      'companyId': companyId,
      'companyName': companyName,
      'invoiceId': invoiceId,
      'title': title,
      'description': description,
      'currency': currency,
      'autoInvoiceAfterPayment': autoInvoiceAfterPayment,
    });
    if (raw is! Map || raw['session'] is! Map) {
      throw const ApiException('Sessione Tap to Pay non valida.');
    }
    return PosMobilePaymentSession.fromMap(
      Map<String, dynamic>.from(raw['session'] as Map),
    );
  }

  Future<String> createConnectionToken() async {
    final raw = await _api.post('/pos/mobile.php', {
      'action': 'create_connection_token',
    });
    if (raw is! Map) {
      throw const ApiException('Token Stripe Terminal non valido.');
    }
    final secret = (raw['secret'] ?? '').toString().trim();
    if (secret.isEmpty) {
      throw const ApiException('Stripe non ha restituito il token terminale.');
    }
    return secret;
  }

  Future<PosMobilePaymentResult> completeMobilePayment(
    String localIntentId,
  ) async {
    final raw = await _api.post('/pos/mobile.php', {
      'action': 'complete_mobile_payment',
      'localIntentId': localIntentId,
    });
    if (raw is! Map) {
      throw const ApiException('Conferma pagamento POS non valida.');
    }
    return PosMobilePaymentResult.fromMap(Map<String, dynamic>.from(raw));
  }

  Future<void> markMobilePaymentFailed(
    String localIntentId, {
    String? reason,
  }) async {
    await _api.post('/pos/mobile.php', {
      'action': 'mark_mobile_payment_failed',
      'localIntentId': localIntentId,
      if (reason != null && reason.trim().isNotEmpty) 'reason': reason,
    });
  }
}
