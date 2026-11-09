import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;

import '../models/bando_models.dart';
import 'api_client.dart';

class ExternalBandoSearchRequest {
  const ExternalBandoSearchRequest({
    this.query = '',
    this.page = 0,
    this.hitsPerPage = 10,
    this.onlyOpen = true,
    this.areaGeografica = const [],
    this.beneficiari = const [],
    this.settore = const [],
    this.agevolazione = const [],
    this.speseFinanziate = const [],
  });

  final String query;
  final int page;
  final int hitsPerPage;
  final bool onlyOpen;
  final List<String> areaGeografica;
  final List<String> beneficiari;
  final List<String> settore;
  final List<String> agevolazione;
  final List<String> speseFinanziate;

  Map<String, dynamic> toJson() => {
    'query': query,
    'page': page,
    'hitsPerPage': hitsPerPage,
    'onlyOpen': onlyOpen,
    'filters': {
      'areaGeografica': areaGeografica,
      'beneficiari': beneficiari,
      'settore': settore,
      'agevolazione': agevolazione,
      'speseFinanziate': speseFinanziate,
    },
  };

  Map<String, List<String>> get filterMap => {
    'taxonomies_hierarchical.area_geografica': areaGeografica,
    'taxonomies.beneficiari': beneficiari,
    'taxonomies_hierarchical.settore': settore,
    'taxonomies.agevolazione': agevolazione,
    'taxonomies.spese_finanziate': speseFinanziate,
  };
}

class ExternalBandoSearchResult {
  const ExternalBandoSearchResult({
    required this.items,
    required this.page,
    required this.nbPages,
    required this.nbHits,
    required this.source,
  });

  final List<ExternalBandoItem> items;
  final int page;
  final int nbPages;
  final int nbHits;
  final String source;

  factory ExternalBandoSearchResult.fromJson(dynamic raw) {
    final map = raw is Map ? raw : const {};
    final items = (map['items'] as List<dynamic>? ?? const [])
        .whereType<Map>()
        .map((item) => ExternalBandoItem.fromJson(item))
        .toList();
    return ExternalBandoSearchResult(
      items: items,
      page: (map['page'] as num?)?.toInt() ?? 0,
      nbPages: (map['nbPages'] as num?)?.toInt() ?? 0,
      nbHits: (map['nbHits'] as num?)?.toInt() ?? items.length,
      source: (map['source'] ?? 'Fonte esterna').toString(),
    );
  }
}

class ExternalBandoItem {
  const ExternalBandoItem({
    required this.externalId,
    required this.titolo,
    required this.ente,
    required this.descrizione,
    required this.link,
    this.scadenza,
    this.scadenzaTesto = '',
    this.regioni = const [],
    this.beneficiari = const [],
    this.settori = const [],
    this.agevolazioni = const [],
    this.speseFinanziate = const [],
    this.source = 'Fonte esterna',
  });

  final String externalId;
  final String titolo;
  final String ente;
  final String descrizione;
  final String link;
  final DateTime? scadenza;
  final String scadenzaTesto;
  final List<String> regioni;
  final List<String> beneficiari;
  final List<String> settori;
  final List<String> agevolazioni;
  final List<String> speseFinanziate;
  final String source;

  static List<String> _strings(dynamic value) => (value as List<dynamic>? ?? [])
      .map((item) => item.toString())
      .where((item) => item.trim().isNotEmpty)
      .toList();

  factory ExternalBandoItem.fromJson(Map<dynamic, dynamic> map) {
    DateTime? date(dynamic value) =>
        value is String ? DateTime.tryParse(value) : null;
    return ExternalBandoItem(
      externalId: (map['externalId'] ?? '').toString(),
      titolo: (map['titolo'] ?? '').toString(),
      ente: (map['ente'] ?? '').toString(),
      descrizione: (map['descrizione'] ?? '').toString(),
      link: (map['link'] ?? '').toString(),
      scadenza: date(map['scadenza']),
      scadenzaTesto: (map['scadenzaTesto'] ?? '').toString(),
      regioni: _strings(map['regioni']),
      beneficiari: _strings(map['beneficiari']),
      settori: _strings(map['settori']),
      agevolazioni: _strings(map['agevolazioni']),
      speseFinanziate: _strings(map['speseFinanziate']),
      source: (map['source'] ?? 'Fonte esterna').toString(),
    );
  }

  factory ExternalBandoItem.fromAlgolia(Map<dynamic, dynamic> hit) {
    final taxonomies = hit['taxonomies'] is Map ? hit['taxonomies'] as Map : {};
    List<String> tax(String key) => _strings(taxonomies[key]);
    final permalink = (hit['permalink'] ?? '').toString();
    final link = permalink.startsWith('/')
        ? 'https://www.contributieuropa.com$permalink'
        : permalink;
    final scadenzaRaw = (hit['scadenza'] ?? '').toString();
    final scadenzaText = (hit['scadenza_testo'] ?? scadenzaRaw).toString();

    return ExternalBandoItem(
      externalId: (hit['objectID'] ?? hit['post_id'] ?? '').toString(),
      titolo: (hit['post_title'] ?? hit['title'] ?? '').toString(),
      ente: 'Contributi Europa',
      descrizione: _stripHtml(
        (hit['post_excerpt'] ?? hit['content'] ?? '').toString(),
      ),
      link: link,
      scadenza: _parseDate(scadenzaRaw),
      scadenzaTesto: scadenzaText,
      regioni: tax('area_geografica'),
      beneficiari: tax('beneficiari'),
      settori: tax('settore'),
      agevolazioni: tax('agevolazione'),
      speseFinanziate: tax('spese_finanziate'),
      source: 'Contributi Europa',
    );
  }

