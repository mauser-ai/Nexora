import '../../../brand_config.dart';
import '../../../app/context_archive_browser.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../data/api_workspace_repository.dart';
import '../../../models/domain_models.dart';
import '../../data/firestore_crm_repository.dart';
import '../../models/crm_extra_models.dart';
import 'detail_widgets.dart';

// ────────────────────────────────────────────────
// Company Detail Page
// ────────────────────────────────────────────────

class CompanyDetailPage extends StatefulWidget {
  const CompanyDetailPage({
    super.key,
    required this.company,
    required this.workspace,
    required this.crmData,
    required this.repository,
    required this.crmRepo,
    required this.userId,
    required this.onBack,
    required this.onEdit,
    this.onAddDeal,
    this.onAddQuotation,
    this.onAddContact,
    this.onAddProject,
    this.onAddInvoice,
    this.onAddTicket,
    this.onAddTask,
    this.onAddWorkOrder,
    this.onOpenContact,
    this.onOpenWorkspaceContact,
    this.onOpenDeal,
    this.onOpenQuotation,
    this.onOpenProject,
    this.onOpenInvoice,
    this.onOpenTicket,
    this.onOpenTask,
  });

  final Company company;
  final WorkspaceSnapshot workspace;
  final CrmData crmData;
  final ApiWorkspaceRepository repository;
  final FirestoreCrmRepository crmRepo;
  final String userId;
  final VoidCallback onBack;
  final Future<void> Function(Company) onEdit;
  final VoidCallback? onAddDeal;
  final VoidCallback? onAddQuotation;
  final VoidCallback? onAddContact;
  final VoidCallback? onAddProject;
  final VoidCallback? onAddInvoice;
  final VoidCallback? onAddTicket;
  final VoidCallback? onAddTask;
  final VoidCallback? onAddWorkOrder;
  final void Function(CrmFirestoreContact contact)? onOpenContact;
  final void Function(CompanyContact contact)? onOpenWorkspaceContact;
  final void Function(Deal deal)? onOpenDeal;
  final void Function(Quotation quotation)? onOpenQuotation;
  final void Function(Project project)? onOpenProject;
  final void Function(InvoiceDraft invoice)? onOpenInvoice;
  final void Function(Ticket ticket)? onOpenTicket;
  final void Function(WorkTask task)? onOpenTask;

  @override
  State<CompanyDetailPage> createState() => _CompanyDetailPageState();
}

class _CompanyDetailPageState extends State<CompanyDetailPage> {
  late Company _company;
  final _currFmt = NumberFormat.currency(
    locale: 'it_IT',
    symbol: '€',
    decimalDigits: 0,
  );

  @override
  void initState() {
    super.initState();
    _company = widget.company;
  }

  @override
  void didUpdateWidget(CompanyDetailPage old) {
    super.didUpdateWidget(old);
    if (old.company.id != widget.company.id) _company = widget.company;
  }

  // Related data helpers
  List<CrmFirestoreContact> get _crmContacts =>
      widget.crmData.contactsForCompany(_company.id);

  List<CompanyContact> get _wsContacts => widget.workspace.companyContacts
      .where((c) => c.companyId == _company.id)
      .toList();

  List<Deal> get _deals => widget.crmData.dealsForCustomer(_company.id);

  List<Quotation> get _quotations =>
      widget.crmData.quotationsForCustomer(_company.id);

  List<Project> get _projects => widget.workspace.projects
      .where((p) => p.companyId == _company.id)
      .toList();

  List<InvoiceDraft> get _invoices => widget.workspace.invoiceDrafts
      .where((i) => i.companyId == _company.id)
      .toList();

  List<Ticket> get _tickets => widget.workspace.tickets
      .where((t) => t.companyId == _company.id)
      .toList();

  List<WorkTask> get _tasks =>
      widget.workspace.tasks.where((t) => t.companyId == _company.id).toList();

