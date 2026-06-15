import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/domain_models.dart';
import '../data/firestore_crm_repository.dart';
import '../models/crm_extra_models.dart';
import 'tl_table.dart';

// ────────────────────────────────────────────────
// Abbonamenti – Subscriptions
// Teamleader: status active|deactivated, billing_cycle, invoicee.customer
// ────────────────────────────────────────────────

class AbbonamentCard extends StatefulWidget {
  const AbbonamentCard({
    super.key,
    required this.crmData,
    required this.companies,
    required this.crmRepo,
    required this.userId,
  });

  final CrmData crmData;
  final List<Company> companies;
  final FirestoreCrmRepository crmRepo;
  final String userId;

  @override
  State<AbbonamentCard> createState() => _AbbonamentCardState();
}

class _AbbonamentCardState extends State<AbbonamentCard> {
  String? _statusFilter;
  final _currFmt = NumberFormat.currency(locale: 'it_IT', symbol: '€', decimalDigits: 2);
  final _dateFmt = DateFormat('dd/MM/yyyy');

  static const _statusFilters = [
    TlStatusFilter(label: 'Attivo', value: 'active', color: Color(0xFF034F3B)),
    TlStatusFilter(label: 'Disattivato', value: 'deactivated', color: Color(0xFF7D89A8)),
  ];

  String _customerName(Subscription s) {
    if (s.customerId == null) return '—';
    return widget.companies.where((c) => c.id == s.customerId).firstOrNull?.name ?? '—';
  }

  List<TlRow> get _rows {
    var list = widget.crmData.subscriptions;
    if (_statusFilter != null) {
      final status = _statusFilter == 'active' ? SubscriptionStatus.active : SubscriptionStatus.deactivated;
      list = list.where((s) => s.status == status).toList();
    }
    return list.map((s) => TlRow(
      key: s.id,
      onTap: () => _showDetail(s),
      cells: [
        TlCell(widget: TlPrimaryCell(text: s.title, sub: s.note.isEmpty ? null : s.note)),
        TlCell(text: _customerName(s)),
        TlCell(widget: TlBadge(label: s.status.label, color: s.status.color)),
        TlCell(widget: TlBadge(label: s.billingCycle.label, color: const Color(0xFF0369A1))),
        TlCell(widget: TlAmountCell(text: _currFmt.format(s.total)), align: TextAlign.right),
        TlCell(text: s.nextRenewalDate != null ? _dateFmt.format(s.nextRenewalDate!) : '—'),
        TlCell(widget: TlRowActions(items: [
          if (s.status == SubscriptionStatus.active)
            PopupMenuItem(
              value: 'deactivate',
              child: const Text('Disattiva'),
              onTap: () => widget.crmRepo.deactivateSubscription(widget.userId, s.id),
            ),
          const PopupMenuDivider(),
          PopupMenuItem(
            value: 'delete',
            child: const Text('Elimina', style: TextStyle(color: Color(0xFFB91C1C))),
            onTap: () => widget.crmRepo.deleteSubscription(widget.userId, s.id),
          ),
        ])),
      ],
    )).toList();
  }

