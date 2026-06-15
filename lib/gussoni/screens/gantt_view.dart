import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../brand_config.dart';
import '../../models/domain_models.dart';

// ── Palette colori fasi (7 fasi standard + ciclo) ────────────────────────────
const _phaseColors = [
  Color(0xFF6366F1),
  Color(0xFF3B82F6),
  Color(0xFF0EA5E9),
  Color(0xFFF59E0B),
  Color(0xFF10B981),
  Color(0xFF8B5CF6),
  Color(0xFFEC4899),
];

Color phaseColor(int order) => _phaseColors[order.clamp(0, _phaseColors.length - 1)];

enum GanttScale { settimane, mesi }

// ── Helper: risolve startDate mancanti ────────────────────────────────────────
typedef _PhaseBar = ({ProjectPhase phase, DateTime start, DateTime end});

List<_PhaseBar> resolvePhases(List<ProjectPhase> phases) {
  final sorted = [...phases]..sort((a, b) => a.order.compareTo(b.order));
  final result = <_PhaseBar>[];
  DateTime? prevEnd;
  for (final phase in sorted) {
    if (phase.deadline == null) continue;
    final end = phase.deadline!;
    final start = phase.startDate ?? prevEnd ?? end.subtract(const Duration(days: 14));
    result.add((phase: phase, start: start, end: end));
    prevEnd = end;
  }
  return result;
}

// ─────────────────────────────────────────────────────────────────────────────
// Gantt view per SINGOLO PROGETTO (tab Suddivisione del lavoro)
// ─────────────────────────────────────────────────────────────────────────────

class ProjectGanttView extends StatefulWidget {
  const ProjectGanttView({super.key, required this.phases});
  final List<ProjectPhase> phases;

  @override
  State<ProjectGanttView> createState() => _ProjectGanttViewState();
}

class _ProjectGanttViewState extends State<ProjectGanttView> {
  GanttScale _scale = GanttScale.mesi;
  final _hScroll = ScrollController();

  static const _leftW  = 160.0;
  static const _rowH   = 44.0;
  static const _hdrH   = 40.0;

  double get _colW => _scale == GanttScale.settimane ? 80.0 : 100.0;

  ({DateTime start, DateTime end}) _range(List<_PhaseBar> bars) {
    if (bars.isEmpty) {
      final now = DateTime.now();
      return (start: DateTime(now.year, now.month, 1), end: now.add(const Duration(days: 90)));
    }
    var minD = bars.map((b) => b.start).reduce((a, b) => a.isBefore(b) ? a : b);
    var maxD = bars.map((b) => b.end).reduce((a, b) => a.isAfter(b) ? a : b);
    final pad = _scale == GanttScale.settimane ? const Duration(days: 14) : const Duration(days: 30);
    minD = _scale == GanttScale.settimane
        ? minD.subtract(pad).subtract(Duration(days: minD.weekday - 1))
        : DateTime(minD.year, minD.month, 1).subtract(pad);
    maxD = maxD.add(pad);
    return (start: minD, end: maxD);
  }

  List<DateTime> _columns(DateTime start, DateTime end) {
    final cols = <DateTime>[];
    var cur = start;
    while (cur.isBefore(end)) {
      cols.add(cur);
      cur = _scale == GanttScale.settimane
          ? cur.add(const Duration(days: 7))
          : DateTime(cur.year, cur.month + 1, 1);
    }
    return cols;
  }

