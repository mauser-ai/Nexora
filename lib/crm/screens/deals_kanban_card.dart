import '../../brand_config.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../data/crm_store.dart';
import '../models/crm_models.dart';

// ────────────────────────────────────────────────
// Deals Kanban Pipeline Card
// ────────────────────────────────────────────────

class DealsKanbanCard extends StatefulWidget {
  const DealsKanbanCard({super.key, required this.store});

  final CrmStore store;

  @override
  State<DealsKanbanCard> createState() => _DealsKanbanCardState();
}

class _DealsKanbanCardState extends State<DealsKanbanCard> {
  DealStatus _filter = DealStatus.open;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.store,
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _PipelineHeader(store: widget.store, filter: _filter, onFilterChanged: (f) => setState(() => _filter = f)),
          const SizedBox(height: 16),
          SizedBox(
            height: 620,
            child: _KanbanBoard(store: widget.store, filter: _filter),
          ),
        ],
      ),
    );
  }
}

// ── Pipeline header with stats ──

class _PipelineHeader extends StatelessWidget {
  const _PipelineHeader({required this.store, required this.filter, required this.onFilterChanged});

  final CrmStore store;
  final DealStatus filter;
  final ValueChanged<DealStatus> onFilterChanged;

  @override
  Widget build(BuildContext context) {
    final currencyFmt = NumberFormat.currency(locale: 'it_IT', symbol: '€', decimalDigits: 0);
    final allDeals = store.deals;
    final openDeals = allDeals.where((d) => d.status == DealStatus.open);
    final wonDeals = allDeals.where((d) => d.status == DealStatus.won);
    final lostDeals = allDeals.where((d) => d.status == DealStatus.lost);

    return Row(
      children: [
        _PipelineStat(
          label: 'In corso',
          count: openDeals.length,
          value: currencyFmt.format(openDeals.fold(0.0, (s, d) => s + d.value)),
          color: const Color(0xFF0369A1),
          selected: filter == DealStatus.open,
          onTap: () => onFilterChanged(DealStatus.open),
        ),
        const SizedBox(width: 12),
        _PipelineStat(
          label: 'Vinti',
          count: wonDeals.length,
          value: currencyFmt.format(wonDeals.fold(0.0, (s, d) => s + d.value)),
          color: GussoniBrand.primary,
          selected: filter == DealStatus.won,
          onTap: () => onFilterChanged(DealStatus.won),
        ),
        const SizedBox(width: 12),
        _PipelineStat(
          label: 'Persi',
          count: lostDeals.length,
          value: currencyFmt.format(lostDeals.fold(0.0, (s, d) => s + d.value)),
          color: const Color(0xFFB91C1C),
          selected: filter == DealStatus.lost,
          onTap: () => onFilterChanged(DealStatus.lost),
        ),
        const Spacer(),
        FilledButton.icon(
          onPressed: () => _showAddDealDialog(context),
          icon: const Icon(Icons.add, size: 16),
          label: const Text('Nuovo deal'),
        ),
      ],
    );
  }

  void _showAddDealDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (context) => _AddDealDialog(store: store),
    );
  }
}

class _PipelineStat extends StatelessWidget {
  const _PipelineStat({required this.label, required this.count, required this.value, required this.color, required this.selected, required this.onTap});

  final String label;
  final int count;
  final String value;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: selected ? color.withValues(alpha: 0.10) : const Color(0xFF0E1020),
          border: Border.all(color: selected ? color : const Color(0xFF1E2130), width: selected ? 1.5 : 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 8, height: 8, decoration: BoxDecoration(shape: BoxShape.circle, color: color)),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('$count $label', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: selected ? color : const Color(0xFFB8C0D8))),
                Text(value, style: TextStyle(fontSize: 12, color: selected ? color : const Color(0xFF525D78), fontWeight: FontWeight.w600)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Kanban Board ──

class _KanbanBoard extends StatelessWidget {
  const _KanbanBoard({required this.store, required this.filter});

  final CrmStore store;
  final DealStatus filter;

  @override
  Widget build(BuildContext context) {
    final stages = store.pipelineStages;
    if (stages.isEmpty) {
      return const Center(child: Text('Nessuna pipeline configurata.', style: TextStyle(color: Color(0xFF525D78))));
    }
    return ScrollConfiguration(
      behavior: const _NoGlowBehavior(),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: stages.map((stage) {
            final stageDeals = store.deals.where((d) => d.stageId == stage.id && d.status == filter).toList();
            return _KanbanColumn(stage: stage, deals: stageDeals, store: store, totalStages: stages.length);
          }).toList(),
        ),
      ),
    );
  }
}

