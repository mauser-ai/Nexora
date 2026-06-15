import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_native_timezone_latest/flutter_native_timezone_latest.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

class PlanningAlertItem {
  const PlanningAlertItem({
    required this.slotId,
    required this.taskName,
    required this.companyName,
    required this.startAt,
    required this.endAt,
  });

  final String slotId;
  final String taskName;
  final String companyName;
  final DateTime startAt;
  final DateTime endAt;
}

class DailyBriefNotificationService {
  DailyBriefNotificationService._();

  static final DailyBriefNotificationService instance =
      DailyBriefNotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  final StreamController<String> _payloadController =
      StreamController<String>.broadcast();

  Stream<String> get payloadStream => _payloadController.stream;

  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }

    tz.initializeTimeZones();
    try {
      final localTimeZone =
          await FlutterNativeTimezoneLatest.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(localTimeZone));
    } catch (_) {
      // Fallback su UTC se timezone locale non disponibile.
      tz.setLocalLocation(tz.UTC);
    }

    const ios = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    const initSettings = InitializationSettings(iOS: ios);

    await _plugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (response) {
        final payload = response.payload;
        if (payload != null && payload.isNotEmpty) {
          _payloadController.add(payload);
        }
      },
    );

    await _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >()
        ?.requestPermissions(alert: true, badge: true, sound: true);

    _initialized = true;
  }

  Future<void> scheduleDailyBrief({
    required String title,
    required String body,
  }) async {
    await initialize();

    const details = NotificationDetails(
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      ),
    );

    final now = tz.TZDateTime.now(tz.local);
    var next = tz.TZDateTime(tz.local, now.year, now.month, now.day, 8, 0);
    if (!next.isAfter(now)) {
      next = next.add(const Duration(days: 1));
    }

    await _plugin.zonedSchedule(
      8080,
      title,
      body,
      next,
      details,
      payload: 'today_brief',
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }

  Future<void> cancelDailyBrief() => _plugin.cancel(8080);

  Future<void> schedulePlanningAlerts(List<PlanningAlertItem> items) async {
    await initialize();
    await _cancelPlanningAlerts();

    const details = NotificationDetails(
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      ),
    );

    final now = DateTime.now();
    for (final item in items) {
      final start = item.startAt;
      if (!start.isAfter(now)) {
        continue;
      }
      var alertAt = start.subtract(const Duration(minutes: 30));
      if (!alertAt.isAfter(now)) {
        alertAt = now.add(const Duration(seconds: 5));
      }

      final title = item.taskName.trim().isEmpty
          ? 'Attivita in arrivo'
          : item.taskName.trim();
      final schedule =
          '${_hhmm(item.startAt)} - ${_hhmm(item.endAt)}'
          '${item.companyName.trim().isEmpty ? '' : ' • ${item.companyName.trim()}'}';
      final id = _planningAlertId(item.slotId);
      final payload = 'planning_alert:${item.startAt.toIso8601String()}';

      await _plugin.zonedSchedule(
        id,
        'Tra 30 min: $title',
        schedule,
        tz.TZDateTime.from(alertAt, tz.local),
        details,
        payload: payload,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
    }
  }

  Future<void> _cancelPlanningAlerts() async {
    final pending = await _plugin.pendingNotificationRequests();
    for (final request in pending) {
      final payload = request.payload ?? '';
      if (payload.startsWith('planning_alert:')) {
        await _plugin.cancel(request.id);
      }
    }
  }

  int _planningAlertId(String slotId) {
    final hash = slotId.codeUnits.fold<int>(0, (acc, c) => acc * 31 + c).abs();
    return 900000 + (hash % 900000000);
  }

  String _hhmm(DateTime value) {
    final hh = value.hour.toString().padLeft(2, '0');
    final mm = value.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }

  Future<void> debugNotifyNow({
    required String title,
    required String body,
  }) async {
    if (!kDebugMode) {
      return;
    }
    await initialize();
    const details = NotificationDetails(
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      ),
    );
    await _plugin.show(8081, title, body, details, payload: 'today_brief');
  }
}
