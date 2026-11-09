import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show FontFeature;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../brand_config.dart';
import '../../data/api_workspace_repository.dart';
import '../../data/team_repository.dart';
import '../../models/desktop_timer_entry.dart';
import '../../models/domain_models.dart';

// ─── Enums ────────────────────────────────────────────────────────────────────

enum _ViewMode { day, week, month }

// ─── Screen principale ────────────────────────────────────────────────────────

class SegantempoGussoniScreen extends StatefulWidget {
  const SegantempoGussoniScreen({
    super.key,
    required this.workspace,
    required this.userId,
    required this.repository,
    required this.onAddTimeTrack,
    required this.desktopTimers,
    required this.onStartTimer,
    required this.onStopTimer,
    required this.onOpenPendingTimer,
    required this.onDiscardPendingTimer,
    this.memberTimeTracks = const {},
    this.teamInfo,
  });

  final WorkspaceSnapshot workspace;
  final String userId;
  final ApiWorkspaceRepository repository;
  final void Function({DateTime? date, TimeTrack? track}) onAddTimeTrack;
  final List<DesktopTimerEntry> desktopTimers;
  final VoidCallback onStartTimer;
  final void Function(DesktopTimerEntry timer) onStopTimer;
  final void Function(DesktopTimerEntry timer) onOpenPendingTimer;
  final void Function(DesktopTimerEntry timer) onDiscardPendingTimer;
  final Map<String, List<TimeTrack>> memberTimeTracks;
  final TeamInfo? teamInfo;

  @override
  State<SegantempoGussoniScreen> createState() =>
      _SegantempoGussoniScreenState();
}

class _SegantempoGussoniScreenState extends State<SegantempoGussoniScreen> {
  _ViewMode _mode = _ViewMode.week;
  DateTime _anchor = DateTime.now();
  String? _filterUserId; // null = current user

  final _eur = NumberFormat.currency(
    locale: 'it_IT',
    symbol: '€',
    decimalDigits: 2,
  );
  final _dateFmt = DateFormat('dd/MM/yyyy');

  // ── week navigation ──

  DateTime get _weekStart {
    final d = _anchor;
    return DateTime(
      d.year,
      d.month,
      d.day,
    ).subtract(Duration(days: d.weekday - 1));
  }

  DateTime get _weekEnd => _weekStart.add(const Duration(days: 6));

  int get _weekNumber {
    final jan4 = DateTime(_weekStart.year, 1, 4);
    final startOfFirstWeek = jan4.subtract(Duration(days: jan4.weekday - 1));
    return ((_weekStart.difference(startOfFirstWeek).inDays) / 7).floor() + 1;
  }

  void _prev() => setState(
    () => _anchor = _anchor.subtract(
      _mode == _ViewMode.day
          ? const Duration(days: 1)
          : _mode == _ViewMode.week
          ? const Duration(days: 7)
          : const Duration(days: 30),
    ),
  );

  void _next() => setState(
    () => _anchor = _anchor.add(
      _mode == _ViewMode.day
          ? const Duration(days: 1)
          : _mode == _ViewMode.week
          ? const Duration(days: 7)
          : const Duration(days: 30),
    ),
  );

  // ── data ──

  String get _activeUserId => _filterUserId ?? widget.userId;

  List<TimeTrack> get _userTracks {
    if (_filterUserId == null || _filterUserId == widget.userId) {
      return widget.workspace.timeTracks;
    }
    return widget.memberTimeTracks[_filterUserId] ?? [];
  }

  List<DateTime> get _visibleDays {
    switch (_mode) {
      case _ViewMode.day:
        return [DateTime(_anchor.year, _anchor.month, _anchor.day)];
      case _ViewMode.week:
        return List.generate(7, (i) => _weekStart.add(Duration(days: i)));
      case _ViewMode.month:
        final first = DateTime(_anchor.year, _anchor.month, 1);
        final last = DateTime(_anchor.year, _anchor.month + 1, 0);
        return List.generate(last.day, (i) => first.add(Duration(days: i)));
    }
  }

  List<TimeTrack> _tracksForDay(DateTime day) {
    return _userTracks.where((t) {
      final d = t.startAt;
      return d.year == day.year && d.month == day.month && d.day == day.day;
    }).toList()..sort((a, b) => a.startAt.compareTo(b.startAt));
  }

  // ── stats ──

  List<TimeTrack> get _periodTracks {
    final days = _visibleDays;
    return _userTracks.where((t) {
      final d = DateTime(t.startAt.year, t.startAt.month, t.startAt.day);
      return days.any((day) => day == d);
    }).toList();
  }

  double get _billableHours =>
      _periodTracks.where((t) => t.billable).fold(0, (s, t) => s + t.hours);
  double get _nonBillableHours =>
      _periodTracks.where((t) => !t.billable).fold(0, (s, t) => s + t.hours);
  double get _totalHours => _billableHours + _nonBillableHours;
  double get _billableAmount =>
      _periodTracks.fold(0, (s, t) => s + t.billableAmount);
  double get _billableRatio =>
      _totalHours > 0 ? _billableHours / _totalHours : 0;

  // ── helpers ──

  String _companyName(String id) =>
      widget.workspace.companies.where((c) => c.id == id).firstOrNull?.name ??
      '';

  String _projectName(String id) =>
      widget.workspace.projects.where((p) => p.id == id).firstOrNull?.name ??
      '';

  String _taskName(String id) =>
      widget.workspace.tasks.where((t) => t.id == id).firstOrNull?.name ?? '';

  String _formatHm(double h) {
    final total = (h * 60).round();
    final hh = total ~/ 60;
    final mm = total % 60;
    return '${hh}h${mm.toString().padLeft(2, '0')}';
  }

  String _formatTime(DateTime dt) =>
      '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';

