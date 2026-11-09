import '../../../brand_config.dart';
// Schede dettaglio semplificate per: Progetto, Fattura, Task, Prodotto
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../app/context_archive_browser.dart';
import '../../../data/api_workspace_repository.dart';
import '../../../data/team_repository.dart';
import '../../../gussoni/widgets/g_table.dart';
import '../../../models/domain_models.dart';
import '../../../gussoni/screens/gantt_view.dart';
import '../../models/crm_extra_models.dart';
import 'detail_widgets.dart';

// ────────────────────────────────────────────────
// Project Detail
// ────────────────────────────────────────────────

class ProjectDetailPage extends StatefulWidget {
  const ProjectDetailPage({
    super.key,
    required this.project,
    required this.workspace,
    required this.crmData,
    required this.onBack,
    required this.onEdit,
    required this.userId,
    required this.repository,
    this.onAddPhase,
    this.onAddTask,
    this.onAddTaskToPhase,
    this.onAddTimeTrack,
    this.onOpenTask,
    this.onCreaAnticipoFattura,
    this.teamMembers = const [],
  });
  final Project project;
  final WorkspaceSnapshot workspace;
  final CrmData crmData;
  final String userId;
  final ApiWorkspaceRepository repository;
  final VoidCallback onBack;
  final Future<void> Function(Project) onEdit;
  final VoidCallback? onAddPhase;
  final VoidCallback? onAddTask;
  final void Function(ProjectPhase phase)? onAddTaskToPhase;
  final VoidCallback? onAddTimeTrack;
  final void Function(WorkTask task)? onOpenTask;
  final VoidCallback? onCreaAnticipoFattura;
  final List<TeamMember> teamMembers;

  @override
  State<ProjectDetailPage> createState() => _ProjectDetailPageState();
}

