import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../app/nexora_dialog.dart';
import '../../brand_config.dart';
import '../../data/api_workspace_repository.dart';
import '../../models/domain_models.dart';
import '../widgets/g_table.dart';

class TaskGussoniScreen extends StatefulWidget {
  const TaskGussoniScreen({
    super.key,
    required this.workspace,
    required this.userId,
    required this.repository,
    this.onAddTask,
    this.onEditTask,
    this.onToggleDone,
    this.onPlanTask,
    this.onOpenTask,
    this.showHeader = true,
    this.showAddButton = true,
    this.isPinned = false,
    this.onPinContext,
  });
  final WorkspaceSnapshot workspace;
  final String userId;
  final ApiWorkspaceRepository repository;
  final VoidCallback? onAddTask;
  final void Function(WorkTask)? onEditTask;
  final void Function(WorkTask)? onToggleDone;
  final void Function(WorkTask)? onPlanTask;
  final void Function(WorkTask)? onOpenTask;
  final bool showHeader;
  final bool showAddButton;
  final bool isPinned;
  final VoidCallback? onPinContext;

  @override
  State<TaskGussoniScreen> createState() => _TaskGussoniScreenState();
}

class _TaskGussoniScreenState extends State<TaskGussoniScreen> {
  TaskStatus? _statusFilter;
  String _search = '';
  WorkTask? _mobileSelected;

  List<WorkTask> get _filtered =>
      widget.workspace.tasks
          .where(
            (t) =>
                (_statusFilter == null || t.status == _statusFilter) &&
                (_search.isEmpty ||
                    t.name.toLowerCase().contains(_search.toLowerCase())),
          )
          .toList()
        ..sort((a, b) => a.deadline.compareTo(b.deadline));

  String _companyName(String id) =>
      widget.workspace.companies.where((c) => c.id == id).firstOrNull?.name ??
      '—';

  String _projectName(String id) =>
      widget.workspace.projects.where((p) => p.id == id).firstOrNull?.name ??
      '—';

  String _phaseName(String id) =>
      widget.workspace.phases.where((p) => p.id == id).firstOrNull?.name ?? '—';