class _KanbanColumn extends StatelessWidget {
  const _KanbanColumn({required this.stage, required this.deals, required this.store, required this.totalStages});

  final CrmPipelineStage stage;
  final List<CrmDeal> deals;
  final CrmStore store;
  final int totalStages;

  @override
  Widget build(BuildContext context) {
    final currencyFmt = NumberFormat.currency(locale: 'it_IT', symbol: '€', decimalDigits: 0);
    final totalValue = deals.fold(0.0, (s, d) => s + d.value);

    return Container(
      width: 280,
      margin: const EdgeInsets.only(right: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Column header
          Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            decoration: BoxDecoration(
              color: stage.color.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: stage.color.withValues(alpha: 0.25)),
            ),
            child: Row(
              children: [
                Container(width: 10, height: 10, decoration: BoxDecoration(shape: BoxShape.circle, color: stage.color)),
                const SizedBox(width: 8),
                Expanded(child: Text(stage.name, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: stage.color))),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(color: stage.color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(999)),
                  child: Text('${deals.length}', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: stage.color)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          // Total value
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(currencyFmt.format(totalValue), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF7D89A8))),
          ),
          const SizedBox(height: 8),
          // Deal cards
          Expanded(
            child: deals.isEmpty
                ? Container(
                    margin: const EdgeInsets.only(top: 4),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFF1E2130), style: BorderStyle.solid),
                    ),
                    child: const Center(
                      child: Padding(
                        padding: EdgeInsets.all(20),
                        child: Text('Nessun deal\nin questo stage', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: Color(0xFF525D78))),
                      ),
                    ),
                  )
                : ListView.separated(
                    itemCount: deals.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) => _DealCard(deal: deals[index], store: store, stage: stage),
                  ),
          ),
        ],
      ),
    );
  }
}

// ── Deal Card ──

class _DealCard extends StatelessWidget {
  const _DealCard({required this.deal, required this.store, required this.stage});

  final CrmDeal deal;
  final CrmStore store;
  final CrmPipelineStage stage;