class _ProjectDetailPageState extends State<ProjectDetailPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  bool _ganttMode = false;

  Future<void> _openProjectFilesDrawer() async {
    final companyName = _company.trim();
    final projectName = _p.name.trim();
    if (companyName.isEmpty || companyName == '—' || projectName.isEmpty) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cartella progetto non disponibile.')),
      );
      return;
    }

    await showGeneralDialog<void>(
      context: context,
      barrierLabel: 'File progetto',
      barrierDismissible: true,
      barrierColor: Colors.black26,
      pageBuilder: (context, _, __) {
        return Align(
          alignment: Alignment.centerRight,
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: 460,
              height: MediaQuery.of(context).size.height,
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(left: BorderSide(color: GussoniBrand.border)),
                boxShadow: [
                  BoxShadow(
                    color: Color(0x22000000),
                    blurRadius: 18,
                    offset: Offset(-6, 0),
                  ),
                ],
              ),
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'File progetto',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: GussoniBrand.textMuted,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _p.name,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w800,
                                    color: GussoniBrand.textPrimary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            onPressed: () => Navigator.of(context).pop(),
                            icon: const Icon(
                              Icons.close,
                              color: GussoniBrand.textMuted,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Expanded(
                        child: ContextArchiveBrowser(
                          rootPath: 'Clienti/$companyName/$projectName',
                          rootLabel: projectName,
                          title: 'Archivio progetto',
                          mode: ContextArchiveBrowserMode.list,
                          showHeader: true,
                          emptyLabel:
                              'Nessun file presente nella cartella di questo progetto.',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
        );
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(1, 0),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        );
      },
    );
  }

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 4, vsync: this);
    _tabs.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Project get _p => widget.project;
  WorkspaceSnapshot get _ws => widget.workspace;

  List<WorkTask> get _tasks =>
      _ws.tasks.where((t) => t.projectId == _p.id).toList();
  List<ProjectPhase> get _phases =>
      _ws.phases.where((p) => p.projectId == _p.id).toList()
        ..sort((a, b) => a.order.compareTo(b.order));
  List<TimeTrack> get _tracks =>
      _ws.timeTracks.where((t) => t.projectId == _p.id).toList();
  String get _company =>
      _ws.companies.where((c) => c.id == _p.companyId).firstOrNull?.name ?? '—';
  double get _loggedHours => _tracks.fold(0.0, (s, t) => s + t.hours);
  double get _estimatedHours =>
      _tasks.fold(0.0, (s, t) => s + t.estimatedHours);
  int get _doneTasks => _tasks.where((t) => t.status == TaskStatus.done).length;

  String _memberName(String? userId) {
    if (userId == null || userId.isEmpty) return 'Non assegnata';
    final teamMember = widget.teamMembers
        .where((member) => member.userId == userId)
        .firstOrNull;
    if (teamMember != null) return teamMember.displayName;
    final contact = _ws.companyContacts
        .where((c) => c.id == userId)
        .firstOrNull;
    if (contact != null) return contact.name;
    return userId.length > 12 ? userId.substring(0, 12) : userId;
  }

  Future<void> _openPhasePlanning(ProjectPhase phase) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => _EditProjectPhaseDialog(
        phase: phase,
        teamMembers: widget.teamMembers,
        onSave: (updated) =>
            widget.repository.updatePhasePlanning(widget.userId, updated),
      ),
    );
  }

  Color get _statusColor {
    return switch (_p.status) {
      'inProgress' => GussoniBrand.warning,
      'approved' => GussoniBrand.success,
      'closed' => GussoniBrand.textMuted,
      'pendingResult' => GussoniBrand.gold,
      'rejected' => GussoniBrand.error,
      _ => GussoniBrand.info,
    };
  }

  String get _statusLabel => switch (_p.status) {
    'draft' => 'Bozza',
    'planning' => 'Pianificazione',
    'inProgress' => 'In corso',
    'pendingResult' => 'In attesa esito',
    'approved' => 'Approvato',
    'closed' => 'Chiuso',
    'rejected' => 'Respinto',
    _ => _p.status,
  };

  List<WorkTask> _phaseTasks(ProjectPhase phase) =>
      _tasks.where((task) => task.phaseId == phase.id).toList()
        ..sort((a, b) => a.deadline.compareTo(b.deadline));

  List<WorkTask> get _tasksWithoutPhase {
    final phaseIds = _phases.map((p) => p.id).toSet();
    return _tasks
        .where((t) => t.phaseId.isEmpty || !phaseIds.contains(t.phaseId))
        .toList()
      ..sort((a, b) => a.deadline.compareTo(b.deadline));
  }

  String _hm(double h) {
    final m = (h * 60).round();
    return '${m ~/ 60}h${(m % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // ── Top bar ──────────────────────────────────────────────────────
        Container(
          margin: const EdgeInsets.fromLTRB(18, 14, 18, 0),
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 0),
          decoration: GussoniBrand.glassPanel(
            radius: 26,
            accent: GussoniBrand.surface,
            opacity: .96,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Back
              DetailBackBar(
                label: 'Panoramica progetti',
                onBack: widget.onBack,
                actions: [
                  if (_tabs.index == 0 &&
                      _phases.any((p) => p.deadline != null))
                    Container(
                      decoration: GussoniBrand.glassField(radius: 16),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _GanttToggleBtn(
                            icon: Icons.list_outlined,
                            active: !_ganttMode,
                            tooltip: 'Lista fasi',
                            onTap: () => setState(() => _ganttMode = false),
                          ),
                          _GanttToggleBtn(
                            icon: Icons.view_timeline_outlined,
                            active: _ganttMode,
                            tooltip: 'Timeline Gantt',
                            onTap: () => setState(() => _ganttMode = true),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(width: 8),
                  _ProjectGlassAction(
                    icon: Icons.edit_outlined,
                    tooltip: 'Modifica progetto',
                    onTap: () => widget.onEdit(_p),
                  ),
                  const SizedBox(width: 8),
                  _ProjectGlassAction(
                    icon: Icons.folder_open_outlined,
                    tooltip: 'File progetto',
                    onTap: _openProjectFilesDrawer,
                  ),
                ],
              ),
              Row(
                children: [
                  Container(
                    width: 58,
                    height: 58,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _statusColor.withValues(alpha: .14),
                      border: Border.all(
                        color: _statusColor.withValues(alpha: .32),
                      ),
                    ),
                    child: Icon(
                      Icons.folder_open_rounded,
                      color: _statusColor,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _p.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 25,
                            fontWeight: FontWeight.w900,
                            color: GussoniBrand.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          [
                            if (_p.code.isNotEmpty) _p.code,
                            _company,
                            '${_phases.length} fasi',
                            '${_tasks.length} task',
                          ].join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13,
                            color: GussoniBrand.textMuted,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  _ProjectStatusPill(label: _statusLabel, color: _statusColor),
                ],
              ),
              const SizedBox(height: 16),
              _ProjectHeroMetrics(
                logged: _hm(_loggedHours),
                estimated: _hm(_estimatedHours),
                tasks: '$_doneTasks/${_tasks.length}',
                phases:
                    '${_phases.where((p) => p.status == PhaseStatus.done).length}/${_phases.length}',
                accent: _statusColor,
              ),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: Container(
                  color: GussoniBrand.surfaceSubtle,
                  child: TabBar(
                    controller: _tabs,
                    labelColor: GussoniBrand.textPrimary,
                    unselectedLabelColor: GussoniBrand.textMuted,
                    indicator: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      color: GussoniBrand.surface,
                      border: Border.all(color: GussoniBrand.border),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x1202332A),
                          blurRadius: 10,
                          offset: Offset(0, 4),
                        ),
                      ],
                    ),
                    indicatorPadding: const EdgeInsets.symmetric(
                      horizontal: 2,
                      vertical: 4,
                    ),
                    dividerColor: Colors.transparent,
                    labelStyle: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0,
                    ),
                    unselectedLabelStyle: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0,
                    ),
                    tabs: const [
                      Tab(text: 'Fasi'),
                      Tab(text: 'Pratica'),
                      Tab(text: 'Fatture'),
                      Tab(text: 'Dettagli'),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),

        // ── Tab content ──────────────────────────────────────────────────
        Expanded(
          child: TabBarView(
            controller: _tabs,
            children: [
              // ── Tab 1: Suddivisione del lavoro ───────────────────────────
              if (_ganttMode)
                ProjectGanttView(phases: _phases)
              else
                SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Banner anticipo non emesso
                      if (!_p.anticipoEmesso) ...[
                        Container(
                          margin: const EdgeInsets.only(bottom: 16),
                          padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
                          decoration: BoxDecoration(
                            color: GussoniBrand.goldBg,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: GussoniBrand.gold.withValues(alpha: 0.4),
                            ),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.warning_amber_rounded,
                                size: 18,
                                color: GussoniBrand.gold,
                              ),
                              const SizedBox(width: 10),
                              const Expanded(
                                child: Text(
                                  'Nessuna fattura di anticipo / avvio servizio emessa per questo progetto.',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: GussoniBrand.gold,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              if (widget.onCreaAnticipoFattura != null)
                                OutlinedButton(
                                  onPressed: widget.onCreaAnticipoFattura,
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: GussoniBrand.gold,
                                    side: BorderSide(
                                      color: GussoniBrand.gold.withValues(
                                        alpha: 0.6,
                                      ),
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 8,
                                    ),
                                    textStyle: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  child: const Text('Crea bozza'),
                                ),
                            ],
                          ),
                        ),
                      ],
                      // Actions
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: .38),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: .64),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.account_tree_rounded,
                              size: 18,
                              color: GussoniBrand.primary,
                            ),
                            const SizedBox(width: 10),
                            const Expanded(
                              child: Text(
                                'Organizza il progetto in fasi, assegna task e apri ogni attività in un pannello dedicato.',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: GussoniBrand.textSecondary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            if (widget.onAddPhase != null)
                              OutlinedButton.icon(
                                onPressed: widget.onAddPhase,
                                icon: const Icon(Icons.add, size: 14),
                                label: const Text('Fase'),
                              ),
                            const SizedBox(width: 8),
                            if (widget.onAddTask != null)
                              FilledButton.icon(
                                onPressed: widget.onAddTask,
                                icon: const Icon(Icons.add, size: 14),
                                label: const Text('Task'),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      // Phases
                      ..._phases.map(
                        (phase) => _PhaseRow(
                          phase: phase,
                          tasks: _phaseTasks(phase),
                          tracks: _tracks,
                          onAddTask: widget.onAddTaskToPhase == null
                              ? null
                              : () => widget.onAddTaskToPhase!(phase),
                          onOpenTask: widget.onOpenTask,
                          assigneeLabel: _memberName(phase.assignedUserId),
                          onEdit: () => _openPhasePlanning(phase),
                          hm: _hm,
                        ),
                      ),
                      if (_tasksWithoutPhase.isNotEmpty)
                        _PhaseRow(
                          phase: null,
                          tasks: _tasksWithoutPhase,
                          tracks: _tracks,
                          assigneeLabel: '—',
                          onAddTask: widget.onAddTask,
                          onOpenTask: widget.onOpenTask,
                          hm: _hm,
                        ),
                      if (_phases.isEmpty && _tasks.isEmpty)
                        _EmptyState(
                          label: 'Nessuna fase o task presente.',
                          onAction: widget.onAddPhase,
                          actionLabel: 'Aggiungi fase',
                        ),
                    ],
                  ),
                ),

              // ── Tab 2: Pratica ────────────────────────────────────────────
              _ProjectPraticaTab(
                project: _p,
                workspace: _ws,
                userId: widget.userId,
                repository: widget.repository,
              ),

              // ── Tab 3: Fatture ───────────────────────────────────────────
              _ProjectInvoicingTab(
                project: _p,
                workspace: _ws,
                userId: widget.userId,
                repository: widget.repository,
              ),

              // ── Tab 4: Dettagli progetto ─────────────────────────────────
              SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: LayoutBuilder(
                  builder: (ctx, c) {
                    final twoCol = c.maxWidth > 600;
                    final dettagli = _DettagliCard(
                      project: _p,
                      company: _company,
                    );
                    final descrizione = _DescrizioneCard(notes: _p.notes);
                    if (twoCol) {
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: dettagli),
                          const SizedBox(width: 16),
                          Expanded(child: descrizione),
                        ],
                      );
                    }
                    return Column(
                      children: [
                        dettagli,
                        const SizedBox(height: 16),
                        descrizione,
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Pratica tab (dentro il progetto) ─────────────────────────────────────────

class _ProjectPraticaTab extends StatelessWidget {
  const _ProjectPraticaTab({
    required this.project,
    required this.workspace,
    required this.userId,
    required this.repository,
  });

  final Project project;
  final WorkspaceSnapshot workspace;
  final String userId;
  final ApiWorkspaceRepository repository;

  Opportunity? get _opp => project.opportunityId == null
      ? null
      : workspace.opportunities
            .where((o) => o.id == project.opportunityId)
            .firstOrNull;

  static String _avanzamentoLabel(AvanzamentoPratica a) => switch (a) {
    AvanzamentoPratica.none => '—',
    AvanzamentoPratica.presentata => 'Presentata',
    AvanzamentoPratica.inEsecuzione => 'In esecuzione',
    AvanzamentoPratica.conclusa => 'Conclusa',
  };

  static String _esitoLabel(EsitoPratica e) => switch (e) {
    EsitoPratica.none => '—',
    EsitoPratica.accolta => 'Accolta',
    EsitoPratica.respinta => 'Respinta',
    EsitoPratica.rinunciata => 'Rinunciata',
    EsitoPratica.nonAmmissibile => 'Non ammissibile',
    EsitoPratica.inAttesa => 'In attesa',
  };

  static Color? _esitoColor(EsitoPratica e) => switch (e) {
    EsitoPratica.accolta => GussoniBrand.success,
    EsitoPratica.respinta => GussoniBrand.error,
    EsitoPratica.nonAmmissibile => GussoniBrand.error,
    EsitoPratica.rinunciata => GussoniBrand.warning,
    _ => null,
  };

  @override
  Widget build(BuildContext context) {
    final opp = _opp;
    final fmt = NumberFormat.currency(
      locale: 'it_IT',
      symbol: '€',
      decimalDigits: 2,
    );
    final dateFmt = DateFormat('dd/MM/yyyy');

    if (opp == null) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.link_off, size: 40, color: GussoniBrand.textDisabled),
            SizedBox(height: 12),
            Text(
              'Nessuna opportunità collegata a questo progetto.',
              style: TextStyle(fontSize: 14, color: GussoniBrand.textMuted),
            ),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Barra avanzamento
          _PraticaProgressBar(opp: opp),
          const SizedBox(height: 20),

          // Avanzamento + importi
          LayoutBuilder(
            builder: (ctx, c) {
              final two = c.maxWidth > 600;

              final statusCard = _SectionCard(
                title: 'Stato pratica',
                icon: Icons.trending_up_outlined,
                action: FilledButton.icon(
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (_) => _EditPraticaDialog(
                      opportunity: opp,
                      userId: userId,
                      repository: repository,
                    ),
                  ),
                  icon: const Icon(Icons.edit_outlined, size: 14),
                  label: const Text('Modifica'),
                  style: FilledButton.styleFrom(
                    backgroundColor: GussoniBrand.primary,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    textStyle: const TextStyle(fontSize: 12),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _DRow(
                      'Avanzamento',
                      _avanzamentoLabel(opp.avanzamentoPratica),
                    ),
                    _DRow(
                      'Esito',
                      _esitoLabel(opp.esitoPratica),
                      valueColor: _esitoColor(opp.esitoPratica),
                    ),
                    if (opp.dataStato != null)
                      _DRow('Data stato', dateFmt.format(opp.dataStato!)),
                    if (opp.termineRendicontazione != null)
                      _DRow(
                        'Termine rendicontazione',
                        dateFmt.format(opp.termineRendicontazione!),
                        valueColor:
                            opp.termineRendicontazione!.isBefore(DateTime.now())
                            ? GussoniBrand.error
                            : null,
                      ),
                  ],
                ),
              );

              final importiRichiesti = _SectionCard(
                title: 'Importi richiesti',
                icon: Icons.request_quote_outlined,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (opp.totaleProgetto != null)
                      _DRow('Totale progetto', fmt.format(opp.totaleProgetto)),
                    if (opp.contributoRichiesto != null)
                      _DRow(
                        'Contributo richiesto',
                        fmt.format(opp.contributoRichiesto),
                      ),
                    if (opp.finanziamentoRichiesto != null)
                      _DRow(
                        'Finanziamento richiesto',
                        fmt.format(opp.finanziamentoRichiesto),
                      ),
                    if (opp.garanziaRichiesta != null)
                      _DRow(
                        'Garanzia richiesta',
                        fmt.format(opp.garanziaRichiesta),
                      ),
                    if (opp.creditoImpostaRichiesto != null)
                      _DRow(
                        'Credito imposta',
                        fmt.format(opp.creditoImpostaRichiesto),
                      ),
                    if (opp.totaleProgetto == null &&
                        opp.contributoRichiesto == null &&
                        opp.finanziamentoRichiesto == null)
                      const Text(
                        'Nessun importo inserito.',
                        style: TextStyle(
                          fontSize: 13,
                          color: GussoniBrand.textMuted,
                        ),
                      ),
                  ],
                ),
              );

              if (two) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: statusCard),
                    const SizedBox(width: 16),
                    Expanded(child: importiRichiesti),
                  ],
                );
              }
              return Column(
                children: [
                  statusCard,
                  const SizedBox(height: 16),
                  importiRichiesti,
                ],
              );
            },
          ),

          // Importi ricevuti (solo se presenti)
          if (opp.contributoRicevuto != null ||
              opp.totaleBeneficioEconomicoRicevuto != null) ...[
            const SizedBox(height: 16),
            _SectionCard(
              title: 'Importi ricevuti',
              icon: Icons.euro_outlined,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (opp.totaleBeneficioEconomicoRicevuto != null)
                    _DRow(
                      'Beneficio ricevuto',
                      fmt.format(opp.totaleBeneficioEconomicoRicevuto),
                      valueColor: GussoniBrand.success,
                    ),
                  if (opp.contributoRicevuto != null)
                    _DRow(
                      'Contributo ricevuto',
                      fmt.format(opp.contributoRicevuto),
                      valueColor: GussoniBrand.success,
                    ),
                  if (opp.finanziamentoRicevuto != null)
                    _DRow(
                      'Finanziamento ricevuto',
                      fmt.format(opp.finanziamentoRicevuto),
                    ),
                  if (opp.garanziaRicevuta != null)
                    _DRow(
                      'Garanzia ricevuta',
                      fmt.format(opp.garanziaRicevuta),
                    ),
                  if (opp.creditoImpostaRicevuto != null)
                    _DRow(
                      'Credito imposta ricevuto',
                      fmt.format(opp.creditoImpostaRicevuto),
                    ),
                  if (opp.totaleProgettoRidefinito != null)
                    _DRow(
                      'Totale ridefinito',
                      fmt.format(opp.totaleProgettoRidefinito),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Dialog modifica pratica ────────────────────────────────────────────────────

class _EditPraticaDialog extends StatefulWidget {
  const _EditPraticaDialog({
    required this.opportunity,
    required this.userId,
    required this.repository,
  });
  final Opportunity opportunity;
  final String userId;
  final ApiWorkspaceRepository repository;

  @override
  State<_EditPraticaDialog> createState() => _EditPraticaDialogState();
}

class _EditPraticaDialogState extends State<_EditPraticaDialog> {
  late AvanzamentoPratica _avanzamento;
  late EsitoPratica _esito;
  DateTime? _dataStato;
  DateTime? _termineRendicontazione;

  final _totaleCtrl = TextEditingController();
  final _contributoRichiesto = TextEditingController();
  final _finanzRichiesto = TextEditingController();
  final _garanziaRichiesta = TextEditingController();
  final _creditoRichiesto = TextEditingController();
  final _beneficioRicevuto = TextEditingController();
  final _contributoRicevuto = TextEditingController();
  final _finanzRicevuto = TextEditingController();
  final _garanziaRicevuta = TextEditingController();
  final _creditoRicevuto = TextEditingController();
  final _totaleRidefinito = TextEditingController();

  bool _saving = false;

  static double? _d(String s) =>
      s.trim().isEmpty ? null : double.tryParse(s.replaceAll(',', '.'));
  static String _fmt(double? v) => v != null ? v.toStringAsFixed(2) : '';

  @override
  void initState() {
    super.initState();
    final o = widget.opportunity;
    _avanzamento = o.avanzamentoPratica;
    _esito = o.esitoPratica;
    _dataStato = o.dataStato;
    _termineRendicontazione = o.termineRendicontazione;
    _totaleCtrl.text = _fmt(o.totaleProgetto);
    _contributoRichiesto.text = _fmt(o.contributoRichiesto);
    _finanzRichiesto.text = _fmt(o.finanziamentoRichiesto);
    _garanziaRichiesta.text = _fmt(o.garanziaRichiesta);
    _creditoRichiesto.text = _fmt(o.creditoImpostaRichiesto);
    _beneficioRicevuto.text = _fmt(o.totaleBeneficioEconomicoRicevuto);
    _contributoRicevuto.text = _fmt(o.contributoRicevuto);
    _finanzRicevuto.text = _fmt(o.finanziamentoRicevuto);
    _garanziaRicevuta.text = _fmt(o.garanziaRicevuta);
    _creditoRicevuto.text = _fmt(o.creditoImpostaRicevuto);
    _totaleRidefinito.text = _fmt(o.totaleProgettoRidefinito);
  }

  @override
  void dispose() {
    for (final c in [
      _totaleCtrl,
      _contributoRichiesto,
      _finanzRichiesto,
      _garanziaRichiesta,
      _creditoRichiesto,
      _beneficioRicevuto,
      _contributoRicevuto,
      _finanzRicevuto,
      _garanziaRicevuta,
      _creditoRicevuto,
      _totaleRidefinito,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final updated = widget.opportunity.copyWith(
        avanzamentoPratica: _avanzamento,
        esitoPratica: _esito,
        dataStato: _dataStato,
        termineRendicontazione: _termineRendicontazione,
        totaleProgetto: _d(_totaleCtrl.text),
        contributoRichiesto: _d(_contributoRichiesto.text),
        finanziamentoRichiesto: _d(_finanzRichiesto.text),
        garanziaRichiesta: _d(_garanziaRichiesta.text),
        creditoImpostaRichiesto: _d(_creditoRichiesto.text),
        totaleBeneficioEconomicoRicevuto: _d(_beneficioRicevuto.text),
        contributoRicevuto: _d(_contributoRicevuto.text),
        finanziamentoRicevuto: _d(_finanzRicevuto.text),
        garanziaRicevuta: _d(_garanziaRicevuta.text),
        creditoImpostaRicevuto: _d(_creditoRicevuto.text),
        totaleProgettoRidefinito: _d(_totaleRidefinito.text),
      );
      await widget.repository.updateOpportunity(widget.userId, updated);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) setState(() => _saving = false);
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Errore: $e')));
    }
  }

  Future<void> _pickDate(
    DateTime? current,
    void Function(DateTime) onPicked,
  ) async {
    final d = await showDatePicker(
      context: context,
      initialDate: current ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (d != null) onPicked(d);
  }

  @override
  Widget build(BuildContext context) {
    final dateFmt = DateFormat('dd/MM/yyyy');
    return Dialog(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 640,
          maxHeight: MediaQuery.of(context).size.height * 0.90,
        ),
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
              child: Row(
                children: [
                  Icon(
                    Icons.trending_up_outlined,
                    size: 18,
                    color: GussoniBrand.primary,
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Avanzamento pratica',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(
                      Icons.close,
                      color: GussoniBrand.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),

            // Body
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Stato
                    const _FormSectionLabel('Stato pratica'),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<AvanzamentoPratica>(
                            value: _avanzamento,
                            decoration: const InputDecoration(
                              labelText: 'Avanzamento',
                              border: OutlineInputBorder(),
                            ),
                            items: AvanzamentoPratica.values
                                .map(
                                  (v) => DropdownMenuItem(
                                    value: v,
                                    child: Text(switch (v) {
                                      AvanzamentoPratica.none => '—',
                                      AvanzamentoPratica.presentata =>
                                        'Presentata',
                                      AvanzamentoPratica.inEsecuzione =>
                                        'In esecuzione',
                                      AvanzamentoPratica.conclusa => 'Conclusa',
                                    }),
                                  ),
                                )
                                .toList(),
                            onChanged: (v) => setState(
                              () => _avanzamento = v ?? _avanzamento,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: DropdownButtonFormField<EsitoPratica>(
                            value: _esito,
                            decoration: const InputDecoration(
                              labelText: 'Esito',
                              border: OutlineInputBorder(),
                            ),
                            items: EsitoPratica.values
                                .map(
                                  (v) => DropdownMenuItem(
                                    value: v,
                                    child: Text(switch (v) {
                                      EsitoPratica.none => '—',
                                      EsitoPratica.inAttesa => 'In attesa',
                                      EsitoPratica.accolta => 'Accolta',
                                      EsitoPratica.respinta => 'Respinta',
                                      EsitoPratica.rinunciata => 'Rinunciata',
                                      EsitoPratica.nonAmmissibile =>
                                        'Non ammissibile',
                                    }),
                                  ),
                                )
                                .toList(),
                            onChanged: (v) =>
                                setState(() => _esito = v ?? _esito),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _DateField(
                            label: 'Data stato',
                            value: _dataStato,
                            dateFmt: dateFmt,
                            onPick: () => _pickDate(
                              _dataStato,
                              (d) => setState(() => _dataStato = d),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _DateField(
                            label: 'Termine rendicontazione',
                            value: _termineRendicontazione,
                            dateFmt: dateFmt,
                            onPick: () => _pickDate(
                              _termineRendicontazione,
                              (d) =>
                                  setState(() => _termineRendicontazione = d),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // Importi richiesti
                    const _FormSectionLabel('Importi richiesti'),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: _EuroField(
                            ctrl: _totaleCtrl,
                            label: 'Totale progetto',
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _EuroField(
                            ctrl: _contributoRichiesto,
                            label: 'Contributo richiesto',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: _EuroField(
                            ctrl: _finanzRichiesto,
                            label: 'Finanziamento richiesto',
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _EuroField(
                            ctrl: _garanziaRichiesta,
                            label: 'Garanzia richiesta',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    _EuroField(
                      ctrl: _creditoRichiesto,
                      label: 'Credito imposta richiesto',
                    ),
                    const SizedBox(height: 20),

                    // Importi ricevuti
                    const _FormSectionLabel(
                      'Importi ricevuti (post-concessione)',
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: _EuroField(
                            ctrl: _beneficioRicevuto,
                            label: 'Beneficio economico ricevuto',
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _EuroField(
                            ctrl: _contributoRicevuto,
                            label: 'Contributo ricevuto',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: _EuroField(
                            ctrl: _finanzRicevuto,
                            label: 'Finanziamento ricevuto',
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _EuroField(
                            ctrl: _garanziaRicevuta,
                            label: 'Garanzia ricevuta',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: _EuroField(
                            ctrl: _creditoRicevuto,
                            label: 'Credito imposta ricevuto',
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _EuroField(
                            ctrl: _totaleRidefinito,
                            label: 'Totale progetto ridefinito',
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const Divider(height: 1),

            // Footer
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              child: Row(
                children: [
                  const Spacer(),
                  TextButton(
                    onPressed: _saving
                        ? null
                        : () => Navigator.of(context).pop(),
                    child: const Text('Annulla'),
                  ),
                  const SizedBox(width: 10),
                  FilledButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: _saving
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.save_outlined, size: 16),
                    label: const Text('Salva'),
                    style: FilledButton.styleFrom(
                      backgroundColor: GussoniBrand.primary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FormSectionLabel extends StatelessWidget {
  const _FormSectionLabel(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Text(
    text,
    style: const TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w700,
      color: GussoniBrand.textMuted,
      letterSpacing: 0.7,
    ),
  );
}

class _DateField extends StatelessWidget {
  const _DateField({
    required this.label,
    required this.value,
    required this.dateFmt,
    required this.onPick,
  });
  final String label;
  final DateTime? value;
  final DateFormat dateFmt;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onPick,
    child: InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        suffixIcon: const Icon(Icons.calendar_today_outlined, size: 16),
      ),
      child: Text(
        value != null ? dateFmt.format(value!) : 'Seleziona…',
        style: TextStyle(
          fontSize: 13,
          color: value != null
              ? GussoniBrand.textPrimary
              : GussoniBrand.textDisabled,
        ),
      ),
    ),
  );
}

class _EuroField extends StatelessWidget {
  const _EuroField({required this.ctrl, required this.label});
  final TextEditingController ctrl;
  final String label;
  @override
  Widget build(BuildContext context) => TextField(
    controller: ctrl,
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    decoration: InputDecoration(
      labelText: label,
      border: const OutlineInputBorder(),
      prefixText: '€ ',
    ),
  );
}

// ── Invoicing tab ────────────────────────────────────────────────────────────

class _ProjectInvoicingTab extends StatelessWidget {
  const _ProjectInvoicingTab({
    required this.project,
    required this.workspace,
    required this.userId,
    required this.repository,
  });

  final Project project;
  final WorkspaceSnapshot workspace;
  final String userId;
  final ApiWorkspaceRepository repository;

  static final _eur = NumberFormat.currency(
    locale: 'it_IT',
    symbol: '€',
    decimalDigits: 2,
  );

  List<InvoiceDraft> get _invoices =>
      workspace.invoiceDrafts.where((i) => i.projectId == project.id).toList()
        ..sort(
          (a, b) => (b.createdAt ?? DateTime(2000)).compareTo(
            a.createdAt ?? DateTime(2000),
          ),
        );

  double? get _totalBase {
    if (project.quotationId != null) {
      final q = workspace.gussoniQuotations
          .where((q) => q.id == project.quotationId)
          .firstOrNull;
      if (q != null) return q.total;
    }
    if (project.successFeeAmount != null && project.successFeeAmount! > 0) {
      return project.successFeeAmount;
    }
    return null;
  }

  double get _invoiced => _invoices.fold(0.0, (s, i) => s + i.amount);
  double get _remaining => (_totalBase ?? 0) - _invoiced;
  double get _percInvoiced => _totalBase != null && _totalBase! > 0
      ? (_invoiced / _totalBase! * 100).clamp(0, 100)
      : 0;

  @override
  Widget build(BuildContext context) {
    final total = _totalBase;
    final canAdd = total == null || _remaining > 0.01;

    return Column(
      children: [
        // ── Summary bar ──────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          color: GussoniBrand.surface,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _SummaryCell(
                    label: 'BASE FATTURABILE',
                    value: total != null ? _eur.format(total) : '—',
                    sub: total == null ? 'Nessun preventivo collegato' : null,
                  ),
                  const VerticalDivider(width: 32, indent: 4, endIndent: 4),
                  _SummaryCell(
                    label: 'FATTURATO',
                    value: _eur.format(_invoiced),
                    sub: total != null
                        ? '${_percInvoiced.toStringAsFixed(1)}%'
                        : null,
                    color: _invoiced > 0 ? GussoniBrand.success : null,
                  ),
                  const VerticalDivider(width: 32, indent: 4, endIndent: 4),
                  _SummaryCell(
                    label: 'RESIDUO',
                    value: total != null
                        ? _eur.format(_remaining.clamp(0, double.infinity))
                        : '—',
                    sub: total != null
                        ? '${(100 - _percInvoiced).clamp(0, 100).toStringAsFixed(1)}%'
                        : null,
                    color: total != null && _remaining < 0.01
                        ? GussoniBrand.success
                        : GussoniBrand.warning,
                  ),
                  const Spacer(),
                  FilledButton.icon(
                    onPressed: canAdd
                        ? () => showDialog<void>(
                            context: context,
                            builder: (_) => _NewProjectInvoiceDialog(
                              project: project,
                              totalBase: total,
                              alreadyInvoiced: _invoiced,
                              invoiceCount: _invoices.length,
                              userId: userId,
                              repository: repository,
                            ),
                          )
                        : null,
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('Nuova fattura'),
                    style: FilledButton.styleFrom(
                      backgroundColor: GussoniBrand.primary,
                    ),
                  ),
                ],
              ),
              if (total != null) ...[
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: _percInvoiced / 100,
                    minHeight: 6,
                    backgroundColor: GussoniBrand.surfaceMuted,
                    color: _percInvoiced >= 100
                        ? GussoniBrand.success
                        : GussoniBrand.primary,
                  ),
                ),
              ],
            ],
          ),
        ),
        const Divider(height: 1),

        // ── Invoice list ─────────────────────────────────────────────
        Expanded(
          child: _invoices.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.receipt_long_outlined,
                        size: 40,
                        color: GussoniBrand.textDisabled,
                      ),
                      SizedBox(height: 12),
                      Text(
                        'Nessuna fattura emessa per questo progetto.',
                        style: TextStyle(
                          fontSize: 14,
                          color: GussoniBrand.textMuted,
                        ),
                      ),
                    ],
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(24),
                  itemCount: _invoices.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) => _InvoiceRow(
                    invoice: _invoices[i],
                    totalBase: total,
                    eur: _eur,
                  ),
                ),
        ),
      ],
    );
  }
}

class _SummaryCell extends StatelessWidget {
  const _SummaryCell({
    required this.label,
    required this.value,
    this.sub,
    this.color,
  });
  final String label, value;
  final String? sub;
  final Color? color;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: GussoniBrand.textMuted,
          letterSpacing: 0.6,
        ),
      ),
      const SizedBox(height: 4),
      Text(
        value,
        style: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w800,
          color: color ?? GussoniBrand.textPrimary,
        ),
      ),
      if (sub != null)
        Text(
          sub!,
          style: const TextStyle(fontSize: 11, color: GussoniBrand.textMuted),
        ),
    ],
  );
}

class _InvoiceRow extends StatelessWidget {
  const _InvoiceRow({
    required this.invoice,
    required this.totalBase,
    required this.eur,
  });
  final InvoiceDraft invoice;
  final double? totalBase;
  final NumberFormat eur;

  @override
  Widget build(BuildContext context) {
    final pct = totalBase != null && totalBase! > 0
        ? (invoice.amount / totalBase! * 100).toStringAsFixed(1)
        : null;
    final statusColor = switch (invoice.status) {
      InvoiceStatus.draft => GussoniBrand.warning,
      InvoiceStatus.readyForXml => GussoniBrand.info,
      InvoiceStatus.exported => GussoniBrand.success,
    };
    final statusLabel = switch (invoice.status) {
      InvoiceStatus.draft => 'Bozza',
      InvoiceStatus.readyForXml => 'Pronta',
      InvoiceStatus.exported => 'Emessa',
    };
    final dateStr = invoice.createdAt != null
        ? DateFormat('dd/MM/yyyy').format(invoice.createdAt!)
        : '—';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: GussoniBrand.surface,
        border: Border.all(color: GussoniBrand.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: GussoniBrand.primaryBg,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: GussoniBrand.primaryBorder),
            ),
            child: Icon(
              Icons.receipt_long_outlined,
              size: 18,
              color: GussoniBrand.primary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  invoice.notes.isNotEmpty ? invoice.notes : invoice.number,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: GussoniBrand.textPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  dateStr,
                  style: const TextStyle(
                    fontSize: 11,
                    color: GussoniBrand.textMuted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          if (pct != null)
            Container(
              margin: const EdgeInsets.only(right: 10),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: GussoniBrand.primaryBg,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: GussoniBrand.primaryBorder),
              ),
              child: Text(
                '$pct%',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: GussoniBrand.primary,
                ),
              ),
            ),
          Text(
            eur.format(invoice.amount),
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: GussoniBrand.textPrimary,
            ),
          ),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: statusColor.withValues(alpha: 0.35)),
            ),
            child: Text(
              statusLabel,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: statusColor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── New invoice dialog ────────────────────────────────────────────────────────

class _NewProjectInvoiceDialog extends StatefulWidget {
  const _NewProjectInvoiceDialog({
    required this.project,
    required this.totalBase,
    required this.alreadyInvoiced,
    required this.invoiceCount,
    required this.userId,
    required this.repository,
  });

  final Project project;
  final double? totalBase;
  final double alreadyInvoiced;
  final int invoiceCount;
  final String userId;
  final ApiWorkspaceRepository repository;

  @override
  State<_NewProjectInvoiceDialog> createState() =>
      _NewProjectInvoiceDialogState();
}

class _NewProjectInvoiceDialogState extends State<_NewProjectInvoiceDialog> {
  bool _usePercent = true;
  final _inputCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  bool _saving = false;

  static final _eur = NumberFormat.currency(
    locale: 'it_IT',
    symbol: '€',
    decimalDigits: 2,
  );

  double get _remaining => (widget.totalBase ?? 0) - widget.alreadyInvoiced;

  double get _inputVal =>
      double.tryParse(_inputCtrl.text.replaceAll(',', '.')) ?? 0;

  double get _amount {
    if (widget.totalBase == null) return _inputVal;
    return _usePercent ? widget.totalBase! * _inputVal / 100 : _inputVal;
  }

  double get _pct {
    if (widget.totalBase == null || widget.totalBase! <= 0) return 0;
    return _usePercent ? _inputVal : (_inputVal / widget.totalBase! * 100);
  }

  String? get _error {
    if (_inputVal <= 0) return null;
    if (widget.totalBase != null && _amount > _remaining + 0.01) {
      final maxPct = (_remaining / widget.totalBase! * 100);
      return _usePercent
          ? 'Puoi fatturare al massimo ${maxPct.toStringAsFixed(1)}% (${_eur.format(_remaining)})'
          : 'Puoi fatturare al massimo ${_eur.format(_remaining)} (${maxPct.toStringAsFixed(1)}%)';
    }
    return null;
  }

  bool get _valid => _inputVal > 0 && _error == null;

  Future<void> _save() async {
    if (!_valid) return;
    setState(() => _saving = true);
    try {
      final now = DateTime.now();
      final seq = widget.invoiceCount + 1;
      final desc = _descCtrl.text.trim().isNotEmpty
          ? _descCtrl.text.trim()
          : widget.totalBase != null
          ? 'Acconto ${_pct.toStringAsFixed(1)}% — ${widget.project.name}'
          : 'Quota servizi — ${widget.project.name}';

      final draft = InvoiceDraft(
        id: 'inv-${widget.project.id}-$seq-${now.microsecondsSinceEpoch}',
        companyId: widget.project.companyId,
        projectId: widget.project.id,
        number: 'BOZZA-$seq',
        amount: _amount,
        status: InvoiceStatus.draft,
        notes: desc,
        createdAt: now,
        lines: [
          InvoiceLine(description: desc, quantity: 1, unitPrice: _amount),
        ],
      );
      await widget.repository.saveInvoice(widget.userId, invoice: draft);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) setState(() => _saving = false);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Errore: $e')));
      }
    }
  }

  @override
  void dispose() {
    _inputCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text(
        'Nuova fattura',
        style: TextStyle(fontWeight: FontWeight.w800),
      ),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Riepilogo residuo
            if (widget.totalBase != null)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: GussoniBrand.primaryBg,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: GussoniBrand.primaryBorder),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Già fatturato',
                            style: TextStyle(
                              fontSize: 11,
                              color: GussoniBrand.textMuted,
                            ),
                          ),
                          Text(
                            _eur.format(widget.alreadyInvoiced),
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: GussoniBrand.textPrimary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const VerticalDivider(width: 24, indent: 4, endIndent: 4),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Residuo fatturabile',
                            style: TextStyle(
                              fontSize: 11,
                              color: GussoniBrand.textMuted,
                            ),
                          ),
                          Text(
                            _eur.format(_remaining.clamp(0, double.infinity)),
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: _remaining > 0.01
                                  ? GussoniBrand.success
                                  : GussoniBrand.error,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 16),

            // Toggle % / €
            Row(
              children: [
                const Text(
                  'Fattura per:',
                  style: TextStyle(
                    fontSize: 13,
                    color: GussoniBrand.textSecondary,
                  ),
                ),
                const SizedBox(width: 12),
                _ModeToggle(
                  usePercent: _usePercent,
                  enabled: widget.totalBase != null,
                  onChanged: (v) => setState(() {
                    _usePercent = v;
                    _inputCtrl.clear();
                  }),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Input
            TextField(
              controller: _inputCtrl,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              autofocus: true,
              decoration: InputDecoration(
                labelText: _usePercent ? 'Percentuale *' : 'Importo (€) *',
                border: const OutlineInputBorder(),
                suffixText: _usePercent ? '%' : '€',
                helperText: _inputVal > 0 && widget.totalBase != null
                    ? _usePercent
                          ? '→ ${_eur.format(_amount)}'
                          : '→ ${_pct.toStringAsFixed(2)}% del totale'
                    : null,
              ),
              onChanged: (_) => setState(() {}),
            ),
            if (_error != null) ...[
              const SizedBox(height: 6),
              Text(
                _error!,
                style: const TextStyle(fontSize: 12, color: GussoniBrand.error),
              ),
            ],
            const SizedBox(height: 12),

            // Descrizione
            TextField(
              controller: _descCtrl,
              decoration: InputDecoration(
                labelText: 'Descrizione (opzionale)',
                border: const OutlineInputBorder(),
                hintText: widget.totalBase != null && _inputVal > 0
                    ? 'Acconto ${_pct.toStringAsFixed(1)}% — ${widget.project.name}'
                    : 'Quota servizi — ${widget.project.name}',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Annulla'),
        ),
        FilledButton.icon(
          onPressed: _saving || !_valid ? null : _save,
          icon: _saving
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.receipt_long_outlined, size: 16),
          label: const Text('Crea bozza'),
          style: FilledButton.styleFrom(backgroundColor: GussoniBrand.primary),
        ),
      ],
    );
  }
}

class _ModeToggle extends StatelessWidget {
  const _ModeToggle({
    required this.usePercent,
    required this.onChanged,
    required this.enabled,
  });
  final bool usePercent, enabled;
  final void Function(bool) onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _Pill(
          label: 'Percentuale (%)',
          active: usePercent,
          onTap: enabled ? () => onChanged(true) : null,
        ),
        const SizedBox(width: 6),
        _Pill(
          label: 'Importo fisso (€)',
          active: !usePercent,
          onTap: () => onChanged(false),
        ),
      ],
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.active, this.onTap});
  final String label;
  final bool active;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: active ? GussoniBrand.primary : GussoniBrand.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: active ? GussoniBrand.primary : GussoniBrand.border,
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: active
              ? Colors.white
              : (onTap == null
                    ? GussoniBrand.textDisabled
                    : GussoniBrand.textSecondary),
        ),
      ),
    ),
  );
}

