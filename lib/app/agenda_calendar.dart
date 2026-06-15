// ignore_for_file: public_member_api_docs
import 'dart:math';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:intl/intl.dart';

import '../brand_config.dart';
import '../data/firestore_workspace_repository.dart';
import '../data/team_repository.dart';
import '../models/domain_models.dart';

// ─── Constants ────────────────────────────────────────────────────────────────

const double _kHourH = 60.0; // px per ora
const int _kFirstHour = 6;
const int _kLastHour = 24;
const double _kHourLabelW = 48.0;
const double _kMinSlotH = 28.0;

double get _kGridH => (_kLastHour - _kFirstHour) * _kHourH;

// ─── View mode ────────────────────────────────────────────────────────────────

enum AgendaViewMode { giorno, settimana, mese, team }

// ─── Public widget ────────────────────────────────────────────────────────────

class AgendaCalendar extends StatefulWidget {
  const AgendaCalendar({
    super.key,
    required this.workspace,
    required this.currentUserId,
    required this.visibleWeekStart,
    required this.onShiftWeek,
    required this.onScheduleTask,
    required this.onMoveSlot,
    required this.onResizeSlot,
    required this.onDeleteTimelineSlot,
    required this.onEditTask,
    required this.onLogTime,
    required this.onToggleTaskDone,
    required this.onAddTask,
    required this.onAddTaskForSchedule,
    required this.selectedPlanningTaskId,
    required this.onSelectedPlanningTaskIdChanged,
    this.members = const [],
    this.selectedMemberId,
    this.onMemberChanged,
    this.memberSlots = const {},
  });

  final WorkspaceSnapshot workspace;
  final String currentUserId;
  final DateTime visibleWeekStart;
  final void Function(int delta) onShiftWeek;
  final Future<void> Function(WorkTask, DateTime, double, double)
  onScheduleTask;
  final Future<void> Function(TimelineSlot, DateTime, double) onMoveSlot;
  final Future<void> Function(TimelineSlot, double) onResizeSlot;
  final Future<void> Function(TimelineSlot) onDeleteTimelineSlot;
  final void Function(WorkTask) onEditTask;
  final void Function(WorkTask) onLogTime;
  final Future<void> Function(WorkTask, bool) onToggleTaskDone;
  final VoidCallback onAddTask;
  final Future<void> Function(DateTime, double, double) onAddTaskForSchedule;
  final String? selectedPlanningTaskId;
  final ValueChanged<String?> onSelectedPlanningTaskIdChanged;
  final List<TeamMember> members;
  final String? selectedMemberId;
  final ValueChanged<String?>? onMemberChanged;
  // memberId → slots (for Team view)
  final Map<String, List<TimelineSlot>> memberSlots;

  @override
  State<AgendaCalendar> createState() => _AgendaCalendarState();
}

class _AgendaCalendarState extends State<AgendaCalendar> {
  AgendaViewMode _mode = AgendaViewMode.settimana;
  DateTime _selectedDay = DateTime.now();
  late final ScrollController _scrollCtrl;

  // Drawing state (drag-to-create slot)
  DateTime? _drawDay;
  double? _drawStartDy;
  double? _drawCurDy;
  final Map<String, double> _previewSlotHeights = {};
  _SlotDragPreview? _slotDragPreview;