  @override
  void dispose() {
    _hScroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bars = resolvePhases(widget.phases);
    final range = _range(bars);
    final cols = _columns(range.start, range.end);
    final totalDays = range.end.difference(range.start).inDays.clamp(1, 99999);
    final timelineW = cols.length * _colW;
    final today = DateTime.now();
    final todayX = today.isBefore(range.start)
        ? 0.0
        : today.isAfter(range.end)
            ? timelineW
            : today.difference(range.start).inDays / totalDays * timelineW;

    if (bars.isEmpty) {
      return const Center(child: Text('Nessuna fase con scadenza impostata.',
          style: TextStyle(color: GussoniBrand.textMuted, fontSize: 13)));
    }

    return Column(children: [
      // ── Toolbar ──────────────────────────────────────────────────
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(children: [
          const Text('Timeline fasi',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: GussoniBrand.textMuted)),
          const Spacer(),
          _ScaleToggle(scale: _scale, onChanged: (s) => setState(() => _scale = s)),
        ]),
      ),

      // ── Gantt ────────────────────────────────────────────────────
      Expanded(child: Row(children: [
        // Colonna sinistra – nomi fasi
        SizedBox(
          width: _leftW,
          child: Column(children: [
            // Header angolo
            _Cell(height: _hdrH, border: const Border(bottom: BorderSide(color: GussoniBrand.border), right: BorderSide(color: GussoniBrand.border))),
            // Righe fasi
            ...bars.asMap().entries.map((e) {
              final i = e.key;
              final b = e.value;
              final color = phaseColor(b.phase.order);
              return _Cell(
                height: _rowH,
                color: i.isEven ? GussoniBrand.surface : GussoniBrand.surfaceMuted,
                border: const Border(bottom: BorderSide(color: GussoniBrand.borderSubtle), right: BorderSide(color: GussoniBrand.border)),
                child: Row(children: [
                  Container(width: 4, height: 24, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
                  const SizedBox(width: 8),
                  Expanded(child: Text(b.phase.name,
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: GussoniBrand.textPrimary),
                      overflow: TextOverflow.ellipsis)),
                ]),
              );
            }),
          ]),
        ),

        // Area timeline – si espande fino a riempire e scorre se serve
        Expanded(child: LayoutBuilder(builder: (_, lc) {
          final availW = lc.maxWidth;
          final effectiveColW = cols.isNotEmpty
              ? (availW / cols.length).clamp(_colW, double.infinity)
              : availW;
          final effectiveW = effectiveColW * cols.length;
          final effectiveTodayX = today.isBefore(range.start)
              ? 0.0
              : today.isAfter(range.end)
                  ? effectiveW
                  : today.difference(range.start).inDays / totalDays * effectiveW;

          return Scrollbar(
            controller: _hScroll,
            thumbVisibility: effectiveW > availW,
            child: SingleChildScrollView(
              controller: _hScroll,
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: effectiveW,
                child: Column(children: [
                  // Header date
                  SizedBox(
                    height: _hdrH,
                    child: Stack(children: [
                      Row(children: cols.map((c) => _DateHeader(col: c, width: effectiveColW, scale: _scale)).toList()),
                      Positioned(left: effectiveTodayX - 1, top: 0, bottom: 0,
                          child: Container(width: 2, color: GussoniBrand.error.withValues(alpha: 0.55))),
                    ]),
                  ),
                  // Righe barre
                  ...bars.asMap().entries.map((e) {
                    final i = e.key;
                    final b = e.value;
                    final offsetDays = b.start.difference(range.start).inDays;
                    final durDays = b.end.difference(b.start).inDays.clamp(1, 99999);
                    final left = (offsetDays / totalDays * effectiveW).clamp(0.0, effectiveW);
                    final width = (durDays / totalDays * effectiveW).clamp(6.0, effectiveW - left);
                    final color = phaseColor(b.phase.order);

                    return SizedBox(
                      height: _rowH,
                      child: Stack(children: [
                        Container(color: i.isEven ? GussoniBrand.surface : GussoniBrand.surfaceMuted),
                        ...cols.asMap().entries.map((ce) => Positioned(
                          left: ce.key * effectiveColW, top: 0, bottom: 0,
                          child: Container(width: 1, color: GussoniBrand.borderSubtle),
                        )),
                        const Positioned(bottom: 0, left: 0, right: 0, child: Divider(height: 1, color: GussoniBrand.borderSubtle)),
                        Positioned(
                          left: left, top: 7, bottom: 7, width: width,
                          child: Tooltip(
                            message: '${b.phase.name}\n'
                                '${DateFormat('dd/MM/yy').format(b.start)} → '
                                '${DateFormat('dd/MM/yy').format(b.end)}',
                            child: Container(
                              decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(5)),
                              alignment: Alignment.centerLeft,
                              padding: const EdgeInsets.symmetric(horizontal: 6),
                              child: width > 50 ? Text(
                                b.phase.name.split(' ').first,
                                style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700),
                                overflow: TextOverflow.ellipsis,
                              ) : null,
                            ),
                          ),
                        ),
                        Positioned(left: effectiveTodayX - 1, top: 0, bottom: 0,
                            child: Container(width: 2, color: GussoniBrand.error.withValues(alpha: 0.5))),
                      ]),
                    );
                  }),
                ]),
              ),
            ),
          );
        })),
      ])),
    ]);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Gantt GLOBALE – listing progetti
