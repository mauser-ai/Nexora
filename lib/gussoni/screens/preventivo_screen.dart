import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../app/nexora_dialog.dart';
import '../../brand_config.dart';
import '../../data/api_workspace_repository.dart';
import '../../models/domain_models.dart';
import '../../data/team_repository.dart';
import '../widgets/g_table.dart';
import '../../data/template_repository.dart';
import '../../models/template_models.dart';
import '../../settings/document_pdf_service.dart';
import '../../settings/send_email_dialog.dart';
import '../../settings/template_picker_field.dart';
import 'project_wizard_dialog.dart';

// ──────────────────────────────────────────────────────────────
// Schermata Preventivi Gussoni
// ──────────────────────────────────────────────────────────────

class PreventivoGussoniScreen extends StatefulWidget {
  const PreventivoGussoniScreen({
    super.key,
    required this.workspace,
    required this.userId,
    required this.repository,
    required this.teamInfo,
    this.initialOpportunity,
    this.onProjectCreated,
    this.showHeader = true,
    this.showCreateButton = true,
  });

  final WorkspaceSnapshot workspace;
  final String userId;
  final ApiWorkspaceRepository repository;
  final TeamInfo? teamInfo;
  final Opportunity? initialOpportunity;
  final void Function(String projectId)? onProjectCreated;
  final bool showHeader;
  final bool showCreateButton;

  @override
  State<PreventivoGussoniScreen> createState() =>
      _PreventivoGussoniScreenState();
}

class _PreventivoGussoniScreenState extends State<PreventivoGussoniScreen> {
  PreventivoStatus? _filterStatus;
  Preventivo? _selected;

  List<Preventivo> get _filtered {
    var list = widget.workspace.gussoniQuotations;
    if (_filterStatus != null) {
      list = list.where((q) => q.status == _filterStatus).toList();
    }
    return list;
  }

  String _companyName(String id) =>
      widget.workspace.companies.where((c) => c.id == id).firstOrNull?.name ??
      id;

  String _oppTitle(String id) =>
      widget.workspace.opportunities
          .where((o) => o.id == id)
          .firstOrNull
          ?.title ??
      '—';