// ── Gantt toggle button ───────────────────────────────────────────────────────

class _GanttToggleBtn extends StatelessWidget {
  const _GanttToggleBtn({
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
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
        decoration: BoxDecoration(
          color: active
              ? GussoniBrand.primary.withValues(alpha: .92)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(13),
        ),
        child: Icon(
          icon,
          size: 15,
          color: active ? Colors.white : GussoniBrand.textSecondary,
        ),
      ),
    ),
  );
}

class _ProjectGlassAction extends StatelessWidget {
  const _ProjectGlassAction({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: .52),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withValues(alpha: .70)),
        ),
        child: Icon(icon, size: 17, color: GussoniBrand.textSecondary),
      ),
    ),
  );
}

class _ProjectStatusPill extends StatelessWidget {
  const _ProjectStatusPill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .12),
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: color.withValues(alpha: .34)),
    ),
    child: Text(
      label,
      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: color),
    ),
  );
}

class _ProjectHeroMetrics extends StatelessWidget {
  const _ProjectHeroMetrics({
    required this.logged,
    required this.estimated,
    required this.tasks,
    required this.phases,
    required this.accent,
  });

  final String logged;
  final String estimated;
  final String tasks;
  final String phases;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final items = [
      _ProjectHeroMetric(
        label: 'Tempo tracciato',
        value: logged,
        icon: Icons.timer_rounded,
        color: GussoniBrand.info,
      ),
      _ProjectHeroMetric(
        label: 'Tempo stimato',
        value: estimated,
        icon: Icons.hourglass_bottom_rounded,
        color: accent,
      ),
      _ProjectHeroMetric(
        label: 'Task completati',
        value: tasks,
        icon: Icons.check_circle_rounded,
        color: GussoniBrand.success,
      ),
      _ProjectHeroMetric(
        label: 'Fasi completate',
        value: phases,
        icon: Icons.account_tree_rounded,
        color: GussoniBrand.primary,
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 780;
        if (compact) {
          final width = ((constraints.maxWidth - 10) / 2).clamp(
            180.0,
            double.infinity,
          );
          return Wrap(
            spacing: 10,
            runSpacing: 10,
            children: items
                .map((item) => SizedBox(width: width, child: item))
                .toList(),
          );
        }
        return Row(
          children: [
            for (var i = 0; i < items.length; i += 1) ...[
              Expanded(child: items[i]),
              if (i != items.length - 1) const SizedBox(width: 10),
            ],
          ],
        );
      },
    );
  }
}

