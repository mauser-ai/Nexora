import '../../brand_config.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../data/crm_store.dart';
import '../models/crm_models.dart';

// ────────────────────────────────────────────────
// CRM Contacts Card
// ────────────────────────────────────────────────

class CrmContactsCard extends StatefulWidget {
  const CrmContactsCard({super.key, required this.store});

  final CrmStore store;

  @override
  State<CrmContactsCard> createState() => _CrmContactsCardState();
}

class _CrmContactsCardState extends State<CrmContactsCard> {
  String _query = '';
  CrmContact? _selected;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.store,
      builder: (context, _) {
        final contacts = widget.store.contacts.where((c) {
          final q = _query.toLowerCase();
          if (q.isEmpty) return true;
          return c.fullName.toLowerCase().contains(q) ||
              c.email.toLowerCase().contains(q) ||
              c.role.toLowerCase().contains(q) ||
              (widget.store.companyById(c.companyId)?.name.toLowerCase().contains(q) ?? false);
        }).toList();

        return LayoutBuilder(
          builder: (context, constraints) {
            final showDetail = _selected != null && constraints.maxWidth > 750;

            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // List panel
                SizedBox(
                  width: showDetail ? 360 : double.infinity,
                  child: _ContactList(
                    contacts: contacts,
                    store: widget.store,
                    selected: _selected,
                    query: _query,
                    onQueryChanged: (q) => setState(() { _query = q; }),
                    onSelected: (c) => setState(() => _selected = c),
                    onAdd: () => _showAddContactDialog(context),
                  ),
                ),
                // Detail panel
                if (showDetail) ...[
                  const SizedBox(width: 16),
                  Expanded(
                    child: _ContactDetail(
                      contact: _selected!,
                      store: widget.store,
                      onClose: () => setState(() => _selected = null),
                    ),
                  ),
                ],
              ],
            );
          },
        );
      },
    );
  }

  void _showAddContactDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (context) => _AddContactDialog(store: widget.store),
    );
  }
}

// ── Contact list ──

class _ContactList extends StatelessWidget {
  const _ContactList({required this.contacts, required this.store, required this.selected, required this.query, required this.onQueryChanged, required this.onSelected, required this.onAdd});

  final List<CrmContact> contacts;
  final CrmStore store;
  final CrmContact? selected;
  final String query;
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<CrmContact> onSelected;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Search + add
        Row(
          children: [
            Expanded(
              child: Container(
                height: 44,
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFF1E2130))),
                child: TextField(
                  onChanged: onQueryChanged,
                  decoration: const InputDecoration(prefixIcon: Icon(Icons.search, size: 18, color: Color(0xFF525D78)), hintText: 'Cerca contatti...', border: InputBorder.none, contentPadding: EdgeInsets.symmetric(vertical: 12)),
                ),
              ),
            ),
            const SizedBox(width: 10),
            FilledButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.person_add_outlined, size: 16),
              label: const Text('Aggiungi'),
              style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
            ),
          ],
        ),
        const SizedBox(height: 12),
        // Count
        Text('${contacts.length} contatti', style: const TextStyle(fontSize: 12, color: Color(0xFF525D78), fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        // List
        Expanded(
          child: contacts.isEmpty
              ? const Center(child: Text('Nessun contatto trovato.', style: TextStyle(color: Color(0xFF525D78))))
              : ListView.separated(
                  itemCount: contacts.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 6),
                  itemBuilder: (context, index) {
                    final contact = contacts[index];
                    final isSelected = selected?.id == contact.id;
                    final company = store.companyById(contact.companyId);
                    return _ContactTile(
                      contact: contact,
                      company: company,
                      isSelected: isSelected,
                      onTap: () => onSelected(contact),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _ContactTile extends StatelessWidget {
  const _ContactTile({required this.contact, required this.company, required this.isSelected, required this.onTap});

  final CrmContact contact;
  final CrmCompany? company;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected ? GussoniBrand.primary.withValues(alpha: 0.07) : const Color(0xFF0E1020),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: isSelected ? GussoniBrand.primary.withValues(alpha: 0.4) : const Color(0xFF1E2130), width: isSelected ? 1.5 : 1),
        ),
        child: Row(
          children: [
            _ContactAvatar(name: contact.fullName, size: 40),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(contact.fullName, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF0F172A))),
                  const SizedBox(height: 2),
                  if (contact.role.isNotEmpty)
                    Text(contact.role, style: const TextStyle(fontSize: 12, color: Color(0xFF7D89A8)), maxLines: 1, overflow: TextOverflow.ellipsis),
                  if (company != null)
                    Row(
                      children: [
                        const Icon(Icons.apartment_outlined, size: 11, color: Color(0xFF525D78)),
                        const SizedBox(width: 3),
                        Expanded(child: Text(company!.name, style: const TextStyle(fontSize: 12, color: Color(0xFF525D78)), maxLines: 1, overflow: TextOverflow.ellipsis)),
                      ],
                    ),
                ],
              ),
            ),
            if (contact.email.isNotEmpty)
              Tooltip(
                message: contact.email,
                child: Icon(Icons.email_outlined, size: 16, color: isSelected ? GussoniBrand.primary : const Color(0xFF1E2130)),
              ),
          ],
        ),
      ),
    );
  }
}

