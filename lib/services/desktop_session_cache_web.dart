// ignore_for_file: avoid_web_libraries_in_flutter

import 'dart:convert';
import 'dart:html' as html;

String _keyFor(String userId) => 'nexora_desktop_session_v1_$userId';

Future<Map<String, dynamic>?> loadCachedDesktopSession(String userId) async {
  try {
    final raw = html.window.localStorage[_keyFor(userId)];
    if (raw == null || raw.isEmpty) {
      return null;
    }
    final decoded = jsonDecode(raw);
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    if (decoded is Map) {
      return Map<String, dynamic>.from(decoded);
    }
  } catch (_) {
    // no-op on storage failures
  }
  return null;
}

Future<void> saveCachedDesktopSession(
  String userId,
  Map<String, dynamic> session,
) async {
  try {
    final payload = jsonEncode({
      ...session,
      'updatedAtMs': DateTime.now().millisecondsSinceEpoch,
    });
    html.window.localStorage[_keyFor(userId)] = payload;
  } catch (_) {
    // no-op on storage failures
  }
}

Future<void> clearCachedDesktopSession(String userId) async {
  try {
    html.window.localStorage.remove(_keyFor(userId));
  } catch (_) {
    // no-op on storage failures
  }
}