class _ProjectHeroMetric extends StatelessWidget {
  const _ProjectHeroMetric({
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
    decoration: GussoniBrand.glassField(radius: 18),
    child: Row(
      children: [
        Icon(icon, size: 18, color: color),
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

// ── Phase row ─────────────────────────────────────────────────────────────────

class _PhaseRow extends StatefulWidget {
  const _PhaseRow({
    required this.phase,
    required this.tasks,
    required this.tracks,
    required this.hm,
    required this.assigneeLabel,
    this.onAddTask,
    this.onOpenTask,
    this.onEdit,
  });
  final ProjectPhase? phase;
  final List<WorkTask> tasks;
  final List<TimeTrack> tracks;
  final String Function(double) hm;
  final String assigneeLabel;
  final VoidCallback? onAddTask;
  final void Function(WorkTask)? onOpenTask;
  final VoidCallback? onEdit;

  @override
  State<_PhaseRow> createState() => _PhaseRowState();
}

class _PhaseRowState extends State<_PhaseRow> {
  bool _expanded = true;

  double get _trackedH {
    if (widget.phase == null) return 0;
    return widget.tracks
        .where((t) => widget.tasks.any((task) => task.id == t.taskId))
        .fold(0, (s, t) => s + t.hours);
  }

  double get _estimatedH =>
      widget.tasks.fold(0, (s, t) => s + t.estimatedHours);

  @override
  Widget build(BuildContext context) {
    final label = widget.phase?.name ?? 'Task senza fase';
    final deadline = widget.phase?.deadline;
    final now = DateTime.now();
    final isOverdue = deadline != null && deadline.isBefore(now);
    final statusColor = _phaseColor(widget.phase?.status);
    final doneTasks = widget.tasks
        .where((task) => task.status == TaskStatus.done)
        .length;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            GussoniBrand.glassSurfaceStrong.withValues(alpha: .88),
            GussoniBrand.glassSurfaceMuted.withValues(alpha: .70),
            statusColor.withValues(alpha: .07),
          ],
        ),
        border: Border.all(color: Colors.white.withValues(alpha: .72)),
        borderRadius: BorderRadius.circular(22),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0F000000),
            blurRadius: 22,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        children: [
          // Phase header
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(22),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: statusColor.withValues(alpha: .12),
                      border: Border.all(
                        color: statusColor.withValues(alpha: .30),
                      ),
                    ),
                    child: Icon(
                      _expanded
                          ? Icons.keyboard_arrow_down_rounded
                          : Icons.keyboard_arrow_right_rounded,
                      size: 22,
                      color: statusColor,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          label,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w900,
                            color: GussoniBrand.textPrimary,
                          ),
                        ),
                        if (widget.phase != null)
                          Text(
                            '${widget.assigneeLabel} · ${widget.phase?.startDate != null ? DateFormat('dd/MM/yyyy').format(widget.phase!.startDate!) : 'inizio da definire'}'
                            ' → ${deadline != null ? DateFormat('dd/MM/yyyy').format(deadline) : 'fine da definire'}',
                            style: const TextStyle(
                              fontSize: 11,
                              color: GussoniBrand.textMuted,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                      ],
                    ),
                  ),
                  _PhaseMetric(
                    label: 'Tracciato',
                    value: _trackedH > 0 ? widget.hm(_trackedH) : '—',
                  ),
                  const SizedBox(width: 22),
                  _PhaseMetric(
                    label: 'Stimato',
                    value: _estimatedH > 0 ? widget.hm(_estimatedH) : '—',
                  ),
                  const SizedBox(width: 22),
                  _PhaseMetric(
                    label: 'Task',
                    value: '$doneTasks/${widget.tasks.length}',
                    valueColor:
                        doneTasks == widget.tasks.length &&
                            widget.tasks.isNotEmpty
                        ? GussoniBrand.success
                        : null,
                  ),
                  const SizedBox(width: 22),
                  _PhaseMetric(
                    label: 'Scadenza',
                    value: deadline != null
                        ? DateFormat('dd/MM/yyyy').format(deadline)
                        : '—',
                    valueColor: isOverdue ? GussoniBrand.error : null,
                    chip: isOverdue,
                  ),
                  // Bottone + aggiungi task
                  if (widget.onAddTask != null) ...[
                    const SizedBox(width: 16),
                    Tooltip(
                      message: 'Aggiungi task a questa fase',
                      child: InkWell(
                        onTap: widget.onAddTask,
                        borderRadius: BorderRadius.circular(6),
                        child: Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: GussoniBrand.primary.withValues(alpha: .12),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: GussoniBrand.primary.withValues(
                                alpha: .28,
                              ),
                            ),
                          ),
                          child: Icon(
                            Icons.add,
                            size: 16,
                            color: GussoniBrand.primary,
                          ),
                        ),
                      ),
                    ),
                  ],
                  if (widget.onEdit != null && widget.phase != null) ...[
                    const SizedBox(width: 8),
                    Tooltip(
                      message: 'Modifica fase',
                      child: InkWell(
                        onTap: widget.onEdit,
                        borderRadius: BorderRadius.circular(6),
                        child: Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: .50),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: .70),
                            ),
                          ),
                          child: const Icon(
                            Icons.edit_outlined,
                            size: 15,
                            color: GussoniBrand.textSecondary,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          // Tasks
          if (_expanded && widget.tasks.isNotEmpty) ...[
            Divider(height: 1, color: Colors.white.withValues(alpha: .56)),
            ...widget.tasks.map(
              (task) => _TaskRow(
                task: task,
                hm: widget.hm,
                onTap: widget.onOpenTask == null
                    ? null
                    : () => widget.onOpenTask!(task),
              ),
            ),
          ],
          // Empty state con invito ad aggiungere
          if (_expanded &&
              widget.tasks.isEmpty &&
              widget.phase != null &&
              widget.onAddTask != null)
            InkWell(
              onTap: widget.onAddTask,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  vertical: 12,
                  horizontal: 16,
                ),
                decoration: const BoxDecoration(
                  border: Border(top: BorderSide(color: Color(0x80FFFFFF))),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.add,
                      size: 14,
                      color: GussoniBrand.textDisabled,
                    ),
                    const SizedBox(width: 6),
                    const Text(
                      'Aggiungi task a questa fase',
                      style: TextStyle(
                        fontSize: 12,
                        color: GussoniBrand.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Color _phaseColor(PhaseStatus? status) => switch (status) {
    PhaseStatus.done => GussoniBrand.success,
    PhaseStatus.inProgress => GussoniBrand.warning,
    PhaseStatus.notStarted || null => GussoniBrand.primary,
  };
}

class _PhaseMetric extends StatelessWidget {
  const _PhaseMetric({
    required this.label,
    required this.value,
    this.valueColor,
    this.chip = false,
  });
  final String label;
  final String value;
  final Color? valueColor;
  final bool chip;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.end,
    children: [
      Text(
        label,
        style: const TextStyle(fontSize: 10, color: GussoniBrand.textMuted),
      ),
      const SizedBox(height: 2),
      chip
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: GussoniBrand.errorBg,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                value,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: valueColor ?? GussoniBrand.error,
                ),
              ),
            )
          : Text(
              value,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: valueColor ?? GussoniBrand.textPrimary,
              ),
            ),
    ],
  );
}

