import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/template_models.dart';
import 'api_client.dart';

/// Template PDF, template email e scelta template per documento.
///
/// Dual-mode: preferisce l'API PHP/MySQL (`/api/app/templates.php`, tabelle
/// di `install.php`); fallback Firestore finché l'endpoint non è deployato.
class TemplateRepository {
  TemplateRepository({FirebaseFirestore? firestore, ApiClient? api})
    : _db = firestore ?? FirebaseFirestore.instance,
      _api = api ?? ApiClient.instance;

  final FirebaseFirestore _db;
  final ApiClient _api;

  static bool? _apiMode;

  final Map<String, StreamController<List<DocumentTemplate>>> _docCtrls = {};
  final Map<String, StreamController<List<EmailTemplate>>> _emailCtrls = {};
  final Map<String, StreamSubscription<dynamic>> _fsSubs = {};

  Future<bool> _useApi() async {
    if (_apiMode != null) return _apiMode!;
    try {
      final raw = await _api.get(
        '/app/templates.php',
        query: {'type': 'document'},
      );
      _apiMode = raw is Map && raw['templates'] is List;
    } catch (_) {
      _apiMode = false;
    }
    return _apiMode!;
  }

  // ── Firestore refs (fallback) ──────────────────────────────────────────────

  CollectionReference<Map<String, dynamic>> _col(String userId) =>
      _db.collection('users').doc(userId).collection('documentTemplates');

  CollectionReference<Map<String, dynamic>> _emailCol(String userId) =>
      _db.collection('users').doc(userId).collection('emailTemplates');

  CollectionReference<Map<String, dynamic>> _choiceCol(String userId) =>
      _db.collection('users').doc(userId).collection('templateChoices');

  // ── Parsing API ────────────────────────────────────────────────────────────

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

  // ── Template PDF ───────────────────────────────────────────────────────────

  Stream<List<DocumentTemplate>> watchTemplates(String userId) {
    final created = !_docCtrls.containsKey(userId);
    final ctrl = _docCtrls.putIfAbsent(
      userId,
      () => StreamController<List<DocumentTemplate>>.broadcast(),
    );
    if (created) unawaited(_refreshDocs(userId));
    return ctrl.stream;
  }

  Future<void> _refreshDocs(String userId) async {
    final ctrl = _docCtrls[userId];
    if (ctrl == null) return;
    if (await _useApi()) {
      try {
        final raw = await _api.get(
          '/app/templates.php',
          query: {'type': 'document'},
        );
        if (!ctrl.isClosed) ctrl.add(_parseDocs(raw));
      } catch (e) {
        if (!ctrl.isClosed) ctrl.addError(e);
      }
      return;
    }
    final subKey = 'doc-$userId';
    if (_fsSubs.containsKey(subKey)) return;
    _fsSubs[subKey] = _col(userId).orderBy('name').snapshots().listen(
      (snap) {
        if (ctrl.isClosed) return;
        ctrl.add(
          snap.docs
              .map((d) => DocumentTemplate.fromMap(d.id, d.data()))
              .toList(),
        );
      },
      onError: (Object e) {
        if (!ctrl.isClosed) ctrl.addError(e);
      },
    );
  }

