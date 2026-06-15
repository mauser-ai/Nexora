import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/calendar/v3.dart' as calendar_api;
import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'package:googleapis_auth/googleapis_auth.dart' as gapis;

class GoogleCalendarService {
  GoogleCalendarService()
    : _googleSignIn = GoogleSignIn.instance,
      _initialized = false;

  final GoogleSignIn _googleSignIn;
  bool _initialized;
  GoogleSignInAccount? _currentUser;
  bool _authorized = false;
  static const _webClientId =
      '541760652202-6rveqocnnrr7gtn4lj65hfrav2o0q0de.apps.googleusercontent.com';
  static const _macosClientId =
      '541760652202-urn3ttb1hukb43va9egju6k08d6gqn2k.apps.googleusercontent.com';

  Future<void> _ensureInitialized() async {
    if (_initialized) {
      return;
    }
    final clientId = kIsWeb
        ? _webClientId
        : (defaultTargetPlatform == TargetPlatform.macOS
              ? _macosClientId
              : null);
    await _googleSignIn.initialize(clientId: clientId);
    _initialized = true;
  }

  String? get userEmail => _currentUser?.email;

  bool get isConnected => _authorized || _currentUser != null;

  Future<GoogleSignInAccount?> tryRestoreSession() async {
    await _ensureInitialized();
    const scopes = [calendar_api.CalendarApi.calendarScope];
    if (kIsWeb) {
      final authorization = await _googleSignIn.authorizationClient
          .authorizationForScopes(scopes);
      _authorized = authorization != null;
      return _currentUser;
    }
    _currentUser = await _googleSignIn.attemptLightweightAuthentication();
    if (_currentUser != null) {
      final authorization = await _currentUser!.authorizationClient
          .authorizationForScopes(scopes);
      _authorized = authorization != null;
    } else {
      _authorized = false;
    }
    return _currentUser;
  }

  Future<GoogleSignInAccount?> connect() async {
    await _ensureInitialized();
    const scopes = [calendar_api.CalendarApi.calendarScope];
    if (kIsWeb) {
      final authorization =
          await _googleSignIn.authorizationClient.authorizationForScopes(
            scopes,
          ) ??
          await _googleSignIn.authorizationClient.authorizeScopes(scopes);
      _authorized = authorization.accessToken.isNotEmpty;
      return _currentUser;
    }

    _currentUser ??= await _googleSignIn.authenticate(scopeHint: scopes);
    await _currentUser!.authorizationClient.authorizeScopes(scopes);
    _authorized = true;
    return _currentUser;
  }

  Future<void> disconnect() async {
    await _ensureInitialized();
    await _googleSignIn.signOut();
    _currentUser = null;
    _authorized = false;
  }

  Future<calendar_api.CalendarApi> _calendarApi() async {
    await _ensureInitialized();
    const scopes = [calendar_api.CalendarApi.calendarScope];
    final authClient = kIsWeb
        ? _googleSignIn.authorizationClient
        : (_currentUser ??= await _googleSignIn
                  .attemptLightweightAuthentication())
              ?.authorizationClient;
    if (authClient == null) {
      throw StateError('Google account non connesso.');
    }
    final authorization =
        await authClient.authorizationForScopes(scopes) ??
        await authClient.authorizeScopes(scopes);
    final gapis.AuthClient client = authorization.authClient(scopes: scopes);
    _authorized = true;
    return calendar_api.CalendarApi(client);
  }

  Future<String> upsertEvent({
    required String calendarId,
    required String title,
    required String description,
    required DateTime start,
    required DateTime end,
    String? eventId,
  }) async {
    final api = await _calendarApi();
    final event = calendar_api.Event()
      ..summary = title
      ..description = description
      ..start = (calendar_api.EventDateTime()..dateTime = start)
      ..end = (calendar_api.EventDateTime()..dateTime = end);

    if (eventId != null && eventId.isNotEmpty) {
      try {
        final updated = await api.events.update(event, calendarId, eventId);
        if (updated.id != null && updated.id!.isNotEmpty) {
          return updated.id!;
        }
      } catch (_) {
        // Fallback a create se l'evento non esiste piu.
      }
    }

    final created = await api.events.insert(event, calendarId);
    if (created.id == null || created.id!.isEmpty) {
      throw StateError('Google Calendar non ha restituito un event id.');
    }
    return created.id!;
  }

  Future<void> deleteEvent({
    required String calendarId,
    required String eventId,
  }) async {
    final api = await _calendarApi();
    try {
      await api.events.delete(calendarId, eventId);
    } catch (_) {
      // Se non esiste piu, consideriamo gia allineato.
    }
  }
}