  @override
  void initState() {
    super.initState();
    // Se arriva un'opportunità iniziale, apre subito il dialog di creazione
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.initialOpportunity != null) {
        _showCreateDialog(context, opportunity: widget.initialOpportunity);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final hasSelected = _selected != null;
    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < 560;

        final tableWidget = GTable<Preventivo>(
          rows: _filtered,
          onRowTap: (q) => setState(() => _selected = q),
          isSelected: (q) => _selected?.id == q.id,
          contextActionsForRow: (q) => [
            GContextMenuAction(
              label: 'Apri dettaglio',
              icon: Icons.open_in_new_rounded,
              onSelected: () => setState(() => _selected = q),
            ),
            GContextMenuAction(
              label: 'Genera PDF',
              icon: Icons.picture_as_pdf_outlined,
              onSelected: () => DocumentPdfService.generateForPreventivo(
                context,
                userId: widget.userId,
                teamId: widget.teamInfo?.id,
                preventivo: q,
                company: widget.workspace.companies
                    .where((c) => c.id == q.companyId)
                    .firstOrNull,
                emittente: widget.workspace.billingProfile,
              ),
            ),
            GContextMenuAction(
              label: 'Elimina',
              icon: Icons.delete_outline_rounded,
              destructive: true,
              onSelected: () => _deletePreventivo(q),
            ),
          ],
          emptyLabel: 'Nessun preventivo.',
          emptyIcon: Icons.request_quote_outlined,
          columns: [
            GCol<Preventivo>(
              label: 'Società',
              flex: 3,
              cell: (q) => Text(
                _companyName(q.companyId),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: GussoniBrand.textPrimary,
                ),
              ),
            ),
            GCol<Preventivo>(
              label: 'Opportunità',
              flex: 4,
              cell: (q) => Text(
                _oppTitle(q.opportunityId),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: GussoniBrand.textSecondary),
              ),
            ),
            GCol<Preventivo>(
              label: 'Stato',
              flex: 2,
              cell: (q) => Align(
                alignment: Alignment.centerLeft,
                child: _QuotStatusChip(status: q.status),
              ),
            ),
            GCol<Preventivo>(
              label: 'Istruttoria',
              flex: 2,
              align: TextAlign.right,
              cell: (q) => Align(
                alignment: Alignment.centerRight,
                child: Text(
                  '€ ${NumberFormat('#,##0.00', 'it_IT').format(q.istruttoriaFee)}',
                  style: const TextStyle(color: GussoniBrand.textSecondary),
                ),
              ),
            ),
            GCol<Preventivo>(
              label: 'Totale',
              flex: 2,
              align: TextAlign.right,
              cell: (q) => Align(
                alignment: Alignment.centerRight,
                child: Text(
                  '€ ${NumberFormat('#,##0.00', 'it_IT').format(q.total)}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: GussoniBrand.textPrimary,
                  ),
                ),
              ),
            ),
            GCol<Preventivo>(
              label: 'Creato',
              flex: 2,
              cell: (q) => Text(
                DateFormat('dd/MM/yyyy').format(q.createdAt),
                style: const TextStyle(color: GussoniBrand.textMuted),
              ),
            ),
          ],
        );

        final listContent = GestureDetector(
          behavior: HitTestBehavior.translucent,
          onSecondaryTapDown: widget.showCreateButton
              ? (details) => showGContextMenu(context, details.globalPosition, [
                  GContextMenuAction(
                    label: 'Nuovo preventivo',
                    icon: Icons.request_quote_outlined,
                    onSelected: () => _showCreateDialog(context),
                  ),
                ])
              : null,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.showHeader) ...[
                _Header(
                  userId: widget.userId,
                  repository: widget.repository,
                  workspace: widget.workspace,
                  onCreated: (_) {},
                  showCreateButton: widget.showCreateButton,
                ),
                const SizedBox(height: 12),
              ],
              _FilterBar(
                selected: _filterStatus,
                quotations: widget.workspace.gussoniQuotations,
                onFilter: (s) => setState(() {
                  _filterStatus = s;
                  _selected = null;
                }),
              ),
              const SizedBox(height: 12),
              Expanded(child: tableWidget),
            ],
          ),
        );

        Widget detailWidget(Preventivo q) => _QuotDetail(
          quotation: q,
          workspace: widget.workspace,
          userId: widget.userId,
          teamId: widget.teamInfo?.id,
          repository: widget.repository,
          teamMembers: widget.teamInfo?.activeMembers ?? [],
          onClose: isMobile ? null : () => setState(() => _selected = null),
          onUpdated: (updated) => setState(() => _selected = updated),
          onProjectCreated: widget.onProjectCreated,
        );

        // ── Mobile ─────────────────────────────────────────────────────────
        if (isMobile) {
          return GMobileNavWrapper(
            showDetail: hasSelected,
            list: listContent,
            detail: !hasSelected
                ? const SizedBox.shrink()
                : Column(
                    children: [
                      GMobileBackBar(
                        backLabel: 'Preventivi',
                        title: _companyName(_selected!.companyId),
                        onBack: () => setState(() => _selected = null),
                      ),
                      Expanded(child: detailWidget(_selected!)),
                    ],
                  ),
          );
        }

        // ── Desktop ─────────────────────────────────────────────────────────
        return Row(
          children: [
            Expanded(flex: hasSelected ? 5 : 10, child: listContent),
            if (hasSelected) ...[
              const VerticalDivider(width: 1),
              Expanded(flex: 5, child: detailWidget(_selected!)),
            ],
          ],
        );
      },
    );
  }

  void _showCreateDialog(BuildContext context, {Opportunity? opportunity}) {
    showDialog<void>(
      context: context,
      builder: (_) => CreateQuotDialog(
        userId: widget.userId,
        repository: widget.repository,
        workspace: widget.workspace,
        preselectedOpportunity: opportunity,
      ),
    );
  }

  Future<void> _deletePreventivo(Preventivo preventivo) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => NexoraConfirmDialog(
        title: 'Elimina preventivo?',
        icon: Icons.delete_outline_rounded,
        message: 'Eliminare questo preventivo?',
        confirmLabel: 'Elimina',
        isDanger: true,
      ),
    );
    if (confirmed != true) return;
    await widget.repository.deleteGussoniQuotation(
      widget.userId,
      preventivo.id,
    );
    if (mounted && _selected?.id == preventivo.id) {
      setState(() => _selected = null);
    }
  }
}

// ── Header ──

class _Header extends StatelessWidget {
  const _Header({
    required this.userId,
    required this.repository,
    required this.workspace,
    required this.onCreated,
    this.showCreateButton = true,
  });
  final String userId;
  final ApiWorkspaceRepository repository;
  final WorkspaceSnapshot workspace;
  final void Function(String) onCreated;
  final bool showCreateButton;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Text(
        'Preventivi',
        style: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w700,
          color: GussoniBrand.textPrimary,
        ),
      ),
      const Spacer(),
      if (showCreateButton)
        FilledButton.icon(
          onPressed: () => showDialog<void>(
            context: context,
            builder: (_) => CreateQuotDialog(
              userId: userId,
              repository: repository,
              workspace: workspace,
            ),
          ),
          icon: const Icon(Icons.add, size: 16),
          label: const Text('Nuovo preventivo'),
        ),
    ],
  );
}

// ── Filter bar ──

