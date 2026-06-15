import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/domain_models.dart';
import '../data/firestore_crm_repository.dart';
import '../models/crm_extra_models.dart';

class OrdiniDiLavoroCard extends StatefulWidget {
  const OrdiniDiLavoroCard({super.key, required this.crmData, required this.companies, required this.crmRepo, required this.userId});
  final CrmData crmData; final List<Company> companies; final FirestoreCrmRepository crmRepo; final String userId;
  @override State<OrdiniDiLavoroCard> createState() => _OrdiniDiLavoroCardState();
}

class _OrdiniDiLavoroCardState extends State<OrdiniDiLavoroCard> {
  WorkOrderStatus? _statusFilter;
  final _dateFmt = DateFormat('dd/MM/yy');

  List<WorkOrder> get _filtered => _statusFilter == null ? widget.crmData.workOrders : widget.crmData.workOrders.where((w) => w.status == _statusFilter).toList();

  String _companyName(WorkOrder w) => w.companyId == null ? '—' : widget.companies.where((c) => c.id == w.companyId).firstOrNull?.name ?? '—';

  @override
  Widget build(BuildContext context) {
    final orders = _filtered;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // ── Toolbar ──
      Row(children: [
        ...[null, ...WorkOrderStatus.values].map((s) {
          final label = s == null ? 'Tutti' : s.label;
          final color = s == null ? const Color(0xFFB8C0D8) : s.color;
          final count = s == null ? widget.crmData.workOrders.length : widget.crmData.workOrders.where((w) => w.status == s).length;
          return Padding(padding: const EdgeInsets.only(right: 8), child: _FilterBtn(label: '$label ($count)', color: color, selected: _statusFilter == s, onTap: () => setState(() => _statusFilter = s)));
        }),
        const Spacer(),
        FilledButton.icon(onPressed: () => _showAddDialog(context), icon: const Icon(Icons.add, size: 16), label: const Text('Nuovo ordine')),
      ]),
      const SizedBox(height: 16),
      // ── List ──
      Container(
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0xFF1E2130))),
        child: orders.isEmpty
            ? const Padding(padding: EdgeInsets.all(24), child: Center(child: Text('Nessun ordine di lavoro.', style: TextStyle(color: Color(0xFF525D78)))))
            : Column(children: orders.map((w) => Column(children: [
                InkWell(
                  onTap: () {},
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: Row(children: [
                      // Priority dot
                      Container(width: 10, height: 10, decoration: BoxDecoration(shape: BoxShape.circle, color: w.priority.color)),
                      const SizedBox(width: 12),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Expanded(child: Text(w.title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF0F172A)), maxLines: 1, overflow: TextOverflow.ellipsis)),
                          _StatusBadge(status: w.status),
                        ]),
                        const SizedBox(height: 3),
                        Row(children: [
                          const Icon(Icons.apartment_outlined, size: 12, color: Color(0xFF525D78)),
                          const SizedBox(width: 4),
                          Text(_companyName(w), style: const TextStyle(fontSize: 12, color: Color(0xFF7D89A8))),
                          if (w.dueDate != null) ...[
                            const SizedBox(width: 12),
                            Icon(Icons.schedule_outlined, size: 12, color: w.isOverdue ? const Color(0xFFB91C1C) : const Color(0xFF525D78)),
                            const SizedBox(width: 4),
                            Text(_dateFmt.format(w.dueDate!), style: TextStyle(fontSize: 12, color: w.isOverdue ? const Color(0xFFB91C1C) : const Color(0xFF525D78), fontWeight: w.isOverdue ? FontWeight.w700 : FontWeight.normal)),
                          ],
                        ]),
                      ])),
                      // Actions
                      PopupMenuButton<String>(
                        icon: const Icon(Icons.more_horiz, size: 18, color: Color(0xFF525D78)),
                        onSelected: (v) async {
                          if (v == 'delete') { await widget.crmRepo.deleteWorkOrder(widget.userId, w.id); return; }
                          final newStatus = WorkOrderStatus.values.firstWhere((s) => s.name == v);
                          await widget.crmRepo.updateWorkOrder(widget.userId, w.copyWith(status: newStatus));
                        },
                        itemBuilder: (_) => [
                          if (w.status != WorkOrderStatus.inProgress) const PopupMenuItem(value: 'inProgress', child: Text('Imposta In corso')),
                          if (w.status != WorkOrderStatus.done) const PopupMenuItem(value: 'done', child: Text('Segna completato')),
                          if (w.status != WorkOrderStatus.cancelled) const PopupMenuItem(value: 'cancelled', child: Text('Annulla')),
                          const PopupMenuDivider(),
                          const PopupMenuItem(value: 'delete', child: Text('Elimina', style: TextStyle(color: Color(0xFFB91C1C)))),
                        ],
                      ),
                    ]),
                  ),
                ),
                const Divider(height: 1, color: Color(0xFF0C0E1A)),
              ])).toList()),
      ),
    ]);
  }

  void _showAddDialog(BuildContext context) {
    showDialog<void>(context: context, builder: (ctx) => _AddWorkOrderDialog(companies: widget.companies, onSave: (w) => widget.crmRepo.createWorkOrder(widget.userId, w)));
  }
}

