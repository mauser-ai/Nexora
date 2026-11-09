import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/pos_models.dart';

class TapToPayBridgeException implements Exception {
  const TapToPayBridgeException(this.message);

  final String message;

  @override
  String toString() => message;
}

class TapToPayBridgeAvailability {
  const TapToPayBridgeAvailability({
    required this.supported,
    required this.platform,
    this.reason,
  });

  final bool supported;
  final String platform;
  final String? reason;
}

class TapToPayBridgeService {
  static const _channel = MethodChannel('nexora/tap_to_pay');

  Future<TapToPayBridgeAvailability> checkAvailability() async {
    if (kIsWeb) {
      return const TapToPayBridgeAvailability(
        supported: false,
        platform: 'web',
        reason: 'Tap to Pay e disponibile solo nell’app mobile Nexora.',
      );
    }
    if (!Platform.isIOS && !Platform.isAndroid) {
      return TapToPayBridgeAvailability(
        supported: false,
        platform: defaultTargetPlatform.name,
        reason: 'Tap to Pay e disponibile solo su iPhone o Android.',
      );
    }
    try {
      final raw = await _channel.invokeMethod<dynamic>('checkAvailability');
      final map = raw is Map ? Map<String, dynamic>.from(raw) : const {};
      return TapToPayBridgeAvailability(
        supported: map['supported'] == true,
        platform: (map['platform'] ?? defaultTargetPlatform.name).toString(),
        reason: (map['reason'] ?? '').toString().trim().isEmpty
            ? null
            : (map['reason'] ?? '').toString(),
      );
    } on PlatformException catch (e) {
      return TapToPayBridgeAvailability(
        supported: false,
        platform: defaultTargetPlatform.name,
        reason: e.message ?? 'Bridge Tap to Pay non disponibile.',
      );
    }
  }

  Future<void> startPayment({
    required String connectionToken,
    required PosMobilePaymentSession session,
  }) async {
    try {
      await _channel.invokeMethod<void>('startPayment', {
        'connectionToken': connectionToken,
        'session': session.toMap(),
      });
    } on PlatformException catch (e) {
      throw TapToPayBridgeException(
        e.message ?? 'Pagamento Tap to Pay non completato.',
      );
    }
  }
}