class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.selected,
    required this.quotations,
    required this.onFilter,
  });
  final PreventivoStatus? selected;
  final List<Preventivo> quotations;
  final void Function(PreventivoStatus?) onFilter;

  static const _tabs = [
    (null, 'Tutti'),
    (PreventivoStatus.draft, 'Bozze'),
    (PreventivoStatus.sent, 'Inviati'),
    (PreventivoStatus.accepted, 'Accettati'),
    (PreventivoStatus.rejected, 'Rifiutati'),
  ];

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: Row(
      children: _tabs.map((t) {
        final isSel = selected == t.$1;
        final count = t.$1 == null
            ? quotations.length
            : quotations.where((q) => q.status == t.$1).length;
        return Padding(
          padding: const EdgeInsets.only(right: 6),
          child: GestureDetector(
            onTap: () => onFilter(t.$1),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                color: isSel ? GussoniBrand.primary : GussoniBrand.surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isSel ? GussoniBrand.primary : GussoniBrand.border,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    t.$2,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: isSel ? Colors.white : GussoniBrand.textSecondary,
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
                        color: isSel
                            ? Colors.white.withOpacity(.25)
                            : GussoniBrand.surfaceSubtle,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '$count',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: isSel ? Colors.white : GussoniBrand.textMuted,
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
  );
}

// ── Lista preventivi ──

class _QuotList extends StatelessWidget {
  const _QuotList({
    required this.quotations,
    required this.companyName,
    required this.oppTitle,
    required this.selected,
    required this.onSelect,
  });
  final List<Preventivo> quotations;
  final String Function(String) companyName;
  final String Function(String) oppTitle;
  final Preventivo? selected;
  final void Function(Preventivo) onSelect;

  @override
  Widget build(BuildContext context) {
    if (quotations.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.request_quote_outlined,
              size: 40,
              color: GussoniBrand.textDisabled,
            ),
            const SizedBox(height: 12),
            Text(
              'Nessun preventivo.',
              style: TextStyle(color: GussoniBrand.textMuted),
            ),
          ],
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 24),
      itemCount: quotations.length,
      separatorBuilder: (_, __) => const SizedBox(height: 4),
      itemBuilder: (_, i) {
        final q = quotations[i];
        final isSel = selected?.id == q.id;
        return _QuotRow(
          quotation: q,
          companyName: companyName(q.companyId),
          oppTitle: oppTitle(q.opportunityId),
          isSelected: isSel,
          onTap: () => onSelect(q),
        );
      },
    );
  }
}

class _QuotRow extends StatelessWidget {
  const _QuotRow({
    required this.quotation,
    required this.companyName,
    required this.oppTitle,
    required this.isSelected,
    required this.onTap,
  });
  final Preventivo quotation;
  final String companyName, oppTitle;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat('#,##0.00', 'it_IT');
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
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    companyName,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: GussoniBrand.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    oppTitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: GussoniBrand.textMuted,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                _QuotStatusChip(status: quotation.status),
                const SizedBox(height: 4),
                Text(
                  'Totale: €${fmt.format(quotation.total)}',
                  style: TextStyle(
                    fontSize: 12,
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
          ],
        ),
      ),
    );
  }
}

// ── Pannello dettaglio preventivo ──

class _QuotDetail extends StatelessWidget {
  const _QuotDetail({
    required this.quotation,
    required this.workspace,
    required this.userId,
    required this.repository,
    required this.teamMembers,
    this.teamId,
    this.onClose,
    this.onUpdated,
    this.onProjectCreated,
  });
  final Preventivo quotation;
  final WorkspaceSnapshot workspace;
  final String userId;
  final ApiWorkspaceRepository repository;
  final List<TeamMember> teamMembers;
  final String? teamId;
  final VoidCallback? onClose;
  final void Function(Preventivo)? onUpdated;
  final void Function(String projectId)? onProjectCreated;

  Company? get _company =>
      workspace.companies.where((c) => c.id == quotation.companyId).firstOrNull;

  Future<void> _generatePdf(BuildContext context) =>
      DocumentPdfService.generateForPreventivo(
        context,
        userId: userId,
        teamId: teamId,
        preventivo: quotation,
        company: _company,
        emittente: workspace.billingProfile,
      );

  Future<void> _sendByEmail(BuildContext context) async {
    final data = DocumentPdfService.preventivoData(
      preventivo: quotation,
      company: _company,
      emittente: workspace.billingProfile,
    );
    final shortId = DocumentPdfService.preventivoShortId(quotation);
    final sent = await showSendEmailDialog(
      context: context,
      userId: userId,
      category: kPreventivo,
      data: data,
      toEmail: _company?.email ?? '',
      signatureHtml: workspace.emailSignatureHtml,
      templateRepo: TemplateRepository(),
      attachmentFileName: 'preventivo_$shortId.pdf',
      buildPdfAttachment: () => DocumentPdfService.buildDocumentPdfBytes(
        context,
        userId: userId,
        teamId: teamId,
        category: kPreventivo,
        docId: quotation.id,
        data: Map<String, dynamic>.from(data),
      ),
      fromEmail: workspace.billingProfile.email,
      fromName: workspace.billingProfile.businessName,
    );
    if (sent == true && quotation.status == PreventivoStatus.draft) {
      await _updateStatus(PreventivoStatus.sent);
    }
  }

