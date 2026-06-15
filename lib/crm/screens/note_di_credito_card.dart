import '../../brand_config.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/domain_models.dart';
import '../../data/firestore_workspace_repository.dart';
import '../data/firestore_crm_repository.dart';
import '../models/crm_extra_models.dart';
import 'tl_table.dart';

// ────────────────────────────────────────────────
// Note di credito – Credit Notes
// Teamleader: credit_note_number, status booked|draft,
// invoice (original ref), invoicee.customer, lines
// ────────────────────────────────────────────────

class NoteDiCreditoCard extends StatefulWidget {
  const NoteDiCreditoCard({
    super.key,
    required this.crmData,
    required this.companies,
    required this.workspace,
    required this.crmRepo,
    required this.userId,
  });

  final CrmData crmData;
  final List<Company> companies;
  final WorkspaceSnapshot workspace;
  final FirestoreCrmRepository crmRepo;
  final String userId;

  @override
  State<NoteDiCreditoCard> createState() => _NoteDiCreditoCardState();
}

class _NoteDiCreditoCardState extends State<NoteDiCreditoCard> {
  String? _statusFilter;
  final _currFmt = NumberFormat.currency(locale: 'it_IT', symbol: '€', decimalDigits: 2);
  final _dateFmt = DateFormat('dd/MM/yyyy');

  static final _statusFilters = [
    TlStatusFilter(label: 'Bozza', value: 'draft', color: Color(0xFF7D89A8)),
    TlStatusFilter(label: 'Registrata', value: 'booked', color: GussoniBrand.primary),
  ];

  String _customerName(CreditNote cn) {
    if (cn.customerId == null) return '—';
    return widget.companies.where((c) => c.id == cn.customerId).firstOrNull?.name ?? '—';
  }

  /// Recupera il numero della fattura originale stornata
  String? _originalInvoiceNumber(CreditNote cn) {
    if (cn.invoiceId == null) return null;
    // cerca nelle InvoiceDraft del workspace
    return widget.workspace.invoiceDrafts
        .where((inv) => inv.id == cn.invoiceId)
        .firstOrNull?.number;
  }

  List<TlRow> get _rows {
    var list = widget.crmData.creditNotes;
    if (_statusFilter != null) {
      final status = _statusFilter == 'draft' ? CreditNoteStatus.draft : CreditNoteStatus.booked;
      list = list.where((cn) => cn.status == status).toList();
    }
    return list.map((cn) {
      final origInv = _originalInvoiceNumber(cn);
      return TlRow(
        key: cn.id,
        onTap: () => _showDetail(cn),
        cells: [
          TlCell(widget: TlPrimaryCell(
            text: cn.creditNoteNumber ?? '—',
            sub: origInv != null ? 'Storno fattura: $origInv' : null,
          )),
          TlCell(text: _customerName(cn)),
          TlCell(widget: TlBadge(label: cn.status.label, color: cn.status.color)),
          TlCell(widget: TlAmountCell(text: _currFmt.format(cn.total)), align: TextAlign.right),
          TlCell(widget: cn.paid
              ? const Row(children: [Icon(Icons.check_circle, size: 15, color: Color(0xFF034F3B)), SizedBox(width: 4), Text('Saldato', style: TextStyle(fontSize: 13, color: Color(0xFF034F3B), fontWeight: FontWeight.w600))])
              : const Text('Non saldato', style: TextStyle(fontSize: 13, color: Color(0xFF525D78)))),
          TlCell(text: cn.creditNoteDate != null ? _dateFmt.format(cn.creditNoteDate!) : '—'),
          TlCell(widget: TlRowActions(items: [
            if (cn.status == CreditNoteStatus.draft)
              PopupMenuItem(
                value: 'book',
                child: const Text('Registra'),
                onTap: () => widget.crmRepo.bookCreditNote(widget.userId, cn.id),
              ),
            const PopupMenuDivider(),
            PopupMenuItem(
              value: 'delete',
              child: const Text('Elimina', style: TextStyle(color: Color(0xFFB91C1C))),
              onTap: () => widget.crmRepo.deleteCreditNote(widget.userId, cn.id),
            ),
          ])),
        ],
      );
    }).toList();
  }

