import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../app/nexora_dialog.dart';
import '../../brand_config.dart';
import '../../data/api_workspace_repository.dart';
import '../../models/domain_models.dart';
import '../widgets/g_table.dart';
import 'gantt_view.dart';

class ProgettiGussoniScreen extends StatefulWidget {
  const ProgettiGussoniScreen({
    super.key,
    required this.workspace,
    required this.userId,
    required this.repository,
    this.onAddProject,
    this.onEditProject,
    this.onAssignPhase,
    this.onCloseProject,
    this.onOpenProject,
    this.showHeader = true,
    this.showAddButton = true,
    this.isPinned = false,
    this.onPinContext,
  });
  final WorkspaceSnapshot workspace;
  final String userId;
  final ApiWorkspaceRepository repository;
  final VoidCallback? onAddProject;
  final void Function(Project)? onEditProject;
  final void Function(Project, ProjectPhase, String? userId)? onAssignPhase;
  final void Function(Project)? onCloseProject;
  final void Function(Project)? onOpenProject;
  final bool showHeader;
  final bool showAddButton;
  final bool isPinned;
  final VoidCallback? onPinContext;

  @override
  State<ProgettiGussoniScreen> createState() => _ProgettiGussoniScreenState();
}

class _ProgettiGussoniScreenState extends State<ProgettiGussoniScreen> {
  String? _statusFilter;
  String _search = '';
  bool _ganttMode = false;

  static const _statusOptions = [
    null,
    'draft',
    'planning',
    'inProgress',
    'pendingResult',
    'approved',
    'closed',
  ];

  List<Project> get _filtered => widget.workspace.projects
      .where(
        (p) =>
            (_statusFilter == null || p.status == _statusFilter) &&
            (_search.isEmpty ||
                p.name.toLowerCase().contains(_search.toLowerCase()) ||
                p.code.toLowerCase().contains(_search.toLowerCase())),
      )
      .toList();

  String _companyName(String id) =>
      widget.workspace.companies.where((c) => c.id == id).firstOrNull?.name ??
      '—';

  List<ProjectPhase> _phasesOf(String projectId) =>
      widget.workspace.phases.where((p) => p.projectId == projectId).toList()
        ..sort((a, b) => a.order.compareTo(b.order));

  int _donePhases(String projectId) =>
      _phasesOf(projectId).where((p) => p.status == PhaseStatus.done).length;