class _FilterBtn extends StatelessWidget {
  const _FilterBtn({required this.label, required this.color, required this.selected, required this.onTap});
  final String label; final Color color; final bool selected; final VoidCallback onTap;
  @override Widget build(BuildContext context) => InkWell(borderRadius: BorderRadius.circular(8), onTap: onTap, child: Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7), decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), color: selected ? color.withValues(alpha: 0.10) : Colors.white, border: Border.all(color: selected ? color : const Color(0xFF1E2130))), child: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: selected ? color : const Color(0xFF7D89A8)))));
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});
  final WorkOrderStatus status;
  @override Widget build(BuildContext context) => Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3), decoration: BoxDecoration(borderRadius: BorderRadius.circular(999), color: status.color.withValues(alpha: 0.10), border: Border.all(color: status.color.withValues(alpha: 0.30))), child: Text(status.label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: status.color)));
}

class _AddWorkOrderDialog extends StatefulWidget {
  const _AddWorkOrderDialog({required this.companies, required this.onSave});
  final List<Company> companies; final Future<void> Function(WorkOrder) onSave;
  @override State<_AddWorkOrderDialog> createState() => _AddWorkOrderDialogState();
}

class _AddWorkOrderDialogState extends State<_AddWorkOrderDialog> {
  final _titleCtrl = TextEditingController(); final _descCtrl = TextEditingController();
  WorkOrderPriority _priority = WorkOrderPriority.medium; String? _companyId; DateTime? _dueDate; bool _saving = false;

  @override void dispose() { _titleCtrl.dispose(); _descCtrl.dispose(); super.dispose(); }

  Future<void> _pickDate() async {
    final d = await showDatePicker(context: context, initialDate: DateTime.now().add(const Duration(days: 7)), firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 365)));
    if (d != null) setState(() => _dueDate = d);
  }

  Future<void> _save() async {
    if (_titleCtrl.text.trim().isEmpty) return;
    setState(() => _saving = true);
    await widget.onSave(WorkOrder(id: 'wo-${DateTime.now().microsecondsSinceEpoch}', title: _titleCtrl.text.trim(), status: WorkOrderStatus.open, priority: _priority, companyId: _companyId, description: _descCtrl.text.trim(), dueDate: _dueDate, createdAt: DateTime.now()));
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Nuovo ordine di lavoro', style: TextStyle(fontWeight: FontWeight.w800)),
    content: SizedBox(width: 460, child: Column(mainAxisSize: MainAxisSize.min, children: [
      TextField(controller: _titleCtrl, decoration: const InputDecoration(labelText: 'Titolo *', border: OutlineInputBorder()), autofocus: true),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(child: DropdownButtonFormField<WorkOrderPriority>(value: _priority, decoration: const InputDecoration(labelText: 'Priorità', border: OutlineInputBorder()), items: WorkOrderPriority.values.map((p) => DropdownMenuItem(value: p, child: Text(p.label))).toList(), onChanged: (v) => setState(() => _priority = v ?? WorkOrderPriority.medium))),
        const SizedBox(width: 12),
        Expanded(child: DropdownButtonFormField<String>(initialValue: _companyId, decoration: const InputDecoration(labelText: 'Azienda', border: OutlineInputBorder()), items: [const DropdownMenuItem(value: null, child: Text('— Nessuna —')), ...widget.companies.map((c) => DropdownMenuItem(value: c.id, child: Text(c.name)))], onChanged: (v) => setState(() => _companyId = v))),
      ]),
      const SizedBox(height: 12),
      InkWell(onTap: _pickDate, child: InputDecorator(decoration: const InputDecoration(labelText: 'Scadenza', border: OutlineInputBorder()), child: Text(_dueDate != null ? DateFormat('dd/MM/yyyy').format(_dueDate!) : 'Seleziona data'))),
      const SizedBox(height: 12),
      TextField(controller: _descCtrl, decoration: const InputDecoration(labelText: 'Note', border: OutlineInputBorder()), maxLines: 3),
    ])),
    actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Annulla')), FilledButton(onPressed: _saving ? null : _save, child: _saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Salva'))],
  );
}