  void _showDetail(CreditNote cn) {
    showDialog<void>(
      context: context,
      builder: (_) => _CreditNoteDetailDialog(
        creditNote: cn,
        customerName: _customerName(cn),
        originalInvoiceNumber: _originalInvoiceNumber(cn),
        crmData: widget.crmData,
        currFmt: _currFmt,
        dateFmt: _dateFmt,
        onBook: cn.status == CreditNoteStatus.draft
            ? () => widget.crmRepo.bookCreditNote(widget.userId, cn.id)
            : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final totalBooked = widget.crmData.creditNotes
        .where((cn) => cn.status == CreditNoteStatus.booked)
        .fold(0.0, (s, cn) => s + cn.total);

    return TlTable(
      searchHint: 'Cerca note di credito...',
      columns: const [
        TlColumn(label: 'Numero', flex: 2),
        TlColumn(label: 'Cliente', flex: 2),
        TlColumn(label: 'Stato', flex: 1),
        TlColumn(label: 'Importo', flex: 1, align: TextAlign.right),
        TlColumn(label: 'Saldo', flex: 1),
        TlColumn(label: 'Data', flex: 1),
        TlColumn(label: '', minWidth: 40),
      ],
      rows: _rows,
      statusFilters: _statusFilters,
      selectedStatus: _statusFilter,
      onStatusChanged: (v) => setState(() => _statusFilter = v),
      onAdd: () => _showAddDialog(),
      addLabel: 'Nuova nota di credito',
      emptyMessage: 'Nessuna nota di credito trovata.',
      extraActions: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(color: const Color(0xFFF5F3FF), borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFFDDD6FE))),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.receipt_outlined, size: 14, color: GussoniBrand.primary),
          const SizedBox(width: 6),
          Text('Totale stornato: ${_currFmt.format(totalBooked)}', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: GussoniBrand.primary)),
        ]),
      ),
    );
  }

  void _showAddDialog() {
    showDialog<void>(
      context: context,
      builder: (ctx) => _AddCreditNoteDialog(
        companies: widget.companies,
        invoices: widget.workspace.invoiceDrafts,
        onSave: (cn) => widget.crmRepo.createCreditNote(widget.userId, cn),
      ),
    );
  }
}

// ── Detail dialog ──

