import '../../brand_config.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/domain_models.dart';
import '../data/firestore_crm_repository.dart';
import '../models/crm_extra_models.dart';
import 'tl_table.dart';

class OpportunitaCard extends StatefulWidget {
  const OpportunitaCard({super.key, required this.crmData, required this.companies, required this.crmRepo, required this.userId, this.onOpenDetail});
  final CrmData crmData; final List<Company> companies; final FirestoreCrmRepository crmRepo; final String userId;
  final void Function(Deal)? onOpenDetail;
  @override State<OpportunitaCard> createState() => _OpportunitaCardState();
}

class _OpportunitaCardState extends State<OpportunitaCard> {
  bool _kanbanView = false;
  String? _statusFilter;
  final _currFmt = NumberFormat.currency(locale: 'it_IT', symbol: '€', decimalDigits: 0);
  final _dateFmt = DateFormat('dd/MM/yyyy');

  static const _statusFilters = [
    TlStatusFilter(label: 'Aperto', value: 'open', color: Color(0xFF0369A1)),
    TlStatusFilter(label: 'Vinto', value: 'won', color: Color(0xFF034F3B)),
    TlStatusFilter(label: 'Perso', value: 'lost', color: Color(0xFFB91C1C)),
  ];

  String _customerName(Deal d) => d.customerId == null ? '—' : widget.companies.where((c) => c.id == d.customerId).firstOrNull?.name ?? '—';

  List<TlRow> get _tableRows {
    var list = widget.crmData.deals;
    if (_statusFilter != null) {
      final s = DealFirestoreStatus.values.firstWhere((v) => v.name == _statusFilter, orElse: () => DealFirestoreStatus.open);
      list = list.where((d) => d.status == s).toList();
    }
    return list.map((d) {
      final stage = widget.crmData.stageById(d.stageId);
      final status = d.status;
      return TlRow(
        key: d.id,
        onTap: widget.onOpenDetail != null ? () => widget.onOpenDetail!(d) : null,
        cells: [
          TlCell(widget: TlPrimaryCell(text: d.title, sub: _customerName(d))),
          TlCell(text: stage?.name ?? '—'),
          TlCell(widget: TlBadge(label: status.label, color: status.color)),
          TlCell(widget: TlAmountCell(text: _currFmt.format(d.value)), align: TextAlign.right),
          TlCell(text: '${d.probability}%'),
          TlCell(text: d.expectedClosingDate != null ? _dateFmt.format(d.expectedClosingDate!) : '—'),
          // Preventivi collegati a questo deal
          TlCell(widget: _QuotationsBadge(count: widget.crmData.quotationsForDeal(d.id).length)),
          TlCell(widget: _DealActions(d: d, crmRepo: widget.crmRepo, userId: widget.userId)),
        ],
      );
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final viewToggle = Row(mainAxisSize: MainAxisSize.min, children: [
      _ViewBtn(icon: Icons.view_list_outlined, active: !_kanbanView, onTap: () => setState(() => _kanbanView = false)),
      const SizedBox(width: 4),
      _ViewBtn(icon: Icons.view_kanban_outlined, active: _kanbanView, onTap: () => setState(() => _kanbanView = true)),
    ]);

    if (_kanbanView) {
      return Column(children: [
        Row(children: [
          const Text('Pipeline', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Color(0xFFB8C0D8))),
          const Spacer(),
          viewToggle,
          const SizedBox(width: 12),
          FilledButton.icon(onPressed: () => _showAddDialog(context), icon: const Icon(Icons.add, size: 16), label: const Text('Aggiungi opportunità')),
        ]),
        const SizedBox(height: 16),
        Expanded(child: _KanbanBoard(crmData: widget.crmData, companies: widget.companies, crmRepo: widget.crmRepo, userId: widget.userId, currFmt: _currFmt)),
      ]);
    }

    return TlTable(
      searchHint: 'Cerca opportunità...',
      columns: const [
        TlColumn(label: 'Titolo / Cliente', flex: 3),
        TlColumn(label: 'Stage', flex: 1),
        TlColumn(label: 'Stato', flex: 1),
        TlColumn(label: 'Valore', flex: 1, align: TextAlign.right),
        TlColumn(label: 'Prob.', flex: 1),
        TlColumn(label: 'Chiusura', flex: 1),
        TlColumn(label: 'Preventivi', flex: 1),
        TlColumn(label: '', minWidth: 40),
      ],
      rows: _tableRows,
      statusFilters: _statusFilters,
      selectedStatus: _statusFilter,
      onStatusChanged: (v) => setState(() => _statusFilter = v),
      onAdd: () => _showAddDialog(context),
      addLabel: 'Aggiungi opportunità',
      emptyMessage: 'Nessuna opportunità trovata.',
      extraActions: viewToggle,
    );
  }

  void _showAddDialog(BuildContext context) {
    showDialog<void>(context: context, builder: (_) => _AddDealDialog(stages: widget.crmData.sortedStages, companies: widget.companies, onSave: (d) => widget.crmRepo.createDeal(widget.userId, d)));
  }
}

// Badge che mostra il numero di preventivi collegati a un deal
class _QuotationsBadge extends StatelessWidget {
  const _QuotationsBadge({required this.count});
  final int count;
  @override
  Widget build(BuildContext context) {
    if (count == 0) return const Text('—', style: TextStyle(fontSize: 13, color: Color(0xFF525D78)));
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(Icons.description_outlined, size: 13, color: GussoniBrand.primary),
      const SizedBox(width: 4),
      Text('$count', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: GussoniBrand.primary)),
    ]);
  }
}

