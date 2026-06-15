import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../app/nexora_dialog.dart';
import '../../brand_config.dart';
import '../../data/team_repository.dart';
import '../../data/memo_repository.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Models
// ─────────────────────────────────────────────────────────────────────────────

enum MemoTool {
  select,
  pen,
  stickyNote,
  text,
  rectangle,
  ellipse,
  arrow,
  eraser,
}

enum MemoElementKind { stickyNote, text, rectangle, ellipse }

const _stickyColors = [
  Color(0xFFFEF3C7),
  Color(0xFFFCE7F3),
  Color(0xFFDBEAFE),
  Color(0xFFD1FAE5),
  Color(0xFFEDE9FE),
  Color(0xFFFED7AA),
  Color(0xFFEAF4FB),
  Color(0xFFDDEAF4),
];

const _penColors = [
  Color(0xFF1E293B),
  Color(0xFFEF4444),
  Color(0xFF3B82F6),
  Color(0xFF10B981),
  Color(0xFF8B5CF6),
  Color(0xFFF59E0B),
  Color(0xFFEC4899),
  Color(0xFF6366F1),
];

class MemoEl {
  MemoEl({
    required this.id,
    required this.kind,
    required this.x,
    required this.y,
    required this.w,
    required this.h,
    this.content = '',
    required this.fill,
    this.textColor = const Color(0xFF1E293B),
    this.fontSize = 14,
    this.bold = false,
    this.rotation = 0,
  });

  final String id;
  final MemoElementKind kind;
  double x, y, w, h;
  String content;
  Color fill;
  Color textColor;
  double fontSize;
  bool bold;
  double rotation;

  MemoEl copyWith({
    double? x,
    double? y,
    double? w,
    double? h,
    String? content,
    Color? fill,
    Color? textColor,
    double? fontSize,
    bool? bold,
    double? rotation,
  }) => MemoEl(
    id: id,
    kind: kind,
    x: x ?? this.x,
    y: y ?? this.y,
    w: w ?? this.w,
    h: h ?? this.h,
    content: content ?? this.content,
    fill: fill ?? this.fill,
    textColor: textColor ?? this.textColor,
    fontSize: fontSize ?? this.fontSize,
    bold: bold ?? this.bold,
    rotation: rotation ?? this.rotation,
  );
}

class MemoStroke {
  MemoStroke({
    required this.id,
    required this.pts,
    required this.color,
    required this.width,
  });
  final String id;
  final List<Offset> pts;
  final Color color;
  final double width;
}

class MemoArrow {
  MemoArrow({
    required this.id,
    required this.start,
    required this.end,
    required this.color,
  });
  final String id;
  Offset start, end;
  final Color color;
}

// ─────────────────────────────────────────────────────────────────────────────
// MemoScreen — shell con listing a sinistra + canvas a destra
// ─────────────────────────────────────────────────────────────────────────────

class MemoScreen extends StatefulWidget {
  const MemoScreen({
    super.key,
    required this.userId,
    required this.teamId,
    required this.userName,
    this.teamMembers = const [],
  });
  final String userId;
  final String teamId;
  final String userName;
  final List<TeamMember> teamMembers;

  @override
  State<MemoScreen> createState() => _MemoScreenState();
}

class _MemoScreenState extends State<MemoScreen> {
  final _repo = FirestoreMemoRepository();
  String? _selectedBoardId;

  Future<void> _createBoard() async {
    final title = await showDialog<String>(
      context: context,
      builder: (_) => const NexoraInputDialog(
        title: 'Nuovo memo',
        icon: Icons.note_alt_outlined,
        label: 'Titolo',
        initialValue: 'Nuovo memo',
        confirmLabel: 'Crea',
      ),
    );
    if (title == null || title.isEmpty || !mounted) return;
    final id = await _repo.createBoard(
      teamId: widget.teamId,
      userId: widget.userId,
      userName: widget.userName,
      title: title,
    );
    setState(() => _selectedBoardId = id);
  }

  Future<void> _deleteBoard(MemoBoard board) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => NexoraConfirmDialog(
        title: 'Elimina memo?',
        icon: Icons.delete_outline_rounded,
        message: 'Verrà eliminato "${board.title}" per tutto il team.',
        confirmLabel: 'Elimina',
        isDanger: true,
      ),
    );
    if (ok != true) return;
    await _repo.deleteBoard(widget.teamId, board.id);
    if (_selectedBoardId == board.id) setState(() => _selectedBoardId = null);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 680;
        final boardList = _MemoBoardListPane(
          repo: _repo,
          teamId: widget.teamId,
          selectedBoardId: _selectedBoardId,
          onCreateBoard: _createBoard,
          onSelectBoard: (id) => setState(() => _selectedBoardId = id),
          onDeleteBoard: _deleteBoard,
          compact: compact,
        );
        final canvas = _selectedBoardId == null
            ? _EmptyCanvas(onNew: _createBoard)
            : _BoardCanvas(
                key: ValueKey(_selectedBoardId),
                boardId: _selectedBoardId!,
                teamId: widget.teamId,
                userId: widget.userId,
                teamMembers: widget.teamMembers,
                repo: _repo,
              );

        if (compact) {
          return Column(
            children: [
              SizedBox(height: 150, child: boardList),
              Expanded(child: canvas),
            ],
          );
        }

        return Row(
          children: [
            SizedBox(width: 220, child: boardList),
            Expanded(child: canvas),
          ],
        );
      },
    );
  }
}

class _MemoBoardListPane extends StatelessWidget {
  const _MemoBoardListPane({
    required this.repo,
    required this.teamId,
    required this.selectedBoardId,
    required this.onCreateBoard,
    required this.onSelectBoard,
    required this.onDeleteBoard,
    required this.compact,
  });

