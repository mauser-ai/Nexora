import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/domain_models.dart';
import '../data/firestore_crm_repository.dart';
import '../models/crm_extra_models.dart';

class SpeseCard extends StatefulWidget {
  const SpeseCard({super.key, required this.crmData, required this.companies, required this.crmRepo, required this.userId});
  final CrmData crmData; final List<Company> companies; final FirestoreCrmRepository crmRepo; final String userId;
  @override State<SpeseCard> createState() => _SpeseCardState();
}

class _SpeseCardState extends State<SpeseCard> {
  ExpenseCategory? _catFilter;
  final _currFmt = NumberFormat.currency(locale: 'it_IT', symbol: '€', decimalDigits: 2);

  List<Expense> get _filtered => _catFilter == null ? widget.crmData.expenses : widget.crmData.expenses.where((e) => e.category == _catFilter).toList();

  double get _totalFiltered => _filtered.fold(0, (s, e) => s + e.amount);

  @override
  Widget build(BuildContext context) {
    final byCategory = <ExpenseCategory, double>{};
    for (final e in widget.crmData.expenses) {
      byCategory[e.category] = (byCategory[e.category] ?? 0) + e.amount;
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // ── Summary cards ──
      SizedBox(
        height: 90,
        child: ListView(scrollDirection: Axis.horizontal, children: [
          _CatCard(label: 'Tutte', amount: widget.crmData.totalExpenses, color: const Color(0xFFB8C0D8), selected: _catFilter == null, currFmt: _currFmt, onTap: () => setState(() => _catFilter = null)),
          const SizedBox(width: 10),
          ...ExpenseCategory.values.where((c) => (byCategory[c] ?? 0) > 0).map((cat) => Row(mainAxisSize: MainAxisSize.min, children: [
            _CatCard(label: cat.label, amount: byCategory[cat] ?? 0, color: cat.color, selected: _catFilter == cat, currFmt: _currFmt, onTap: () => setState(() => _catFilter = _catFilter == cat ? null : cat)),
            const SizedBox(width: 10),
          ])),
        ]),
      ),
      const SizedBox(height: 16),
      // ── Toolbar ──
      Row(children: [
        Text('${_filtered.length} spese · ${_currFmt.format(_totalFiltered)} totale', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFFB8C0D8))),
        const Spacer(),
        FilledButton.icon(onPressed: () => _showAddDialog(context), icon: const Icon(Icons.add, size: 16), label: const Text('Nuova spesa')),
      ]),
      const SizedBox(height: 12),
      // ── List ──
      Container(
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0xFF1E2130))),
        child: _filtered.isEmpty
            ? const Padding(padding: EdgeInsets.all(24), child: Center(child: Text('Nessuna spesa trovata.', style: TextStyle(color: Color(0xFF525D78)))))
            : Column(children: _filtered.map((e) => Column(children: [
                InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () {},
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: Row(children: [
                      Container(width: 36, height: 36, decoration: BoxDecoration(shape: BoxShape.circle, color: e.category.color.withValues(alpha: 0.12)), child: Icon(_catIcon(e.category), size: 18, color: e.category.color)),
                      const SizedBox(width: 12),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(e.title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF0F172A))),
                        Row(children: [
                          _Badge(label: e.category.label, color: e.category.color),
                          const SizedBox(width: 8),
                          Text(DateFormat('dd/MM/yyyy').format(e.date), style: const TextStyle(fontSize: 12, color: Color(0xFF525D78))),
                        ]),
                      ])),
                      Text(_currFmt.format(e.amount), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: Color(0xFF0F172A))),
                      const SizedBox(width: 8),
                      IconButton(onPressed: () => widget.crmRepo.deleteExpense(widget.userId, e.id), icon: const Icon(Icons.delete_outline, size: 16, color: Color(0xFF525D78)), tooltip: 'Elimina'),
                    ]),
                  ),
                ),
                const Divider(height: 1, color: Color(0xFF0C0E1A)),
              ])).toList()),
      ),
    ]);
  }

  IconData _catIcon(ExpenseCategory cat) {
    switch (cat) {
      case ExpenseCategory.software: return Icons.computer_outlined;
      case ExpenseCategory.hardware: return Icons.devices_outlined;
      case ExpenseCategory.travel: return Icons.directions_car_outlined;
      case ExpenseCategory.marketing: return Icons.campaign_outlined;
      case ExpenseCategory.office: return Icons.business_outlined;
      case ExpenseCategory.consulting: return Icons.people_outline;
      case ExpenseCategory.other: return Icons.category_outlined;
    }
  }

  void _showAddDialog(BuildContext context) {
    showDialog<void>(context: context, builder: (ctx) => _AddExpenseDialog(companies: widget.companies, onSave: (e) => widget.crmRepo.createExpense(widget.userId, e)));
  }
}