  @override
  Widget build(BuildContext context) {
    final statusLabels = {
      null: 'Tutti',
      'draft': 'Bozza',
      'planning': 'Pianificazione',
      'inProgress': 'In corso',
      'pendingResult': 'In attesa esito',
      'approved': 'Approvato',
      'closed': 'Chiuso',
    };
    final activeProjects = widget.workspace.projects
        .where((p) => p.status != 'closed' && p.status != 'approved')
        .length;
    final approvedProjects = widget.workspace.projects
        .where((p) => p.status == 'approved')
        .length;
    final closedProjects = widget.workspace.projects
        .where((p) => p.status == 'closed')
        .length;
    final totalPhases = widget.workspace.phases.length;
    final donePhases = widget.workspace.phases
        .where((p) => p.status == PhaseStatus.done)
        .length;

    final cols = <GCol<Project>>[
      GCol(
        label: 'Progetto',
        flex: 4,
        cell: (p) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            GCellText(p.name, bold: true),
            GCellText(p.code, muted: true),
          ],
        ),
      ),
      GCol(
        label: 'Cliente',
        flex: 3,
        cell: (p) => GCellText(_companyName(p.companyId), muted: true),
      ),
      GCol(
        label: 'Tipo',
        flex: 2,
        cell: (p) => GStatusChip(
          label: p.type == ProjectType.noProfit ? 'No-Profit' : 'Profit',
          color: p.type == ProjectType.noProfit
              ? GussoniBrand.info
              : GussoniBrand.primary,
          small: true,
        ),
      ),
      GCol(
        label: 'Stato',
        flex: 2,
        cell: (p) => GStatusChip(
          label: statusLabels[p.status] ?? p.status,
          color: _statusColor(p.status),
          small: true,
        ),
      ),
      GCol(
        label: 'Fasi',
        flex: 2,
        cell: (p) {
          final phases = _phasesOf(p.id);
          if (phases.isEmpty) return GCellText('—', muted: true);
          final done = _donePhases(p.id);
          return _PhaseProgress(done: done, total: phases.length);
        },
      ),
    ];

    return GScreenLayout(
      title: 'Progetti',
      count: _filtered.length,
      showHeader: widget.showHeader,
      isPinned: widget.isPinned,
      onPinContext: widget.onPinContext,
      contextActions: () => [
        if (widget.onAddProject != null && !_ganttMode)
          GContextMenuAction(
            label: 'Nuovo progetto',
            icon: Icons.create_new_folder_outlined,
            onSelected: widget.onAddProject!,
          ),
      ],
      action: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Toggle Lista / Timeline
          Container(
            margin: const EdgeInsets.only(right: 10),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.white.withValues(alpha: .58),
                  GussoniBrand.glassSurfaceMuted.withValues(alpha: .72),
                ],
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withValues(alpha: .74)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _ViewToggle(
                  icon: Icons.list_outlined,
                  active: !_ganttMode,
                  onTap: () => setState(() => _ganttMode = false),
                  tooltip: 'Lista',
                ),
                _ViewToggle(
                  icon: Icons.view_timeline_outlined,
                  active: _ganttMode,
                  onTap: () => setState(() => _ganttMode = true),
                  tooltip: 'Timeline',
                ),
              ],
            ),
          ),
          if (widget.showAddButton)
            FilledButton.icon(
              onPressed: widget.onAddProject,
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Nuovo progetto'),
            ),
        ],
      ),
      filters: _ganttMode
          ? null
          : GFilterPills<String?>(
              items: _statusOptions,
              selected: _statusFilter,
              onSelect: (s) => setState(() {
                _statusFilter = s;
              }),
              labelOf: (s) => statusLabels[s] ?? 'Tutti',
              countOf: (s) => s == null
                  ? widget.workspace.projects.length
                  : widget.workspace.projects
                        .where((p) => p.status == s)
                        .length,
            ),
      searchHint: _ganttMode ? null : 'Cerca per nome, codice…',
      onSearch: _ganttMode
          ? null
          : (v) => setState(() {
              _search = v;
            }),
      body: _ganttMode
          ? GanttGlobaleView(
              projects: widget.workspace.projects,
              phases: widget.workspace.phases,
              companies: widget.workspace.companies,
              onOpenProject: (p) => widget.onOpenProject?.call(p),
            )
          : Column(
              children: [
                _ProjectsOverview(
                  active: activeProjects,
                  approved: approvedProjects,
                  closed: closedProjects,
                  donePhases: donePhases,
                  totalPhases: totalPhases,
                ),
                const SizedBox(height: 14),
                Expanded(
                  child: GTable<Project>(
                    columns: cols,
                    rows: _filtered,
                    isSelected: (_) => false,
                    onRowTap: (p) => widget.onOpenProject?.call(p),
                    contextActionsForRow: (p) => [
                      if (widget.onOpenProject != null)
                        GContextMenuAction(
                          label: 'Apri progetto',
                          icon: Icons.open_in_new_rounded,
                          onSelected: () => widget.onOpenProject!(p),
                        ),
                      if (widget.onEditProject != null)
                        GContextMenuAction(
                          label: 'Modifica',
                          icon: Icons.edit_outlined,
                          onSelected: () => widget.onEditProject!(p),
                        ),
                      if (widget.onCloseProject != null && p.status != 'closed')
                        GContextMenuAction(
                          label: 'Chiudi progetto',
                          icon: Icons.check_circle_outline,
                          onSelected: () => widget.onCloseProject!(p),
                        ),
                    ],
                    emptyLabel: 'Nessun progetto trovato.',
                    emptyIcon: Icons.folder_open_outlined,
                  ),
                ),
              ],
            ),
    );
  }

  static Color _statusColor(String status) => switch (status) {
    'draft' => GussoniBrand.textMuted,
    'planning' => GussoniBrand.info,
    'inProgress' => GussoniBrand.warning,
    'pendingResult' => GussoniBrand.gold,
    'approved' => GussoniBrand.success,
    'closed' => GussoniBrand.textSecondary,
    _ => GussoniBrand.textMuted,
  };
}

