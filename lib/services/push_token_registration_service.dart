import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../data/api_workspace_repository.dart';
import 'web_push_browser_helper_factory.dart';

class PushTokenRegistrationService {
  PushTokenRegistrationService({FirebaseMessaging? messaging})
    : _messaging = messaging ?? FirebaseMessaging.instance;

  static const _webVapidKey =
      'BA4oG21J64KX8lZfigH-VW00wzn53WncHsdImtjqFE0IEGkUnoLWAL2yuVjMU7sDxFgFRXTh1ukq8OHVnu-gE1I';

  final FirebaseMessaging _messaging;
  StreamSubscription<String>? _refreshSub;
  StreamSubscription<RemoteMessage>? _messageSub;
  final _browserPushHelper = createBrowserPushHelper();

  Future<void> start({
    required String userId,
    required ApiWorkspaceRepository repository,
  }) async {
    try {
      if (kIsWeb) {
        await _browserPushHelper.waitUntilReady();
      }

      final settings = await _messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );

      if (settings.authorizationStatus == AuthorizationStatus.denied) {
        return;
      }

      await _messaging.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );

      final token = await _messaging.getToken(
        vapidKey: kIsWeb ? _webVapidKey : null,
      );
      if (token != null && token.trim().isNotEmpty) {
        await _storeToken(userId, token);
      } else {
        debugPrint('[PushTokenRegistrationService] token FCM non disponibile');
      }

      await _refreshSub?.cancel();
      _refreshSub = _messaging.onTokenRefresh.listen((nextToken) async {
        if (nextToken.trim().isEmpty) {
          return;
        }
        await _storeToken(userId, nextToken);
      });

      await _messageSub?.cancel();
      _messageSub = FirebaseMessaging.onMessage.listen((message) async {
        final notification = message.notification;
        if (notification == null) {
          return;
        }
        await _browserPushHelper.showNotification(
          title: notification.title?.trim().isNotEmpty == true
              ? notification.title!.trim()
              : 'Nexora',
          body: notification.body?.trim().isNotEmpty == true
              ? notification.body!.trim()
              : 'Hai una nuova notifica.',
        );
      });
    } on MissingPluginException {
      // Messaging plugin non disponibile su questo runtime/build.
      return;
    } catch (error, stackTrace) {
      debugPrint(
        '[PushTokenRegistrationService] start error: $error\n$stackTrace',
      );
      return;
    }
  }

  Future<void> stop() async {
    await _refreshSub?.cancel();
    await _messageSub?.cancel();
    _refreshSub = null;
    _messageSub = null;
  }

  Future<void> _storeToken(String userId, String token) {
    return FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .collection('pushTokens')
        .doc(token)
        .set({
          'token': token,
          'platform': _platformName(),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
  }

  String _platformName() {
    if (kIsWeb) {
      return 'web';
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS:
        return 'ios';
      case TargetPlatform.android:
        return 'android';
      case TargetPlatform.macOS:
        return 'macos';
      case TargetPlatform.windows:
        return 'windows';
      case TargetPlatform.linux:
        return 'linux';
      case TargetPlatform.fuchsia:
        return 'fuchsia';
    }
  }
}