  @override
  Widget build(BuildContext context) {
    final currencyFmt = NumberFormat.currency(locale: 'it_IT', symbol: '€', decimalDigits: 0);
    final customer = deal.customerType == 'company'
        ? store.companyById(deal.customerId)?.name
        : store.contactById(deal.customerId)?.fullName;
    final assignee = store.userById(deal.assignedTo);
    final stages = store.pipelineStages;
    final currentStageIndex = stages.indexWhere((s) => s.id == deal.stageId);
    final canMoveBack = currentStageIndex > 0;
    final canMoveForward = currentStageIndex < stages.length - 1;
    final closingFmt = deal.expectedClosingDate != null ? DateFormat('dd/MM/yy').format(deal.expectedClosingDate!) : null;
    final isOverdue = deal.expectedClosingDate != null && deal.expectedClosingDate!.isBefore(DateTime.now()) && deal.status == DealStatus.open;

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0E1020),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF1E2130)),
        boxShadow: const [BoxShadow(color: Color(0x0A000000), blurRadius: 6, offset: Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(deal.title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Color(0xFF0F172A)), maxLines: 2, overflow: TextOverflow.ellipsis),
                if (customer != null) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.apartment_outlined, size: 12, color: Color(0xFF525D78)),
                      const SizedBox(width: 4),
                      Expanded(child: Text(customer, style: const TextStyle(fontSize: 12, color: Color(0xFF7D89A8)), maxLines: 1, overflow: TextOverflow.ellipsis)),
                    ],
                  ),
                ],
                const SizedBox(height: 8),
                Row(
                  children: [
                    Text(currencyFmt.format(deal.value), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Color(0xFF0F172A))),
                    const Spacer(),
                    if (assignee != null) _InlineAvatar(name: assignee.fullName),
                  ],
                ),
                const SizedBox(height: 8),
                // Probability bar
                Row(
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(999),
                        child: LinearProgressIndicator(
                          value: deal.probability / 100,
                          minHeight: 4,
                          backgroundColor: const Color(0xFF1E2130),
                          valueColor: AlwaysStoppedAnimation<Color>(stage.color),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text('${deal.probability}%', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF7D89A8))),
                  ],
                ),
                if (closingFmt != null) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(Icons.event_outlined, size: 12, color: isOverdue ? const Color(0xFFB91C1C) : const Color(0xFF525D78)),
                      const SizedBox(width: 4),
                      Text(closingFmt, style: TextStyle(fontSize: 11, color: isOverdue ? const Color(0xFFB91C1C) : const Color(0xFF525D78), fontWeight: FontWeight.w600)),
                      if (isOverdue) ...[
                        const SizedBox(width: 4),
                        const Text('In ritardo', style: TextStyle(fontSize: 10, color: Color(0xFFB91C1C), fontWeight: FontWeight.w700)),
                      ],
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 10),
          Container(
            height: 1,
            color: const Color(0xFF0C0E1A),
          ),
          // Actions row
          Row(
            children: [
              if (canMoveBack)
                _CardAction(icon: Icons.arrow_back_ios_rounded, tooltip: 'Stage precedente', onTap: () {
                  final prev = store.pipelineStages[currentStageIndex - 1];
                  store.moveDeal(deal.id, prev.id);
                })
              else
                const SizedBox(width: 40),
              const Spacer(),
              _CardAction(icon: Icons.more_horiz_rounded, tooltip: 'Azioni', onTap: () => _showDealActions(context)),
              const Spacer(),
              if (canMoveForward)
                _CardAction(icon: Icons.arrow_forward_ios_rounded, tooltip: 'Stage successivo', onTap: () {
                  final next = store.pipelineStages[currentStageIndex + 1];
                  store.moveDeal(deal.id, next.id);
                })
              else
                const SizedBox(width: 40),
            ],
          ),
        ],
      ),
    );
  }

  void _showDealActions(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(deal.title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.check_circle_outline, color: Color(0xFF034F3B)),
              title: const Text('Segna come vinto'),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              onTap: () { store.closeDeal(deal.id, DealStatus.won); Navigator.pop(context); },
            ),
            ListTile(
              leading: const Icon(Icons.cancel_outlined, color: Color(0xFFB91C1C)),
              title: const Text('Segna come perso'),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              onTap: () { store.closeDeal(deal.id, DealStatus.lost); Navigator.pop(context); },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Color(0xFF7D89A8)),
              title: const Text('Elimina deal'),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              onTap: () { store.deleteDeal(deal.id); Navigator.pop(context); },
            ),
          ],
        ),
      ),
    );
  }
}

class _CardAction extends StatelessWidget {
  const _CardAction({required this.icon, required this.tooltip, required this.onTap});

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: SizedBox(
          width: 40,
          height: 34,
          child: Icon(icon, size: 14, color: const Color(0xFF525D78)),
        ),
      ),
    );
  }
}

class _InlineAvatar extends StatelessWidget {
  const _InlineAvatar({required this.name});

  final String name;

  Color _colorForName(String name) {
    const palette = [Color(0xFF0369A1), Color(0xFF7C3AED), Color(0xFF034F3B), Color(0xFFD97706)];
    final hash = name.codeUnits.fold<int>(0, (acc, c) => (acc * 31 + c));
    return palette[hash.abs() % palette.length];
  }

