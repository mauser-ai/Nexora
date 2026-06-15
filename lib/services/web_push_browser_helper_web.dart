// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter

import 'dart:html' as html;

import 'web_push_browser_helper.dart';

class BrowserWebPushHelper implements WebPushBrowserHelper {
  @override
  Future<void> waitUntilReady() async {
    final serviceWorker = html.window.navigator.serviceWorker;
    if (serviceWorker == null) {
      return;
    }
    try {
      await serviceWorker.ready;
    } catch (_) {}
  }

  @override
  Future<void> showNotification({
    required String title,
    required String body,
  }) async {
    if (!html.Notification.supported) {
      return;
    }
    if (html.Notification.permission != 'granted') {
      return;
    }
    html.Notification(
      title,
      body: body,
      icon: '/icons/Icon-192.png',
      tag: 'gussoni-web-push',
    );
  }
}

WebPushBrowserHelper createWebPushBrowserHelper() => BrowserWebPushHelper();