  // ── build ──

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < 560;
        if (isMobile) return _buildMobileLayout();
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHeader(),
              const SizedBox(height: 14),
              _DesktopTimersPanel(
                timers: widget.desktopTimers,
                companyName: _companyName,
                projectName: _projectName,
                taskName: _taskName,
                onStartTimer: widget.onStartTimer,
                onStopTimer: widget.onStopTimer,
                onOpenPendingTimer: widget.onOpenPendingTimer,
                onDiscardPendingTimer: widget.onDiscardPendingTimer,
              ),
              const SizedBox(height: 14),
              _buildStatsBar(),
              const SizedBox(height: 14),
              Expanded(
                child: Container(
                  decoration: GussoniBrand.glassPanel(radius: 26, opacity: .9),
                  clipBehavior: Clip.antiAlias,
                  child: _buildDayList(),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ── Mobile layout ──────────────────────────────────────────────────────────

  Widget _buildMobileLayout() {
    final running = widget.desktopTimers.where((t) => t.isRunning).toList();
    final pending = widget.desktopTimers.where((t) => !t.isRunning).toList();
    final rangeLabel = _mode == _ViewMode.week
        ? '${DateFormat('dd MMM', 'it').format(_weekStart)}–${DateFormat('dd MMM', 'it').format(_weekEnd)}'
        : _mode == _ViewMode.day
        ? DateFormat('EEE d MMM', 'it').format(_anchor)
        : DateFormat('MMM yyyy', 'it').format(_anchor);

    final days = _visibleDays;

    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        // ── 1. Stats strip compatto ───────────────────────────────────────
        SliverToBoxAdapter(
          child: _MobileStatsStrip(
            totalHours: _totalHours,
            billableHours: _billableHours,
            nonBillableHours: _nonBillableHours,
            billableRatio: _billableRatio,
            rangeLabel: rangeLabel,
            formatHm: _formatHm,
          ),
        ),

        // ── 2. Nav compatto sticky ────────────────────────────────────────
        SliverPersistentHeader(
          pinned: true,
          delegate: _MobileNavDelegate(
            mode: _mode,
            rangeLabel: rangeLabel,
            onModeChanged: (m) => setState(() => _mode = m),
            onPrev: _prev,
            onNext: _next,
            onAdd: () => widget.onAddTimeTrack(date: _anchor),
          ),
        ),

        // ── 3. Timer pill (se running) ────────────────────────────────────
        if (running.isNotEmpty)
          SliverToBoxAdapter(
            child: _MobileRunningBanner(
              timers: running,
              companyName: _companyName,
              onStop: widget.onStopTimer,
            ),
          ),

        // ── 4. Timer da associare (slim) ──────────────────────────────────
        if (pending.isNotEmpty)
          SliverToBoxAdapter(
            child: _MobilePendingBanner(
              count: pending.length,
              onOpen: () => widget.onOpenPendingTimer(pending.first),
            ),
          ),

        // ── 5. CTA avvia timer ────────────────────────────────────────────
        if (running.isEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: GestureDetector(
                onTap: widget.onStartTimer,
                child: Container(
                  height: 58,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [GussoniBrand.primary, GussoniBrand.primaryHover],
                    ),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: GussoniBrand.primary.withValues(alpha: .30),
                        blurRadius: 14,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.play_arrow_rounded,
                        color: Colors.white,
                        size: 26,
                      ),
                      SizedBox(width: 10),
                      Text(
                        'Avvia timer',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

        // ── 6. Flat day list (iOS table style — nessun box nidificato) ────
        for (final day in days) ...[
          // Day header
          SliverToBoxAdapter(
            child: _MobileDayHeader(
              day: day,
              tracks: _tracksForDay(day),
              formatHm: _formatHm,
              onAdd: () => widget.onAddTimeTrack(date: day),
            ),
          ),
          // Track cells
          SliverList(
            delegate: SliverChildBuilderDelegate((context, i) {
              final tracks = _tracksForDay(day);
              if (i >= tracks.length) return null;
              final t = tracks[i];
              return _MobileTrackCell(
                track: t,
                companyName: _companyName(t.companyId),
                projectName: _projectName(t.projectId),
                taskName: _taskName(t.taskId),
                formatHm: _formatHm,
                isLast: i == tracks.length - 1,
                onEdit: () => widget.onAddTimeTrack(track: t),
                onDelete: () =>
                    widget.repository.deleteTimeTrack(widget.userId, t.id),
              );
            }, childCount: _tracksForDay(day).length),
          ),
        ],

        const SliverToBoxAdapter(child: SizedBox(height: 40)),
      ],
    );
  }

  // ── Header ──

  Widget _buildHeader() {
    final members = widget.teamInfo?.activeMembers ?? [];
    final rangeLabel = _mode == _ViewMode.week
        ? '${DateFormat('dd MMM', 'it').format(_weekStart)} – ${DateFormat('dd MMM yyyy', 'it').format(_weekEnd)}  Settimana $_weekNumber'
        : _mode == _ViewMode.day
        ? DateFormat('EEEE dd MMMM yyyy', 'it').format(_anchor)
        : DateFormat('MMMM yyyy', 'it').format(_anchor);

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 720;
        final nav = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              onPressed: _prev,
              icon: const Icon(Icons.chevron_left, size: 20),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            ),
            const SizedBox(width: 4),
            IconButton(
              onPressed: _next,
              icon: const Icon(Icons.chevron_right, size: 20),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            ),
          ],
        );
        final userFilter = members.isEmpty
            ? const SizedBox.shrink()
            : SizedBox(
                width: compact ? double.infinity : 180,
                child: DropdownButtonFormField<String?>(
                  value: _filterUserId,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                  ),
                  isDense: true,
                  items: [
                    DropdownMenuItem(
                      value: null,
                      child: Text(
                        _currentUserName(),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    ...members
                        .where((m) => m.userId != widget.userId)
                        .map(
                          (m) => DropdownMenuItem(
                            value: m.userId,
                            child: Text(
                              m.displayName,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                  ],
                  onChanged: (v) => setState(() => _filterUserId = v),
                ),
              );
        final addButton = FilledButton.icon(
          onPressed: () => widget.onAddTimeTrack(date: _anchor),
          icon: const Icon(Icons.add, size: 16),
          label: Text(compact ? 'Aggiungi' : 'Aggiungi segnatempo'),
          style: FilledButton.styleFrom(backgroundColor: GussoniBrand.primary),
        );

        return Padding(
          padding: EdgeInsets.fromLTRB(20, 14, compact ? 20 : 16, 14),
          child: compact
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        nav,
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            rangeLabel,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: GussoniBrand.textSecondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        _ViewToggle(
                          mode: _mode,
                          onChanged: (m) => setState(() => _mode = m),
                        ),
                        if (members.isNotEmpty)
                          SizedBox(
                            width: constraints.maxWidth < 420
                                ? (constraints.maxWidth - 40)
                                      .clamp(180.0, double.infinity)
                                      .toDouble()
                                : 190,
                            child: userFilter,
                          ),
                        addButton,
                      ],
                    ),
                  ],
                )
              : Row(
                  children: [
                    nav,
                    const SizedBox(width: 10),
                    Flexible(
                      child: Text(
                        rangeLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: GussoniBrand.textSecondary,
                        ),
                      ),
                    ),
                    const Spacer(),
                    _ViewToggle(
                      mode: _mode,
                      onChanged: (m) => setState(() => _mode = m),
                    ),
                    const SizedBox(width: 12),
                    userFilter,
                    const SizedBox(width: 12),
                    addButton,
                  ],
                ),
        );
      },
    );
  }

  String _currentUserName() {
    final me = widget.teamInfo?.activeMembers
        .where((m) => m.userId == widget.userId)
        .firstOrNull;
    return me?.displayName ?? 'Tu';
  }

  // ── Stats bar ──

  Widget _buildStatsBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
      decoration: GussoniBrand.glassPanel(radius: 24, opacity: .92),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final cards = <Widget>[
            _StatCard(
              minWidth: 260,
              child: Row(
                children: [
                  SizedBox(
                    width: 56,
                    height: 56,
                    child: CustomPaint(
                      painter: _DonutPainter(ratio: _billableRatio),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Incidenza fatturabile',
                        style: TextStyle(
                          fontSize: 11,
                          color: GussoniBrand.textMuted,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${(_billableRatio * 100).toStringAsFixed(0)}%',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: GussoniBrand.textPrimary,
                          height: 1,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            _StatItem(
              dot: GussoniBrand.textMuted,
              label: 'Non fatturabile',
              value: _formatHm(_nonBillableHours),
            ),
            _StatItem(
              dot: GussoniBrand.info,
              label: 'Fatturabile',
              value: _formatHm(_billableHours),
            ),
            if (_billableAmount > 0)
              _StatItem(
                label: 'Importo fatturabile',
                value: _eur.format(_billableAmount),
                valueColor: GussoniBrand.success,
              ),
            _StatCard(
              minWidth: 180,
              alignment: Alignment.centerLeft,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Tempo segnato',
                    style: TextStyle(
                      fontSize: 11,
                      color: GussoniBrand.textMuted,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _formatHm(_totalHours),
                    style: const TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w900,
                      color: GussoniBrand.textPrimary,
                      height: 1,
                    ),
                  ),
                ],
              ),
            ),
          ];

          return Wrap(
            spacing: 14,
            runSpacing: 14,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: cards,
          );
        },
      ),
    );
  }

  // ── Day list ──

  Widget _buildDayList() {
    final days = _visibleDays;
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 32),
      itemCount: days.length,
      itemBuilder: (context, i) => _DaySection(
        day: days[i],
        tracks: _tracksForDay(days[i]),
        companyName: _companyName,
        projectName: _projectName,
        taskName: _taskName,
        formatTime: _formatTime,
        formatHm: _formatHm,
        onAdd: () => widget.onAddTimeTrack(date: days[i]),
        onEdit: (t) => widget.onAddTimeTrack(track: t),
        onDelete: (t) => widget.repository.deleteTimeTrack(widget.userId, t.id),
      ),
    );
  }
}