// ── Contact Detail ──

class _ContactDetail extends StatelessWidget {
  const _ContactDetail({required this.contact, required this.store, required this.onClose});

  final CrmContact contact;
  final CrmStore store;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final company = store.companyById(contact.companyId);
    final assignee = store.userById(contact.assignedTo);
    final relatedDeals = store.deals.where((d) => d.customerId == contact.id || d.customerId == contact.companyId).toList();
    final relatedTasks = store.tasksForEntity('contact', contact.id);
    final currencyFmt = NumberFormat.currency(locale: 'it_IT', symbol: '€', decimalDigits: 0);

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0E1020),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF1E2130)),
        boxShadow: const [BoxShadow(color: Color(0x0A000000), blurRadius: 8, offset: Offset(0, 2))],
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _ContactAvatar(name: contact.fullName, size: 56),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(contact.fullName, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Color(0xFF0F172A))),
                      if (contact.role.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(contact.role, style: const TextStyle(fontSize: 13, color: Color(0xFF7D89A8), fontWeight: FontWeight.w600)),
                      ],
                      if (company != null) ...[
                        const SizedBox(height: 4),
                        InkWell(
                          borderRadius: BorderRadius.circular(6),
                          onTap: () {},
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.apartment_outlined, size: 13, color: Color(0xFF034F3B)),
                              const SizedBox(width: 4),
                              Text(company.name, style: const TextStyle(fontSize: 13, color: Color(0xFF034F3B), fontWeight: FontWeight.w700)),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                IconButton(onPressed: onClose, icon: const Icon(Icons.close, color: Color(0xFF525D78)), tooltip: 'Chiudi'),
              ],
            ),
            const SizedBox(height: 20),
            const Divider(color: Color(0xFF0C0E1A)),
            const SizedBox(height: 16),

            // Contact info
            _DetailSection(title: 'Informazioni di contatto', children: [
              if (contact.email.isNotEmpty) _InfoRow(icon: Icons.email_outlined, label: 'Email', value: contact.email),
              if (contact.phone.isNotEmpty) _InfoRow(icon: Icons.phone_outlined, label: 'Telefono', value: contact.phone),
              if (assignee != null) _InfoRow(icon: Icons.person_outline_rounded, label: 'Responsabile', value: assignee.fullName),
              if (contact.createdAt != null) _InfoRow(icon: Icons.calendar_today_outlined, label: 'Creato il', value: DateFormat('dd/MM/yyyy').format(contact.createdAt!)),
            ]),

            if (contact.tags.isNotEmpty) ...[
              const SizedBox(height: 16),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: contact.tags.map((tag) => Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(borderRadius: BorderRadius.circular(999), color: const Color(0xFF0C0E1A), border: Border.all(color: const Color(0xFF1E2130))),
                  child: Text(tag, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFFB8C0D8))),
                )).toList(),
              ),
            ],

            // Deals
            if (relatedDeals.isNotEmpty) ...[
              const SizedBox(height: 20),
              _DetailSection(title: 'Deal collegati (${relatedDeals.length})', children: [
                ...relatedDeals.map((deal) {
                  final stage = store.stageById(deal.stageId);
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        Expanded(child: Text(deal.title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis)),
                        const SizedBox(width: 8),
                        if (stage != null) _SmallBadge(label: stage.name, color: stage.color),
                        const SizedBox(width: 8),
                        Text(currencyFmt.format(deal.value), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Color(0xFF0F172A))),
                      ],
                    ),
                  );
                }),
              ]),
            ],

            // Tasks
            if (relatedTasks.isNotEmpty) ...[
              const SizedBox(height: 20),
              _DetailSection(title: 'Task collegati (${relatedTasks.length})', children: [
                ...relatedTasks.map((task) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Container(width: 7, height: 7, decoration: BoxDecoration(shape: BoxShape.circle, color: task.priority.color)),
                      const SizedBox(width: 8),
                      Expanded(child: Text(task.title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis)),
                      const SizedBox(width: 8),
                      _SmallBadge(label: task.status.label, color: task.status.color),
                    ],
                  ),
                )),
              ]),
            ],
          ],
        ),
      ),
    );
  }
}