  void _showDetail(Subscription s) {
    showDialog<void>(
      context: context,
      builder: (_) => _SubscriptionDetailDialog(
        subscription: s,
        customerName: _customerName(s),
        crmData: widget.crmData,
        currFmt: _currFmt,
        dateFmt: _dateFmt,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final active = widget.crmData.subscriptions.where((s) => s.status == SubscriptionStatus.active).length;
    final monthlyTotal = widget.crmData.subscriptions
        .where((s) => s.status == SubscriptionStatus.active && s.billingCycle.unit == 'month')
        .fold(0.0, (sum, s) => sum + s.total);

    return TlTable(
      searchHint: 'Cerca abbonamenti...',
      columns: const [
        TlColumn(label: 'Titolo', flex: 3),
        TlColumn(label: 'Cliente', flex: 2),
        TlColumn(label: 'Stato', flex: 1),
        TlColumn(label: 'Ciclo', flex: 2),
        TlColumn(label: 'Importo', flex: 1, align: TextAlign.right),
        TlColumn(label: 'Prossimo rinnovo', flex: 1),
        TlColumn(label: '', minWidth: 40),
      ],
      rows: _rows,
      statusFilters: _statusFilters,
      selectedStatus: _statusFilter,
      onStatusChanged: (v) => setState(() => _statusFilter = v),
      onAdd: () => _showAddDialog(),
      addLabel: 'Nuovo abbonamento',
      emptyMessage: 'Nessun abbonamento trovato.',
      extraActions: _StatusSummary(active: active, monthlyTotal: monthlyTotal, currFmt: _currFmt),
    );
  }

  void _showAddDialog() {
    showDialog<void>(
      context: context,
      builder: (ctx) => _AddSubscriptionDialog(
        companies: widget.companies,
        onSave: (s) => widget.crmRepo.createSubscription(widget.userId, s),
      ),
    );
  }
}

// ── Summary pill ──
class _StatusSummary extends StatelessWidget {
  const _StatusSummary({required this.active, required this.monthlyTotal, required this.currFmt});
  final int active; final double monthlyTotal; final NumberFormat currFmt;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
    decoration: BoxDecoration(color: const Color(0xFFF0FDF4), borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFFBBF7D0))),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.repeat, size: 14, color: Color(0xFF034F3B)),
      const SizedBox(width: 6),
      Text('$active attivi · ${currFmt.format(monthlyTotal)}/mese', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF034F3B))),
    ]),
  );
}

// ── Detail dialog ──
class _SubscriptionDetailDialog extends StatelessWidget {
  const _SubscriptionDetailDialog({required this.subscription, required this.customerName, required this.crmData, required this.currFmt, required this.dateFmt});
  final Subscription subscription; final String customerName; final CrmData crmData; final NumberFormat currFmt; final DateFormat dateFmt;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Row(children: [
      Expanded(child: Text(subscription.title, style: const TextStyle(fontWeight: FontWeight.w800))),
      TlBadge(label: subscription.status.label, color: subscription.status.color),
    ]),
    content: SizedBox(
      width: 560,
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        _Row(label: 'Cliente', value: customerName),
        _Row(label: 'Ciclo fatturazione', value: subscription.billingCycle.label),
        if (subscription.startsOn != null) _Row(label: 'Inizia il', value: dateFmt.format(subscription.startsOn!)),
        if (subscription.endsOn != null) _Row(label: 'Termina il', value: dateFmt.format(subscription.endsOn!)),
        if (subscription.nextRenewalDate != null) _Row(label: 'Prossimo rinnovo', value: dateFmt.format(subscription.nextRenewalDate!)),
        if (subscription.note.isNotEmpty) _Row(label: 'Note', value: subscription.note),
        const Divider(),
        const Text('Righe abbonamento', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF525D78))),
        const SizedBox(height: 8),
        ...subscription.lines.map((l) {
          final product = l.productId != null ? crmData.productById(l.productId) : null;
          return Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(l.description, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                if (product != null) Text('da catalogo: ${product.name}', style: const TextStyle(fontSize: 11, color: Color(0xFF525D78))),
              ])),
              Text('${l.quantity} × ${currFmt.format(l.unitPrice)}', style: const TextStyle(fontSize: 12, color: Color(0xFF7D89A8))),
              const SizedBox(width: 12),
              Text(currFmt.format(l.total), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
            ]),
          );
        }),
        const Divider(),
        Row(children: [
          const Spacer(),
          Text('Totale: ${currFmt.format(subscription.total)}', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: Color(0xFF034F3B))),
        ]),
      ]),
    ),
    actions: [FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Chiudi'))],
  );
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value});
  final String label; final String value;
  @override Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(children: [
      SizedBox(width: 150, child: Text(label, style: const TextStyle(fontSize: 13, color: Color(0xFF7D89A8)))),
      Expanded(child: Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
    ]),
  );
}