class _DesktopTimersPanel extends StatelessWidget {
  const _DesktopTimersPanel({
    required this.timers,
    required this.companyName,
    required this.projectName,
    required this.taskName,
    required this.onStartTimer,
    required this.onStopTimer,
    required this.onOpenPendingTimer,
    required this.onDiscardPendingTimer,
  });

  final List<DesktopTimerEntry> timers;
  final String Function(String) companyName;
  final String Function(String) projectName;
  final String Function(String) taskName;
  final VoidCallback onStartTimer;
  final void Function(DesktopTimerEntry timer) onStopTimer;
  final void Function(DesktopTimerEntry timer) onOpenPendingTimer;
  final void Function(DesktopTimerEntry timer) onDiscardPendingTimer;

  @override
  Widget build(BuildContext context) {
    final running = timers.where((timer) => timer.isRunning).toList()
      ..sort((a, b) => b.startedAt.compareTo(a.startedAt));
    final pending = timers.where((timer) => !timer.isRunning).toList()
      ..sort((a, b) => b.stoppedAt!.compareTo(a.stoppedAt!));

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      decoration: GussoniBrand.glassPanel(radius: 24, opacity: .92),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: GussoniBrand.surface.withValues(alpha: .9),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: GussoniBrand.border.withValues(alpha: .9),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.play_circle_outline_rounded,
                      size: 16,
                      color: GussoniBrand.primary,
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'Timer',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: GussoniBrand.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '${running.length} attivi • ${pending.length} da associare',
                style: const TextStyle(
                  fontSize: 12,
                  color: GussoniBrand.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              FilledButton.icon(
                onPressed: onStartTimer,
                icon: const Icon(Icons.play_arrow_rounded, size: 16),
                label: const Text('Nuovo timer'),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (running.isNotEmpty)
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: running
                  .map(
                    (timer) => _TimerChipCard(
                      timer: timer,
                      label: _timerLabel(timer),
                      subtitle: _subtitle(timer),
                      onPrimary: () => onStopTimer(timer),
                      primaryLabel: 'Stop',
                      primaryIcon: Icons.stop_rounded,
                    ),
                  )
                  .toList(),
            ),
          if (running.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
              decoration: BoxDecoration(
                color: GussoniBrand.surface.withValues(alpha: .9),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: GussoniBrand.border.withValues(alpha: .88),
                ),
              ),
              child: const Text(
                'Nessun timer attivo. Avviane uno e lascia che il desktop raccolga il tempo per te.',
                style: TextStyle(
                  fontSize: 13,
                  color: GussoniBrand.textMuted,
                  height: 1.4,
                ),
              ),
            ),
          if (pending.isNotEmpty) ...[
            const SizedBox(height: 14),
            const Text(
              'Da associare',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: GussoniBrand.textSecondary,
                letterSpacing: .5,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: pending
                  .map(
                    (timer) => _TimerChipCard(
                      timer: timer,
                      label: _timerLabel(timer),
                      subtitle: _subtitle(timer),
                      onPrimary: () => onOpenPendingTimer(timer),
                      primaryLabel: 'Segna tempo',
                      primaryIcon: Icons.playlist_add_check_circle_rounded,
                      onSecondary: () => onDiscardPendingTimer(timer),
                    ),
                  )
                  .toList(),
            ),
          ],
        ],
      ),
    );
  }

  String _timerLabel(DesktopTimerEntry timer) {
    final task = timer.taskId.isNotEmpty ? taskName(timer.taskId) : '';
    if (task.isNotEmpty) return task;
    if (timer.name.trim().isNotEmpty) return timer.name.trim();
    return 'Timer libero';
  }

  String _subtitle(DesktopTimerEntry timer) {
    final company = timer.companyId.isNotEmpty
        ? companyName(timer.companyId)
        : '';
    final project = timer.projectId.isNotEmpty
        ? projectName(timer.projectId)
        : '';
    final start = DateFormat('HH:mm').format(timer.startedAt);
    final end = timer.stoppedAt != null
        ? DateFormat('HH:mm').format(timer.stoppedAt!)
        : 'in corso';
    final parts = <String>['$start - $end'];
    if (company.isNotEmpty) parts.add(company);
    if (project.isNotEmpty) parts.add(project);
    if (timer.description.trim().isNotEmpty)
      parts.add(timer.description.trim());
    return parts.join(' • ');
  }
}

