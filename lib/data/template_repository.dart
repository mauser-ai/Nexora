import 'dart:async';

import '../models/template_models.dart';
import 'api_client.dart';

/// Template PDF, template email e scelta template per documento.
///
/// MySQL-only: nessun fallback Firestore.
class TemplateRepository {
  TemplateRepository({ApiClient? api}) : _api = api ?? ApiClient.instance;

  final ApiClient _api;

  static bool? _apiMode;
  static const Duration _cacheTtl = Duration(minutes: 3);
  static final Map<String, _TemplateCacheEntry<List<DocumentTemplate>>>
  _docsCache = {};
  static final Map<String, _TemplateCacheEntry<List<EmailTemplate>>>
  _emailsCache = {};

  final Map<String, StreamController<List<DocumentTemplate>>> _docCtrls = {};
  final Map<String, StreamController<List<EmailTemplate>>> _emailCtrls = {};
  static const Duration _requestTimeout = Duration(seconds: 12);

  Future<dynamic> _getWithTimeout(String path, {Map<String, String>? query}) =>
      _api.get(path, query: query).timeout(_requestTimeout);

  Future<dynamic> _postWithTimeout(String path, [Map<String, dynamic>? body]) =>
      _api.post(path, body).timeout(_requestTimeout);

  Future<dynamic> _putWithTimeout(
    String path,
    Map<String, dynamic> body, {
    Map<String, String>? query,
  }) => _api.put(path, body, query: query).timeout(_requestTimeout);

  Future<dynamic> _deleteWithTimeout(
    String path, {
    Map<String, String>? query,
  }) => _api.delete(path, query: query).timeout(_requestTimeout);

  Future<bool> _useApi({bool forceRefresh = false}) async {
    if (forceRefresh) {
      _apiMode = null;
    }
    if (_apiMode != null) return _apiMode!;
    try {
      final raw = await _getWithTimeout(
        '/app/templates.php',
        query: {'probe': '1'},
      );
      _apiMode = raw is Map && raw['ok'] == true;
    } catch (_) {
      _apiMode = false;
    }
    return _apiMode == true;
  }

  Future<void> _requireApi({bool forceRefresh = false}) async {
    if (!await _useApi(forceRefresh: forceRefresh)) {
      throw const ApiException(
        'API template MySQL non disponibile. Carica /api/app/templates.php e aggiorna lo schema con /api/app/install.php?run=yes.',
      );
    }
  }

  List<DocumentTemplate> _parseDocs(dynamic raw) {
    final items = (raw is Map ? raw['templates'] : null) as List? ?? [];
    return items
        .whereType<Map>()
        .map(
          (m) => DocumentTemplate.fromMap(
            (m['id'] ?? '').toString(),
            Map<String, dynamic>.from(m),
          ),
        )
        .toList();
  }

  List<EmailTemplate> _parseEmails(dynamic raw) {
    final items = (raw is Map ? raw['templates'] : null) as List? ?? [];
    return items
        .whereType<Map>()
        .map(
          (m) => EmailTemplate.fromMap(
            (m['id'] ?? '').toString(),
            Map<String, dynamic>.from(m),
          ),
        )
        .toList();
  }

  Stream<List<DocumentTemplate>> watchTemplates(String userId) async* {
    final created = !_docCtrls.containsKey(userId);
    final ctrl = _docCtrls.putIfAbsent(
      userId,
      () => StreamController<List<DocumentTemplate>>.broadcast(),
    );
    yield _docsCache['$userId|*']?.value ?? const <DocumentTemplate>[];
    if (created) {
      unawaited(_refreshDocs(userId));
    }
    yield* ctrl.stream;
  }

  Future<void> _refreshDocs(String userId) async {
    final ctrl = _docCtrls[userId];
    if (ctrl == null) return;
    try {
      await _requireApi(forceRefresh: true);
      final raw = await _getWithTimeout(
        '/app/templates.php',
        query: {'type': 'document'},
      );
      final parsed = _parseDocs(raw);
      _docsCache['$userId|*'] = _TemplateCacheEntry(parsed);
      if (!ctrl.isClosed) ctrl.add(parsed);
    } catch (e) {
      if (!ctrl.isClosed) {
        ctrl.addError(e);
      }
    }
  }

  Future<void> save(String userId, DocumentTemplate t) async {
    await _requireApi();
    await _postWithTimeout('/app/templates.php?type=document', {
      'id': t.id,
      'name': t.name,
      'category': t.category,
      'backgroundImageUrl': t.backgroundImageUrl,
      'elements': t.elements.map((e) => e.toMap()).toList(),
      'customFields': t.customFields.map((f) => f.toMap()).toList(),
    });
    _invalidateDocCache(userId);
    await _refreshDocs(userId);
  }