class _CreditNoteDetailDialog extends StatelessWidget {
  const _CreditNoteDetailDialog({
    required this.creditNote, required this.customerName,
    required this.originalInvoiceNumber, required this.crmData,
    required this.currFmt, required this.dateFmt, this.onBook,
  });
  final CreditNote creditNote; final String customerName; final String? originalInvoiceNumber;
  final CrmData crmData; final NumberFormat currFmt; final DateFormat dateFmt; final VoidCallback? onBook;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Row(children: [
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(creditNote.creditNoteNumber ?? 'Nota di credito', style: const TextStyle(fontWeight: FontWeight.w800)),
        if (originalInvoiceNumber != null)
          Row(children: [
            const Icon(Icons.receipt_long_outlined, size: 13, color: Color(0xFF7D89A8)),
            const SizedBox(width: 4),
            Text('Storno fattura: $originalInvoiceNumber', style: const TextStyle(fontSize: 12, color: Color(0xFF7D89A8), fontWeight: FontWeight.w600)),
          ]),
      ])),
      TlBadge(label: creditNote.status.label, color: creditNote.status.color),
    ]),
    content: SizedBox(
      width: 580,
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Info rows
        _InfoRow(label: 'Cliente', value: customerName),
        if (creditNote.creditNoteDate != null)
          _InfoRow(label: 'Data emissione', value: dateFmt.format(creditNote.creditNoteDate!)),
        _InfoRow(label: 'Saldo', value: creditNote.paid ? 'Saldato${creditNote.paidAt != null ? " il ${dateFmt.format(creditNote.paidAt!)}" : ""}' : 'Non saldato'),
        if (creditNote.note.isNotEmpty) _InfoRow(label: 'Note', value: creditNote.note),
        const SizedBox(height: 16),
        // Lines
        Container(
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFF1E2130))),
          child: Column(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              decoration: const BoxDecoration(color: const Color(0xFF0C0E1A), borderRadius: BorderRadius.vertical(top: Radius.circular(10))),
              child: const Row(children: [
                Expanded(flex: 3, child: Text('Descrizione', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF7D89A8)))),
                SizedBox(width: 60, child: Text('Qtà', textAlign: TextAlign.right, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF7D89A8)))),
                SizedBox(width: 90, child: Text('Prezzo', textAlign: TextAlign.right, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF7D89A8)))),
                SizedBox(width: 90, child: Text('Totale', textAlign: TextAlign.right, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF7D89A8)))),
              ]),
            ),
            ...creditNote.lines.map((l) => Column(children: [
              const Divider(height: 1, color: Color(0xFF0C0E1A)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: Row(children: [
                  Expanded(flex: 3, child: Text(l.description, style: const TextStyle(fontSize: 13))),
                  SizedBox(width: 60, child: Text('${l.quantity}', textAlign: TextAlign.right, style: const TextStyle(fontSize: 13, color: Color(0xFF7D89A8)))),
                  SizedBox(width: 90, child: Text(currFmt.format(l.unitPrice), textAlign: TextAlign.right, style: const TextStyle(fontSize: 13, color: Color(0xFF7D89A8)))),
                  SizedBox(width: 90, child: Text(currFmt.format(l.total), textAlign: TextAlign.right, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700))),
                ]),
              ),
            ])),
            const Divider(height: 1, color: Color(0xFF1E2130)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(children: [
                const Spacer(),
                Text('Subtot. ${currFmt.format(creditNote.subtotal)}  ·  IVA ${currFmt.format(creditNote.vatTotal)}  ·  ', style: const TextStyle(fontSize: 12, color: Color(0xFF7D89A8))),
                Text('Totale: ${currFmt.format(creditNote.total)}', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: GussoniBrand.primary)),
              ]),
            ),
          ]),
        ),
      ]),
    ),
    actions: [
      if (onBook != null) FilledButton(onPressed: () { onBook!(); Navigator.of(context).pop(); }, child: const Text('Registra nota di credito')),
      TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Chiudi')),
    ],
  );
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});
  final String label; final String value;
  @override Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(children: [
      SizedBox(width: 140, child: Text(label, style: const TextStyle(fontSize: 13, color: Color(0xFF7D89A8)))),
      Expanded(child: Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
    ]),
  );
}

// ── Add dialog ──
class _AddCreditNoteDialog extends StatefulWidget {
  const _AddCreditNoteDialog({required this.companies, required this.invoices, required this.onSave});
  final List<Company> companies; final List<InvoiceDraft> invoices; final Future<void> Function(CreditNote) onSave;
  @override State<_AddCreditNoteDialog> createState() => _AddCreditNoteDialogState();
}

class _AddCreditNoteDialogState extends State<_AddCreditNoteDialog> {
  final _numCtrl = TextEditingController();
  String? _customerId; String? _invoiceId;
  final List<_LineRow> _lines = [_LineRow()]; bool _saving = false;
  DateTime _date = DateTime.now();

  @override void dispose() { _numCtrl.dispose(); for (final l in _lines) l.dispose(); super.dispose(); }

