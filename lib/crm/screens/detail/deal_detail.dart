import '../../../brand_config.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../data/firestore_workspace_repository.dart';
import '../../../models/domain_models.dart';
import '../../data/firestore_crm_repository.dart';
import '../../models/crm_extra_models.dart';
import 'detail_widgets.dart';

class DealDetailPage extends StatefulWidget {
  const DealDetailPage({
    super.key,
    required this.deal,
    required this.workspace,
    required this.crmData,
    required this.crmRepo,
    required this.userId,
    required this.onBack,
    required this.onEdit,
    this.onOpenQuotation,
    this.onOpenProject,
    this.onOpenTask,
  });

  final Deal deal;
  final WorkspaceSnapshot workspace;
  final CrmData crmData;
  final FirestoreCrmRepository crmRepo;
  final String userId;
  final VoidCallback onBack;
  final Future<void> Function(Deal) onEdit;
  final void Function(Quotation quotation)? onOpenQuotation;
  final void Function(Project project)? onOpenProject;
  final void Function(WorkTask task)? onOpenTask;

  @override
  State<DealDetailPage> createState() => _DealDetailPageState();
}

class _DealDetailPageState extends State<DealDetailPage> {
  late Deal _deal;
  final _currFmt = NumberFormat.currency(
    locale: 'it_IT',
    symbol: '€',
    decimalDigits: 2,
  );
  final _dateFmt = DateFormat('dd/MM/yyyy');

  @override
  void initState() {
    super.initState();
    _deal = widget.deal;
  }

  DealStage? get _stage => widget.crmData.stageById(_deal.stageId);

  String get _customerName => _deal.customerType == 'contact'
      ? widget.crmData.contactById(_deal.customerId)?.fullName ?? '—'
      : widget.workspace.companies
                .where((c) => c.id == _deal.customerId)
                .firstOrNull
                ?.name ??
            '—';

  List<Quotation> get _quotations => widget.crmData.quotationsForDeal(_deal.id);

  List<Project> get _projects =>
      widget.workspace.projects.where((p) => p.dealId == _deal.id).toList();

  List<WorkTask> get _tasks => widget.workspace.tasks
      .where((t) => t.companyId == _deal.customerId)
      .toList();