class _ViewBtn extends StatelessWidget {
  const _ViewBtn({required this.icon, required this.active, required this.onTap});
  final IconData icon; final bool active; final VoidCallback onTap;
  @override Widget build(BuildContext context) => InkWell(
    borderRadius: BorderRadius.circular(7),
    onTap: onTap,
    child: Container(
      width: 34, height: 34,
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(7), color: active ? GussoniBrand.primary : Colors.white, border: Border.all(color: active ? GussoniBrand.primary : const Color(0xFF1E2130))),
      child: Icon(icon, size: 17, color: active ? Colors.white : const Color(0xFF525D78)),
    ),
  );
}

class _DealActions extends StatelessWidget {
  const _DealActions({required this.d, required this.crmRepo, required this.userId});
  final Deal d; final FirestoreCrmRepository crmRepo; final String userId;
  @override Widget build(BuildContext context) => TlRowActions(items: [
    if (d.status == DealFirestoreStatus.open) ...[
      PopupMenuItem(value: 'won', child: const Text('Segna vinto'), onTap: () => crmRepo.updateDeal(userId, d.copyWith(status: DealFirestoreStatus.won))),
      PopupMenuItem(value: 'lost', child: const Text('Segna perso'), onTap: () => crmRepo.updateDeal(userId, d.copyWith(status: DealFirestoreStatus.lost))),
      const PopupMenuDivider(),
    ],
    PopupMenuItem(value: 'delete', child: const Text('Elimina', style: TextStyle(color: Color(0xFFB91C1C))), onTap: () => crmRepo.deleteDeal(userId, d.id)),
  ]);
}

// ── Kanban board ──

class _KanbanBoard extends StatelessWidget {
  const _KanbanBoard({required this.crmData, required this.companies, required this.crmRepo, required this.userId, required this.currFmt});
  final CrmData crmData; final List<Company> companies; final FirestoreCrmRepository crmRepo; final String userId; final NumberFormat currFmt;

  String _customer(Deal d) => d.customerId == null ? '—' : companies.where((c) => c.id == d.customerId).firstOrNull?.name ?? '—';