class _ProjectsOverview extends StatelessWidget {
  const _ProjectsOverview({
    required this.active,
    required this.approved,
    required this.closed,
    required this.donePhases,
    required this.totalPhases,
  });

  final int active;
  final int approved;
  final int closed;
  final int donePhases;
  final int totalPhases;

  @override
  Widget build(BuildContext context) {
    final phaseText = totalPhases == 0 ? '—' : '$donePhases/$totalPhases';
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            GussoniBrand.glassSurfaceStrong.withValues(alpha: .88),
            GussoniBrand.glassSurfaceMuted.withValues(alpha: .70),
            GussoniBrand.primary.withValues(alpha: .08),
          ],
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withValues(alpha: .72)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x10000000),
            blurRadius: 24,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: _ProjectMetric(
              label: 'In lavorazione',
              value: '$active',
              icon: Icons.auto_awesome_motion_rounded,
              color: GussoniBrand.primary,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _ProjectMetric(
              label: 'Approvati',
              value: '$approved',
              icon: Icons.verified_rounded,
              color: GussoniBrand.success,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _ProjectMetric(
              label: 'Chiusi',
              value: '$closed',
              icon: Icons.archive_rounded,
              color: GussoniBrand.textMuted,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _ProjectMetric(
              label: 'Fasi completate',
              value: phaseText,
              icon: Icons.timeline_rounded,
              color: GussoniBrand.info,
            ),
          ),
        ],
      ),
    );
  }
}

class _ProjectMetric extends StatelessWidget {
  const _ProjectMetric({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: .46),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: Colors.white.withValues(alpha: .68)),
    ),
    child: Row(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color.withValues(alpha: .12),
            border: Border.all(color: color.withValues(alpha: .28)),
          ),
          child: Icon(icon, color: color, size: 18),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                  color: GussoniBrand.textPrimary,
                ),
              ),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: GussoniBrand.textMuted,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _ViewToggle extends StatelessWidget {
  const _ViewToggle({
    required this.icon,
    required this.active,
    required this.onTap,
    required this.tooltip,
  });
  final IconData icon;
  final bool active;
  final VoidCallback onTap;
  final String tooltip;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: active
              ? GussoniBrand.primary.withValues(alpha: .92)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(13),
          boxShadow: active
              ? [
                  BoxShadow(
                    color: GussoniBrand.primary.withValues(alpha: .18),
                    blurRadius: 12,
                    offset: const Offset(0, 6),
                  ),
                ]
              : null,
        ),
        child: Icon(
          icon,
          size: 16,
          color: active ? Colors.white : GussoniBrand.textSecondary,
        ),
      ),
    ),
  );
}

class _PhaseProgress extends StatelessWidget {
  const _PhaseProgress({required this.done, required this.total});
  final int done, total;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: total > 0 ? done / total : 0,
            minHeight: 4,
            backgroundColor: GussoniBrand.surfaceMuted,
            color: done == total ? GussoniBrand.success : GussoniBrand.primary,
          ),
        ),
      ),
      const SizedBox(width: 6),
      Text(
        '$done/$total',
        style: TextStyle(
          fontSize: 11,
          color: GussoniBrand.textMuted,
          fontWeight: FontWeight.w600,
        ),
      ),
    ],
  );
}

class _ProjectDetail extends StatefulWidget {
  const _ProjectDetail({
    required this.project,
    required this.phases,
    required this.workspace,
    required this.userId,
    required this.repository,
    required this.onClose,
    this.onEdit,
    this.onClose2,
  });
  final Project project;
  final List<ProjectPhase> phases;
  final WorkspaceSnapshot workspace;
  final String userId;
  final ApiWorkspaceRepository repository;
  final VoidCallback onClose;
  final void Function(Project)? onEdit;
  final void Function(Project)? onClose2;

  @override
  State<_ProjectDetail> createState() => _ProjectDetailState();
}

class _ProjectDetailState extends State<_ProjectDetail> {
  String _companyName() =>
      widget.workspace.companies
          .where((c) => c.id == widget.project.companyId)
          .firstOrNull
          ?.name ??
      '—';

