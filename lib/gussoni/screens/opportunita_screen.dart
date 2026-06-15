import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../app/nexora_dialog.dart';
import '../../brand_config.dart';
import '../../data/api_workspace_repository.dart';
import '../../models/domain_models.dart';
import '../../data/team_repository.dart';
import '../widgets/g_table.dart';

// ──────────────────────────────────────────────────────────────
// Schermata principale Opportunità
// ──────────────────────────────────────────────────────────────

class OpportunitaGussoniScreen extends StatefulWidget {
  const OpportunitaGussoniScreen({
    super.key,
    required this.workspace,
    required this.userId,
    required this.repository,
    required this.teamInfo,
    this.onCreatePreventivo,
    this.onOpenOpportunity,
    this.showHeader = true,
    this.showCreateButton = true,
  });

  final WorkspaceSnapshot workspace;
  final String userId;
  final ApiWorkspaceRepository repository;
  final TeamInfo? teamInfo;
  final void Function(Opportunity opp)? onCreatePreventivo;
  final void Function(Opportunity opp)? onOpenOpportunity;
  final bool showHeader;
  final bool showCreateButton;

  @override
  State<OpportunitaGussoniScreen> createState() =>
      _OpportunitaGussoniScreenState();
}

class _OpportunitaGussoniScreenState extends State<OpportunitaGussoniScreen> {
  OpportunityStatus? _filterStatus;
  String _search = '';
  Opportunity? _mobileSelected;
  bool _isMobile = false;

  List<Opportunity> get _filtered {
    var list = widget.workspace.opportunities;
    if (_filterStatus != null) {
      list = list.where((o) => o.status == _filterStatus).toList();
    }
    if (_search.isNotEmpty) {
      final q = _search.toLowerCase();
      list = list
          .where(
            (o) =>
                o.title.toLowerCase().contains(q) ||
                _companyName(o.companyId).toLowerCase().contains(q) ||
                o.bandoSource.toLowerCase().contains(q),
          )
          .toList();
    }
    return list;
  }