class _EditProjectPhaseDialog extends StatefulWidget {
  const _EditProjectPhaseDialog({
    required this.phase,
    required this.teamMembers,
    required this.onSave,
  });

  final ProjectPhase phase;
  final List<TeamMember> teamMembers;
  final Future<void> Function(ProjectPhase phase) onSave;

  @override
  State<_EditProjectPhaseDialog> createState() =>
      _EditProjectPhaseDialogState();
}

class _EditProjectPhaseDialogState extends State<_EditProjectPhaseDialog> {
  late final TextEditingController _name;
  late final TextEditingController _notes;
  late PhaseStatus _status;
  String? _assigneeId;
  DateTime? _startDate;
  DateTime? _deadline;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.phase.name);
    _notes = TextEditingController(text: widget.phase.notes);
    _status = widget.phase.status;
    _assigneeId = widget.phase.assignedUserId;
    _startDate = widget.phase.startDate;
    _deadline = widget.phase.deadline;
  }

  @override
  void dispose() {
    _name.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _pickDate(
    DateTime? current,
    void Function(DateTime? value) onPick,
  ) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: current ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (picked != null) onPick(picked);
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Inserisci il nome della fase.')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await widget.onSave(
        widget.phase.copyWith(
          name: _name.text.trim(),
          status: _status,
          assignedUserId: _assigneeId,
          startDate: _startDate,
          deadline: _deadline,
          notes: _notes.text.trim(),
        ),
      );
      if (!mounted) return;
      Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateFmt = DateFormat('dd/MM/yyyy');
    return Dialog(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 560,
          maxHeight: MediaQuery.of(context).size.height * 0.88,
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Modifica fase',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: _saving
                        ? null
                        : () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: _name,
                      decoration: const InputDecoration(
                        labelText: 'Nome fase',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<PhaseStatus>(
                      value: _status,
                      decoration: const InputDecoration(
                        labelText: 'Stato',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: PhaseStatus.notStarted,
                          child: Text('Non iniziata'),
                        ),
                        DropdownMenuItem(
                          value: PhaseStatus.inProgress,
                          child: Text('In corso'),
                        ),
                        DropdownMenuItem(
                          value: PhaseStatus.done,
                          child: Text('Completata'),
                        ),
                      ],
                      onChanged: (value) =>
                          setState(() => _status = value ?? _status),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String?>(
                      value: _assigneeId,
                      decoration: const InputDecoration(
                        labelText: 'Assegnatario',
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        const DropdownMenuItem<String?>(
                          value: null,
                          child: Text('Non assegnato'),
                        ),
                        ...widget.teamMembers.map(
                          (member) => DropdownMenuItem<String?>(
                            value: member.userId,
                            child: Text(member.displayName),
                          ),
                        ),
                      ],
                      onChanged: (value) => setState(() => _assigneeId = value),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            onTap: () => _pickDate(
                              _startDate,
                              (value) => setState(() => _startDate = value),
                            ),
                            child: InputDecorator(
                              decoration: const InputDecoration(
                                labelText: 'Data inizio',
                                border: OutlineInputBorder(),
                                suffixIcon: Icon(
                                  Icons.calendar_today_outlined,
                                  size: 16,
                                ),
                              ),
                              child: Text(
                                _startDate != null
                                    ? dateFmt.format(_startDate!)
                                    : 'Da definire',
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: InkWell(
                            onTap: () => _pickDate(
                              _deadline,
                              (value) => setState(() => _deadline = value),
                            ),
                            child: InputDecorator(
                              decoration: const InputDecoration(
                                labelText: 'Scadenza',
                                border: OutlineInputBorder(),
                                suffixIcon: Icon(
                                  Icons.event_outlined,
                                  size: 16,
                                ),
                              ),
                              child: Text(
                                _deadline != null
                                    ? dateFmt.format(_deadline!)
                                    : 'Da definire',
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _notes,
                      minLines: 3,
                      maxLines: 5,
                      decoration: const InputDecoration(
                        labelText: 'Note fase',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: GussoniBrand.primaryBg,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: GussoniBrand.primaryBorder),
                      ),
                      child: Text(
                        'Al salvataggio vengono aggiornati anche assegnatario e date dei task di questa fase, così il Gantt e la pianificazione restano coerenti.',
                        style: TextStyle(
                          fontSize: 12,
                          color: GussoniBrand.primary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              child: Row(
                children: [
                  const Spacer(),
                  TextButton(
                    onPressed: _saving
                        ? null
                        : () => Navigator.of(context).pop(),
                    child: const Text('Annulla'),
                  ),
                  const SizedBox(width: 10),
                  FilledButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: _saving
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.save_outlined, size: 16),
                    label: const Text('Salva fase'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TaskRow extends StatelessWidget {
  const _TaskRow({required this.task, required this.hm, this.onTap});
  final WorkTask task;
  final String Function(double) hm;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final done = task.status == TaskStatus.done;
    final overdue = !done && task.deadline.isBefore(DateTime.now());
    return InkWell(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: .42),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: .64)),
        ),
        child: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: (done ? GussoniBrand.success : GussoniBrand.primary)
                    .withValues(alpha: .10),
                border: Border.all(
                  color: (done ? GussoniBrand.success : GussoniBrand.primary)
                      .withValues(alpha: .24),
                ),
              ),
              child: Icon(
                done ? Icons.check_rounded : Icons.radio_button_unchecked,
                size: 16,
                color: done ? GussoniBrand.success : GussoniBrand.textDisabled,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                task.name,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: GussoniBrand.textPrimary,
                  decoration: done ? TextDecoration.lineThrough : null,
                ),
              ),
            ),
            _PhaseMetric(label: 'Tracciato', value: '—'),
            const SizedBox(width: 22),
            _PhaseMetric(label: 'Stimato', value: hm(task.estimatedHours)),
            const SizedBox(width: 22),
            _PhaseMetric(
              label: 'Scadenza',
              value: DateFormat('dd/MM/yyyy').format(task.deadline),
              valueColor: overdue ? GussoniBrand.error : null,
              chip: overdue,
            ),
          ],
        ),
      ),
    );
  }
}

class _StatCell extends StatelessWidget {
  const _StatCell({required this.label, required this.value, this.color});
  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: color ?? GussoniBrand.textSecondary,
          letterSpacing: 0.5,
        ),
      ),
      const SizedBox(height: 6),
      Text(
        value,
        style: const TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w900,
          color: GussoniBrand.textPrimary,
        ),
      ),
      const SizedBox(height: 4),
      Container(
        height: 3,
        width: 40,
        decoration: BoxDecoration(
          color: color ?? GussoniBrand.border,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    ],
  );
}

class _DettagliCard extends StatelessWidget {
  const _DettagliCard({required this.project, required this.company});
  final Project project;
  final String company;

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat.currency(
      locale: 'it_IT',
      symbol: '€',
      decimalDigits: 2,
    );
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            GussoniBrand.glassSurfaceStrong.withValues(alpha: .88),
            GussoniBrand.glassSurfaceMuted.withValues(alpha: .70),
          ],
        ),
        border: Border.all(color: Colors.white.withValues(alpha: .72)),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Dettagli',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: GussoniBrand.textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          _DRow('Cliente', company),
          if (project.code.isNotEmpty) _DRow('Codice', project.code),
          if (project.idProgettoEsterno.isNotEmpty)
            _DRow('ID ente', project.idProgettoEsterno),
          if (project.titoloProgetto.isNotEmpty)
            _DRow('Titolo ufficiale', project.titoloProgetto),
          if (project.daFaturareA.isNotEmpty)
            _DRow('Da fatturare a', project.daFaturareA),
          if (project.contributoRichiesto != null)
            _DRow(
              'Contributo richiesto',
              fmt.format(project.contributoRichiesto),
            ),
          if (project.contributoRicevuto != null)
            _DRow(
              'Contributo ricevuto',
              fmt.format(project.contributoRicevuto),
            ),
          if (project.grantAmount != null)
            _DRow('Grant', fmt.format(project.grantAmount)),
          if (project.successFeeAmount != null)
            _DRow('Success fee', fmt.format(project.successFeeAmount)),
          if (project.dataInizioProgetto != null)
            _DRow(
              'Inizio',
              DateFormat('dd/MM/yyyy').format(project.dataInizioProgetto!),
            ),
          if (project.dataFineProgetto != null)
            _DRow(
              'Fine',
              DateFormat('dd/MM/yyyy').format(project.dataFineProgetto!),
            ),
          if (project.termineRendicontazione != null)
            _DRow(
              'Termine rend.',
              DateFormat('dd/MM/yyyy').format(project.termineRendicontazione!),
            ),
          if (project.avanzamentoPratica != AvanzamentoPratica.none)
            _DRow('Avanzamento', project.avanzamentoPratica.name),
          if (project.esitoPratica != EsitoPratica.none)
            _DRow('Esito pratica', project.esitoPratica.name),
        ],
      ),
    );
  }
}

class _DescrizioneCard extends StatelessWidget {
  const _DescrizioneCard({required this.notes});
  final String notes;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          GussoniBrand.glassSurfaceStrong.withValues(alpha: .88),
          GussoniBrand.glassSurfaceMuted.withValues(alpha: .70),
        ],
      ),
      border: Border.all(color: Colors.white.withValues(alpha: .72)),
      borderRadius: BorderRadius.circular(22),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Descrizione',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: GussoniBrand.textPrimary,
          ),
        ),
        const SizedBox(height: 12),
        notes.isEmpty
            ? const Text(
                'Non c\'è ancora una descrizione.',
                style: TextStyle(fontSize: 13, color: GussoniBrand.textMuted),
              )
            : Text(
                notes,
                style: const TextStyle(
                  fontSize: 13,
                  color: GussoniBrand.textSecondary,
                  height: 1.5,
                ),
              ),
      ],
    ),
  );
}

class _DRow extends StatelessWidget {
  const _DRow(this.label, this.value, {this.valueColor});
  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 140,
          child: Text(
            label,
            style: const TextStyle(fontSize: 12, color: GussoniBrand.textMuted),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: valueColor ?? GussoniBrand.textPrimary,
            ),
          ),
        ),
      ],
    ),
  );
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.label, this.onAction, this.actionLabel});
  final String label;
  final VoidCallback? onAction;
  final String? actionLabel;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 40),
        Icon(Icons.inbox_outlined, size: 48, color: GussoniBrand.textDisabled),
        const SizedBox(height: 12),
        Text(
          label,
          style: const TextStyle(color: GussoniBrand.textMuted, fontSize: 14),
        ),
        if (onAction != null && actionLabel != null) ...[
          const SizedBox(height: 12),
          FilledButton(onPressed: onAction, child: Text(actionLabel!)),
        ],
      ],
    ),
  );
}

// ────────────────────────────────────────────────
// Opportunity Detail
// ────────────────────────────────────────────────

class OpportunityDetailPage extends StatefulWidget {
  const OpportunityDetailPage({
    super.key,
    required this.opportunity,
    required this.workspace,
    required this.userId,
    required this.repository,
    required this.onBack,
    required this.onEdit,
    this.onCreatePreventivo,
    this.onOpenProject,
    this.onUpdateStatus,
    this.onCreateProject,
  });

  final Opportunity opportunity;
  final WorkspaceSnapshot workspace;
  final String userId;
  final ApiWorkspaceRepository repository;
  final VoidCallback onBack;
  final Future<void> Function(Opportunity) onEdit;
  final VoidCallback? onCreatePreventivo;
  final void Function(Project)? onOpenProject;
  final Future<void> Function(Opportunity, OpportunityStatus)? onUpdateStatus;
  final VoidCallback?
  onCreateProject; // crea progetto direttamente dall'opportunità

  @override
  State<OpportunityDetailPage> createState() => _OpportunityDetailPageState();
}