  Future<void> delete(String userId, String templateId) async {
    await _requireApi();
    await _deleteWithTimeout(
      '/app/templates.php',
      query: {'type': 'document', 'id': templateId},
    );
    _invalidateDocCache(userId);
    await _refreshDocs(userId);
  }

  Future<List<DocumentTemplate>> getTemplates(
    String userId, {
    String? category,
    bool forceRefresh = false,
  }) async {
    await _requireApi(forceRefresh: forceRefresh);
    final cacheKey = '$userId|${category ?? '*'}';
    final cached = _docsCache[cacheKey];
    if (!forceRefresh && cached != null && !cached.isExpired) {
      return cached.value;
    }
    final raw = await _getWithTimeout(
      '/app/templates.php',
      query: {
        'type': 'document',
        if (category case final value?) 'category': value,
      },
    );
    final parsed = _parseDocs(raw);
    _docsCache[cacheKey] = _TemplateCacheEntry(parsed);
    return parsed;
  }

  Future<void> setDocTemplateChoice(
    String userId,
    String docId,
    String? templateId,
  ) async {
    if (docId.isEmpty) return;
    await _requireApi();
    await _putWithTimeout('/app/templates.php', {
      'choice': docId,
      'templateId': templateId ?? '',
    });
  }

  Future<String?> getDocTemplateChoice(String userId, String docId) async {
    if (docId.isEmpty) return null;
    await _requireApi();
    final raw = await _getWithTimeout(
      '/app/templates.php',
      query: {'choice': docId},
    );
    final value = raw is Map ? raw['templateId'] : null;
    final id = value?.toString().trim() ?? '';
    return id.isEmpty ? null : id;
  }

  Stream<List<EmailTemplate>> watchEmailTemplates(String userId) async* {
    final created = !_emailCtrls.containsKey(userId);
    final ctrl = _emailCtrls.putIfAbsent(
      userId,
      () => StreamController<List<EmailTemplate>>.broadcast(),
    );
    yield _emailsCache[userId]?.value ?? const <EmailTemplate>[];
    if (created) {
      unawaited(_refreshEmails(userId));
    }
    yield* ctrl.stream;
  }

  Future<void> _refreshEmails(String userId) async {
    final ctrl = _emailCtrls[userId];
    if (ctrl == null) return;
    try {
      await _requireApi(forceRefresh: true);
      final raw = await _getWithTimeout(
        '/app/templates.php',
        query: {'type': 'email'},
      );
      final parsed = _parseEmails(raw);
      _emailsCache[userId] = _TemplateCacheEntry(parsed);
      if (!ctrl.isClosed) ctrl.add(parsed);
    } catch (e) {
      if (!ctrl.isClosed) {
        ctrl.addError(e);
      }
    }
  }

  Future<List<EmailTemplate>> getEmailTemplates(String userId) async {
    await _requireApi();
    final cached = _emailsCache[userId];
    if (cached != null && !cached.isExpired) {
      return cached.value;
    }
    final raw = await _getWithTimeout(
      '/app/templates.php',
      query: {'type': 'email'},
    );
    final parsed = _parseEmails(raw);
    _emailsCache[userId] = _TemplateCacheEntry(parsed);
    return parsed;
  }

  Future<void> saveEmailTemplate(String userId, EmailTemplate t) async {
    await _requireApi();
    await _postWithTimeout('/app/templates.php?type=email', {
      'id': t.id,
      'name': t.name,
      'category': t.category,
      'subject': t.subject,
      'body': t.body,
    });
    _invalidateEmailCache(userId);
    await _refreshEmails(userId);
  }

  Future<void> deleteEmailTemplate(String userId, String id) async {
    await _requireApi();
    await _deleteWithTimeout(
      '/app/templates.php',
      query: {'type': 'email', 'id': id},
    );
    _invalidateEmailCache(userId);
    await _refreshEmails(userId);
  }

  void _invalidateDocCache(String userId) {
    _docsCache.removeWhere((key, _) => key.startsWith('$userId|'));
  }

  void _invalidateEmailCache(String userId) {
    _emailsCache.remove(userId);
  }
}

class _TemplateCacheEntry<T> {
  _TemplateCacheEntry(this.value) : createdAt = DateTime.now();

  final T value;
  final DateTime createdAt;

  bool get isExpired =>
      DateTime.now().difference(createdAt) > TemplateRepository._cacheTtl;
}
