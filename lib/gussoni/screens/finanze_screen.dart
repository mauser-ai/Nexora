import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../app/nexora_dialog.dart';
import '../../brand_config.dart';
import '../../data/api_workspace_repository.dart';
import '../../models/domain_models.dart';
import '../widgets/g_table.dart';
import '../../data/template_repository.dart';
import '../../models/template_models.dart';
import '../../settings/document_pdf_service.dart';
import '../../settings/send_email_dialog.dart';
import '../../settings/template_picker_field.dart';

class FinanzeGussoniScreen extends StatefulWidget {
  const FinanzeGussoniScreen({
    super.key,
    required this.workspace,
    required this.userId,
    required this.repository,
    this.onCreateInvoice,
    this.onEditInvoice,
    this.onExportXml,
    this.showHeader = true,
    this.showCreateButton = true,
    this.isPinned = false,
    this.onPinContext,
  });
  final WorkspaceSnapshot workspace;
  final String userId;
  final ApiWorkspaceRepository repository;
  final VoidCallback? onCreateInvoice;
  final void Function(InvoiceDraft)? onEditInvoice;
  final void Function(InvoiceDraft)? onExportXml;
  final bool showHeader;
  final bool showCreateButton;
  final bool isPinned;
  final VoidCallback? onPinContext;

  @override
  State<FinanzeGussoniScreen> createState() => _FinanzeGussoniScreenState();
}

class _FinanzeGussoniScreenState extends State<FinanzeGussoniScreen> {
  InvoiceStatus? _statusFilter;
  bool _onlySuccessFee = false;
  String _search = '';
  InvoiceDraft? _selected;

  final _fmt = NumberFormat('#,##0.00', 'it_IT');

  Future<void> _sendInvoiceEmail(InvoiceDraft inv) async {
    final company = widget.workspace.companies
        .where((c) => c.id == inv.companyId)
        .firstOrNull;
    final data = DocumentPdfService.invoiceData(
      invoice: inv,
      company: company,
      emittente: widget.workspace.billingProfile,
    );
    await showSendEmailDialog(
      context: context,
      userId: widget.userId,
      category: kFattura,
      data: data,
      toEmail: company?.email ?? '',
      signatureHtml: widget.workspace.emailSignatureHtml,
      templateRepo: TemplateRepository(),
      attachmentFileName: 'fattura_${inv.number.replaceAll('/', '-')}.pdf',
      buildPdfAttachment: () => DocumentPdfService.buildDocumentPdfBytes(
        context,
        userId: widget.userId,
        category: kFattura,
        docId: inv.id,
        data: Map<String, dynamic>.from(data),
      ),
      fromEmail: widget.workspace.billingProfile.email,
      fromName: widget.workspace.billingProfile.businessName,
    );
  }

  List<InvoiceDraft> get _filtered => widget.workspace.invoiceDrafts
      .where(
        (i) =>
            (_statusFilter == null || i.status == _statusFilter) &&
            (!_onlySuccessFee || i.isSuccessFee) &&
            (_search.isEmpty ||
                i.number.toLowerCase().contains(_search.toLowerCase()) ||
                _companyName(
                  i.companyId,
                ).toLowerCase().contains(_search.toLowerCase())),
      )
      .toList();

  String _companyName(String id) =>
      widget.workspace.companies.where((c) => c.id == id).firstOrNull?.name ??
      '—';

  double get _totalAmount => _filtered.fold(0, (s, i) => s + i.amount);