// ─────────────────────────────────────────────────────────────────────────────

class GanttGlobaleView extends StatefulWidget {
  const GanttGlobaleView({
    super.key,
    required this.projects,
    required this.phases,
    required this.companies,
    required this.onOpenProject,
  });

  final List<Project> projects;
  final List<ProjectPhase> phases;
  final List<Company> companies;
  final void Function(Project) onOpenProject;

  @override
  State<GanttGlobaleView> createState() => _GanttGlobaleViewState();
}

class _GanttGlobaleViewState extends State<GanttGlobaleView> {
  GanttScale _scale = GanttScale.mesi;
  final _hScroll = ScrollController();

  static const _leftW  = 200.0;
  static const _rowH   = 48.0;
  static const _hdrH   = 48.0;

  double get _colW => _scale == GanttScale.settimane ? 96.0 : 120.0;

  ({DateTime start, DateTime end}) _range() {
    final allBars = widget.phases
        .where((p) => p.deadline != null)
        .expand((p) => resolvePhases([p]))
        .toList();
    if (allBars.isEmpty) {
      final now = DateTime.now();
      return (start: DateTime(now.year, now.month, 1), end: now.add(const Duration(days: 90)));
    }
    var minD = allBars.map((b) => b.start).reduce((a, b) => a.isBefore(b) ? a : b);
    var maxD = allBars.map((b) => b.end).reduce((a, b) => a.isAfter(b) ? a : b);
    final pad = _scale == GanttScale.settimane ? const Duration(days: 14) : const Duration(days: 30);
    minD = _scale == GanttScale.settimane
        ? minD.subtract(pad).subtract(Duration(days: minD.weekday - 1))
        : DateTime(minD.year, minD.month, 1).subtract(pad);
    maxD = maxD.add(pad);
    return (start: minD, end: maxD);
  }

  List<DateTime> _columns(DateTime start, DateTime end) {
    final cols = <DateTime>[];
    var cur = start;
    while (cur.isBefore(end)) {
      cols.add(cur);
      cur = _scale == GanttScale.settimane
          ? cur.add(const Duration(days: 7))
          : DateTime(cur.year, cur.month + 1, 1);
    }
    return cols;
  }