  Future<void> _save() async {
    if (_numCtrl.text.trim().isEmpty) return;
    setState(() => _saving = true);
    final lines = _lines.map((l) => QuotationLine(description: l.desc.text.trim(), quantity: double.tryParse(l.qty.text) ?? 1, unitPrice: double.tryParse(l.price.text.replaceAll(',', '.')) ?? 0)).toList();
    await widget.onSave(CreditNote(
      id: 'cn-${DateTime.now().microsecondsSinceEpoch}',
      creditNoteNumber: _numCtrl.text.trim(),
      creditNoteDate: _date,
      status: CreditNoteStatus.draft,
      lines: lines, customerId: _customerId,
      customerType: _customerId != null ? 'company' : null,
      invoiceId: _invoiceId, createdAt: DateTime.now(),
    ));
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(context: context, initialDate: _date, firstDate: DateTime(2020), lastDate: DateTime.now());
    if (d != null) setState(() => _date = d);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Nuova nota di credito', style: TextStyle(fontWeight: FontWeight.w800)),
    content: SizedBox(width: 520, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
      Row(children: [
        Expanded(child: TextField(controller: _numCtrl, decoration: const InputDecoration(labelText: 'Numero *', border: OutlineInputBorder()), autofocus: true)),
        const SizedBox(width: 12),
        Expanded(child: InkWell(onTap: _pickDate, child: InputDecorator(decoration: const InputDecoration(labelText: 'Data', border: OutlineInputBorder()), child: Text(DateFormat('dd/MM/yyyy').format(_date))))),
      ]),
      const SizedBox(height: 12),
      DropdownButtonFormField<String>(initialValue: _customerId, decoration: const InputDecoration(labelText: 'Cliente', border: OutlineInputBorder()), items: [const DropdownMenuItem(value: null, child: Text('— Nessuno —')), ...widget.companies.map((c) => DropdownMenuItem(value: c.id, child: Text(c.name)))], onChanged: (v) => setState(() => _customerId = v)),
      const SizedBox(height: 12),
      DropdownButtonFormField<String>(
        initialValue: _invoiceId,
        decoration: const InputDecoration(labelText: 'Fattura originale stornata', border: OutlineInputBorder(), prefixIcon: Icon(Icons.receipt_long_outlined, size: 18)),
        items: [
          const DropdownMenuItem(value: null, child: Text('— Nessuna —')),
          ...widget.invoices.where((i) => i.number.isNotEmpty).map((i) => DropdownMenuItem(value: i.id, child: Text(i.number))),
        ],
        onChanged: (v) => setState(() => _invoiceId = v),
      ),
      const SizedBox(height: 16),
      const Align(alignment: Alignment.centerLeft, child: Text('Righe nota di credito', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700))),
      const SizedBox(height: 8),
      ...List.generate(_lines.length, (i) => Padding(padding: const EdgeInsets.only(bottom: 8), child: Row(children: [
        Expanded(flex: 3, child: TextField(controller: _lines[i].desc, decoration: const InputDecoration(labelText: 'Descrizione', border: OutlineInputBorder(), isDense: true))),
        const SizedBox(width: 8),
        SizedBox(width: 65, child: TextField(controller: _lines[i].qty, decoration: const InputDecoration(labelText: 'Qtà', border: OutlineInputBorder(), isDense: true), keyboardType: const TextInputType.numberWithOptions(decimal: true))),
        const SizedBox(width: 8),
        SizedBox(width: 90, child: TextField(controller: _lines[i].price, decoration: const InputDecoration(labelText: '€', border: OutlineInputBorder(), isDense: true), keyboardType: const TextInputType.numberWithOptions(decimal: true))),
        IconButton(onPressed: _lines.length > 1 ? () => setState(() { _lines[i].dispose(); _lines.removeAt(i); }) : null, icon: const Icon(Icons.remove_circle_outline, size: 18, color: Color(0xFF525D78)), padding: EdgeInsets.zero),
      ]))),
      TextButton.icon(onPressed: () => setState(() => _lines.add(_LineRow())), icon: const Icon(Icons.add, size: 15), label: const Text('Aggiungi riga')),
    ]))),
    actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Annulla')), FilledButton(onPressed: _saving ? null : _save, child: _saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Salva'))],
  );
}

class _LineRow { final desc = TextEditingController(); final qty = TextEditingController(text: '1'); final price = TextEditingController(); void dispose() { desc.dispose(); qty.dispose(); price.dispose(); } }
