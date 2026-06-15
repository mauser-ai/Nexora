import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../brand_config.dart';
import '../../data/api_workspace_repository.dart';
import '../../models/domain_models.dart';

// ─── Panoramica CRM ───────────────────────────────────────────────────────────
// Schermata landing che mostra tutti i listing principali in sezioni compatte.

class PanoramicaScreen extends StatelessWidget {
  const PanoramicaScreen({
    super.key,
    required this.workspace,
    required this.userId,
    required this.repository,
    required this.onGoToSocieta,
    required this.onGoToContatti,
    required this.onGoToOpportunita,
    required this.onGoToPreventivi,
    required this.onGoToProgetti,
    required this.onOpenCompany,
    required this.onOpenOpportunity,
    required this.onOpenProject,
  });

  final WorkspaceSnapshot workspace;
  final String userId;
  final ApiWorkspaceRepository repository;

  // navigazione alle sezioni complete
  final VoidCallback onGoToSocieta;
  final VoidCallback onGoToContatti;
  final VoidCallback onGoToOpportunita;
  final VoidCallback onGoToPreventivi;
  final VoidCallback onGoToProgetti;

  // navigazione al dettaglio singolo
  final void Function(Company) onOpenCompany;
  final void Function(Opportunity) onOpenOpportunity;
  final void Function(Project) onOpenProject;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          const Text(
            'Panoramica',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: GussoniBrand.textPrimary),
          ),
          const SizedBox(height: 4),
          Text(
            DateFormat('EEEE d MMMM yyyy', 'it').format(DateTime.now()),
            style: const TextStyle(fontSize: 13, color: GussoniBrand.textMuted),
          ),
          const SizedBox(height: 24),

          // KPI pills
          _KpiRow(workspace: workspace),
          const SizedBox(height: 28),

          // Listing sections in 2-column grid on wide screens
          LayoutBuilder(builder: (ctx, c) {
            final wide = c.maxWidth > 900;
            if (wide) {
              return Column(children: [
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(child: _SocietaSection(workspace: workspace, onGoTo: onGoToSocieta, onOpen: onOpenCompany)),
                  const SizedBox(width: 20),
                  Expanded(child: _ContattiSection(workspace: workspace, onGoTo: onGoToContatti)),
                ]),
                const SizedBox(height: 20),
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(child: _OpportunitaSection(workspace: workspace, onGoTo: onGoToOpportunita, onOpen: onOpenOpportunity)),
                  const SizedBox(width: 20),
                  Expanded(child: _PreventiviSection(workspace: workspace, onGoTo: onGoToPreventivi)),
                ]),
                const SizedBox(height: 20),
                _ProgettiSection(workspace: workspace, onGoTo: onGoToProgetti, onOpen: onOpenProject),
              ]);
            }
            return Column(children: [
              _SocietaSection(workspace: workspace, onGoTo: onGoToSocieta, onOpen: onOpenCompany),
              const SizedBox(height: 20),
              _ContattiSection(workspace: workspace, onGoTo: onGoToContatti),
              const SizedBox(height: 20),
              _OpportunitaSection(workspace: workspace, onGoTo: onGoToOpportunita, onOpen: onOpenOpportunity),
              const SizedBox(height: 20),
              _PreventiviSection(workspace: workspace, onGoTo: onGoToPreventivi),
              const SizedBox(height: 20),
              _ProgettiSection(workspace: workspace, onGoTo: onGoToProgetti, onOpen: onOpenProject),
            ]);
          }),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

// ─── KPI pills ────────────────────────────────────────────────────────────────

class _KpiRow extends StatelessWidget {
  const _KpiRow({required this.workspace});
  final WorkspaceSnapshot workspace;

  @override
  Widget build(BuildContext context) {
    final openOpps = workspace.opportunities
        .where((o) => o.status != OpportunityStatus.persa)
        .length;
    final activeProjects = workspace.projects
        .where((p) => p.status != 'closed' && p.status != 'rejected')
        .length;
    final openInvoices = workspace.invoiceDrafts
        .where((i) => i.status == InvoiceStatus.draft)
        .length;
    final totalCompanies = workspace.companies.length;

    return Wrap(spacing: 12, runSpacing: 12, children: [
      _KpiPill(label: 'Aziende', value: '$totalCompanies', icon: Icons.apartment_outlined, color: GussoniBrand.primary),
      _KpiPill(label: 'Opportunità aperte', value: '$openOpps', icon: Icons.trending_up_outlined, color: GussoniBrand.gold),
      _KpiPill(label: 'Progetti attivi', value: '$activeProjects', icon: Icons.folder_open_outlined, color: GussoniBrand.info),
      _KpiPill(label: 'Fatture in bozza', value: '$openInvoices', icon: Icons.receipt_long_outlined, color: GussoniBrand.warning),
    ]);
  }
}