class _TimerChipCard extends StatefulWidget {
  const _TimerChipCard({
    required this.timer,
    required this.label,
    required this.subtitle,
    required this.onPrimary,
    required this.primaryLabel,
    required this.primaryIcon,
    this.onSecondary,
  });

  final DesktopTimerEntry timer;
  final String label;
  final String subtitle;
  final VoidCallback onPrimary;
  final String primaryLabel;
  final IconData primaryIcon;
  final VoidCallback? onSecondary;

  @override
  State<_TimerChipCard> createState() => _TimerChipCardState();
}

class _TimerChipCardState extends State<_TimerChipCard> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _syncTicker();
  }

  @override
  void didUpdateWidget(covariant _TimerChipCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.timer.isRunning != widget.timer.isRunning) {
      _syncTicker();
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  void _syncTicker() {
    _ticker?.cancel();
    if (!widget.timer.isRunning) {
      return;
    }
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final timer = widget.timer;
    final elapsed = (timer.stoppedAt ?? DateTime.now()).difference(
      timer.startedAt,
    );
    final hours = elapsed.inHours;
    final minutes = elapsed.inMinutes.remainder(60);
    final seconds = elapsed.inSeconds.remainder(60);
    final durationLabel =
        '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';

    return Container(
      width: 276,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            GussoniBrand.glassSurfaceStrong.withValues(alpha: .92),
            GussoniBrand.surfaceSubtle.withValues(alpha: .82),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: GussoniBrand.border.withValues(alpha: .92)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  widget.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: GussoniBrand.textPrimary,
                  ),
                ),
              ),
              Text(
                durationLabel,
                style: TextStyle(
                  fontSize: 12,
                  fontFeatures: const [FontFeature.tabularFigures()],
                  color: timer.isRunning
                      ? GussoniBrand.primary
                      : GussoniBrand.textSecondary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            widget.subtitle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 11,
              color: GussoniBrand.textMuted,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              FilledButton.icon(
                onPressed: widget.onPrimary,
                icon: Icon(widget.primaryIcon, size: 16),
                label: Text(widget.primaryLabel),
              ),
              if (widget.onSecondary != null) ...[
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: widget.onSecondary,
                  child: const Text('Scarta'),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Day section ──────────────────────────────────────────────────────────────

class _DaySection extends StatefulWidget {
  const _DaySection({
    required this.day,
    required this.tracks,
    required this.companyName,
    required this.projectName,
    required this.taskName,
    required this.formatTime,
    required this.formatHm,
    required this.onAdd,
    required this.onEdit,
    required this.onDelete,
    this.isMobile = false,
  });

  final DateTime day;
  final List<TimeTrack> tracks;
  final String Function(String) companyName;
  final String Function(String) projectName;
  final String Function(String) taskName;
  final String Function(DateTime) formatTime;
  final String Function(double) formatHm;
  final VoidCallback onAdd;
  final void Function(TimeTrack) onEdit;
  final void Function(TimeTrack) onDelete;
  final bool isMobile;

  @override
  State<_DaySection> createState() => _DaySectionState();
}

class _DaySectionState extends State<_DaySection> {
  bool _expanded = true;

  bool get _isToday {
    final now = DateTime.now();
    return widget.day.year == now.year &&
        widget.day.month == now.month &&
        widget.day.day == now.day;
  }

  double get _totalHours => widget.tracks.fold(0, (s, t) => s + t.hours);

  @override
  void initState() {
    super.initState();
    // auto-expand today and days with entries
    _expanded = _isToday || widget.tracks.isNotEmpty;
  }

  @override
  Widget build(BuildContext context) {
    final dayLabel = DateFormat('EEE d MMM', 'it').format(widget.day);
    final firstTrack = widget.tracks.firstOrNull;
    final lastTrack = widget.tracks.lastOrNull;
    final rangeLabel = firstTrack != null && lastTrack != null
        ? '${widget.formatTime(firstTrack.startAt)} – ${widget.formatTime(lastTrack.endAt)}'
        : '—';

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: GussoniBrand.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: GussoniBrand.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Day header ──
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
              child: Row(
                children: [
                  Icon(
                    _expanded
                        ? Icons.keyboard_arrow_down
                        : Icons.keyboard_arrow_right,
                    size: 18,
                    color: GussoniBrand.textMuted,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    dayLabel,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: _isToday
                          ? GussoniBrand.primary
                          : GussoniBrand.textPrimary,
                    ),
                  ),
                  if (_isToday) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: GussoniBrand.primaryBg,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: GussoniBrand.primaryBorder),
                      ),
                      child: Text(
                        'Oggi',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: GussoniBrand.primary,
                        ),
                      ),
                    ),
                  ],
                  const Spacer(),
                  // time range + total
                  Text(
                    rangeLabel,
                    style: const TextStyle(
                      fontSize: 12,
                      color: GussoniBrand.textMuted,
                    ),
                  ),
                  const SizedBox(width: 16),
                  // progress bar area
                  SizedBox(
                    width: 100,
                    child: Column(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(2),
                          child: LinearProgressIndicator(
                            value: (_totalHours / 8).clamp(0, 1),
                            minHeight: 3,
                            backgroundColor: GussoniBrand.surfaceMuted,
                            color: _totalHours >= 8
                                ? GussoniBrand.success
                                : GussoniBrand.info,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${widget.formatHm(_totalHours)} / 8h00',
                          style: const TextStyle(
                            fontSize: 10,
                            color: GussoniBrand.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  // quick-add button
                  InkWell(
                    onTap: widget.onAdd,
                    borderRadius: BorderRadius.circular(6),
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        border: Border.all(color: GussoniBrand.border),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Icon(
                        Icons.timer_outlined,
                        size: 16,
                        color: GussoniBrand.textMuted,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Entries ──
          if (_expanded && widget.tracks.isNotEmpty) ...[
            const Divider(height: 1),
            ...widget.tracks.map(
              (t) => _TrackRow(
                track: t,
                companyName: widget.companyName(t.companyId),
                projectName: widget.projectName(t.projectId),
                taskName: widget.taskName(t.taskId),
                formatTime: widget.formatTime,
                formatHm: widget.formatHm,
                onEdit: () => widget.onEdit(t),
                onDelete: () => widget.onDelete(t),
              ),
            ),
          ],
          if (_expanded && widget.tracks.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
              child: Text(
                'Nessun segnatempo per questo giorno.',
                style: TextStyle(
                  fontSize: 12,
                  color: GussoniBrand.textDisabled,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ─── Track row ────────────────────────────────────────────────────────────────

class _TrackRow extends StatelessWidget {
  const _TrackRow({
    required this.track,
    required this.companyName,
    required this.projectName,
    required this.taskName,
    required this.formatTime,
    required this.formatHm,
    required this.onEdit,
    required this.onDelete,
  });

  final TimeTrack track;
  final String companyName;
  final String projectName;
  final String taskName;
  final String Function(DateTime) formatTime;
  final String Function(double) formatHm;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final hasTask = track.taskId.isNotEmpty && taskName.isNotEmpty;
    final hasProject = track.projectId.isNotEmpty && projectName.isNotEmpty;
    final hasCompany = track.companyId.isNotEmpty && companyName.isNotEmpty;

    return Container(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: GussoniBrand.borderSubtle)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          // ── Left: icon + context ──
          Icon(
            hasTask ? Icons.diamond_outlined : Icons.apartment_outlined,
            size: 14,
            color: hasTask ? GussoniBrand.gold : GussoniBrand.textMuted,
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (hasTask)
                  Text(
                    '$taskName${hasCompany ? ' • $companyName' : ''}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: GussoniBrand.primary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  )
                else if (hasProject)
                  Text(
                    '$projectName${hasCompany ? ' • $companyName' : ''}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: GussoniBrand.primary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  )
                else if (hasCompany)
                  Text(
                    companyName,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: GussoniBrand.primary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                if (track.tipo.isNotEmpty)
                  Text(
                    track.tipo,
                    style: const TextStyle(
                      fontSize: 11,
                      color: GussoniBrand.textMuted,
                    ),
                  ),
              ],
            ),
          ),
          // ── Description ──
          Expanded(
            flex: 4,
            child: Text(
              track.name.isNotEmpty ? track.name : track.description,
              style: const TextStyle(
                fontSize: 13,
                color: GussoniBrand.textPrimary,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 12),
          // ── Fatturabile badge ──
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(
              color: track.billable
                  ? const Color(0xFFEFF6FF)
                  : GussoniBrand.surfaceSubtle,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              track.billable ? 'Fatturabile' : 'Non fatturabile',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: track.billable
                    ? GussoniBrand.info
                    : GussoniBrand.textMuted,
              ),
            ),
          ),
          const SizedBox(width: 12),
          // ── Time range + duration ──
          Text(
            '${formatHm(track.hours)} (${formatTime(track.startAt)} – ${formatTime(track.endAt)})',
            style: const TextStyle(
              fontSize: 12,
              color: GussoniBrand.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 8),
          // ── Actions ──
          IconButton(
            onPressed: onEdit,
            icon: const Icon(
              Icons.edit_outlined,
              size: 15,
              color: GussoniBrand.textMuted,
            ),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            tooltip: 'Modifica',
          ),
          PopupMenuButton<String>(
            icon: const Icon(
              Icons.more_vert,
              size: 15,
              color: GussoniBrand.textMuted,
            ),
            iconSize: 15,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'edit',
                child: const Text('Modifica'),
                onTap: onEdit,
              ),
              PopupMenuItem(
                value: 'delete',
                onTap: onDelete,
                child: const Text(
                  'Elimina',
                  style: TextStyle(color: GussoniBrand.error),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── View toggle ─────────────────────────────────────────────────────────────

class _ViewToggle extends StatelessWidget {
  const _ViewToggle({required this.mode, required this.onChanged});
  final _ViewMode mode;
  final ValueChanged<_ViewMode> onChanged;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      border: Border.all(color: GussoniBrand.border),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _pill('Giorno', _ViewMode.day),
        _pill('Settimana', _ViewMode.week),
        _pill('Mese', _ViewMode.month),
      ],
    ),
  );

  Widget _pill(String label, _ViewMode m) {
    final active = mode == m;
    return GestureDetector(
      onTap: () => onChanged(m),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: active ? GussoniBrand.textPrimary : Colors.transparent,
          borderRadius: BorderRadius.circular(7),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: active ? Colors.white : GussoniBrand.textSecondary,
          ),
        ),
      ),
    );
  }
}

// ─── Stat item ───────────────────────────────────────────────────────────────

class _StatItem extends StatelessWidget {
  const _StatItem({
    required this.label,
    required this.value,
    this.dot,
    this.valueColor,
  });
  final String label;
  final String value;
  final Color? dot;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) => _StatCard(
    minWidth: 170,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            if (dot != null) ...[
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
              ),
              const SizedBox(width: 6),
            ],
            Flexible(
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 11,
                  color: GussoniBrand.textMuted,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          value,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: valueColor ?? GussoniBrand.textPrimary,
            height: 1,
          ),
        ),
      ],
    ),
  );
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.child,
    this.minWidth = 0,
    this.alignment = Alignment.centerLeft,
  });

  final Widget child;
  final double minWidth;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) => Container(
    constraints: BoxConstraints(minWidth: minWidth),
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    decoration: BoxDecoration(
      color: GussoniBrand.surface.withValues(alpha: .96),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: GussoniBrand.border.withValues(alpha: .9)),
    ),
    alignment: alignment,
    child: child,
  );
}