class _CatCard extends StatelessWidget {
  const _CatCard({required this.label, required this.amount, required this.color, required this.selected, required this.currFmt, required this.onTap});
  final String label; final double amount; final Color color; final bool selected; final NumberFormat currFmt; final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => InkWell(
    borderRadius: BorderRadius.circular(12),
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 130),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), color: selected ? color.withValues(alpha: 0.10) : Colors.white, border: Border.all(color: selected ? color : const Color(0xFF1E2130), width: selected ? 1.5 : 1)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: selected ? color : const Color(0xFFB8C0D8))),
        const SizedBox(height: 4),
        Text(currFmt.format(amount), style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: selected ? color : const Color(0xFF0F172A))),
      ]),
    ),
  );
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.color});
  final String label; final Color color;
  @override Widget build(BuildContext context) => Container(padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2), decoration: BoxDecoration(borderRadius: BorderRadius.circular(999), color: color.withValues(alpha: 0.10), border: Border.all(color: color.withValues(alpha: 0.30))), child: Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: color)));
}

class _AddExpenseDialog extends StatefulWidget {
  const _AddExpenseDialog({required this.companies, required this.onSave});
  final List<Company> companies; final Future<void> Function(Expense) onSave;
  @override State<_AddExpenseDialog> createState() => _AddExpenseDialogState();
}

class _AddExpenseDialogState extends State<_AddExpenseDialog> {
  final _titleCtrl = TextEditingController(); final _amountCtrl = TextEditingController(); final _notesCtrl = TextEditingController();
  ExpenseCategory _cat = ExpenseCategory.other; DateTime _date = DateTime.now(); bool _saving = false;

  @override void dispose() { _titleCtrl.dispose(); _amountCtrl.dispose(); _notesCtrl.dispose(); super.dispose(); }

  Future<void> _pickDate() async {
    final d = await showDatePicker(context: context, initialDate: _date, firstDate: DateTime(2020), lastDate: DateTime.now());
    if (d != null) setState(() => _date = d);
  }

  Future<void> _save() async {
    final title = _titleCtrl.text.trim(); if (title.isEmpty) return;
    setState(() => _saving = true);
    await widget.onSave(Expense(id: 'exp-${DateTime.now().microsecondsSinceEpoch}', title: title, amount: double.tryParse(_amountCtrl.text.replaceAll(',', '.')) ?? 0, category: _cat, date: _date, notes: _notesCtrl.text.trim(), createdAt: DateTime.now()));
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Nuova spesa', style: TextStyle(fontWeight: FontWeight.w800)),
    content: SizedBox(width: 460, child: Column(mainAxisSize: MainAxisSize.min, children: [
      TextField(controller: _titleCtrl, decoration: const InputDecoration(labelText: 'Titolo *', border: OutlineInputBorder()), autofocus: true),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(child: TextField(controller: _amountCtrl, decoration: const InputDecoration(labelText: 'Importo *', border: OutlineInputBorder(), prefixText: '€ '), keyboardType: const TextInputType.numberWithOptions(decimal: true))),
        const SizedBox(width: 12),
        Expanded(child: DropdownButtonFormField<ExpenseCategory>(value: _cat, decoration: const InputDecoration(labelText: 'Categoria', border: OutlineInputBorder()), items: ExpenseCategory.values.map((c) => DropdownMenuItem(value: c, child: Text(c.label))).toList(), onChanged: (v) => setState(() => _cat = v ?? ExpenseCategory.other))),
      ]),
      const SizedBox(height: 12),
      InkWell(onTap: _pickDate, child: InputDecorator(decoration: const InputDecoration(labelText: 'Data', border: OutlineInputBorder()), child: Text(DateFormat('dd/MM/yyyy').format(_date)))),
      const SizedBox(height: 12),
      TextField(controller: _notesCtrl, decoration: const InputDecoration(labelText: 'Note', border: OutlineInputBorder()), maxLines: 2),
    ])),
    actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Annulla')), FilledButton(onPressed: _saving ? null : _save, child: _saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Salva'))],
  );
}
