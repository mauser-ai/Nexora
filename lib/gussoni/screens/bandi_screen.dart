import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../brand_config.dart';
import '../../data/bando_repository.dart';
import '../../data/workspace_snapshot.dart';
import '../../models/bando_models.dart';
import '../../models/domain_models.dart';
import '../widgets/g_table.dart';

/// Modulo Bandi (Centro Studi): anagrafica bandi/incentivi con requisiti e
/// matching automatico sui clienti in anagrafica.
class BandiScreen extends StatefulWidget {
  const BandiScreen({
    super.key,
    required this.workspace,
    required this.scopeId,
    this.onCreateOpportunity,
    this.onOpenCompany,
  });

  final WorkspaceSnapshot workspace;

  /// Team id (o uid utente) sotto cui condividere l'anagrafica bandi.
  final String scopeId;
  final void Function(Company company, Bando bando)? onCreateOpportunity;
  final void Function(Company company)? onOpenCompany;

  @override
  State<BandiScreen> createState() => _BandiScreenState();
}

enum _BandoFilter { tutti, aperti, inScadenza, chiusi }

class _BandiScreenState extends State<BandiScreen> {
  final _repo = BandoRepository();

  final _date = DateFormat('dd/MM/yyyy');

  String _search = '';
  _BandoFilter _filter = _BandoFilter.aperti;
  ExternalBandoItem? _selected;
  List<ExternalBandoItem> _items = const [];
  bool _loading = false;
  String? _error;
  int _page = 0;
  int _nbPages = 0;
  int _nbHits = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadExternal());
  }

  @override
  void dispose() {
    _repo.dispose();
    super.dispose();
  }

  List<ExternalBandoItem> _applyFilters(List<ExternalBandoItem> all) {
    var list = all.toList();
    list = switch (_filter) {
      _BandoFilter.tutti => list,
      _BandoFilter.aperti => list.where((b) => !_isExpired(b)).toList(),
      _BandoFilter.inScadenza => list.where(_isExpiringSoon).toList(),
      _BandoFilter.chiusi => list.where(_isExpired).toList(),
    };
    return list;
  }

  ExternalBandoSearchRequest _request({int page = 0}) {
    return ExternalBandoSearchRequest(
      query: _search,
      page: page,
      hitsPerPage: 16,
      onlyOpen:
          _filter == _BandoFilter.aperti || _filter == _BandoFilter.inScadenza,
    );
  }

  Future<void> _loadExternal({int page = 0}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await _repo.searchExternal(_request(page: page));
      if (!mounted) return;
      setState(() {
        _items = result.items;
        _page = result.page;
        _nbPages = result.nbPages;
        _nbHits = result.nbHits;
        if (_items.isEmpty) {
          _selected = null;
        } else if (_selected != null &&
            !_items.any((item) => item.externalId == _selected!.externalId)) {
          _selected = null;
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _items = const [];
        _selected = null;
        _error = e.toString();
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  bool _isExpired(ExternalBandoItem item) {
    final deadline = item.scadenza;
    if (deadline == null) return false;
    return deadline.isBefore(DateTime.now());
  }

  bool _isExpiringSoon(ExternalBandoItem item) {
    final deadline = item.scadenza;
    if (deadline == null || _isExpired(item)) return false;
    final days = deadline.difference(DateTime.now()).inDays;
    return days <= 45;
  }

  // ─── UI helpers ─────────────────────────────────────────────────────────

  (String, Color) _scadenzaChip(ExternalBandoItem item) {
    if (item.scadenza == null) {
      return (
        item.scadenzaTesto.isEmpty ? 'A sportello' : item.scadenzaTesto,
        GussoniBrand.info,
      );
    }
    if (_isExpired(item)) return ('Scaduto', GussoniBrand.error);
    final giorni = item.scadenza!.difference(DateTime.now()).inDays;
    if (giorni <= 30) return ('$giorni gg', GussoniBrand.error);
    if (giorni <= 60) return ('$giorni gg', GussoniBrand.warning);
    return (_date.format(item.scadenza!), GussoniBrand.success);
  }

  String _shortList(List<String> values, {String fallback = '—'}) {
    if (values.isEmpty) return fallback;
    if (values.length <= 2) return values.join(', ');
    return '${values.take(2).join(', ')} +${values.length - 2}';
  }

  @override
  Widget build(BuildContext context) {
    final bandi = _applyFilters(_items);
    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < 760;
        final selected = _selected;
        final canPrev = !_loading && _page > 0;
        final canNext = !_loading && (_nbPages == 0 || _page + 1 < _nbPages);

        final table = GScreenLayout(
          title: 'Bandi',
          subtitle:
              'Bandi esterni consultabili dentro Nexora, con matching sui clienti',
          count: _nbHits,
          showHeader: !isMobile,
          searchHint: 'Cerca bando, ente, settore…',
          onSearch: (value) {
            _search = value.trim();
            _loadExternal();
          },
          action: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: 'Pagina precedente',
                onPressed: canPrev
                    ? () => _loadExternal(page: _page - 1)
                    : null,
                icon: const Icon(Icons.chevron_left_rounded, size: 20),
              ),
              Text(
                '${_page + 1}/${_nbPages == 0 ? 1 : _nbPages}',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: GussoniBrand.textMuted,
                ),
              ),
              IconButton(
                tooltip: 'Pagina successiva',
                onPressed: canNext
                    ? () => _loadExternal(page: _page + 1)
                    : null,
                icon: const Icon(Icons.chevron_right_rounded, size: 20),
              ),
              const SizedBox(width: 6),
              IconButton.filledTonal(
                tooltip: 'Aggiorna bandi',
                onPressed: _loading ? null : () => _loadExternal(page: _page),
                icon: _loading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.sync_rounded, size: 18),
              ),
            ],
          ),
          filters: GFilterPills<_BandoFilter>(
            items: const [
              _BandoFilter.tutti,
              _BandoFilter.aperti,
              _BandoFilter.inScadenza,
              _BandoFilter.chiusi,
            ],
            selected: _filter,
            onSelect: (filter) {
              setState(() => _filter = filter ?? _BandoFilter.tutti);
              _loadExternal();
            },
            labelOf: (filter) => switch (filter) {
              _BandoFilter.aperti => 'Aperti',
              _BandoFilter.inScadenza => 'In scadenza',
              _BandoFilter.chiusi => 'Scaduti',
              _ => 'Tutti',
            },
            countOf: (filter) => switch (filter) {
              _BandoFilter.aperti => _items.where((b) => !_isExpired(b)).length,
              _BandoFilter.inScadenza => _items.where(_isExpiringSoon).length,
              _BandoFilter.chiusi => _items.where(_isExpired).length,
              _ => _items.length,
            },
          ),
          body: Column(
            children: [
              if (_error != null)
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: GussoniBrand.error.withValues(alpha: .08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: GussoniBrand.error.withValues(alpha: .25),
                    ),
                  ),
                  child: Text(
                    _error!,
                    style: const TextStyle(
                      fontSize: 12,
                      color: GussoniBrand.error,
                      height: 1.35,
                    ),
                  ),
                ),
              Expanded(
                child: GTable<ExternalBandoItem>(
                  rows: bandi,
                  isLoading: _loading,
                  rowsPerPage: 16,
                  onRowTap: (bando) => setState(() => _selected = bando),
                  isSelected: (bando) =>
                      bando.externalId == _selected?.externalId,
                  emptyLabel: _error == null
                      ? 'Nessun bando trovato dalla fonte esterna.'
                      : 'La fonte esterna non ha restituito risultati.',
                  emptyIcon: Icons.travel_explore_rounded,
                  contextActionsForRow: (bando) => [
                    GContextMenuAction(
                      label: 'Apri dettaglio',
                      icon: Icons.auto_awesome_rounded,
                      onSelected: () => setState(() => _selected = bando),
                    ),
                    if (bando.link.isNotEmpty)
                      GContextMenuAction(
                        label: 'Apri fonte',
                        icon: Icons.open_in_new_rounded,
                        onSelected: () => launchUrl(
                          Uri.parse(bando.link),
                          webOnlyWindowName: '_blank',
                        ),
                      ),
                  ],
                  columns: [
                    GCol<ExternalBandoItem>(
                      label: 'Bando',
                      flex: 5,
                      cell: (bando) => Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            bando.titolo,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: GussoniBrand.textPrimary,
                            ),
                          ),
                          Text(
                            bando.ente.isEmpty ? bando.source : bando.ente,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11,
                              color: GussoniBrand.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    GCol<ExternalBandoItem>(
                      label: 'Territorio',
                      flex: 2,
                      cell: (bando) => GCellText(
                        _shortList(bando.regioni, fallback: 'Nazionale'),
                        muted: true,
                      ),
                    ),
                    GCol<ExternalBandoItem>(
                      label: 'Beneficiari',
                      flex: 2,
                      cell: (bando) =>
                          GCellText(_shortList(bando.beneficiari), muted: true),
                    ),
                    GCol<ExternalBandoItem>(
                      label: 'Scadenza',
                      flex: 2,
                      cell: (bando) {
                        final (label, color) = _scadenzaChip(bando);
                        return Align(
                          alignment: Alignment.centerLeft,
                          child: GStatusChip(label: label, color: color),
                        );
                      },
                    ),
                    GCol<ExternalBandoItem>(
                      label: 'Compatibili',
                      flex: 2,
                      cell: (bando) {
                        final matches = matchAllCompanies(
                          bando.toDraft(),
                          widget.workspace.companies,
                        );
                        final strong = matches
                            .where(
                              (m) => m.level == BandoMatchLevel.compatibile,
                            )
                            .length;
                        final partial = matches.length - strong;
                        if (matches.isEmpty) {
                          return const GCellText('—', muted: true);
                        }
                        return Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            GStatusChip(
                              label: '$strong',
                              color: GussoniBrand.success,
                              small: true,
                            ),
                            if (partial > 0) ...[
                              const SizedBox(width: 4),
                              GStatusChip(
                                label: '$partial ?',
                                color: GussoniBrand.warning,
                                small: true,
                              ),
                            ],
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        );

        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          child: selected == null
              ? KeyedSubtree(key: const ValueKey('bandi-list'), child: table)
              : KeyedSubtree(
                  key: ValueKey('bandi-detail-${selected.externalId}'),
                  child: _BandoDetailPage(
                    item: selected,
                    workspace: widget.workspace,
                    onBack: () => setState(() => _selected = null),
                    onCreateOpportunity: widget.onCreateOpportunity,
                    onOpenCompany: widget.onOpenCompany,
                  ),
                ),
        );
      },
    );
  }
}

