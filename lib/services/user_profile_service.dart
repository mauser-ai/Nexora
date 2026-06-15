import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;

import '../data/api_client.dart';

/// Profili utente, preferenze, integrazioni e ruoli piattaforma.
///
/// Dual-mode: preferisce l'API PHP/MySQL (`/api/app/...`, tabelle create da
/// `install.php`); finché l'endpoint non è deployato usa Firestore come
/// fallback (collection `users`). Su Firestore restano solo auth e push.
class UserProfileService {
  UserProfileService({FirebaseFirestore? firestore, ApiClient? api})
    : _db = firestore ?? FirebaseFirestore.instance,
      _api = api ?? ApiClient.instance;

  final FirebaseFirestore _db;
  final ApiClient _api;

  /// Probe condiviso sull'app API (null = non verificato).
  static bool? _apiMode;

  /// Ruolo dell'utente corrente (valorizzato dopo fetchProfile in API mode).
  static String currentRole = 'operatore';

  Future<bool> apiAvailable() async {
    if (_apiMode != null) return _apiMode!;
    try {
      final raw = await _api.get('/app/profile.php');
      _apiMode = raw is Map && raw['profile'] is Map;
    } catch (_) {
      _apiMode = false;
    }
    return _apiMode!;
  }

  // ─── Profilo / preferenze ──────────────────────────────────────────────────

  /// Profilo (preferenze incluse) con chiavi identiche al vecchio doc
  /// Firestore: accentColorHex, desktopWallpaperUrl,
  /// desktopNotificationsEnabled, avatarUrl, displayName, email, role.
  Future<Map<String, dynamic>?> fetchProfile(
    String uid, {
    String? email,
  }) async {
    if (await apiAvailable()) {
      final raw = await _api.get(
        '/app/profile.php',
        query: {if (email != null && email.isNotEmpty) 'email': email},
      );
      final profile = raw is Map ? raw['profile'] : null;
      if (profile is Map) {
        final map = Map<String, dynamic>.from(profile);
        currentRole = (map['role'] as String?) ?? 'operatore';
        return map;
      }
      return null;
    }
    final doc = await _db.collection('users').doc(uid).get();
    return doc.data();
  }

  Future<void> updateProfile(String uid, Map<String, dynamic> fields) async {
    if (await apiAvailable()) {
      await _api.put('/app/profile.php', fields);
      return;
    }
    await _db
        .collection('users')
        .doc(uid)
        .set(fields, SetOptions(merge: true));
  }

  // ─── Identità per il login (pre-auth) ──────────────────────────────────────

  /// Lookup nome/avatar da email per il prefill del login. Gira PRIMA
  /// dell'autenticazione: usa l'endpoint pubblico, fallback Firestore.
  Future<({String displayName, String avatarUrl, String email})?>
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
          );
        }
        if (data['found'] == false) return null;
      }
    } catch (_) {}

    // Fallback Firestore (comportamento storico).
    try {
      final query = await _db
          .collection('users')
          .where('email', isEqualTo: email)
          .limit(1)
          .get();
      if (query.docs.isEmpty) return null;
      final doc = query.docs.first.data();
      return (
        displayName: (doc['displayName'] as String? ?? '').trim(),
        avatarUrl: (doc['avatarUrl'] as String? ?? '').trim(),
        email: (doc['email'] as String? ?? email).trim(),
      );
    } catch (_) {
      return null;
    }
  }

  // ─── Integrazioni ──────────────────────────────────────────────────────────

  Future<Map<String, Map<String, dynamic>>> loadIntegrations(
    String uid,
  ) async {
    if (await apiAvailable()) {
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
    final doc = await _db.collection('users').doc(uid).get();
    final raw = doc.data()?['integrations'];
    if (raw is! Map) return {};
    return raw.map(
      (k, v) => MapEntry(
        k.toString(),
        v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{},
      ),
    );
  }

  Future<void> saveIntegration(
    String uid,
    String key,
    Map<String, String> values,
  ) async {
    if (await apiAvailable()) {
      await _api.put('/app/integrations.php', {'key': key, 'data': values});
      return;
    }
    await _db.collection('users').doc(uid).set({
      'integrations': {
        key: {...values, 'updatedAt': FieldValue.serverTimestamp()},
      },
    }, SetOptions(merge: true));
  }

  Future<void> removeIntegration(String uid, String key) async {
    if (await apiAvailable()) {
      await _api.delete('/app/integrations.php', query: {'key': key});
      return;
    }
    await _db.collection('users').doc(uid).set({
      'integrations': {key: FieldValue.delete()},
    }, SetOptions(merge: true));
  }

  // ─── Gestione utenti piattaforma (solo superadmin, solo API) ──────────────

  Future<List<Map<String, dynamic>>> listPlatformUsers() async {
    if (!await apiAvailable()) return [];
    final raw = await _api.get('/app/users.php');
    final users = raw is Map ? raw['users'] : null;
    if (users is! List) return [];
    return users
        .whereType<Map>()
        .map((u) => Map<String, dynamic>.from(u))
        .toList();
  }

  Future<void> setPlatformRole(String uid, String role) async {
    await _api.put('/app/users.php', {'uid': uid, 'role': role});
  }
}