  @override
  Widget build(BuildContext context) {
    final stage = _stage;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DetailBackBar(
            label: 'Panoramica opportunità',
            onBack: widget.onBack,
            actions: [
              if (_deal.status == DealFirestoreStatus.open) ...[
                FilledButton.icon(
                  onPressed: () async {
                    await widget.crmRepo.updateDeal(
                      widget.userId,
                      _deal.copyWith(status: DealFirestoreStatus.won),
                    );
                    widget.onBack();
                  },
                  icon: const Icon(Icons.check_circle_outline, size: 15),
                  label: const Text('Segna vinto'),
                  style: FilledButton.styleFrom(
                    backgroundColor: GussoniBrand.primary,
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: () async {
                    await widget.crmRepo.updateDeal(
                      widget.userId,
                      _deal.copyWith(status: DealFirestoreStatus.lost),
                    );
                    widget.onBack();
                  },
                  child: const Text('Segna perso'),
                ),
              ],
            ],
          ),
          LayoutBuilder(
            builder: (context, c) {
              final wide = c.maxWidth > 800;
              final infoCard = DetailInfoCard(
                title: 'Informazioni opportunità',
                onEdit: () => widget.onEdit(_deal),
                avatar: Row(
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        color: GussoniBrand.primary.withValues(alpha: 0.10),
                      ),
                      child: const Icon(
                        Icons.trending_up_outlined,
                        size: 26,
                        color: Color(0xFF034F3B),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _deal.title,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFFE4E8FF),
                            ),
                          ),
                          if (stage != null)
                            DetailBadge(label: stage.name, color: stage.color),
                        ],
                      ),
                    ),
                  ],
                ),
                rows: [
                  DetailInfoRow(label: 'Stato', value: _deal.status.label),
                  DetailInfoRow(label: 'Cliente', value: _customerName),
                  DetailInfoRow(
                    label: 'Valore',
                    value: _currFmt.format(_deal.value),
                  ),
                  DetailInfoRow(
                    label: 'Probabilità',
                    value: '${_deal.probability}%',
                  ),
                  if (_deal.expectedClosingDate != null)
                    DetailInfoRow(
                      label: 'Chiusura prevista',
                      value: _dateFmt.format(_deal.expectedClosingDate!),
                    ),
                  if (_deal.notes.isNotEmpty)
                    DetailInfoRow(label: 'Note', value: _deal.notes),
                  if (_deal.createdAt != null)
                    DetailInfoRow(
                      label: 'Creato il',
                      value: _dateFmt.format(_deal.createdAt!),
                    ),
                ],
              );
              final statusCard = _DealStatusCard(
                deal: _deal,
                stages: widget.crmData.sortedStages,
                crmRepo: widget.crmRepo,
                userId: widget.userId,
                onMoved: (d) => setState(() => _deal = d),
              );

              if (wide)
                return IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 3, child: infoCard),
                      const SizedBox(width: 16),
                      Expanded(flex: 2, child: statusCard),
                    ],
                  ),
                );
              return Column(
                children: [infoCard, const SizedBox(height: 12), statusCard],
              );
            },
          ),
          const SizedBox(height: 20),

          // Preventivi collegati
          DetailAccordion(
            title: 'Preventivi',
            count: _quotations.length,
            children: _quotations
                .map(
                  (q) => Column(
                    children: [
                      AccordionRow(
                        leading: Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: q.status.color,
                          ),
                        ),
                        title: q.number,
                        subtitle: q.createdAt != null
                            ? _dateFmt.format(q.createdAt!)
                            : null,
                        trailing: Text(
                          _currFmt.format(q.total),
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        badge: DetailBadge(
                          label: q.status.label,
                          color: q.status.color,
                        ),
                        onTap: widget.onOpenQuotation == null
                            ? null
                            : () => widget.onOpenQuotation!(q),
                      ),
                      const AccordionDivider(),
                    ],
                  ),
                )
                .toList(),
          ),

          // Progetto collegato
          DetailAccordion(
            title: 'Progetto collegato',
            count: _projects.length,
            children: _projects
                .map(
                  (p) => Column(
                    children: [
                      AccordionRow(
                        leading: const Icon(
                          Icons.folder_open_outlined,
                          size: 18,
                          color: Color(0xFF034F3B),
                        ),
                        title: p.name,
                        subtitle: p.code.isNotEmpty ? 'Cod: ${p.code}' : null,
                        onTap: widget.onOpenProject == null
                            ? null
                            : () => widget.onOpenProject!(p),
                      ),
                      const AccordionDivider(),
                    ],
                  ),
                )
                .toList(),
          ),

          // Task
          DetailAccordion(
            title: 'Task',
            count: _tasks.length,
            children: _tasks
                .map(
                  (t) => Column(
                    children: [
                      AccordionRow(
                        leading: Icon(
                          t.status == TaskStatus.done
                              ? Icons.check_circle
                              : Icons.radio_button_unchecked,
                          size: 18,
                          color: t.status == TaskStatus.done
                              ? GussoniBrand.primary
                              : const Color(0xFF1E2130),
                        ),
                        title: t.name,
                        subtitle: 'Scadenza: ${_dateFmt.format(t.deadline)}',
                        onTap: widget.onOpenTask == null
                            ? null
                            : () => widget.onOpenTask!(t),
                      ),
                      const AccordionDivider(),
                    ],
                  ),
                )
                .toList(),
          ),

          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

// ── Pipeline status card ──
class _DealStatusCard extends StatelessWidget {
  const _DealStatusCard({
    required this.deal,
    required this.stages,
    required this.crmRepo,
    required this.userId,
    required this.onMoved,
  });
  final Deal deal;
  final List<DealStage> stages;
  final FirestoreCrmRepository crmRepo;
  final String userId;
  final ValueChanged<Deal> onMoved;

  @override
  Widget build(BuildContext context) {
    final currIdx = stages.indexWhere((s) => s.id == deal.stageId);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF0E1020),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF1E2130)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Pipeline',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: Color(0xFFE4E8FF),
            ),
          ),
          const SizedBox(height: 16),
          ...List.generate(stages.length, (i) {
            final stage = stages[i];
            final isCurrent = i == currIdx;
            final isPast = i < currIdx;
            final color = isCurrent
                ? stage.color
                : isPast
                ? GussoniBrand.primary
                : const Color(0xFF1E2130);
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: isCurrent
                    ? null
                    : () async {
                        final updated = deal.copyWith(stageId: stage.id);
                        await crmRepo.updateDeal(userId, updated);
                        onMoved(updated);
                      },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    color: isCurrent
                        ? stage.color.withValues(alpha: 0.08)
                        : Colors.transparent,
                    border: Border.all(
                      color: isCurrent ? stage.color : const Color(0xFF0C0E1A),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: color,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          stage.name,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: isCurrent
                                ? FontWeight.w800
                                : FontWeight.w500,
                            color: isCurrent
                                ? stage.color
                                : const Color(0xFFB8C0D8),
                          ),
                        ),
                      ),
                      Text(
                        '${stage.probability}%',
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF525D78),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}
