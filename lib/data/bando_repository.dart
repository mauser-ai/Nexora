import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/bando_models.dart';
import 'api_client.dart';

/// Anagrafica bandi del Centro Studi, condivisa con il team.
/// [scopeId] = id del team (fallback: uid dell'utente senza team).
///
/// Doppia modalità di persistenza:
/// 1. **API PHP / MySQL** (`/api/bandi/index.php`, tabella creata da
///    `install.php`) — preferita, stessa base dati del gestionale;
/// 2. **Firestore** (`bandi_workspaces/{scopeId}/bandi`) — fallback
///    automatico finché l'endpoint non è deployato.
class BandoRepository {
  BandoRepository({FirebaseFirestore? firestore, ApiClient? api})
    : _db = firestore ?? FirebaseFirestore.instance,
      _api = api ?? ApiClient.instance;

  final FirebaseFirestore _db;
  final ApiClient _api;

  /// Esito del probe sull'endpoint PHP, condiviso tra le istanze
  /// (null = non ancora verificato).
  static bool? _apiMode;

  final Map<String, StreamController<List<Bando>>> _controllers = {};
  final Map<String, StreamSubscription<dynamic>> _firestoreSubs = {};

  CollectionReference<Map<String, dynamic>> _col(String scopeId) =>
      _db.collection('bandi_workspaces').doc(scopeId).collection('bandi');

  void _sort(List<Bando> list) {
    list.sort((a, b) {
      final byStato = a.stato.index.compareTo(b.stato.index);
      if (byStato != 0) return byStato;
      final da = a.scadenza, db = b.scadenza;
      if (da == null && db == null) return a.titolo.compareTo(b.titolo);
      if (da == null) return 1;
      if (db == null) return -1;
      return da.compareTo(db);
    });
  }

  // ─── Modalità ──────────────────────────────────────────────────────────────

  Future<bool> _ensureApiMode(String scopeId) async {
    if (_apiMode != null) return _apiMode!;
    try {
      final raw = await _api.get('/bandi/index.php', query: {'scope': scopeId});
      _apiMode = raw is Map && raw['bandi'] is List;
    } catch (_) {
      _apiMode = false;
    }
    return _apiMode!;
  }

  List<Bando> _parseApiList(dynamic raw) {
    final items = (raw is Map ? raw['bandi'] : null) as List<dynamic>? ?? [];
    final list = items
        .whereType<Map>()
        .map(
          (m) => Bando.fromMap(
            (m['id'] ?? '').toString(),
            Map<String, dynamic>.from(m),
          ),
        )
        .toList();
    _sort(list);
    return list;
  }

  // ─── Lettura ───────────────────────────────────────────────────────────────

  Stream<List<Bando>> watchBandi(String scopeId) {
    final created = !_controllers.containsKey(scopeId);
    final ctrl = _controllers.putIfAbsent(
      scopeId,
      () => StreamController<List<Bando>>.broadcast(),
    );
    // Caricamento iniziale solo alla prima sottoscrizione: i rebuild della
    // UI riusano lo stream senza rifare la GET (le scritture fanno refresh).
    if (created) unawaited(refresh(scopeId));
    return ctrl.stream;
  }

  /// Ricarica i dati e li emette sugli stream attivi.
  Future<void> refresh(String scopeId) async {
    final ctrl = _controllers[scopeId];
    if (ctrl == null) return;
    final useApi = await _ensureApiMode(scopeId);
    if (useApi) {
      try {
        final raw = await _api.get(
          '/bandi/index.php',
          query: {'scope': scopeId},
        );
        if (!ctrl.isClosed) ctrl.add(_parseApiList(raw));
      } catch (e) {
        if (!ctrl.isClosed) ctrl.addError(e);
      }
      return;
    }
    // Fallback Firestore: stream live, agganciato una sola volta per scope.
    if (_firestoreSubs.containsKey(scopeId)) return;
    _firestoreSubs[scopeId] = _col(scopeId).snapshots().listen(
      (snap) {
        final list = snap.docs
            .map((d) => Bando.fromMap(d.id, d.data()))
            .toList();
        _sort(list);
        if (!ctrl.isClosed) ctrl.add(list);
      },
      onError: (Object e) {
        if (!ctrl.isClosed) ctrl.addError(e);
      },
    );
  }

  // ─── Scrittura ─────────────────────────────────────────────────────────────

  Future<String> save(String scopeId, Bando bando) async {
    final useApi = await _ensureApiMode(scopeId);
    if (useApi) {
      final raw = await _api.post('/bandi/index.php', {
        'scope': scopeId,
        if (bando.id.isNotEmpty) 'id': bando.id,
        'titolo': bando.titolo,
        'ente': bando.ente,
        'descrizione': bando.descrizione,
        'link': bando.link,
        'note': bando.note,
        'stato': bando.stato.name,
        'apertura': bando.apertura?.toIso8601String(),
        'scadenza': bando.scadenza?.toIso8601String(),
        'dotazione': bando.dotazione,
        'percentualeContributo': bando.percentualeContributo,
        'importoMin': bando.importoMin,
        'importoMax': bando.importoMax,
        'regioni': bando.regioni,
        'codiciAteco': bando.codiciAteco,
        'dimensioni': bando.dimensioni.map((d) => d.name).toList(),
        'tipi': bando.tipi.map((t) => t.name).toList(),
        'areeInvestimento': bando.areeInvestimento,
      });
      await refresh(scopeId);
      return ((raw is Map ? raw['id'] : null) ?? bando.id).toString();
    }

    if (bando.id.isEmpty) {
      final doc = await _col(scopeId).add({
        ...bando.toMap(),
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      return doc.id;
    }
    await _col(scopeId).doc(bando.id).set({
      ...bando.toMap(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    return bando.id;
  }

  Future<void> delete(String scopeId, String bandoId) async {
    final useApi = await _ensureApiMode(scopeId);
    if (useApi) {
      await _api.delete(
        '/bandi/index.php',
        query: {'id': bandoId, 'scope': scopeId},
      );
      await refresh(scopeId);
      return;
    }
    await _col(scopeId).doc(bandoId).delete();
  }

  void dispose() {
    for (final sub in _firestoreSubs.values) {
      sub.cancel();
    }
    for (final ctrl in _controllers.values) {
      ctrl.close();
    }
  }
}