  @override
  void initState() {
    super.initState();
    _scrollCtrl = ScrollController();
    // Scroll to ora di lavoro (9:00)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final target = (9 - _kFirstHour) * _kHourH - 8;
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.jumpTo(
          target.clamp(0.0, _scrollCtrl.position.maxScrollExtent),
        );
      }
    });
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  // ─── Helpers ──────────────────────────────────────────────────────────────

  List<DateTime> get _weekDays =>
      List.generate(7, (i) => widget.visibleWeekStart.add(Duration(days: i)));

  List<DateTime> get _visibleDays {
    switch (_mode) {
      case AgendaViewMode.giorno:
        return [_selectedDay];
      case AgendaViewMode.mese:
        return _weekDays;
      default:
        return _weekDays;
    }
  }

  List<TimelineSlot> _slotsForDay(DateTime day) {
    final own = widget.workspace.plannedSlots
        .where((s) => _sameDay(s.date, day))
        .toList();
    if (_mode == AgendaViewMode.team) {
      for (final slots in widget.memberSlots.values) {
        own.addAll(slots.where((s) => _sameDay(s.date, day)));
      }
    }
    return own;
  }

  List<WorkTask> _tasksForDay(DateTime day) => widget.workspace.tasks
      .where((t) => _sameDay(t.startDate, day) || _sameDay(t.deadline, day))
      .toList();

  WorkTask? _taskById(String id) =>
      widget.workspace.tasks.where((t) => t.id == id).firstOrNull;

  double _startHourFrom(double dy) => (_kFirstHour + dy / _kHourH).clamp(
    _kFirstHour.toDouble(),
    (_kLastHour - 0.5).toDouble(),
  );

  double _durationFrom(double startDy, double endDy) {
    final s = _startHourFrom(min(startDy, endDy));
    final e = _startHourFrom(max(startDy, endDy)) + 0.5;
    final rounded = ((e - s) * 2).ceil() / 2.0;
    return rounded.clamp(0.5, 12.0).toDouble();
  }

  bool get _isDrawing =>
      _drawDay != null && _drawStartDy != null && _drawCurDy != null;

  String get _weekLabelText {
    final end = widget.visibleWeekStart.add(const Duration(days: 6));
    final fmt = DateFormat('d');
    final mFmt = DateFormat('MMMM', 'it_IT');
    final wn = _isoWeekNumber(widget.visibleWeekStart);
    return 'Settimana $wn: ${fmt.format(widget.visibleWeekStart)} - ${fmt.format(end)} ${_capitalize(mFmt.format(end))}';
  }

  String _dayLabelText(DateTime d) =>
      '${_weekdayAbbr(d.weekday)} ${d.day}/${d.month}';

  Color _slotColor(TimelineSlot slot) {
    if (_mode == AgendaViewMode.team) {
      // colore per membro
      for (final entry in widget.memberSlots.entries) {
        if (entry.value.any((s) => s.id == slot.id)) {
          return _memberColor(entry.key);
        }
      }
    }
    final task = _taskById(slot.taskId);
    return task != null ? _taskColor(task) : const Color(0xFF4A6B8A);
  }

  String _slotLabel(TimelineSlot slot) {
    final task = _taskById(slot.taskId);
    if (task == null) return slot.taskId;
    final company = widget.workspace.companies
        .where((c) => c.id == task.companyId)
        .firstOrNull;
    final parts = <String>[];
    if (company != null)
      parts.add(
        company.name.length > 1
            ? company.name.substring(0, 1).toUpperCase()
            : company.name,
      );
    parts.add(task.name);
    return parts.join(' · ');
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 640) {
          return _buildMobileCalendar();
        }
        return _buildDesktopCalendar();
      },
    );
  }

  Widget _buildDesktopCalendar() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFFFCFBF9).withValues(alpha: .96),
            const Color(0xFFF6F4F1).withValues(alpha: .92),
            const Color(0xFFF6E9E3).withValues(alpha: .90),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: .82)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x12000000),
            blurRadius: 24,
            offset: Offset(0, 16),
          ),
        ],
      ),
      child: Column(
        children: [
          _buildTopBar(),
          Divider(height: 1, color: GussoniBrand.border.withValues(alpha: .72)),
          if (_mode == AgendaViewMode.mese)
            Expanded(child: _buildMonthView())
          else
            Expanded(child: _buildCalendarGrid()),
        ],
      ),
    );
  }

  Widget _buildMobileCalendar() {
    final now = DateTime.now();
    final selectedSlots = _slotsForDay(_selectedDay)
      ..sort((a, b) => a.startHour.compareTo(b.startHour));
    final selectedTasks = _tasksForDay(_selectedDay);
    final plannedHours = selectedSlots.fold<double>(
      0,
      (sum, slot) => sum + slot.plannedHours,
    );
    final week = _weekDays;

    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFFCFAF7), Color(0xFFF0E9E1), Color(0xFFF6E9E3)],
        ),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            DateFormat(
                              'MMMM yyyy',
                              'it_IT',
                            ).format(_selectedDay).toUpperCase(),
                            style: TextStyle(
                              color: GussoniBrand.textMuted.withValues(
                                alpha: .86,
                              ),
                              fontSize: 11,
                              fontWeight: FontWeight.w900,
                              letterSpacing: .6,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            DateFormat('EEEE d', 'it_IT').format(_selectedDay),
                            style: const TextStyle(
                              color: GussoniBrand.textPrimary,
                              fontSize: 30,
                              fontWeight: FontWeight.w900,
                              height: 1.04,
                            ),
                          ),
                        ],
                      ),
                    ),
                    _mobileIconButton(
                      Icons.chevron_left_rounded,
                      () => setState(
                        () => _selectedDay = _selectedDay.subtract(
                          const Duration(days: 1),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _mobileIconButton(
                      Icons.chevron_right_rounded,
                      () => setState(
                        () => _selectedDay = _selectedDay.add(
                          const Duration(days: 1),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _mobileIconButton(Icons.add_rounded, widget.onAddTask),
                  ],
                ),
                const SizedBox(height: 14),
                SizedBox(
                  height: 82,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: week.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 9),
                    itemBuilder: (context, index) {
                      final day = week[index];
                      final selected = _sameDay(day, _selectedDay);
                      final today = _sameDay(day, now);
                      final slots = _slotsForDay(day);
                      return GestureDetector(
                        onTap: () => setState(() => _selectedDay = day),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 140),
                          width: 54,
                          padding: const EdgeInsets.symmetric(vertical: 9),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(22),
                            gradient: selected
                                ? const LinearGradient(
                                    colors: [
                                      Color(0xFF5B1205),
                                      Color(0xFFB08948),
                                    ],
                                  )
                                : null,
                            color: selected
                                ? null
                                : Colors.white.withValues(alpha: .66),
                            border: Border.all(
                              color: selected
                                  ? Colors.white.withValues(alpha: .70)
                                  : Colors.white,
                            ),
                            boxShadow: selected
                                ? [
                                    BoxShadow(
                                      color: GussoniBrand.primary.withValues(
                                        alpha: .24,
                                      ),
                                      blurRadius: 18,
                                      offset: const Offset(0, 10),
                                    ),
                                  ]
                                : null,
                          ),
                          child: Column(
                            children: [
                              Text(
                                _weekdayAbbr(day.weekday).toUpperCase(),
                                style: TextStyle(
                                  color: selected
                                      ? Colors.white.withValues(alpha: .78)
                                      : GussoniBrand.textMuted,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                '${day.day}',
                                style: TextStyle(
                                  color: selected
                                      ? Colors.white
                                      : GussoniBrand.textPrimary,
                                  fontSize: 20,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const Spacer(),
                              Container(
                                width: slots.isNotEmpty ? 18 : 5,
                                height: 5,
                                decoration: BoxDecoration(
                                  color: today
                                      ? const Color(0xFFA8332C)
                                      : selected
                                      ? Colors.white
                                      : GussoniBrand.textDisabled,
                                  borderRadius: BorderRadius.circular(999),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _MobileCalendarMetric(
                        label: 'Pianificato',
                        value: '${plannedHours.toStringAsFixed(1)} h',
                        icon: Icons.schedule_rounded,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _MobileCalendarMetric(
                        label: 'Task',
                        value: '${selectedTasks.length}',
                        icon: Icons.check_circle_rounded,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: selectedSlots.isEmpty && selectedTasks.isEmpty
                ? _MobileCalendarEmpty(onAdd: widget.onAddTask)
                : ListView(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 22),
                    children: [
                      if (selectedSlots.isNotEmpty) ...[
                        const _MobileCalendarSectionTitle('Programma'),
                        const SizedBox(height: 8),
                        for (final slot in selectedSlots)
                          _MobileSlotCard(
                            slot: slot,
                            label: _slotLabel(slot),
                            color: _slotColor(slot),
                            onTap: () {
                              final task = _taskById(slot.taskId);
                              if (task != null) widget.onEditTask(task);
                            },
                          ),
                        const SizedBox(height: 18),
                      ],
                      if (selectedTasks.isNotEmpty) ...[
                        const _MobileCalendarSectionTitle('Task del giorno'),
                        const SizedBox(height: 8),
                        for (final task in selectedTasks)
                          _MobileTaskCard(
                            task: task,
                            onTap: () => widget.onEditTask(task),
                            onDone: () => widget.onToggleTaskDone(
                              task,
                              task.status != TaskStatus.done,
                            ),
                          ),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _mobileIconButton(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: .82),
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: Colors.white),
          boxShadow: const [
            BoxShadow(
              color: Color(0x10000000),
              blurRadius: 12,
              offset: Offset(0, 7),
            ),
          ],
        ),
        child: Icon(icon, color: GussoniBrand.textPrimary, size: 22),
      ),
    );
  }

  // ─── Top bar ──────────────────────────────────────────────────────────────

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          // Navigation
          _iconBtn(Icons.chevron_left, () {
            if (_mode == AgendaViewMode.giorno) {
              setState(
                () => _selectedDay = _selectedDay.subtract(
                  const Duration(days: 1),
                ),
              );
            } else {
              widget.onShiftWeek(-1);
            }
          }),
          const SizedBox(width: 4),
          _iconBtn(Icons.chevron_right, () {
            if (_mode == AgendaViewMode.giorno) {
              setState(
                () => _selectedDay = _selectedDay.add(const Duration(days: 1)),
              );
            } else {
              widget.onShiftWeek(1);
            }
          }),
          const SizedBox(width: 12),
          Text(
            _mode == AgendaViewMode.giorno
                ? '${_weekdayAbbr(_selectedDay.weekday).toUpperCase()} ${_selectedDay.day}/${_selectedDay.month}/${_selectedDay.year}'
                : _weekLabelText,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: GussoniBrand.textSecondary,
            ),
          ),
          const Spacer(),
          // View mode tabs
          _viewTabsRow(),
          const SizedBox(width: 12),
          // Person selector
          if (widget.members.isNotEmpty) _buildMemberSelector(),
          const SizedBox(width: 8),
          // Add task
          IconButton(
            icon: const Icon(Icons.add_task_outlined, size: 20),
            tooltip: 'Aggiungi task',
            onPressed: widget.onAddTask,
          ),
        ],
      ),
    );
  }

  Widget _viewTabsRow() {
    final modes = [
      (AgendaViewMode.giorno, 'Giorno'),
      (AgendaViewMode.settimana, 'Settimana'),
      (AgendaViewMode.mese, 'Mese'),
      if (widget.members.isNotEmpty) (AgendaViewMode.team, 'Team'),
    ];
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFFF6F4F1).withValues(alpha: .92),
            const Color(0xFFF5EDDE).withValues(alpha: .86),
          ],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: .72)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: modes.map((entry) {
          final sel = _mode == entry.$1;
          return GestureDetector(
            onTap: () => setState(() => _mode = entry.$1),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                gradient: sel
                    ? LinearGradient(
                        colors: [
                          Colors.white.withValues(alpha: .94),
                          const Color(0xFFF6E9E3),
                        ],
                      )
                    : null,
                color: sel ? null : Colors.transparent,
                borderRadius: BorderRadius.circular(10),
                boxShadow: sel
                    ? [
                        BoxShadow(
                          color: GussoniBrand.primary.withValues(alpha: .16),
                          blurRadius: 12,
                          offset: const Offset(0, 6),
                        ),
                      ]
                    : null,
              ),
              child: Text(
                entry.$2,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: sel ? FontWeight.w700 : FontWeight.w500,
                  color: sel
                      ? GussoniBrand.textPrimary
                      : GussoniBrand.textMuted,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildMemberSelector() {
    final allId = '__all__';
    final options = <(String, String)>[
      (widget.currentUserId, 'Io'),
      ...widget.members
          .where((m) => m.userId != widget.currentUserId)
          .map(
            (m) =>
                (m.userId, m.displayName.isNotEmpty ? m.displayName : m.email),
          ),
      if (_mode == AgendaViewMode.team) (allId, 'Tutti'),
    ];
    final current = widget.selectedMemberId ?? widget.currentUserId;
    return DropdownButton<String>(
      value: options.any((o) => o.$1 == current) ? current : options.first.$1,
      isDense: true,
      underline: const SizedBox.shrink(),
      style: const TextStyle(fontSize: 13, color: GussoniBrand.textSecondary),
      items: options
          .map(
            (o) => DropdownMenuItem(
              value: o.$1,
              child: Text(o.$2, style: const TextStyle(fontSize: 13)),
            ),
          )
          .toList(),
      onChanged: (v) => widget.onMemberChanged?.call(v == allId ? null : v),
    );
  }

  // ─── Calendar grid ────────────────────────────────────────────────────────

  Widget _buildCalendarGrid() {
    final days = _visibleDays;
    return LayoutBuilder(
      builder: (context, constraints) {
        final totalW = constraints.maxWidth;
        final dayW = max(80.0, (totalW - _kHourLabelW) / days.length);

        return Column(
          children: [
            // Day headers
            _buildDayHeaders(days, dayW),
            // Time grid
            Expanded(
              child: SingleChildScrollView(
                controller: _scrollCtrl,
                child: SizedBox(
                  width: totalW,
                  height: _kGridH,
                  child: _buildGridStack(days, dayW, totalW),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildDayHeaders(List<DateTime> days, double dayW) {
    final now = DateTime.now();
    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: GussoniBrand.border.withValues(alpha: .78)),
        ),
        gradient: LinearGradient(
          colors: [
            const Color(0xFFF6F4F1).withValues(alpha: .92),
            const Color(0xFFF6E9E3).withValues(alpha: .88),
          ],
        ),
      ),
      child: Row(
        children: [
          SizedBox(width: _kHourLabelW), // spacer for hour column
          ...days.map((day) {
            final isToday = _sameDay(day, now);
            final isWeekend = day.weekday >= 6;
            final slots = _slotsForDay(day);
            final tasks = _tasksForDay(day);
            final totalHours = widget.workspace.availability
                .where((a) => a.weekday == day.weekday && !a.isOff)
                .fold<double>(0, (s, a) => s + (a.hours > 0 ? a.hours : 8));
            final plannedH = slots.fold<double>(
              0,
              (s, sl) => s + sl.plannedHours,
            );
            final progress = totalHours > 0
                ? (plannedH / totalHours).clamp(0.0, 1.0)
                : 0.0;

            return SizedBox(
              width: dayW,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
                color: isWeekend
                    ? const Color(0xFFF6F4F1).withValues(alpha: .48)
                    : Colors.transparent,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Day label
                    Row(
                      children: [
                        if (isToday)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Color(0xFF5B1205), Color(0xFFB08948)],
                              ),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              _dayLabelText(day),
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                          )
                        else
                          Text(
                            _dayLabelText(day),
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: isWeekend
                                  ? GussoniBrand.textDisabled
                                  : GussoniBrand.textSecondary,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    // Progress bar
                    ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 3,
                        backgroundColor: GussoniBrand.borderSubtle,
                        color: GussoniBrand.primary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    // Task count
                    if (tasks.isNotEmpty)
                      Row(
                        children: [
                          const Icon(
                            Icons.check_box_outline_blank,
                            size: 11,
                            color: GussoniBrand.textMuted,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            '${tasks.length} task${tasks.length > 1 ? "s" : ""}',
                            style: const TextStyle(
                              fontSize: 10,
                              color: GussoniBrand.textMuted,
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildGridStack(List<DateTime> days, double dayW, double totalW) {
    final now = DateTime.now();
    final nowFrac = (now.hour + now.minute / 60.0 - _kFirstHour).clamp(
      0.0,
      (_kLastHour - _kFirstHour).toDouble(),
    );

    return Stack(
      clipBehavior: Clip.none,
      children: [
        // Hour lines + labels
        Positioned.fill(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: _kHourLabelW,
                child: Column(
                  children: List.generate(_kLastHour - _kFirstHour, (i) {
                    final h = _kFirstHour + i;
                    return SizedBox(
                      height: _kHourH,
                      child: Align(
                        alignment: Alignment.topRight,
                        child: Padding(
                          padding: const EdgeInsets.only(right: 8, top: 2),
                          child: Text(
                            '$h',
                            style: const TextStyle(
                              fontSize: 10,
                              color: GussoniBrand.textDisabled,
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
                ),
              ),
              Expanded(
                child: Column(
                  children: List.generate(
                    _kLastHour - _kFirstHour,
                    (i) => Container(
                      height: _kHourH,
                      decoration: const BoxDecoration(
                        border: Border(
                          bottom: BorderSide(color: GussoniBrand.borderSubtle),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),

        // Vertical day separators
        for (int i = 0; i < days.length; i++)
          Positioned(
            left: _kHourLabelW + i * dayW,
            top: 0,
            bottom: 0,
            width: 1,
            child: Container(color: GussoniBrand.border.withValues(alpha: .66)),
          ),

        // Weekend background
        for (int i = 0; i < days.length; i++)
          if (days[i].weekday >= 6)
            Positioned(
              left: _kHourLabelW + i * dayW,
              top: 0,
              bottom: 0,
              width: dayW,
              child: Container(
                color: const Color(0xFFF6F4F1).withValues(alpha: .40),
              ),
            ),

        // Per-day drag interaction areas
        for (int i = 0; i < days.length; i++)
          _buildDayInteractionArea(days[i], i, dayW),

        // Slot chips
        for (int i = 0; i < days.length; i++)
          ..._buildDaySlots(days[i], i, dayW),

        // Drawing preview
        if (_isDrawing && _drawDay != null)
          Builder(
            builder: (ctx) {
              final dayIdx = days.indexWhere((d) => _sameDay(d, _drawDay!));
              if (dayIdx < 0) return const SizedBox.shrink();
              final topDy = min(_drawStartDy!, _drawCurDy!).clamp(0.0, _kGridH);
              final botDy = max(_drawStartDy!, _drawCurDy!).clamp(0.0, _kGridH);
              return Positioned(
                left: _kHourLabelW + dayIdx * dayW + 2,
                top: topDy,
                width: dayW - 4,
                height: max(botDy - topDy, 8.0),
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFFB08948).withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFB08948)),
                  ),
                ),
              );
            },
          ),

        // Drag preview snapped to 30-minute grid
        if (_slotDragPreview != null)
          Builder(
            builder: (ctx) {
              final preview = _slotDragPreview!;
              final dayIdx = days.indexWhere((d) => _sameDay(d, preview.day));
              if (dayIdx < 0) {
                return const SizedBox.shrink();
              }
              final top = ((preview.startHour - _kFirstHour) * _kHourH).clamp(
                0.0,
                _kGridH - _kMinSlotH,
              );
              final height = max(
                preview.slot.plannedHours * _kHourH,
                _kMinSlotH,
              );
              return Positioned(
                left: _kHourLabelW + dayIdx * dayW + 2,
                top: top,
                width: dayW - 4,
                height: height,
                child: IgnorePointer(
                  child: Container(
                    decoration: BoxDecoration(
                      color: _slotColor(preview.slot).withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: _slotColor(preview.slot),
                        width: 1.5,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),

        // Current time indicator
        if (now.hour >= _kFirstHour && now.hour < _kLastHour)
          Positioned(
            left: _kHourLabelW - 6,
            top: nowFrac * _kHourH - 1,
            right: 0,
            child: Row(
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: const BoxDecoration(
                    color: Color(0xFFA8332C),
                    shape: BoxShape.circle,
                  ),
                ),
                Expanded(
                  child: Container(height: 1.5, color: const Color(0xFFA8332C)),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildDayInteractionArea(DateTime day, int dayIdx, double dayW) {
    return Positioned(
      left: _kHourLabelW + dayIdx * dayW,
      top: 0,
      bottom: 0,
      width: dayW,
      child: DragTarget<_SlotDragData>(
        onWillAcceptWithDetails: (_) => true,
        onMove: (details) {
          final nextStartHour = _previewStartHourForDrop(
            targetContext: context,
            details: details,
            durationHours: details.data.slot.plannedHours,
          );
          if (nextStartHour == null) {
            return;
          }
          setState(() {
            _slotDragPreview = _SlotDragPreview(
              slot: details.data.slot,
              day: day,
              startHour: nextStartHour,
            );
          });
        },
        onLeave: (_) {
          if (_slotDragPreview != null) {
            setState(() => _slotDragPreview = null);
          }
        },
        onAcceptWithDetails: (details) async {
          final startHour = _previewStartHourForDrop(
            targetContext: context,
            details: details,
            durationHours: details.data.slot.plannedHours,
          );
          setState(() => _slotDragPreview = null);
          if (startHour == null) return;
          await widget.onMoveSlot(details.data.slot, day, startHour);
        },
        builder: (context, candidateData, rejectedData) => GestureDetector(
          behavior: HitTestBehavior.translucent,
          onPanStart: (d) {
            if (_drawDay != null) return;
            setState(() {
              _drawDay = day;
              _drawStartDy = d.localPosition.dy.clamp(0, _kGridH);
              _drawCurDy = _drawStartDy;
            });
          },
          onPanUpdate: (d) {
            if (_drawDay == null || !_sameDay(_drawDay!, day)) return;
            setState(() => _drawCurDy = d.localPosition.dy.clamp(0, _kGridH));
          },
          onPanEnd: (_) async {
            if (!_isDrawing || !_sameDay(_drawDay!, day)) {
              setState(() {
                _drawDay = null;
                _drawStartDy = null;
                _drawCurDy = null;
              });
              return;
            }
            final startDy = _drawStartDy!;
            final endDy = _drawCurDy!;
            setState(() {
              _drawDay = null;
              _drawStartDy = null;
              _drawCurDy = null;
            });

            final startH = _startHourFrom(min(startDy, endDy));
            final durH = _durationFrom(
              startDy,
              endDy,
            ).clamp(0.5, 12.0).toDouble();
            await _openSchedulePopup(
              day: day,
              startHour: startH,
              durationHours: durH,
            );
          },
          child: candidateData.isEmpty
              ? const SizedBox.expand()
              : Container(
                  color: const Color(0xFFB08948).withValues(alpha: 0.08),
                ),
        ),
      ),
    );
  }

  List<Widget> _buildDaySlots(DateTime day, int dayIdx, double dayW) {
    final daySlots = _slotsForDay(day);
    if (daySlots.isEmpty) return [];
    final layouts = _slotLayouts(daySlots);
    return daySlots
        .map((slot) {
          final task = _taskById(slot.taskId);
          if (task == null) return const SizedBox.shrink();
          final layout = layouts[slot.id] ?? _SlotLayout(0, 1);
          final top = ((slot.startHour - _kFirstHour) * _kHourH).clamp(
            0.0,
            _kGridH - _kMinSlotH,
          );
          final displayHours =
              _previewSlotHeights[slot.id] ?? slot.plannedHours;
          final height = max(displayHours * _kHourH, _kMinSlotH);
          final laneW =
              (dayW - 4 - ((layout.laneCount - 1) * 2.0)) / layout.laneCount;
          final left =
              _kHourLabelW + dayIdx * dayW + 2 + layout.lane * (laneW + 2);
          final color = _slotColor(slot);

          return Positioned(
            left: left,
            top: top,
            width: laneW,
            height: height,
            child: Draggable<_SlotDragData>(
              data: _SlotDragData(slot),
              dragAnchorStrategy: pointerDragAnchorStrategy,
              onDragStarted: () {
                setState(() {
                  _slotDragPreview = _SlotDragPreview(
                    slot: slot,
                    day: day,
                    startHour: _snapHour(slot.startHour),
                  );
                });
              },
              onDragEnd: (_) {
                if (_slotDragPreview != null) {
                  setState(() => _slotDragPreview = null);
                }
              },
              onDraggableCanceled: (_, __) {
                if (_slotDragPreview != null) {
                  setState(() => _slotDragPreview = null);
                }
              },
              feedback: Material(
                color: Colors.transparent,
                child: ConstrainedBox(
                  constraints: BoxConstraints.tightFor(
                    width: laneW,
                    height: height,
                  ),
                  child: _AgendaSlotCard(
                    slot: slot,
                    label: _slotLabel(slot),
                    color: color,
                    height: height,
                    displayHours: displayHours,
                  ),
                ),
              ),
              childWhenDragging: Opacity(
                opacity: 0.25,
                child: _AgendaSlotCard(
                  slot: slot,
                  label: _slotLabel(slot),
                  color: color,
                  height: height,
                  displayHours: displayHours,
                ),
              ),
              child: _AgendaResizableSlot(
                slot: slot,
                label: _slotLabel(slot),
                color: color,
                height: height,
                displayHours: displayHours,
                onMenu: (d) => _showSlotMenu(d, slot, task),
                onPreviewHours: (hours) {
                  setState(() => _previewSlotHeights[slot.id] = hours);
                },
                onCommitHours: (hours) async {
                  setState(() => _previewSlotHeights.remove(slot.id));
                  final delta = hours - slot.plannedHours;
                  if (delta.abs() < 0.1) return;
                  await widget.onResizeSlot(slot, delta);
                },
                onCancelPreview: () {
                  setState(() => _previewSlotHeights.remove(slot.id));
                },
              ),
            ),
          );
        })
        .whereType<Widget>()
        .toList();
  }

  Future<void> _showSlotMenu(
    TapDownDetails details,
    TimelineSlot slot,
    WorkTask task,
  ) async {
    final overlay = Overlay.of(context).context.findRenderObject();
    if (overlay is! RenderBox) return;
    final isDone = task.status == TaskStatus.done;
    final action = await showMenu<_SlotAction>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromPoints(details.globalPosition, details.globalPosition),
        Offset.zero & overlay.size,
      ),
      items: [
        const PopupMenuItem(
          value: _SlotAction.remove,
          child: Text('Rimuovi evento pianificato'),
        ),
        const PopupMenuItem(
          value: _SlotAction.edit,
          child: Text('Modifica task'),
        ),
        const PopupMenuItem(value: _SlotAction.log, child: Text('Segna tempo')),
        PopupMenuItem(
          value: _SlotAction.done,
          child: Text(isDone ? 'Riapri' : 'Segna come fatto'),
        ),
      ],
    );
    if (!mounted || action == null) return;
    switch (action) {
      case _SlotAction.remove:
        await widget.onDeleteTimelineSlot(slot);
      case _SlotAction.edit:
        widget.onEditTask(task);
      case _SlotAction.log:
        widget.onLogTime(task);
      case _SlotAction.done:
        final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(isDone ? 'Riapri task' : 'Segna come fatto'),
            content: Text(
              isDone
                  ? 'Riapri "${task.name}"?'
                  : '"${task.name}" è completato?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Annulla'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: Text(isDone ? 'Riapri' : 'Conferma'),
              ),
            ],
          ),
        );
        if (ok == true) await widget.onToggleTaskDone(task, !isDone);
    }
  }

  Future<void> _openSchedulePopup({
    required DateTime day,
    required double startHour,
    required double durationHours,
  }) async {
    final openTasks =
        widget.workspace.tasks
            .where(
              (t) =>
                  (t.assigneeId == widget.currentUserId ||
                      t.assigneeId.isEmpty) &&
                  t.status != TaskStatus.done,
            )
            .toList()
          ..sort((a, b) => a.deadline.compareTo(b.deadline));

    // Se c'è un task in memoria → schedula direttamente
    if (widget.selectedPlanningTaskId != null) {
      final task = openTasks
          .where((t) => t.id == widget.selectedPlanningTaskId)
          .firstOrNull;
      if (task != null) {
        await widget.onScheduleTask(task, day, startHour, durationHours);
        return;
      }
      widget.onSelectedPlanningTaskIdChanged(null);
    }

    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${_weekdayAbbr(day.weekday).toUpperCase()} ${day.day}/${day.month} · ${_timeLbl(startHour)} · ${durationHours.toStringAsFixed(1)}h',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: GussoniBrand.textSecondary,
                ),
              ),
              const SizedBox(height: 10),
              ListTile(
                leading: const Icon(Icons.add_task_outlined),
                title: const Text('Pianifica nuovo task'),
                onTap: () => Navigator.of(ctx).pop('new'),
              ),
              ListTile(
                leading: const Icon(Icons.playlist_add_check_circle_outlined),
                title: const Text('Seleziona task esistente'),
                onTap: () => Navigator.of(ctx).pop('existing'),
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted || action == null) return;

    if (action == 'new') {
      await widget.onAddTaskForSchedule(day, startHour, durationHours);
      return;
    }

    if (openTasks.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nessun task aperto disponibile.')),
      );
      return;
    }

    final taskId = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Seleziona task'),
        content: SizedBox(
          width: 480,
          height: 360,
          child: ListView.separated(
            itemCount: openTasks.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (ctx, i) {
              final t = openTasks[i];
              final co = widget.workspace.companies
                  .where((c) => c.id == t.companyId)
                  .firstOrNull;
              return ListTile(
                dense: true,
                title: Text(
                  t.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  '${co?.name ?? ''} · Scad. ${t.deadline.day}/${t.deadline.month}/${t.deadline.year}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: _taskColor(t).withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${t.estimatedHours}h',
                    style: TextStyle(
                      fontSize: 11,
                      color: _taskColor(t),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                onTap: () => Navigator.of(ctx).pop(t.id),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Annulla'),
          ),
        ],
      ),
    );
    if (!mounted || taskId == null) return;
    final task = openTasks.firstWhere((t) => t.id == taskId);
    await widget.onScheduleTask(task, day, startHour, durationHours);
  }

  double _normalizeStartHour({
    required double startHour,
    required double durationHours,
  }) {
    final latestStart = (_kLastHour - durationHours).clamp(
      _kFirstHour.toDouble(),
      _kLastHour.toDouble(),
    );
    final rounded = _snapHour(startHour);
    return rounded.clamp(_kFirstHour.toDouble(), latestStart).toDouble();
  }

  double _snapHour(double hour) => (hour * 2).round() / 2.0;

  double? _previewStartHourForDrop({
    required BuildContext targetContext,
    required DragTargetDetails<_SlotDragData> details,
    required double durationHours,
  }) {
    final box = targetContext.findRenderObject() as RenderBox?;
    if (box == null) {
      return null;
    }
    final local = box.globalToLocal(details.offset);
    final rawHour = _startHourFrom(local.dy);
    return _normalizeStartHour(
      startHour: rawHour,
      durationHours: durationHours,
    );
  }

  // ─── Month view ──────────────────────────────────────────────────────────

  Widget _buildMonthView() {
    final now = DateTime.now();
    final first = DateTime(
      widget.visibleWeekStart.year,
      widget.visibleWeekStart.month,
      1,
    );
    final firstMonday = first.subtract(Duration(days: (first.weekday - 1) % 7));
    final weeks = 6;
    final days = List.generate(
      weeks * 7,
      (i) => firstMonday.add(Duration(days: i)),
    );
    const headers = ['Lun', 'Mar', 'Mer', 'Gio', 'Ven', 'Sab', 'Dom'];

    return Column(
      children: [
        // Weekday headers
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            children: headers
                .map(
                  (h) => Expanded(
                    child: Text(
                      h,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: GussoniBrand.textMuted,
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: GridView.builder(
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.all(4),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              childAspectRatio: 1.4,
            ),
            itemCount: days.length,
            itemBuilder: (_, i) {
              final day = days[i];
              final isToday = _sameDay(day, now);
              final isCurrentMonth = day.month == first.month;
              final daySlots = _slotsForDay(day);
              return GestureDetector(
                onTap: () => setState(() {
                  _selectedDay = day;
                  _mode = AgendaViewMode.giorno;
                }),
                child: Container(
                  margin: const EdgeInsets.all(1),
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    gradient: isToday
                        ? const LinearGradient(
                            colors: [Color(0xFFF6E9E3), Color(0xFFF0E9E1)],
                          )
                        : null,
                    borderRadius: BorderRadius.circular(10),
                    border: isToday
                        ? Border.all(color: GussoniBrand.primary)
                        : null,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${day.day}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: isToday
                              ? GussoniBrand.primaryDark
                              : isCurrentMonth
                              ? GussoniBrand.textPrimary
                              : GussoniBrand.textDisabled,
                        ),
                      ),
                      const SizedBox(height: 2),
                      ...daySlots.take(2).map((slot) {
                        final task = _taskById(slot.taskId);
                        return Container(
                          margin: const EdgeInsets.only(bottom: 1),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 3,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: task != null
                                ? _taskColor(task).withValues(alpha: 0.86)
                                : GussoniBrand.textMuted,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            task?.name ?? '',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 8,
                              color: Colors.white,
                            ),
                          ),
                        );
                      }),
                      if (daySlots.length > 2)
                        Text(
                          '+${daySlots.length - 2}',
                          style: const TextStyle(
                            fontSize: 8,
                            color: GussoniBrand.textMuted,
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

// ─── Slot layout (overlap detection) ─────────────────────────────────────────

class _SlotLayout {
  const _SlotLayout(this.lane, this.laneCount);
  final int lane;
  final int laneCount;
}

Map<String, _SlotLayout> _slotLayouts(List<TimelineSlot> slots) {
  if (slots.isEmpty) return {};
  final sorted = [...slots]..sort((a, b) => a.startHour.compareTo(b.startHour));
  final result = <String, _SlotLayout>{};
  final groups = <List<TimelineSlot>>[];
  final active = <TimelineSlot>[];

  for (final slot in sorted) {
    active.removeWhere((s) => s.startHour + s.plannedHours <= slot.startHour);
    if (active.isEmpty)
      groups.add([slot]);
    else
      groups.last.add(slot);
    active.add(slot);
  }

  for (final group in groups) {
    final n = group.length;
    for (int i = 0; i < n; i++) {
      result[group[i].id] = _SlotLayout(i, n);
    }
  }
  return result;
}

// ─── Enum ─────────────────────────────────────────────────────────────────────

enum _SlotAction { remove, edit, log, done }

// ─── Utility ─────────────────────────────────────────────────────────────────

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

String _weekdayAbbr(int wd) {
  const names = ['', 'Lun', 'Mar', 'Mer', 'Gio', 'Ven', 'Sab', 'Dom'];
  return names[wd.clamp(1, 7)];
}

String _timeLbl(double h) {
  final hour = h.floor();
  final min = ((h - hour) * 60).round();
  return '${hour.toString().padLeft(2, '0')}:${min.toString().padLeft(2, '0')}';
}

String _capitalize(String s) =>
    s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

Color _taskColor(WorkTask task) {
  final hash = task.id.codeUnits.fold<int>(
    17,
    (s, v) => (s * 31 + v) & 0x7fffffff,
  );
  return HSLColor.fromAHSL(
    1,
    (hash % 360).toDouble(),
    (0.65 + (hash % 23) / 100).clamp(0.0, 1.0),
    (0.38 + (hash % 14) / 100).clamp(0.0, 1.0),
  ).toColor();
}

Color _memberColor(String userId) {
  final hash = userId.codeUnits.fold<int>(
    7,
    (s, v) => (s * 13 + v) & 0x7fffffff,
  );
  return HSLColor.fromAHSL(1, (hash % 360).toDouble(), 0.6, 0.45).toColor();
}

IconButton _iconBtn(IconData icon, VoidCallback onTap) => IconButton(
  icon: Icon(icon, size: 20, color: GussoniBrand.textSecondary),
  onPressed: onTap,
  padding: const EdgeInsets.all(4),
  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
  style: IconButton.styleFrom(
    backgroundColor: const Color(0xFFF6F4F1),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
  ),
);

class _SlotDragData {
  const _SlotDragData(this.slot);

  final TimelineSlot slot;
}

class _SlotDragPreview {
  const _SlotDragPreview({
    required this.slot,
    required this.day,
    required this.startHour,
  });

  final TimelineSlot slot;
  final DateTime day;
  final double startHour;
}

class _AgendaSlotCard extends StatelessWidget {
  const _AgendaSlotCard({
    required this.slot,
    required this.label,
    required this.color,
    required this.height,
    required this.displayHours,
  });

  final TimelineSlot slot;
  final String label;
  final Color color;
  final double height;
  final double displayHours;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 1),
      decoration: BoxDecoration(
        color: color.withOpacity(0.85),
        borderRadius: BorderRadius.circular(4),
        border: Border(left: BorderSide(color: color, width: 3)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: height > 42 ? 3 : 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              color: Color(0xFFFFFFFF),
              height: 1.3,
            ),
          ),
          if (height > 38)
            Text(
              '${_timeLbl(slot.startHour)} · ${displayHours.toStringAsFixed(1)}h',
              style: TextStyle(
                fontSize: 9.5,
                color: Colors.white.withOpacity(0.85),
              ),
            ),
        ],
      ),
    );
  }
}

class _AgendaResizableSlot extends StatefulWidget {
  const _AgendaResizableSlot({
    required this.slot,
    required this.label,
    required this.color,
    required this.height,
    required this.displayHours,
    required this.onMenu,
    required this.onPreviewHours,
    required this.onCommitHours,
    required this.onCancelPreview,
  });

  final TimelineSlot slot;
  final String label;
  final Color color;
  final double height;
  final double displayHours;
  final ValueChanged<TapDownDetails> onMenu;
  final ValueChanged<double> onPreviewHours;
  final ValueChanged<double> onCommitHours;
  final VoidCallback onCancelPreview;

  @override
  State<_AgendaResizableSlot> createState() => _AgendaResizableSlotState();
}

class _AgendaResizableSlotState extends State<_AgendaResizableSlot> {
  double _dragAccumulator = 0;
  double? _previewHours;
  int? _pointerId;
  double? _lastPointerY;
  bool _resizing = false;

  @override
  void didUpdateWidget(covariant _AgendaResizableSlot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.slot.id != widget.slot.id) {
      _previewHours = null;
      _dragAccumulator = 0;
      _pointerId = null;
      _lastPointerY = null;
      _resizing = false;
    }
  }

  void _handleResizeStep(double deltaY) {
    _dragAccumulator += deltaY;
    while (_dragAccumulator >= _kHourH / 2) {
      _dragAccumulator -= _kHourH / 2;
      _setPreview((_previewHours ?? widget.displayHours) + 0.5);
    }
    while (_dragAccumulator <= -_kHourH / 2) {
      _dragAccumulator += _kHourH / 2;
      _setPreview((_previewHours ?? widget.displayHours) - 0.5);
    }
  }

  void _setPreview(double hours) {
    final next = hours.clamp(0.5, 12.0).toDouble();
    setState(() => _previewHours = next);
    widget.onPreviewHours(next);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        GestureDetector(
          onSecondaryTapDown: widget.onMenu,
          onLongPressStart: (d) =>
              widget.onMenu(TapDownDetails(globalPosition: d.globalPosition)),
          child: _AgendaSlotCard(
            slot: widget.slot,
            label: widget.label,
            color: widget.color,
            height: widget.height,
            displayHours: _previewHours ?? widget.displayHours,
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: MouseRegion(
            cursor: SystemMouseCursors.resizeUpDown,
            child: Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: (event) {
                if (event.buttons != kPrimaryMouseButton &&
                    event.kind == PointerDeviceKind.mouse) {
                  return;
                }
                _dragAccumulator = 0;
                _pointerId = event.pointer;
                _lastPointerY = event.position.dy;
                _resizing = true;
              },
              onPointerMove: (event) {
                if (!_resizing ||
                    _pointerId != event.pointer ||
                    _lastPointerY == null) {
                  return;
                }
                final deltaY = event.position.dy - _lastPointerY!;
                _lastPointerY = event.position.dy;
                _handleResizeStep(deltaY);
              },
              onPointerUp: (_) {
                final hours = _previewHours;
                _resetPointerState();
                if (hours == null) return;
                widget.onCommitHours(hours);
                setState(() => _previewHours = null);
              },
              onPointerCancel: (_) {
                _resetPointerState();
                widget.onCancelPreview();
                setState(() => _previewHours = null);
              },
              child: const SizedBox(height: 10, width: double.infinity),
            ),
          ),
        ),
      ],
    );
  }

  void _resetPointerState() {
    _dragAccumulator = 0;
    _pointerId = null;
    _lastPointerY = null;
    _resizing = false;
  }
}

class _MobileCalendarMetric extends StatelessWidget {
  const _MobileCalendarMetric({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .74),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white),
      ),
      child: Row(
        children: [
          Icon(icon, color: GussoniBrand.primary, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: GussoniBrand.textMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  value,
                  style: const TextStyle(
                    color: GussoniBrand.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
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

class _MobileCalendarSectionTitle extends StatelessWidget {
  const _MobileCalendarSectionTitle(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label.toUpperCase(),
      style: const TextStyle(
        color: GussoniBrand.textMuted,
        fontSize: 11,
        fontWeight: FontWeight.w900,
        letterSpacing: .7,
      ),
    );
  }
}

class _MobileCalendarEmpty extends StatelessWidget {
  const _MobileCalendarEmpty({required this.onAdd});
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Container(
          padding: const EdgeInsets.all(22),
          decoration: GussoniBrand.glassPanel(radius: 28, opacity: .82),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.calendar_today_rounded,
                color: GussoniBrand.primary,
                size: 36,
              ),
              const SizedBox(height: 12),
              const Text(
                'Giornata libera',
                style: TextStyle(
                  color: GussoniBrand.textPrimary,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 5),
              const Text(
                'Nessun task o blocco pianificato.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: GussoniBrand.textMuted,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: onAdd,
                icon: const Icon(Icons.add_rounded),
                label: const Text('Aggiungi task'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MobileSlotCard extends StatelessWidget {
  const _MobileSlotCard({
    required this.slot,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final TimelineSlot slot;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final start = _timeLabel(slot.startHour);
    final end = _timeLabel(slot.startHour + slot.plannedHours);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: .80),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: Colors.white),
            boxShadow: const [
              BoxShadow(
                color: Color(0x0D000000),
                blurRadius: 14,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 5,
                height: 54,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$start - $end',
                      style: const TextStyle(
                        color: GussoniBrand.textMuted,
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      label,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: GussoniBrand.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: GussoniBrand.textDisabled,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MobileTaskCard extends StatelessWidget {
  const _MobileTaskCard({
    required this.task,
    required this.onTap,
    required this.onDone,
  });

  final WorkTask task;
  final VoidCallback onTap;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final done = task.status == TaskStatus.done;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: .78),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: Colors.white),
          ),
          child: Row(
            children: [
              GestureDetector(
                onTap: onDone,
                child: Icon(
                  done
                      ? Icons.check_circle_rounded
                      : Icons.radio_button_unchecked_rounded,
                  color: done ? GussoniBrand.success : GussoniBrand.textMuted,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  task.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: done
                        ? GussoniBrand.textMuted
                        : GussoniBrand.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    decoration: done ? TextDecoration.lineThrough : null,
                  ),
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: GussoniBrand.textDisabled,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _timeLabel(double hour) {
  final h = hour.floor().clamp(0, 23);
  final m = ((hour - h) * 60).round().clamp(0, 59);
  return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
}

int _isoWeekNumber(DateTime date) {
  final d = DateTime(date.year, date.month, date.day);
  final dayOfYear = d.difference(DateTime(d.year)).inDays + 1;
  final wday = d.weekday;
  return ((dayOfYear - wday + 10) / 7).floor();
}