  List<WorkOrder> get _workOrders =>
      widget.crmData.workOrdersForCompany(_company.id);

  @override
  Widget build(BuildContext context) {
    final color = colorForName(_company.name);
    final allContactsCount = _crmContacts.length + _wsContacts.length;
    final openRelatedCount =
        _deals.where((item) => item.status == DealFirestoreStatus.open).length +
        _quotations
            .where(
              (item) =>
                  item.status == QuotationStatus.draft ||
                  item.status == QuotationStatus.sent,
            )
            .length +
        _tasks.where((item) => item.status != TaskStatus.done).length;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Back bar
          DetailBackBar(label: 'Panoramica società', onBack: widget.onBack),
          _CompanyDetailHero(
            company: _company,
            color: color,
            contacts: allContactsCount,
            openItems: openRelatedCount,
            projects: _projects.length,
            revenue: _company.mediaRicavi,
            currencyFormat: _currFmt,
          ),
          const SizedBox(height: 16),
          // Two-column top area
          LayoutBuilder(
            builder: (context, c) {
              final wide = c.maxWidth > 800;
              final infoCard = DetailInfoCard(
                title: 'Informazioni sulla società',
                onEdit: () => widget.onEdit(_company),
                avatar: Row(
                  children: [
                    EntityAvatar(
                      initials: initialsFor(_company.name),
                      color: color,
                      size: 52,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _company.name,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFFE4E8FF),
                            ),
                          ),
                          if (_company.vatNumber.isNotEmpty)
                            Text(
                              _company.vatNumber,
                              style: const TextStyle(
                                fontSize: 13,
                                color: Color(0xFF7D89A8),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
                rows: [
                  if (_company.email.isNotEmpty)
                    DetailInfoRow(
                      label: 'E-mail',
                      value: _company.email,
                      isLink: true,
                    ),
                  if (_company.addressLine.isNotEmpty)
                    DetailInfoRow(
                      label: 'Indirizzo principale',
                      value:
                          '${_company.addressLine}\n${_company.postalCode} ${_company.city} ${_company.country}'
                              .trim(),
                    ),
                  if (_company.phone.isNotEmpty)
                    DetailInfoRow(label: 'Telefono', value: _company.phone),
                  if (_company.website.isNotEmpty)
                    DetailInfoRow(
                      label: 'Sito web',
                      value: _company.website,
                      isLink: true,
                    ),
                  if (_company.pec.isNotEmpty)
                    DetailInfoRow(label: 'PEC', value: _company.pec),
                  if (_company.sdiCode.isNotEmpty)
                    DetailInfoRow(
                      label: 'Cod. destinatario',
                      value: _company.sdiCode,
                    ),
                  if (_company.taxCode.isNotEmpty)
                    DetailInfoRow(
                      label: 'Codice fiscale',
                      value: _company.taxCode,
                    ),
                  if (_company.contactPerson.isNotEmpty)
                    DetailInfoRow(
                      label: 'Referente',
                      value: _company.contactPerson,
                    ),
                ],
              );

              final notesCard = DetailNotesCard(
                notes: _company.notes,
                onSave: (notes) async {
                  final updated = _company.copyWith(notes: notes);
                  await widget.repository.updateCompany(widget.userId, updated);
                  setState(() => _company = updated);
                },
              );

              if (wide) {
                return IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 3, child: infoCard),
                      const SizedBox(width: 16),
                      Expanded(flex: 2, child: notesCard),
                    ],
                  ),
                );
              }
              return Column(
                children: [infoCard, const SizedBox(height: 12), notesCard],
              );
            },
          ),
          const SizedBox(height: 20),

          // ── Accordion sections ──

          // Opportunità
          DetailAccordion(
            title: 'Opportunità',
            count: _deals.length,
            initiallyExpanded: _deals.isNotEmpty,
            onAdd: widget.onAddDeal,
            children: _deals.map((d) {
              final stage = widget.crmData.stageById(d.stageId);
              return Column(
                children: [
                  AccordionRow(
                    leading: Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: d.status.color,
                      ),
                    ),
                    title: d.title,
                    subtitle: stage?.name,
                    trailing: Text(
                      _currFmt.format(d.value),
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    badge: DetailBadge(
                      label: d.status.label,
                      color: d.status.color,
                    ),
                    onTap: widget.onOpenDeal == null
                        ? null
                        : () => widget.onOpenDeal!(d),
                  ),
                  const AccordionDivider(),
                ],
              );
            }).toList(),
          ),

          // Preventivi
          DetailAccordion(
            title: 'Preventivi',
            count: _quotations.length,
            initiallyExpanded: _quotations.isNotEmpty,
            onAdd: widget.onAddQuotation,
            children: _quotations
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
                        subtitle: q.createdAt != null
                            ? DateFormat('dd/MM/yyyy').format(q.createdAt!)
                            : null,
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
                        onTap: widget.onOpenQuotation == null
                            ? null
                            : () => widget.onOpenQuotation!(q),
                      ),
                      const AccordionDivider(),
                    ],
                  ),
                )
                .toList(),
          ),

          // Contatti collegati (CRM + workspace)
          DetailAccordion(
            title: 'Contatti collegati',
            count: allContactsCount,
            initiallyExpanded: allContactsCount > 0,
            onAdd: widget.onAddContact,
            children: [
              ..._crmContacts.map(
                (c) => Column(
                  children: [
                    AccordionRow(
                      leading: EntityAvatar(
                        initials: c.initials,
                        color: colorForName(c.fullName),
                        size: 32,
                      ),
                      title: c.fullName,
                      subtitle: c.role.isEmpty ? c.email : c.role,
                      onTap: widget.onOpenContact == null
                          ? null
                          : () => widget.onOpenContact!(c),
                    ),
                    const AccordionDivider(),
                  ],
                ),
              ),
              ..._wsContacts.map(
                (c) => Column(
                  children: [
                    AccordionRow(
                      leading: EntityAvatar(
                        initials: initialsFor(c.name),
                        color: colorForName(c.name),
                        size: 32,
                      ),
                      title: c.name,
                      subtitle: c.role.isEmpty ? c.email : c.role,
                      onTap: widget.onOpenWorkspaceContact == null
                          ? null
                          : () => widget.onOpenWorkspaceContact!(c),
                    ),
                    const AccordionDivider(),
                  ],
                ),
              ),
            ],
          ),

          // Progetti
          DetailAccordion(
            title: 'Progetti',
            count: _projects.length,
            onAdd: widget.onAddProject,
            children: _projects
                .map(
                  (p) => Column(
                    children: [
                      AccordionRow(
                        leading: const Icon(
                          Icons.folder_open_outlined,
                          size: 18,
                          color: Color(0xFF034F3B),
                        ),
                        title: p.name,
                        subtitle: p.code.isNotEmpty ? 'Cod: ${p.code}' : null,
                        badge: _ProjectBadge(status: p.status),
                        onTap: widget.onOpenProject == null
                            ? null
                            : () => widget.onOpenProject!(p),
                      ),
                      const AccordionDivider(),
                    ],
                  ),
                )
                .toList(),
          ),

          // Fatture
          DetailAccordion(
            title: 'Fatture',
            count: _invoices.length,
            onAdd: widget.onAddInvoice,
            children: _invoices
                .map(
                  (inv) => Column(
                    children: [
                      AccordionRow(
                        leading: const Icon(
                          Icons.receipt_long_outlined,
                          size: 18,
                          color: Color(0xFFB8C0D8),
                        ),
                        title: inv.number.isEmpty
                            ? 'Fattura senza numero'
                            : inv.number,
                        trailing: Text(
                          _currFmt.format(inv.amount),
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        badge: _InvoiceBadge(status: inv.status),
                        onTap: widget.onOpenInvoice == null
                            ? null
                            : () => widget.onOpenInvoice!(inv),
                      ),
                      const AccordionDivider(),
                    ],
                  ),
                )
                .toList(),
          ),

          // Ticket
          DetailAccordion(
            title: 'Ticket',
            count: _tickets.length,
            onAdd: widget.onAddTicket,
            children: _tickets
                .map(
                  (t) => Column(
                    children: [
                      AccordionRow(
                        leading: const Icon(
                          Icons.support_agent_outlined,
                          size: 18,
                          color: Color(0xFF0369A1),
                        ),
                        title: t.title,
                        subtitle: t.recipientEmail,
                        badge: _TicketBadge(status: t.status),
                        onTap: widget.onOpenTicket == null
                            ? null
                            : () => widget.onOpenTicket!(t),
                      ),
                      const AccordionDivider(),
                    ],
                  ),
                )
                .toList(),
          ),

          // Task
          DetailAccordion(
            title: 'Task',
            count: _tasks.length,
            onAdd: widget.onAddTask,
            children: _tasks.map((t) {
              final overdue =
                  t.deadline.isBefore(DateTime.now()) &&
                  t.status != TaskStatus.done;
              return Column(
                children: [
                  AccordionRow(
                    leading: Icon(
                      t.status == TaskStatus.done
                          ? Icons.check_circle
                          : Icons.radio_button_unchecked,
                      size: 18,
                      color: t.status == TaskStatus.done
                          ? GussoniBrand.primary
                          : (overdue
                                ? const Color(0xFFB91C1C)
                                : const Color(0xFF1E2130)),
                    ),
                    title: t.name,
                    subtitle:
                        'Scadenza: ${DateFormat('dd/MM/yyyy').format(t.deadline)}',
                    onTap: widget.onOpenTask == null
                        ? null
                        : () => widget.onOpenTask!(t),
                  ),
                  const AccordionDivider(),
                ],
              );
            }).toList(),
          ),

          // Ordini di lavoro
          DetailAccordion(
            title: 'Ordini di lavoro',
            count: _workOrders.length,
            onAdd: widget.onAddWorkOrder,
            children: _workOrders
                .map(
                  (w) => Column(
                    children: [
                      AccordionRow(
                        leading: Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: w.priority.color,
                          ),
                        ),
                        title: w.title,
                        badge: DetailBadge(
                          label: w.status.label,
                          color: w.status.color,
                        ),
                      ),
                      const AccordionDivider(),
                    ],
                  ),
                )
                .toList(),
          ),

          const SizedBox(height: 20),
          SizedBox(
            height: 430,
            child: ContextArchiveBrowser(
              rootPath: 'Clienti/${_company.name.trim()}',
              rootLabel: _company.name.trim(),
              title: 'Archivio cliente',
              mode: ContextArchiveBrowserMode.grid,
              emptyLabel:
                  'Nessun file presente nella cartella di questa società.',
            ),
          ),

          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