class _KpiPill extends StatelessWidget {
  const _KpiPill({required this.label, required this.value, required this.icon, required this.color});
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    decoration: BoxDecoration(
      gradient: LinearGradient(
        colors: [
          const Color(0xFFF6FBFF).withValues(alpha: .92),
          const Color(0xFFF6E9E3).withValues(alpha: .84),
        ],
      ),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: Colors.white.withValues(alpha: .78)),
    ),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Container(
        width: 36, height: 36,
        decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
        child: Icon(icon, size: 18, color: color),
      ),
      const SizedBox(width: 12),
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: color)),
        Text(label, style: const TextStyle(fontSize: 11, color: GussoniBrand.textMuted)),
      ]),
    ]),
  );
}

// ─── Section header ───────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.count, required this.onGoTo});
  final String title;
  final int count;
  final VoidCallback onGoTo;

  @override
  Widget build(BuildContext context) => Row(children: [
    Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: GussoniBrand.textPrimary)),
    const SizedBox(width: 8),
    Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.white.withValues(alpha: .88),
            const Color(0xFFF0E9E1),
          ],
        ),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: .82)),
      ),
      child: Text('$count', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: GussoniBrand.textMuted)),
    ),
    const Spacer(),
    InkWell(
      onTap: onGoTo,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text('Vedi tutti', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: GussoniBrand.primary)),
          SizedBox(width: 4),
          Icon(Icons.arrow_forward, size: 13, color: GussoniBrand.primary),
        ]),
      ),
    ),
  ]);
}

// ─── Sezione Società ──────────────────────────────────────────────────────────

class _SocietaSection extends StatelessWidget {
  const _SocietaSection({required this.workspace, required this.onGoTo, required this.onOpen});
  final WorkspaceSnapshot workspace;
  final VoidCallback onGoTo;
  final void Function(Company) onOpen;

  @override
  Widget build(BuildContext context) {
    final items = workspace.companies.take(6).toList();
    return _ListCard(
      header: _SectionHeader(title: 'Società', count: workspace.companies.length, onGoTo: onGoTo),
      children: items.isEmpty
          ? [const _EmptyRow(label: 'Nessuna società')]
          : items.map((c) => _ListRow(
              leading: CircleAvatar(radius: 14,
                  backgroundColor: GussoniBrand.primaryBg,
                  child: Text(c.name.isNotEmpty ? c.name[0].toUpperCase() : '?',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: GussoniBrand.primary))),
              title: c.name,
              sub: c.city.isNotEmpty ? c.city : c.vatNumber,
              badge: c.companyType == CompanyType.nonProfit ? 'NP' : c.companyType == CompanyType.pa ? 'PA' : null,
              onTap: () => onOpen(c),
            )).toList(),
    );
  }
}

// ─── Sezione Contatti ─────────────────────────────────────────────────────────

class _ContattiSection extends StatelessWidget {
  const _ContattiSection({required this.workspace, required this.onGoTo});
  final WorkspaceSnapshot workspace;
  final VoidCallback onGoTo;

  String _companyName(String id) =>
      workspace.companies.where((c) => c.id == id).firstOrNull?.name ?? '';

  @override
  Widget build(BuildContext context) {
    final items = workspace.companyContacts.take(6).toList();
    return _ListCard(
      header: _SectionHeader(title: 'Contatti', count: workspace.companyContacts.length, onGoTo: onGoTo),
      children: items.isEmpty
          ? [const _EmptyRow(label: 'Nessun contatto')]
          : items.map((c) => _ListRow(
              leading: CircleAvatar(radius: 14,
                  backgroundColor: GussoniBrand.goldBg,
                  child: Text(c.name.isNotEmpty ? c.name[0].toUpperCase() : '?',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: GussoniBrand.gold))),
              title: c.name,
              sub: c.role.isNotEmpty ? c.role : _companyName(c.companyId),
              onTap: null,
            )).toList(),
    );
  }
}

// ─── Sezione Opportunità ──────────────────────────────────────────────────────

class _OpportunitaSection extends StatelessWidget {
  const _OpportunitaSection({required this.workspace, required this.onGoTo, required this.onOpen});
  final WorkspaceSnapshot workspace;
  final VoidCallback onGoTo;
  final void Function(Opportunity) onOpen;

