// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:convert';
import 'dart:html' as html;

import 'brand_bootstrap_cache_model.dart';

const _kBrandBootstrapCacheKey = 'nexora_brand_bootstrap_v1';

Future<CachedBrandTheme?> loadCachedBrandTheme() async {
  try {
    final raw = html.window.localStorage[_kBrandBootstrapCacheKey];
    if (raw == null || raw.isEmpty) return null;
    final map = jsonDecode(raw) as Map<String, dynamic>;
    return CachedBrandTheme(
      colorHex: map['colorHex'] as String?,
      logoUrl: map['logoUrl'] as String?,
    );
  } catch (_) {
    return null;
  }
}

Future<void> saveCachedBrandTheme(CachedBrandTheme theme) async {
  try {
    final payload = jsonEncode({
      'colorHex': theme.colorHex,
      'logoUrl': theme.logoUrl,
      'updatedAtMs': DateTime.now().millisecondsSinceEpoch,
    });
    html.window.localStorage[_kBrandBootstrapCacheKey] = payload;
  } catch (_) {
    // no-op on storage failures
  }
}

Future<void> clearCachedBrandTheme() async {
  try {
    html.window.localStorage.remove(_kBrandBootstrapCacheKey);
  } catch (_) {
    // no-op on storage failures
  }
}
