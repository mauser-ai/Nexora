import '../../brand_config.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/domain_models.dart';
import '../data/firestore_crm_repository.dart';
import '../models/crm_extra_models.dart';
import 'tl_table.dart';

class PreventiviCard extends StatefulWidget {
  const PreventiviCard({super.key, required this.crmData, required this.companies, required this.crmRepo, required this.userId, this.onOpenDetail});
  final CrmData crmData; final List<Company> companies; final FirestoreCrmRepository crmRepo; final String userId;
  final void Function(Quotation)? onOpenDetail;
  @override State<PreventiviCard> createState() => _PreventiviCardState();
}

class _PreventiviCardState extends State<PreventiviCard> {
  String? _statusFilter;
  final _currFmt = NumberFormat.currency(locale: 'it_IT', symbol: '€', decimalDigits: 2);
  final _dateFmt = DateFormat('dd/MM/yyyy');

  static const _statusFilters = [
    TlStatusFilter(label: 'Bozza', value: 'draft', color: Color(0xFF7D89A8)),
    TlStatusFilter(label: 'Inviato', value: 'sent', color: Color(0xFF0369A1)),
    TlStatusFilter(label: 'Accettato', value: 'accepted', color: Color(0xFF034F3B)),
    TlStatusFilter(label: 'Rifiutato', value: 'rejected', color: Color(0xFFB91C1C)),
  ];

  String _customerName(Quotation q) {
    if (q.customerId == null) return '—';
    return widget.companies.where((c) => c.id == q.customerId).firstOrNull?.name ?? '—';
  }

  String? _dealTitle(Quotation q) =>
      q.dealId == null ? null : widget.crmData.dealById(q.dealId)?.title;

  List<TlRow> get _rows {
    var list = widget.crmData.quotations;
    if (_statusFilter != null) {
      final s = QuotationStatus.values.firstWhere((v) => v.name == _statusFilter, orElse: () => QuotationStatus.draft);
      list = list.where((q) => q.status == s).toList();
    }
    return list.map((q) {
      final dealTitle = _dealTitle(q);
      return TlRow(
        key: q.id,
        onTap: () => widget.onOpenDetail != null ? widget.onOpenDetail!(q) : _showDetail(q),
        cells: [
          TlCell(widget: TlPrimaryCell(text: q.number, sub: dealTitle != null ? '↗ $dealTitle' : null)),
          TlCell(text: _customerName(q)),
          TlCell(widget: TlBadge(label: q.status.label, color: q.status.color)),
          TlCell(widget: TlAmountCell(text: _currFmt.format(q.total)), align: TextAlign.right),
          TlCell(text: q.createdAt != null ? _dateFmt.format(q.createdAt!) : '—'),
          TlCell(widget: _QuotationActions(q: q, crmRepo: widget.crmRepo, userId: widget.userId)),
        ],
      );
    }).toList();
  }

  void _showDetail(Quotation q) {
    showDialog<void>(
      context: context,
      builder: (_) => _QuotationDetailDialog(q: q, customerName: _customerName(q), dealTitle: _dealTitle(q), crmData: widget.crmData, currFmt: _currFmt),
    );
  }

  @override
  Widget build(BuildContext context) {
    return TlTable(
      searchHint: 'Cerca preventivi...',
      columns: const [
        TlColumn(label: 'Nome preventivo', flex: 2),
        TlColumn(label: 'Cliente', flex: 2),
        TlColumn(label: 'Stato', flex: 1),
        TlColumn(label: 'Importo totale', flex: 1, align: TextAlign.right),
        TlColumn(label: 'Data creata', flex: 1),
        TlColumn(label: '', minWidth: 40),
      ],
      rows: _rows,
      statusFilters: _statusFilters,
      selectedStatus: _statusFilter,
      onStatusChanged: (v) => setState(() => _statusFilter = v),
      onAdd: () => _showAddDialog(),
      addLabel: 'Aggiungi preventivo',
      emptyMessage: 'Nessun preventivo trovato.',
    );
  }

  void _showAddDialog() {
    showDialog<void>(
      context: context,
      builder: (ctx) => _AddQuotationDialog(
        companies: widget.companies,
        deals: widget.crmData.deals.where((d) => d.status == DealFirestoreStatus.open).toList(),
        products: widget.crmData.products,
        onSave: (q) => widget.crmRepo.createQuotation(widget.userId, q),
      ),
    );
  }
}

// ── Actions ──

class _QuotationActions extends StatelessWidget {
  const _QuotationActions({required this.q, required this.crmRepo, required this.userId});
  final Quotation q; final FirestoreCrmRepository crmRepo; final String userId;