// ─── Dettaglio bando esterno ────────────────────────────────────────────────

class _BandoDetailPage extends StatelessWidget {
  const _BandoDetailPage({
    required this.item,
    required this.workspace,
    required this.onBack,
    this.onCreateOpportunity,
    this.onOpenCompany,
  });

  final ExternalBandoItem item;
  final WorkspaceSnapshot workspace;
  final VoidCallback onBack;
  final void Function(Company company, Bando bando)? onCreateOpportunity;
  final void Function(Company company)? onOpenCompany;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 760;
        return Padding(
          padding: EdgeInsets.fromLTRB(
            compact ? 10 : 0,
            compact ? 8 : 0,
            compact ? 10 : 0,
            compact ? 10 : 0,
          ),
          child: Column(
            children: [
              Container(
                padding: EdgeInsets.symmetric(
                  horizontal: compact ? 10 : 14,
                  vertical: compact ? 8 : 10,
                ),
                decoration: GussoniBrand.glassPanel(radius: 16),
                child: Row(
                  children: [
                    IconButton.filledTonal(
                      tooltip: 'Torna ai bandi',
                      onPressed: onBack,
                      icon: const Icon(Icons.arrow_back_rounded, size: 18),
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Torna al listing',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: GussoniBrand.textPrimary,
                            ),
                          ),
                          Text(
                            'Dettaglio bando e matching clienti',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
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
              const SizedBox(height: 12),
              Expanded(
                child: _ExternalBandoDetail(
                  item: item,
                  workspace: workspace,
                  onClose: onBack,
                  onCreateOpportunity: onCreateOpportunity,
                  onOpenCompany: onOpenCompany,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ExternalBandoDetail extends StatelessWidget {
  const _ExternalBandoDetail({
    required this.item,
    required this.workspace,
    this.onClose,
    this.onCreateOpportunity,
    this.onOpenCompany,
  });

  final ExternalBandoItem item;
  final WorkspaceSnapshot workspace;
  final VoidCallback? onClose;
  final void Function(Company company, Bando bando)? onCreateOpportunity;
  final void Function(Company company)? onOpenCompany;

  @override
  Widget build(BuildContext context) {
    final draft = item.toDraft();
    final matches = matchAllCompanies(draft, workspace.companies);

    return GDetailPanel(
      title: item.titolo,
      subtitle: item.ente.isEmpty ? item.source : item.ente,
      onClose: onClose,
      icon: Icon(
        Icons.travel_explore_rounded,
        size: 18,
        color: GussoniBrand.primary,
      ),
      actions: [
        if (item.link.isNotEmpty)
          IconButton(
            tooltip: 'Apri fonte',
            onPressed: () =>
                launchUrl(Uri.parse(item.link), webOnlyWindowName: '_blank'),
            icon: const Icon(
              Icons.open_in_new_rounded,
              size: 16,
              color: GussoniBrand.info,
            ),
          ),
      ],
      children: [
        GDetailSection(
          title: 'Sintesi',
          children: [
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                GStatusChip(
                  label: item.source,
                  color: GussoniBrand.info,
                  small: true,
                ),
                if (item.scadenzaTesto.isNotEmpty)
                  GStatusChip(
                    label: item.scadenzaTesto,
                    color: GussoniBrand.warning,
                    small: true,
                  ),
                GStatusChip(
                  label: '${matches.length} clienti da valutare',
                  color: GussoniBrand.success,
                  small: true,
                ),
              ],
            ),
            if (item.descrizione.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                item.descrizione,
                style: const TextStyle(
                  fontSize: 12.5,
                  height: 1.45,
                  color: GussoniBrand.textSecondary,
                ),
              ),
            ],
          ],
        ),
        GDetailSection(
          title: 'Dati dalla fonte',
          children: [
            if (item.scadenzaTesto.isNotEmpty)
              _ReqRow('Scadenza', [item.scadenzaTesto]),
            _ReqRow(
              'Territorio',
              item.regioni.isEmpty ? ['Nazionale'] : item.regioni,
            ),
            if (item.beneficiari.isNotEmpty)
              _ReqRow('Beneficiari', item.beneficiari),
            if (item.settori.isNotEmpty) _ReqRow('Settori', item.settori),
            if (item.agevolazioni.isNotEmpty)
              _ReqRow('Agevolazioni', item.agevolazioni),
            if (item.speseFinanziate.isNotEmpty)
              _ReqRow('Spese', item.speseFinanziate),
          ],
        ),
        GDetailSection(
          title: 'Matching clienti (${matches.length})',
          children: [
            if (matches.isEmpty)
              const Text(
                'Nessun cliente risulta compatibile con i dati disponibili. '
                'Il matching migliora quando società e fonte hanno regione, '
                'ATECO, dimensione e aree investimento compilate.',
                style: TextStyle(
                  fontSize: 11.5,
                  color: GussoniBrand.textMuted,
                  height: 1.4,
                ),
              )
            else
              for (final match in matches)
                _MatchTile(
                  match: match,
                  bando: draft,
                  onCreateOpportunity: onCreateOpportunity,
                  onOpenCompany: onOpenCompany,
                ),
          ],
        ),
      ],
    );
  }
}

class _ReqRow extends StatelessWidget {
  const _ReqRow(this.label, this.values);
  final String label;
  final List<String> values;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 88,
            child: Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: GussoniBrand.textMuted,
                ),
              ),
            ),
          ),
          Expanded(
            child: Wrap(
              spacing: 5,
              runSpacing: 5,
              children: values
                  .map(
                    (v) => Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: GussoniBrand.surfaceSubtle,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        v,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: GussoniBrand.textSecondary,
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }
}

class _MatchTile extends StatelessWidget {
  const _MatchTile({
    required this.match,
    required this.bando,
    this.onCreateOpportunity,
    this.onOpenCompany,
  });

  final BandoMatch match;
  final Bando bando;
  final void Function(Company, Bando)? onCreateOpportunity;
  final void Function(Company)? onOpenCompany;

  Color get _levelColor => switch (match.level) {
    BandoMatchLevel.compatibile => GussoniBrand.success,
    BandoMatchLevel.parziale => GussoniBrand.warning,
    BandoMatchLevel.escluso => GussoniBrand.error,
  };

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: GussoniBrand.scaffoldBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: GussoniBrand.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: onOpenCompany == null
                      ? null
                      : () => onOpenCompany!(match.company),
                  child: Text(
                    match.company.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: GussoniBrand.textPrimary,
                    ),
                  ),
                ),
              ),
              GStatusChip(
                label: match.level.label,
                color: _levelColor,
                small: true,
              ),
            ],
          ),
          if (match.criteri.isNotEmpty) ...[
            const SizedBox(height: 6),
            Wrap(
              spacing: 5,
              runSpacing: 4,
              children: match.criteri
                  .map(
                    (c) => Tooltip(
                      message: c.dettaglio.isEmpty ? c.label : c.dettaglio,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            switch (c.outcome) {
                              MatchOutcome.ok => Icons.check_circle_rounded,
                              MatchOutcome.ko => Icons.cancel_rounded,
                              MatchOutcome.unknown =>
                                Icons.help_outline_rounded,
                            },
                            size: 12,
                            color: switch (c.outcome) {
                              MatchOutcome.ok => GussoniBrand.success,
                              MatchOutcome.ko => GussoniBrand.error,
                              MatchOutcome.unknown => GussoniBrand.warning,
                            },
                          ),
                          const SizedBox(width: 3),
                          Text(
                            c.label,
                            style: const TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w600,
                              color: GussoniBrand.textSecondary,
                            ),
                          ),
                          const SizedBox(width: 6),
                        ],
                      ),
                    ),
                  )
                  .toList(),
            ),
          ],
          if (onCreateOpportunity != null) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: OutlinedButton.icon(
                onPressed: () => onCreateOpportunity!(match.company, bando),
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                ),
                icon: const Icon(Icons.trending_up_rounded, size: 14),
                label: const Text(
                  'Crea opportunità',
                  style: TextStyle(fontSize: 11.5),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
