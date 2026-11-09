import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

// ─────────────────────────────────────────────────────────────────────────────
// Configurazione — modifica solo BASE_URL
// ─────────────────────────────────────────────────────────────────────────────
const String _kBaseUrl = 'https://nexora.sviluppo.host/api';

const String _kKeyAccess = 'nexora_access_token';
const String _kKeyRefresh = 'nexora_refresh_token';
const String _kKeyUserId = 'nexora_api_user_id';

// ─────────────────────────────────────────────────────────────────────────────
// ApiException
// ─────────────────────────────────────────────────────────────────────────────
class ApiException implements Exception {
  const ApiException(this.message, {this.statusCode});
  final String message;
  final int? statusCode;

  @override
  String toString() => 'ApiException($statusCode): $message';
}

// ─────────────────────────────────────────────────────────────────────────────
// ApiClient  –  singleton con gestione JWT + auto-refresh
// ─────────────────────────────────────────────────────────────────────────────
class ApiClient {
  ApiClient._();
  static final ApiClient instance = ApiClient._();
  static const String baseUrl = _kBaseUrl;

  // Web: usa aesGcm (richiede HTTPS). Se fallisce usa fallback in-memory.
  static FlutterSecureStorage get _secureStorage => kIsWeb
      ? const FlutterSecureStorage(
          webOptions: WebOptions(dbName: 'nexora_crm', publicKey: 'NexoraCRM'),
        )
      : const FlutterSecureStorage();

  // Fallback in-memory (usato se flutter_secure_storage non è disponibile)
  static final Map<String, String> _memStorage = {};

  final _http = http.Client();

  String? _accessToken;
  String? _refreshToken;
  String? _tokenUserId;
  bool _refreshing = false;
  Completer<void>? _refreshCompleter;

  // ── Storage helpers con fallback in-memory ────────────────────────────────
  Future<void> _write(String key, String? value) async {
    try {
      if (value == null) {
        await _secureStorage.delete(key: key);
        _memStorage.remove(key);
      } else {
        await _secureStorage.write(key: key, value: value);
        _memStorage[key] = value;
      }
    } catch (_) {
      // Fallback solo memory
      if (value == null) {
        _memStorage.remove(key);
      } else {
        _memStorage[key] = value;
      }
    }
  }

  Future<String?> _read(String key) async {
    try {
      return await _secureStorage.read(key: key);
    } catch (_) {
      return _memStorage[key];
    }
  }

  // ── Login con Firebase ───────────────────────────────────────────────────
  Future<void> loginWithFirebase() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw const ApiException('Utente non autenticato');

    // Forza il refresh del token Firebase per averne uno fresco
    final firebaseToken = await user.getIdToken(true);