  @override
  Widget build(BuildContext context) => TlRowActions(items: [
    PopupMenuItem(value: 'view', child: const Text('Dettaglio'), onTap: () {}),
    if (q.status == QuotationStatus.draft)
      PopupMenuItem(value: 'send', child: const Text('Segna inviato'), onTap: () => crmRepo.updateQuotation(userId, q.copyWith(status: QuotationStatus.sent))),
    if (q.status == QuotationStatus.sent) ...[
      PopupMenuItem(value: 'accept', child: const Text('Segna accettato'), onTap: () => crmRepo.updateQuotation(userId, q.copyWith(status: QuotationStatus.accepted))),
      PopupMenuItem(value: 'reject', child: const Text('Segna rifiutato'), onTap: () => crmRepo.updateQuotation(userId, q.copyWith(status: QuotationStatus.rejected))),
    ],
    const PopupMenuDivider(),
    PopupMenuItem(value: 'delete', child: const Text('Elimina', style: TextStyle(color: Color(0xFFB91C1C))), onTap: () => crmRepo.deleteQuotation(userId, q.id)),
  ]);
}

// ── Detail dialog ──

class _QuotationDetailDialog extends StatelessWidget {
  const _QuotationDetailDialog({required this.q, required this.customerName, required this.dealTitle, required this.crmData, required this.currFmt});
  final Quotation q; final String customerName; final String? dealTitle; final CrmData crmData; final NumberFormat currFmt;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Row(children: [
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(q.number, style: const TextStyle(fontWeight: FontWeight.w800)),
        if (dealTitle != null)
          Row(children: [const Icon(Icons.trending_up_outlined, size: 13, color: Color(0xFF034F3B)), const SizedBox(width: 4), Text(dealTitle!, style: const TextStyle(fontSize: 12, color: Color(0xFF034F3B), fontWeight: FontWeight.w600))]),
      ])),
      TlBadge(label: q.status.label, color: q.status.color),
    ]),
    content: SizedBox(
      width: 620,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        // Customer + meta row
        Row(children: [
          const Icon(Icons.apartment_outlined, size: 14, color: Color(0xFF525D78)),
          const SizedBox(width: 6),
          Text(customerName, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          if (q.createdAt != null) ...[
            const Spacer(),
            Text(DateFormat('dd/MM/yyyy').format(q.createdAt!), style: const TextStyle(fontSize: 12, color: Color(0xFF525D78))),
          ],
        ]),
        const SizedBox(height: 16),
        // Lines table
        Container(
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFF1E2130))),
          child: Column(children: [
            _tableHeader(),
            const Divider(height: 1, color: Color(0xFF1E2130)),
            ...q.lines.map((l) {
              final product = l.productId != null ? crmData.productById(l.productId) : null;
              return Column(children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  child: Row(children: [
                    Expanded(flex: 3, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(l.description, style: const TextStyle(fontSize: 13)),
                      if (product != null) Row(children: [
                        const Icon(Icons.inventory_2_outlined, size: 11, color: Color(0xFF525D78)),
                        const SizedBox(width: 3),
                        Text(product.name, style: const TextStyle(fontSize: 11, color: Color(0xFF525D78))),
                      ]),
                    ])),
                    SizedBox(width: 60, child: Text('${l.quantity}', textAlign: TextAlign.right, style: const TextStyle(fontSize: 13, color: Color(0xFF7D89A8)))),
                    SizedBox(width: 90, child: Text(currFmt.format(l.unitPrice), textAlign: TextAlign.right, style: const TextStyle(fontSize: 13, color: Color(0xFF7D89A8)))),
                    SizedBox(width: 90, child: Text(currFmt.format(l.total), textAlign: TextAlign.right, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700))),
                  ]),
                ),
                const Divider(height: 1, color: Color(0xFF0C0E1A)),
              ]);
            }),
            _totalRow(currFmt),
          ]),
        ),
        if (q.notes.isNotEmpty) ...[
          const SizedBox(height: 12),
          Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: const Color(0xFF080A14), borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFF1E2130))), child: Text(q.notes, style: const TextStyle(fontSize: 13, color: Color(0xFFB8C0D8)))),
        ],
      ]),
    ),
    actions: [FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Chiudi'))],
  );

  Widget _tableHeader() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
    color: const Color(0xFF0C0E1A),
    child: const Row(children: [
      Expanded(flex: 3, child: Text('Descrizione', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF7D89A8)))),
      SizedBox(width: 60, child: Text('Qtà', textAlign: TextAlign.right, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF7D89A8)))),
      SizedBox(width: 90, child: Text('Prezzo unit.', textAlign: TextAlign.right, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF7D89A8)))),
      SizedBox(width: 90, child: Text('Totale', textAlign: TextAlign.right, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF7D89A8)))),
    ]),
  );

  Widget _totalRow(NumberFormat fmt) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    child: Row(children: [
      const Spacer(),
      Text('Subtot. ${fmt.format(q.subtotal)}  ·  IVA ${fmt.format(q.vatTotal)}  ·  ', style: const TextStyle(fontSize: 12, color: Color(0xFF7D89A8))),
      Text('Totale: ${fmt.format(q.total)}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: Color(0xFF034F3B))),
    ]),
  );
}

