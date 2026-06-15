import '../../brand_config.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/domain_models.dart';
import '../../data/firestore_workspace_repository.dart';
import 'tl_table.dart';

class TaskListCard extends StatefulWidget {
  const TaskListCard({
    super.key,
    required this.workspace,
    required this.onAddTask,
    required this.onEditTask,
    required this.onDeleteTask,
    required this.onToggleTaskDone,
    required this.onLogTime,
    required this.onPlanTaskInCalendar,
    this.onOpenDetail,
    this.filterUserId, // null = tutti, stringa = solo questo assigneeId
    this.onPaginationChanged,
  });

  final WorkspaceSnapshot workspace;
  final VoidCallback onAddTask;
  final Future<void> Function(WorkTask) onEditTask;
  final Future<void> Function(WorkTask) onDeleteTask;
  final Future<void> Function(WorkTask, bool) onToggleTaskDone;
  final Future<void> Function(WorkTask) onLogTime;
  final Future<void> Function(WorkTask) onPlanTaskInCalendar;
  final void Function(WorkTask)? onOpenDetail;
  final String? filterUserId; // Teamleader: task.assignee.id
  final void Function(int page, int pageSize)? onPaginationChanged;

  @override
  State<TaskListCard> createState() => _TaskListCardState();
}

class _TaskListCardState extends State<TaskListCard> {
  String? _statusFilter;
  bool _hideDoneByDefault = true;
  bool _hideVeryOldByDefault = true;
  final _dateFmt = DateFormat('dd/MM/yyyy');
  static const int _veryOldTaskDays = 180;

  static const _statusFilters = [
    TlStatusFilter(
      label: 'Pianificato',
      value: 'planned',
      color: Color(0xFF0369A1),
    ),
    TlStatusFilter(
      label: 'In corso',
      value: 'inProgress',
      color: Color(0xFFD97706),
    ),
  ];

  Color _statusColor(TaskStatus s) {
    switch (s) {
      case TaskStatus.backlog:
        return const Color(0xFF7D89A8);
      case TaskStatus.planned:
        return const Color(0xFF0369A1);
      case TaskStatus.inProgress:
        return const Color(0xFFD97706);
      case TaskStatus.done:
        return GussoniBrand.primary;
    }
  }

  String _statusLabel(TaskStatus s) {
    switch (s) {
      case TaskStatus.backlog:
        return 'Backlog';
      case TaskStatus.planned:
        return 'Pianificato';
      case TaskStatus.inProgress:
        return 'In corso';
      case TaskStatus.done:
        return 'Fatto';
    }
  }