  String _initials(String name) {
    final parts = name.trim().split(' ');
    if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    return name.isNotEmpty ? name[0].toUpperCase() : '?';
  }

  @override
  Widget build(BuildContext context) {
    final color = _colorForName(name);
    return Tooltip(
      message: name,
      child: Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(shape: BoxShape.circle, color: color.withValues(alpha: 0.15), border: Border.all(color: color.withValues(alpha: 0.4))),
        child: Center(child: Text(_initials(name), style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: color))),
      ),
    );
  }
}

// ── Add Deal Dialog ──

class _AddDealDialog extends StatefulWidget {
  const _AddDealDialog({required this.store});

  final CrmStore store;

  @override
  State<_AddDealDialog> createState() => _AddDealDialogState();
}

class _AddDealDialogState extends State<_AddDealDialog> {
  final _titleController = TextEditingController();
  final _valueController = TextEditingController();
  String? _selectedStageId;
  String? _selectedCustomerId;
  String _customerType = 'company';
  String? _assignedTo;

  @override
  void initState() {
    super.initState();
    _selectedStageId = widget.store.pipelineStages.firstOrNull?.id;
    _assignedTo = widget.store.currentUser.id;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _valueController.dispose();
    super.dispose();
  }

  void _submit() {
    final title = _titleController.text.trim();
    final value = double.tryParse(_valueController.text.replaceAll(',', '.')) ?? 0;
    if (title.isEmpty || _selectedStageId == null) {
      return;
    }
    final deal = CrmDeal(
      id: 'deal-${DateTime.now().microsecondsSinceEpoch}',
      teamId: widget.store.teamId,
      title: title,
      stageId: _selectedStageId!,
      status: DealStatus.open,
      value: value,
      customerId: _selectedCustomerId,
      customerType: _selectedCustomerId != null ? _customerType : null,
      assignedTo: _assignedTo,
      createdBy: widget.store.currentUser.id,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    widget.store.addDeal(deal);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final stages = widget.store.pipelineStages;
    final companies = widget.store.companies;
    final users = widget.store.users;

    return AlertDialog(
      title: const Text('Nuovo deal', style: TextStyle(fontWeight: FontWeight.w800)),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _titleController,
              decoration: const InputDecoration(labelText: 'Titolo deal *', border: OutlineInputBorder()),
              autofocus: true,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _valueController,
              decoration: const InputDecoration(labelText: 'Valore (€)', border: OutlineInputBorder(), prefixText: '€ '),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _selectedStageId,
              decoration: const InputDecoration(labelText: 'Stage *', border: OutlineInputBorder()),
              items: stages.map((s) => DropdownMenuItem(value: s.id, child: Text(s.name))).toList(),
              onChanged: (v) => setState(() => _selectedStageId = v),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _selectedCustomerId,
              decoration: const InputDecoration(labelText: 'Azienda cliente', border: OutlineInputBorder()),
              items: [
                const DropdownMenuItem(value: null, child: Text('– Nessuna –')),
                ...companies.map((c) => DropdownMenuItem(value: c.id, child: Text(c.name))),
              ],
              onChanged: (v) => setState(() { _selectedCustomerId = v; _customerType = 'company'; }),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _assignedTo,
              decoration: const InputDecoration(labelText: 'Assegnato a', border: OutlineInputBorder()),
              items: users.map((u) => DropdownMenuItem(value: u.id, child: Text(u.fullName))).toList(),
              onChanged: (v) => setState(() => _assignedTo = v),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Annulla')),
        FilledButton(onPressed: _submit, child: const Text('Crea deal')),
      ],
    );
  }
}

// ── Scroll behavior to remove glow ──

class _NoGlowBehavior extends ScrollBehavior {
  const _NoGlowBehavior();

  @override
  Widget buildOverscrollIndicator(BuildContext context, Widget child, ScrollableDetails details) => child;
}