class _CompanyDetailHero extends StatelessWidget {
  const _CompanyDetailHero({
    required this.company,
    required this.color,
    required this.contacts,
    required this.openItems,
    required this.projects,
    required this.revenue,
    required this.currencyFormat,
  });

  final Company company;
  final Color color;
  final int contacts;
  final int openItems;
  final int projects;
  final double? revenue;
  final NumberFormat currencyFormat;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            GussoniBrand.glassSurfaceStrong.withValues(alpha: .92),
            GussoniBrand.glassSurfaceMuted.withValues(alpha: .76),
            color.withValues(alpha: .12),
          ],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: .72)),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: .16),
            blurRadius: 34,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 760;
          final headline = Row(
            children: [
              EntityAvatar(
                initials: initialsFor(company.name),
                color: color,
                size: 58,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      company.name,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                        color: GussoniBrand.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      [
                        if (company.city.isNotEmpty) company.city,
                        if (company.riferimentoInterno.isNotEmpty)
                          'Ref. ${company.riferimentoInterno}',
                        _companyTypeLabel(company.companyType),
                      ].join(' · '),
                      style: const TextStyle(
                        fontSize: 13,
                        color: GussoniBrand.textMuted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );

          final metrics = Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _HeroMetric(
                label: 'Contatti',
                value: '$contacts',
                icon: Icons.people_alt_rounded,
                color: const Color(0xFF68A6FF),
              ),
              _HeroMetric(
                label: 'Aperti',
                value: '$openItems',
                icon: Icons.bolt_rounded,
                color: const Color(0xFFFF8A5B),
              ),
              _HeroMetric(
                label: 'Progetti',
                value: '$projects',
                icon: Icons.folder_open_rounded,
                color: GussoniBrand.primary,
              ),
              _HeroMetric(
                label: 'Ricavi medi',
                value: revenue == null ? '—' : currencyFormat.format(revenue),
                icon: Icons.query_stats_rounded,
                color: const Color(0xFFF06E9C),
              ),
            ],
          );

          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [headline, const SizedBox(height: 16), metrics],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(flex: 5, child: headline),
              const SizedBox(width: 20),
              Expanded(flex: 6, child: metrics),
            ],
          );
        },
      ),
    );
  }
}

