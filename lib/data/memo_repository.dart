import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import 'api_client.dart';
import '../gussoni/screens/memo_screen.dart' show MemoEl, MemoStroke, MemoArrow, MemoElementKind;
import 'package:flutter/material.dart';

// ─────────────────────────────────────────────────────────────────────────────
// MemoBoard — documento Firestore che rappresenta un singolo memo condiviso
// ─────────────────────────────────────────────────────────────────────────────

class MemoBoard {
  const MemoBoard({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.createdBy,
    required this.createdByName,
    this.updatedAt,
    this.elements = const [],
    this.strokes  = const [],
    this.arrows   = const [],
  });

  final String id;
  final String title;
  final DateTime createdAt;
  final String createdBy;
  final String createdByName;
  final DateTime? updatedAt;
  final List<MemoEl>     elements;
  final List<MemoStroke> strokes;
  final List<MemoArrow>  arrows;

  MemoBoard copyWith({
    String? title, List<MemoEl>? elements,
    List<MemoStroke>? strokes, List<MemoArrow>? arrows,
    DateTime? updatedAt,
  }) => MemoBoard(
    id: id, title: title ?? this.title,
    createdAt: createdAt, createdBy: createdBy, createdByName: createdByName,
    updatedAt: updatedAt ?? this.updatedAt,
    elements: elements ?? this.elements,
    strokes: strokes  ?? this.strokes,
    arrows:  arrows   ?? this.arrows,
  );

  Map<String, dynamic> toMap() => {
    'title':         title,
    'createdAt':     Timestamp.fromDate(createdAt),
    'createdBy':     createdBy,
    'createdByName': createdByName,
    'updatedAt':     FieldValue.serverTimestamp(),
    'elements':      elements.map(_elToMap).toList(),
    'strokes':       strokes.map(_strokeToMap).toList(),
    'arrows':        arrows.map(_arrowToMap).toList(),
  };

  factory MemoBoard.fromMap(String id, Map<String, dynamic> m) => MemoBoard(
    id:             id,
    title:          m['title'] as String? ?? 'Memo',
    createdAt:      _parseDate(m['createdAt']),
    createdBy:      m['createdBy'] as String? ?? '',
    createdByName:  m['createdByName'] as String? ?? '',
    updatedAt:      m['updatedAt'] != null ? _parseDate(m['updatedAt']) : null,
    elements: (m['elements'] as List<dynamic>? ?? [])
        .map((e) => _elFromMap(Map<String, dynamic>.from(e as Map)))
        .toList(),
    strokes: (m['strokes'] as List<dynamic>? ?? [])
        .map((s) => _strokeFromMap(Map<String, dynamic>.from(s as Map)))
        .toList(),
    arrows: (m['arrows'] as List<dynamic>? ?? [])
        .map((a) => _arrowFromMap(Map<String, dynamic>.from(a as Map)))
        .toList(),
  );
}

// ── Serialization helpers ──────────────────────────────────────────────────────

DateTime _parseDate(dynamic v) {
  if (v is Timestamp) return v.toDate();
  if (v is DateTime) return v;
  if (v is String) return DateTime.tryParse(v) ?? DateTime.now();
  return DateTime.now();
}

Map<String, dynamic> _elToMap(MemoEl e) => {
  'id': e.id, 'kind': e.kind.name,
  'x': e.x, 'y': e.y, 'w': e.w, 'h': e.h,
  'content': e.content,
  'fill': e.fill.toARGB32(),
  'textColor': e.textColor.toARGB32(),
  'fontSize': e.fontSize, 'bold': e.bold,
  'rotation': e.rotation,
};

MemoEl _elFromMap(Map<String, dynamic> m) => MemoEl(
  id:   m['id'] as String,
  kind: MemoElementKind.values.byName(m['kind'] as String),
  x: (m['x'] as num).toDouble(), y: (m['y'] as num).toDouble(),
  w: (m['w'] as num).toDouble(), h: (m['h'] as num).toDouble(),
  content:   m['content'] as String? ?? '',
  fill:      Color(m['fill'] as int),
  textColor: Color(m['textColor'] as int),
  fontSize:  (m['fontSize'] as num).toDouble(),
  bold:      m['bold'] as bool? ?? false,
  rotation:  (m['rotation'] as num? ?? 0).toDouble(),
);