class _OpportunityDetailPageState extends State<OpportunityDetailPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  int _relatedTabIndex = 0;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Opportunity get _opp => widget.opportunity;

  String get _companyName =>
      widget.workspace.companies
          .where((c) => c.id == _opp.companyId)
          .firstOrNull
          ?.name ??
      '—';

  List<Preventivo> get _linkedQuotations =>
      widget.workspace.gussoniQuotations
          .where((q) => q.opportunityId == _opp.id)
          .toList()
        ..sort((a, b) {
          final aDate = a.sentAt ?? a.createdAt;
          final bDate = b.sentAt ?? b.createdAt;
          return bDate.compareTo(aDate);
        });

  List<Project> get _linkedProjects =>
      widget.workspace.projects
          .where((p) => p.opportunityId == _opp.id)
          .toList()
        ..sort((a, b) {
          final aDate = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          final bDate = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          return bDate.compareTo(aDate);
        });

  Project? get _linkedProject => _linkedProjects.firstOrNull;

  List<InvoiceDraft> get _linkedInvoices {
    final projectIds = _linkedProjects.map((project) => project.id).toSet();
    if (projectIds.isEmpty) {
      return const [];
    }
    return widget.workspace.invoiceDrafts
        .where((invoice) => projectIds.contains(invoice.projectId))
        .toList()
      ..sort((a, b) {
        final aDate = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bDate = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        return bDate.compareTo(aDate);
      });
  }

  Color get _statusColor => switch (_opp.status) {
    OpportunityStatus.inAttesa => GussoniBrand.info,
    OpportunityStatus.preventivazione => GussoniBrand.gold,
    OpportunityStatus.accettata => GussoniBrand.success,
    OpportunityStatus.accettataSenzaFirma => GussoniBrand.success,
    OpportunityStatus.inAttesaRinnovoAutomatico => GussoniBrand.warning,
    OpportunityStatus.presaInCarico => GussoniBrand.primary,
    OpportunityStatus.persa => GussoniBrand.textMuted,
  };

  String get _statusLabel => switch (_opp.status) {
    OpportunityStatus.inAttesa => 'In attesa',
    OpportunityStatus.preventivazione => 'Preventivazione',
    OpportunityStatus.accettata => 'Accettata',
    OpportunityStatus.accettataSenzaFirma => 'Acc. senza firma',
    OpportunityStatus.inAttesaRinnovoAutomatico => 'Rinnovo automatico',
    OpportunityStatus.presaInCarico => 'Presa in carico',
    OpportunityStatus.persa => 'Persa',
  };

  @override
  Widget build(BuildContext context) {
    final dateFmt = DateFormat('dd/MM/yyyy');
    final fmt = NumberFormat.currency(
      locale: 'it_IT',
      symbol: '€',
      decimalDigits: 2,
    );

    return Column(
      children: [
        // ── Top bar ──────────────────────────────────────────────────────
        Container(
          margin: const EdgeInsets.fromLTRB(18, 14, 18, 0),
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 0),
          decoration: GussoniBrand.glassPanel(
            radius: 26,
            accent: GussoniBrand.surface,
            opacity: .96,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DetailBackBar(
                label: 'Panoramica opportunità',
                onBack: widget.onBack,
                actions: [
                  _ProjectGlassAction(
                    icon: Icons.edit_outlined,
                    tooltip: 'Modifica opportunità',
                    onTap: () => widget.onEdit(_opp),
                  ),
                  if (_opp.status == OpportunityStatus.preventivazione &&
                      widget.onCreatePreventivo != null) ...[
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      onPressed: widget.onCreatePreventivo,
                      icon: const Icon(Icons.request_quote_outlined, size: 14),
                      label: const Text('Crea preventivo'),
                      style: FilledButton.styleFrom(
                        backgroundColor: GussoniBrand.primary,
                      ),
                    ),
                  ],
                  if ((_opp.status == OpportunityStatus.accettata ||
                          _opp.status ==
                              OpportunityStatus.accettataSenzaFirma) &&
                      _linkedProject == null &&
                      widget.onCreateProject != null) ...[
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      onPressed: widget.onCreateProject,
                      icon: const Icon(Icons.folder_open_outlined, size: 14),
                      label: const Text('Crea progetto'),
                      style: FilledButton.styleFrom(
                        backgroundColor: GussoniBrand.success,
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _opp.title,
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                            color: GussoniBrand.textPrimary,
                            height: 1.2,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _companyName,
                          style: const TextStyle(
                            fontSize: 13,
                            color: GussoniBrand.textSecondary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: _statusColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: _statusColor.withValues(alpha: 0.4),
                      ),
                    ),
                    child: Text(
                      _statusLabel,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: _statusColor,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: Container(
                  color: GussoniBrand.surfaceSubtle,
                  child: TabBar(
                    controller: _tabs,
                    labelColor: GussoniBrand.textPrimary,
                    unselectedLabelColor: GussoniBrand.textMuted,
                    indicator: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      color: GussoniBrand.surface,
                      border: Border.all(color: GussoniBrand.border),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x1202332A),
                          blurRadius: 10,
                          offset: Offset(0, 4),
                        ),
                      ],
                    ),
                    indicatorPadding: const EdgeInsets.symmetric(
                      horizontal: 2,
                      vertical: 4,
                    ),
                    indicatorSize: TabBarIndicatorSize.tab,
                    dividerColor: Colors.transparent,
                    labelStyle: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0,
                    ),
                    unselectedLabelStyle: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0,
                    ),
                    tabs: const [
                      Tab(text: 'Info bando'),
                      Tab(text: 'Pratica'),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),

        Expanded(
          child: TabBarView(
            controller: _tabs,
            children: [
              // ── Tab 1: Info bando ─────────────────────────────────────────
              SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: LayoutBuilder(
                  builder: (ctx, c) {
                    final twoCol = c.maxWidth > 600;
                    final info = Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: GussoniBrand.surface,
                        border: Border.all(color: GussoniBrand.border),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Dettagli bando',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 12),
                          _DRow('Cliente', _companyName),
                          if (_opp.rifOfferta.isNotEmpty)
                            _DRow('Rif. offerta', _opp.rifOfferta),
                          if (_opp.bandoSource.isNotEmpty)
                            _DRow('Ente / Portale', _opp.bandoSource),
                          if (_opp.bandoReference.isNotEmpty)
                            _DRow('Codice bando', _opp.bandoReference),
                          if (_opp.estimatedValue != null)
                            _DRow(
                              'Valore stimato',
                              fmt.format(_opp.estimatedValue),
                            ),
                          if (_opp.bandoDeadline != null)
                            _DRow(
                              'Scadenza bando',
                              dateFmt.format(_opp.bandoDeadline!),
                            ),
                          if (_opp.scadenzaPresentazione != null)
                            _DRow(
                              'Scad. presentazione',
                              dateFmt.format(_opp.scadenzaPresentazione!),
                            ),
                          if (_opp.scadenzaOperativa != null)
                            _DRow(
                              'Scad. operativa',
                              dateFmt.format(_opp.scadenzaOperativa!),
                            ),
                        ],
                      ),
                    );
                    final commerciale = Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: GussoniBrand.surface,
                        border: Border.all(color: GussoniBrand.border),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Dettagli commerciali',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 12),
                          if (_opp.contattoCommerciale.isNotEmpty)
                            _DRow('Contatto comm.', _opp.contattoCommerciale),
                          if (_opp.daFaturareA.isNotEmpty)
                            _DRow('Da fatturare a', _opp.daFaturareA),
                          if (_opp.partnerCommerciale.isNotEmpty)
                            _DRow('Partner', _opp.partnerCommerciale),
                          if (_opp.fornitore.isNotEmpty)
                            _DRow('Fornitore', _opp.fornitore),
                          _DRow(
                            'Presa in carico',
                            _opp.presaInCarico ? 'Sì' : 'No',
                          ),
                          if (_opp.notes.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            const Text(
                              'Note',
                              style: TextStyle(
                                fontSize: 12,
                                color: GussoniBrand.textMuted,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _opp.notes,
                              style: const TextStyle(fontSize: 13, height: 1.5),
                            ),
                          ],
                        ],
                      ),
                    );
                    if (twoCol) {
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: info),
                          const SizedBox(width: 16),
                          Expanded(child: commerciale),
                        ],
                      );
                    }
                    return Column(
                      children: [info, const SizedBox(height: 16), commerciale],
                    );
                  },
                ),
              ),

              // ── Tab 2: Pratica ────────────────────────────────────────
              SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Progress bar bando
                    _SectionCard(
                      title: 'Avanzamento pratica',
                      icon: Icons.trending_up_outlined,
                      child: Column(
                        children: [
                          _PraticaProgressBar(opp: _opp),
                          const SizedBox(height: 16),
                          LayoutBuilder(
                            builder: (ctx, c) {
                              final two = c.maxWidth > 500;
                              final left = Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _DRow(
                                    'Avanzamento',
                                    _avanzamentoLabel(_opp.avanzamentoPratica),
                                  ),
                                  _DRow(
                                    'Esito',
                                    _esitoLabel(_opp.esitoPratica),
                                    valueColor: _esitoColor(_opp.esitoPratica),
                                  ),
                                  if (_opp.dataStato != null)
                                    _DRow(
                                      'Data stato',
                                      DateFormat(
                                        'dd/MM/yyyy',
                                      ).format(_opp.dataStato!),
                                    ),
                                  if (_opp.termineRendicontazione != null)
                                    _DRow(
                                      'Termine rend.',
                                      DateFormat(
                                        'dd/MM/yyyy',
                                      ).format(_opp.termineRendicontazione!),
                                      valueColor:
                                          _opp.termineRendicontazione!.isBefore(
                                            DateTime.now(),
                                          )
                                          ? GussoniBrand.error
                                          : null,
                                    ),
                                ],
                              );
                              final right = Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (_opp.contributoRichiesto != null)
                                    _DRow(
                                      'Contributo richiesto',
                                      fmt.format(_opp.contributoRichiesto),
                                    ),
                                  if (_opp.finanziamentoRichiesto != null)
                                    _DRow(
                                      'Finanziamento richiesto',
                                      fmt.format(_opp.finanziamentoRichiesto),
                                    ),
                                  if (_opp.garanziaRichiesta != null)
                                    _DRow(
                                      'Garanzia richiesta',
                                      fmt.format(_opp.garanziaRichiesta),
                                    ),
                                  if (_opp.creditoImpostaRichiesto != null)
                                    _DRow(
                                      'Credito imposta',
                                      fmt.format(_opp.creditoImpostaRichiesto),
                                    ),
                                  if (_opp.totaleProgetto != null)
                                    _DRow(
                                      'Totale progetto',
                                      fmt.format(_opp.totaleProgetto),
                                    ),
                                ],
                              );
                              if (two)
                                return Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(child: left),
                                    const SizedBox(width: 24),
                                    Expanded(child: right),
                                  ],
                                );
                              return Column(
                                children: [
                                  left,
                                  const SizedBox(height: 12),
                                  right,
                                ],
                              );
                            },
                          ),
                        ],
                      ),
                    ),

                    // Importi ricevuti
                    if (_opp.contributoRicevuto != null ||
                        _opp.totaleBeneficioEconomicoRicevuto != null) ...[
                      const SizedBox(height: 16),
                      _SectionCard(
                        title: 'Importi ricevuti',
                        icon: Icons.euro_outlined,
                        child: Column(
                          children: [
                            if (_opp.totaleBeneficioEconomicoRicevuto != null)
                              _DRow(
                                'Beneficio ricevuto',
                                fmt.format(
                                  _opp.totaleBeneficioEconomicoRicevuto,
                                ),
                                valueColor: GussoniBrand.success,
                              ),
                            if (_opp.contributoRicevuto != null)
                              _DRow(
                                'Contributo ricevuto',
                                fmt.format(_opp.contributoRicevuto),
                                valueColor: GussoniBrand.success,
                              ),
                            if (_opp.finanziamentoRicevuto != null)
                              _DRow(
                                'Finanziamento ricevuto',
                                fmt.format(_opp.finanziamentoRicevuto),
                              ),
                            if (_opp.garanziaRicevuta != null)
                              _DRow(
                                'Garanzia ricevuta',
                                fmt.format(_opp.garanziaRicevuta),
                              ),
                            if (_opp.creditoImpostaRicevuto != null)
                              _DRow(
                                'Credito imposta ricevuto',
                                fmt.format(_opp.creditoImpostaRicevuto),
                              ),
                            if (_opp.totaleProgettoRidefinito != null)
                              _DRow(
                                'Totale ridefinito',
                                fmt.format(_opp.totaleProgettoRidefinito),
                              ),
                          ],
                        ),
                      ),
                    ],

                    // Box relazioni collegate
                    const SizedBox(height: 16),
                    _SectionCard(
                      title: 'Relazioni collegate',
                      icon: Icons.dashboard_customize_outlined,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              _RelatedTabPill(
                                label: 'Preventivi',
                                count: _linkedQuotations.length,
                                selected: _relatedTabIndex == 0,
                                onTap: () =>
                                    setState(() => _relatedTabIndex = 0),
                              ),
                              const SizedBox(width: 8),
                              _RelatedTabPill(
                                label: 'Progetti',
                                count: _linkedProjects.length,
                                selected: _relatedTabIndex == 1,
                                onTap: () =>
                                    setState(() => _relatedTabIndex = 1),
                              ),
                              const SizedBox(width: 8),
                              _RelatedTabPill(
                                label: 'Fatture',
                                count: _linkedInvoices.length,
                                selected: _relatedTabIndex == 2,
                                onTap: () =>
                                    setState(() => _relatedTabIndex = 2),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          if (_relatedTabIndex == 0)
                            _OpportunityRelatedQuotations(
                              quotations: _linkedQuotations,
                              onCreate: widget.onCreatePreventivo,
                              canCreate:
                                  _opp.status ==
                                  OpportunityStatus.preventivazione,
                            )
                          else if (_relatedTabIndex == 1)
                            _OpportunityRelatedProjects(
                              projects: _linkedProjects,
                              onOpenProject: widget.onOpenProject,
                              showRendicontazioneHint:
                                  _linkedProjects.isEmpty &&
                                  _opp.termineRendicontazione != null,
                            )
                          else
                            _OpportunityRelatedInvoices(
                              invoices: _linkedInvoices,
                              projectNameOf: (projectId) =>
                                  widget.workspace.projects
                                      .where(
                                        (project) => project.id == projectId,
                                      )
                                      .firstOrNull
                                      ?.name ??
                                  '—',
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

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

  Color? _esitoColor(EsitoPratica e) => switch (e) {
    EsitoPratica.accolta => GussoniBrand.success,
    EsitoPratica.respinta => GussoniBrand.error,
    EsitoPratica.nonAmmissibile => GussoniBrand.error,
    EsitoPratica.rinunciata => GussoniBrand.warning,
    _ => null,
  };
}

// ── Pratica progress bar ──────────────────────────────────────────────────────

class _PraticaProgressBar extends StatelessWidget {
  const _PraticaProgressBar({required this.opp});
  final Opportunity opp;

  @override
  Widget build(BuildContext context) {
    final steps = [
      (
        'Accettata',
        opp.status == OpportunityStatus.accettata ||
            opp.status == OpportunityStatus.accettataSenzaFirma,
      ),
      (
        'Presentata',
        opp.avanzamentoPratica == AvanzamentoPratica.presentata ||
            opp.avanzamentoPratica == AvanzamentoPratica.inEsecuzione ||
            opp.avanzamentoPratica == AvanzamentoPratica.conclusa,
      ),
      (
        'In esecuzione',
        opp.avanzamentoPratica == AvanzamentoPratica.inEsecuzione ||
            opp.avanzamentoPratica == AvanzamentoPratica.conclusa,
      ),
      (
        'Esito',
        opp.esitoPratica != EsitoPratica.none &&
            opp.esitoPratica != EsitoPratica.inAttesa,
      ),
      ('Conclusa', opp.avanzamentoPratica == AvanzamentoPratica.conclusa),
    ];

    return Row(
      children: steps.asMap().entries.map((e) {
        final idx = e.key;
        final (label, done) = e.value;
        return Expanded(
          child: Row(
            children: [
              Expanded(
                child: Column(
                  children: [
                    Container(
                      height: 8,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: done
                            ? GussoniBrand.primary
                            : GussoniBrand.surfaceMuted,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: done
                            ? GussoniBrand.primary
                            : GussoniBrand.textMuted,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
              if (idx < steps.length - 1) const SizedBox(width: 4),
            ],
          ),
        );
      }).toList(),
    );
  }
}

// ── placeholder per build ─────────────────────────────────────────────────────

class _RendicontazioneStep extends StatelessWidget {
  const _RendicontazioneStep({
    required this.label,
    required this.sublabel,
    required this.done,
    this.isLast = false,
  });
  final String label;
  final String sublabel;
  final bool done;
  final bool isLast;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Column(
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: done ? GussoniBrand.success : GussoniBrand.surfaceSubtle,
              shape: BoxShape.circle,
              border: Border.all(
                color: done ? GussoniBrand.success : GussoniBrand.border,
              ),
            ),
            child: Icon(
              done ? Icons.check : Icons.circle_outlined,
              size: 14,
              color: done ? Colors.white : GussoniBrand.textDisabled,
            ),
          ),
          if (!isLast)
            Container(
              width: 2,
              height: 32,
              color: done ? GussoniBrand.success : GussoniBrand.border,
            ),
        ],
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Padding(
          padding: const EdgeInsets.only(top: 2, bottom: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: done ? GussoniBrand.success : GussoniBrand.textPrimary,
                ),
              ),
              Text(
                sublabel,
                style: const TextStyle(
                  fontSize: 11,
                  color: GussoniBrand.textMuted,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ),
    ],
  );
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.icon,
    required this.child,
    this.action,
  });
  final String title;
  final IconData icon;
  final Widget child;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          GussoniBrand.glassSurfaceStrong.withValues(alpha: .88),
          GussoniBrand.glassSurfaceMuted.withValues(alpha: .70),
        ],
      ),
      border: Border.all(color: Colors.white.withValues(alpha: .72)),
      borderRadius: BorderRadius.circular(22),
      boxShadow: const [
        BoxShadow(
          color: Color(0x0E000000),
          blurRadius: 22,
          offset: Offset(0, 12),
        ),
      ],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 16, color: GussoniBrand.textMuted),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: GussoniBrand.textPrimary,
                ),
              ),
            ),
            if (action != null) action!,
          ],
        ),
        const SizedBox(height: 12),
        child,
      ],
    ),
  );
}

