import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/domain_models.dart';
import '../data/firestore_crm_repository.dart';
import '../models/crm_extra_models.dart';
import 'tl_table.dart';

class ContattiFirestoreCard extends StatefulWidget {
  const ContattiFirestoreCard({super.key, required this.crmData, required this.companies, required this.crmRepo, required this.userId, this.onOpenDetail});
  final CrmData crmData; final List<Company> companies; final FirestoreCrmRepository crmRepo; final String userId;
  final void Function(CrmFirestoreContact)? onOpenDetail;
  @override State<ContattiFirestoreCard> createState() => _ContattiFirestoreCardState();
}

class _ContattiFirestoreCardState extends State<ContattiFirestoreCard> {
  CrmFirestoreContact? _selected;

  String _companyName(CrmFirestoreContact c) =>
      c.companyId == null ? '—' : widget.companies.where((co) => co.id == c.companyId).firstOrNull?.name ?? '—';

  Color _avatarColor(String name) {
    const p = [Color(0xFF0369A1), Color(0xFF7C3AED), Color(0xFF034F3B), Color(0xFFD97706), Color(0xFF0891B2)];
    return p[name.codeUnits.fold<int>(0, (a, c) => a * 31 + c).abs() % p.length];
  }

  Widget _avatar(CrmFirestoreContact c) {
    final color = _avatarColor(c.fullName);
    return Container(
      width: 28, height: 28,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color.withValues(alpha: 0.15), border: Border.all(color: color.withValues(alpha: 0.4))),
      child: Center(child: Text(c.initials, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: color))),
    );
  }

  List<TlRow> get _rows => widget.crmData.contacts.map((c) => TlRow(
    key: c.id,
    onTap: () => widget.onOpenDetail != null ? widget.onOpenDetail!(c) : setState(() => _selected = c),
    cells: [
      TlCell(widget: Row(children: [_avatar(c), const SizedBox(width: 10), Expanded(child: TlPrimaryCell(text: c.fullName, sub: c.role.isEmpty ? null : c.role))])),
      TlCell(text: _companyName(c)),
      TlCell(text: c.email.isEmpty ? '—' : c.email),
      TlCell(text: c.phone.isEmpty ? '—' : c.phone),
      TlCell(text: c.createdAt != null ? DateFormat('dd/MM/yyyy').format(c.createdAt!) : '—'),
      TlCell(widget: TlRowActions(items: [
        PopupMenuItem(value: 'delete', child: const Text('Elimina', style: TextStyle(color: Color(0xFFB91C1C))), onTap: () => widget.crmRepo.deleteContact(widget.userId, c.id)),
      ])),
    ],
  )).toList();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final showDetail = _selected != null && c.maxWidth > 780;
      return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Expanded(
          flex: showDetail ? 3 : 1,
          child: TlTable(
            searchHint: 'Cerca contatti...',
            columns: const [
              TlColumn(label: 'Nome', flex: 2),
              TlColumn(label: 'Azienda', flex: 2),
              TlColumn(label: 'Email', flex: 2),
              TlColumn(label: 'Telefono', flex: 1),
              TlColumn(label: 'Aggiunto', flex: 1),
              TlColumn(label: '', minWidth: 40),
            ],
            rows: _rows,
            onAdd: () => _showAddDialog(context),
            addLabel: 'Aggiungi contatto',
            emptyMessage: 'Nessun contatto trovato.',
          ),
        ),
        if (showDetail) ...[
          const SizedBox(width: 16),
          SizedBox(
            width: 320,
            child: _ContactSidePanel(
              contact: _selected!,
              companyName: _companyName(_selected!),
              crmData: widget.crmData,
              onClose: () => setState(() => _selected = null),
              onDelete: () async { await widget.crmRepo.deleteContact(widget.userId, _selected!.id); setState(() => _selected = null); },
            ),
          ),
        ],
      ]);
    });
  }

  void _showAddDialog(BuildContext context) {
    showDialog<void>(context: context, builder: (ctx) => _AddContactDialog(companies: widget.companies, onSave: (c) => widget.crmRepo.createContact(widget.userId, c)));
  }
}

// ── Side panel detail ──

class _ContactSidePanel extends StatelessWidget {
  const _ContactSidePanel({required this.contact, required this.companyName, required this.crmData, required this.onClose, required this.onDelete});
  final CrmFirestoreContact contact; final String companyName; final CrmData crmData; final VoidCallback onClose; final VoidCallback onDelete;

  Color _color(String n) {
    const p = [Color(0xFF0369A1), Color(0xFF7C3AED), Color(0xFF034F3B), Color(0xFFD97706)];
    return p[n.codeUnits.fold<int>(0, (a, c) => a * 31 + c).abs() % p.length];
  }