Map<String, dynamic> _strokeToMap(MemoStroke s) => {
  'id': s.id,
  'pts': s.pts.map((p) => {'x': p.dx, 'y': p.dy}).toList(),
  'color': s.color.toARGB32(),
  'width': s.width,
};

MemoStroke _strokeFromMap(Map<String, dynamic> m) => MemoStroke(
  id:    m['id'] as String,
  pts:   (m['pts'] as List).map((p) {
    final pp = p as Map;
    return Offset((pp['x'] as num).toDouble(), (pp['y'] as num).toDouble());
  }).toList(),
  color: Color(m['color'] as int),
  width: (m['width'] as num).toDouble(),
);

Map<String, dynamic> _arrowToMap(MemoArrow a) => {
  'id': a.id,
  'sx': a.start.dx, 'sy': a.start.dy,
  'ex': a.end.dx,   'ey': a.end.dy,
  'color': a.color.toARGB32(),
};

MemoArrow _arrowFromMap(Map<String, dynamic> m) => MemoArrow(
  id:    m['id'] as String,
  start: Offset((m['sx'] as num).toDouble(), (m['sy'] as num).toDouble()),
  end:   Offset((m['ex'] as num).toDouble(), (m['ey'] as num).toDouble()),
  color: Color(m['color'] as int),
);

// ─────────────────────────────────────────────────────────────────────────────
// FirestoreMemoRepository
// Boards team: teams/{teamId}/memoBoards/{boardId}
// Boards personali (no team): users/{userId}/memoBoards/{boardId}
// ─────────────────────────────────────────────────────────────────────────────

class FirestoreMemoRepository {
  FirestoreMemoRepository({ApiClient? api})
    : _fs = FirebaseFirestore.instance,
      _api = api ?? ApiClient.instance;
  final FirebaseFirestore _fs;
  final ApiClient _api;

  /// Probe sull'API memo MySQL (null = non verificato).
  static bool? _apiMode;
  final Map<String, StreamController<List<MemoBoard>>> _listCtrls = {};
  final Map<String, Timer> _pollTimers = {};

  CollectionReference<Map<String, dynamic>> _col(String teamId) =>
      _fs.collection('teams').doc(teamId).collection('memoBoards');

  Future<bool> _useApi(String teamId) async {
    if (_apiMode != null) return _apiMode!;
    try {
      final raw = await _api.get('/app/memos.php', query: {'scope': teamId});
      _apiMode = raw is Map && raw['memos'] is List;
    } catch (_) {
      _apiMode = false;
    }
    return _apiMode!;
  }

  MemoBoard _boardFromApi(Map<String, dynamic> m) {
    final payload = m['payload'] is Map
        ? Map<String, dynamic>.from(m['payload'] as Map)
        : <String, dynamic>{};
    return MemoBoard.fromMap((m['id'] ?? '').toString(), {
      'title': m['title'],
      'createdAt': m['createdAt'],
      'createdBy': m['createdBy'],
      'createdByName': m['createdByName'],
      'updatedAt': m['updatedAt'],
      'elements': payload['elements'] ?? const [],
      'strokes': payload['strokes'] ?? const [],
      'arrows': payload['arrows'] ?? const [],
    });
  }

  Map<String, dynamic> _boardToApi(String teamId, MemoBoard board) => {
    'scope': teamId,
    'id': board.id,
    'title': board.title,
    'createdBy': board.createdBy,
    'createdByName': board.createdByName,
    'payload': {
      'elements': board.elements.map(_elToMap).toList(),
      'strokes': board.strokes.map(_strokeToMap).toList(),
      'arrows': board.arrows.map(_arrowToMap).toList(),
    },
  };

  Future<List<MemoBoard>> _fetchApi(String teamId) async {
    final raw = await _api.get('/app/memos.php', query: {'scope': teamId});
    final items = (raw is Map ? raw['memos'] : null) as List? ?? [];
    return items
        .whereType<Map>()
        .map((m) => _boardFromApi(Map<String, dynamic>.from(m)))
        .toList();
  }

  Future<void> _refreshApi(String teamId) async {
    final ctrl = _listCtrls[teamId];
    if (ctrl == null || ctrl.isClosed) return;
    try {
      ctrl.add(await _fetchApi(teamId));
    } catch (e) {
      if (!ctrl.isClosed) ctrl.addError(e);
    }
  }