String _companyTypeLabel(CompanyType type) => switch (type) {
  CompanyType.profit => 'Impresa',
  CompanyType.nonProfit => 'Non profit',
  CompanyType.pa => 'Pubblica amministrazione',
  CompanyType.pf => 'Persona fisica',
};

class _HeroMetric extends StatelessWidget {
  const _HeroMetric({
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
    width: 132,
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: .54),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: Colors.white.withValues(alpha: .74)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(height: 9),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w900,
            color: GussoniBrand.textPrimary,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            color: GussoniBrand.textMuted,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    ),
  );
}

class _ProjectBadge extends StatelessWidget {
  const _ProjectBadge({required this.status});
  final String status;
  Color get _color =>
      status == 'active' ? GussoniBrand.primary : const Color(0xFF7D89A8);
  String get _label => status == 'active'
      ? 'Attivo'
      : status == 'archived'
      ? 'Archiviato'
      : status;
  @override
  Widget build(BuildContext context) =>
      DetailBadge(label: _label, color: _color);
}

class _InvoiceBadge extends StatelessWidget {
  const _InvoiceBadge({required this.status});
  final InvoiceStatus status;
  Color get _color => switch (status) {
    InvoiceStatus.draft => const Color(0xFF7D89A8),
    InvoiceStatus.readyForXml => const Color(0xFF0369A1),
    InvoiceStatus.exported => GussoniBrand.primary,
  };
  String get _label => switch (status) {
    InvoiceStatus.draft => 'Bozza',
    InvoiceStatus.readyForXml => 'Pronta XML',
    InvoiceStatus.exported => 'Esportata',
  };
  @override
  Widget build(BuildContext context) =>
      DetailBadge(label: _label, color: _color);
}

class _TicketBadge extends StatelessWidget {
  const _TicketBadge({required this.status});
  final TicketStatus status;
  Color get _color => switch (status) {
    TicketStatus.newTicket => const Color(0xFF0369A1),
    TicketStatus.open => GussoniBrand.primary,
    TicketStatus.waitingCustomer => const Color(0xFFD97706),
    TicketStatus.closed => const Color(0xFF7D89A8),
  };
  String get _label => switch (status) {
    TicketStatus.newTicket => 'Nuovo',
    TicketStatus.open => 'Aperto',
    TicketStatus.waitingCustomer => 'In attesa',
    TicketStatus.closed => 'Chiuso',
  };
  @override
  Widget build(BuildContext context) =>
      DetailBadge(label: _label, color: _color);
}