  static DateTime? _parseDate(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty) return null;
    final direct = DateTime.tryParse(normalized);
    if (direct != null) return direct;
    final match = RegExp(
      r'^(\d{1,2})[/-](\d{1,2})[/-](\d{4})$',
    ).firstMatch(normalized);
    if (match == null) return null;
    final day = int.tryParse(match.group(1)!);
    final month = int.tryParse(match.group(2)!);
    final year = int.tryParse(match.group(3)!);
    if (day == null || month == null || year == null) return null;
    return DateTime(year, month, day);
  }

  static String _stripHtml(String value) => value
      .replaceAll(RegExp(r'<[^>]+>'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  Bando toDraft() => Bando(
    id: '',
    titolo: titolo,
    ente: ente.isEmpty ? source : ente,
    descrizione: descrizione,
    link: link,
    note: [
      if (externalId.isNotEmpty) 'ID fonte: $externalId',
      if (scadenzaTesto.isNotEmpty) 'Scadenza fonte: $scadenzaTesto',
      if (beneficiari.isNotEmpty) 'Beneficiari: ${beneficiari.join(', ')}',
      if (settori.isNotEmpty) 'Settori: ${settori.join(', ')}',
      if (agevolazioni.isNotEmpty) 'Agevolazioni: ${agevolazioni.join(', ')}',
      if (speseFinanziate.isNotEmpty)
        'Spese finanziate: ${speseFinanziate.join(', ')}',
    ].join('\n'),
    stato: BandoStato.aperto,
    scadenza: scadenza,
    regioni: regioni,
    areeInvestimento: speseFinanziate,
  );
}

/// Anagrafica bandi del Centro Studi, condivisa con il team.
/// [scopeId] = id del team (fallback: uid dell'utente senza team).
///
/// Persistenza MySQL-only: Firebase resta solo per Auth e notifiche push.
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
      throw ApiException(
        'API bandi MySQL non disponibile. Installa/carica /api/bandi/index.php.',
      );
    }
    if (_apiMode != true) {
      throw ApiException('Risposta API bandi MySQL non valida.');
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

  Future<ExternalBandoSearchResult> searchExternal(
    ExternalBandoSearchRequest request,
  ) async {
    try {
      final raw = await _api.post(
        '/bandi/search_external.php',
        request.toJson(),
      );
      return ExternalBandoSearchResult.fromJson(raw);
    } catch (_) {
      return _searchExternalDirect(request);
    }
  }

  Future<ExternalBandoSearchResult> _searchExternalDirect(
    ExternalBandoSearchRequest request,
  ) async {
    final filterGroups = <String>[];
    for (final entry in request.filterMap.entries) {
      final values = entry.value
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty)
          .toList();
      if (values.isEmpty) continue;
      final parts = values.map((value) {
        final safe = value.replaceAll('"', r'\"');
        if (entry.key.contains('hierarchical')) {
          return '${entry.key}.lvl0:"$safe" OR ${entry.key}.lvl1:"$safe"';
        }
        return '${entry.key}:"$safe"';
      }).toList();
      filterGroups.add('(${parts.join(' OR ')})');
    }
    if (request.onlyOpen) {
      filterGroups.add(
        '(scadenza_testo:"Bandi aperti" OR scadenza_testo:"Aperto")',
      );
    }

    final response = await http.post(
      Uri.parse(
        'https://LHI8XKBFMN-dsn.algolia.net/1/indexes/ceu_searchable_posts/query',
      ),
      headers: const {
        'Content-Type': 'application/json',
        'X-Algolia-Application-Id': 'LHI8XKBFMN',
        'X-Algolia-API-Key': 'f55131344ae840ea7f27c6dcb0782654',
      },
      body: jsonEncode({
        'query': request.query,
        'hitsPerPage': request.hitsPerPage,
        'page': request.page,
        'filters': filterGroups.join(' AND '),
        'facets': ['*'],
        'maxValuesPerFacet': 1000,
      }),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(
        'Ricerca bandi esterna non disponibile (${response.statusCode})',
        statusCode: response.statusCode,
      );
    }

    final raw = jsonDecode(response.body);
    final map = raw is Map ? raw : const {};
    final items = (map['hits'] as List<dynamic>? ?? const [])
        .whereType<Map>()
        .map(ExternalBandoItem.fromAlgolia)
        .where((item) => item.titolo.trim().isNotEmpty)
        .toList();
    return ExternalBandoSearchResult(
      items: items,
      page: (map['page'] as num?)?.toInt() ?? request.page,
      nbPages: (map['nbPages'] as num?)?.toInt() ?? 0,
      nbHits: (map['nbHits'] as num?)?.toInt() ?? items.length,
      source: 'Contributi Europa',
    );
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