  static Color _statusColor(OpportunityStatus s) => switch (s) {
    OpportunityStatus.inAttesa                    => GussoniBrand.info,
    OpportunityStatus.preventivazione             => GussoniBrand.gold,
    OpportunityStatus.accettata                   => GussoniBrand.success,
    OpportunityStatus.accettataSenzaFirma         => GussoniBrand.success,
    OpportunityStatus.inAttesaRinnovoAutomatico   => GussoniBrand.warning,
    OpportunityStatus.presaInCarico => GussoniBrand.primary,
    OpportunityStatus.persa                       => GussoniBrand.textDisabled,
  };

  static String _statusLabel(OpportunityStatus s) => switch (s) {
    OpportunityStatus.inAttesa                    => 'In attesa',
    OpportunityStatus.preventivazione             => 'Preventiv.',
    OpportunityStatus.accettata                   => 'Accettata',
    OpportunityStatus.accettataSenzaFirma         => 'Acc. s/firma',
    OpportunityStatus.inAttesaRinnovoAutomatico   => 'Rinnovo',
    OpportunityStatus.presaInCarico => 'Presa in carico',
    OpportunityStatus.persa                       => 'Persa',
  };

  @override
  Widget build(BuildContext context) {
    final sorted = [...workspace.opportunities]
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final items = sorted.take(6).toList();
    return _ListCard(
      header: _SectionHeader(title: 'Opportunità', count: workspace.opportunities.length, onGoTo: onGoTo),
      children: items.isEmpty
          ? [const _EmptyRow(label: 'Nessuna opportunità')]
          : items.map((o) {
              final companyName = workspace.companies.where((c) => c.id == o.companyId).firstOrNull?.name ?? '';
              return _ListRow(
                leading: Container(
                  width: 8, height: 8,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: _statusColor(o.status)),
                ),
                title: o.title,
                sub: companyName,
                badge: _statusLabel(o.status),
                badgeColor: _statusColor(o.status),
                onTap: () => onOpen(o),
              );
            }).toList(),
    );
  }
}

// ─── Sezione Preventivi ───────────────────────────────────────────────────────

class _PreventiviSection extends StatelessWidget {
  const _PreventiviSection({required this.workspace, required this.onGoTo});
  final WorkspaceSnapshot workspace;
  final VoidCallback onGoTo;

  @override
  Widget build(BuildContext context) {
    final eur = NumberFormat.currency(locale: 'it_IT', symbol: '€', decimalDigits: 0);
    final items = workspace.gussoniQuotations.take(6).toList();
    return _ListCard(
      header: _SectionHeader(title: 'Preventivi', count: workspace.gussoniQuotations.length, onGoTo: onGoTo),
      children: items.isEmpty
          ? [const _EmptyRow(label: 'Nessun preventivo')]
          : items.map((q) {
              final companyName = workspace.companies.where((c) => c.id == q.companyId).firstOrNull?.name ?? '—';
              final statusLabel = switch (q.status) {
                PreventivoStatus.draft    => 'Bozza',
                PreventivoStatus.sent     => 'Inviato',
                PreventivoStatus.accepted => 'Accettato',
                PreventivoStatus.rejected => 'Rifiutato',
              };
              final statusColor = switch (q.status) {
                PreventivoStatus.draft    => GussoniBrand.textMuted,
                PreventivoStatus.sent     => GussoniBrand.info,
                PreventivoStatus.accepted => GussoniBrand.success,
                PreventivoStatus.rejected => GussoniBrand.error,
              };
              return _ListRow(
                leading: Icon(Icons.request_quote_outlined, size: 16, color: GussoniBrand.textMuted),
                title: companyName,
                sub: eur.format(q.total),
                badge: statusLabel,
                badgeColor: statusColor,
                onTap: null,
              );
            }).toList(),
    );
  }
}

// ─── Sezione Progetti ─────────────────────────────────────────────────────────

class _ProgettiSection extends StatelessWidget {
  const _ProgettiSection({required this.workspace, required this.onGoTo, required this.onOpen});
  final WorkspaceSnapshot workspace;
  final VoidCallback onGoTo;
  final void Function(Project) onOpen;

  static Color _statusColor(String s) => switch (s) {
    'draft'         => GussoniBrand.textMuted,
    'planning'      => GussoniBrand.info,
    'inProgress'    => GussoniBrand.warning,
    'pendingResult' => GussoniBrand.gold,
    'approved'      => GussoniBrand.success,
    'closed'        => GussoniBrand.textSecondary,
    _               => GussoniBrand.textMuted,
  };

