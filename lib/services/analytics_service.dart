import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/foundation.dart';

class AnalyticsService {
  AnalyticsService._();

  static final AnalyticsService instance = AnalyticsService._();

  FirebaseAnalyticsObserver get observer => FirebaseAnalyticsObserver(
        analytics: FirebaseAnalytics.instance,
      );

  Future<void> logAppOpened() => FirebaseAnalytics.instance.logAppOpen();

  Future<void> logLogin(String method) => FirebaseAnalytics.instance.logLogin(
        loginMethod: method,
      );

  Future<void> logSignUp(String method) => FirebaseAnalytics.instance.logSignUp(
        signUpMethod: method,
      );

  Future<void> logScreen(String screenName) => FirebaseAnalytics.instance.logScreenView(
        screenName: screenName,
      );

  Future<void> logSeedWorkspace() => FirebaseAnalytics.instance.logEvent(
        name: 'seed_workspace',
      );

  Future<void> logTaskTimeChanged() => FirebaseAnalytics.instance.logEvent(
        name: 'task_time_changed',
      );

  Future<void> logTaskCompleted() => FirebaseAnalytics.instance.logEvent(
        name: 'task_completed',
      );

  Future<void> logTimelineSlotMoved() => FirebaseAnalytics.instance.logEvent(
        name: 'timeline_slot_moved',
      );

  Future<void> logTimelineSlotResized() => FirebaseAnalytics.instance.logEvent(
        name: 'timeline_slot_resized',
      );

  Future<void> setUser(String? userId) async {
    if (kIsWeb) {
      await FirebaseAnalytics.instance.setUserId(id: userId);
    }
  }
}
