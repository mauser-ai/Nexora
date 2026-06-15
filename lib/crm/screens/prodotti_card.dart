import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../data/firestore_crm_repository.dart';
import '../models/crm_extra_models.dart';
import 'tl_table.dart';

class ProdottiCard extends StatefulWidget {
  const ProdottiCard({super.key, required this.crmData, required this.crmRepo, required this.userId, this.onOpenDetail});
  final CrmData crmData; final FirestoreCrmRepository crmRepo; final String userId;
  final void Function(Product)? onOpenDetail;
  @override State<ProdottiCard> createState() => _ProdottiCardState();
}

class _ProdottiCardState extends State<ProdottiCard> {
  String? _catFilter;
  final _currFmt = NumberFormat.currency(locale: 'it_IT', symbol: '€', decimalDigits: 2);

  List<String> get _categories => widget.crmData.products.map((p) => p.category).toSet().where((c) => c.isNotEmpty).toList()..sort();

  List<TlStatusFilter> get _statusFilters => _categories.map((c) => TlStatusFilter(label: c, value: c)).toList();

  List<TlRow> get _rows {
    var list = widget.crmData.products;
    if (_catFilter != null) list = list.where((p) => p.category == _catFilter).toList();
    return list.map((p) => TlRow(
      key: p.id,
      onTap: widget.onOpenDetail != null ? () => widget.onOpenDetail!(p) : null,
      cells: [
        TlCell(widget: TlPrimaryCell(text: p.name, sub: p.description.isEmpty ? null : p.description)),
        TlCell(text: p.sku.isEmpty ? '—' : p.sku),
        TlCell(widget: p.category.isEmpty ? const SizedBox() : Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(999), color: const Color(0xFF0C0E1A)),
          child: Text(p.category, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFFB8C0D8))),
        )),
        TlCell(widget: TlAmountCell(text: _currFmt.format(p.price)), align: TextAlign.right),
        TlCell(text: '${p.unit}  ·  IVA ${p.vatRate.toStringAsFixed(0)}%'),
        TlCell(widget: TlRowActions(items: [
          PopupMenuItem(value: 'delete', child: const Text('Elimina', style: TextStyle(color: Color(0xFFB91C1C))), onTap: () => widget.crmRepo.deleteProduct(widget.userId, p.id)),
        ])),
      ],
    )).toList();
  }

  @override
  Widget build(BuildContext context) {
    return TlTable(
      searchHint: 'Cerca prodotti o SKU...',
      columns: const [
        TlColumn(label: 'Nome prodotto', flex: 3),
        TlColumn(label: 'SKU', flex: 1),
        TlColumn(label: 'Categoria', flex: 1),
        TlColumn(label: 'Prezzo', flex: 1, align: TextAlign.right),
        TlColumn(label: 'Unità / IVA', flex: 1),
        TlColumn(label: '', minWidth: 40),
      ],
      rows: _rows,
      statusFilters: _statusFilters,
      selectedStatus: _catFilter,
      onStatusChanged: (v) => setState(() => _catFilter = v),
      onAdd: () => _showAddDialog(),
      addLabel: 'Aggiungi prodotto',
      emptyMessage: 'Nessun prodotto nel catalogo.',
    );
  }

  void _showAddDialog() {
    showDialog<void>(context: context, builder: (ctx) => _AddProductDialog(onSave: (p) => widget.crmRepo.createProduct(widget.userId, p)));
  }
}

class _AddProductDialog extends StatefulWidget {
  const _AddProductDialog({required this.onSave});
  final Future<void> Function(Product) onSave;
  @override State<_AddProductDialog> createState() => _AddProductDialogState();
}
class _AddProductDialogState extends State<_AddProductDialog> {
  final _nameCtrl = TextEditingController(); final _skuCtrl = TextEditingController();
  final _descCtrl = TextEditingController(); final _priceCtrl = TextEditingController();
  final _unitCtrl = TextEditingController(text: 'pz'); final _catCtrl = TextEditingController();
  bool _saving = false;
  @override void dispose() { _nameCtrl.dispose(); _skuCtrl.dispose(); _descCtrl.dispose(); _priceCtrl.dispose(); _unitCtrl.dispose(); _catCtrl.dispose(); super.dispose(); }
  Future<void> _save() async {
    if (_nameCtrl.text.trim().isEmpty) return;
    setState(() => _saving = true);
    await widget.onSave(Product(id: 'prod-${DateTime.now().microsecondsSinceEpoch}', name: _nameCtrl.text.trim(), sku: _skuCtrl.text.trim(), description: _descCtrl.text.trim(), price: double.tryParse(_priceCtrl.text.replaceAll(',', '.')) ?? 0, unit: _unitCtrl.text.trim().isEmpty ? 'pz' : _unitCtrl.text.trim(), category: _catCtrl.text.trim(), createdAt: DateTime.now()));
    if (mounted) Navigator.of(context).pop();
  }
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Nuovo prodotto / servizio', style: TextStyle(fontWeight: FontWeight.w800)),
    content: SizedBox(width: 460, child: Column(mainAxisSize: MainAxisSize.min, children: [
      TextField(controller: _nameCtrl, decoration: const InputDecoration(labelText: 'Nome *', border: OutlineInputBorder()), autofocus: true),
      const SizedBox(height: 12),
      Row(children: [Expanded(child: TextField(controller: _skuCtrl, decoration: const InputDecoration(labelText: 'SKU / Codice', border: OutlineInputBorder()))), const SizedBox(width: 12), Expanded(child: TextField(controller: _catCtrl, decoration: const InputDecoration(labelText: 'Categoria', border: OutlineInputBorder())))]),
      const SizedBox(height: 12),
      Row(children: [Expanded(child: TextField(controller: _priceCtrl, decoration: const InputDecoration(labelText: 'Prezzo *', border: OutlineInputBorder(), prefixText: '€ '), keyboardType: const TextInputType.numberWithOptions(decimal: true))), const SizedBox(width: 12), SizedBox(width: 100, child: TextField(controller: _unitCtrl, decoration: const InputDecoration(labelText: 'Unità', border: OutlineInputBorder())))]),
      const SizedBox(height: 12),
      TextField(controller: _descCtrl, decoration: const InputDecoration(labelText: 'Descrizione', border: OutlineInputBorder()), maxLines: 2),
    ])),
    actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Annulla')), FilledButton(onPressed: _saving ? null : _save, child: _saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Salva'))],
  );
}