  @override
  Widget build(BuildContext context) {
    final cols = <GCol<InvoiceDraft>>[
      GCol(
        label: 'N. Fattura',
        flex: 2,
        cell: (i) => Row(
          children: [
            if (i.isSuccessFee) ...[
              Icon(Icons.star_outline, size: 12, color: GussoniBrand.gold),
              const SizedBox(width: 4),
            ],
            GCellText(i.number, bold: true),
          ],
        ),
      ),
      GCol(
        label: 'Cliente',
        flex: 3,
        cell: (i) => GCellText(_companyName(i.companyId), muted: true),
      ),
      GCol(
        label: 'Importo',
        flex: 2,
        cell: (i) => Text(
          '€ ${_fmt.format(i.amount)}',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: i.isSuccessFee
                ? GussoniBrand.gold
                : GussoniBrand.textPrimary,
          ),
        ),
      ),
      GCol(
        label: 'Tipo',
        flex: 2,
        cell: (i) => i.isSuccessFee
            ? GStatusChip(
                label: 'Success fee',
                color: GussoniBrand.gold,
                small: true,
              )
            : GStatusChip(
                label: 'Istruttoria',
                color: GussoniBrand.primary,
                small: true,
              ),
      ),
      GCol(
        label: 'Stato',
        flex: 2,
        cell: (i) => GStatusChip(
          label: _statusLabel(i.status),
          color: _statusColor(i.status),
          small: true,
        ),
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < 760;

        final listPane = GScreenLayout(
          title: 'Fatture',
          count: _filtered.length,
          subtitle: 'Totale filtrato: € ${_fmt.format(_totalAmount)}',
          showHeader: widget.showHeader,
          isPinned: widget.isPinned,
          onPinContext: widget.onPinContext,
          contextActions: () => [
            if (widget.onCreateInvoice != null)
              GContextMenuAction(
                label: 'Nuova fattura',
                icon: Icons.add_rounded,
                onSelected: widget.onCreateInvoice!,
              ),
          ],
          action: widget.showCreateButton
              ? FilledButton.icon(
                  onPressed: widget.onCreateInvoice,
                  icon: const Icon(Icons.add, size: 16),
                  label: Text(isMobile ? 'Nuova' : 'Nuova fattura'),
                )
              : null,
          filters: Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              GFilterPills<InvoiceStatus?>(
                items: const [
                  null,
                  InvoiceStatus.draft,
                  InvoiceStatus.readyForXml,
                  InvoiceStatus.exported,
                ],
                selected: _statusFilter,
                onSelect: (s) => setState(() {
                  _statusFilter = s;
                  _selected = null;
                }),
                labelOf: (s) => s == null ? 'Tutte' : _statusLabel(s),
                countOf: (s) => s == null
                    ? widget.workspace.invoiceDrafts.length
                    : widget.workspace.invoiceDrafts
                          .where((i) => i.status == s)
                          .length,
              ),
              FilterChip(
                label: const Text('Solo success fee'),
                selected: _onlySuccessFee,
                onSelected: (v) => setState(() {
                  _onlySuccessFee = v;
                  _selected = null;
                }),
                selectedColor: GussoniBrand.goldBg,
                checkmarkColor: GussoniBrand.gold,
              ),
            ],
          ),
          searchHint: 'Cerca per numero, cliente…',
          onSearch: (v) => setState(() {
            _search = v;
            _selected = null;
          }),
          body: GTable<InvoiceDraft>(
            columns: cols,
            rows: _filtered,
            isSelected: (i) => _selected?.id == i.id,
            onRowTap: (i) => setState(() => _selected = i),
            contextActionsForRow: (i) => [
              GContextMenuAction(
                label: 'Apri dettaglio',
                icon: Icons.open_in_new_rounded,
                onSelected: () => setState(() => _selected = i),
              ),
              GContextMenuAction(
                label: 'Genera PDF',
                icon: Icons.picture_as_pdf_outlined,
                onSelected: () => DocumentPdfService.generateForInvoice(
                  context,
                  userId: widget.userId,
                  invoice: i,
                  company: widget.workspace.companies
                      .where((c) => c.id == i.companyId)
                      .firstOrNull,
                  emittente: widget.workspace.billingProfile,
                ),
              ),
              if (widget.onEditInvoice != null)
                GContextMenuAction(
                  label: 'Modifica',
                  icon: Icons.edit_outlined,
                  onSelected: () => widget.onEditInvoice!(i),
                ),
              if (widget.onExportXml != null &&
                  i.status == InvoiceStatus.readyForXml)
                GContextMenuAction(
                  label: 'Esporta XML',
                  icon: Icons.file_download_outlined,
                  onSelected: () => widget.onExportXml!(i),
                ),
              GContextMenuAction(
                label: 'Elimina',
                icon: Icons.delete_outline_rounded,
                destructive: true,
                onSelected: () => _deleteInvoice(i),
              ),
            ],
            emptyLabel: 'Nessuna fattura trovata.',
            emptyIcon: Icons.receipt_long_outlined,
          ),
        );