  final FirestoreMemoRepository repo;
  final String teamId;
  final String? selectedBoardId;
  final VoidCallback onCreateBoard;
  final void Function(String) onSelectBoard;
  final void Function(MemoBoard) onDeleteBoard;
  final bool compact;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        colors: [
          Colors.white.withValues(alpha: .62),
          GussoniBrand.primaryBg.withValues(alpha: .24),
        ],
      ),
      border: Border(
        right: compact
            ? BorderSide.none
            : const BorderSide(color: GussoniBrand.border),
        bottom: compact
            ? const BorderSide(color: GussoniBrand.borderSubtle)
            : BorderSide.none,
      ),
    ),
    child: StreamBuilder<List<MemoBoard>>(
      stream: repo.watchBoards(teamId),
      builder: (ctx, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(strokeWidth: 2));
        }
        final boards = snap.data ?? [];
        if (boards.isEmpty) {
          return Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.sticky_note_2_outlined,
                  size: 34,
                  color: GussoniBrand.textDisabled,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Nessun memo.\nCreane uno!',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: GussoniBrand.textMuted),
                ),
                const SizedBox(height: 10),
                FilledButton.icon(
                  onPressed: onCreateBoard,
                  icon: const Icon(Icons.add, size: 14),
                  label: const Text('Nuovo memo'),
                  style: FilledButton.styleFrom(
                    backgroundColor: GussoniBrand.primary,
                    textStyle: const TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
          );
        }
        return ListView.builder(
          scrollDirection: compact ? Axis.horizontal : Axis.vertical,
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 10 : 0,
            vertical: compact ? 10 : 6,
          ),
          itemCount: boards.length,
          itemBuilder: (_, i) => SizedBox(
            width: compact ? 190 : null,
            child: _BoardTile(
              board: boards[i],
              isSelected: selectedBoardId == boards[i].id,
              onTap: () => onSelectBoard(boards[i].id),
              onDelete: () => onDeleteBoard(boards[i]),
            ),
          ),
        );
      },
    ),
  );
}

// ── Board listing tile ────────────────────────────────────────────────────────

class _BoardTile extends StatelessWidget {
  const _BoardTile({
    required this.board,
    required this.isSelected,
    required this.onTap,
    required this.onDelete,
  });
  final MemoBoard board;
  final bool isSelected;
  final VoidCallback onTap, onDelete;