  @override
  void dispose() {
    _hScroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final range = _range();
    final cols = _columns(range.start, range.end);
    final totalDays = range.end.difference(range.start).inDays.clamp(1, 99999);
    final timelineW = cols.length * _colW;
    final today = DateTime.now();
    final todayX = today.isBefore(range.start)
        ? 0.0
        : today.isAfter(range.end)
            ? timelineW
            : today.difference(range.start).inDays / totalDays * timelineW;

    final projects = widget.projects
        .where((p) => widget.phases.any((ph) => ph.projectId == p.id && ph.deadline != null))
        .toList();

    return Column(children: [
      // Toolbar
      Padding(
        padding: const EdgeInsets.fromLTRB(0, 0, 0, 12),
        child: Row(children: [
          Text('${projects.length} progetti in timeline',
              style: const TextStyle(fontSize: 13, color: GussoniBrand.textMuted, fontWeight: FontWeight.w600)),
          const Spacer(),
          _ScaleToggle(scale: _scale, onChanged: (s) => setState(() => _scale = s)),
        ]),
      ),

      if (projects.isEmpty)
        const Expanded(child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.timeline, size: 48, color: GussoniBrand.textDisabled),
          SizedBox(height: 12),
          Text('Nessuna fase con scadenza impostata.',
              style: TextStyle(fontSize: 14, color: GussoniBrand.textMuted)),
        ])))
      else
        Expanded(child: Row(children: [
          // Colonna fissa sinistra
          SizedBox(
            width: _leftW,
            child: Column(children: [
              _Cell(height: _hdrH, border: const Border(bottom: BorderSide(color: GussoniBrand.border), right: BorderSide(color: GussoniBrand.border))),
              Expanded(child: ListView.builder(
                physics: const NeverScrollableScrollPhysics(),
                itemCount: projects.length,
                itemExtent: _rowH,
                itemBuilder: (_, i) {
                  final p = projects[i];
                  final company = widget.companies.where((c) => c.id == p.companyId).firstOrNull?.name ?? '—';
                  return GestureDetector(
                    onTap: () => widget.onOpenProject(p),
                    child: _Cell(
                      height: _rowH,
                      color: i.isEven ? GussoniBrand.surface : GussoniBrand.surfaceMuted,
                      border: const Border(bottom: BorderSide(color: GussoniBrand.borderSubtle), right: BorderSide(color: GussoniBrand.border)),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                        Text(p.name, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: GussoniBrand.textPrimary), overflow: TextOverflow.ellipsis),
                        Text(company, style: const TextStyle(fontSize: 10, color: GussoniBrand.textMuted), overflow: TextOverflow.ellipsis),
                      ]),
                    ),
                  );
                },
              )),
            ]),
          ),

          // Area timeline – si espande fino a riempire e scorre se serve
          Expanded(child: LayoutBuilder(builder: (_, lc) {
            final availW = lc.maxWidth;
            final effectiveColW = cols.isNotEmpty
                ? (availW / cols.length).clamp(_colW, double.infinity)
                : availW;
            final effectiveW = effectiveColW * cols.length;
            final effectiveTodayX = today.isBefore(range.start)
                ? 0.0
                : today.isAfter(range.end)
                    ? effectiveW
                    : today.difference(range.start).inDays / totalDays * effectiveW;

            return Scrollbar(
              controller: _hScroll,
              thumbVisibility: effectiveW > availW,
              child: SingleChildScrollView(
                controller: _hScroll,
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: effectiveW,
                  child: Column(children: [
                    // Header date
                    SizedBox(
                      height: _hdrH,
                      child: Stack(children: [
                        Row(children: cols.map((c) => _DateHeader(col: c, width: effectiveColW, scale: _scale)).toList()),
                        Positioned(left: effectiveTodayX - 1, top: 0, bottom: 0,
                            child: Container(width: 2, color: GussoniBrand.error.withValues(alpha: 0.5))),
                      ]),
                    ),
                    // Righe progetti
                    ...projects.asMap().entries.map((e) {
                      final i = e.key;
                      final p = e.value;
                      final bars = resolvePhases(
                          widget.phases.where((ph) => ph.projectId == p.id).toList());

                      return SizedBox(
                        height: _rowH,
                        child: Stack(children: [
                          Container(color: i.isEven ? GussoniBrand.surface : GussoniBrand.surfaceMuted),
                          ...cols.asMap().entries.map((ce) => Positioned(
                            left: ce.key * effectiveColW, top: 0, bottom: 0,
                            child: Container(width: 1, color: GussoniBrand.borderSubtle),
                          )),
                          const Positioned(bottom: 0, left: 0, right: 0, child: Divider(height: 1, color: GussoniBrand.borderSubtle)),
                          ...bars.map((b) {
                            final offsetDays = b.start.difference(range.start).inDays;
                            final durDays = b.end.difference(b.start).inDays.clamp(1, 99999);
                            final left = (offsetDays / totalDays * effectiveW).clamp(0.0, effectiveW);
                            final width = (durDays / totalDays * effectiveW).clamp(6.0, effectiveW - left);
                            final color = phaseColor(b.phase.order);
                            return Positioned(
                              left: left, top: 8, bottom: 8, width: width,
                              child: Tooltip(
                                message: '${b.phase.name}\n'
                                    '${DateFormat('dd/MM/yy').format(b.start)} → '
                                    '${DateFormat('dd/MM/yy').format(b.end)}',
                                child: Container(
                                  decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4)),
                                  alignment: Alignment.centerLeft,
                                  padding: const EdgeInsets.symmetric(horizontal: 6),
                                  child: width > 50 ? Text(
                                    b.phase.name.split(' ').first,
                                    style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700),
                                    overflow: TextOverflow.ellipsis,
                                  ) : null,
                                ),
                              ),
                            );
                          }),
                          Positioned(left: effectiveTodayX - 1, top: 0, bottom: 0,
                              child: Container(width: 2, color: GussoniBrand.error.withValues(alpha: 0.45))),
                        ]),
                      );
                    }),
                  ]),
                ),
              ),
            );
          })),
        ])),
    ]);
  }
}

