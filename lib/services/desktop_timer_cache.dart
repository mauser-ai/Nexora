import 'desktop_timer_cache_stub.dart'
    if (dart.library.html) 'desktop_timer_cache_web.dart'
    as impl;

Future<List<Map<String, dynamic>>> loadCachedDesktopTimers(String userId) =>
    impl.loadCachedDesktopTimers(userId);

Future<void> saveCachedDesktopTimers(
  String userId,
  List<Map<String, dynamic>> timers,
) => impl.saveCachedDesktopTimers(userId, timers);

Future<void> clearCachedDesktopTimers(String userId) =>
    impl.clearCachedDesktopTimers(userId);