  String _relativeTime() {
    final ref = board.updatedAt ?? board.createdAt;
    final diff = DateTime.now().difference(ref);
    if (diff.inMinutes < 1) return 'Adesso';
    if (diff.inHours < 1) return '${diff.inMinutes} min fa';
    if (diff.inDays < 1) return '${diff.inHours} ore fa';
    if (diff.inDays < 7) return '${diff.inDays} giorni fa';
    return DateFormat('dd/MM/yyyy').format(ref);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 130),
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
        decoration: BoxDecoration(
          color: isSelected ? GussoniBrand.primaryBg : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? GussoniBrand.primaryBorder : Colors.transparent,
          ),
        ),
        child: Row(
          children: [
            Icon(
              Icons.sticky_note_2_outlined,
              size: 15,
              color: isSelected ? GussoniBrand.primary : GussoniBrand.textMuted,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    board.title,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: isSelected
                          ? GussoniBrand.primary
                          : GussoniBrand.textPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    '${board.createdByName} · ${_relativeTime()}',
                    style: const TextStyle(
                      fontSize: 10,
                      color: GussoniBrand.textMuted,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            GestureDetector(
              onTap: onDelete,
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Icon(
                  Icons.close,
                  size: 13,
                  color: isSelected
                      ? GussoniBrand.primary
                      : GussoniBrand.textDisabled,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyCanvas extends StatelessWidget {
  const _EmptyCanvas({required this.onNew});
  final VoidCallback onNew;
  @override
  Widget build(BuildContext context) => Container(
    color: const Color(0xFFF8F7F4),
    child: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.draw_outlined,
            size: 64,
            color: GussoniBrand.textDisabled,
          ),
          const SizedBox(height: 16),
          const Text(
            'Seleziona un memo o creane uno nuovo',
            style: TextStyle(fontSize: 15, color: GussoniBrand.textMuted),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: onNew,
            icon: const Icon(Icons.add, size: 16),
            label: const Text('Nuovo memo'),
            style: FilledButton.styleFrom(
              backgroundColor: GussoniBrand.primary,
            ),
          ),
        ],
      ),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// _BoardCanvas — il vero canvas di disegno per un singolo board
// ─────────────────────────────────────────────────────────────────────────────

class _BoardCanvas extends StatefulWidget {
  const _BoardCanvas({
    super.key,
    required this.boardId,
    required this.teamId,
    required this.userId,
    required this.teamMembers,
    required this.repo,
  });
  final String boardId, teamId, userId;
  final List<TeamMember> teamMembers;
  final FirestoreMemoRepository repo;

  @override
  State<_BoardCanvas> createState() => _BoardCanvasState();
}

class _BoardCanvasState extends State<_BoardCanvas> {
  // ── State ──────────────────────────────────────────────────────────────────
  MemoTool _tool = MemoTool.select;
  final List<MemoEl> _elements = [];
  final List<MemoStroke> _strokes = [];
  final List<MemoArrow> _arrows = [];

  String? _selectedId;
  Color _activeColor = _stickyColors[0];
  Color _penColor = _penColors[0];
  double _penWidth = 3.0;
  String _boardName = 'Memo';
  bool _saving = false;
  bool _loaded = false;

  // Drawing
  List<Offset> _currentPts = [];
  Offset? _arrowStart, _arrowCurrent;
  Offset? _shapeStart, _shapeCurrent;

  // Drag element
  Offset? _dragStart;
  double? _dragElX, _dragElY;

  final _transformCtrl = TransformationController();

  // Firestore
  StreamSubscription<MemoBoard?>? _boardSub;
  Timer? _saveDebounce;
  DateTime? _lastRemoteUpdate;

  static String _uid() => DateTime.now().microsecondsSinceEpoch.toString();

  @override
  void initState() {
    super.initState();
    _loadBoard();
  }

  @override
  void dispose() {
    _boardSub?.cancel();
    _saveDebounce?.cancel();
    super.dispose();
  }

  // ── Firestore ─────────────────────────────────────────────────────────────
  void _loadBoard() {
    _boardSub = widget.repo.watchBoard(widget.teamId, widget.boardId).listen((
      board,
    ) {
      if (!mounted || board == null) return;
      // Skip se è un echo del nostro ultimo save (entro 3s)
      if (_lastRemoteUpdate != null &&
          board.updatedAt != null &&
          board.updatedAt!.isBefore(
            _lastRemoteUpdate!.add(const Duration(seconds: 3)),
          )) {
        return;
      }
      setState(() {
        _boardName = board.title;
        if (!_loaded) {
          // Prima carica: popola tutto
          _elements
            ..clear()
            ..addAll(board.elements);
          _strokes
            ..clear()
            ..addAll(board.strokes);
          _arrows
            ..clear()
            ..addAll(board.arrows);
          _loaded = true;
        }
      });
    });
  }

  void _scheduleAutoSave() {
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(seconds: 2), _saveNow);
  }

  Future<void> _saveNow() async {
    if (!mounted) return;
    setState(() => _saving = true);
    try {
      final board = MemoBoard(
        id: widget.boardId,
        title: _boardName,
        createdAt: DateTime.now(),
        createdBy: widget.userId,
        createdByName: '',
        elements: List.from(_elements),
        strokes: List.from(_strokes),
        arrows: List.from(_arrows),
      );
      _lastRemoteUpdate = DateTime.now();
      await widget.repo.saveBoard(widget.teamId, board);
    } catch (_) {}
    if (mounted) setState(() => _saving = false);
  }

  // Override setState per triggerare auto-save
  void _mutate(void Function() fn) {
    setState(fn);
    _scheduleAutoSave();
  }

  // ── Coordinate helpers ─────────────────────────────────────────────────────
  Offset _toBoard(Offset local) => local;

  // ── Tool actions ───────────────────────────────────────────────────────────
  void _handleTapOnCanvas(Offset board) {
    switch (_tool) {
      case MemoTool.stickyNote:
        _addStickyNote(board);
      case MemoTool.text:
        _addText(board);
      case MemoTool.select:
        setState(() => _selectedId = null);
      default:
        break;
    }
  }

  void _addStickyNote(Offset pos) {
    final el = MemoEl(
      id: _uid(),
      kind: MemoElementKind.stickyNote,
      x: pos.dx - 80,
      y: pos.dy - 60,
      w: 160,
      h: 120,
      fill: _activeColor,
    );
    _mutate(() {
      _elements.add(el);
      _selectedId = el.id;
    });
    Future.microtask(() => _editText(el));
  }

  void _addText(Offset pos) {
    final el = MemoEl(
      id: _uid(),
      kind: MemoElementKind.text,
      x: pos.dx,
      y: pos.dy,
      w: 200,
      h: 40,
      fill: Colors.transparent,
      content: 'Testo',
    );
    setState(() {
      _elements.add(el);
      _selectedId = el.id;
    });
    Future.microtask(() => _editText(el));
  }

  void _deleteSelected() {
    if (_selectedId == null) return;
    _mutate(() {
      _elements.removeWhere((e) => e.id == _selectedId);
      _arrows.removeWhere((a) => a.id == _selectedId);
      _selectedId = null;
    });
  }

  void _undo() {
    if (_strokes.isNotEmpty) {
      _mutate(() => _strokes.removeLast());
    } else if (_elements.isNotEmpty) {
      _mutate(() => _elements.removeLast());
    } else if (_arrows.isNotEmpty) {
      _mutate(() => _arrows.removeLast());
    }
  }

  Future<void> _clearAll() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => const NexoraConfirmDialog(
        title: 'Cancella tutto?',
        icon: Icons.delete_sweep_outlined,
        message: 'Tutti gli elementi del memo verranno eliminati.',
        confirmLabel: 'Cancella',
        isDanger: true,
      ),
    );
    if (ok != true) return;
    _mutate(() {
      _elements.clear();
      _strokes.clear();
      _arrows.clear();
      _selectedId = null;
    });
  }

  // ── Text editing ───────────────────────────────────────────────────────────
  Future<void> _editText(MemoEl el) async {
    final ctrl = TextEditingController(text: el.content);
    await showDialog<void>(
      context: context,
      barrierColor: Colors.transparent,
      builder: (ctx) => _TextEditDialog(
        ctrl: ctrl,
        el: el,
        teamMembers: widget.teamMembers,
        onChanged: (val) {
          final idx = _elements.indexWhere((e) => e.id == el.id);
          if (idx >= 0)
            setState(
              () => _elements[idx] = _elements[idx].copyWith(content: val),
            );
        },
        onColorChanged: (c) {
          final idx = _elements.indexWhere((e) => e.id == el.id);
          if (idx >= 0)
            setState(() => _elements[idx] = _elements[idx].copyWith(fill: c));
        },
        onFontSizeChanged: (s) {
          final idx = _elements.indexWhere((e) => e.id == el.id);
          if (idx >= 0)
            setState(
              () => _elements[idx] = _elements[idx].copyWith(fontSize: s),
            );
        },
      ),
    );
  }

  // ── Gesture handlers on canvas ─────────────────────────────────────────────
  void _onPanStart(DragStartDetails d) {
    final pos = d.localPosition;
    switch (_tool) {
      case MemoTool.pen:
        setState(() {
          _currentPts = [pos];
        });
      case MemoTool.eraser:
        setState(() {
          _currentPts = [pos];
        });
      case MemoTool.arrow:
        setState(() {
          _arrowStart = pos;
          _arrowCurrent = pos;
        });
      case MemoTool.rectangle:
      case MemoTool.ellipse:
        setState(() {
          _shapeStart = pos;
          _shapeCurrent = pos;
        });
      default:
        break;
    }
  }

  void _onPanUpdate(DragUpdateDetails d) {
    final pos = d.localPosition;
    switch (_tool) {
      case MemoTool.pen:
        setState(() => _currentPts.add(pos));
      case MemoTool.eraser:
        // Remove strokes near this point
        setState(() {
          _strokes.removeWhere(
            (s) => s.pts.any((p) => (p - pos).distance < 16),
          );
        });
      case MemoTool.arrow:
        setState(() => _arrowCurrent = pos);
      case MemoTool.rectangle:
      case MemoTool.ellipse:
        setState(() => _shapeCurrent = pos);
      default:
        break;
    }
  }

  void _onPanEnd(DragEndDetails d) {
    switch (_tool) {
      case MemoTool.pen:
        if (_currentPts.length > 1) {
          _mutate(() {
            _strokes.add(
              MemoStroke(
                id: _uid(),
                pts: List.from(_currentPts),
                color: _penColor,
                width: _penWidth,
              ),
            );
            _currentPts = [];
          });
        } else {
          setState(() => _currentPts = []);
        }
      case MemoTool.arrow:
        if (_arrowStart != null &&
            _arrowCurrent != null &&
            (_arrowStart! - _arrowCurrent!).distance > 20) {
          _mutate(() {
            _arrows.add(
              MemoArrow(
                id: _uid(),
                start: _arrowStart!,
                end: _arrowCurrent!,
                color: _penColor,
              ),
            );
            _arrowStart = null;
            _arrowCurrent = null;
          });
        } else {
          setState(() {
            _arrowStart = null;
            _arrowCurrent = null;
          });
        }
      case MemoTool.rectangle:
      case MemoTool.ellipse:
        if (_shapeStart != null && _shapeCurrent != null) {
          final r = Rect.fromPoints(_shapeStart!, _shapeCurrent!);
          if (r.width > 20 && r.height > 20) {
            final el = MemoEl(
              id: _uid(),
              kind: _tool == MemoTool.rectangle
                  ? MemoElementKind.rectangle
                  : MemoElementKind.ellipse,
              x: r.left,
              y: r.top,
              w: r.width,
              h: r.height,
              fill: _activeColor.withValues(alpha: 0.85),
            );
            _mutate(() {
              _elements.add(el);
              _selectedId = el.id;
            });
          }
          setState(() {
            _shapeStart = null;
            _shapeCurrent = null;
          });
        }
      default:
        break;
    }
  }

  void _onTapUp(TapUpDetails d) {
    _handleTapOnCanvas(d.localPosition);
  }

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final isPanMode = _tool == MemoTool.select;

    return Scaffold(
      backgroundColor: const Color(0xFFF8F7F4),
      body: Stack(
        children: [
          // ── Canvas ────────────────────────────────────────────────────────
          InteractiveViewer(
            transformationController: _transformCtrl,
            panEnabled: isPanMode,
            scaleEnabled: isPanMode,
            minScale: 0.2,
            maxScale: 4.0,
            boundaryMargin: const EdgeInsets.all(double.infinity),
            child: SizedBox(
              width: 4000,
              height: 3000,
              child: GestureDetector(
                onPanStart: isPanMode ? null : _onPanStart,
                onPanUpdate: isPanMode ? null : _onPanUpdate,
                onPanEnd: isPanMode ? null : _onPanEnd,
                onTapUp: _onTapUp,
                child: Stack(
                  children: [
                    // Dot grid + strokes + arrows
                    CustomPaint(
                      size: const Size(4000, 3000),
                      painter: _CanvasPainter(
                        strokes: _strokes,
                        arrows: _arrows,
                        currentPts: _currentPts,
                        penColor: _penColor,
                        penWidth: _penWidth,
                        arrowStart: _arrowStart,
                        arrowEnd: _arrowCurrent,
                        shapeStart: _shapeStart,
                        shapeEnd: _shapeCurrent,
                        tool: _tool,
                        shapeColor: _activeColor,
                      ),
                    ),

                    // Elements (sticky notes, text, shapes)
                    ..._elements.map((el) => _buildElement(el)),

                    // Selection overlay (delete button)
                    if (_selectedId != null)
                      Positioned(
                        right: 0,
                        top: 0,
                        child: SafeArea(
                          child: Padding(
                            padding: const EdgeInsets.all(8),
                            child: IconButton(
                              onPressed: _deleteSelected,
                              icon: const Icon(
                                Icons.delete_outline,
                                color: Colors.red,
                              ),
                              tooltip: 'Elimina',
                              style: IconButton.styleFrom(
                                backgroundColor: Colors.white,
                                elevation: 2,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),

          // ── Top bar ───────────────────────────────────────────────────────
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: _TopBar(
              boardName: _boardName,
              isSaving: _saving,
              onNameChanged: (n) {
                setState(() => _boardName = n);
                widget.repo
                    .updateTitle(widget.teamId, widget.boardId, n)
                    .catchError((_) {});
              },
              onUndo: _undo,
              onClear: _clearAll,
              transformCtrl: _transformCtrl,
            ),
          ),

          // ── Left toolbar ──────────────────────────────────────────────────
          Positioned(
            left: 12,
            top: 0,
            bottom: 0,
            child: Center(
              child: _ToolBar(
                selected: _tool,
                onSelect: (t) => setState(() {
                  _tool = t;
                  _selectedId = null;
                }),
              ),
            ),
          ),

          // ── Bottom color / size picker ────────────────────────────────────
          Positioned(
            bottom: 16,
            left: 0,
            right: 0,
            child: Center(
              child: _BottomOptions(
                tool: _tool,
                activeColor: _activeColor,
                penColor: _penColor,
                penWidth: _penWidth,
                onActiveColorChanged: (c) => setState(() => _activeColor = c),
                onPenColorChanged: (c) => setState(() => _penColor = c),
                onPenWidthChanged: (w) => setState(() => _penWidth = w),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildElement(MemoEl el) {
    final isSelected = _selectedId == el.id;

    return Positioned(
      left: el.x,
      top: el.y,
      width: el.w,
      height: el.h,
      child: GestureDetector(
        onTap: () {
          if (_tool == MemoTool.select) setState(() => _selectedId = el.id);
        },
        onDoubleTap: () => _editText(el),
        onPanStart: _tool == MemoTool.select
            ? (d) {
                setState(() {
                  _selectedId = el.id;
                  _dragStart = d.globalPosition;
                  _dragElX = el.x;
                  _dragElY = el.y;
                });
              }
            : null,
        onPanUpdate: _tool == MemoTool.select
            ? (d) {
                if (_dragStart == null) return;
                final delta = d.globalPosition - _dragStart!;
                final idx = _elements.indexWhere((e) => e.id == el.id);
                if (idx >= 0) {
                  setState(
                    () => _elements[idx] = _elements[idx].copyWith(
                      x: _dragElX! + delta.dx,
                      y: _dragElY! + delta.dy,
                    ),
                  );
                }
              }
            : null,
        onPanEnd: _tool == MemoTool.select
            ? (_) {
                setState(() {
                  _dragStart = null;
                  _dragElX = null;
                  _dragElY = null;
                });
              }
            : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          decoration: BoxDecoration(
            color: el.kind == MemoElementKind.ellipse
                ? null
                : el.kind == MemoElementKind.text
                ? Colors.transparent
                : el.fill,
            borderRadius: el.kind == MemoElementKind.stickyNote
                ? BorderRadius.circular(8)
                : BorderRadius.circular(4),
            shape: el.kind == MemoElementKind.ellipse
                ? BoxShape.circle
                : BoxShape.rectangle,
            border: isSelected
                ? Border.all(color: GussoniBrand.primary, width: 2)
                : el.kind == MemoElementKind.text
                ? null
                : Border.all(
                    color: Colors.black.withValues(alpha: 0.08),
                    width: 1,
                  ),
            boxShadow: el.kind == MemoElementKind.stickyNote
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 8,
                      offset: const Offset(2, 4),
                    ),
                  ]
                : isSelected
                ? [
                    BoxShadow(
                      color: GussoniBrand.primary.withValues(alpha: 0.2),
                      blurRadius: 8,
                    ),
                  ]
                : null,
          ),
          clipBehavior: el.kind == MemoElementKind.ellipse
              ? Clip.antiAlias
              : Clip.none,
          child:
              el.kind == MemoElementKind.rectangle ||
                  el.kind == MemoElementKind.ellipse
              ? Container(color: el.fill)
              : _ElementText(el: el),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Custom Painter
// ─────────────────────────────────────────────────────────────────────────────

class _CanvasPainter extends CustomPainter {
  const _CanvasPainter({
    required this.strokes,
    required this.arrows,
    required this.currentPts,
    required this.penColor,
    required this.penWidth,
    this.arrowStart,
    this.arrowEnd,
    this.shapeStart,
    this.shapeEnd,
    required this.tool,
    required this.shapeColor,
  });

  final List<MemoStroke> strokes;
  final List<MemoArrow> arrows;
  final List<Offset> currentPts;
  final Color penColor;
  final double penWidth;
  final Offset? arrowStart, arrowEnd;
  final Offset? shapeStart, shapeEnd;
  final MemoTool tool;
  final Color shapeColor;

  @override
  void paint(Canvas canvas, Size size) {
    _drawGrid(canvas, size);
    for (final s in strokes) _drawStroke(canvas, s.pts, s.color, s.width);
    if (currentPts.isNotEmpty)
      _drawStroke(canvas, currentPts, penColor, penWidth);
    for (final a in arrows) _drawArrow(canvas, a.start, a.end, a.color);
    if (arrowStart != null && arrowEnd != null)
      _drawArrow(canvas, arrowStart!, arrowEnd!, penColor);
    if (shapeStart != null && shapeEnd != null) _drawShapePreview(canvas);
  }

  void _drawGrid(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFCBD5E1).withValues(alpha: 0.5)
      ..strokeWidth = 1;
    const spacing = 28.0;
    const r = 1.2;
    for (double x = 0; x < size.width; x += spacing) {
      for (double y = 0; y < size.height; y += spacing) {
        canvas.drawCircle(Offset(x, y), r, paint..style = PaintingStyle.fill);
      }
    }
  }

  void _drawStroke(Canvas canvas, List<Offset> pts, Color color, double w) {
    if (pts.length < 2) return;
    final paint = Paint()
      ..color = color
      ..strokeWidth = w
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    final path = Path()..moveTo(pts[0].dx, pts[0].dy);
    for (int i = 1; i < pts.length - 1; i++) {
      final mid = Offset(
        (pts[i].dx + pts[i + 1].dx) / 2,
        (pts[i].dy + pts[i + 1].dy) / 2,
      );
      path.quadraticBezierTo(pts[i].dx, pts[i].dy, mid.dx, mid.dy);
    }
    path.lineTo(pts.last.dx, pts.last.dy);
    canvas.drawPath(path, paint);
  }

  void _drawArrow(Canvas canvas, Offset start, Offset end, Color color) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    // Draw curved line
    final mid = Offset((start.dx + end.dx) / 2, (start.dy + end.dy) / 2 - 30);
    final path = Path()
      ..moveTo(start.dx, start.dy)
      ..quadraticBezierTo(mid.dx, mid.dy, end.dx, end.dy);
    canvas.drawPath(path, paint);

    // Arrowhead
    const len = 12.0;
    const ang = 0.45;
    final angle = atan2(end.dy - mid.dy, end.dx - mid.dx);
    canvas.drawLine(
      end,
      Offset(end.dx - len * cos(angle - ang), end.dy - len * sin(angle - ang)),
      paint,
    );
    canvas.drawLine(
      end,
      Offset(end.dx - len * cos(angle + ang), end.dy - len * sin(angle + ang)),
      paint,
    );
  }

  void _drawShapePreview(Canvas canvas) {
    if (shapeStart == null || shapeEnd == null) return;
    final rect = Rect.fromPoints(shapeStart!, shapeEnd!);
    final paint = Paint()
      ..color = shapeColor.withValues(alpha: 0.4)
      ..style = PaintingStyle.fill;
    final border = Paint()
      ..color = shapeColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    if (tool == MemoTool.rectangle) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(4)),
        paint,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(4)),
        border,
      );
    } else if (tool == MemoTool.ellipse) {
      canvas.drawOval(rect, paint);
      canvas.drawOval(rect, border);
    }
  }

  @override
  bool shouldRepaint(_CanvasPainter o) => true;
}

// ─────────────────────────────────────────────────────────────────────────────
// Element text display
// ─────────────────────────────────────────────────────────────────────────────

class _ElementText extends StatelessWidget {
  const _ElementText({required this.el});
  final MemoEl el;

  @override
  Widget build(BuildContext context) {
    // Render @mentions with highlight
    final spans = <InlineSpan>[];
    final parts = el.content.split(RegExp(r'(@\w[\w\s]*\w|\w+)'));
    final mentions = RegExp(
      r'@\w[\w\s]*',
    ).allMatches(el.content).map((m) => m.group(0)!).toSet();

    // Simple approach: highlight @words
    final words = el.content.split(' ');
    for (var i = 0; i < words.length; i++) {
      final word = words[i];
      if (word.startsWith('@')) {
        spans.add(
          WidgetSpan(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: GussoniBrand.primary.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                word,
                style: TextStyle(
                  color: GussoniBrand.primary,
                  fontWeight: FontWeight.w700,
                  fontSize: el.fontSize,
                ),
              ),
            ),
          ),
        );
      } else {
        spans.add(
          TextSpan(
            text: word,
            style: TextStyle(
              color: el.textColor,
              fontSize: el.fontSize,
              fontWeight: el.bold ? FontWeight.w700 : FontWeight.w500,
              height: 1.4,
            ),
          ),
        );
      }
      if (i < words.length - 1) spans.add(const TextSpan(text: ' '));
    }

    return Padding(
      padding: el.kind == MemoElementKind.text
          ? EdgeInsets.zero
          : const EdgeInsets.all(10),
      child: Text.rich(
        TextSpan(children: spans),
        style: TextStyle(fontSize: el.fontSize, color: el.textColor),
        overflow: TextOverflow.fade,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Text Edit Dialog (with @mentions)
// ─────────────────────────────────────────────────────────────────────────────

class _TextEditDialog extends StatefulWidget {
  const _TextEditDialog({
    required this.ctrl,
    required this.el,
    required this.teamMembers,
    required this.onChanged,
    required this.onColorChanged,
    required this.onFontSizeChanged,
  });
  final TextEditingController ctrl;
  final MemoEl el;
  final List<TeamMember> teamMembers;
  final void Function(String) onChanged;
  final void Function(Color) onColorChanged;
  final void Function(double) onFontSizeChanged;

  @override
  State<_TextEditDialog> createState() => _TextEditDialogState();
}

class _TextEditDialogState extends State<_TextEditDialog> {
  List<TeamMember> _suggestions = [];
  Color _color = const Color(0xFFFEF3C7);
  double _fontSize = 14;

  @override
  void initState() {
    super.initState();
    _color = widget.el.fill;
    _fontSize = widget.el.fontSize;
    widget.ctrl.addListener(_checkMention);
  }

  @override
  void dispose() {
    widget.ctrl.removeListener(_checkMention);
    super.dispose();
  }

  void _checkMention() {
    final text = widget.ctrl.text;
    final cursor = widget.ctrl.selection.baseOffset;
    if (cursor < 0) return;
    final before = text.substring(0, cursor);
    final atIdx = before.lastIndexOf('@');
    if (atIdx >= 0 && !before.substring(atIdx).contains(' ')) {
      final query = before.substring(atIdx + 1).toLowerCase();
      setState(() {
        _suggestions = widget.teamMembers
            .where(
              (m) =>
                  m.displayName.toLowerCase().contains(query) ||
                  m.email.toLowerCase().contains(query),
            )
            .toList();
      });
    } else {
      setState(() => _suggestions = []);
    }
    widget.onChanged(text);
  }

  void _insertMention(TeamMember m) {
    final text = widget.ctrl.text;
    final cursor = widget.ctrl.selection.baseOffset;
    final before = text.substring(0, cursor);
    final atIdx = before.lastIndexOf('@');
    if (atIdx < 0) return;
    final after = text.substring(cursor);
    final mention = '@${m.displayName} ';
    final newText = '${text.substring(0, atIdx)}$mention$after';
    widget.ctrl.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: atIdx + mention.length),
    );
    setState(() => _suggestions = []);
    widget.onChanged(newText);
  }

  @override
  Widget build(BuildContext context) {
    final isSticky = widget.el.kind == MemoElementKind.stickyNote;
    return Dialog(
      child: Container(
        width: 380,
        padding: const EdgeInsets.all(0),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(12)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header toolbar
            Container(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              decoration: BoxDecoration(
                color: GussoniBrand.surface,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(12),
                ),
                border: const Border(
                  bottom: BorderSide(color: GussoniBrand.border),
                ),
              ),
              child: Row(
                children: [
                  // Font size
                  SizedBox(
                    width: 60,
                    child: DropdownButton<double>(
                      value: _fontSize,
                      isDense: true,
                      underline: const SizedBox(),
                      items: [10, 12, 14, 16, 20, 24, 32, 40]
                          .map(
                            (s) => DropdownMenuItem(
                              value: s.toDouble(),
                              child: Text('$s'),
                            ),
                          )
                          .toList(),
                      onChanged: (s) {
                        setState(() => _fontSize = s!);
                        widget.onFontSizeChanged(s!);
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Color swatches (only for sticky)
                  if (isSticky) ...[
                    ...(_stickyColors
                        .take(6)
                        .map(
                          (c) => GestureDetector(
                            onTap: () {
                              setState(() => _color = c);
                              widget.onColorChanged(c);
                            },
                            child: Container(
                              width: 20,
                              height: 20,
                              margin: const EdgeInsets.only(right: 4),
                              decoration: BoxDecoration(
                                color: c,
                                shape: BoxShape.circle,
                                border: _color == c
                                    ? Border.all(
                                        color: GussoniBrand.primary,
                                        width: 2,
                                      )
                                    : Border.all(color: GussoniBrand.border),
                              ),
                            ),
                          ),
                        )),
                  ],
                  const Spacer(),
                  // @mention button
                  if (widget.teamMembers.isNotEmpty)
                    IconButton(
                      icon: const Text(
                        '@',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                        ),
                      ),
                      tooltip: 'Menziona un membro',
                      onPressed: () {
                        final pos = widget.ctrl.selection.baseOffset;
                        final text = widget.ctrl.text;
                        final newText =
                            '${text.substring(0, pos)}@${text.substring(pos)}';
                        widget.ctrl.value = TextEditingValue(
                          text: newText,
                          selection: TextSelection.collapsed(offset: pos + 1),
                        );
                      },
                      style: IconButton.styleFrom(
                        minimumSize: const Size(32, 32),
                      ),
                    ),
                  IconButton(
                    icon: const Icon(
                      Icons.check,
                      size: 18,
                      color: GussoniBrand.success,
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                    style: IconButton.styleFrom(
                      minimumSize: const Size(32, 32),
                    ),
                  ),
                ],
              ),
            ),

            // Text field
            Container(
              color: isSticky ? _color : Colors.white,
              constraints: const BoxConstraints(minHeight: 80, maxHeight: 200),
              child: TextField(
                controller: widget.ctrl,
                autofocus: true,
                maxLines: null,
                style: TextStyle(
                  fontSize: _fontSize,
                  color: const Color(0xFF1E293B),
                  height: 1.5,
                ),
                decoration: const InputDecoration(
                  contentPadding: EdgeInsets.all(14),
                  border: InputBorder.none,
                  hintText: 'Scrivi qui… usa @ per menzionare',
                  hintStyle: TextStyle(color: Color(0xFF94A3B8)),
                ),
              ),
            ),

            // @mention suggestions
            if (_suggestions.isNotEmpty)
              Container(
                constraints: const BoxConstraints(maxHeight: 160),
                decoration: BoxDecoration(
                  border: const Border(
                    top: BorderSide(color: GussoniBrand.border),
                  ),
                  borderRadius: const BorderRadius.vertical(
                    bottom: Radius.circular(12),
                  ),
                ),
                child: ListView(
                  shrinkWrap: true,
                  children: _suggestions
                      .map(
                        (m) => ListTile(
                          dense: true,
                          leading: CircleAvatar(
                            radius: 14,
                            backgroundColor: GussoniBrand.primary,
                            child: Text(
                              m.displayName.isNotEmpty
                                  ? m.displayName[0].toUpperCase()
                                  : '?',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          title: Text(
                            m.displayName,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          subtitle: Text(
                            m.email,
                            style: const TextStyle(fontSize: 11),
                          ),
                          onTap: () => _insertMention(m),
                        ),
                      )
                      .toList(),
                ),
              )
            else
              const SizedBox(height: 0),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Top Bar
// ─────────────────────────────────────────────────────────────────────────────

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.boardName,
    required this.onNameChanged,
    required this.onUndo,
    required this.onClear,
    required this.transformCtrl,
    this.isSaving = false,
  });
  final String boardName;
  final bool isSaving;
  final void Function(String) onNameChanged;
  final VoidCallback onUndo, onClear;
  final TransformationController transformCtrl;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 52,
      decoration: BoxDecoration(
        color: GussoniBrand.surface.withValues(alpha: 0.95),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          const SizedBox(width: 68),
          // Board name
          Expanded(
            child: GestureDetector(
              onDoubleTap: () async {
                final newName = await showDialog<String>(
                  context: context,
                  builder: (_) => NexoraInputDialog(
                    title: 'Rinomina memo',
                    icon: Icons.drive_file_rename_outline_rounded,
                    label: 'Nome',
                    initialValue: boardName,
                    confirmLabel: 'Salva',
                  ),
                );
                if (newName != null && newName.isNotEmpty) {
                  onNameChanged(newName);
                }
              },
              child: Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.sticky_note_2_outlined,
                      size: 16,
                      color: GussoniBrand.primary,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      boardName,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: GussoniBrand.textPrimary,
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(
                      Icons.edit_outlined,
                      size: 13,
                      color: GussoniBrand.textMuted,
                    ),
                    if (isSaving) ...[
                      const SizedBox(width: 8),
                      const SizedBox(
                        width: 10,
                        height: 10,
                        child: CircularProgressIndicator(
                          strokeWidth: 1.5,
                          color: GussoniBrand.textMuted,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Text(
                        'Salvataggio…',
                        style: TextStyle(
                          fontSize: 10,
                          color: GussoniBrand.textMuted,
                        ),
                      ),
                    ] else ...[
                      const SizedBox(width: 8),
                      const Icon(
                        Icons.cloud_done_outlined,
                        size: 12,
                        color: GussoniBrand.success,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          // Actions
          IconButton(
            onPressed: onUndo,
            icon: const Icon(Icons.undo_outlined, size: 18),
            tooltip: 'Annulla',
            color: GussoniBrand.textSecondary,
          ),
          IconButton(
            onPressed: onClear,
            icon: const Icon(Icons.delete_sweep_outlined, size: 18),
            tooltip: 'Cancella tutto',
            color: GussoniBrand.textSecondary,
          ),
          // Zoom
          _ZoomControls(ctrl: transformCtrl),
          const SizedBox(width: 12),
        ],
      ),
    );
  }
}

class _ZoomControls extends StatelessWidget {
  const _ZoomControls({required this.ctrl});
  final TransformationController ctrl;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton(
          onPressed: () {
            final s = ctrl.value.getMaxScaleOnAxis();
            if (s > 0.25) ctrl.value = ctrl.value..scale(1 / 1.25, 1 / 1.25);
          },
          icon: const Icon(Icons.remove, size: 16),
          tooltip: 'Zoom out',
        ),
        GestureDetector(
          onTap: () => ctrl.value = Matrix4.identity(),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: GussoniBrand.surfaceMuted,
              borderRadius: BorderRadius.circular(6),
            ),
            child: AnimatedBuilder(
              animation: ctrl,
              builder: (_, __) => Text(
                '${(ctrl.value.getMaxScaleOnAxis() * 100).round()}%',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: GussoniBrand.textSecondary,
                ),
              ),
            ),
          ),
        ),
        IconButton(
          onPressed: () {
            final s = ctrl.value.getMaxScaleOnAxis();
            if (s < 4.0) ctrl.value = ctrl.value..scale(1.25, 1.25);
          },
          icon: const Icon(Icons.add, size: 16),
          tooltip: 'Zoom in',
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Left Toolbar
// ─────────────────────────────────────────────────────────────────────────────

class _ToolBar extends StatelessWidget {
  const _ToolBar({required this.selected, required this.onSelect});
  final MemoTool selected;
  final void Function(MemoTool) onSelect;

  static const _tools = [
    (MemoTool.select, Icons.near_me_outlined, 'Seleziona (V)'),
    (MemoTool.pen, Icons.gesture_outlined, 'Penna (P)'),
    (MemoTool.stickyNote, Icons.sticky_note_2_outlined, 'Nota adesiva (N)'),
    (MemoTool.text, Icons.text_fields_outlined, 'Testo (T)'),
    (MemoTool.rectangle, Icons.rectangle_outlined, 'Rettangolo (R)'),
    (MemoTool.ellipse, Icons.circle_outlined, 'Ellisse (E)'),
    (MemoTool.arrow, Icons.arrow_forward_outlined, 'Freccia (A)'),
    (MemoTool.eraser, Icons.auto_fix_normal_outlined, 'Gomma (X)'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      decoration: BoxDecoration(
        color: GussoniBrand.surface.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(2, 0),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: _tools.map((t) {
          final (tool, icon, label) = t;
          final isSelected = selected == tool;
          return Tooltip(
            message: label,
            preferBelow: false,
            child: GestureDetector(
              onTap: () => onSelect(tool),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                width: 40,
                height: 40,
                margin: const EdgeInsets.symmetric(vertical: 2),
                decoration: BoxDecoration(
                  color: isSelected ? GussoniBrand.primary : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  icon,
                  size: 18,
                  color: isSelected ? Colors.white : GussoniBrand.textSecondary,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Bottom Options (color + size)
// ─────────────────────────────────────────────────────────────────────────────

class _BottomOptions extends StatelessWidget {
  const _BottomOptions({
    required this.tool,
    required this.activeColor,
    required this.penColor,
    required this.penWidth,
    required this.onActiveColorChanged,
    required this.onPenColorChanged,
    required this.onPenWidthChanged,
  });
  final MemoTool tool;
  final Color activeColor, penColor;
  final double penWidth;
  final void Function(Color) onActiveColorChanged, onPenColorChanged;
  final void Function(double) onPenWidthChanged;

  @override
  Widget build(BuildContext context) {
    final showPen = tool == MemoTool.pen || tool == MemoTool.arrow;
    final showShape =
        tool == MemoTool.stickyNote ||
        tool == MemoTool.rectangle ||
        tool == MemoTool.ellipse;
    if (!showPen && !showShape) return const SizedBox.shrink();

    final colors = showPen ? _penColors : _stickyColors;
    final current = showPen ? penColor : activeColor;
    final onChange = showPen ? onPenColorChanged : onActiveColorChanged;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: GussoniBrand.surface.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(40),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 12,
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ...colors.map(
            (c) => GestureDetector(
              onTap: () => onChange(c),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 100),
                width: current == c ? 26 : 22,
                height: current == c ? 26 : 22,
                margin: const EdgeInsets.symmetric(horizontal: 3),
                decoration: BoxDecoration(
                  color: c,
                  shape: BoxShape.circle,
                  border: current == c
                      ? Border.all(color: GussoniBrand.primary, width: 2.5)
                      : Border.all(color: Colors.black12),
                  boxShadow: current == c
                      ? [
                          BoxShadow(
                            color: GussoniBrand.primary.withValues(alpha: 0.3),
                            blurRadius: 6,
                          ),
                        ]
                      : null,
                ),
              ),
            ),
          ),
          if (showPen) ...[
            const SizedBox(width: 8),
            const SizedBox(height: 20, child: VerticalDivider(width: 1)),
            const SizedBox(width: 8),
            // Stroke widths
            ...([1.5, 3.0, 5.5, 9.0]).map(
              (w) => GestureDetector(
                onTap: () => onPenWidthChanged(w),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 100),
                  width: 28,
                  height: 28,
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  decoration: BoxDecoration(
                    color: penWidth == w
                        ? GussoniBrand.primaryBg
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                    border: penWidth == w
                        ? Border.all(color: GussoniBrand.primaryBorder)
                        : null,
                  ),
                  child: Center(
                    child: Container(
                      width: w * 1.5,
                      height: w * 1.5,
                      decoration: BoxDecoration(
                        color: penColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