  // ── CRUD ──────────────────────────────────────────────────────────────────

  Future<String> createBoard({
    required String teamId,
    required String userId,
    required String userName,
    required String title,
  }) async {
    if (await _useApi(teamId)) {
      final board = MemoBoard(
        id: '',
        title: title,
        createdAt: DateTime.now(),
        createdBy: userId,
        createdByName: userName,
      );
      final raw = await _api.post(
        '/app/memos.php',
        _boardToApi(teamId, board)..remove('id'),
      );
      await _refreshApi(teamId);
      return ((raw is Map ? raw['id'] : null) ?? '').toString();
    }
    final ref = _col(teamId).doc();
    await ref.set(MemoBoard(
      id: ref.id, title: title,
      createdAt: DateTime.now(),
      createdBy: userId, createdByName: userName,
    ).toMap());
    return ref.id;
  }

  Future<void> saveBoard(String teamId, MemoBoard board) async {
    if (await _useApi(teamId)) {
      await _api.post('/app/memos.php', _boardToApi(teamId, board));
      await _refreshApi(teamId);
      return;
    }
    await _col(teamId).doc(board.id).set(board.toMap());
  }

  Future<void> updateTitle(String teamId, String boardId, String title) async {
    if (await _useApi(teamId)) {
      final raw = await _api.get(
        '/app/memos.php',
        query: {'scope': teamId, 'id': boardId},
      );
      final memo = raw is Map ? raw['memo'] : null;
      if (memo is Map) {
        final board = _boardFromApi(Map<String, dynamic>.from(memo));
        await _api.post(
          '/app/memos.php',
          _boardToApi(teamId, board.copyWith(title: title)),
        );
        await _refreshApi(teamId);
      }
      return;
    }
    await _col(teamId).doc(boardId).update(
      {'title': title, 'updatedAt': FieldValue.serverTimestamp()},
    );
  }

  Future<void> deleteBoard(String teamId, String boardId) async {
    if (await _useApi(teamId)) {
      await _api.delete(
        '/app/memos.php',
        query: {'scope': teamId, 'id': boardId},
      );
      await _refreshApi(teamId);
      return;
    }
    await _col(teamId).doc(boardId).delete();
  }

  // ── Streams ────────────────────────────────────────────────────────────────

  Stream<List<MemoBoard>> watchBoards(String teamId) {
    final created = !_listCtrls.containsKey(teamId);
    final ctrl = _listCtrls.putIfAbsent(
      teamId,
      () => StreamController<List<MemoBoard>>.broadcast(),
    );
    if (created) {
      unawaited(() async {
        if (await _useApi(teamId)) {
          await _refreshApi(teamId);
          // Refresh periodico: surrogato del realtime per la collaborazione.
          _pollTimers[teamId] = Timer.periodic(
            const Duration(seconds: 20),
            (_) {
              if (ctrl.hasListener) unawaited(_refreshApi(teamId));
            },
          );
          return;
        }
        _col(teamId)
            .orderBy('createdAt', descending: true)
            .snapshots()
            .listen(
              (s) {
                if (ctrl.isClosed) return;
                ctrl.add(
                  s.docs
                      .map((d) => MemoBoard.fromMap(d.id, d.data()))
                      .toList(),
                );
              },
              onError: (Object e) {
                if (!ctrl.isClosed) ctrl.addError(e);
              },
            );
      }());
    }
    return ctrl.stream;
  }

  Stream<MemoBoard?> watchBoard(String teamId, String boardId) async* {
    if (await _useApi(teamId)) {
      while (true) {
        try {
          final raw = await _api.get(
            '/app/memos.php',
            query: {'scope': teamId, 'id': boardId},
          );
          final memo = raw is Map ? raw['memo'] : null;
          yield memo is Map
              ? _boardFromApi(Map<String, dynamic>.from(memo))
              : null;
        } catch (_) {
          yield null;
        }
        await Future<void>.delayed(const Duration(seconds: 10));
      }
    }
    yield* _col(teamId)
        .doc(boardId)
        .snapshots()
        .map((d) => d.exists ? MemoBoard.fromMap(d.id, d.data()!) : null);
  }
}

// Extension for Color serialization compatibility
extension _ColorExt on Color {
  int toARGB32() => value;
}