// ── Add Dialog with product picker ──

class _AddQuotationDialog extends StatefulWidget {
  const _AddQuotationDialog({required this.companies, required this.deals, required this.products, required this.onSave});
  final List<Company> companies;
  final List<Deal> deals;
  final List<Product> products;
  final Future<void> Function(Quotation) onSave;
  @override State<_AddQuotationDialog> createState() => _AddQuotationDialogState();
}

class _AddQuotationDialogState extends State<_AddQuotationDialog> {
  final _numCtrl = TextEditingController();
  String? _customerId;
  String? _dealId;
  final List<_LineState> _lines = [_LineState()];
  bool _saving = false;

  @override void dispose() { _numCtrl.dispose(); for (final l in _lines) l.dispose(); super.dispose(); }

  void _addLineFromProduct(Product p) {
    setState(() {
      final line = _LineState();
      line.desc.text = p.name;
      line.price.text = p.price.toStringAsFixed(2);
      line.productId = p.id;
      _lines.add(line);
    });
  }

  Future<void> _save() async {
    if (_numCtrl.text.trim().isEmpty) return;
    setState(() => _saving = true);
    final lines = _lines.map((l) => QuotationLine(
      description: l.desc.text.trim(),
      quantity: double.tryParse(l.qty.text) ?? 1,
      unitPrice: double.tryParse(l.price.text.replaceAll(',', '.')) ?? 0,
      productId: l.productId,
    )).toList();
    await widget.onSave(Quotation(
      id: 'quot-${DateTime.now().microsecondsSinceEpoch}',
      number: _numCtrl.text.trim(),
      status: QuotationStatus.draft,
      lines: lines,
      customerId: _customerId,
      customerType: _customerId != null ? 'company' : null,
      dealId: _dealId,
      createdAt: DateTime.now(),
    ));
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Nuovo preventivo', style: TextStyle(fontWeight: FontWeight.w800)),
      content: SizedBox(width: 680, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        // Header fields
        Row(children: [
          Expanded(child: TextField(controller: _numCtrl, decoration: const InputDecoration(labelText: 'Numero *', border: OutlineInputBorder()), autofocus: true)),
          const SizedBox(width: 12),
          Expanded(child: DropdownButtonFormField<String>(
            initialValue: _customerId,
            decoration: const InputDecoration(labelText: 'Cliente', border: OutlineInputBorder()),
            items: [const DropdownMenuItem(value: null, child: Text('— Nessuno —')), ...widget.companies.map((c) => DropdownMenuItem(value: c.id, child: Text(c.name)))],
            onChanged: (v) => setState(() => _customerId = v),
          )),
        ]),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: _dealId,
          decoration: const InputDecoration(labelText: 'Opportunità collegata', border: OutlineInputBorder(), prefixIcon: Icon(Icons.trending_up_outlined, size: 18)),
          items: [const DropdownMenuItem(value: null, child: Text('— Nessuna —')), ...widget.deals.map((d) => DropdownMenuItem(value: d.id, child: Text(d.title)))],
          onChanged: (v) => setState(() => _dealId = v),
        ),
        const SizedBox(height: 20),
        // Lines section
        Row(children: [
          const Text('Righe preventivo', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
          const Spacer(),
          if (widget.products.isNotEmpty)
            OutlinedButton.icon(
              onPressed: () => _showProductPicker(),
              icon: const Icon(Icons.inventory_2_outlined, size: 15),
              label: const Text('Dal catalogo'),
              style: OutlinedButton.styleFrom(minimumSize: const Size(0, 34), padding: const EdgeInsets.symmetric(horizontal: 12)),
            ),
        ]),
        const SizedBox(height: 8),
        ...List.generate(_lines.length, (i) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(flex: 3, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              TextField(controller: _lines[i].desc, decoration: const InputDecoration(labelText: 'Descrizione', border: OutlineInputBorder(), isDense: true)),
              if (_lines[i].productId != null)
                Padding(padding: const EdgeInsets.only(top: 2, left: 2), child: Row(children: [const Icon(Icons.inventory_2_outlined, size: 10, color: Color(0xFF525D78)), const SizedBox(width: 3), Text('da catalogo', style: const TextStyle(fontSize: 10, color: Color(0xFF525D78)))])),
            ])),
            const SizedBox(width: 8),
            SizedBox(width: 65, child: TextField(controller: _lines[i].qty, decoration: const InputDecoration(labelText: 'Qtà', border: OutlineInputBorder(), isDense: true), keyboardType: const TextInputType.numberWithOptions(decimal: true))),
            const SizedBox(width: 8),
            SizedBox(width: 100, child: TextField(controller: _lines[i].price, decoration: const InputDecoration(labelText: '€ Prezzo', border: OutlineInputBorder(), isDense: true), keyboardType: const TextInputType.numberWithOptions(decimal: true))),
            const SizedBox(width: 4),
            IconButton(onPressed: _lines.length > 1 ? () => setState(() { _lines[i].dispose(); _lines.removeAt(i); }) : null, icon: const Icon(Icons.remove_circle_outline, size: 18, color: Color(0xFF525D78)), padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 32, minHeight: 40)),
          ]),
        )),
        TextButton.icon(onPressed: () => setState(() => _lines.add(_LineState())), icon: const Icon(Icons.add, size: 15), label: const Text('Aggiungi riga vuota')),
      ]))),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Annulla')),
        FilledButton(onPressed: _saving ? null : _save, child: _saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Salva preventivo')),
      ],
    );
  }

  void _showProductPicker() {
    showDialog<Product>(
      context: context,
      builder: (ctx) => _ProductPickerDialog(products: widget.products),
    ).then((p) { if (p != null) _addLineFromProduct(p); });
  }
}

