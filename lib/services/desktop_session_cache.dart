import 'desktop_session_cache_stub.dart'
    if (dart.library.html) 'desktop_session_cache_web.dart' as impl;

Future<Map<String, dynamic>?> loadCachedDesktopSession(String userId) =>
    impl.loadCachedDesktopSession(userId);

Future<void> saveCachedDesktopSession(
  String userId,
  Map<String, dynamic> session,
) => impl.saveCachedDesktopSession(userId, session);

Future<void> clearCachedDesktopSession(String userId) =>
    impl.clearCachedDesktopSession(userId);
