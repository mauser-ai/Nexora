import 'web_push_browser_helper.dart';

class StubWebPushBrowserHelper implements WebPushBrowserHelper {
  @override
  Future<void> waitUntilReady() async {}

  @override
  Future<void> showNotification({
    required String title,
    required String body,
  }) async {}
}

WebPushBrowserHelper createWebPushBrowserHelper() => StubWebPushBrowserHelper();