  List<TlRow> get _rows {
    var tasks = widget.workspace.tasks;
    final companyNameById = <String, String>{
      for (final company in widget.workspace.companies)
        company.id: company.name,
    };
    final projectNameById = <String, String>{
      for (final project in widget.workspace.projects) project.id: project.name,
    };
    // Filtra per membro del team se specificato
    if (widget.filterUserId != null) {
      tasks = tasks.where((t) => t.assigneeId == widget.filterUserId).toList();
    }
    if (_statusFilter != null) {
      final s = TaskStatus.values.firstWhere(
        (v) => v.name == _statusFilter,
        orElse: () => TaskStatus.planned,
      );
      tasks = tasks.where((t) => t.status == s).toList();
    }
    final now = DateTime.now();
    final veryOldThreshold = now.subtract(
      const Duration(days: _veryOldTaskDays),
    );
    final isDoneStatusExplicit = _statusFilter == TaskStatus.done.name;
    if (_hideDoneByDefault && !isDoneStatusExplicit) {
      tasks = tasks.where((t) => t.status != TaskStatus.done).toList();
    }
    if (_hideVeryOldByDefault) {
      tasks = tasks
          .where((t) => !t.deadline.isBefore(veryOldThreshold))
          .toList();
    }
    return tasks.map((t) {
      final isOverdue =
          t.deadline.isBefore(DateTime.now()) && t.status != TaskStatus.done;
      final done = t.status == TaskStatus.done;
      return TlRow(
        key: t.id,
        onTap: () => widget.onOpenDetail != null
            ? widget.onOpenDetail!(t)
            : widget.onEditTask(t),
        cells: [
          TlCell(
            widget: Row(
              children: [
                if (done)
                  const Icon(
                    Icons.check_circle,
                    size: 18,
                    color: Color(0xFF034F3B),
                  )
                else
                  Icon(
                    Icons.radio_button_unchecked,
                    size: 18,
                    color: isOverdue
                        ? const Color(0xFFB91C1C)
                        : const Color(0xFF1E2130),
                  ),
                const SizedBox(width: 10),
                Expanded(child: TlPrimaryCell(text: t.name)),
              ],
            ),
          ),
          TlCell(text: companyNameById[t.companyId] ?? '—'),
          TlCell(text: projectNameById[t.projectId] ?? '—'),
          TlCell(
            widget: TlBadge(
              label: _statusLabel(t.status),
              color: _statusColor(t.status),
            ),
          ),
          TlCell(
            text: t.estimatedHours > 0
                ? '${t.estimatedHours.toStringAsFixed(1)}h'
                : '—',
          ),
          TlCell(
            widget: Text(
              _dateFmt.format(t.deadline),
              style: TextStyle(
                fontSize: 13,
                color: isOverdue
                    ? const Color(0xFFB91C1C)
                    : const Color(0xFFB8C0D8),
                fontWeight: isOverdue ? FontWeight.w700 : FontWeight.normal,
              ),
            ),
          ),
          TlCell(
            widget: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextButton.icon(
                  onPressed: () => widget.onPlanTaskInCalendar(t),
                  icon: const Icon(Icons.calendar_month_outlined, size: 16),
                  label: const Text('Pianifica'),
                ),
                TlRowActions(
                  items: [
                    PopupMenuItem(
                      value: 'plan',
                      child: const Text('Pianifica nel calendario'),
                      onTap: () => widget.onPlanTaskInCalendar(t),
                    ),
                    PopupMenuItem(
                      value: 'edit',
                      child: const Text('Modifica'),
                      onTap: () => widget.onEditTask(t),
                    ),
                    PopupMenuItem(
                      value: 'done',
                      child: Text(done ? 'Riapri' : 'Segna fatto'),
                      onTap: () => widget.onToggleTaskDone(t, !done),
                    ),
                    PopupMenuItem(
                      value: 'time',
                      child: const Text('Segna tempo'),
                      onTap: () => widget.onLogTime(t),
                    ),
                    const PopupMenuDivider(),
                    PopupMenuItem(
                      value: 'delete',
                      child: const Text(
                        'Elimina',
                        style: TextStyle(color: Color(0xFFB91C1C)),
                      ),
                      onTap: () => widget.onDeleteTask(t),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      );
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return TlTable(
      searchHint: 'Cerca task...',
      columns: const [
        TlColumn(label: 'Nome task', flex: 3),
        TlColumn(label: 'Azienda', flex: 2),
        TlColumn(label: 'Progetto', flex: 2),
        TlColumn(label: 'Stato', flex: 1),
        TlColumn(label: 'Stima', flex: 1),
        TlColumn(label: 'Scadenza', flex: 1),
        TlColumn(label: '', minWidth: 190),
      ],
      rows: _rows,
      statusFilters: _statusFilters,
      selectedStatus: _statusFilter,
      onStatusChanged: (v) => setState(() => _statusFilter = v),
      onPaginationChanged: widget.onPaginationChanged,
      onAdd: widget.onAddTask,
      addLabel: 'Aggiungi task',
      emptyMessage: _hideDoneByDefault || _hideVeryOldByDefault
          ? 'Nessun task trovato con i filtri predefiniti (miei/non chiusi/non vecchissimi).'
          : 'Nessun task trovato.',
    );
  }
}
