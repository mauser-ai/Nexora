import '../../brand_config.dart';
import 'package:flutter/material.dart';

import '../../models/domain_models.dart';
import '../../data/firestore_workspace_repository.dart';
import 'tl_table.dart';

class ProgettiCard extends StatefulWidget {
  const ProgettiCard({
    super.key,
    required this.workspace,
    required this.onAddProject,
    required this.onEditProject,
    required this.onAddTask,
    this.onOpenDetail,
  });

  final WorkspaceSnapshot workspace;
  final VoidCallback onAddProject;
  final Future<void> Function(Project) onEditProject;
  final Future<void> Function(Project) onAddTask;
  final void Function(Project)? onOpenDetail;

  @override
  State<ProgettiCard> createState() => _ProgettiCardState();
}

class _ProgettiCardState extends State<ProgettiCard> {
  String? _statusFilter;

  static const _statusFilters = [
    TlStatusFilter(label: 'Attivo', value: 'active', color: Color(0xFF034F3B)),
    TlStatusFilter(label: 'Archiviato', value: 'archived', color: Color(0xFF7D89A8)),
  ];

  Color _statusColor(String status) {
    switch (status) {
      case 'active': return GussoniBrand.primary;
      case 'archived': return const Color(0xFF7D89A8);
      default: return const Color(0xFF0369A1);
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'active': return 'Attivo';
      case 'archived': return 'Archiviato';
      default: return status;
    }
  }

  String _companyName(Project p) =>
      widget.workspace.companies.where((c) => c.id == p.companyId).firstOrNull?.name ?? '—';

  int _tasksCount(Project p) =>
      widget.workspace.tasks.where((t) => t.projectId == p.id).length;

  double _loggedHours(Project p) =>
      widget.workspace.timeTracks.where((t) => t.projectId == p.id).fold(0.0, (s, t) => s + t.hours);

  // dealId → nome del deal sorgente (Teamleader: project.source)
  String? _sourceDealTitle(Project p) {
    if (p.dealId == null) return null;
    return widget.workspace.tasks.isEmpty ? null : null; // tasks doesn't have deals
    // Il collegamento deal viene da crmData, ma ProgettiCard ha solo workspace.
    // Il dealId viene mostrato se valorizzato nel Project.
  }

  List<TlRow> get _rows {
    var projects = widget.workspace.projects;
    if (_statusFilter != null) {
      projects = projects.where((p) => p.status == _statusFilter).toList();
    }
    return projects.map((p) {
      final logged = _loggedHours(p);
      final tasks = _tasksCount(p);
      final phases = widget.workspace.phases.where((ph) => ph.projectId == p.id).length;
      final sub = [if (p.code.isNotEmpty) 'Cod: ${p.code}', if (p.dealId != null) '↗ Da opportunità'].join(' · ');
      return TlRow(
        key: p.id,
        onTap: () => widget.onOpenDetail != null ? widget.onOpenDetail!(p) : widget.onEditProject(p),
        cells: [
          TlCell(widget: TlPrimaryCell(text: p.name, sub: sub.isNotEmpty ? sub : null)),
          TlCell(text: _companyName(p)),
          TlCell(widget: TlBadge(label: _statusLabel(p.status), color: _statusColor(p.status))),
          TlCell(widget: tasks > 0
              ? Row(children: [const Icon(Icons.task_alt_outlined, size: 13, color: Color(0xFF525D78)), const SizedBox(width: 4), Text('$tasks', style: const TextStyle(fontSize: 13, color: Color(0xFFB8C0D8)))])
              : const Text('—', style: TextStyle(color: Color(0xFF525D78)))),
          TlCell(widget: phases > 0
              ? Row(children: [const Icon(Icons.account_tree_outlined, size: 13, color: Color(0xFF525D78)), const SizedBox(width: 4), Text('$phases', style: const TextStyle(fontSize: 13, color: Color(0xFFB8C0D8)))])
              : const Text('—', style: TextStyle(color: Color(0xFF525D78)))),
          TlCell(text: logged > 0 ? '${logged.toStringAsFixed(1)}h' : '—'),
          TlCell(widget: TlRowActions(items: [
            PopupMenuItem(value: 'edit', child: const Text('Modifica'), onTap: () => widget.onEditProject(p)),
            PopupMenuItem(value: 'task', child: const Text('Aggiungi task'), onTap: () => widget.onAddTask(p)),
          ])),
        ],
      );
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return TlTable(
      searchHint: 'Cerca progetti...',
      columns: const [
        TlColumn(label: 'Nome progetto', flex: 3),
        TlColumn(label: 'Cliente', flex: 2),
        TlColumn(label: 'Stato', flex: 1),
        TlColumn(label: 'Task', flex: 1),
        TlColumn(label: 'Fasi', flex: 1),
        TlColumn(label: 'Ore', flex: 1),
        TlColumn(label: '', minWidth: 40),
      ],
      rows: _rows,
      statusFilters: _statusFilters,
      selectedStatus: _statusFilter,
      onStatusChanged: (v) => setState(() => _statusFilter = v),
      onAdd: widget.onAddProject,
      addLabel: 'Aggiungi progetto',
      emptyMessage: 'Nessun progetto trovato.',
    );
  }
}