  String _companyName(String id) {
    final c = widget.workspace.companies.where((c) => c.id == id).firstOrNull;
    return c?.name ?? id;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        _isMobile = constraints.maxWidth < 560;
        return _isMobile ? _buildMobileWrapper() : _buildContent();
      },
    );
  }

  Widget _buildMobileWrapper() {
    final sel = _mobileSelected;
    return GMobileNavWrapper(
      showDetail: sel != null,
      list: _buildContent(),
      detail: sel == null
          ? const SizedBox.shrink()
          : Column(
              children: [
                GMobileBackBar(
                  backLabel: 'Opportunità',
                  title: sel.title,
                  onBack: () => setState(() => _mobileSelected = null),
                ),
                Expanded(
                  child: GDetailPanel(
                    title: sel.title,
                    subtitle: _companyName(sel.companyId),
                    icon: _StatusDot(status: sel.status),
                    children: [
                      GDetailSection(
                        title: 'Opportunità',
                        children: [
                          GInfoRow('Cliente', _companyName(sel.companyId)),
                          GInfoRow('Stato', _statusLabel(sel.status)),
                          if (sel.bandoDeadline != null)
                            GInfoRow(
                              'Scadenza bando',
                              DateFormat(
                                'dd/MM/yyyy',
                              ).format(sel.bandoDeadline!),
                            ),
                          if (sel.estimatedValue != null)
                            GInfoRow(
                              'Valore stimato',
                              '€ ${NumberFormat('#,##0.00', 'it_IT').format(sel.estimatedValue)}',
                            ),
                          if (sel.bandoSource.isNotEmpty)
                            GInfoRow('Fonte', sel.bandoSource),
                          if (sel.rifOfferta.isNotEmpty)
                            GInfoRow('Rif. Offerta', sel.rifOfferta),
                        ],
                      ),
                      if (sel.notes.isNotEmpty)
                        GDetailSection(
                          title: 'Note',
                          children: [
                            Text(
                              sel.notes,
                              style: const TextStyle(fontSize: 13, height: 1.5),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  String _statusLabel(OpportunityStatus s) => switch (s) {
    OpportunityStatus.inAttesa => 'In attesa',
    OpportunityStatus.preventivazione => 'Preventivazione',
    OpportunityStatus.presaInCarico => 'Presa in carico',
    OpportunityStatus.accettata => 'Accettata',
    OpportunityStatus.accettataSenzaFirma => 'Acc. senza firma',
    OpportunityStatus.inAttesaRinnovoAutomatico => 'Rinnovo automatico',
    OpportunityStatus.persa => 'Persa',
  };

  Widget _buildContent() {
    final pending = widget.workspace.opportunities
        .where(
          (o) =>
              o.status == OpportunityStatus.inAttesa ||
              o.status == OpportunityStatus.preventivazione,
        )
        .length;
    final accepted = widget.workspace.opportunities
        .where(
          (o) =>
              o.status == OpportunityStatus.accettata ||
              o.status == OpportunityStatus.accettataSenzaFirma,
        )
        .length;
    final taken = widget.workspace.opportunities
        .where((o) => o.status == OpportunityStatus.presaInCarico)
        .length;
    final expiring = widget.workspace.opportunities.where((o) {
      final deadline = o.bandoDeadline;
      if (deadline == null) return false;
      final days = deadline.difference(DateTime.now()).inDays;
      return days >= 0 && days <= 14;
    }).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.showHeader) ...[
          _Header(
            userId: widget.userId,
            repository: widget.repository,
            companies: widget.workspace.companies,
            onCreated: (_) {},
            showCreateButton: widget.showCreateButton,
            onSearch: (v) => setState(() => _search = v),
          ),
          const SizedBox(height: 12),
        ] else ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              SizedBox(
                width: 250,
                child: TextField(
                  onChanged: (v) => setState(() => _search = v),
                  decoration: const InputDecoration(
                    hintText: 'Cerca…',
                    prefixIcon: Icon(Icons.search_rounded, size: 17),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
        ],
        _FilterBar(
          selected: _filterStatus,
          opportunities: widget.workspace.opportunities,
          onFilter: (s) => setState(() {
            _filterStatus = s;
          }),
        ),
        const SizedBox(height: 12),
        _OpportunityOverview(
          pending: pending,
          accepted: accepted,
          taken: taken,
          expiring: expiring,
        ),
        const SizedBox(height: 14),
        Expanded(
          child: GTable<Opportunity>(
            rows: _filtered,
            onRowTap: (o) {
              if (_isMobile) {
                setState(() => _mobileSelected = o);
              } else {
                widget.onOpenOpportunity?.call(o);
              }
            },
            contextActionsForRow: (o) => [
              if (widget.onOpenOpportunity != null)
                GContextMenuAction(
                  label: 'Apri opportunità',
                  icon: Icons.open_in_new_rounded,
                  onSelected: () => widget.onOpenOpportunity!(o),
                ),
              if (widget.onCreatePreventivo != null)
                GContextMenuAction(
                  label: 'Crea preventivo',
                  icon: Icons.request_quote_outlined,
                  onSelected: () => widget.onCreatePreventivo!(o),
                ),
              GContextMenuAction(
                label: 'Elimina',
                icon: Icons.delete_outline_rounded,
                destructive: true,
                onSelected: () => _deleteOpportunity(o),
              ),
            ],
            emptyLabel: 'Nessuna opportunità trovata.',
            columns: [
              GCol<Opportunity>(
                label: 'Titolo',
                flex: 4,
                cell: (o) => Row(
                  children: [
                    _StatusDot(status: o.status),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        o.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: GussoniBrand.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              GCol<Opportunity>(
                label: 'Società',
                flex: 3,
                cell: (o) => Row(
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: GussoniBrand.primary.withValues(alpha: .10),
                        border: Border.all(
                          color: GussoniBrand.primary.withValues(alpha: .24),
                        ),
                      ),
                      child: Icon(
                        Icons.apartment_rounded,
                        size: 14,
                        color: GussoniBrand.primary,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _companyName(o.companyId),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: GussoniBrand.textSecondary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              GCol<Opportunity>(
                label: 'Fonte',
                flex: 2,
                cell: (o) => Text(
                  o.bandoSource.isEmpty ? '—' : o.bandoSource,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: GussoniBrand.textMuted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              GCol<Opportunity>(
                label: 'Stato',
                flex: 2,
                cell: (o) => Align(
                  alignment: Alignment.centerLeft,
                  child: _StatusChip(status: o.status),
                ),
              ),
              GCol<Opportunity>(
                label: 'Scadenza',
                flex: 2,
                cell: (o) => Text(
                  o.bandoDeadline != null
                      ? DateFormat('dd/MM/yyyy').format(o.bandoDeadline!)
                      : '—',
                  style: TextStyle(
                    color: o.bandoDeadline == null
                        ? GussoniBrand.textMuted
                        : _deadlineColorStatic(o.bandoDeadline!),
                  ),
                ),
              ),
              GCol<Opportunity>(
                label: 'Valore',
                flex: 2,
                align: TextAlign.right,
                cell: (o) => Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    o.estimatedValue != null
                        ? '€ ${NumberFormat('#,##0', 'it_IT').format(o.estimatedValue)}'
                        : '—',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: GussoniBrand.gold,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _deleteOpportunity(Opportunity opportunity) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => NexoraConfirmDialog(
        title: 'Elimina opportunità?',
        icon: Icons.delete_outline_rounded,
        message: 'Eliminare "${opportunity.title}"?',
        confirmLabel: 'Elimina',
        isDanger: true,
      ),
    );
    if (confirmed != true) return;
    await widget.repository.deleteOpportunity(widget.userId, opportunity.id);
    if (mounted && _mobileSelected?.id == opportunity.id) {
      setState(() => _mobileSelected = null);
    }
  }
}

Color _deadlineColorStatic(DateTime d) {
  final diff = d.difference(DateTime.now()).inDays;
  if (diff < 0) return GussoniBrand.error;
  if (diff < 7) return GussoniBrand.warning;
  return GussoniBrand.textMuted;
}

class _OpportunityOverview extends StatelessWidget {
  const _OpportunityOverview({
    required this.pending,
    required this.accepted,
    required this.taken,
    required this.expiring,
  });

  final int pending;
  final int accepted;
  final int taken;
  final int expiring;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          GussoniBrand.glassSurfaceStrong.withValues(alpha: .88),
          GussoniBrand.glassSurfaceMuted.withValues(alpha: .70),
          GussoniBrand.warning.withValues(alpha: .08),
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
          child: _OpportunityMetric(
            label: 'Da lavorare',
            value: '$pending',
            icon: Icons.bolt_rounded,
            color: GussoniBrand.warning,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _OpportunityMetric(
            label: 'Accettate',
            value: '$accepted',
            icon: Icons.verified_rounded,
            color: GussoniBrand.success,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _OpportunityMetric(
            label: 'Prese in carico',
            value: '$taken',
            icon: Icons.hub_rounded,
            color: GussoniBrand.primary,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _OpportunityMetric(
            label: 'Scadono presto',
            value: '$expiring',
            icon: Icons.alarm_rounded,
            color: GussoniBrand.error,
          ),
        ),
      ],
    ),
  );
}

class _OpportunityMetric extends StatelessWidget {
  const _OpportunityMetric({
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

// ── Header con pulsante nuova opportunità ──

class _Header extends StatelessWidget {
  const _Header({
    required this.userId,
    required this.repository,
    required this.companies,
    required this.onCreated,
    required this.onSearch,
    this.showCreateButton = true,
  });
  final String userId;
  final ApiWorkspaceRepository repository;
  final List<Company> companies;
  final void Function(String id) onCreated;
  final void Function(String) onSearch;
  final bool showCreateButton;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: GussoniBrand.warning.withValues(alpha: .12),
                  border: Border.all(
                    color: GussoniBrand.warning.withValues(alpha: .30),
                  ),
                ),
                child: const Icon(
                  Icons.trending_up_rounded,
                  color: GussoniBrand.warning,
                  size: 19,
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'Opportunità',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  color: GussoniBrand.textPrimary,
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          width: 250,
          child: TextField(
            onChanged: onSearch,
            decoration: const InputDecoration(
              hintText: 'Cerca…',
              prefixIcon: Icon(Icons.search_rounded, size: 17),
            ),
          ),
        ),
        const SizedBox(width: 10),
        if (showCreateButton)
          FilledButton.icon(
            onPressed: () => _showCreateDialog(context),
            icon: const Icon(Icons.add, size: 16),
            label: const Text('Nuova opportunità'),
          ),
      ],
    );
  }

  void _showCreateDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (_) => CreateOppDialog(
        userId: userId,
        repository: repository,
        companies: companies,
      ),
    );
  }
}

// ── Filtri per status ──

class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.selected,
    required this.opportunities,
    required this.onFilter,
  });
  final OpportunityStatus? selected;
  final List<Opportunity> opportunities;
  final void Function(OpportunityStatus?) onFilter;

  static const _tabs = [
    (null, 'Tutte'),
    (OpportunityStatus.inAttesa, 'In attesa'),
    (OpportunityStatus.preventivazione, 'Preventivazione'),
    (OpportunityStatus.accettata, 'Accettate'),
    (OpportunityStatus.accettataSenzaFirma, 'Acc. senza firma'),
    (OpportunityStatus.inAttesaRinnovoAutomatico, 'Rinnovo auto'),
    (OpportunityStatus.presaInCarico, 'Prese in carico'),
    (OpportunityStatus.persa, 'Perse'),
  ];

  int _count(OpportunityStatus? s) => s == null
      ? opportunities.length
      : opportunities.where((o) => o.status == s).length;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: _tabs.map((t) {
                final isSelected = selected == t.$1;
                final count = _count(t.$1);
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: GestureDetector(
                    onTap: () => onFilter(t.$1),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: isSelected
                              ? [
                                  GussoniBrand.primary.withValues(alpha: .94),
                                  GussoniBrand.info.withValues(alpha: .84),
                                ]
                              : [
                                  Colors.white.withValues(alpha: .58),
                                  GussoniBrand.glassSurfaceMuted.withValues(
                                    alpha: .68,
                                  ),
                                ],
                        ),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: isSelected
                              ? Colors.white.withValues(alpha: .62)
                              : Colors.white.withValues(alpha: .72),
                        ),
                        boxShadow: isSelected
                            ? [
                                BoxShadow(
                                  color: GussoniBrand.primary.withValues(
                                    alpha: .18,
                                  ),
                                  blurRadius: 14,
                                  offset: const Offset(0, 8),
                                ),
                              ]
                            : null,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            t.$2,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: isSelected
                                  ? Colors.white
                                  : GussoniBrand.textSecondary,
                            ),
                          ),
                          if (count > 0) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 1,
                              ),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? Colors.white.withValues(alpha: .25)
                                    : Colors.white.withValues(alpha: .56),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                '$count',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: isSelected
                                      ? Colors.white
                                      : GussoniBrand.textMuted,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ),
      ],
    );
  }
}

// ── Lista opportunità ──

class _OppList extends StatefulWidget {
  const _OppList({
    required this.opportunities,
    required this.companyName,
    required this.selected,
    required this.onSelect,
  });
  final List<Opportunity> opportunities;
  final String Function(String) companyName;
  final Opportunity? selected;
  final void Function(Opportunity) onSelect;

  @override
  State<_OppList> createState() => _OppListState();
}

class _OppListState extends State<_OppList> {
  static const _rowsPerPage = 10;
  int _page = 0;

  @override
  void didUpdateWidget(covariant _OppList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.opportunities.length != widget.opportunities.length) {
      _page = 0;
      return;
    }
    final maxPage = _maxPage;
    if (_page > maxPage) {
      _page = maxPage;
    }
  }

  int get _maxPage {
    if (widget.opportunities.isEmpty) {
      return 0;
    }
    return (widget.opportunities.length - 1) ~/ _rowsPerPage;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.opportunities.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.search_off_outlined,
              size: 40,
              color: GussoniBrand.textDisabled,
            ),
            const SizedBox(height: 12),
            Text(
              'Nessuna opportunità trovata.',
              style: TextStyle(color: GussoniBrand.textMuted, fontSize: 14),
            ),
          ],
        ),
      );
    }
    final start = (_page * _rowsPerPage).clamp(0, widget.opportunities.length);
    final end = (start + _rowsPerPage).clamp(0, widget.opportunities.length);
    final pageItems = widget.opportunities.sublist(start, end);
    final totalPages = ((widget.opportunities.length - 1) ~/ _rowsPerPage) + 1;
    final from = (start + 1).clamp(1, widget.opportunities.length);
    final to = end;

    return Column(
      children: [
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.only(bottom: 12),
            itemCount: pageItems.length,
            separatorBuilder: (_, __) => const SizedBox(height: 4),
            itemBuilder: (context, i) {
              final opp = pageItems[i];
              final isSel = widget.selected?.id == opp.id;
              return _OppRow(
                opp: opp,
                companyName: widget.companyName(opp.companyId),
                isSelected: isSel,
                onTap: () => widget.onSelect(opp),
              );
            },
          ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(4, 10, 4, 0),
          child: Row(
            children: [
              Text(
                '$from-$to di ${widget.opportunities.length}',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: GussoniBrand.textMuted,
                ),
              ),
              const Spacer(),
              Text(
                'Pagina ${_page + 1} / $totalPages',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: GussoniBrand.textMuted,
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: _page == 0
                    ? null
                    : () => setState(
                        () => _page = (_page - 1).clamp(0, _maxPage),
                      ),
                tooltip: 'Pagina precedente',
                icon: const Icon(Icons.chevron_left),
              ),
              IconButton(
                onPressed: _page >= _maxPage
                    ? null
                    : () => setState(
                        () => _page = (_page + 1).clamp(0, _maxPage),
                      ),
                tooltip: 'Pagina successiva',
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _OppRow extends StatelessWidget {
  const _OppRow({
    required this.opp,
    required this.companyName,
    required this.isSelected,
    required this.onTap,
  });
  final Opportunity opp;
  final String companyName;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isSelected ? GussoniBrand.primaryBg : GussoniBrand.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected
                ? GussoniBrand.primaryBorder
                : GussoniBrand.border,
          ),
        ),
        child: Row(
          children: [
            // Status dot
            _StatusDot(status: opp.status),
            const SizedBox(width: 12),
            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    opp.title,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: GussoniBrand.textPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Icon(
                        Icons.apartment_outlined,
                        size: 12,
                        color: GussoniBrand.textMuted,
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          companyName,
                          style: TextStyle(
                            fontSize: 12,
                            color: GussoniBrand.textMuted,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (opp.bandoSource.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Icon(
                          Icons.source_outlined,
                          size: 12,
                          color: GussoniBrand.textDisabled,
                        ),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            opp.bandoSource,
                            style: TextStyle(
                              fontSize: 12,
                              color: GussoniBrand.textDisabled,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            // Right info
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                _StatusChip(status: opp.status),
                if (opp.bandoDeadline != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Scad. ${DateFormat('dd/MM/yy').format(opp.bandoDeadline!)}',
                    style: TextStyle(
                      fontSize: 11,
                      color: _deadlineColor(opp.bandoDeadline!),
                    ),
                  ),
                ],
                if (opp.estimatedValue != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    '€ ${NumberFormat('#,##0', 'it_IT').format(opp.estimatedValue)}',
                    style: TextStyle(
                      fontSize: 11,
                      color: GussoniBrand.gold,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Color _deadlineColor(DateTime d) {
    final diff = d.difference(DateTime.now()).inDays;
    if (diff < 0) return GussoniBrand.error;
    if (diff < 7) return GussoniBrand.warning;
    return GussoniBrand.textMuted;
  }
}

// ── Pannello dettaglio opportunità ──

class _OppDetail extends StatelessWidget {
  const _OppDetail({
    required this.opp,
    required this.workspace,
    required this.userId,
    required this.repository,
    required this.teamInfo,
    required this.onClose,
    this.onCreatePreventivo,
    this.onUpdated,
  });
  final Opportunity opp;
  final WorkspaceSnapshot workspace;
  final String userId;
  final ApiWorkspaceRepository repository;
  final TeamInfo? teamInfo;
  final VoidCallback onClose;
  final void Function(Opportunity)? onCreatePreventivo;
  final void Function(Opportunity)? onUpdated;

  String _companyName() {
    return workspace.companies
            .where((c) => c.id == opp.companyId)
            .firstOrNull
            ?.name ??
        '—';
  }

  // Preventivo Gussoni collegato
  Preventivo? get _linkedQuotation => workspace.gussoniQuotations
      .where((q) => q.opportunityId == opp.id)
      .firstOrNull;

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat('#,##0.00', 'it_IT');
    final dateFmt = DateFormat('dd/MM/yyyy');
    final linked = _linkedQuotation;

    return Container(
      color: GussoniBrand.scaffoldBg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.fromLTRB(20, 16, 12, 14),
            color: GussoniBrand.surface,
            child: Row(
              children: [
                _StatusDot(status: opp.status),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        opp.title,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: GussoniBrand.textPrimary,
                        ),
                      ),
                      Text(
                        _companyName(),
                        style: TextStyle(
                          fontSize: 13,
                          color: GussoniBrand.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: onClose,
                  icon: Icon(
                    Icons.close,
                    size: 18,
                    color: GussoniBrand.textMuted,
                  ),
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
                  // Status + azioni
                  _DetailSection(
                    title: 'Stato e azioni',
                    children: [
                      Row(
                        children: [
                          _StatusChip(status: opp.status),
                          const Spacer(),
                          ..._buildActions(context),
                        ],
                      ),
                    ],
                  ),

                  const SizedBox(height: 12),

                  // Commerciale
                  _DetailSection(
                    title: 'Commerciale',
                    children: [
                      if (opp.rifOfferta.isNotEmpty)
                        _InfoRow('Rif. Offerta', opp.rifOfferta),
                      if (opp.contattoCommerciale.isNotEmpty)
                        _InfoRow('Contatto comm.', opp.contattoCommerciale),
                      if (opp.daFaturareA.isNotEmpty)
                        _InfoRow('Da fatturare a', opp.daFaturareA),
                      if (opp.partnerCommerciale.isNotEmpty)
                        _InfoRow('Partner comm.', opp.partnerCommerciale),
                      if (opp.fornitore.isNotEmpty)
                        _InfoRow('Fornitore', opp.fornitore),
                      _InfoRow(
                        'Presa in carico',
                        opp.presaInCarico ? 'Sì' : 'No',
                      ),
                      if (opp.dataInvioPreventivo != null)
                        _InfoRow(
                          'Invio preventivo',
                          dateFmt.format(opp.dataInvioPreventivo!),
                        ),
                      if (opp.dataConfermaPreventivo != null)
                        _InfoRow(
                          'Conferma prev.',
                          dateFmt.format(opp.dataConfermaPreventivo!),
                        ),
                    ],
                  ),

                  const SizedBox(height: 12),

                  // Bando
                  _DetailSection(
                    title: 'Bando',
                    children: [
                      if (opp.bandoReference.isNotEmpty)
                        _InfoRow('Riferimento', opp.bandoReference),
                      _InfoRow(
                        'Ente',
                        opp.bandoSource.isNotEmpty ? opp.bandoSource : '—',
                      ),
                      if (opp.bandoDeadline != null)
                        _InfoRow(
                          'Scadenza bando',
                          dateFmt.format(opp.bandoDeadline!),
                        ),
                      if (opp.scadenzaPresentazione != null)
                        _InfoRow(
                          'Scad. presentaz.',
                          dateFmt.format(opp.scadenzaPresentazione!),
                        ),
                      if (opp.scadenzaOperativa != null)
                        _InfoRow(
                          'Scad. operativa',
                          dateFmt.format(opp.scadenzaOperativa!),
                        ),
                      _InfoRow(
                        'Valore stimato',
                        opp.estimatedValue != null
                            ? '€ ${fmt.format(opp.estimatedValue)}'
                            : '—',
                      ),
                    ],
                  ),

                  const SizedBox(height: 12),

                  // Note operative
                  if (opp.notes.isNotEmpty)
                    _DetailSection(
                      title: 'Note',
                      children: [
                        Text(
                          opp.notes,
                          style: TextStyle(
                            fontSize: 13,
                            color: GussoniBrand.textSecondary,
                            height: 1.5,
                          ),
                        ),
                      ],
                    ),

                  if (opp.analysisNotes.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    _DetailSection(
                      title: 'Note analisi',
                      children: [
                        Text(
                          opp.analysisNotes,
                          style: TextStyle(
                            fontSize: 13,
                            color: GussoniBrand.textSecondary,
                            height: 1.5,
                          ),
                        ),
                      ],
                    ),
                  ],

                  // Preventivo collegato
                  if (linked != null) ...[
                    const SizedBox(height: 12),
                    _DetailSection(
                      title: 'Preventivo collegato',
                      children: [
                        _PreventivoMiniCard(quotation: linked, fmt: fmt),
                      ],
                    ),
                  ],

                  const SizedBox(height: 12),
                  _InfoRow(
                    'Creato il',
                    DateFormat('dd/MM/yyyy HH:mm').format(opp.createdAt),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildActions(BuildContext context) {
    final actions = <Widget>[];
    switch (opp.status) {
      case OpportunityStatus.inAttesa:
        actions.add(
          _ActionBtn(
            label: 'Avvia preventivazione',
            icon: Icons.request_quote_outlined,
            color: GussoniBrand.gold,
            onTap: () =>
                _updateStatus(context, OpportunityStatus.preventivazione),
          ),
        );
        actions.add(
          _ActionBtn(
            label: 'Segna persa',
            icon: Icons.cancel_outlined,
            color: GussoniBrand.error,
            onTap: () => _updateStatus(context, OpportunityStatus.persa),
          ),
        );
      case OpportunityStatus.preventivazione:
        actions.add(
          _ActionBtn(
            label: 'Crea preventivo',
            icon: Icons.request_quote_outlined,
            color: GussoniBrand.primary,
            onTap: () => onCreatePreventivo?.call(opp),
          ),
        );
        actions.add(
          _ActionBtn(
            label: 'Accettata',
            icon: Icons.check_circle_outline,
            color: GussoniBrand.success,
            onTap: () => _updateStatus(context, OpportunityStatus.accettata),
          ),
        );
        actions.add(
          _ActionBtn(
            label: 'Segna persa',
            icon: Icons.cancel_outlined,
            color: GussoniBrand.error,
            onTap: () => _updateStatus(context, OpportunityStatus.persa),
          ),
        );
      case OpportunityStatus.accettata:
      case OpportunityStatus.accettataSenzaFirma:
      case OpportunityStatus.inAttesaRinnovoAutomatico:
      case OpportunityStatus.presaInCarico:
      case OpportunityStatus.persa:
        break;
    }
    return actions;
  }

  Future<void> _updateStatus(
    BuildContext context,
    OpportunityStatus status,
  ) async {
    final updated = opp.copyWith(status: status);
    await repository.updateOpportunity(userId, updated);
    onUpdated?.call(updated);
  }
}

// ── Dialog crea opportunità ──

/// Dialog di creazione opportunità: popup unico con selezione cliente
/// (usato dal modulo Opportunità, dalle azioni rapide e dal modulo Bandi).
class CreateOppDialog extends StatefulWidget {
  const CreateOppDialog({
    super.key,
    required this.userId,
    required this.repository,
    required this.companies,
    this.preselectedCompanyId,
    this.initialTitle,
    this.initialBandoSource,
    this.initialDeadline,
  });
  final String userId;
  final ApiWorkspaceRepository repository;
  final List<Company> companies;
  final String? preselectedCompanyId;
  final String? initialTitle;
  final String? initialBandoSource;
  final DateTime? initialDeadline;

  @override
  State<CreateOppDialog> createState() => _CreateOppDialogState();
}

class _CreateOppDialogState extends State<CreateOppDialog> {
  final _titleCtrl = TextEditingController();
  final _bandoRefCtrl = TextEditingController();
  final _bandoSourceCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  final _valueCtrl = TextEditingController();
  final _rifOffertaCtrl = TextEditingController();
  final _contCommercialeCtrl = TextEditingController();
  final _daFaturareACtrl = TextEditingController();
  final _partnerCtrl = TextEditingController();
  String? _companyId;
  DateTime? _deadline;
  DateTime? _scadPresentazione;
  DateTime? _scadOperativa;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.companies.any((c) => c.id == widget.preselectedCompanyId)) {
      _companyId = widget.preselectedCompanyId;
    }
    if (widget.initialTitle != null) _titleCtrl.text = widget.initialTitle!;
    if (widget.initialBandoSource != null) {
      _bandoSourceCtrl.text = widget.initialBandoSource!;
    }
    _deadline = widget.initialDeadline;
  }

  @override
  void dispose() {
    for (final c in [
      _titleCtrl,
      _bandoRefCtrl,
      _bandoSourceCtrl,
      _notesCtrl,
      _valueCtrl,
      _rifOffertaCtrl,
      _contCommercialeCtrl,
      _daFaturareACtrl,
      _partnerCtrl,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_titleCtrl.text.trim().isEmpty || _companyId == null) {
      setState(() => _error = 'Titolo e cliente sono obbligatori.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final now = DateTime.now();
      await widget.repository.createOpportunity(
        widget.userId,
        Opportunity(
          id: '',
          companyId: _companyId!,
          title: _titleCtrl.text.trim(),
          status: OpportunityStatus.inAttesa,
          createdAt: now,
          createdByUserId: widget.userId,
          bandoReference: _bandoRefCtrl.text.trim(),
          bandoSource: _bandoSourceCtrl.text.trim(),
          bandoDeadline: _deadline,
          estimatedValue: double.tryParse(_valueCtrl.text.replaceAll(',', '.')),
          notes: _notesCtrl.text.trim(),
          rifOfferta: _rifOffertaCtrl.text.trim(),
          contattoCommerciale: _contCommercialeCtrl.text.trim(),
          daFaturareA: _daFaturareACtrl.text.trim(),
          partnerCommerciale: _partnerCtrl.text.trim(),
          scadenzaPresentazione: _scadPresentazione,
          scadenzaOperativa: _scadOperativa,
        ),
      );
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      setState(() {
        _error = e.toString();
        _saving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return NexoraDialog(
      title: 'Nuova opportunità',
      icon: Icons.rocket_launch_outlined,
      width: 620,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _titleCtrl,
            decoration: NexoraDialog.fieldDecoration(
              'Titolo opportunità / Bando *',
            ),
          ),
          const SizedBox(height: 14),
          DropdownButtonFormField<String>(
            value: _companyId,
            decoration: NexoraDialog.fieldDecoration('Cliente *'),
            items: widget.companies
                .map((c) => DropdownMenuItem(value: c.id, child: Text(c.name)))
                .toList(),
            onChanged: (v) => setState(() => _companyId = v),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _rifOffertaCtrl,
                  decoration: NexoraDialog.fieldDecoration(
                    'Rif. Offerta (es. 01.2025)',
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _contCommercialeCtrl,
                  decoration: NexoraDialog.fieldDecoration(
                    'Contatto commerciale',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _bandoSourceCtrl,
                  decoration: NexoraDialog.fieldDecoration(
                    'Ente / Portale bando',
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _bandoRefCtrl,
                  decoration: NexoraDialog.fieldDecoration(
                    'Codice / Riferimento bando',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _daFaturareACtrl,
                  decoration: NexoraDialog.fieldDecoration(
                    'Da fatturare a (es. Beneficiario)',
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _partnerCtrl,
                  decoration: NexoraDialog.fieldDecoration(
                    'Partner commerciale',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _valueCtrl,
                  decoration: NexoraDialog.fieldDecoration(
                    'Valore stimato (€)',
                    prefix: '€ ',
                  ),
                  keyboardType: TextInputType.number,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _DatePickerField(
                  label: 'Scadenza bando',
                  value: _deadline,
                  onPicked: (d) => setState(() => _deadline = d),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _DatePickerField(
                  label: 'Scadenza presentazione',
                  value: _scadPresentazione,
                  onPicked: (d) => setState(() => _scadPresentazione = d),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _DatePickerField(
                  label: 'Scadenza operativa',
                  value: _scadOperativa,
                  onPicked: (d) => setState(() => _scadOperativa = d),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _notesCtrl,
            decoration: NexoraDialog.fieldDecoration('Note'),
            maxLines: 3,
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(
              _error!,
              style: const TextStyle(color: GussoniBrand.error, fontSize: 12),
            ),
          ],
          const SizedBox(height: 4),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          style: NexoraDialog.cancelButtonStyle(),
          child: const Text('Annulla'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          style: NexoraDialog.primaryButtonStyle(),
          child: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text('Crea opportunità'),
        ),
      ],
    );
  }
}

// ── Widget riutilizzabili ──

class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.status});
  final OpportunityStatus status;
  @override
  Widget build(BuildContext context) => Container(
    width: 8,
    height: 8,
    decoration: BoxDecoration(shape: BoxShape.circle, color: _color),
  );

  Color get _color => switch (status) {
    OpportunityStatus.inAttesa => GussoniBrand.info,
    OpportunityStatus.preventivazione => GussoniBrand.gold,
    OpportunityStatus.accettata => GussoniBrand.success,
    OpportunityStatus.accettataSenzaFirma => GussoniBrand.success,
    OpportunityStatus.inAttesaRinnovoAutomatico => GussoniBrand.warning,
    OpportunityStatus.presaInCarico => GussoniBrand.primary,
    OpportunityStatus.persa => GussoniBrand.textDisabled,
  };
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});
  final OpportunityStatus status;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
    decoration: BoxDecoration(
      color: _bg,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: _border),
    ),
    child: Text(
      _label,
      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: _fg),
    ),
  );

  String get _label => switch (status) {
    OpportunityStatus.inAttesa => 'In attesa',
    OpportunityStatus.preventivazione => 'Preventivazione',
    OpportunityStatus.accettata => 'Accettata',
    OpportunityStatus.accettataSenzaFirma => 'Acc. senza firma',
    OpportunityStatus.inAttesaRinnovoAutomatico => 'Rinnovo automatico',
    OpportunityStatus.presaInCarico => 'Presa in carico',
    OpportunityStatus.persa => 'Persa',
  };
  Color get _fg => switch (status) {
    OpportunityStatus.inAttesa => GussoniBrand.info,
    OpportunityStatus.preventivazione => GussoniBrand.gold,
    OpportunityStatus.accettata => GussoniBrand.success,
    OpportunityStatus.accettataSenzaFirma => GussoniBrand.success,
    OpportunityStatus.inAttesaRinnovoAutomatico => GussoniBrand.warning,
    OpportunityStatus.presaInCarico => GussoniBrand.primary,
    OpportunityStatus.persa => GussoniBrand.textMuted,
  };
  Color get _bg => _fg.withOpacity(.08);
  Color get _border => _fg.withOpacity(.2);
}

class _DetailSection extends StatelessWidget {
  const _DetailSection({required this.title, required this.children});
  final String title;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: GussoniBrand.surface,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: GussoniBrand.border),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: GussoniBrand.textMuted,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 10),
        ...children,
      ],
    ),
  );
}

class _InfoRow extends StatelessWidget {
  const _InfoRow(this.label, this.value);
  final String label, value;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(
      children: [
        SizedBox(
          width: 120,
          child: Text(
            label,
            style: TextStyle(fontSize: 12, color: GussoniBrand.textMuted),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: GussoniBrand.textPrimary,
            ),
          ),
        ),
      ],
    ),
  );
}

class _ActionBtn extends StatelessWidget {
  const _ActionBtn({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: 8),
    child: OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 14),
      label: Text(label, style: const TextStyle(fontSize: 12)),
      style: OutlinedButton.styleFrom(
        foregroundColor: color,
        side: BorderSide(color: color.withOpacity(.5)),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
    ),
  );
}

class _PreventivoMiniCard extends StatelessWidget {
  const _PreventivoMiniCard({required this.quotation, required this.fmt});
  final Preventivo quotation;
  final NumberFormat fmt;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: GussoniBrand.surfaceSubtle,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: GussoniBrand.borderSubtle),
    ),
    child: Row(
      children: [
        Icon(
          Icons.request_quote_outlined,
          size: 16,
          color: GussoniBrand.primary,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Preventivo – €${fmt.format(quotation.total)}',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: GussoniBrand.textPrimary,
                ),
              ),
              Text(
                'Istruttoria: €${fmt.format(quotation.istruttoriaFee)}',
                style: TextStyle(fontSize: 11, color: GussoniBrand.textMuted),
              ),
            ],
          ),
        ),
        _QuotStatusChip(status: quotation.status),
      ],
    ),
  );
}

class _QuotStatusChip extends StatelessWidget {
  const _QuotStatusChip({required this.status});
  final PreventivoStatus status;
  @override
  Widget build(BuildContext context) {
    final label = switch (status) {
      PreventivoStatus.draft => 'Bozza',
      PreventivoStatus.sent => 'Inviato',
      PreventivoStatus.accepted => 'Accettato',
      PreventivoStatus.rejected => 'Rifiutato',
    };
    final color = switch (status) {
      PreventivoStatus.draft => GussoniBrand.textMuted,
      PreventivoStatus.sent => GussoniBrand.info,
      PreventivoStatus.accepted => GussoniBrand.success,
      PreventivoStatus.rejected => GussoniBrand.error,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(.3)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

class _DatePickerField extends StatelessWidget {
  const _DatePickerField({
    required this.label,
    required this.value,
    required this.onPicked,
  });
  final String label;
  final DateTime? value;
  final void Function(DateTime) onPicked;
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: () async {
      final picked = await showDatePicker(
        context: context,
        initialDate: value ?? DateTime.now().add(const Duration(days: 30)),
        firstDate: DateTime.now(),
        lastDate: DateTime.now().add(const Duration(days: 730)),
      );
      if (picked != null) onPicked(picked);
    },
    child: InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        suffixIcon: const Icon(Icons.calendar_today_outlined, size: 16),
      ),
      child: Text(
        value != null ? DateFormat('dd/MM/yyyy').format(value!) : '—',
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