// ── Shared widgets ────────────────────────────────────────────────────────────

class _Cell extends StatelessWidget {
  const _Cell({required this.height, this.color, this.border, this.child});
  final double height;
  final Color? color;
  final BoxBorder? border;
  final Widget? child;

  @override
  Widget build(BuildContext context) => Container(
    height: height,
    decoration: BoxDecoration(color: color ?? GussoniBrand.surface, border: border),
    padding: child != null ? const EdgeInsets.symmetric(horizontal: 12) : null,
    child: child,
  );
}

class _DateHeader extends StatelessWidget {
  const _DateHeader({required this.col, required this.width, required this.scale});
  final DateTime col;
  final double width;
  final GanttScale scale;

  @override
  Widget build(BuildContext context) {
    final label = scale == GanttScale.settimane
        ? DateFormat('dd MMM', 'it_IT').format(col)
        : DateFormat('MMM yy', 'it_IT').format(col);
    return Container(
      width: width,
      decoration: const BoxDecoration(
        color: GussoniBrand.surface,
        border: Border(bottom: BorderSide(color: GussoniBrand.border), right: BorderSide(color: GussoniBrand.border)),
      ),
      alignment: Alignment.bottomLeft,
      padding: const EdgeInsets.fromLTRB(8, 0, 4, 6),
      child: Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: GussoniBrand.textSecondary)),
    );
  }
}

class _ScaleToggle extends StatelessWidget {
  const _ScaleToggle({required this.scale, required this.onChanged});
  final GanttScale scale;
  final void Function(GanttScale) onChanged;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: GussoniBrand.surfaceMuted,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: GussoniBrand.border),
    ),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      _Pill(label: 'Settimane', active: scale == GanttScale.settimane,
          onTap: () => onChanged(GanttScale.settimane)),
      _Pill(label: 'Mesi', active: scale == GanttScale.mesi,
          onTap: () => onChanged(GanttScale.mesi)),
    ]),
  );
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.active, required this.onTap});
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: active ? GussoniBrand.primary : Colors.transparent,
        borderRadius: BorderRadius.circular(7),
      ),
      child: Text(label, style: TextStyle(
        fontSize: 12, fontWeight: FontWeight.w600,
        color: active ? Colors.white : GussoniBrand.textSecondary,
      )),
    ),
  );
}
