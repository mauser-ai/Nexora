// ignore_for_file: avoid_web_libraries_in_flutter

import 'dart:convert';
import 'dart:html' as html;

String _keyFor(String userId) => 'nexora_desktop_timers_v1_$userId';

Future<List<Map<String, dynamic>>> loadCachedDesktopTimers(
  String userId,
) async {
  try {
    final raw = html.window.localStorage[_keyFor(userId)];
    if (raw == null || raw.isEmpty) {
      return const [];
    }
    final decoded = jsonDecode(raw);
    if (decoded is List) {
      return decoded
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
    }
  } catch (_) {
    // no-op
  }
  return const [];
}

Future<void> saveCachedDesktopTimers(
  String userId,
  List<Map<String, dynamic>> timers,
) async {
  try {
    html.window.localStorage[_keyFor(userId)] = jsonEncode(timers);
  } catch (_) {
    // no-op
  }
}

Future<void> clearCachedDesktopTimers(String userId) async {
  try {
    html.window.localStorage.remove(_keyFor(userId));
  } catch (_) {
    // no-op
  }
}