  @override
  Widget build(BuildContext context) {
    final stages = crmData.sortedStages;
    if (stages.isEmpty) return const Center(child: Text('Nessuna pipeline configurata.', style: TextStyle(color: Color(0xFF525D78))));
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: stages.map((stage) {
          final deals = crmData.deals.where((d) => d.stageId == stage.id && d.status == DealFirestoreStatus.open).toList();
          final total = deals.fold(0.0, (s, d) => s + d.value);
          return Container(
            width: 270,
            margin: const EdgeInsets.only(right: 12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Container(
                padding: const EdgeInsets.fromLTRB(12, 9, 12, 9),
                decoration: BoxDecoration(color: stage.color.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(10), border: Border.all(color: stage.color.withValues(alpha: 0.25))),
                child: Row(children: [
                  Container(width: 9, height: 9, decoration: BoxDecoration(shape: BoxShape.circle, color: stage.color)),
                  const SizedBox(width: 8),
                  Expanded(child: Text(stage.name, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: stage.color))),
                  TlBadge(label: '${deals.length}', color: stage.color),
                ]),
              ),
              Padding(padding: const EdgeInsets.fromLTRB(4, 4, 4, 8), child: Text(currFmt.format(total), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF525D78)))),
              ...deals.map((d) {
                final idx = stages.indexWhere((s) => s.id == d.stageId);
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFF1E2130)), boxShadow: const [BoxShadow(color: Color(0x0A000000), blurRadius: 4, offset: Offset(0, 2))]),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(d.title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800), maxLines: 2, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 4),
                    Text(_customer(d), style: const TextStyle(fontSize: 12, color: Color(0xFF7D89A8)), maxLines: 1, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 8),
                    Row(children: [
                      Text(currFmt.format(d.value), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900)),
                      const Spacer(),
                      Text('${d.probability}%', style: const TextStyle(fontSize: 11, color: Color(0xFF525D78))),
                    ]),
                    const SizedBox(height: 8),
                    ClipRRect(borderRadius: BorderRadius.circular(999), child: LinearProgressIndicator(value: d.probability / 100, minHeight: 3, backgroundColor: const Color(0xFF1E2130), valueColor: AlwaysStoppedAnimation<Color>(stage.color))),
                    const SizedBox(height: 6),
                    Row(children: [
                      if (idx > 0) GestureDetector(onTap: () => crmRepo.updateDeal(userId, d.copyWith(stageId: stages[idx - 1].id)), child: const Icon(Icons.arrow_back_ios_rounded, size: 13, color: Color(0xFF525D78))),
                      const Spacer(),
                      GestureDetector(onTap: () => crmRepo.updateDeal(userId, d.copyWith(status: DealFirestoreStatus.won)), child: const Icon(Icons.check_circle_outline, size: 15, color: Color(0xFF034F3B))),
                      const SizedBox(width: 6),
                      GestureDetector(onTap: () => crmRepo.deleteDeal(userId, d.id), child: const Icon(Icons.delete_outline, size: 15, color: Color(0xFF525D78))),
                      const Spacer(),
                      if (idx < stages.length - 1) GestureDetector(onTap: () => crmRepo.updateDeal(userId, d.copyWith(stageId: stages[idx + 1].id)), child: const Icon(Icons.arrow_forward_ios_rounded, size: 13, color: Color(0xFF525D78))),
                    ]),
                  ]),
                );
              }),
            ]),
          );
        }).toList(),
      ),
    );
  }
}

class _AddDealDialog extends StatefulWidget {
  const _AddDealDialog({required this.stages, required this.companies, required this.onSave});
  final List<DealStage> stages; final List<Company> companies; final Future<void> Function(Deal) onSave;
  @override State<_AddDealDialog> createState() => _AddDealDialogState();
}
class _AddDealDialogState extends State<_AddDealDialog> {
  final _titleCtrl = TextEditingController(); final _valueCtrl = TextEditingController();
  String? _stageId; String? _customerId; bool _saving = false;
  @override void initState() { super.initState(); _stageId = widget.stages.firstOrNull?.id; }
  @override void dispose() { _titleCtrl.dispose(); _valueCtrl.dispose(); super.dispose(); }
  Future<void> _save() async {
    if (_titleCtrl.text.trim().isEmpty || _stageId == null) return;
    setState(() => _saving = true);
    await widget.onSave(Deal(id: 'deal-${DateTime.now().microsecondsSinceEpoch}', title: _titleCtrl.text.trim(), stageId: _stageId!, status: DealFirestoreStatus.open, value: double.tryParse(_valueCtrl.text.replaceAll(',', '.')) ?? 0, customerId: _customerId, customerType: _customerId != null ? 'company' : null, createdAt: DateTime.now(), updatedAt: DateTime.now()));
    if (mounted) Navigator.of(context).pop();
  }
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Nuova opportunità', style: TextStyle(fontWeight: FontWeight.w800)),
    content: SizedBox(width: 460, child: Column(mainAxisSize: MainAxisSize.min, children: [
      TextField(controller: _titleCtrl, decoration: const InputDecoration(labelText: 'Titolo *', border: OutlineInputBorder()), autofocus: true),
      const SizedBox(height: 12),
      TextField(controller: _valueCtrl, decoration: const InputDecoration(labelText: 'Valore (€)', border: OutlineInputBorder(), prefixText: '€ '), keyboardType: const TextInputType.numberWithOptions(decimal: true)),
      const SizedBox(height: 12),
      DropdownButtonFormField<String>(initialValue: _stageId, decoration: const InputDecoration(labelText: 'Stage *', border: OutlineInputBorder()), items: widget.stages.map((s) => DropdownMenuItem(value: s.id, child: Text(s.name))).toList(), onChanged: (v) => setState(() => _stageId = v)),
      const SizedBox(height: 12),
      DropdownButtonFormField<String>(initialValue: _customerId, decoration: const InputDecoration(labelText: 'Azienda', border: OutlineInputBorder()), items: [const DropdownMenuItem(value: null, child: Text('— Nessuna —')), ...widget.companies.map((c) => DropdownMenuItem(value: c.id, child: Text(c.name)))], onChanged: (v) => setState(() => _customerId = v)),
    ])),
    actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Annulla')), FilledButton(onPressed: _saving ? null : _save, child: _saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Salva'))],
  );
}
