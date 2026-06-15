import 'web_push_browser_helper.dart';
import 'web_push_browser_helper_stub.dart'
    if (dart.library.html) 'web_push_browser_helper_web.dart'
    as impl;

WebPushBrowserHelper createBrowserPushHelper() =>
    impl.createWebPushBrowserHelper();