  Future<void> save(String userId, DocumentTemplate t) async {
    if (await _useApi()) {
      await _api.post('/app/templates.php?type=document', {
        'id': t.id,
        'name': t.name,
        'category': t.category,
        'backgroundImageUrl': t.backgroundImageUrl,
        'elements': t.elements.map((e) => e.toMap()).toList(),
        'customFields': t.customFields.map((f) => f.toMap()).toList(),
      });
      await _refreshDocs(userId);
      return;
    }
    await _col(userId).doc(t.id).set({
      ...t.toMap(),
      'updatedAt': FieldValue.serverTimestamp(),
      'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> delete(String userId, String templateId) async {
    if (await _useApi()) {
      await _api.delete(
        '/app/templates.php',
        query: {'type': 'document', 'id': templateId},
      );
      await _refreshDocs(userId);
      return;
    }
    await _col(userId).doc(templateId).delete();
  }

  Future<List<DocumentTemplate>> getTemplates(
    String userId, {
    String? category,
  }) async {
    if (await _useApi()) {
      final raw = await _api.get(
        '/app/templates.php',
        query: {
          'type': 'document',
          if (category != null) 'category': category,
        },
      );
      return _parseDocs(raw);
    }
    Query<Map<String, dynamic>> query = _col(userId);
    if (category != null) {
      query = query.where('category', isEqualTo: category);
    }
    final snap = await query.get();
    final list =
        snap.docs.map((d) => DocumentTemplate.fromMap(d.id, d.data())).toList()
          ..sort((a, b) => a.name.compareTo(b.name));
    return list;
  }

  // ── Scelta template per documento ─────────────────────────────────────────

  Future<void> setDocTemplateChoice(
    String userId,
    String docId,
    String? templateId,
  ) async {
    if (docId.isEmpty) return;
    if (await _useApi()) {
      await _api.put('/app/templates.php', {
        'choice': docId,
        'templateId': templateId ?? '',
      });
      return;
    }
    if (templateId == null || templateId.isEmpty) {
      await _choiceCol(userId).doc(docId).delete();
    } else {
      await _choiceCol(userId).doc(docId).set({
        'templateId': templateId,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
  }

  Future<String?> getDocTemplateChoice(String userId, String docId) async {
    if (docId.isEmpty) return null;
    if (await _useApi()) {
      final raw = await _api.get(
        '/app/templates.php',
        query: {'choice': docId},
      );
      final value = raw is Map ? raw['templateId'] : null;
      final id = value?.toString().trim() ?? '';
      return id.isEmpty ? null : id;
    }
    final doc = await _choiceCol(userId).doc(docId).get();
    return (doc.data()?['templateId'] as String?)?.trim();
  }

  // ── Template email ─────────────────────────────────────────────────────────

  Stream<List<EmailTemplate>> watchEmailTemplates(String userId) {
    final created = !_emailCtrls.containsKey(userId);
    final ctrl = _emailCtrls.putIfAbsent(
      userId,
      () => StreamController<List<EmailTemplate>>.broadcast(),
    );
    if (created) unawaited(_refreshEmails(userId));
    return ctrl.stream;
  }

  Future<void> _refreshEmails(String userId) async {
    final ctrl = _emailCtrls[userId];
    if (ctrl == null) return;
    if (await _useApi()) {
      try {
        final raw = await _api.get(
          '/app/templates.php',
          query: {'type': 'email'},
        );
        if (!ctrl.isClosed) ctrl.add(_parseEmails(raw));
      } catch (e) {
        if (!ctrl.isClosed) ctrl.addError(e);
      }
      return;
    }
    final subKey = 'email-$userId';
    if (_fsSubs.containsKey(subKey)) return;
    _fsSubs[subKey] = _emailCol(userId).orderBy('name').snapshots().listen(
      (snap) {
        if (ctrl.isClosed) return;
        ctrl.add(
          snap.docs.map((d) => EmailTemplate.fromMap(d.id, d.data())).toList(),
        );
      },
      onError: (Object e) {
        if (!ctrl.isClosed) ctrl.addError(e);
      },
    );
  }

  Future<List<EmailTemplate>> getEmailTemplates(String userId) async {
    if (await _useApi()) {
      final raw = await _api.get(
        '/app/templates.php',
        query: {'type': 'email'},
      );
      return _parseEmails(raw);
    }
    final snap = await _emailCol(userId).orderBy('name').get();
    return snap.docs.map((d) => EmailTemplate.fromMap(d.id, d.data())).toList();
  }

  Future<void> saveEmailTemplate(String userId, EmailTemplate t) async {
    if (await _useApi()) {
      await _api.post('/app/templates.php?type=email', {
        'id': t.id,
        'name': t.name,
        'category': t.category,
        'subject': t.subject,
        'body': t.body,
      });
      await _refreshEmails(userId);
      return;
    }
    await _emailCol(userId).doc(t.id).set({
      ...t.toMap(),
      'updatedAt': FieldValue.serverTimestamp(),
      'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> deleteEmailTemplate(String userId, String id) async {
    if (await _useApi()) {
      await _api.delete(
        '/app/templates.php',
        query: {'type': 'email', 'id': id},
      );
      await _refreshEmails(userId);
      return;
    }
    await _emailCol(userId).doc(id).delete();
  }
}