    final resp = await _http.post(
      Uri.parse('$_kBaseUrl/auth/login.php'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'firebase_token': firebaseToken}),
    );

    final body = _parseBody(resp);
    _accessToken = body['access_token'] as String;
    _refreshToken = body['refresh_token'] as String;
    _tokenUserId = user.uid;

    await _write(_kKeyAccess, _accessToken);
    await _write(_kKeyRefresh, _refreshToken);
    await _write(_kKeyUserId, _tokenUserId);
  }

  // ── Carica tokens da storage al lancio ───────────────────────────────────
  Future<bool> loadStoredTokens() async {
    _accessToken = await _read(_kKeyAccess);
    _refreshToken = await _read(_kKeyRefresh);
    _tokenUserId = await _read(_kKeyUserId);
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    if (currentUserId != null &&
        _tokenUserId != null &&
        _tokenUserId != currentUserId) {
      await _clearLocalAuthState();
      return false;
    }
    return _accessToken != null;
  }

  // ── Logout ───────────────────────────────────────────────────────────────
  Future<void> logout() async {
    try {
      if (_refreshToken != null) {
        await post('/auth/logout.php', {'refresh_token': _refreshToken});
      }
    } catch (_) {}
    await _clearLocalAuthState();
  }

  // ── GET ──────────────────────────────────────────────────────────────────
  Future<dynamic> get(String path, {Map<String, String>? query}) async {
    final uri = _buildUri(path, query);
    final resp = await _authedRequest(
      () async => _http.get(uri, headers: await _headers()),
    );
    return _parseBody(resp);
  }

  // ── POST ─────────────────────────────────────────────────────────────────
  Future<dynamic> post(String path, [Map<String, dynamic>? body]) async {
    final uri = _buildUri(path);
    final bBody = body != null ? jsonEncode(body) : null;
    final resp = await _authedRequest(
      () async => _http.post(uri, headers: await _headers(), body: bBody),
    );
    return _parseBody(resp);
  }

  // ── PUT ──────────────────────────────────────────────────────────────────
  Future<dynamic> put(
    String path,
    Map<String, dynamic> body, {
    Map<String, String>? query,
  }) async {
    final uri = _buildUri(path, query);
    final bBody = jsonEncode(body);
    final resp = await _authedRequest(
      () async => _http.put(uri, headers: await _headers(), body: bBody),
    );
    return _parseBody(resp);
  }

  // ── DELETE ───────────────────────────────────────────────────────────────
  Future<dynamic> delete(String path, {Map<String, String>? query}) async {
    final uri = _buildUri(path, query);
    final resp = await _authedRequest(
      () async => _http.delete(uri, headers: await _headers()),
    );
    return _parseBody(resp);
  }

  // ── Internals ────────────────────────────────────────────────────────────

  Uri _buildUri(String path, [Map<String, String>? query]) {
    final base = '$_kBaseUrl$path';
    if (query == null || query.isEmpty) return Uri.parse(base);
    final q = query.entries.map((e) => '${e.key}=${e.value}').join('&');
    return Uri.parse('$base?$q');
  }

  Future<Map<String, String>> _headers() async => {
    'Content-Type': 'application/json',
    if (_accessToken != null) 'Authorization': 'Bearer $_accessToken',
  };

  Future<Map<String, String>> authorizedHeaders({
    Map<String, String>? extra,
    bool includeJsonContentType = true,
  }) async {
    await _ensureAuth();
    final headers = <String, String>{
      if (includeJsonContentType) 'Content-Type': 'application/json',
      if (_accessToken != null) 'Authorization': 'Bearer $_accessToken',
    };
    if (extra != null) {
      headers.addAll(extra);
    }
    return headers;
  }

  Future<String> ensureAccessToken() async {
    await _ensureAuth();
    if (_accessToken == null || _accessToken!.isEmpty) {
      throw const ApiException('Token di accesso non disponibile');
    }
    return _accessToken!;
  }

  // Garantisce che il token sia disponibile prima di ogni request
  Future<void> _ensureAuth() async {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    if (currentUserId == null) {
      await _clearLocalAuthState();
      throw const ApiException('Utente non autenticato');
    }
    if (_accessToken != null &&
        _tokenUserId != null &&
        _tokenUserId == currentUserId) {
      return;
    }
    if (_accessToken != null && _tokenUserId != currentUserId) {
      await _clearLocalAuthState();
    }
    // Prova prima i token salvati, poi Firebase
    final loaded = await loadStoredTokens();
    if (!loaded) await loginWithFirebase();
  }

  // Esegue la request; su 401 ri-autentica e riprova una volta
  Future<http.Response> _authedRequest(
    Future<Future<http.Response>> Function() fn,
  ) async {
    if (_accessToken == null) await _ensureAuth();
    var resp = await (await fn());
    if (resp.statusCode == 401) {
      await _doRefresh();
      resp = await (await fn());
    }
    return resp;
  }

  Future<void> _doRefresh() async {
    // Evita refresh multipli in parallelo
    if (_refreshing) {
      await _refreshCompleter!.future;
      return;
    }
    _refreshing = true;
    _refreshCompleter = Completer<void>();
    try {
      if (_refreshToken == null) {
        // Nessun refresh token → ri-autentica con Firebase
        await loginWithFirebase();
        return;
      }
      final resp = await _http.post(
        Uri.parse('$_kBaseUrl/auth/refresh.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'refresh_token': _refreshToken}),
      );
      if (resp.statusCode != 200) {
        await loginWithFirebase();
        return;
      }
      final body = jsonDecode(resp.body) as Map<String, dynamic>;
      _accessToken = body['access_token'] as String;
      _refreshToken = body['refresh_token'] as String;
      _tokenUserId = FirebaseAuth.instance.currentUser?.uid;
      await _write(_kKeyAccess, _accessToken);
      await _write(_kKeyRefresh, _refreshToken);
      await _write(_kKeyUserId, _tokenUserId);
    } finally {
      _refreshing = false;
      _refreshCompleter?.complete();
    }
  }

  Future<void> _clearLocalAuthState() async {
    _accessToken = null;
    _refreshToken = null;
    _tokenUserId = null;
    await _write(_kKeyAccess, null);
    await _write(_kKeyRefresh, null);
    await _write(_kKeyUserId, null);
  }

  dynamic _parseBody(http.Response resp) {
    if (resp.statusCode == 204) return null;
    final rawBody = resp.body.trim();
    if (rawBody.isEmpty) {
      throw ApiException(
        'Risposta vuota dal server (${resp.statusCode})',
        statusCode: resp.statusCode,
      );
    }

    dynamic body;
    try {
      body = jsonDecode(rawBody);
    } on FormatException {
      final preview = rawBody.length > 240
          ? '${rawBody.substring(0, 240)}…'
          : rawBody;
      throw ApiException(
        'Risposta non JSON dal server (${resp.statusCode}): $preview',
        statusCode: resp.statusCode,
      );
    }

    if (resp.statusCode >= 400) {
      final msg =
          (body is Map ? body['error'] : null) ?? 'Errore ${resp.statusCode}';
      throw ApiException(msg.toString(), statusCode: resp.statusCode);
    }
    return body;
  }
}