// ─── Mobile: hero card statistiche ───────────────────────────────────────────

class _MobileStatsStrip extends StatelessWidget {
  const _MobileStatsStrip({
    required this.totalHours,
    required this.billableHours,
    required this.nonBillableHours,
    required this.billableRatio,
    required this.rangeLabel,
    required this.formatHm,
  });
  final double totalHours;
  final double billableHours;
  final double nonBillableHours;
  final double billableRatio;
  final String rangeLabel;
  final String Function(double) formatHm;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
      decoration: BoxDecoration(
        // Nexora glass — identico ai DesktopWindow
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [GussoniBrand.glassSurfaceStrong, GussoniBrand.surfaceSubtle],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: GussoniBrand.border.withValues(alpha: .92)),
        boxShadow: [
          BoxShadow(
            color: GussoniBrand.primary.withValues(alpha: .08),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Ore totali — grande
          Text(
            formatHm(totalHours),
            style: const TextStyle(
              fontSize: 42,
              fontWeight: FontWeight.w900,
              color: GussoniBrand.textPrimary,
              height: 1,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'ore segnate · $rangeLabel',
            style: const TextStyle(
              fontSize: 13,
              color: GussoniBrand.textMuted,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 14),
          // Barra fatturabile
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: billableRatio.clamp(0.0, 1.0),
              minHeight: 6,
              backgroundColor: GussoniBrand.border,
              color: GussoniBrand.primary,
            ),
          ),
          const SizedBox(height: 12),
          // Stat row
          Row(
            children: [
              _StatPill(
                label: 'Fatturabile',
                value: formatHm(billableHours),
                color: GussoniBrand.primary,
              ),
              const SizedBox(width: 8),
              _StatPill(
                label: 'Non fatt.',
                value: formatHm(nonBillableHours),
                color: GussoniBrand.textMuted,
              ),
              const Spacer(),
              Text(
                '${(billableRatio * 100).toStringAsFixed(0)}%',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: GussoniBrand.primary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatPill extends StatelessWidget {
  const _StatPill({
    required this.label,
    required this.value,
    required this.color,
  });
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: .18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: color,
              height: 1.1,
            ),
          ),
          Text(
            label,
            style: const TextStyle(fontSize: 10, color: GussoniBrand.textMuted),
          ),
        ],
      ),
    );
  }
}