  String _memberName(String? id) {
    if (id == null || id.isEmpty) return '—';
    return widget.workspace.companyContacts
            .where((c) => c.id == id)
            .firstOrNull
            ?.name ??
        id.substring(0, 8);
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.project;
    return GDetailPanel(
      title: p.name,
      subtitle: '${p.code} · ${_companyName()}',
      icon: Icon(
        Icons.folder_open_outlined,
        size: 18,
        color: GussoniBrand.primary,
      ),
      onClose: widget.onClose,
      actions: [
        if (widget.onEdit != null)
          IconButton(
            onPressed: () => widget.onEdit!(p),
            icon: Icon(
              Icons.edit_outlined,
              size: 16,
              color: GussoniBrand.textMuted,
            ),
          ),
      ],
      children: [
        GDetailSection(
          title: 'Info progetto',
          children: [
            GInfoRow('Cliente', _companyName()),
            GInfoRow('Codice', p.code.isNotEmpty ? p.code : '—'),
            GInfoRow(
              'Tipologia',
              p.type == ProjectType.noProfit ? 'No-Profit' : 'Profit',
            ),
            GInfoRow('Stato', _statusLabel(p.status)),
            if (p.daFaturareA.isNotEmpty)
              GInfoRow('Da fatturare a', p.daFaturareA),
            if (p.createdAt != null)
              GInfoRow(
                'Creato il',
                DateFormat('dd/MM/yyyy').format(p.createdAt!),
              ),
            if (p.grantAmount != null)
              GInfoRow(
                'Contributo',
                '€ ${NumberFormat('#,##0.00', 'it_IT').format(p.grantAmount)}',
                valueColor: GussoniBrand.success,
              ),
            if (p.successFeeAmount != null)
              GInfoRow(
                'Success fee',
                '€ ${NumberFormat('#,##0.00', 'it_IT').format(p.successFeeAmount)}',
                valueColor: GussoniBrand.gold,
              ),
          ],
        ),
        if (p.titoloProgetto.isNotEmpty ||
            p.idProgettoEsterno.isNotEmpty ||
            p.rifProgetto.isNotEmpty)
          GDetailSection(
            title: 'Dati bando / pratica',
            children: [
              if (p.titoloProgetto.isNotEmpty)
                GInfoRow('Titolo ufficiale', p.titoloProgetto),
              if (p.idProgettoEsterno.isNotEmpty)
                GInfoRow('ID progetto ente', p.idProgettoEsterno),
              if (p.rifProgetto.isNotEmpty)
                GInfoRow('Rif. progetto', p.rifProgetto),
              if (p.rifCaricamento.isNotEmpty)
                GInfoRow('Rif. caricamento', p.rifCaricamento),
              if (p.dataInizioProgetto != null)
                GInfoRow(
                  'Inizio',
                  DateFormat('dd/MM/yyyy').format(p.dataInizioProgetto!),
                ),
              if (p.dataFineProgetto != null)
                GInfoRow(
                  'Fine',
                  DateFormat('dd/MM/yyyy').format(p.dataFineProgetto!),
                ),
            ],
          ),
        if (p.contributoRichiesto != null ||
            p.finanziamentoRichiesto != null ||
            p.garanziaRichiesta != null ||
            p.creditoImpostaRichiesto != null)
          GDetailSection(
            title: 'Importi richiesti',
            children: [
              if (p.totaleProgetto != null)
                GInfoRow(
                  'Totale progetto',
                  '€ ${NumberFormat('#,##0.00', 'it_IT').format(p.totaleProgetto)}',
                ),
              if (p.totaleBeneficioEconomicoRichiesto != null)
                GInfoRow(
                  'Beneficio richiesto',
                  '€ ${NumberFormat('#,##0.00', 'it_IT').format(p.totaleBeneficioEconomicoRichiesto)}',
                ),
              if (p.contributoRichiesto != null)
                GInfoRow(
                  'Contributo',
                  '€ ${NumberFormat('#,##0.00', 'it_IT').format(p.contributoRichiesto)}',
                ),
              if (p.finanziamentoRichiesto != null)
                GInfoRow(
                  'Finanziamento',
                  '€ ${NumberFormat('#,##0.00', 'it_IT').format(p.finanziamentoRichiesto)}',
                ),
              if (p.garanziaRichiesta != null)
                GInfoRow(
                  'Garanzia',
                  '€ ${NumberFormat('#,##0.00', 'it_IT').format(p.garanziaRichiesta)}',
                ),
              if (p.creditoImpostaRichiesto != null)
                GInfoRow(
                  'Credito d\'imposta',
                  '€ ${NumberFormat('#,##0.00', 'it_IT').format(p.creditoImpostaRichiesto)}',
                ),
            ],
          ),
        if (p.avanzamentoPratica != AvanzamentoPratica.none ||
            p.esitoPratica != EsitoPratica.none)
          GDetailSection(
            title: 'Avanzamento pratica',
            children: [
              if (p.avanzamentoPratica != AvanzamentoPratica.none)
                GInfoRow(
                  'Avanzamento',
                  _avanzamentoLabel(p.avanzamentoPratica),
                ),
              if (p.esitoPratica != EsitoPratica.none)
                GInfoRow(
                  'Esito',
                  p.esitoPratica.name == 'accolta'
                      ? p.esitoPratica.name
                      : _esitoLabel(p.esitoPratica),
                  valueColor: p.esitoPratica == EsitoPratica.accolta
                      ? GussoniBrand.success
                      : p.esitoPratica == EsitoPratica.respinta ||
                            p.esitoPratica == EsitoPratica.nonAmmissibile
                      ? GussoniBrand.error
                      : null,
                ),
              if (p.dataStato != null)
                GInfoRow(
                  'Data stato',
                  DateFormat('dd/MM/yyyy').format(p.dataStato!),
                ),
            ],
          ),
        if (p.contributoRicevuto != null || p.finanziamentoRicevuto != null)
          GDetailSection(
            title: 'Importi ricevuti',
            children: [
              if (p.totaleProgettoRidefinito != null)
                GInfoRow(
                  'Totale ridefinito',
                  '€ ${NumberFormat('#,##0.00', 'it_IT').format(p.totaleProgettoRidefinito)}',
                ),
              if (p.totaleBeneficioEconomicoRicevuto != null)
                GInfoRow(
                  'Beneficio ricevuto',
                  '€ ${NumberFormat('#,##0.00', 'it_IT').format(p.totaleBeneficioEconomicoRicevuto)}',
                  valueColor: GussoniBrand.success,
                ),
              if (p.contributoRicevuto != null)
                GInfoRow(
                  'Contributo',
                  '€ ${NumberFormat('#,##0.00', 'it_IT').format(p.contributoRicevuto)}',
                  valueColor: GussoniBrand.success,
                ),
              if (p.finanziamentoRicevuto != null)
                GInfoRow(
                  'Finanziamento',
                  '€ ${NumberFormat('#,##0.00', 'it_IT').format(p.finanziamentoRicevuto)}',
                ),
              if (p.garanziaRicevuta != null)
                GInfoRow(
                  'Garanzia',
                  '€ ${NumberFormat('#,##0.00', 'it_IT').format(p.garanziaRicevuta)}',
                ),
              if (p.creditoImpostaRicevuto != null)
                GInfoRow(
                  'Credito d\'imposta',
                  '€ ${NumberFormat('#,##0.00', 'it_IT').format(p.creditoImpostaRicevuto)}',
                ),
            ],
          ),
        if (p.termineRendicontazione != null ||
            p.statoRendicontazione != StatoRendicontazione.none)
          GDetailSection(
            title: 'Rendicontazione',
            children: [
              if (p.termineRendicontazione != null)
                GInfoRow(
                  'Termine',
                  DateFormat('dd/MM/yyyy').format(p.termineRendicontazione!),
                  valueColor: p.termineRendicontazione!.isBefore(DateTime.now())
                      ? GussoniBrand.error
                      : null,
                ),
              if (p.statoRendicontazione != StatoRendicontazione.none)
                GInfoRow(
                  'Stato',
                  p.statoRendicontazione == StatoRendicontazione.aperta
                      ? 'Aperta'
                      : 'Chiusa',
                  valueColor:
                      p.statoRendicontazione == StatoRendicontazione.chiusa
                      ? GussoniBrand.success
                      : GussoniBrand.warning,
                ),
            ],
          ),
        if (widget.phases.isNotEmpty)
          GDetailSection(
            title: 'Fasi (${widget.phases.length})',
            children: [
              ...widget.phases.map(
                (phase) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    children: [
                      _PhaseStatusDot(status: phase.status),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            GCellText(
                              phase.name,
                              bold: phase.status == PhaseStatus.inProgress,
                            ),
                            if (phase.assignedUserId != null)
                              GCellText(
                                _memberName(phase.assignedUserId),
                                muted: true,
                              ),
                          ],
                        ),
                      ),
                      _PhaseStatusChip(status: phase.status),
                    ],
                  ),
                ),
              ),
            ],
          ),
        if (p.status != 'closed' &&
            p.status != 'approved' &&
            widget.onClose2 != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: OutlinedButton.icon(
              onPressed: () => _showCloseDialog(context),
              icon: const Icon(Icons.check_circle_outline, size: 14),
              label: const Text('Chiudi progetto e genera fattura'),
              style: OutlinedButton.styleFrom(
                foregroundColor: GussoniBrand.success,
                side: BorderSide(color: GussoniBrand.success.withOpacity(.5)),
              ),
            ),
          ),
      ],
    );
  }

  String _statusLabel(String s) => switch (s) {
    'draft' => 'Bozza',
    'planning' => 'Pianificazione',
    'inProgress' => 'In corso',
    'pendingResult' => 'In attesa esito',
    'approved' => 'Approvato',
    'closed' => 'Chiuso',
    _ => s,
  };

  String _avanzamentoLabel(AvanzamentoPratica a) => switch (a) {
    AvanzamentoPratica.none => '—',
    AvanzamentoPratica.presentata => 'Presentata',
    AvanzamentoPratica.inEsecuzione => 'In esecuzione',
    AvanzamentoPratica.conclusa => 'Conclusa',
  };

  String _esitoLabel(EsitoPratica e) => switch (e) {
    EsitoPratica.none => '—',
    EsitoPratica.accolta => 'Accolta',
    EsitoPratica.respinta => 'Respinta',
    EsitoPratica.rinunciata => 'Rinunciata',
    EsitoPratica.nonAmmissibile => 'Non ammissibile',
    EsitoPratica.inAttesa => 'In attesa',
  };

  void _showCloseDialog(BuildContext context) {
    final ctrl = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (ctx) => NexoraDialog(
        title: 'Chiudi progetto',
        icon: Icons.task_alt_outlined,
        accent: GussoniBrand.gold,
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: GussoniBrand.goldBg,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: GussoniBrand.gold.withValues(alpha: .30),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, size: 16, color: GussoniBrand.gold),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'La success fee verrà calcolata automaticamente '
                      '(9% ≤ €50.000, 8% > €50.000) e verrà creata una fattura bozza.',
                      style: TextStyle(fontSize: 12, color: GussoniBrand.gold),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: ctrl,
              keyboardType: TextInputType.number,
              decoration: NexoraDialog.fieldDecoration(
                'Contributo ottenuto (€) *',
                prefix: '€ ',
              ),
            ),
            const SizedBox(height: 4),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            style: NexoraDialog.cancelButtonStyle(),
            child: const Text('Annulla'),
          ),
          FilledButton(
            onPressed: () async {
              final amount = double.tryParse(ctrl.text.replaceAll(',', '.'));
              if (amount == null || amount <= 0) return;
              Navigator.of(ctx).pop();
              await widget.repository.closeProjectWithInvoice(
                userId: widget.userId,
                project: widget.project,
                grantAmount: amount,
              );
            },
            style: NexoraDialog.primaryButtonStyle(color: GussoniBrand.gold),
            child: const Text('Chiudi e genera fattura'),
          ),
        ],
      ),
    );
  }
}

class _PhaseStatusDot extends StatelessWidget {
  const _PhaseStatusDot({required this.status});
  final PhaseStatus status;
  @override
  Widget build(BuildContext context) => Container(
    width: 8,
    height: 8,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: switch (status) {
        PhaseStatus.notStarted => GussoniBrand.textDisabled,
        PhaseStatus.inProgress => GussoniBrand.warning,
        PhaseStatus.done => GussoniBrand.success,
      },
    ),
  );
}

class _PhaseStatusChip extends StatelessWidget {
  const _PhaseStatusChip({required this.status});
  final PhaseStatus status;
  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      PhaseStatus.notStarted => ('Non iniziata', GussoniBrand.textDisabled),
      PhaseStatus.inProgress => ('In corso', GussoniBrand.warning),
      PhaseStatus.done => ('Completata', GussoniBrand.success),
    };
    return GStatusChip(label: label, color: color, small: true);
  }
}
