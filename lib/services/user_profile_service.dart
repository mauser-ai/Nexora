import 'dart:convert';

import 'package:http/http.dart' as http;

import '../data/api_client.dart';

/// Profili utente, preferenze, integrazioni e ruoli piattaforma.
///
/// MySQL-only: Firebase resta solo per Auth e notifiche push.
class UserProfileService {
  UserProfileService({ApiClient? api}) : _api = api ?? ApiClient.instance;

  final ApiClient _api;

  /// Probe condiviso sull'app API (null = non verificato).
  static bool? _apiMode;

  /// Ruolo dell'utente corrente (valorizzato dopo fetchProfile in API mode).
  static String currentRole = 'operatore';

  static void resetApiProbe() {
    _apiMode = null;
  }

  Future<bool> apiAvailable({bool forceRefresh = false}) async {
    if (forceRefresh) {
      _apiMode = null;
    }
    if (_apiMode != null) return _apiMode!;
    try {
      final response = await http
          .get(Uri.parse('${ApiClient.baseUrl}/app/profile.php?probe=1'))
          .timeout(const Duration(seconds: 8));
      _apiMode = response.statusCode == 200;
    } catch (_) {
      _apiMode = false;
    }
    return _apiMode!;
  }

  Future<void> _requireApi({bool forceRefresh = false}) async {
    if (!await apiAvailable(forceRefresh: forceRefresh)) {
      throw ApiException(
        'API profilo MySQL non disponibile. Installa/carica /api/app/install.php e /api/app/profile.php.',
      );
    }
  }

  // ─── Profilo / preferenze ──────────────────────────────────────────────────

  /// Profilo (preferenze incluse) con chiavi identiche al vecchio doc
  /// Firestore: accentColorHex, desktopWallpaperUrl,
  /// desktopNotificationsEnabled, avatarUrl, displayName, email, role.
  Future<Map<String, dynamic>?> fetchProfile(
    String uid, {
    String? email,
  }) async {
    await _requireApi();
    final raw = await _api
        .get(
          '/app/profile.php',
          query: {if (email != null && email.isNotEmpty) 'email': email},
        )
        .timeout(const Duration(seconds: 10));
    final profile = raw is Map ? raw['profile'] : null;
    if (profile is Map) {
      final map = Map<String, dynamic>.from(profile);
      currentRole = (map['role'] as String?) ?? 'operatore';
      return map;
    }
    return null;
  }

  Future<void> updateProfile(String uid, Map<String, dynamic> fields) async {
    await _requireApi();
    await _api
        .put('/app/profile.php', fields)
        .timeout(const Duration(seconds: 10));
  }

  // ─── Identità per il login (pre-auth) ──────────────────────────────────────

  /// Lookup nome/avatar da email per il prefill del login. Gira PRIMA
  /// dell'autenticazione: usa l'endpoint pubblico, fallback Firestore.
  Future<
    ({
      String displayName,
      String avatarUrl,
      String email,
      String brandLogoUrl,
      String brandColor,
      bool brandingEnabled,
    })?
  >
  identityByEmail(String email) async {
    // Endpoint pubblico (senza JWT).
    try {
      final response = await http
          .get(
            Uri.parse(
              '${ApiClient.baseUrl}/app/identity.php'
              '?email=${Uri.encodeQueryComponent(email)}',
            ),
          )
          .timeout(const Duration(seconds: 4));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        if (data['found'] == true) {
          return (
            displayName: (data['displayName'] as String? ?? '').trim(),
            avatarUrl: (data['avatarUrl'] as String? ?? '').trim(),
            email: (data['email'] as String? ?? email).trim(),
            brandLogoUrl: (data['brandLogoUrl'] as String? ?? '').trim(),
            brandColor: (data['brandColor'] as String? ?? '').trim(),
            brandingEnabled: data['brandingEnabled'] as bool? ?? false,
          );
        }
        if (data['found'] == false) return null;
      }
    } catch (_) {}

    return null;
  }

  // ─── Integrazioni ──────────────────────────────────────────────────────────

  Future<Map<String, Map<String, dynamic>>> loadIntegrations(String uid) async {
    await _requireApi();
    final raw = await _api.get('/app/integrations.php');
    final map = raw is Map ? raw['integrations'] : null;
    if (map is Map) {
      return map.map(
        (k, v) => MapEntry(
          k.toString(),
          v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{},
        ),
      );
    }
    return {};
  }

  Future<void> saveIntegration(
    String uid,
    String key,
    Map<String, String> values,
  ) async {
    await _requireApi();
    await _api.put('/app/integrations.php', {'key': key, 'data': values});
  }

  Future<void> removeIntegration(String uid, String key) async {
    await _requireApi();
    await _api.delete('/app/integrations.php', query: {'key': key});
  }

  // ─── Gestione utenti piattaforma (solo superadmin, solo API) ──────────────

  Future<List<Map<String, dynamic>>> listPlatformUsers() async {
    await _requireApi();
    final raw = await _api.get('/app/users.php');
    final users = raw is Map ? raw['users'] : null;
    if (users is! List) return [];
    return users
        .whereType<Map>()
        .map((u) => Map<String, dynamic>.from(u))
        .toList();
  }

  Future<void> setPlatformRole(String uid, String role) async {
    await _requireApi();
    await _api.put('/app/users.php', {'uid': uid, 'role': role});
  }
}
