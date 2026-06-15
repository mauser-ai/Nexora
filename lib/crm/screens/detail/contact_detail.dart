import '../../../brand_config.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../data/firestore_workspace_repository.dart';
import '../../../models/domain_models.dart';
import '../../data/firestore_crm_repository.dart';
import '../../models/crm_extra_models.dart';
import 'detail_widgets.dart';

class ContactDetailPage extends StatefulWidget {
  const ContactDetailPage({
    super.key,
    required this.contact,
    required this.workspace,
    required this.crmData,
    required this.crmRepo,
    required this.userId,
    required this.onBack,
    required this.onEdit,
    required this.onDelete,
    this.onAddDeal,
    this.onAddQuotation,
    this.onAddTask,
    this.onOpenDeal,
    this.onOpenQuotation,
    this.onOpenTask,
  });

  final CrmFirestoreContact contact;
  final WorkspaceSnapshot workspace;
  final CrmData crmData;
  final FirestoreCrmRepository crmRepo;
  final String userId;
  final VoidCallback onBack;
  final Future<void> Function(CrmFirestoreContact) onEdit;
  final Future<void> Function() onDelete;
  final VoidCallback? onAddDeal;
  final VoidCallback? onAddQuotation;
  final VoidCallback? onAddTask;
  final void Function(Deal deal)? onOpenDeal;
  final void Function(Quotation quotation)? onOpenQuotation;
  final void Function(WorkTask task)? onOpenTask;

  @override
  State<ContactDetailPage> createState() => _ContactDetailPageState();
}

class _ContactDetailPageState extends State<ContactDetailPage> {
  late CrmFirestoreContact _contact;
  final _currFmt = NumberFormat.currency(
    locale: 'it_IT',
    symbol: '€',
    decimalDigits: 0,
  );

  @override
  void initState() {
    super.initState();
    _contact = widget.contact;
  }

  Company? get _company => _contact.companyId == null
      ? null
      : widget.workspace.companies
            .where((c) => c.id == _contact.companyId)
            .firstOrNull;

  List<Deal> get _deals => widget.crmData.dealsForCustomer(_contact.id);

  List<Quotation> get _quotations =>
      widget.crmData.quotationsForCustomer(_contact.id);

  List<WorkTask> get _tasks => widget.workspace.tasks
      .where((t) => t.assigneeId == _contact.id || t.companyId == _contact.id)
      .toList();

  @override
  Widget build(BuildContext context) {
    final color = colorForName(_contact.fullName);

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DetailBackBar(
            label: 'Panoramica contatti',
            onBack: widget.onBack,
            actions: [
              OutlinedButton.icon(
                onPressed: () async {
                  await widget.onDelete();
                  widget.onBack();
                },
                icon: const Icon(Icons.delete_outline, size: 15),
                label: const Text('Elimina'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFB91C1C),
                  side: const BorderSide(color: Color(0xFFB91C1C)),
                ),
              ),
            ],
          ),
          LayoutBuilder(
            builder: (context, c) {
              final wide = c.maxWidth > 800;
              final infoCard = DetailInfoCard(
                title: 'Informazioni sul contatto',
                onEdit: () => widget.onEdit(_contact),
                avatar: Row(
                  children: [
                    EntityAvatar(
                      initials: _contact.initials,
                      color: color,
                      size: 52,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _contact.fullName,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFFE4E8FF),
                            ),
                          ),
                          if (_contact.role.isNotEmpty)
                            Text(
                              _contact.role,
                              style: const TextStyle(
                                fontSize: 13,
                                color: Color(0xFF7D89A8),
                              ),
                            ),
                          if (_company != null) ...[
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                const Icon(
                                  Icons.apartment_outlined,
                                  size: 13,
                                  color: Color(0xFF034F3B),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  _company!.name,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: Color(0xFF034F3B),
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
                rows: [
                  if (_contact.email.isNotEmpty)
                    DetailInfoRow(
                      label: 'E-mail',
                      value: _contact.email,
                      isLink: true,
                    ),
                  if (_contact.phone.isNotEmpty)
                    DetailInfoRow(label: 'Telefono', value: _contact.phone),
                  if (_contact.notes.isNotEmpty)
                    DetailInfoRow(label: 'Note', value: _contact.notes),
                  if (_contact.createdAt != null)
                    DetailInfoRow(
                      label: 'Aggiunto il',
                      value: DateFormat(
                        'dd/MM/yyyy',
                      ).format(_contact.createdAt!),
                    ),
                ],
                tags: _contact.tags,
              );
              final notesCard = DetailNotesCard(
                notes: _contact.notes,
                onSave: (notes) async {
                  final updated = _contact.copyWith(notes: notes);
                  await widget.crmRepo.updateContact(widget.userId, updated);
                  setState(() => _contact = updated);
                },
              );
              if (wide)
                return IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 3, child: infoCard),
                      const SizedBox(width: 16),
                      Expanded(flex: 2, child: notesCard),
                    ],
                  ),
                );
              return Column(
                children: [infoCard, const SizedBox(height: 12), notesCard],
              );
            },
          ),
          const SizedBox(height: 20),

          // Opportunità collegate
          DetailAccordion(
            title: 'Opportunità',
            count: _deals.length,
            onAdd: widget.onAddDeal,
            children: _deals.map((d) {
              final stage = widget.crmData.stageById(d.stageId);
              return Column(
                children: [
                  AccordionRow(
                    leading: Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: d.status.color,
                      ),
                    ),
                    title: d.title,
                    subtitle: stage?.name,
                    trailing: Text(
                      _currFmt.format(d.value),
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    badge: DetailBadge(
                      label: d.status.label,
                      color: d.status.color,
                    ),
                    onTap: widget.onOpenDeal == null
                        ? null
                        : () => widget.onOpenDeal!(d),
                  ),
                  const AccordionDivider(),
                ],
              );
            }).toList(),
          ),

          // Preventivi
          DetailAccordion(
            title: 'Preventivi',
            count: _quotations.length,
            onAdd: widget.onAddQuotation,
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

          // Task
          DetailAccordion(
            title: 'Task',
            count: _tasks.length,
            onAdd: widget.onAddTask,
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
                        subtitle:
                            'Scadenza: ${DateFormat('dd/MM/yyyy').format(t.deadline)}',
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