class _DetailSection extends StatelessWidget {
  const _DetailSection({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Color(0xFF525D78), letterSpacing: 0.5)),
        const SizedBox(height: 10),
        ...children,
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.icon, required this.label, required this.value});

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon, size: 14, color: const Color(0xFF525D78)),
          const SizedBox(width: 8),
          Text('$label: ', style: const TextStyle(fontSize: 13, color: Color(0xFF525D78), fontWeight: FontWeight.w500)),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFFB8C0D8)), maxLines: 1, overflow: TextOverflow.ellipsis)),
        ],
      ),
    );
  }
}

class _SmallBadge extends StatelessWidget {
  const _SmallBadge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(999), color: color.withValues(alpha: 0.10), border: Border.all(color: color.withValues(alpha: 0.30))),
      child: Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: color)),
    );
  }
}

class _ContactAvatar extends StatelessWidget {
  const _ContactAvatar({required this.name, this.size = 36});

  final String name;
  final double size;

  Color _colorForName(String name) {
    const palette = [Color(0xFF0369A1), Color(0xFF7C3AED), Color(0xFF034F3B), Color(0xFFD97706), Color(0xFF0891B2), Color(0xFFB91C1C)];
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
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color.withValues(alpha: 0.15), border: Border.all(color: color.withValues(alpha: 0.4))),
      child: Center(child: Text(_initials(name), style: TextStyle(fontSize: size * 0.33, fontWeight: FontWeight.w800, color: color))),
    );
  }
}

// ── Add Contact Dialog ──

class _AddContactDialog extends StatefulWidget {
  const _AddContactDialog({required this.store});

  final CrmStore store;

  @override
  State<_AddContactDialog> createState() => _AddContactDialogState();
}

class _AddContactDialogState extends State<_AddContactDialog> {
  final _firstNameCtrl = TextEditingController();
  final _lastNameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _roleCtrl = TextEditingController();
  String? _selectedCompanyId;

  @override
  void dispose() {
    _firstNameCtrl.dispose();
    _lastNameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _roleCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    final firstName = _firstNameCtrl.text.trim();
    final lastName = _lastNameCtrl.text.trim();
    if (firstName.isEmpty || lastName.isEmpty) {
      return;
    }
    final contact = CrmContact(
      id: 'cnt-${DateTime.now().microsecondsSinceEpoch}',
      teamId: widget.store.teamId,
      firstName: firstName,
      lastName: lastName,
      companyId: _selectedCompanyId,
      email: _emailCtrl.text.trim(),
      phone: _phoneCtrl.text.trim(),
      role: _roleCtrl.text.trim(),
      createdBy: widget.store.currentUser.id,
      assignedTo: widget.store.currentUser.id,
      createdAt: DateTime.now(),
    );
    widget.store.addContact(contact);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final companies = widget.store.companies;

    return AlertDialog(
      title: const Text('Nuovo contatto', style: TextStyle(fontWeight: FontWeight.w800)),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(child: TextField(controller: _firstNameCtrl, decoration: const InputDecoration(labelText: 'Nome *', border: OutlineInputBorder()), autofocus: true)),
                const SizedBox(width: 12),
                Expanded(child: TextField(controller: _lastNameCtrl, decoration: const InputDecoration(labelText: 'Cognome *', border: OutlineInputBorder()))),
              ],
            ),
            const SizedBox(height: 12),
            TextField(controller: _emailCtrl, decoration: const InputDecoration(labelText: 'Email', border: OutlineInputBorder()), keyboardType: TextInputType.emailAddress),
            const SizedBox(height: 12),
            TextField(controller: _phoneCtrl, decoration: const InputDecoration(labelText: 'Telefono', border: OutlineInputBorder()), keyboardType: TextInputType.phone),
            const SizedBox(height: 12),
            TextField(controller: _roleCtrl, decoration: const InputDecoration(labelText: 'Ruolo / Titolo', border: OutlineInputBorder())),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _selectedCompanyId,
              decoration: const InputDecoration(labelText: 'Azienda', border: OutlineInputBorder()),
              items: [
                const DropdownMenuItem(value: null, child: Text('– Nessuna –')),
                ...companies.map((c) => DropdownMenuItem(value: c.id, child: Text(c.name))),
              ],
              onChanged: (v) => setState(() => _selectedCompanyId = v),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Annulla')),
        FilledButton(onPressed: _submit, child: const Text('Salva contatto')),
      ],
    );
  }
}
