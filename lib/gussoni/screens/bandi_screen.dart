import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/nexora_dialog.dart';
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

  @override
  void dispose() {
    _repo.dispose();
    super.dispose();
  }

  final _euro = NumberFormat('#,##0', 'it_IT');
  final _date = DateFormat('dd/MM/yyyy');

  String _search = '';
  _BandoFilter _filter = _BandoFilter.tutti;
  String? _selectedId;

  List<Bando> _applyFilters(List<Bando> all) {
    var list = all;
    list = switch (_filter) {
      _BandoFilter.tutti => list,
      _BandoFilter.aperti =>
        list.where((b) => b.stato == BandoStato.aperto && !b.scaduto).toList(),
      _BandoFilter.inScadenza => list.where((b) => b.inScadenza).toList(),
      _BandoFilter.chiusi =>
        list.where((b) => b.stato != BandoStato.aperto || b.scaduto).toList(),
    };
    if (_search.isNotEmpty) {
      final q = _search.toLowerCase();
      list = list
          .where(
            (b) =>
                b.titolo.toLowerCase().contains(q) ||
                b.ente.toLowerCase().contains(q) ||
                b.descrizione.toLowerCase().contains(q),
          )
          .toList();
    }
    return list;
  }

  Future<void> _openEditor({Bando? bando}) async {
    final saved = await showDialog<Bando>(
      context: context,
      builder: (_) => _BandoDialog(bando: bando, existingAree: _knownAree()),
    );
    if (saved == null) return;
    final id = await _repo.save(widget.scopeId, saved);
    if (mounted) setState(() => _selectedId = id);
  }

  /// Categorie investimento già censite sui clienti (suggerimenti dialog).
  List<String> _knownAree() {
    final set = <String>{};
    for (final c in widget.workspace.companies) {
      for (final a in c.areeInvestimento) {
        if (a.categoria.trim().isNotEmpty) set.add(a.categoria.trim());
      }
    }
    final list = set.toList()..sort();
    return list;
  }

  Future<void> _delete(Bando bando) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => NexoraConfirmDialog(
        title: 'Eliminare il bando?',
        message:
            '"${bando.titolo}" verrà rimosso dall\'anagrafica del Centro Studi.',
        isDanger: true,
        confirmLabel: 'Elimina',
      ),
    );
    if (ok == true) {
      await _repo.delete(widget.scopeId, bando.id);
      if (mounted && _selectedId == bando.id) {
        setState(() => _selectedId = null);
      }
    }
  }

  Uri _contributiEuropaUrl({
    String query = '',
    Company? company,
    bool onlyOpen = true,
  }) {
    final params = <String, String>{};
    final tokens = <String>[
      query.trim(),
      if (company != null) ...[
        company.atecoPrimario,
        ...company.areeInvestimento.map((a) => a.categoria),
      ],
    ].where((v) => v.trim().isNotEmpty).toList();
    if (tokens.isNotEmpty) {
      params['q'] = tokens.join(' ');
    }

    if (company != null) {
      if (company.regione.trim().isNotEmpty) {
        params['taxonomies_hierarchical_area_geografica'] = company.regione
            .trim();
      }
      final beneficiari = _beneficiariFor(company);
      if (beneficiari.isNotEmpty) {
        params['taxonomies_beneficiari'] = beneficiari.join('|');
      }
    }

    if (onlyOpen) {
      params['scadenza_testo'] = 'Bandi aperti';
    }

    return Uri.https(
      'www.contributieuropa.com',
      '/tuttibandi/',
      params.isEmpty ? null : params,
    );
  }

  List<String> _beneficiariFor(Company company) {
    final values = <String>{};
    switch (company.companyType) {
      case CompanyType.profit:
        final size = company.dimensioneImpresa;
        if (size == CompanySize.grande) {
          values.add('Grande Impresa');
        } else {
          values.addAll(['PMI', 'Micro impresa']);
        }
        break;
      case CompanyType.nonProfit:
        values.add(
          'Associazione-Ente Non profit/Terzo settore/Impresa e Cooperativa sociale',
        );
        break;
      case CompanyType.pa:
        values.add('Ente pubblico');
        break;
      case CompanyType.pf:
        values.add('Persona fisica/Aspirante imprenditore');
        values.add('Libero professionista');
        break;
    }
    return values.toList();
  }

  Future<void> _openExternalSearch() async {
    final uri = await showDialog<Uri>(
      context: context,
      builder: (_) => _ExternalBandiSearchDialog(
        companies: widget.workspace.companies,
        initialQuery: _search,
        buildUrl: _contributiEuropaUrl,
      ),
    );
    if (uri == null) return;
    await launchUrl(uri, webOnlyWindowName: '_blank');
  }

  // ─── UI helpers ─────────────────────────────────────────────────────────

  (String, Color) _scadenzaChip(Bando b) {
    if (b.stato != BandoStato.aperto) {
      return (b.stato.label, GussoniBrand.textMuted);
    }
    if (b.scadenza == null) return ('A sportello', GussoniBrand.info);
    if (b.scaduto) return ('Scaduto', GussoniBrand.error);
    final giorni = b.scadenza!.difference(DateTime.now()).inDays;
    if (giorni <= 30) return ('$giorni gg', GussoniBrand.error);
    if (giorni <= 60) return ('$giorni gg', GussoniBrand.warning);
    return (_date.format(b.scadenza!), GussoniBrand.success);
  }

  String _contributoLabel(Bando b) {
    final parts = <String>[];
    if (b.percentualeContributo != null) {
      parts.add('${b.percentualeContributo!.toStringAsFixed(0)}%');
    }
    if (b.importoMax != null) {
      parts.add('max € ${_euro.format(b.importoMax)}');
    }
    return parts.isEmpty ? '—' : parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Bando>>(
      stream: _repo.watchBandi(widget.scopeId),
      builder: (context, snapshot) {
        final all = snapshot.data ?? const <Bando>[];
        final bandi = _applyFilters(all);
        final selected = all.where((b) => b.id == _selectedId).firstOrNull;

        return LayoutBuilder(
          builder: (context, constraints) {
            final isMobile = constraints.maxWidth < 760;

            final table = GScreenLayout(
              title: 'Bandi',
              subtitle:
                  'Centro Studi: opportunità di finanziamento e matching clienti',
              count: all.length,
              showHeader: !isMobile,
              searchHint: 'Cerca bando o ente…',
              onSearch: (v) => setState(() => _search = v.trim()),
              action: Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.end,
                children: [
                  OutlinedButton.icon(
                    onPressed: _openExternalSearch,
                    icon: const Icon(Icons.travel_explore_rounded, size: 16),
                    label: const Text('Cerca bandi'),
                  ),
                  FilledButton.icon(
                    onPressed: () => _openEditor(),
                    icon: const Icon(Icons.add_rounded, size: 16),
                    label: const Text('Nuovo bando'),
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
                onSelect: (f) =>
                    setState(() => _filter = f ?? _BandoFilter.tutti),
                labelOf: (f) => switch (f) {
                  _BandoFilter.aperti => 'Aperti',
                  _BandoFilter.inScadenza => 'In scadenza',
                  _BandoFilter.chiusi => 'Chiusi',
                  _ => 'Tutti',
                },
                countOf: (f) => switch (f) {
                  _BandoFilter.aperti =>
                    all
                        .where(
                          (b) => b.stato == BandoStato.aperto && !b.scaduto,
                        )
                        .length,
                  _BandoFilter.inScadenza =>
                    all.where((b) => b.inScadenza).length,
                  _ => 0,
                },
              ),
              body: GTable<Bando>(
                rows: bandi,
                isLoading: snapshot.connectionState == ConnectionState.waiting,
                onRowTap: (b) => setState(() => _selectedId = b.id),
                isSelected: (b) => b.id == _selectedId,
                emptyLabel: all.isEmpty
                    ? 'Nessun bando in anagrafica.\nInserisci il primo bando dal Centro Studi.'
                    : 'Nessun bando corrisponde ai filtri.',
                emptyIcon: Icons.travel_explore_rounded,
                contextActionsForRow: (b) => [
                  GContextMenuAction(
                    label: 'Apri dettaglio',
                    icon: Icons.open_in_new_rounded,
                    onSelected: () => setState(() => _selectedId = b.id),
                  ),
                  GContextMenuAction(
                    label: 'Modifica',
                    icon: Icons.edit_outlined,
                    onSelected: () => _openEditor(bando: b),
                  ),
                  GContextMenuAction(
                    label: 'Elimina',
                    icon: Icons.delete_outline_rounded,
                    destructive: true,
                    onSelected: () => _delete(b),
                  ),
                ],
                columns: [
                  GCol<Bando>(
                    label: 'Bando',
                    flex: 4,
                    cell: (b) => Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          b.titolo,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: GussoniBrand.textPrimary,
                          ),
                        ),
                        if (b.ente.isNotEmpty)
                          Text(
                            b.ente,
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
                  GCol<Bando>(
                    label: 'Territorio',
                    flex: 2,
                    cell: (b) => GCellText(
                      b.regioni.isEmpty
                          ? 'Nazionale'
                          : b.regioni.length <= 2
                          ? b.regioni.join(', ')
                          : '${b.regioni.take(2).join(', ')} +${b.regioni.length - 2}',
                      muted: true,
                    ),
                  ),
                  GCol<Bando>(
                    label: 'Contributo',
                    flex: 2,
                    cell: (b) => GCellText(_contributoLabel(b)),
                  ),
                  GCol<Bando>(
                    label: 'Scadenza',
                    flex: 2,
                    cell: (b) {
                      final (label, color) = _scadenzaChip(b);
                      return Align(
                        alignment: Alignment.centerLeft,
                        child: GStatusChip(label: label, color: color),
                      );
                    },
                  ),
                  GCol<Bando>(
                    label: 'Compatibili',
                    flex: 2,
                    cell: (b) {
                      final matches = matchAllCompanies(
                        b,
                        widget.workspace.companies,
                      );
                      final pieni = matches
                          .where((m) => m.level == BandoMatchLevel.compatibile)
                          .length;
                      final parziali = matches.length - pieni;
                      if (matches.isEmpty) {
                        return const GCellText('—', muted: true);
                      }
                      return Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          GStatusChip(
                            label: '$pieni',
                            color: GussoniBrand.success,
                            small: true,
                          ),
                          if (parziali > 0) ...[
                            const SizedBox(width: 4),
                            GStatusChip(
                              label: '$parziali ?',
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
            );

            final detail = selected == null
                ? null
                : _BandoDetail(
                    bando: selected,
                    workspace: widget.workspace,
                    euro: _euro,
                    date: _date,
                    onClose: () => setState(() => _selectedId = null),
                    onEdit: () => _openEditor(bando: selected),
                    onCreateOpportunity: widget.onCreateOpportunity,
                    onOpenCompany: widget.onOpenCompany,
                  );

            if (isMobile) {
              return GMobileNavWrapper(
                showDetail: detail != null,
                list: table,
                detail: detail == null
                    ? const SizedBox.shrink()
                    : Column(
                        children: [
                          GMobileBackBar(
                            backLabel: 'Bandi',
                            title: selected!.titolo,
                            onBack: () => setState(() => _selectedId = null),
                          ),
                          Expanded(child: detail),
                        ],
                      ),
              );
            }

            return Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(flex: 3, child: table),
                if (detail != null) ...[
                  const SizedBox(width: 14),
                  SizedBox(width: 420, child: detail),
                ],
              ],
            );
          },
        );
      },
    );
  }
}

// ─── Ricerca esterna bandi ──────────────────────────────────────────────────

class _ExternalBandiSearchDialog extends StatefulWidget {
  const _ExternalBandiSearchDialog({
    required this.companies,
    required this.buildUrl,
    this.initialQuery = '',
  });

  final List<Company> companies;
  final String initialQuery;
  final Uri Function({String query, Company? company, bool onlyOpen}) buildUrl;

  @override
  State<_ExternalBandiSearchDialog> createState() =>
      _ExternalBandiSearchDialogState();
}

class _ExternalBandiSearchDialogState
    extends State<_ExternalBandiSearchDialog> {
  late final TextEditingController _query = TextEditingController(
    text: widget.initialQuery,
  );
  String? _companyId;
  bool _onlyOpen = true;

  Company? get _company =>
      widget.companies.where((company) => company.id == _companyId).firstOrNull;

  Uri get _url => widget.buildUrl(
    query: _query.text.trim(),
    company: _company,
    onlyOpen: _onlyOpen,
  );

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  List<String> _summary(Company? company) {
    if (company == null) {
      return ['Ricerca testuale libera', if (_onlyOpen) 'Solo bandi aperti'];
    }
    return [
      if (company.regione.trim().isNotEmpty) 'Regione: ${company.regione}',
      'Beneficiario: ${company.companyType.label}',
      if (company.dimensioneImpresa != null)
        'Dimensione: ${company.dimensioneImpresa!.label}',
      if (company.atecoPrimario.trim().isNotEmpty)
        'ATECO: ${company.atecoPrimario}',
      if (company.areeInvestimento.isNotEmpty)
        'Investimenti: ${company.areeInvestimento.map((a) => a.categoria).take(3).join(', ')}',
      if (_onlyOpen) 'Solo bandi aperti',
    ];
  }

  @override
  Widget build(BuildContext context) {
    final company = _company;
    final summary = _summary(company);

    return NexoraDialog(
      title: 'Ricerca bandi',
      icon: Icons.travel_explore_rounded,
      width: 620,
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          style: NexoraDialog.cancelButtonStyle(),
          child: const Text('Annulla'),
        ),
        FilledButton.icon(
          onPressed: () => Navigator.of(context).pop(_url),
          style: NexoraDialog.primaryButtonStyle(),
          icon: const Icon(Icons.open_in_new_rounded, size: 16),
          label: const Text('Apri ricerca'),
        ),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Apri Contributi Europa con i filtri già costruiti da Nexora. '
            'Quando trovi un bando interessante, salvalo qui come nuovo bando '
            'e il matching clienti resta gestito dal tuo CRM.',
            style: TextStyle(
              fontSize: 12.5,
              height: 1.45,
              color: GussoniBrand.textSecondary,
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _query,
            onChanged: (_) => setState(() {}),
            decoration: NexoraDialog.fieldDecoration(
              'Parole chiave',
              hint: 'es. digitalizzazione, macchinari, export',
            ),
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String?>(
            initialValue: _companyId,
            decoration: NexoraDialog.fieldDecoration(
              'Matching da cliente',
              hint:
                  'Scegli una società per prefiltrare territorio e beneficiario',
            ),
            items: [
              const DropdownMenuItem<String?>(
                value: null,
                child: Text('Nessun cliente specifico'),
              ),
              ...widget.companies.map(
                (company) => DropdownMenuItem<String?>(
                  value: company.id,
                  child: Text(
                    company.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
            onChanged: (value) => setState(() => _companyId = value),
          ),
          const SizedBox(height: 10),
          SwitchListTile.adaptive(
            value: _onlyOpen,
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: const Text(
              'Mostra solo bandi aperti',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: GussoniBrand.textPrimary,
              ),
            ),
            subtitle: const Text(
              'Usa il filtro pubblico “Bandi aperti” della ricerca esterna.',
              style: TextStyle(fontSize: 11, color: GussoniBrand.textMuted),
            ),
            onChanged: (value) => setState(() => _onlyOpen = value),
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: GussoniBrand.surfaceSubtle,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: GussoniBrand.borderSubtle),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Filtri generati',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: GussoniBrand.textMuted,
                    letterSpacing: .6,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: summary
                      .map(
                        (item) => GStatusChip(
                          label: item,
                          color: GussoniBrand.info,
                          small: true,
                        ),
                      )
                      .toList(),
                ),
                const SizedBox(height: 10),
                SelectableText(
                  _url.toString(),
                  style: const TextStyle(
                    fontSize: 10.5,
                    height: 1.35,
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
}

// ─── Dettaglio bando ─────────────────────────────────────────────────────────

class _BandoDetail extends StatelessWidget {
  const _BandoDetail({
    required this.bando,
    required this.workspace,
    required this.euro,
    required this.date,
    this.onClose,
    this.onEdit,
    this.onCreateOpportunity,
    this.onOpenCompany,
  });

  final Bando bando;
  final WorkspaceSnapshot workspace;
  final NumberFormat euro;
  final DateFormat date;
  final VoidCallback? onClose;
  final VoidCallback? onEdit;
  final void Function(Company, Bando)? onCreateOpportunity;
  final void Function(Company)? onOpenCompany;

  @override
  Widget build(BuildContext context) {
    final matches = matchAllCompanies(bando, workspace.companies);

    return GDetailPanel(
      title: bando.titolo,
      subtitle: bando.ente,
      icon: Icon(
        Icons.travel_explore_rounded,
        size: 18,
        color: GussoniBrand.primary,
      ),
      onClose: onClose,
      actions: [
        if (bando.link.isNotEmpty)
          IconButton(
            tooltip: 'Apri pagina del bando',
            onPressed: () =>
                launchUrl(Uri.parse(bando.link), webOnlyWindowName: '_blank'),
            icon: const Icon(
              Icons.open_in_new_rounded,
              size: 16,
              color: GussoniBrand.info,
            ),
          ),
        if (onEdit != null)
          IconButton(
            tooltip: 'Modifica bando',
            onPressed: onEdit,
            icon: const Icon(
              Icons.edit_outlined,
              size: 16,
              color: GussoniBrand.textMuted,
            ),
          ),
      ],
      children: [
        if (bando.descrizione.isNotEmpty)
          GDetailSection(
            title: 'Sintesi',
            children: [
              Text(
                bando.descrizione,
                style: const TextStyle(
                  fontSize: 12.5,
                  height: 1.45,
                  color: GussoniBrand.textSecondary,
                ),
              ),
            ],
          ),
        GDetailSection(
          title: 'Bando',
          children: [
            GInfoRow('Stato', bando.stato.label),
            if (bando.apertura != null)
              GInfoRow('Apertura', date.format(bando.apertura!)),
            GInfoRow(
              'Scadenza',
              bando.scadenza == null
                  ? 'A sportello'
                  : date.format(bando.scadenza!),
              valueColor: bando.inScadenza || bando.scaduto
                  ? GussoniBrand.error
                  : null,
            ),
            if (bando.percentualeContributo != null)
              GInfoRow(
                'Contributo',
                '${bando.percentualeContributo!.toStringAsFixed(0)}% a fondo perduto',
              ),
            if (bando.importoMin != null || bando.importoMax != null)
              GInfoRow(
                'Importo progetto',
                [
                  if (bando.importoMin != null)
                    'da € ${euro.format(bando.importoMin)}',
                  if (bando.importoMax != null)
                    'fino a € ${euro.format(bando.importoMax)}',
                ].join(' '),
              ),
            if (bando.dotazione != null)
              GInfoRow('Dotazione', '€ ${euro.format(bando.dotazione)}'),
            if (bando.note.isNotEmpty) GInfoRow('Note', bando.note),
          ],
        ),
        GDetailSection(
          title: 'Requisiti',
          children: [
            _ReqRow(
              'Territorio',
              bando.regioni.isEmpty ? ['Nazionale'] : bando.regioni,
            ),
            _ReqRow(
              'ATECO',
              bando.codiciAteco.isEmpty ? ['Tutti'] : bando.codiciAteco,
            ),
            _ReqRow(
              'Dimensione',
              bando.dimensioni.isEmpty
                  ? ['Tutte']
                  : bando.dimensioni.map((d) => d.label).toList(),
            ),
            _ReqRow(
              'Tipologia',
              bando.tipi.isEmpty
                  ? ['Tutte']
                  : bando.tipi.map((t) => t.label).toList(),
            ),
            if (bando.areeInvestimento.isNotEmpty)
              _ReqRow('Investimenti', bando.areeInvestimento),
          ],
        ),
        GDetailSection(
          title: 'Clienti compatibili (${matches.length})',
          children: [
            if (matches.isEmpty)
              const Text(
                'Nessun cliente in anagrafica soddisfa i requisiti. '
                'Completa i dati delle società (ATECO, regione, dimensione) '
                'per migliorare il matching.',
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
                  bando: bando,
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

// ─── Dialog crea/modifica bando ──────────────────────────────────────────────

class _BandoDialog extends StatefulWidget {
  const _BandoDialog({this.bando, this.existingAree = const []});
  final Bando? bando;
  final List<String> existingAree;

  @override
  State<_BandoDialog> createState() => _BandoDialogState();
}

class _BandoDialogState extends State<_BandoDialog> {
  late final _titolo = TextEditingController(text: widget.bando?.titolo ?? '');
  late final _ente = TextEditingController(text: widget.bando?.ente ?? '');
  late final _descrizione = TextEditingController(
    text: widget.bando?.descrizione ?? '',
  );
  late final _link = TextEditingController(text: widget.bando?.link ?? '');
  late final _note = TextEditingController(text: widget.bando?.note ?? '');
  late final _ateco = TextEditingController(
    text: widget.bando?.codiciAteco.join(', ') ?? '',
  );
  late final _percentuale = TextEditingController(
    text: widget.bando?.percentualeContributo?.toStringAsFixed(0) ?? '',
  );
  late final _importoMin = TextEditingController(
    text: widget.bando?.importoMin?.toStringAsFixed(0) ?? '',
  );
  late final _importoMax = TextEditingController(
    text: widget.bando?.importoMax?.toStringAsFixed(0) ?? '',
  );
  late final _dotazione = TextEditingController(
    text: widget.bando?.dotazione?.toStringAsFixed(0) ?? '',
  );

  late BandoStato _stato = widget.bando?.stato ?? BandoStato.aperto;
  late DateTime? _apertura = widget.bando?.apertura;
  late DateTime? _scadenza = widget.bando?.scadenza;
  late final Set<String> _regioni = {...?widget.bando?.regioni};
  late final Set<CompanySize> _dimensioni = {...?widget.bando?.dimensioni};
  late final Set<CompanyType> _tipi = {...?widget.bando?.tipi};
  late final Set<String> _aree = {...?widget.bando?.areeInvestimento};

  String? _error;
  final _dateFmt = DateFormat('dd/MM/yyyy');

  @override
  void dispose() {
    for (final c in [
      _titolo,
      _ente,
      _descrizione,
      _link,
      _note,
      _ateco,
      _percentuale,
      _importoMin,
      _importoMax,
      _dotazione,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  double? _num(TextEditingController c) =>
      double.tryParse(c.text.replaceAll('.', '').replaceAll(',', '.'));

  void _submit() {
    if (_titolo.text.trim().isEmpty) {
      setState(() => _error = 'Inserisci il titolo del bando.');
      return;
    }
    final bando = Bando(
      id: widget.bando?.id ?? '',
      titolo: _titolo.text.trim(),
      ente: _ente.text.trim(),
      descrizione: _descrizione.text.trim(),
      link: _link.text.trim(),
      note: _note.text.trim(),
      stato: _stato,
      apertura: _apertura,
      scadenza: _scadenza,
      dotazione: _num(_dotazione),
      percentualeContributo: _num(_percentuale),
      importoMin: _num(_importoMin),
      importoMax: _num(_importoMax),
      regioni: _regioni.toList()..sort(),
      codiciAteco: _ateco.text
          .split(RegExp(r'[,;]'))
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList(),
      dimensioni: CompanySize.values.where(_dimensioni.contains).toList(),
      tipi: CompanyType.values.where(_tipi.contains).toList(),
      areeInvestimento: _aree.toList()..sort(),
      createdAt: widget.bando?.createdAt,
    );
    Navigator.of(context).pop(bando);
  }

  Future<void> _pickDate(bool isApertura) async {
    final initial = (isApertura ? _apertura : _scadenza) ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() {
        if (isApertura) {
          _apertura = picked;
        } else {
          _scadenza = picked;
        }
      });
    }
  }

  Widget _chips<T>({
    required List<T> all,
    required Set<T> selected,
    required String Function(T) labelOf,
    required void Function(T, bool) onToggle,
  }) => Wrap(
    spacing: 6,
    runSpacing: 6,
    children: all
        .map(
          (item) => FilterChip(
            label: Text(labelOf(item), style: const TextStyle(fontSize: 11.5)),
            selected: selected.contains(item),
            visualDensity: VisualDensity.compact,
            onSelected: (v) => setState(() => onToggle(item, v)),
          ),
        )
        .toList(),
  );

  Widget _sectionLabel(String label, {String? hint}) => Padding(
    padding: const EdgeInsets.only(top: 14, bottom: 6),
    child: Row(
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            color: GussoniBrand.textMuted,
            letterSpacing: .6,
          ),
        ),
        if (hint != null) ...[
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              hint,
              style: const TextStyle(
                fontSize: 10.5,
                color: GussoniBrand.textMuted,
              ),
            ),
          ),
        ],
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    return NexoraDialog(
      title: widget.bando == null ? 'Nuovo bando' : 'Modifica bando',
      icon: Icons.travel_explore_rounded,
      width: 640,
      // ignore: sort_child_properties_last
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _titolo,
            decoration: NexoraDialog.fieldDecoration('Titolo bando *'),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _ente,
                  decoration: NexoraDialog.fieldDecoration(
                    'Ente erogatore',
                    hint: 'es. Regione Lombardia, MIMIT, Invitalia',
                  ),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 170,
                child: DropdownButtonFormField<BandoStato>(
                  initialValue: _stato,
                  decoration: NexoraDialog.fieldDecoration('Stato'),
                  items: BandoStato.values
                      .map(
                        (s) => DropdownMenuItem(value: s, child: Text(s.label)),
                      )
                      .toList(),
                  onChanged: (v) =>
                      setState(() => _stato = v ?? BandoStato.aperto),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _descrizione,
            maxLines: 3,
            decoration: NexoraDialog.fieldDecoration('Sintesi / descrizione'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _link,
            decoration: NexoraDialog.fieldDecoration(
              'Link al bando',
              hint: 'https://…',
            ),
          ),

          _sectionLabel('SCADENZE E CONTRIBUTO'),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _pickDate(true),
                  icon: const Icon(Icons.calendar_today_outlined, size: 14),
                  label: Text(
                    _apertura == null
                        ? 'Apertura'
                        : 'Apre ${_dateFmt.format(_apertura!)}',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _pickDate(false),
                  icon: const Icon(Icons.event_outlined, size: 14),
                  label: Text(
                    _scadenza == null
                        ? 'Scadenza (a sportello)'
                        : 'Scade ${_dateFmt.format(_scadenza!)}',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ),
              if (_scadenza != null)
                IconButton(
                  tooltip: 'Rimuovi scadenza',
                  onPressed: () => setState(() => _scadenza = null),
                  icon: const Icon(Icons.close, size: 15),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _percentuale,
                  keyboardType: TextInputType.number,
                  decoration: NexoraDialog.fieldDecoration(
                    'Contributo %',
                    suffix: '%',
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _importoMin,
                  keyboardType: TextInputType.number,
                  decoration: NexoraDialog.fieldDecoration(
                    'Importo min',
                    prefix: '€ ',
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _importoMax,
                  keyboardType: TextInputType.number,
                  decoration: NexoraDialog.fieldDecoration(
                    'Importo max',
                    prefix: '€ ',
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _dotazione,
                  keyboardType: TextInputType.number,
                  decoration: NexoraDialog.fieldDecoration(
                    'Dotazione',
                    prefix: '€ ',
                  ),
                ),
              ),
            ],
          ),

          _sectionLabel(
            'REQUISITI',
            hint: 'lascia vuoto un gruppo per non porre vincoli',
          ),
          _sectionLabel('Territorio'),
          _chips<String>(
            all: kRegioniItaliane,
            selected: _regioni,
            labelOf: (r) => r,
            onToggle: (r, v) => v ? _regioni.add(r) : _regioni.remove(r),
          ),
          _sectionLabel('Dimensione impresa'),
          _chips<CompanySize>(
            all: CompanySize.values,
            selected: _dimensioni,
            labelOf: (d) => d.label,
            onToggle: (d, v) => v ? _dimensioni.add(d) : _dimensioni.remove(d),
          ),
          _sectionLabel('Tipologia beneficiario'),
          _chips<CompanyType>(
            all: CompanyType.values,
            selected: _tipi,
            labelOf: (t) => t.label,
            onToggle: (t, v) => v ? _tipi.add(t) : _tipi.remove(t),
          ),
          _sectionLabel('Codici ATECO ammessi'),
          TextField(
            controller: _ateco,
            decoration: NexoraDialog.fieldDecoration(
              'Codici o prefissi separati da virgola',
              hint: 'es. 62, 63.1, 25.62 (vuoto = tutti)',
            ),
          ),
          if (widget.existingAree.isNotEmpty) ...[
            _sectionLabel(
              'Aree di investimento',
              hint: 'categorie già censite sui clienti',
            ),
            _chips<String>(
              all: widget.existingAree,
              selected: _aree,
              labelOf: (a) => a,
              onToggle: (a, v) => v ? _aree.add(a) : _aree.remove(a),
            ),
          ],

          const SizedBox(height: 12),
          TextField(
            controller: _note,
            maxLines: 2,
            decoration: NexoraDialog.fieldDecoration('Note interne'),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                _error!,
                style: const TextStyle(color: GussoniBrand.error, fontSize: 12),
              ),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          style: NexoraDialog.cancelButtonStyle(),
          child: const Text('Annulla'),
        ),
        FilledButton(
          onPressed: _submit,
          style: NexoraDialog.primaryButtonStyle(),
          child: Text(widget.bando == null ? 'Crea bando' : 'Salva'),
        ),
      ],
    );
  }
}
