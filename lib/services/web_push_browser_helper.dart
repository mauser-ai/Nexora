abstract class WebPushBrowserHelper {
  Future<void> waitUntilReady();

  Future<void> showNotification({required String title, required String body});
}