  @override
  Widget build(BuildContext context) {
    final cols = <GCol<WorkTask>>[
      GCol(
        label: 'Task',
        flex: 4,
        cell: (t) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            GCellText(t.name, bold: true),
            if (_companyName(t.companyId) != '—')
              GCellText(_companyName(t.companyId), muted: true),
          ],
        ),
      ),
      GCol(
        label: 'Progetto / Fase',
        flex: 3,
        cell: (t) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            GCellText(_projectName(t.projectId), muted: true),
            if (t.phaseId.isNotEmpty)
              GCellText(_phaseName(t.phaseId), muted: true),
          ],
        ),
      ),
      GCol(
        label: 'Scadenza',
        flex: 2,
        cell: (t) {
          final overdue =
              t.deadline.isBefore(DateTime.now()) &&
              t.status != TaskStatus.done;
          return GCellText(
            DateFormat('dd/MM/yyyy').format(t.deadline),
            muted: !overdue,
          );
        },
      ),
      GCol(
        label: 'Ore',
        flex: 2,
        cell: (t) => GCellText(
          '${t.loggedHours.toStringAsFixed(1)}/${t.estimatedHours.toStringAsFixed(1)}',
        ),
      ),
      GCol(
        label: 'Stato',
        flex: 2,
        cell: (t) => GStatusChip(
          label: _statusLabel(t.status),
          color: _statusColor(t.status),
          small: true,
        ),
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < 560;

        final listPane = GScreenLayout(
          title: 'Task',
          count: _filtered.length,
          showHeader: widget.showHeader,
          isPinned: widget.isPinned,
          onPinContext: widget.onPinContext,
          contextActions: () => [
            if (widget.onAddTask != null)
              GContextMenuAction(
                label: 'Nuovo task',
                icon: Icons.add_task_outlined,
                onSelected: widget.onAddTask!,
              ),
          ],
          action: widget.showAddButton
              ? FilledButton.icon(
                  onPressed: widget.onAddTask,
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Nuovo task'),
                )
              : null,
          filters: GFilterPills<TaskStatus?>(
            items: const [
              null,
              TaskStatus.backlog,
              TaskStatus.planned,
              TaskStatus.inProgress,
              TaskStatus.done,
            ],
            selected: _statusFilter,
            onSelect: (s) => setState(() {
              _statusFilter = s;
              _mobileSelected = null;
            }),
            labelOf: (s) => s == null ? 'Tutti' : _statusLabel(s),
            countOf: (s) => s == null
                ? widget.workspace.tasks.length
                : widget.workspace.tasks.where((t) => t.status == s).length,
          ),
          searchHint: 'Cerca task…',
          onSearch: (v) => setState(() {
            _search = v;
            _mobileSelected = null;
          }),
          body: GTable<WorkTask>(
            columns: cols,
            rows: _filtered,
            isSelected: (_) => false,
            onRowTap: (t) {
              if (isMobile) {
                setState(() => _mobileSelected = t);
              } else {
                widget.onOpenTask?.call(t);
              }
            },
            contextActionsForRow: (t) => [
              GContextMenuAction(
                label: 'Apri task',
                icon: Icons.open_in_new_rounded,
                onSelected: () {
                  if (isMobile) {
                    setState(() => _mobileSelected = t);
                  } else {
                    widget.onOpenTask?.call(t);
                  }
                },
              ),
              if (widget.onEditTask != null)
                GContextMenuAction(
                  label: 'Modifica',
                  icon: Icons.edit_outlined,
                  onSelected: () => widget.onEditTask!(t),
                ),
              if (widget.onPlanTask != null)
                GContextMenuAction(
                  label: 'Pianifica',
                  icon: Icons.event_available_outlined,
                  onSelected: () => widget.onPlanTask!(t),
                ),
              if (widget.onToggleDone != null)
                GContextMenuAction(
                  label: t.status == TaskStatus.done
                      ? 'Segna da fare'
                      : 'Segna completato',
                  icon: Icons.check_circle_outline,
                  onSelected: () => widget.onToggleDone!(t),
                ),
              GContextMenuAction(
                label: 'Elimina',
                icon: Icons.delete_outline_rounded,
                destructive: true,
                onSelected: () => _deleteTask(t),
              ),
            ],
            emptyLabel: 'Nessun task trovato.',
            emptyIcon: Icons.checklist_outlined,
          ),
        );

        if (!isMobile) return listPane;

        return GMobileNavWrapper(
          showDetail: _mobileSelected != null,
          list: listPane,
          detail: _mobileSelected == null
              ? const SizedBox.shrink()
              : Column(
                  children: [
                    GMobileBackBar(
                      backLabel: 'Task',
                      title: _mobileSelected!.name,
                      onBack: () => setState(() => _mobileSelected = null),
                      action: widget.onEditTask != null
                          ? IconButton(
                              onPressed: () =>
                                  widget.onEditTask!(_mobileSelected!),
                              icon: Icon(
                                Icons.edit_outlined,
                                size: 18,
                                color: GussoniBrand.primary,
                              ),
                            )
                          : null,
                    ),
                    Expanded(
                      child: GDetailPanel(
                        title: _mobileSelected!.name,
                        subtitle: _companyName(_mobileSelected!.companyId),
                        icon: GStatusChip(
                          label: _statusLabel(_mobileSelected!.status),
                          color: _statusColor(_mobileSelected!.status),
                          small: true,
                        ),
                        children: [
                          GDetailSection(
                            title: 'Dettagli',
                            children: [
                              GInfoRow('Nome', _mobileSelected!.name),
                              GInfoRow(
                                'Progetto',
                                _projectName(_mobileSelected!.projectId),
                              ),
                              if (_mobileSelected!.phaseId.isNotEmpty)
                                GInfoRow(
                                  'Fase',
                                  _phaseName(_mobileSelected!.phaseId),
                                ),
                              GInfoRow(
                                'Scadenza',
                                DateFormat(
                                  'dd/MM/yyyy',
                                ).format(_mobileSelected!.deadline),
                              ),
                              GInfoRow(
                                'Ore',
                                '${_mobileSelected!.loggedHours.toStringAsFixed(1)} / ${_mobileSelected!.estimatedHours.toStringAsFixed(1)} h',
                              ),
                              GInfoRow(
                                'Stato',
                                _statusLabel(_mobileSelected!.status),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
        );
      },
    );
  }

  static Color _statusColor(TaskStatus s) => switch (s) {
    TaskStatus.backlog => GussoniBrand.textMuted,
    TaskStatus.planned => GussoniBrand.info,
    TaskStatus.inProgress => GussoniBrand.warning,
    TaskStatus.done => GussoniBrand.success,
  };

  static String _statusLabel(TaskStatus s) => switch (s) {
    TaskStatus.backlog => 'Backlog',
    TaskStatus.planned => 'Pianificato',
    TaskStatus.inProgress => 'In corso',
    TaskStatus.done => 'Fatto',
  };

  Future<void> _deleteTask(WorkTask task) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => NexoraConfirmDialog(
        title: 'Elimina task?',
        icon: Icons.delete_outline_rounded,
        message: 'Eliminare "${task.name}"?',
        confirmLabel: 'Elimina',
        isDanger: true,
      ),
    );
    if (confirmed != true) return;
    await widget.repository.deleteTask(widget.userId, task.id);
    if (mounted && _mobileSelected?.id == task.id) {
      setState(() => _mobileSelected = null);
    }
  }
}
