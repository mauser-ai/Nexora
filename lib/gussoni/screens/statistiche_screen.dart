import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../brand_config.dart';
import '../../data/firestore_workspace_repository.dart';
import '../../models/domain_models.dart';
import '../widgets/g_table.dart';

class StatisticheGussoniScreen extends StatelessWidget {
  const StatisticheGussoniScreen({
    super.key,
    required this.workspace,
    required this.userId,
    this.showHeader = true,
  });
  final WorkspaceSnapshot workspace;
  final String userId;
  final bool showHeader;

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat('#,##0.00', 'it_IT');
    final fmtInt = NumberFormat('#,##0', 'it_IT');

    // KPI calcolati
    final totalOpps = workspace.opportunities.length;
    final acceptedOpps = workspace.opportunities
        .where((o) => o.status == OpportunityStatus.accettata)
        .length;
    final conversionRate = totalOpps > 0
        ? (acceptedOpps / totalOpps * 100).toStringAsFixed(0)
        : '0';

    final activeProjects = workspace.projects
        .where((p) => p.status == 'inProgress' || p.status == 'planning')
        .length;
    final closedProjects = workspace.projects
        .where((p) => p.status == 'approved' || p.status == 'closed')
        .length;

    final totalGrant = workspace.projects
        .where((p) => p.grantAmount != null)
        .fold(0.0, (s, p) => s + (p.grantAmount ?? 0));
    final totalSuccessFee = workspace.projects
        .where((p) => p.successFeeAmount != null)
        .fold(0.0, (s, p) => s + (p.successFeeAmount ?? 0));

    final draftInvoices = workspace.invoiceDrafts
        .where((i) => i.status == InvoiceStatus.draft)
        .length;
    final totalInvoiced = workspace.invoiceDrafts
        .where((i) => i.status == InvoiceStatus.exported)
        .fold(0.0, (s, i) => s + i.amount);
    final totalPending = workspace.invoiceDrafts
        .where(
          (i) =>
              i.status == InvoiceStatus.draft ||
              i.status == InvoiceStatus.readyForXml,
        )
        .fold(0.0, (s, i) => s + i.amount);