// ────────────────────────────────────────────────
// Invoice Detail
// ────────────────────────────────────────────────

class InvoiceDetailPage extends StatelessWidget {
  InvoiceDetailPage({
    super.key,
    required this.invoice,
    required this.workspace,
    required this.crmData,
    required this.onBack,
    required this.onEdit,
    required this.onExportXml,
    required this.onEmitYoudox,
    required this.onDelete,
  });
  final InvoiceDraft invoice;
  final WorkspaceSnapshot workspace;
  final CrmData crmData;
  final VoidCallback onBack;
  final Future<void> Function(InvoiceDraft) onEdit;
  final Future<void> Function(InvoiceDraft) onExportXml;
  final Future<void> Function(InvoiceDraft) onEmitYoudox;
  final Future<void> Function(InvoiceDraft) onDelete;

  final _currFmt = NumberFormat.currency(
    locale: 'it_IT',
    symbol: '€',
    decimalDigits: 2,
  );
  String get _company =>
      workspace.companies
          .where((c) => c.id == invoice.companyId)
          .firstOrNull
          ?.name ??
      '—';

  Color get _statusColor => switch (invoice.status) {
    InvoiceStatus.draft => const Color(0xFF7D89A8),
    InvoiceStatus.readyForXml => const Color(0xFF0369A1),
    InvoiceStatus.exported => GussoniBrand.primary,
  };
  String get _statusLabel => switch (invoice.status) {
    InvoiceStatus.draft => 'Bozza',
    InvoiceStatus.readyForXml => 'Pronta XML',
    InvoiceStatus.exported => 'Esportata',
  };

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DetailBackBar(
            label: 'Panoramica finanze',
            onBack: onBack,
            actions: [
              FilledButton.icon(
                onPressed: () => onEmitYoudox(invoice),
                icon: const Icon(Icons.cloud_upload_outlined, size: 15),
                label: const Text('Emetti'),
              ),
              const SizedBox(width: 8),
              if (invoice.status != InvoiceStatus.exported)
                FilledButton.icon(
                  onPressed: () => onExportXml(invoice),
                  icon: const Icon(Icons.code, size: 15),
                  label: const Text('Esporta XML FatturaPA'),
                ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: () => onEdit(invoice),
                icon: const Icon(Icons.edit_outlined, color: Color(0xFFB8C0D8)),
              ),
            ],
          ),
          DetailInfoCard(
            title: 'Dati fattura',
            avatar: Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    color: const Color(0xFFB8C0D8).withValues(alpha: 0.08),
                  ),
                  child: const Icon(
                    Icons.receipt_long_outlined,
                    size: 26,
                    color: Color(0xFFB8C0D8),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        invoice.number.isEmpty
                            ? 'Fattura senza numero'
                            : invoice.number,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFFE4E8FF),
                        ),
                      ),
                      DetailBadge(label: _statusLabel, color: _statusColor),
                    ],
                  ),
                ),
              ],
            ),
            rows: [
              DetailInfoRow(label: 'Cliente', value: _company),
              DetailInfoRow(
                label: 'Importo',
                value: _currFmt.format(invoice.amount),
              ),
            ],
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

// ────────────────────────────────────────────────
// Product Detail
// ────────────────────────────────────────────────

class ProductDetailPage extends StatelessWidget {
  ProductDetailPage({
    super.key,
    required this.product,
    required this.crmData,
    required this.onBack,
    required this.onDelete,
  });
  final Product product;
  final CrmData crmData;
  final VoidCallback onBack;
  final Future<void> Function() onDelete;

  final _currFmt = NumberFormat.currency(
    locale: 'it_IT',
    symbol: '€',
    decimalDigits: 2,
  );

  List<Quotation> get _usedIn => crmData.quotations
      .where((q) => q.lines.any((l) => l.productId == product.id))
      .toList();

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DetailBackBar(
            label: 'Panoramica prodotti',
            onBack: onBack,
            actions: [
              OutlinedButton.icon(
                onPressed: () async {
                  await onDelete();
                  onBack();
                },
                icon: const Icon(Icons.delete_outline, size: 15),
                label: const Text('Elimina'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFB91C1C),
                  side: const BorderSide(color: Color(0xFFB91C1C)),
                ),
              ),
            ],
          ),
          DetailInfoCard(
            title: 'Scheda prodotto',
            avatar: Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    color: GussoniBrand.primary.withValues(alpha: 0.10),
                  ),
                  child: const Icon(
                    Icons.inventory_2_outlined,
                    size: 26,
                    color: Color(0xFF034F3B),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        product.name,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFFE4E8FF),
                        ),
                      ),
                      if (product.sku.isNotEmpty)
                        Text(
                          product.sku,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF525D78),
                            fontFamily: 'monospace',
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            rows: [
              DetailInfoRow(
                label: 'Prezzo',
                value: '${_currFmt.format(product.price)} / ${product.unit}',
              ),
              DetailInfoRow(
                label: 'IVA',
                value: '${product.vatRate.toStringAsFixed(0)}%',
              ),
              if (product.category.isNotEmpty)
                DetailInfoRow(label: 'Categoria', value: product.category),
              if (product.description.isNotEmpty)
                DetailInfoRow(label: 'Descrizione', value: product.description),
            ],
          ),
          const SizedBox(height: 20),

          // Usato in preventivi
          DetailAccordion(
            title: 'Usato in preventivi',
            count: _usedIn.length,
            children: _usedIn
                .map(
                  (q) => Column(
                    children: [
                      AccordionRow(
                        leading: Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: q.status.color,
                          ),
                        ),
                        title: q.number,
                        trailing: Text(
                          _currFmt.format(q.total),
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        badge: DetailBadge(
                          label: q.status.label,
                          color: q.status.color,
                        ),
                      ),
                      const AccordionDivider(),
                    ],
                  ),
                )
                .toList(),
          ),

          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

class _RelatedTabPill extends StatelessWidget {
  const _RelatedTabPill({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: selected ? GussoniBrand.primaryBg : GussoniBrand.surfaceMuted,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: selected ? GussoniBrand.primaryBorder : GussoniBrand.border,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: selected
                  ? GussoniBrand.primary
                  : GussoniBrand.textSecondary,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: GussoniBrand.border),
            ),
            child: Text(
              '$count',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: GussoniBrand.textMuted,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _OpportunityRelatedQuotations extends StatelessWidget {
  const _OpportunityRelatedQuotations({
    required this.quotations,
    required this.canCreate,
    this.onCreate,
  });

  final List<Preventivo> quotations;
  final bool canCreate;
  final VoidCallback? onCreate;

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat.currency(
      locale: 'it_IT',
      symbol: '€',
      decimalDigits: 2,
    );
    if (quotations.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Nessun preventivo collegato a questa opportunità.',
            style: TextStyle(fontSize: 13, color: GussoniBrand.textMuted),
          ),
          if (onCreate != null && canCreate) ...[
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: onCreate,
              icon: const Icon(Icons.add, size: 14),
              label: const Text('Crea preventivo'),
            ),
          ],
        ],
      );
    }

    return Column(
      children: quotations
          .map(
            (quotation) => Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: GussoniBrand.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: GussoniBrand.border),
              ),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: GussoniBrand.primaryBg,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.request_quote_outlined,
                      color: GussoniBrand.primary,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          quotation.id,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: GussoniBrand.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Totale ${fmt.format(quotation.total)} · Istruttoria ${fmt.format(quotation.istruttoriaFee)}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: GussoniBrand.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  GStatusChip(
                    label: quotation.status.name,
                    color: switch (quotation.status) {
                      PreventivoStatus.draft => GussoniBrand.textMuted,
                      PreventivoStatus.sent => GussoniBrand.info,
                      PreventivoStatus.accepted => GussoniBrand.success,
                      PreventivoStatus.rejected => GussoniBrand.error,
                    },
                    small: true,
                  ),
                ],
              ),
            ),
          )
          .toList(),
    );
  }
}

class _OpportunityRelatedProjects extends StatelessWidget {
  const _OpportunityRelatedProjects({
    required this.projects,
    required this.showRendicontazioneHint,
    this.onOpenProject,
  });

  final List<Project> projects;
  final bool showRendicontazioneHint;
  final void Function(Project)? onOpenProject;

  @override
  Widget build(BuildContext context) {
    if (projects.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Nessun progetto collegato. Viene generato quando l\'opportunità viene presa in carico.',
            style: TextStyle(fontSize: 13, color: GussoniBrand.textMuted),
          ),
          if (showRendicontazioneHint) ...[
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.info_outline,
                  size: 13,
                  color: GussoniBrand.info,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Alla creazione del progetto verranno aggiunti automaticamente i task di rendicontazione nella fase dedicata.',
                    style: const TextStyle(
                      fontSize: 12,
                      color: GussoniBrand.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      );
    }

    return Column(
      children: projects
          .map(
            (project) => InkWell(
              onTap: onOpenProject == null
                  ? null
                  : () => onOpenProject!(project),
              borderRadius: BorderRadius.circular(10),
              child: Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: GussoniBrand.surface,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: GussoniBrand.border),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: GussoniBrand.primaryBg,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        Icons.folder_open_outlined,
                        color: GussoniBrand.primary,
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            project.name,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: GussoniBrand.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            project.code.isNotEmpty
                                ? '${project.code} · ${project.status}'
                                : project.status,
                            style: const TextStyle(
                              fontSize: 12,
                              color: GussoniBrand.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(
                      Icons.chevron_right,
                      size: 16,
                      color: GussoniBrand.textMuted,
                    ),
                  ],
                ),
              ),
            ),
          )
          .toList(),
    );
  }
}

class _OpportunityRelatedInvoices extends StatelessWidget {
  const _OpportunityRelatedInvoices({
    required this.invoices,
    required this.projectNameOf,
  });

  final List<InvoiceDraft> invoices;
  final String Function(String projectId) projectNameOf;

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat.currency(
      locale: 'it_IT',
      symbol: '€',
      decimalDigits: 2,
    );
    if (invoices.isEmpty) {
      return const Text(
        'Nessuna fattura collegata ai progetti di questa opportunità.',
        style: TextStyle(fontSize: 13, color: GussoniBrand.textMuted),
      );
    }