// ─── Mobile: timer attivo — card prominente ───────────────────────────────────

class _MobileRunningBanner extends StatelessWidget {
  const _MobileRunningBanner({
    required this.timers,
    required this.companyName,
    required this.onStop,
  });
  final List<DesktopTimerEntry> timers;
  final String Function(String) companyName;
  final void Function(DesktopTimerEntry) onStop;

  @override
  Widget build(BuildContext context) {
    final t = timers.first;
    final company = companyName(t.companyId ?? '');

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            GussoniBrand.primaryBg,
            GussoniBrand.primary.withValues(alpha: .06),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: GussoniBrand.primaryBorder),
        boxShadow: [
          BoxShadow(
            color: GussoniBrand.primary.withValues(alpha: .14),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Badge IN CORSO
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: GussoniBrand.primary,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                timers.length == 1
                    ? 'IN CORSO'
                    : '${timers.length} TIMER ATTIVI',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.6,
                  color: GussoniBrand.primary,
                ),
              ),
              if (company.isNotEmpty) ...[
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '· $company',
                    style: const TextStyle(
                      fontSize: 11,
                      color: GussoniBrand.textMuted,
                      fontWeight: FontWeight.w500,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          // Ticker grande
          Center(
            child: _TimerTicker(
              timer: t,
              style: const TextStyle(
                fontSize: 44,
                fontWeight: FontWeight.w900,
                color: GussoniBrand.textPrimary,
                fontFeatures: [FontFeature.tabularFigures()],
                height: 1,
                letterSpacing: -1,
              ),
            ),
          ),
          const SizedBox(height: 16),
          // Stop button full-width
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => onStop(t),
              icon: const Icon(Icons.stop_rounded, size: 18),
              label: const Text(
                'Stop',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: GussoniBrand.primary,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 46),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MobilePendingBanner extends StatelessWidget {
  const _MobilePendingBanner({required this.count, required this.onOpen});
  final int count;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onOpen,
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: GussoniBrand.goldBg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: GussoniBrand.gold.withValues(alpha: .35)),
        ),
        child: Row(
          children: [
            Icon(
              Icons.pause_circle_outline_rounded,
              size: 15,
              color: GussoniBrand.gold,
            ),
            const SizedBox(width: 8),
            Text(
              '$count timer da associare  →',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: GussoniBrand.gold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Mobile: day header flat ──────────────────────────────────────────────────

class _MobileDayHeader extends StatelessWidget {
  const _MobileDayHeader({
    required this.day,
    required this.tracks,
    required this.formatHm,
    required this.onAdd,
  });
  final DateTime day;
  final List<TimeTrack> tracks;
  final String Function(double) formatHm;
  final VoidCallback onAdd;

  bool get _isToday {
    final n = DateTime.now();
    return day.year == n.year && day.month == n.month && day.day == n.day;
  }

  double get _total => tracks.fold(0, (s, t) => s + t.hours);

  @override
  Widget build(BuildContext context) {
    final label = _isToday
        ? 'OGGI'
        : DateFormat('EEE d MMM', 'it').format(day).toUpperCase();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 18, 12, 6),
          child: Row(
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.6,
                  color: _isToday
                      ? GussoniBrand.primary
                      : GussoniBrand.textMuted,
                ),
              ),
              if (_isToday) ...[
                const SizedBox(width: 6),
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: GussoniBrand.primary,
                    shape: BoxShape.circle,
                  ),
                ),
              ],
              const Spacer(),
              if (_total > 0)
                Text(
                  formatHm(_total),
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: GussoniBrand.textSecondary,
                  ),
                ),
              const SizedBox(width: 6),
              GestureDetector(
                onTap: onAdd,
                child: const Icon(
                  Icons.add_circle_outline_rounded,
                  size: 18,
                  color: GussoniBrand.textMuted,
                ),
              ),
            ],
          ),
        ),
        if (tracks.isEmpty)
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: Text(
              'Nessun segnatempo',
              style: TextStyle(fontSize: 12, color: GussoniBrand.textDisabled),
            ),
          )
        else
          Divider(height: 1, color: GussoniBrand.borderSubtle),
      ],
    );
  }
}

// ─── Mobile: track cell flat (iOS table style) ────────────────────────────────

class _MobileTrackCell extends StatelessWidget {
  const _MobileTrackCell({
    required this.track,
    required this.companyName,
    required this.projectName,
    required this.taskName,
    required this.formatHm,
    required this.isLast,
    required this.onEdit,
    required this.onDelete,
  });
  final TimeTrack track;
  final String companyName;
  final String projectName;
  final String taskName;
  final String Function(double) formatHm;
  final bool isLast;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  String get _contextLabel {
    if (taskName.isNotEmpty) {
      return companyName.isNotEmpty ? '$taskName · $companyName' : taskName;
    }
    if (projectName.isNotEmpty) {
      return companyName.isNotEmpty
          ? '$projectName · $companyName'
          : projectName;
    }
    return companyName.isNotEmpty ? companyName : '—';
  }