// ── Add dialog ──
class _AddSubscriptionDialog extends StatefulWidget {
  const _AddSubscriptionDialog({required this.companies, required this.onSave});
  final List<Company> companies; final Future<void> Function(Subscription) onSave;
  @override State<_AddSubscriptionDialog> createState() => _AddSubscriptionDialogState();
}

class _AddSubscriptionDialogState extends State<_AddSubscriptionDialog> {
  final _titleCtrl = TextEditingController(); final _noteCtrl = TextEditingController();
  String? _customerId; String _cycleUnit = 'month'; int _cyclePeriod = 1; int _daysInAdvance = 5;
  final List<_LineRow> _lines = [_LineRow()]; bool _saving = false;
  DateTime _startsOn = DateTime.now();

  @override void dispose() { _titleCtrl.dispose(); _noteCtrl.dispose(); for (final l in _lines) l.dispose(); super.dispose(); }

  Future<void> _save() async {
    if (_titleCtrl.text.trim().isEmpty) return;
    setState(() => _saving = true);
    final lines = _lines.map((l) => QuotationLine(description: l.desc.text.trim(), quantity: double.tryParse(l.qty.text) ?? 1, unitPrice: double.tryParse(l.price.text.replaceAll(',', '.')) ?? 0)).toList();
    await widget.onSave(Subscription(
      id: 'sub-${DateTime.now().microsecondsSinceEpoch}',
      title: _titleCtrl.text.trim(), note: _noteCtrl.text.trim(),
      status: SubscriptionStatus.active,
      billingCycle: BillingCycle(unit: _cycleUnit, period: _cyclePeriod, daysInAdvance: _daysInAdvance),
      lines: lines, customerId: _customerId, customerType: _customerId != null ? 'company' : null,
      startsOn: _startsOn, createdAt: DateTime.now(),
    ));
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Nuovo abbonamento', style: TextStyle(fontWeight: FontWeight.w800)),
    content: SizedBox(width: 520, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
      TextField(controller: _titleCtrl, decoration: const InputDecoration(labelText: 'Titolo *', border: OutlineInputBorder()), autofocus: true),
      const SizedBox(height: 12),
      DropdownButtonFormField<String>(initialValue: _customerId, decoration: const InputDecoration(labelText: 'Cliente', border: OutlineInputBorder()), items: [const DropdownMenuItem(value: null, child: Text('— Nessuno —')), ...widget.companies.map((c) => DropdownMenuItem(value: c.id, child: Text(c.name)))], onChanged: (v) => setState(() => _customerId = v)),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(child: DropdownButtonFormField<String>(value: _cycleUnit, decoration: const InputDecoration(labelText: 'Unità ciclo', border: OutlineInputBorder()), items: const [DropdownMenuItem(value: 'week', child: Text('Settimana')), DropdownMenuItem(value: 'month', child: Text('Mese')), DropdownMenuItem(value: 'year', child: Text('Anno'))], onChanged: (v) => setState(() => _cycleUnit = v ?? 'month'))),
        const SizedBox(width: 12),
        SizedBox(width: 80, child: TextFormField(initialValue: '$_cyclePeriod', keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Ogni', border: OutlineInputBorder()), onChanged: (v) => _cyclePeriod = int.tryParse(v) ?? 1)),
        const SizedBox(width: 12),
        SizedBox(width: 100, child: TextFormField(initialValue: '$_daysInAdvance', keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'GG anticipo', border: OutlineInputBorder()), onChanged: (v) => _daysInAdvance = int.tryParse(v) ?? 5)),
      ]),
      const SizedBox(height: 16),
      const Align(alignment: Alignment.centerLeft, child: Text('Righe', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700))),
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
      const SizedBox(height: 8),
      TextField(controller: _noteCtrl, decoration: const InputDecoration(labelText: 'Note', border: OutlineInputBorder()), maxLines: 2),
    ]))),
    actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Annulla')), FilledButton(onPressed: _saving ? null : _save, child: _saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Salva'))],
  );
}

class _LineRow { final desc = TextEditingController(); final qty = TextEditingController(text: '1'); final price = TextEditingController(); void dispose() { desc.dispose(); qty.dispose(); price.dispose(); } }