  @override
  Widget build(BuildContext context) {
    final relatedDeals = crmData.deals.where((d) => d.customerId == contact.id).toList();
    final currFmt = NumberFormat.currency(locale: 'it_IT', symbol: '€', decimalDigits: 0);
    final color = _color(contact.fullName);

    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFE2D7C9))),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(width: 48, height: 48, decoration: BoxDecoration(shape: BoxShape.circle, color: color.withValues(alpha: 0.15), border: Border.all(color: color.withValues(alpha: 0.4))),
              child: Center(child: Text(contact.initials, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: color)))),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(contact.fullName, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Color(0xFFE4E8FF))),
              if (contact.role.isNotEmpty) Text(contact.role, style: const TextStyle(fontSize: 12, color: Color(0xFF7D89A8))),
            ])),
            IconButton(onPressed: onClose, icon: const Icon(Icons.close, size: 18, color: Color(0xFF8C8478))),
          ]),
          const SizedBox(height: 16),
          const Divider(color: Color(0xFFE8DFD3)),
          const SizedBox(height: 12),
          if (companyName != '—') _InfoLine(Icons.apartment_outlined, companyName),
          if (contact.email.isNotEmpty) _InfoLine(Icons.email_outlined, contact.email),
          if (contact.phone.isNotEmpty) _InfoLine(Icons.phone_outlined, contact.phone),
          if (contact.notes.isNotEmpty) _InfoLine(Icons.notes_outlined, contact.notes),
          if (relatedDeals.isNotEmpty) ...[
            const SizedBox(height: 16),
            const Text('Opportunità', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF8C8478), letterSpacing: 0.5)),
            const SizedBox(height: 8),
            ...relatedDeals.map((d) {
              final stage = crmData.stageById(d.stageId);
              return Padding(padding: const EdgeInsets.only(bottom: 8), child: Row(children: [
                Expanded(child: Text(d.title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis)),
                if (stage != null) ...[const SizedBox(width: 6), TlBadge(label: stage.name, color: stage.color)],
                const SizedBox(width: 6),
                Text(currFmt.format(d.value), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
              ]));
            }),
          ],
          const SizedBox(height: 16),
          OutlinedButton.icon(onPressed: onDelete, icon: const Icon(Icons.delete_outline, size: 15), label: const Text('Elimina contatto'), style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFFB91C1C), side: const BorderSide(color: Color(0xFFB91C1C)))),
        ]),
      ),
    );
  }
}

class _InfoLine extends StatelessWidget {
  const _InfoLine(this.icon, this.text);
  final IconData icon; final String text;
  @override Widget build(BuildContext context) => Padding(padding: const EdgeInsets.only(bottom: 8), child: Row(children: [Icon(icon, size: 14, color: const Color(0xFF8C8478)), const SizedBox(width: 8), Expanded(child: Text(text, style: const TextStyle(fontSize: 13, color: Color(0xFFB8C0D8)), maxLines: 2, overflow: TextOverflow.ellipsis))]));
}

// ── Add dialog ──
class _AddContactDialog extends StatefulWidget {
  const _AddContactDialog({required this.companies, required this.onSave});
  final List<Company> companies; final Future<void> Function(CrmFirestoreContact) onSave;
  @override State<_AddContactDialog> createState() => _AddContactDialogState();
}
class _AddContactDialogState extends State<_AddContactDialog> {
  final _fn = TextEditingController(); final _ln = TextEditingController();
  final _email = TextEditingController(); final _phone = TextEditingController(); final _role = TextEditingController();
  String? _companyId; bool _saving = false;
  @override void dispose() { _fn.dispose(); _ln.dispose(); _email.dispose(); _phone.dispose(); _role.dispose(); super.dispose(); }
  Future<void> _save() async {
    if (_fn.text.trim().isEmpty || _ln.text.trim().isEmpty) return;
    setState(() => _saving = true);
    await widget.onSave(CrmFirestoreContact(id: 'cnt-${DateTime.now().microsecondsSinceEpoch}', firstName: _fn.text.trim(), lastName: _ln.text.trim(), companyId: _companyId, email: _email.text.trim(), phone: _phone.text.trim(), role: _role.text.trim(), createdAt: DateTime.now(), updatedAt: DateTime.now()));
    if (mounted) Navigator.of(context).pop();
  }
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Nuovo contatto', style: TextStyle(fontWeight: FontWeight.w800)),
    content: SizedBox(width: 460, child: Column(mainAxisSize: MainAxisSize.min, children: [
      Row(children: [Expanded(child: TextField(controller: _fn, decoration: const InputDecoration(labelText: 'Nome *', border: OutlineInputBorder()), autofocus: true)), const SizedBox(width: 12), Expanded(child: TextField(controller: _ln, decoration: const InputDecoration(labelText: 'Cognome *', border: OutlineInputBorder())))]),
      const SizedBox(height: 12),
      Row(children: [Expanded(child: TextField(controller: _email, decoration: const InputDecoration(labelText: 'Email', border: OutlineInputBorder()), keyboardType: TextInputType.emailAddress)), const SizedBox(width: 12), Expanded(child: TextField(controller: _phone, decoration: const InputDecoration(labelText: 'Telefono', border: OutlineInputBorder())))]),
      const SizedBox(height: 12),
      Row(children: [Expanded(child: TextField(controller: _role, decoration: const InputDecoration(labelText: 'Ruolo', border: OutlineInputBorder()))), const SizedBox(width: 12), Expanded(child: DropdownButtonFormField<String>(initialValue: _companyId, decoration: const InputDecoration(labelText: 'Azienda', border: OutlineInputBorder()), items: [const DropdownMenuItem(value: null, child: Text('— Nessuna —')), ...widget.companies.map((c) => DropdownMenuItem(value: c.id, child: Text(c.name)))], onChanged: (v) => setState(() => _companyId = v)))]),
    ])),
    actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Annulla')), FilledButton(onPressed: _saving ? null : _save, child: _saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Salva'))],
  );
}