    return Column(
      children: invoices
          .map(
            (invoice) => Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: GussoniBrand.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: GussoniBrand.border),
              ),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: GussoniBrand.goldBg,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.receipt_long_outlined,
                      color: GussoniBrand.gold,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          invoice.number,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: GussoniBrand.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${fmt.format(invoice.amount)} · ${invoice.projectId == null ? 'Progetto non collegato' : projectNameOf(invoice.projectId!)}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: GussoniBrand.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  GStatusChip(
                    label: invoice.status.name,
                    color: switch (invoice.status) {
                      InvoiceStatus.draft => GussoniBrand.textMuted,
                      InvoiceStatus.readyForXml => GussoniBrand.info,
                      InvoiceStatus.exported => GussoniBrand.success,
                    },
                    small: true,
                  ),
                ],
              ),
            ),
          )
          .toList(),
    );
  }
}

// ────────────────────────────────────────────────
// Task Detail
// ────────────────────────────────────────────────

class TaskDetailPage extends StatefulWidget {
  const TaskDetailPage({
    super.key,
    required this.task,
    required this.workspace,
    required this.userId,
    required this.repository,
    required this.onBack,
    required this.onEdit,
    this.onMarkDone,
    this.onLogTime,
    this.siblingTasks = const [],
    this.onNavigateToTask,
    this.currentUserName,
    this.teamMembers = const [],
  });

  final WorkTask task;
  final WorkspaceSnapshot workspace;
  final String userId;
  final ApiWorkspaceRepository repository;
  final VoidCallback onBack;
  final Future<void> Function(WorkTask) onEdit;
  final Future<void> Function(WorkTask)? onMarkDone;
  final VoidCallback? onLogTime;
  final List<WorkTask> siblingTasks;
  final void Function(WorkTask)? onNavigateToTask;
  final String? currentUserName;
  final List<TeamMember> teamMembers;

  @override
  State<TaskDetailPage> createState() => _TaskDetailPageState();
}

class _TaskDetailPageState extends State<TaskDetailPage> {
  final _commentCtrl = TextEditingController();
  bool _submittingComment = false;

  @override
  void dispose() {
    _commentCtrl.dispose();
    super.dispose();
  }

  WorkTask get _task => widget.task;

  String get _company =>
      widget.workspace.companies
          .where((c) => c.id == _task.companyId)
          .firstOrNull
          ?.name ??
      '—';
  String get _project =>
      widget.workspace.projects
          .where((p) => p.id == _task.projectId)
          .firstOrNull
          ?.name ??
      '—';
  String get _phase =>
      widget.workspace.phases
          .where((p) => p.id == _task.phaseId)
          .firstOrNull
          ?.name ??
      '';
  String get _assignee {
    if (_task.assigneeId.isEmpty) return '—';
    // Prima cerca nei team members (utenti interni)
    final teamMember = widget.teamMembers
        .where((m) => m.userId == _task.assigneeId)
        .firstOrNull;
    if (teamMember != null) return teamMember.displayName;
    // Poi cerca nei contatti aziendali
    final contact = widget.workspace.companyContacts
        .where((c) => c.id == _task.assigneeId)
        .firstOrNull;
    if (contact != null) return contact.name;
    // Fallback: mostra l'ID troncato leggibile
    return _task.assigneeId.length > 12
        ? _task.assigneeId.substring(0, 12)
        : _task.assigneeId;
  }

  Color get _statusColor => switch (_task.status) {
    TaskStatus.backlog => GussoniBrand.textMuted,
    TaskStatus.planned => GussoniBrand.info,
    TaskStatus.inProgress => GussoniBrand.warning,
    TaskStatus.done => GussoniBrand.success,
  };

  String get _statusLabel => switch (_task.status) {
    TaskStatus.backlog => 'Backlog',
    TaskStatus.planned => 'Pianificato',
    TaskStatus.inProgress => 'In corso',
    TaskStatus.done => 'Fatto',
  };

  int get _currentIndex =>
      widget.siblingTasks.indexWhere((t) => t.id == _task.id);
  WorkTask? get _prevTask =>
      _currentIndex > 0 ? widget.siblingTasks[_currentIndex - 1] : null;
  WorkTask? get _nextTask =>
      _currentIndex >= 0 && _currentIndex < widget.siblingTasks.length - 1
      ? widget.siblingTasks[_currentIndex + 1]
      : null;

  Future<void> _addComment() async {
    final text = _commentCtrl.text.trim();
    if (text.isEmpty) return;
    setState(() => _submittingComment = true);
    final comment = TaskComment(
      id: 'tc-${DateTime.now().microsecondsSinceEpoch}',
      taskId: _task.id,
      authorId: widget.userId,
      authorName: widget.currentUserName ?? widget.userId,
      body: text,
      createdAt: DateTime.now(),
    );
    await widget.repository.createTaskComment(widget.userId, comment);
    _commentCtrl.clear();
    if (mounted) setState(() => _submittingComment = false);
  }

  @override
  Widget build(BuildContext context) {
    final dateFmt = DateFormat('dd/MM/yyyy');
    final isOverdue =
        _task.deadline.isBefore(DateTime.now()) &&
        _task.status != TaskStatus.done;

    return Column(
      children: [
        // ── Top nav ──────────────────────────────────────────────────────
        Container(
          color: GussoniBrand.surface,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          child: Row(
            children: [
              InkWell(
                onTap: widget.onBack,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.arrow_back,
                      size: 14,
                      color: GussoniBrand.textMuted,
                    ),
                    const SizedBox(width: 6),
                    const Text(
                      'Panoramica task',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: GussoniBrand.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              // Prev / Next
              if (_prevTask != null)
                InkWell(
                  onTap: () => widget.onNavigateToTask?.call(_prevTask!),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.chevron_left,
                        size: 16,
                        color: GussoniBrand.textMuted,
                      ),
                      Text(
                        'Task precedente',
                        style: TextStyle(
                          fontSize: 12,
                          color: GussoniBrand.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              if (_prevTask != null && _nextTask != null)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Text(
                    '|',
                    style: TextStyle(color: GussoniBrand.textDisabled),
                  ),
                ),
              if (_nextTask != null)
                InkWell(
                  onTap: () => widget.onNavigateToTask?.call(_nextTask!),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Prossimo task',
                        style: TextStyle(
                          fontSize: 12,
                          color: GussoniBrand.textMuted,
                        ),
                      ),
                      Icon(
                        Icons.chevron_right,
                        size: 16,
                        color: GussoniBrand.textMuted,
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        const Divider(height: 1),

        // ── Content ──────────────────────────────────────────────────────
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Task card ───────────────────────────────────────────────
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: GussoniBrand.surface,
                    border: Border.all(color: GussoniBrand.border),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header
                      Row(
                        children: [
                          const Text(
                            'Task',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: GussoniBrand.textPrimary,
                            ),
                          ),
                          const Spacer(),
                          IconButton(
                            onPressed: () => widget.onEdit(_task),
                            icon: const Icon(
                              Icons.edit_outlined,
                              size: 16,
                              color: GussoniBrand.textMuted,
                            ),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                              minWidth: 28,
                              minHeight: 28,
                            ),
                            tooltip: 'Modifica',
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      // Subtitle row: status · scadenza | titolo  [badge priorità]
                      Row(
                        children: [
                          DetailBadge(label: _statusLabel, color: _statusColor),
                          const SizedBox(width: 8),
                          if (isOverdue)
                            const DetailBadge(
                              label: 'Scaduto',
                              color: GussoniBrand.error,
                            ),
                          if (!isOverdue)
                            Text(
                              dateFmt.format(_task.deadline),
                              style: const TextStyle(
                                fontSize: 12,
                                color: GussoniBrand.textMuted,
                              ),
                            ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _task.name,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: GussoniBrand.textPrimary,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      // Action buttons
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          OutlinedButton.icon(
                            onPressed: widget.onLogTime,
                            icon: const Icon(Icons.schedule_outlined, size: 14),
                            label: const Text('Segna il tempo'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: GussoniBrand.textSecondary,
                              side: const BorderSide(
                                color: GussoniBrand.border,
                              ),
                              textStyle: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          if (_task.status != TaskStatus.done)
                            FilledButton.icon(
                              onPressed: widget.onMarkDone == null
                                  ? null
                                  : () => widget.onMarkDone!(_task),
                              icon: const Icon(
                                Icons.check_circle_outline,
                                size: 14,
                              ),
                              label: const Text('Segna come fatto'),
                              style: FilledButton.styleFrom(
                                backgroundColor: GussoniBrand.success,
                                textStyle: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            )
                          else
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: GussoniBrand.successBg,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: GussoniBrand.successBorder,
                                ),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.check_circle,
                                    size: 14,
                                    color: GussoniBrand.success,
                                  ),
                                  SizedBox(width: 6),
                                  Text(
                                    'Completato',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: GussoniBrand.success,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      // Two-column: fields + description
                      LayoutBuilder(
                        builder: (ctx, c) {
                          final twoCol = c.maxWidth > 600;
                          final fields = Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _TRow('Cliente', _company),
                              _TRow('Assegnato a', _assignee),
                              _TRow(
                                'Data di scadenza',
                                dateFmt.format(_task.deadline),
                                valueColor: isOverdue
                                    ? GussoniBrand.error
                                    : null,
                              ),
                              if (_project.isNotEmpty)
                                _TRow('Progetto', _project),
                              if (_phase.isNotEmpty) _TRow('Fase', _phase),
                              _TRow('Ore stimate', '${_task.estimatedHours}h'),
                              if (_task.loggedHours > 0)
                                _TRow('Ore tracciate', '${_task.loggedHours}h'),
                              _TRow(
                                'Fatturabile',
                                _task.billable ? 'Sì' : 'No',
                              ),
                            ],
                          );
                          final desc = Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Descrizione',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: GussoniBrand.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 8),
                              // For now description is empty - this can be extended with a description field on WorkTask
                              const Text(
                                'Nessuna descrizione.',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: GussoniBrand.textMuted,
                                ),
                              ),
                            ],
                          );
                          if (twoCol) {
                            return Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(child: fields),
                                const SizedBox(width: 32),
                                Expanded(child: desc),
                              ],
                            );
                          }
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              fields,
                              const SizedBox(height: 16),
                              desc,
                            ],
                          );
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // ── Messaggi interni ─────────────────────────────────────────
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: GussoniBrand.surface,
                    border: Border.all(color: GussoniBrand.border),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Messaggi interni',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: GussoniBrand.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 14),
                      // Input
                      const Text(
                        'Aggiungi un messaggio',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: GussoniBrand.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _commentCtrl,
                        minLines: 3,
                        maxLines: 6,
                        decoration: InputDecoration(
                          hintText:
                              widget.currentUserName ??
                              'Scrivi un messaggio...',
                          border: const OutlineInputBorder(),
                          contentPadding: const EdgeInsets.all(12),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          OutlinedButton(
                            onPressed: () {},
                            style: OutlinedButton.styleFrom(
                              foregroundColor: GussoniBrand.textSecondary,
                              side: const BorderSide(
                                color: GussoniBrand.border,
                              ),
                            ),
                            child: const Text(
                              'Aggiungi allegato',
                              style: TextStyle(fontSize: 12),
                            ),
                          ),
                          const Spacer(),
                          FilledButton(
                            onPressed: _submittingComment ? null : _addComment,
                            style: FilledButton.styleFrom(
                              backgroundColor: GussoniBrand.primary,
                            ),
                            child: _submittingComment
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Text('Aggiungi'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      // Comments stream
                      StreamBuilder<List<TaskComment>>(
                        stream: widget.repository.watchTaskComments(
                          widget.userId,
                          _task.id,
                        ),
                        builder: (ctx, snap) {
                          final comments = snap.data ?? [];
                          if (comments.isEmpty && !snap.hasData) {
                            return const SizedBox.shrink();
                          }
                          if (comments.isEmpty) {
                            return const Text(
                              'Nessun messaggio.',
                              style: TextStyle(
                                fontSize: 13,
                                color: GussoniBrand.textMuted,
                              ),
                            );
                          }
                          return Column(
                            children: comments
                                .map((c) => _CommentRow(comment: c))
                                .toList(),
                          );
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _TRow extends StatelessWidget {
  const _TRow(this.label, this.value, {this.valueColor});
  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 130,
          child: Text(
            label,
            style: const TextStyle(fontSize: 13, color: GussoniBrand.textMuted),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: valueColor ?? GussoniBrand.textPrimary,
            ),
          ),
        ),
      ],
    ),
  );
}

class _CommentRow extends StatelessWidget {
  const _CommentRow({required this.comment});
  final TaskComment comment;

  @override
  Widget build(BuildContext context) {
    final timeFmt = DateFormat('dd/MM/yyyy HH:mm');
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: GussoniBrand.borderSubtle)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: GussoniBrand.surfaceSubtle,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: GussoniBrand.border),
            ),
            child: const Icon(
              Icons.person_outline,
              size: 16,
              color: GussoniBrand.textMuted,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: const TextStyle(
                  fontSize: 13,
                  color: GussoniBrand.textPrimary,
                ),
                children: [
                  TextSpan(
                    text: '${comment.authorName}: ',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  TextSpan(text: comment.body),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            timeFmt.format(comment.createdAt),
            style: const TextStyle(fontSize: 11, color: GussoniBrand.textMuted),
          ),
        ],
      ),
    );
  }
}
