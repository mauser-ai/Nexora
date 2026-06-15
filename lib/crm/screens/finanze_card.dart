import '../../brand_config.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/domain_models.dart';
import '../../data/firestore_workspace_repository.dart';
import 'tl_table.dart';

class FinanzeCard extends StatefulWidget {
  const FinanzeCard({
    super.key,
    required this.workspace,
    required this.onCreateInvoice,
    required this.onEditInvoice,
    required this.onDeleteInvoice,
    required this.onExportXml,
    this.onOpenDetail,
  });

  final WorkspaceSnapshot workspace;
  final VoidCallback onCreateInvoice;
  final Future<void> Function(InvoiceDraft) onEditInvoice;
  final Future<void> Function(InvoiceDraft) onDeleteInvoice;
  final Future<void> Function(InvoiceDraft) onExportXml;
  final void Function(InvoiceDraft)? onOpenDetail;

  @override
  State<FinanzeCard> createState() => _FinanzeCardState();
}

class _FinanzeCardState extends State<FinanzeCard> {
  String? _statusFilter;
  final _currFmt = NumberFormat.currency(locale: 'it_IT', symbol: '€', decimalDigits: 2);

  static const _statusFilters = [
    TlStatusFilter(label: 'Bozza', value: 'draft', color: Color(0xFF7D89A8)),
    TlStatusFilter(label: 'Pronta XML', value: 'readyForXml', color: Color(0xFF0369A1)),
    TlStatusFilter(label: 'Esportata', value: 'exported', color: Color(0xFF034F3B)),
  ];

  Color _statusColor(InvoiceStatus s) {
    switch (s) {
      case InvoiceStatus.draft: return const Color(0xFF7D89A8);
      case InvoiceStatus.readyForXml: return const Color(0xFF0369A1);
      case InvoiceStatus.exported: return GussoniBrand.primary;
    }
  }

  String _statusLabel(InvoiceStatus s) {
    switch (s) {
      case InvoiceStatus.draft: return 'Bozza';
      case InvoiceStatus.readyForXml: return 'Pronta XML';
      case InvoiceStatus.exported: return 'Esportata';
    }
  }

  String _companyName(InvoiceDraft inv) =>
      widget.workspace.companies.where((c) => c.id == inv.companyId).firstOrNull?.name ?? '—';

  List<TlRow> get _rows {
    var invoices = widget.workspace.invoiceDrafts;
    if (_statusFilter != null) {
      final s = InvoiceStatus.values.firstWhere((v) => v.name == _statusFilter, orElse: () => InvoiceStatus.draft);
      invoices = invoices.where((i) => i.status == s).toList();
    }
    return invoices.map((inv) => TlRow(
      key: inv.id,
      onTap: () => widget.onOpenDetail != null ? widget.onOpenDetail!(inv) : widget.onEditInvoice(inv),
      cells: [
        TlCell(widget: TlPrimaryCell(text: inv.number.isEmpty ? '—' : inv.number)),
        TlCell(text: _companyName(inv)),
        TlCell(widget: TlBadge(label: _statusLabel(inv.status), color: _statusColor(inv.status))),
        TlCell(widget: TlAmountCell(text: _currFmt.format(inv.amount)), align: TextAlign.right),
        TlCell(widget: TlRowActions(items: [
          PopupMenuItem(value: 'edit', child: const Text('Modifica'), onTap: () => widget.onEditInvoice(inv)),
          if (inv.status != InvoiceStatus.exported)
            PopupMenuItem(value: 'xml', child: const Text('Esporta XML FatturaPA'), onTap: () => widget.onExportXml(inv)),
          const PopupMenuDivider(),
          PopupMenuItem(value: 'delete', child: const Text('Elimina', style: TextStyle(color: Color(0xFFB91C1C))), onTap: () => widget.onDeleteInvoice(inv)),
        ])),
      ],
    )).toList();
  }

  @override
  Widget build(BuildContext context) {
    // Totale fatture visibili
    final filtered = _statusFilter == null
        ? widget.workspace.invoiceDrafts
        : widget.workspace.invoiceDrafts.where((i) => i.status.name == _statusFilter).toList();
    final total = filtered.fold(0.0, (s, i) => s + i.amount);

    return TlTable(
      searchHint: 'Cerca fatture...',
      columns: const [
        TlColumn(label: 'Numero fattura', flex: 2),
        TlColumn(label: 'Cliente', flex: 3),
        TlColumn(label: 'Stato', flex: 1),
        TlColumn(label: 'Importo', flex: 1, align: TextAlign.right),
        TlColumn(label: '', minWidth: 40),
      ],
      rows: _rows,
      statusFilters: _statusFilters,
      selectedStatus: _statusFilter,
      onStatusChanged: (v) => setState(() => _statusFilter = v),
      onAdd: widget.onCreateInvoice,
      addLabel: 'Nuova fattura',
      emptyMessage: 'Nessuna fattura trovata.',
      extraActions: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(color: const Color(0xFFF0FDF4), borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFFBBF7D0))),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.euro, size: 14, color: Color(0xFF034F3B)),
          const SizedBox(width: 4),
          Text('Totale: ${_currFmt.format(total)}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Color(0xFF034F3B))),
        ]),
      ),
    );
  }
}