  static String _statusLabel(String s) => switch (s) {
    'draft'         => 'Bozza',
    'planning'      => 'Pianific.',
    'inProgress'    => 'In corso',
    'pendingResult' => 'In attesa',
    'approved'      => 'Approvato',
    'closed'        => 'Chiuso',
    _               => s,
  };

  @override
  Widget build(BuildContext context) {
    final active = workspace.projects
        .where((p) => p.status != 'closed' && p.status != 'rejected')
        .toList()
      ..sort((a, b) => (b.createdAt ?? DateTime(0)).compareTo(a.createdAt ?? DateTime(0)));

    return _ListCard(
      header: _SectionHeader(title: 'Progetti', count: workspace.projects.length, onGoTo: onGoTo),
      children: active.isEmpty
          ? [const _EmptyRow(label: 'Nessun progetto attivo')]
          : active.take(8).map((p) {
              final company = workspace.companies.where((c) => c.id == p.companyId).firstOrNull?.name ?? '—';
              final phases = workspace.phases.where((ph) => ph.projectId == p.id).length;
              final done = workspace.phases.where((ph) => ph.projectId == p.id && ph.status == PhaseStatus.done).length;
              return _ListRow(
                leading: Icon(Icons.folder_open_outlined, size: 16,
                    color: p.anticipoEmesso ? GussoniBrand.textMuted : GussoniBrand.warning),
                title: p.name,
                sub: company,
                badge: _statusLabel(p.status),
                badgeColor: _statusColor(p.status),
                trailing: phases > 0
                    ? Text('$done/$phases fasi', style: const TextStyle(fontSize: 11, color: GussoniBrand.textMuted))
                    : null,
                onTap: () => onOpen(p),
              );
            }).toList(),
    );
  }
}

// ─── Shared widgets ───────────────────────────────────────────────────────────

class _ListCard extends StatelessWidget {
  const _ListCard({required this.header, required this.children});
  final Widget header;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Colors.white.withValues(alpha: .95),
          const Color(0xFFF1F8FF).withValues(alpha: .94),
        ],
      ),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: Colors.white.withValues(alpha: .82)),
      boxShadow: const [
        BoxShadow(
          color: Color(0x12000000),
          blurRadius: 22,
          offset: Offset(0, 14),
        ),
      ],
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(padding: const EdgeInsets.fromLTRB(18, 16, 16, 12), child: header),
      const Divider(height: 1),
      ...children,
    ]),
  );
}

class _ListRow extends StatelessWidget {
  const _ListRow({
    required this.leading,
    required this.title,
    this.sub,
    this.badge,
    this.badgeColor,
    this.trailing,
    this.onTap,
  });

  final Widget leading;
  final String title;
  final String? sub;
  final String? badge;
  final Color? badgeColor;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(14),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        border: const Border(bottom: BorderSide(color: GussoniBrand.borderSubtle)),
        gradient: onTap != null
            ? LinearGradient(
                colors: [
                  const Color(0xFFF7FCFF).withValues(alpha: .68),
                  const Color(0xFFEAF8FF).withValues(alpha: .42),
                ],
              )
            : null,
      ),
      child: Row(children: [
        leading,
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title,
              style: TextStyle(
                fontSize: 13, fontWeight: FontWeight.w600,
                color: onTap != null ? GussoniBrand.primary : GussoniBrand.textPrimary,
              ),
              overflow: TextOverflow.ellipsis),
          if (sub != null && sub!.isNotEmpty)
            Text(sub!, style: const TextStyle(fontSize: 11, color: GussoniBrand.textMuted), overflow: TextOverflow.ellipsis),
        ])),
        if (badge != null) ...[
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: (badgeColor ?? GussoniBrand.textMuted).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(badge!, style: TextStyle(
              fontSize: 10, fontWeight: FontWeight.w700,
              color: badgeColor ?? GussoniBrand.textMuted,
            )),
          ),
        ],
        if (trailing != null) ...[const SizedBox(width: 8), trailing!],
        if (onTap != null)
          const Icon(Icons.chevron_right, size: 14, color: GussoniBrand.textDisabled),
      ]),
    ),
  );
}

class _EmptyRow extends StatelessWidget {
  const _EmptyRow({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(16),
    child: Text(label, style: const TextStyle(fontSize: 13, color: GussoniBrand.textMuted)),
  );
}