  String get _secondLine {
    final d = track.name.isNotEmpty ? track.name : track.description;
    return d.trim();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        InkWell(
          onTap: onEdit,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Dot billable
                Container(
                  width: 7,
                  height: 7,
                  margin: const EdgeInsets.only(right: 10),
                  decoration: BoxDecoration(
                    color: track.billable
                        ? GussoniBrand.primary
                        : GussoniBrand.border,
                    shape: BoxShape.circle,
                  ),
                ),
                // Context + description
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _contextLabel,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: GussoniBrand.textPrimary,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (_secondLine.isNotEmpty)
                        Text(
                          _secondLine,
                          style: const TextStyle(
                            fontSize: 11,
                            color: GussoniBrand.textMuted,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                // Duration
                Text(
                  formatHm(track.hours),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: GussoniBrand.textSecondary,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
                // Context menu
                PopupMenuButton<String>(
                  icon: const Icon(
                    Icons.more_vert,
                    size: 16,
                    color: GussoniBrand.textMuted,
                  ),
                  iconSize: 16,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 32,
                  ),
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: 'edit',
                      onTap: onEdit,
                      child: const Text('Modifica'),
                    ),
                    PopupMenuItem(
                      value: 'delete',
                      onTap: onDelete,
                      child: const Text(
                        'Elimina',
                        style: TextStyle(color: GussoniBrand.error),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        if (!isLast) const Divider(height: 1, indent: 33, endIndent: 0),
      ],
    );
  }
}

// ─── Mobile stats card ───────────────────────────────────────────────────────

class _MobileStatsCard extends StatelessWidget {
  const _MobileStatsCard({
    required this.totalHours,
    required this.billableHours,
    required this.nonBillableHours,
    required this.billableRatio,
    required this.rangeLabel,
    required this.formatHm,
  });

  final double totalHours;
  final double billableHours;
  final double nonBillableHours;
  final double billableRatio;
  final String rangeLabel;
  final String Function(double) formatHm;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
      decoration: BoxDecoration(
        // Nexora glass — stesso stile dei pannelli desktop
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [GussoniBrand.glassSurfaceStrong, GussoniBrand.surfaceSubtle],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: GussoniBrand.border.withValues(alpha: .92)),
        boxShadow: [
          BoxShadow(
            color: GussoniBrand.primary.withValues(alpha: .10),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          // Activity ring + totale al centro
          SizedBox(
            width: 120,
            height: 120,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CustomPaint(
                  size: const Size(120, 120),
                  painter: _ActivityRingPainter(
                    ratio: billableRatio,
                    color: GussoniBrand.primary,
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      formatHm(totalHours),
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                        color: GussoniBrand.textPrimary,
                        height: 1,
                      ),
                    ),
                    const SizedBox(height: 3),
                    const Text(
                      'ore totali',
                      style: TextStyle(
                        fontSize: 10,
                        color: GussoniBrand.textMuted,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          // Stat row
          IntrinsicHeight(
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    children: [
                      Text(
                        formatHm(billableHours),
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: GussoniBrand.primary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      const Text(
                        'Fatturabile',
                        style: TextStyle(
                          fontSize: 11,
                          color: GussoniBrand.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  width: 1,
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  color: GussoniBrand.borderSubtle,
                ),
                Expanded(
                  child: Column(
                    children: [
                      Text(
                        formatHm(nonBillableHours),
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: GussoniBrand.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      const Text(
                        'Non fatt.',
                        style: TextStyle(
                          fontSize: 11,
                          color: GussoniBrand.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  width: 1,
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  color: GussoniBrand.borderSubtle,
                ),
                Expanded(
                  child: Column(
                    children: [
                      Text(
                        '${(billableRatio * 100).toStringAsFixed(0)}%',
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: GussoniBrand.success,
                        ),
                      ),
                      const SizedBox(height: 2),
                      const Text(
                        'Fatt. ratio',
                        style: TextStyle(
                          fontSize: 11,
                          color: GussoniBrand.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Activity ring (iOS style) ────────────────────────────────────────────────

class _ActivityRingPainter extends CustomPainter {
  const _ActivityRingPainter({required this.ratio, required this.color});
  final double ratio;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    const strokeW = 10.0;
    final radius = cx - strokeW / 2;

    final track = Paint()
      ..color = color.withValues(alpha: .12)
      ..strokeWidth = strokeW
      ..style = PaintingStyle.stroke;

    final arc = Paint()
      ..color = color
      ..strokeWidth = strokeW
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(Offset(cx, cy), radius, track);
    if (ratio > 0) {
      canvas.drawArc(
        Rect.fromCircle(center: Offset(cx, cy), radius: radius),
        -math.pi / 2,
        2 * math.pi * ratio.clamp(0.0, 1.0),
        false,
        arc,
      );
    }
  }

  @override
  bool shouldRepaint(_ActivityRingPainter old) => old.ratio != ratio;
}

// ─── Mobile nav delegate (sticky) ────────────────────────────────────────────

class _MobileNavDelegate extends SliverPersistentHeaderDelegate {
  const _MobileNavDelegate({
    required this.mode,
    required this.rangeLabel,
    required this.onModeChanged,
    required this.onPrev,
    required this.onNext,
    required this.onAdd,
  });

  final _ViewMode mode;
  final String rangeLabel;
  final ValueChanged<_ViewMode> onModeChanged;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final VoidCallback onAdd;

  @override
  double get minExtent => 44;
  @override
  double get maxExtent => 44;

  @override
  bool shouldRebuild(covariant _MobileNavDelegate old) =>
      old.mode != mode || old.rangeLabel != rangeLabel;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return Container(
      color: GussoniBrand.surface,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: GussoniBrand.border)),
      ),
      child: Row(
        children: [
          // G / S / M — compatto, nessun contenitore esterno
          Container(
            height: 28,
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              color: GussoniBrand.surfaceSubtle,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: GussoniBrand.border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final m in _ViewMode.values)
                  GestureDetector(
                    onTap: () => onModeChanged(m),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 140),
                      width: 26,
                      decoration: BoxDecoration(
                        color: mode == m
                            ? GussoniBrand.primary
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        switch (m) {
                          _ViewMode.day => 'G',
                          _ViewMode.week => 'S',
                          _ViewMode.month => 'M',
                        },
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: mode == m
                              ? Colors.white
                              : GussoniBrand.textMuted,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Prev
          GestureDetector(
            onTap: onPrev,
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 4),
              child: Icon(
                Icons.chevron_left,
                size: 18,
                color: GussoniBrand.textMuted,
              ),
            ),
          ),
          // Range label
          Expanded(
            child: Text(
              rangeLabel,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: GussoniBrand.textPrimary,
              ),
            ),
          ),
          // Next
          GestureDetector(
            onTap: onNext,
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 4),
              child: Icon(
                Icons.chevron_right,
                size: 18,
                color: GussoniBrand.textMuted,
              ),
            ),
          ),
          const SizedBox(width: 4),
          // Add
          GestureDetector(
            onTap: onAdd,
            child: Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                color: GussoniBrand.primary,
                borderRadius: BorderRadius.circular(7),
              ),
              child: const Icon(Icons.add, size: 16, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Mobile timer section ─────────────────────────────────────────────────────

class _MobileTimerSection extends StatelessWidget {
  const _MobileTimerSection({
    required this.timers,
    required this.companyName,
    required this.projectName,
    required this.taskName,
    required this.onStart,
    required this.onStop,
    required this.onOpen,
    required this.onDiscard,
  });

  final List<DesktopTimerEntry> timers;
  final String Function(String) companyName;
  final String Function(String) projectName;
  final String Function(String) taskName;
  final VoidCallback onStart;
  final void Function(DesktopTimerEntry) onStop;
  final void Function(DesktopTimerEntry) onOpen;
  final void Function(DesktopTimerEntry) onDiscard;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            children: [
              const Text(
                'TIMER',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.0,
                  color: GussoniBrand.textMuted,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Container(height: 1, color: GussoniBrand.borderSubtle),
              ),
              const SizedBox(width: 10),
              GestureDetector(
                onTap: onStart,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.add_circle_outline_rounded,
                      size: 14,
                      color: GussoniBrand.primary,
                    ),
                    SizedBox(width: 4),
                    Text(
                      'Nuovo',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: GussoniBrand.primary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        for (final timer in timers)
          _MobileTimerCard(
            timer: timer,
            companyName: companyName(timer.companyId ?? ''),
            projectName: projectName(timer.projectId ?? ''),
            onPrimary: timer.isRunning
                ? () => onStop(timer)
                : () => onOpen(timer),
            onDiscard: timer.isRunning ? null : () => onDiscard(timer),
          ),
      ],
    );
  }
}

class _MobileTimerCard extends StatelessWidget {
  const _MobileTimerCard({
    required this.timer,
    required this.companyName,
    required this.projectName,
    required this.onPrimary,
    this.onDiscard,
  });

  final DesktopTimerEntry timer;
  final String companyName;
  final String projectName;
  final VoidCallback onPrimary;
  final VoidCallback? onDiscard;

  @override
  Widget build(BuildContext context) {
    final isRunning = timer.isRunning;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isRunning
              ? [GussoniBrand.glassSurfaceStrong, GussoniBrand.primaryBg]
              : [GussoniBrand.glassSurfaceStrong, GussoniBrand.surfaceSubtle],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isRunning ? GussoniBrand.primaryBorder : GussoniBrand.border,
        ),
        boxShadow: [
          if (isRunning)
            BoxShadow(
              color: GussoniBrand.primary.withValues(alpha: .12),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
        ],
      ),
      child: Row(
        children: [
          // Pulsing dot (running) o pausa
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: isRunning
                  ? GussoniBrand.primary.withValues(alpha: .12)
                  : GussoniBrand.surfaceSubtle,
              shape: BoxShape.circle,
            ),
            child: Icon(
              isRunning ? Icons.play_arrow_rounded : Icons.pause_rounded,
              color: isRunning ? GussoniBrand.primary : GussoniBrand.textMuted,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          // Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  companyName.isEmpty ? 'Nessuna società' : companyName,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: isRunning
                        ? GussoniBrand.primary
                        : GussoniBrand.textPrimary,
                  ),
                ),
                if (projectName.isNotEmpty)
                  Text(
                    projectName,
                    style: const TextStyle(
                      fontSize: 11,
                      color: GussoniBrand.textMuted,
                    ),
                  ),
              ],
            ),
          ),
          // Live ticker
          _TimerTicker(
            timer: timer,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: isRunning
                  ? GussoniBrand.primary
                  : GussoniBrand.textPrimary,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(width: 10),
          // Action
          GestureDetector(
            onTap: onPrimary,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: isRunning
                    ? GussoniBrand.primary
                    : GussoniBrand.primaryBg,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                isRunning ? 'Stop' : 'Segna',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: isRunning ? Colors.white : GussoniBrand.primary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Mobile stat chip ────────────────────────────────────────────────────────

class _MobileStatChip extends StatelessWidget {
  const _MobileStatChip({
    required this.label,
    required this.value,
    required this.color,
  });
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w900,
            color: color,
          ),
        ),
        Text(
          label,
          style: const TextStyle(fontSize: 11, color: GussoniBrand.textMuted),
        ),
      ],
    );
  }
}

// ─── Timer ticker ─────────────────────────────────────────────────────────────

class _TimerTicker extends StatefulWidget {
  const _TimerTicker({required this.timer, required this.style});
  final DesktopTimerEntry timer;
  final TextStyle style;

  @override
  State<_TimerTicker> createState() => _TimerTickerState();
}

class _TimerTickerState extends State<_TimerTicker> {
  Timer? _tick;
  Duration _elapsed = Duration.zero;

  @override
  void initState() {
    super.initState();
    _update();
    if (widget.timer.isRunning) {
      _tick = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(_update);
      });
    }
  }

  void _update() {
    if (widget.timer.isRunning) {
      _elapsed = DateTime.now().difference(widget.timer.startedAt);
    } else {
      _elapsed = (widget.timer.stoppedAt ?? DateTime.now()).difference(
        widget.timer.startedAt,
      );
    }
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  String _format(Duration d) {
    final h = d.inHours.toString().padLeft(2, '0');
    final m = (d.inMinutes % 60).toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  @override
  Widget build(BuildContext context) =>
      Text(_format(_elapsed), style: widget.style);
}

// ─── Donut painter ───────────────────────────────────────────────────────────

class _DonutPainter extends CustomPainter {
  const _DonutPainter({required this.ratio});
  final double ratio;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final r = math.min(cx, cy) - 4;
    const strokeW = 7.0;
    const startAngle = -math.pi / 2;

    final bgPaint = Paint()
      ..color = GussoniBrand.surfaceMuted
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeW
      ..strokeCap = StrokeCap.round;

    final fgPaint = Paint()
      ..color = GussoniBrand.info
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeW
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(Offset(cx, cy), r, bgPaint);
    if (ratio > 0) {
      canvas.drawArc(
        Rect.fromCircle(center: Offset(cx, cy), radius: r),
        startAngle,
        2 * math.pi * ratio,
        false,
        fgPaint,
      );
    }
  }

  @override
  bool shouldRepaint(_DonutPainter old) => old.ratio != ratio;
}