    final totalHours = workspace.timeTracks.fold(0.0, (s, t) => s + t.hours);
    final billableHours = workspace.timeTracks
        .where((t) => t.billable)
        .fold(0.0, (s, t) => s + t.hours);

    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showHeader) ...[
            Text(
              'Statistiche',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: GussoniBrand.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Panoramica operativa della piattaforma',
              style: TextStyle(fontSize: 12, color: GussoniBrand.textMuted),
            ),
            const SizedBox(height: 20),
          ],

          // Row 1: Opportunità
          _KpiSection(
            title: 'Opportunità & Commerciale',
            children: [
              _KpiCard(
                label: 'Totale opportunità',
                value: '$totalOpps',
                icon: Icons.trending_up_outlined,
                color: GussoniBrand.info,
              ),
              _KpiCard(
                label: 'Accettate',
                value: '$acceptedOpps',
                icon: Icons.check_circle_outline,
                color: GussoniBrand.success,
              ),
              _KpiCard(
                label: 'Tasso conversione',
                value: '$conversionRate%',
                icon: Icons.percent_outlined,
                color: GussoniBrand.gold,
              ),
              _KpiCard(
                label: 'Preventivi aperti',
                value:
                    '${workspace.gussoniQuotations.where((q) => q.status == PreventivoStatus.sent).length}',
                icon: Icons.request_quote_outlined,
                color: GussoniBrand.warning,
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Row 2: Progetti
          _KpiSection(
            title: 'Progetti',
            children: [
              _KpiCard(
                label: 'In corso',
                value: '$activeProjects',
                icon: Icons.folder_open_outlined,
                color: GussoniBrand.primary,
              ),
              _KpiCard(
                label: 'Chiusi con esito',
                value: '$closedProjects',
                icon: Icons.task_alt_outlined,
                color: GussoniBrand.success,
              ),
              _KpiCard(
                label: 'Contributi ottenuti',
                value: '€ ${fmtInt.format(totalGrant)}',
                icon: Icons.savings_outlined,
                color: GussoniBrand.gold,
              ),
              _KpiCard(
                label: 'Success fee maturate',
                value: '€ ${fmtInt.format(totalSuccessFee)}',
                icon: Icons.star_outline,
                color: GussoniBrand.gold,
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Row 3: Fatturazione
          _KpiSection(
            title: 'Fatturazione',
            children: [
              _KpiCard(
                label: 'Fatture in bozza',
                value: '$draftInvoices',
                icon: Icons.receipt_outlined,
                color: GussoniBrand.warning,
              ),
              _KpiCard(
                label: 'Da incassare',
                value: '€ ${fmtInt.format(totalPending)}',
                icon: Icons.hourglass_empty_outlined,
                color: GussoniBrand.warning,
              ),
              _KpiCard(
                label: 'Totale fatturato',
                value: '€ ${fmtInt.format(totalInvoiced)}',
                icon: Icons.receipt_long_outlined,
                color: GussoniBrand.success,
              ),
              _KpiCard(
                label: 'Fatture success fee',
                value:
                    '${workspace.invoiceDrafts.where((i) => i.isSuccessFee).length}',
                icon: Icons.star_half_outlined,
                color: GussoniBrand.gold,
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Row 4: Tempo
          _KpiSection(
            title: 'Ore lavoro',
            children: [
              _KpiCard(
                label: 'Ore totali',
                value: '${totalHours.toStringAsFixed(1)} h',
                icon: Icons.schedule_outlined,
                color: GussoniBrand.primary,
              ),
              _KpiCard(
                label: 'Ore fatturabili',
                value: '${billableHours.toStringAsFixed(1)} h',
                icon: Icons.monetization_on_outlined,
                color: GussoniBrand.success,
              ),
              _KpiCard(
                label: 'Task aperti',
                value:
                    '${workspace.tasks.where((t) => t.status != TaskStatus.done).length}',
                icon: Icons.checklist_outlined,
                color: GussoniBrand.info,
              ),
              _KpiCard(
                label: 'Società clienti',
                value: '${workspace.companies.length}',
                icon: Icons.apartment_outlined,
                color: GussoniBrand.textSecondary,
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Tabella opportunità recenti
          _TableCard(
            title: 'Opportunità recenti',
            child: Column(
              children: [
                _TableHeader(const [
                  'Cliente',
                  'Titolo',
                  'Stato',
                  'Valore stimato',
                ]),
                ...workspace.opportunities.take(8).map((o) {
                  final company =
                      workspace.companies
                          .where((c) => c.id == o.companyId)
                          .firstOrNull
                          ?.name ??
                      '—';
                  return _TableRow(
                    [
                      company,
                      o.title,
                      _oppStatusLabel(o.status),
                      o.estimatedValue != null
                          ? '€ ${fmtInt.format(o.estimatedValue)}'
                          : '—',
                    ],
                    statusIndex: 2,
                    statusColor: _oppStatusColor(o.status),
                  );
                }),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _oppStatusLabel(OpportunityStatus s) => switch (s) {
    OpportunityStatus.inAttesa => 'In attesa',
    OpportunityStatus.preventivazione => 'Preventivazione',
    OpportunityStatus.accettata => 'Accettata',
    OpportunityStatus.accettataSenzaFirma => 'Acc. senza firma',
    OpportunityStatus.inAttesaRinnovoAutomatico => 'Rinnovo automatico',
    OpportunityStatus.presaInCarico => 'Presa in carico',
    OpportunityStatus.persa => 'Persa',
  };

  static Color _oppStatusColor(OpportunityStatus s) => switch (s) {
    OpportunityStatus.inAttesa => GussoniBrand.info,
    OpportunityStatus.preventivazione => GussoniBrand.gold,
    OpportunityStatus.accettata => GussoniBrand.success,
    OpportunityStatus.accettataSenzaFirma => GussoniBrand.success,
    OpportunityStatus.inAttesaRinnovoAutomatico => GussoniBrand.warning,
    OpportunityStatus.presaInCarico => GussoniBrand.primary,
    OpportunityStatus.persa => GussoniBrand.textDisabled,
  };
}

// ── Componenti interni statistiche ──

class _KpiSection extends StatelessWidget {
  const _KpiSection({required this.title, required this.children});
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final compact = constraints.maxWidth < 620;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: GussoniBrand.textMuted,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 8),
          if (compact)
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: children
                  .map(
                    (c) => SizedBox(
                      width: (constraints.maxWidth - 10) / 2,
                      child: c,
                    ),
                  )
                  .toList(),
            )
          else
            Row(
              children: children
                  .map(
                    (c) => Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(right: 12),
                        child: c,
                      ),
                    ),
                  )
                  .toList(),
            ),
        ],
      );
    },
  );
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });
  final String label, value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: GussoniBrand.surface,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: GussoniBrand.border),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color.withOpacity(.1),
          ),
          child: Icon(icon, size: 16, color: color),
        ),
        const SizedBox(height: 12),
        Text(
          value,
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: GussoniBrand.textPrimary,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(fontSize: 11, color: GussoniBrand.textMuted),
        ),
      ],
    ),
  );
}

class _TableCard extends StatelessWidget {
  const _TableCard({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: GussoniBrand.surface,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: GussoniBrand.border),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
          child: Text(
            title,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: GussoniBrand.textPrimary,
            ),
          ),
        ),
        const Divider(height: 1),
        child,
      ],
    ),
  );
}

class _TableHeader extends StatelessWidget {
  const _TableHeader(this.labels);
  final List<String> labels;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    color: GussoniBrand.surfaceMuted,
    child: Row(
      children: labels
          .map(
            (l) => Expanded(
              child: Text(
                l.toUpperCase(),
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: GussoniBrand.textMuted,
                  letterSpacing: 0.7,
                ),
              ),
            ),
          )
          .toList(),
    ),
  );
}

class _TableRow extends StatelessWidget {
  const _TableRow(this.cells, {this.statusIndex, this.statusColor});
  final List<String> cells;
  final int? statusIndex;
  final Color? statusColor;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: GussoniBrand.borderSubtle)),
    ),
    child: Row(
      children: cells
          .asMap()
          .entries
          .map(
            (e) => Expanded(
              child: e.key == statusIndex && statusColor != null
                  ? GStatusChip(
                      label: e.value,
                      color: statusColor!,
                      small: true,
                    )
                  : GCellText(e.key == 0 ? e.value : e.value, muted: e.key > 0),
            ),
          )
          .toList(),
    ),
  );
}