  String _companyName() =>
      workspace.companies
          .where((c) => c.id == quotation.companyId)
          .firstOrNull
          ?.name ??
      '—';

  Opportunity? get _opportunity => workspace.opportunities
      .where((o) => o.id == quotation.opportunityId)
      .firstOrNull;

  @override
  Widget build(BuildContext context) {
    final opp = _opportunity;
    final fmt = NumberFormat('#,##0.00', 'it_IT');
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
                Icon(
                  Icons.request_quote_outlined,
                  size: 18,
                  color: GussoniBrand.primary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _companyName(),
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: GussoniBrand.textPrimary,
                        ),
                      ),
                      if (opp != null)
                        Text(
                          opp.title,
                          style: TextStyle(
                            fontSize: 12,
                            color: GussoniBrand.textMuted,
                          ),
                        ),
                    ],
                  ),
                ),
                if (onClose != null)
                  IconButton(
                    onPressed: onClose,
                    icon: const Icon(
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
                  // Stato + azioni
                  _Section(
                    title: 'Stato',
                    children: [
                      Row(
                        children: [
                          _QuotStatusChip(status: quotation.status),
                          const Spacer(),
                          ..._buildActions(context),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Documento: template PDF + azioni
                  _Section(
                    title: 'Documento',
                    children: [
                      TemplatePickerField(
                        userId: userId,
                        category: kPreventivo,
                        docId: quotation.id,
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          _Btn(
                            label: 'PDF',
                            icon: Icons.picture_as_pdf_outlined,
                            color: GussoniBrand.primary,
                            onTap: () => _generatePdf(context),
                          ),
                          const SizedBox(width: 8),
                          _Btn(
                            label: 'Invia',
                            icon: Icons.send_rounded,
                            color: GussoniBrand.success,
                            onTap: () => _sendByEmail(context),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Importi
                  _Section(
                    title: 'Importi',
                    children: [
                      _importRow(
                        'Righe',
                        '€ ${fmt.format(quotation.subtotal)}',
                      ),
                      _importRow(
                        'Istruttoria',
                        '€ ${fmt.format(quotation.istruttoriaFee)}',
                      ),
                      const Divider(height: 20),
                      _importRow(
                        'Totale',
                        '€ ${fmt.format(quotation.total)}',
                        bold: true,
                        color: GussoniBrand.primary,
                      ),
                      const SizedBox(height: 8),
                      _importRow(
                        'Success fee stimata',
                        '€ ${fmt.format(quotation.calculateSuccessFee(opp?.estimatedValue ?? 0))}',
                        color: GussoniBrand.gold,
                      ),
                      Text(
                        '(su contributo stimato €${fmt.format(opp?.estimatedValue ?? 0)} '
                        '· aliquota ${quotation.successFeePercent != null
                            ? "${quotation.successFeePercent!.toStringAsFixed(0)}%"
                            : (opp?.estimatedValue ?? 0) <= 50000
                            ? "9%"
                            : "8%"})',
                        style: TextStyle(
                          fontSize: 11,
                          color: GussoniBrand.textDisabled,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Righe preventivo
                  if (quotation.lines.isNotEmpty)
                    _Section(
                      title: 'Voci',
                      children: [
                        ...quotation.lines.map(
                          (l) => Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    l.description,
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: GussoniBrand.textPrimary,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  '${l.quantity.toStringAsFixed(0)} × €${fmt.format(l.unitPrice)}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: GussoniBrand.textMuted,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  '€ ${fmt.format(l.total)}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: GussoniBrand.textPrimary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  const SizedBox(height: 12),

                  if (quotation.notes.isNotEmpty)
                    _Section(
                      title: 'Note',
                      children: [
                        Text(
                          quotation.notes,
                          style: TextStyle(
                            fontSize: 13,
                            color: GussoniBrand.textSecondary,
                            height: 1.5,
                          ),
                        ),
                      ],
                    ),
                  const SizedBox(height: 12),
                  Text(
                    'Creato il ${DateFormat('dd/MM/yyyy').format(quotation.createdAt)}',
                    style: TextStyle(
                      fontSize: 12,
                      color: GussoniBrand.textDisabled,
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

  Widget _importRow(
    String label,
    String value, {
    bool bold = false,
    Color? color,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(fontSize: 13, color: GussoniBrand.textSecondary),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
            color: color ?? GussoniBrand.textPrimary,
          ),
        ),
      ],
    ),
  );

  List<Widget> _buildActions(BuildContext context) {
    final actions = <Widget>[];
    switch (quotation.status) {
      case PreventivoStatus.draft:
        actions.add(
          _Btn(
            label: 'Segna inviato',
            icon: Icons.send_outlined,
            color: GussoniBrand.info,
            onTap: () => _updateStatus(PreventivoStatus.sent),
          ),
        );
      case PreventivoStatus.sent:
        actions.addAll([
          _Btn(
            label: 'Rifiutato',
            icon: Icons.cancel_outlined,
            color: GussoniBrand.error,
            onTap: () => _updateStatus(PreventivoStatus.rejected),
          ),
          const SizedBox(width: 8),
          _Btn(
            label: 'Accettato →',
            icon: Icons.check_circle_outlined,
            color: GussoniBrand.success,
            onTap: () => _acceptAndCreateProject(context),
          ),
        ]);
      case PreventivoStatus.accepted:
        actions.add(
          _Btn(
            label: 'Crea progetto',
            icon: Icons.folder_open_outlined,
            color: GussoniBrand.primary,
            onTap: () => _showCreateProjectDialog(context),
          ),
        );
      case PreventivoStatus.rejected:
        break;
    }
    return actions;
  }

  Future<void> _updateStatus(PreventivoStatus status) async {
    final updated = Preventivo(
      id: quotation.id,
      opportunityId: quotation.opportunityId,
      companyId: quotation.companyId,
      status: status,
      createdAt: quotation.createdAt,
      lines: quotation.lines,
      istruttoriaFee: quotation.istruttoriaFee,
      successFeePercent: quotation.successFeePercent,
      notes: quotation.notes,
      sentAt: quotation.sentAt,
      acceptedAt: quotation.acceptedAt,
      expiresAt: quotation.expiresAt,
    );
    await repository.updateGussoniQuotation(userId, updated);
    onUpdated?.call(updated);
  }

  Future<void> _acceptAndCreateProject(BuildContext context) async {
    await repository.acceptGussoniQuotation(
      userId,
      quotation.id,
      quotation.opportunityId,
    );
    final updated = Preventivo(
      id: quotation.id,
      opportunityId: quotation.opportunityId,
      companyId: quotation.companyId,
      status: PreventivoStatus.accepted,
      createdAt: quotation.createdAt,
      lines: quotation.lines,
      istruttoriaFee: quotation.istruttoriaFee,
      successFeePercent: quotation.successFeePercent,
      notes: quotation.notes,
    );
    onUpdated?.call(updated);
    if (context.mounted) _showCreateProjectDialog(context);
  }

  Future<void> _showCreateProjectDialog(BuildContext context) async {
    final opp = workspace.opportunities
        .where((o) => o.id == quotation.opportunityId)
        .firstOrNull;
    final company = workspace.companies
        .where((c) => c.id == quotation.companyId)
        .firstOrNull;
    final nameCtrl = TextEditingController(text: opp?.title ?? '');

    // Step 1: conferma nome
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => NexoraDialog(
          title: 'Crea progetto da preventivo',
          icon: Icons.folder_outlined,
          accent: GussoniBrand.success,
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: GussoniBrand.successBg,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: GussoniBrand.successBorder),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.check_circle_outline,
                      size: 16,
                      color: GussoniBrand.success,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Preventivo accettato per ${company?.name ?? "—"}.',
                        style: const TextStyle(
                          fontSize: 13,
                          color: GussoniBrand.success,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: nameCtrl,
                autofocus: true,
                onChanged: (_) => setSt(() {}),
                decoration: NexoraDialog.fieldDecoration('Nome progetto *'),
              ),
              const SizedBox(height: 4),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              style: NexoraDialog.cancelButtonStyle(),
              child: const Text('Annulla'),
            ),
            FilledButton.icon(
              onPressed: nameCtrl.text.trim().isEmpty
                  ? null
                  : () => Navigator.of(ctx).pop(true),
              icon: const Icon(Icons.chevron_right, size: 16),
              label: const Text('Avanti'),
              style: NexoraDialog.primaryButtonStyle(
                color: GussoniBrand.success,
              ),
            ),
          ],
        ),
      ),
    );

    if (ok != true || !context.mounted) {
      nameCtrl.dispose();
      return;
    }

    final name = nameCtrl.text.trim();
    nameCtrl.dispose();
    final projectType = company?.companyType == CompanyType.nonProfit
        ? ProjectType.noProfit
        : ProjectType.profit;

    // Step 2: template o progetto vuoto
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ProjectWizardDialog(
        projectName: name,
        projectType: projectType,
        companyId: quotation.companyId,
        companyName: company?.name,
        opportunityId: quotation.opportunityId,
        quotationId: quotation.id,
        userId: userId,
        repository: repository,
        teamMembers: teamMembers,
        templates: workspace.youdoxConfig.projectTemplates,
        onCreated: (id) async {
          onProjectCreated?.call(id);
          // Step 3: anticipo
          if (context.mounted) {
            await showDialog<void>(
              context: context,
              barrierDismissible: false,
              builder: (_) => _AnticipoDialog(
                projectId: id,
                companyId: quotation.companyId,
                totalePreventivo: quotation.total,
                userId: userId,
                repository: repository,
                onDone: () {},
              ),
            );
          }
        },
      ),
    );
  }
}

// ── Dialog crea preventivo ──

/// Dialog di creazione preventivo: popup unico, sempre collegato a una
/// opportunità (selezionata via dropdown col nome della società).
class CreateQuotDialog extends StatefulWidget {
  const CreateQuotDialog({
    super.key,
    required this.userId,
    required this.repository,
    required this.workspace,
    this.preselectedOpportunity,
  });
  final String userId;
  final ApiWorkspaceRepository repository;
  final WorkspaceSnapshot workspace;
  final Opportunity? preselectedOpportunity;

  @override
  State<CreateQuotDialog> createState() => _CreateQuotDialogState();
}

class _CreateQuotDialogState extends State<CreateQuotDialog> {
  String? _oppId;
  String? _companyId;
  final _istruttoriaCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  final _lines = <_LineItem>[];
  String? _pdfTemplateId;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.preselectedOpportunity != null) {
      _oppId = widget.preselectedOpportunity!.id;
      _companyId = widget.preselectedOpportunity!.companyId;
    }
    _lines.add(_LineItem());
  }

  @override
  void dispose() {
    _istruttoriaCtrl.dispose();
    _notesCtrl.dispose();
    for (final l in _lines) l.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_oppId == null) {
      setState(() => _error = 'Seleziona un\'opportunità.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final compId =
          _companyId ??
          widget.workspace.opportunities
              .where((o) => o.id == _oppId)
              .firstOrNull
              ?.companyId ??
          '';
      final quotLines = _lines
          .where((l) => l.descCtrl.text.isNotEmpty)
          .map(
            (l) => PreventivoLine(
              description: l.descCtrl.text.trim(),
              quantity: double.tryParse(l.qtyCtrl.text) ?? 1,
              unitPrice:
                  double.tryParse(l.priceCtrl.text.replaceAll(',', '.')) ?? 0,
            ),
          )
          .toList();
      final newId = await widget.repository.createGussoniQuotation(
        widget.userId,
        Preventivo(
          id: '',
          opportunityId: _oppId!,
          companyId: compId,
          status: PreventivoStatus.draft,
          createdAt: DateTime.now(),
          lines: quotLines,
          istruttoriaFee:
              double.tryParse(_istruttoriaCtrl.text.replaceAll(',', '.')) ?? 0,
          notes: _notesCtrl.text.trim(),
        ),
      );
      if (_pdfTemplateId != null) {
        await TemplateRepository().setDocTemplateChoice(
          widget.userId,
          newId,
          _pdfTemplateId,
        );
      }
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
      title: 'Nuovo preventivo',
      icon: Icons.request_quote_outlined,
      width: 580,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DropdownButtonFormField<String>(
            value: _oppId,
            decoration: NexoraDialog.fieldDecoration('Opportunità *'),
            items: widget.workspace.opportunities
                .where(
                  (o) =>
                      o.status == OpportunityStatus.inAttesa ||
                      o.status == OpportunityStatus.preventivazione ||
                      o.id == _oppId,
                )
                .map((o) {
                  final companyName = widget.workspace.companies
                      .where((c) => c.id == o.companyId)
                      .firstOrNull
                      ?.name;
                  return DropdownMenuItem(
                    value: o.id,
                    child: Text(
                      companyName == null || companyName.isEmpty
                          ? o.title
                          : '${o.title} — $companyName',
                      overflow: TextOverflow.ellipsis,
                    ),
                  );
                })
                .toList(),
            onChanged: (v) {
              setState(() {
                _oppId = v;
                _companyId = widget.workspace.opportunities
                    .where((o) => o.id == v)
                    .firstOrNull
                    ?.companyId;
              });
            },
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              const Expanded(
                child: Text(
                  'VOCI PREVENTIVO',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                    color: GussoniBrand.textMuted,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: () => setState(() => _lines.add(_LineItem())),
                icon: const Icon(Icons.add, size: 14),
                label: const Text('Aggiungi voce'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ..._lines.asMap().entries.map((e) {
            final idx = e.key;
            final l = e.value;
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  Expanded(
                    flex: 4,
                    child: TextField(
                      controller: l.descCtrl,
                      decoration: NexoraDialog.fieldDecoration('Descrizione'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 64,
                    child: TextField(
                      controller: l.qtyCtrl,
                      decoration: NexoraDialog.fieldDecoration('Qtà'),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: l.priceCtrl,
                      decoration: NexoraDialog.fieldDecoration(
                        'Prezzo €',
                        prefix: '€ ',
                      ),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                  if (_lines.length > 1)
                    IconButton(
                      icon: const Icon(
                        Icons.remove_circle_outline,
                        size: 18,
                        color: GussoniBrand.error,
                      ),
                      onPressed: () => setState(() {
                        _lines[idx].dispose();
                        _lines.removeAt(idx);
                      }),
                    ),
                ],
              ),
            );
          }),
          const SizedBox(height: 6),
          TextField(
            controller: _istruttoriaCtrl,
            decoration: NexoraDialog.fieldDecoration(
              'Quota istruttoria (€)',
              prefix: '€ ',
            ),
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: 12),
          TemplatePickerField(
            userId: widget.userId,
            category: kPreventivo,
            value: _pdfTemplateId,
            onChanged: (id) => setState(() => _pdfTemplateId = id),
          ),
          const SizedBox(height: 12),
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
              : const Text('Crea preventivo'),
        ),
      ],
    );
  }
}

// ── Dialog crea progetto da preventivo accettato ──

class _CreateProjectFromQuotDialog extends StatefulWidget {
  const _CreateProjectFromQuotDialog({
    required this.quotation,
    required this.workspace,
    required this.userId,
    required this.repository,
    this.onCreated,
  });
  final Preventivo quotation;
  final WorkspaceSnapshot workspace;
  final String userId;
  final ApiWorkspaceRepository repository;
  final void Function(String)? onCreated;

  @override
  State<_CreateProjectFromQuotDialog> createState() =>
      _CreateProjectFromQuotDialogState();
}

class _CreateProjectFromQuotDialogState
    extends State<_CreateProjectFromQuotDialog> {
  final _nameCtrl = TextEditingController();
  ProjectType _type = ProjectType.profit;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Pre-popola il nome dal titolo dell'opportunità
    final opp = widget.workspace.opportunities
        .where((o) => o.id == widget.quotation.opportunityId)
        .firstOrNull;
    if (opp != null) _nameCtrl.text = opp.title;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_nameCtrl.text.trim().isEmpty) {
      setState(() => _error = 'Inserisci un nome per il progetto.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final id = await widget.repository.createProjectFromQuotation(
        userId: widget.userId,
        name: _nameCtrl.text.trim(),
        companyId: widget.quotation.companyId,
        opportunityId: widget.quotation.opportunityId,
        quotationId: widget.quotation.id,
        type: _type,
      );
      if (!mounted) return;
      // Chiudi il dialog di creazione progetto
      Navigator.of(context).pop();
      // Mostra subito il dialog anticipo
      if (mounted) {
        await showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (_) => _AnticipoDialog(
            projectId: id,
            companyId: widget.quotation.companyId,
            totalePreventivo: widget.quotation.total,
            userId: widget.userId,
            repository: widget.repository,
            onDone: () => widget.onCreated?.call(id),
          ),
        );
      }
    } catch (e) {
      setState(() {
        _error = e.toString();
        _saving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final company = widget.workspace.companies
        .where((c) => c.id == widget.quotation.companyId)
        .firstOrNull;
    return NexoraDialog(
      title: 'Crea progetto da preventivo',
      icon: Icons.folder_outlined,
      accent: GussoniBrand.success,
      width: 480,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: GussoniBrand.successBg,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: GussoniBrand.successBorder),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.check_circle_outlined,
                  size: 16,
                  color: GussoniBrand.success,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Preventivo accettato per ${company?.name ?? "—"}. '
                    'Verranno create automaticamente le 4 fasi standard.',
                    style: const TextStyle(
                      fontSize: 12,
                      color: GussoniBrand.success,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _nameCtrl,
            decoration: NexoraDialog.fieldDecoration('Nome progetto *'),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<ProjectType>(
            value: _type,
            decoration: NexoraDialog.fieldDecoration('Tipologia'),
            items: const [
              DropdownMenuItem(
                value: ProjectType.profit,
                child: Text('Profit'),
              ),
              DropdownMenuItem(
                value: ProjectType.noProfit,
                child: Text('No-Profit'),
              ),
            ],
            onChanged: (v) => setState(() => _type = v ?? ProjectType.profit),
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
          style: NexoraDialog.primaryButtonStyle(color: GussoniBrand.success),
          child: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text('Crea progetto'),
        ),
      ],
    );
  }
}

// ── Shared widgets ──

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(.25)),
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

class _Btn extends StatelessWidget {
  const _Btn({
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
  Widget build(BuildContext context) => OutlinedButton.icon(
    onPressed: onTap,
    icon: Icon(icon, size: 14),
    label: Text(label, style: const TextStyle(fontSize: 12)),
    style: OutlinedButton.styleFrom(
      foregroundColor: color,
      side: BorderSide(color: color.withOpacity(.5)),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    ),
  );
}

class _LineItem {
  final descCtrl = TextEditingController();
  final qtyCtrl = TextEditingController(text: '1');
  final priceCtrl = TextEditingController();
  void dispose() {
    descCtrl.dispose();
    qtyCtrl.dispose();
    priceCtrl.dispose();
  }
}

// ── Dialog Anticipo / Avvio Servizio ─────────────────────────────────────────

class _AnticipoDialog extends StatefulWidget {
  const _AnticipoDialog({
    required this.projectId,
    required this.companyId,
    required this.totalePreventivo,
    required this.userId,
    required this.repository,
    required this.onDone,
  });

  final String projectId;
  final String companyId;
  final double totalePreventivo;
  final String userId;
  final ApiWorkspaceRepository repository;
  final VoidCallback onDone;

  @override
  State<_AnticipoDialog> createState() => _AnticipoDialogState();
}

class _AnticipoDialogState extends State<_AnticipoDialog> {
  final _percCtrl = TextEditingController(text: '30');
  bool _saving = false;

  double get _perc => double.tryParse(_percCtrl.text.replaceAll(',', '.')) ?? 0;
  double get _importo => widget.totalePreventivo * _perc / 100;

  final _eur = NumberFormat.currency(
    locale: 'it_IT',
    symbol: '€',
    decimalDigits: 2,
  );

  Future<void> _crea() async {
    if (_perc <= 0 || _perc > 100) return;
    setState(() => _saving = true);
    try {
      final now = DateTime.now();
      final invoiceId = 'inv-ant-${now.microsecondsSinceEpoch}';
      final draft = InvoiceDraft(
        id: invoiceId,
        companyId: widget.companyId,
        projectId: widget.projectId,
        number: 'BOZZA-ANT',
        amount: _importo,
        status: InvoiceStatus.draft,
        notes:
            'Anticipo/Avvio Servizio — ${_perc.toStringAsFixed(0)}% del totale preventivo',
        createdAt: now,
        lines: [
          InvoiceLine(
            description:
                'Anticipo/Avvio Servizio (${_perc.toStringAsFixed(0)}%)',
            quantity: 1,
            unitPrice: _importo,
          ),
        ],
      );
      await widget.repository.saveInvoice(widget.userId, invoice: draft);
      await widget.repository.setAnticipoEmesso(
        widget.userId,
        widget.projectId,
      );
    } finally {
      if (mounted) {
        Navigator.of(context).pop();
        widget.onDone();
      }
    }
  }

  void _salta() {
    Navigator.of(context).pop();
    widget.onDone();
  }

  @override
  void dispose() {
    _percCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return NexoraDialog(
      title: 'Fattura anticipo / avvio servizio',
      icon: Icons.receipt_long_outlined,
      width: 500,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: GussoniBrand.primaryBg,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: GussoniBrand.primaryBorder),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, size: 16, color: GussoniBrand.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Progetto creato. Vuoi emettere subito una fattura in bozza per l\'anticipo di avvio servizio?',
                    style: TextStyle(fontSize: 13, color: GussoniBrand.primary),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              const Text(
                'Totale preventivo:',
                style: TextStyle(fontSize: 13, color: GussoniBrand.textMuted),
              ),
              const Spacer(),
              Text(
                _eur.format(widget.totalePreventivo),
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: GussoniBrand.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: TextField(
                  controller: _percCtrl,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: NexoraDialog.fieldDecoration(
                    '% Anticipo',
                    suffix: '%',
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 20),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Text(
                    'Importo bozza',
                    style: TextStyle(
                      fontSize: 11,
                      color: GussoniBrand.textMuted,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _eur.format(_importo),
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      color: GussoniBrand.success,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: GussoniBrand.surfaceSubtle,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: GussoniBrand.border),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.receipt_outlined,
                  size: 14,
                  color: GussoniBrand.textMuted,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Voce fattura: "Anticipo/Avvio Servizio (${_perc.toStringAsFixed(0)}%)"',
                    style: const TextStyle(
                      fontSize: 12,
                      color: GussoniBrand.textMuted,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : _salta,
          style: NexoraDialog.cancelButtonStyle(),
          child: const Text('Salta per ora'),
        ),
        FilledButton.icon(
          onPressed: (_saving || _perc <= 0 || _perc > 100) ? null : _crea,
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
          label: const Text('Crea bozza fattura'),
          style: NexoraDialog.primaryButtonStyle(),
        ),
      ],
    );
  }
}