class _LineState {
  final desc = TextEditingController();
  final qty = TextEditingController(text: '1');
  final price = TextEditingController();
  String? productId;
  void dispose() { desc.dispose(); qty.dispose(); price.dispose(); }
}

// ── Product Picker Dialog ──

class _ProductPickerDialog extends StatefulWidget {
  const _ProductPickerDialog({required this.products});
  final List<Product> products;
  @override State<_ProductPickerDialog> createState() => _ProductPickerDialogState();
}

class _ProductPickerDialogState extends State<_ProductPickerDialog> {
  String _query = '';
  final _currFmt = NumberFormat.currency(locale: 'it_IT', symbol: '€', decimalDigits: 2);

  @override
  Widget build(BuildContext context) {
    final filtered = widget.products.where((p) =>
        p.name.toLowerCase().contains(_query.toLowerCase()) ||
        p.sku.toLowerCase().contains(_query.toLowerCase()) ||
        p.category.toLowerCase().contains(_query.toLowerCase())).toList();

    return AlertDialog(
      title: const Text('Seleziona dal catalogo', style: TextStyle(fontWeight: FontWeight.w800)),
      content: SizedBox(
        width: 500,
        height: 420,
        child: Column(children: [
          TextField(
            onChanged: (v) => setState(() => _query = v),
            autofocus: true,
            decoration: const InputDecoration(prefixIcon: Icon(Icons.search, size: 18), hintText: 'Cerca prodotti...', border: OutlineInputBorder(), isDense: true),
          ),
          const SizedBox(height: 10),
          Expanded(child: filtered.isEmpty
            ? const Center(child: Text('Nessun prodotto trovato.', style: TextStyle(color: Color(0xFF525D78))))
            : ListView.separated(
              itemCount: filtered.length,
              separatorBuilder: (_, _) => const Divider(height: 1, color: Color(0xFF0C0E1A)),
              itemBuilder: (context, i) {
                final p = filtered[i];
                return InkWell(
                  onTap: () => Navigator.of(context).pop(p),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    child: Row(children: [
                      Container(width: 36, height: 36, decoration: BoxDecoration(shape: BoxShape.circle, color: GussoniBrand.primary.withValues(alpha: 0.10)), child: const Icon(Icons.inventory_2_outlined, size: 17, color: Color(0xFF034F3B))),
                      const SizedBox(width: 12),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(p.name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                        if (p.sku.isNotEmpty) Text(p.sku, style: const TextStyle(fontSize: 11, color: Color(0xFF525D78))),
                      ])),
                      Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                        Text(_currFmt.format(p.price), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Color(0xFF0F172A))),
                        Text('/ ${p.unit}', style: const TextStyle(fontSize: 11, color: Color(0xFF525D78))),
                      ]),
                    ]),
                  ),
                );
              },
            )),
        ]),
      ),
      actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Annulla'))],
    );
  }
}