        Widget detailPanel(InvoiceDraft inv) => GDetailPanel(
          title: inv.number,
          subtitle: _companyName(inv.companyId),
          icon: Icon(
            inv.isSuccessFee ? Icons.star_outline : Icons.receipt_long_outlined,
            size: 18,
            color: inv.isSuccessFee ? GussoniBrand.gold : GussoniBrand.primary,
          ),
          onClose: isMobile ? null : () => setState(() => _selected = null),
          actions: [
            IconButton(
              tooltip: 'Genera PDF',
              onPressed: () => DocumentPdfService.generateForInvoice(
                context,
                userId: widget.userId,
                invoice: inv,
                company: widget.workspace.companies
                    .where((c) => c.id == inv.companyId)
                    .firstOrNull,
                emittente: widget.workspace.billingProfile,
              ),
              icon: Icon(
                Icons.picture_as_pdf_outlined,
                size: 16,
                color: GussoniBrand.primary,
              ),
            ),
            IconButton(
              tooltip: 'Invia via email',
              onPressed: () => _sendInvoiceEmail(inv),
              icon: const Icon(
                Icons.send_rounded,
                size: 16,
                color: GussoniBrand.success,
              ),
            ),
            if (widget.onEditInvoice != null)
              IconButton(
                onPressed: () => widget.onEditInvoice!(inv),
                icon: const Icon(
                  Icons.edit_outlined,
                  size: 16,
                  color: GussoniBrand.textMuted,
                ),
              ),
            if (widget.onExportXml != null &&
                inv.status == InvoiceStatus.readyForXml)
              IconButton(
                onPressed: () => widget.onExportXml!(inv),
                icon: const Icon(
                  Icons.file_download_outlined,
                  size: 16,
                  color: GussoniBrand.info,
                ),
                tooltip: 'Esporta XML',
              ),
          ],
          children: [
            GDetailSection(
              title: 'Documento',
              children: [
                TemplatePickerField(
                  userId: widget.userId,
                  category: kFattura,
                  docId: inv.id,
                ),
              ],
            ),
            GDetailSection(
              title: 'Fattura',
              children: [
                GInfoRow('Numero', inv.number),
                GInfoRow('Cliente', _companyName(inv.companyId)),
                GInfoRow(
                  'Importo',
                  '€ ${_fmt.format(inv.amount)}',
                  valueColor: inv.isSuccessFee
                      ? GussoniBrand.gold
                      : GussoniBrand.primary,
                ),
                GInfoRow(
                  'Stato',
                  _statusLabel(inv.status),
                  valueColor: _statusColor(inv.status),
                ),
                GInfoRow(
                  'Tipo',
                  inv.isSuccessFee ? 'Success fee' : 'Istruttoria',
                ),
                if (inv.grantAmount != null)
                  GInfoRow('Contributo', '€ ${_fmt.format(inv.grantAmount)}'),
              ],
            ),
            if (inv.lines.isNotEmpty)
              GDetailSection(
                title: 'Righe',
                children: [
                  ...inv.lines.map(
                    (l) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 10,
                        runSpacing: 4,
                        children: [
                          ConstrainedBox(
                            constraints: BoxConstraints(
                              maxWidth: isMobile
                                  ? (constraints.maxWidth - 72)
                                        .clamp(160.0, double.infinity)
                                        .toDouble()
                                  : 260,
                            ),
                            child: Text(
                              l.description,
                              style: const TextStyle(
                                fontSize: 12,
                                color: GussoniBrand.textSecondary,
                                height: 1.35,
                              ),
                            ),
                          ),
                          Text(
                            '€ ${_fmt.format(l.net)}',
                            style: const TextStyle(
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
            if (inv.notes.isNotEmpty)
              GDetailSection(
                title: 'Note',
                children: [
                  Text(
                    inv.notes,
                    style: const TextStyle(
                      fontSize: 12,
                      color: GussoniBrand.textSecondary,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
          ],
        );

        // ── Mobile ───────────────────────────────────────────────────────────
        if (isMobile) {
          return GMobileNavWrapper(
            showDetail: _selected != null,
            list: listPane,
            detail: _selected == null
                ? const SizedBox.shrink()
                : Column(
                    children: [
                      GMobileBackBar(
                        backLabel: 'Fatture',
                        title: _selected!.number,
                        onBack: () => setState(() => _selected = null),
                      ),
                      Expanded(child: detailPanel(_selected!)),
                    ],
                  ),
          );
        }

        // ── Desktop ──────────────────────────────────────────────────────────
        return Row(
          children: [
            Expanded(flex: _selected != null ? 6 : 10, child: listPane),
            if (_selected != null) ...[
              const VerticalDivider(width: 1),
              Expanded(flex: 4, child: detailPanel(_selected!)),
            ],
          ],
        );
      },
    );
  }

  Future<void> _deleteInvoice(InvoiceDraft invoice) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => NexoraConfirmDialog(
        title: 'Elimina fattura?',
        icon: Icons.delete_outline_rounded,
        message: 'Eliminare la fattura "${invoice.number}"?',
        confirmLabel: 'Elimina',
        isDanger: true,
      ),
    );
    if (confirmed != true) return;
    await widget.repository.deleteInvoice(widget.userId, invoice.id);
    if (mounted && _selected?.id == invoice.id) {
      setState(() => _selected = null);
    }
  }

  static String _statusLabel(InvoiceStatus s) => switch (s) {
    InvoiceStatus.draft => 'Bozza',
    InvoiceStatus.readyForXml => 'Pronta per XML',
    InvoiceStatus.exported => 'Inviata',
  };

  static Color _statusColor(InvoiceStatus s) => switch (s) {
    InvoiceStatus.draft => GussoniBrand.textMuted,
    InvoiceStatus.readyForXml => GussoniBrand.warning,
    InvoiceStatus.exported => GussoniBrand.success,
  };
}
