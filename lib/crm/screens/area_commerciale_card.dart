import 'package:flutter/material.dart';

import '../../brand_config.dart';
import '../../data/team_repository.dart';

// ─── Data transfer objects ─────────────────────────────────────────────────

class CommercialLeadContactDraft {
  CommercialLeadContactDraft({String? assignedTo}) : assignedTo = assignedTo;

  final firstNameCtrl = TextEditingController();
  final lastNameCtrl  = TextEditingController();
  final emailCtrl     = TextEditingController();
  final phoneCtrl     = TextEditingController();
  final roleCtrl      = TextEditingController();
  String? assignedTo;

  bool get hasData => firstNameCtrl.text.trim().isNotEmpty || lastNameCtrl.text.trim().isNotEmpty;
  bool get isValid => firstNameCtrl.text.trim().isNotEmpty && lastNameCtrl.text.trim().isNotEmpty;

  CommercialContactRecord toRecord() => CommercialContactRecord(
    firstName: firstNameCtrl.text.trim(),
    lastName:  lastNameCtrl.text.trim(),
    email:     emailCtrl.text.trim(),
    phone:     phoneCtrl.text.trim(),
    role:      roleCtrl.text.trim(),
    assignedTo: assignedTo,
  );

  void dispose() {
    firstNameCtrl.dispose(); lastNameCtrl.dispose(); emailCtrl.dispose();
    phoneCtrl.dispose(); roleCtrl.dispose();
  }
}

class CommercialContactRecord {
  const CommercialContactRecord({
    required this.firstName,
    required this.lastName,
    this.email = '',
    this.phone = '',
    this.role = '',
    this.assignedTo,
  });
  final String firstName;
  final String lastName;
  final String email;
  final String phone;
  final String role;
  final String? assignedTo;
}

class CommercialLeadSubmission {
  const CommercialLeadSubmission({
    required this.createCompany,
    required this.createContact,
    required this.createOpportunity,
    // company
    this.companyName = '',
    this.vatNumber = '',
    this.taxCode = '',
    this.pec = '',
    this.sdiCode = '',
    this.email = '',
    this.phone = '',
    this.website = '',
    this.addressLine = '',
    this.city = '',
    this.postalCode = '',
    this.country = 'Italia',
    this.companyNotes = '',
    // contacts
    this.contacts = const [],
    // opportunity
    this.opportunityTitle = '',
    this.bandoSource = '',
    this.rifOfferta = '',
    this.contattoCommerciale = '',
    this.daFaturareA = '',
    this.partnerCommerciale = '',
    this.estimatedValue,
    this.bandoDeadline,
    this.scadenzaPresentazione,
    this.scadenzaOperativa,
    this.opportunityNotes = '',
    this.opportunityAssignedTo,
  });

  // flags
  final bool createCompany;
  final bool createContact;
  final bool createOpportunity;

  // azienda
  final String companyName;
  final String vatNumber;
  final String taxCode;
  final String pec;
  final String sdiCode;
  final String email;
  final String phone;
  final String website;
  final String addressLine;
  final String city;
  final String postalCode;
  final String country;
  final String companyNotes;

  // contatti
  final List<CommercialContactRecord> contacts;

  // opportunità
  final String opportunityTitle;
  final String bandoSource;
  final String rifOfferta;
  final String contattoCommerciale;
  final String daFaturareA;
  final String partnerCommerciale;
  final double? estimatedValue;
  final DateTime? bandoDeadline;
  final DateTime? scadenzaPresentazione;
  final DateTime? scadenzaOperativa;
  final String opportunityNotes;
  final String? opportunityAssignedTo;
}

// ─── Widget principale ─────────────────────────────────────────────────────

class CommercialeIntakeCard extends StatefulWidget {
  const CommercialeIntakeCard({
    super.key,
    required this.members,
    required this.currentUserId,
    required this.onSubmit,
  });

  final List<TeamMember> members;
  final String currentUserId;
  final Future<void> Function(CommercialLeadSubmission) onSubmit;

  @override
  State<CommercialeIntakeCard> createState() => _CommercialeIntakeCardState();
}

class _CommercialeIntakeCardState extends State<CommercialeIntakeCard> {
  final _formKey = GlobalKey<FormState>();

  // ── sezioni attive ──
  bool _doCompany     = true;
  bool _doContact     = true;
  bool _doOpportunity = false;

  // ── Azienda ──
  final _companyNameCtrl = TextEditingController();
  final _vatCtrl         = TextEditingController();
  final _taxCodeCtrl     = TextEditingController();
  final _pecCtrl         = TextEditingController();
  final _sdiCtrl         = TextEditingController();
  final _companyEmailCtrl = TextEditingController();
  final _companyPhoneCtrl = TextEditingController();
  final _websiteCtrl     = TextEditingController();
  final _addressCtrl     = TextEditingController();
  final _cityCtrl        = TextEditingController();
  final _postalCodeCtrl  = TextEditingController();
  final _countryCtrl     = TextEditingController(text: 'Italia');
  final _companyNotesCtrl = TextEditingController();

  // ── Contatti ──
  late List<CommercialLeadContactDraft> _contacts;

  // ── Opportunità ──
  final _oppTitleCtrl    = TextEditingController();
  final _bandoSourceCtrl = TextEditingController();
  final _rifOffertaCtrl  = TextEditingController();
  final _contCommCtrl    = TextEditingController();
  final _daFaturareCtrl  = TextEditingController(text: 'Beneficiario');
  final _partnerCtrl     = TextEditingController();
  final _valueCtrl       = TextEditingController();
  final _oppNotesCtrl    = TextEditingController();
  DateTime? _bandoDeadline;
  DateTime? _scadPres;
  DateTime? _scadOp;
  String? _oppAssignedTo;

  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _oppAssignedTo = widget.currentUserId;
    _contacts = [CommercialLeadContactDraft(assignedTo: widget.currentUserId)];
  }

  @override
  void dispose() {
    for (final c in [
      _companyNameCtrl, _vatCtrl, _taxCodeCtrl, _pecCtrl, _sdiCtrl,
      _companyEmailCtrl, _companyPhoneCtrl, _websiteCtrl, _addressCtrl,
      _cityCtrl, _postalCodeCtrl, _countryCtrl, _companyNotesCtrl,
      _oppTitleCtrl, _bandoSourceCtrl, _rifOffertaCtrl, _contCommCtrl,
      _daFaturareCtrl, _partnerCtrl, _valueCtrl, _oppNotesCtrl,
    ]) { c.dispose(); }
    for (final c in _contacts) { c.dispose(); }
    super.dispose();
  }

  // ── toggle sezioni ──

  void _toggleCompany(bool v) => setState(() => _doCompany = v);

  void _toggleContact(bool v) {
    setState(() {
      _doContact = v;
      if (!v) _doOpportunity = false; // opportunità richiede contatto
    });
  }

  void _toggleOpportunity(bool v) {
    setState(() {
      _doOpportunity = v;
      if (v) _doContact = true; // forza il contatto
    });
  }

  // ── submit ──

  Future<void> _submit() async {
    if (!_doCompany && !_doContact && !_doOpportunity) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Seleziona almeno una sezione da creare.')),
      );
      return;
    }
    if (!_formKey.currentState!.validate()) return;

    // Validazione manuale contatti
    if (_doContact) {
      final validContacts = _contacts.where((c) => c.isValid).toList();
      if (validContacts.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Inserisci almeno un contatto con nome e cognome.')),
        );
        return;
      }
    }

    setState(() => _submitting = true);
    try {
      final contacts = _doContact
          ? _contacts.where((c) => c.isValid).map((c) => c.toRecord()).toList()
          : <CommercialContactRecord>[];

      await widget.onSubmit(CommercialLeadSubmission(
        createCompany:     _doCompany,
        createContact:     _doContact,
        createOpportunity: _doOpportunity,
        // azienda
        companyName:   _companyNameCtrl.text.trim(),
        vatNumber:     _vatCtrl.text.trim(),
        taxCode:       _taxCodeCtrl.text.trim(),
        pec:           _pecCtrl.text.trim(),
        sdiCode:       _sdiCtrl.text.trim(),
        email:         _companyEmailCtrl.text.trim(),
        phone:         _companyPhoneCtrl.text.trim(),
        website:       _websiteCtrl.text.trim(),
        addressLine:   _addressCtrl.text.trim(),
        city:          _cityCtrl.text.trim(),
        postalCode:    _postalCodeCtrl.text.trim(),
        country:       _countryCtrl.text.trim(),
        companyNotes:  _companyNotesCtrl.text.trim(),
        // contatti
        contacts: contacts,
        // opportunità
        opportunityTitle:    _oppTitleCtrl.text.trim(),
        bandoSource:         _bandoSourceCtrl.text.trim(),
        rifOfferta:          _rifOffertaCtrl.text.trim(),
        contattoCommerciale: _contCommCtrl.text.trim(),
        daFaturareA:         _daFaturareCtrl.text.trim(),
        partnerCommerciale:  _partnerCtrl.text.trim(),
        estimatedValue: double.tryParse(_valueCtrl.text.replaceAll(',', '.')),
        bandoDeadline:        _bandoDeadline,
        scadenzaPresentazione: _scadPres,
        scadenzaOperativa:    _scadOp,
        opportunityNotes:    _oppNotesCtrl.text.trim(),
        opportunityAssignedTo: _oppAssignedTo,
      ));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Inserimento completato.')),
        );
        _reset();
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _reset() {
    _formKey.currentState?.reset();
    for (final c in [
      _companyNameCtrl, _vatCtrl, _taxCodeCtrl, _pecCtrl, _sdiCtrl,
      _companyEmailCtrl, _companyPhoneCtrl, _websiteCtrl, _addressCtrl,
      _cityCtrl, _postalCodeCtrl, _companyNotesCtrl,
      _oppTitleCtrl, _bandoSourceCtrl, _rifOffertaCtrl, _contCommCtrl,
      _partnerCtrl, _valueCtrl, _oppNotesCtrl,
    ]) { c.clear(); }
    _countryCtrl.text = 'Italia';
    _daFaturareCtrl.text = 'Beneficiario';
    _bandoDeadline = _scadPres = _scadOp = null;
    _oppAssignedTo = widget.currentUserId;
    for (final c in _contacts) { c.dispose(); }
    _contacts = [CommercialLeadContactDraft(assignedTo: widget.currentUserId)];
    setState(() {
      _doCompany = true; _doContact = true; _doOpportunity = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header + toggle pills ──────────────────────────────
              const Text('Nuovo inserimento commerciale',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              const Text(
                'Seleziona cosa vuoi creare. Puoi combinare liberamente le sezioni.',
                style: TextStyle(color: GussoniBrand.textSecondary, fontSize: 13),
              ),
              const SizedBox(height: 16),
              _ToggleRow(
                doCompany: _doCompany,
                doContact: _doContact,
                doOpportunity: _doOpportunity,
                onCompany: _toggleCompany,
                onContact: _toggleContact,
                onOpportunity: _toggleOpportunity,
              ),
              const SizedBox(height: 20),

              // ── Sezione Azienda ───────────────────────────────────
              if (_doCompany) ...[
                _SectionBox(
                  title: 'Azienda',
                  icon: Icons.apartment_outlined,
                  color: GussoniBrand.primary,
                  child: Column(children: [
                    _row(_tf(_companyNameCtrl, 'Ragione sociale *',
                        validator: _req), _tf(_vatCtrl, 'Partita IVA')),
                    const SizedBox(height: 12),
                    _row(_tf(_taxCodeCtrl, 'Codice fiscale'), _tf(_sdiCtrl, 'Codice SDI')),
                    const SizedBox(height: 12),
                    _row(_tf(_pecCtrl, 'PEC'), _tf(_companyEmailCtrl, 'Email azienda')),
                    const SizedBox(height: 12),
                    _row(_tf(_companyPhoneCtrl, 'Telefono'), _tf(_websiteCtrl, 'Sito web')),
                    const SizedBox(height: 12),
                    _row(_tf(_addressCtrl, 'Indirizzo'), _tf(_cityCtrl, 'Città')),
                    const SizedBox(height: 12),
                    _row(_tf(_postalCodeCtrl, 'CAP'), _tf(_countryCtrl, 'Paese')),
                    const SizedBox(height: 12),
                    _tf(_companyNotesCtrl, 'Note azienda', maxLines: 2),
                  ]),
                ),
                const SizedBox(height: 16),
              ],

              // ── Sezione Contatti ──────────────────────────────────
              if (_doContact) ...[
                _SectionBox(
                  title: 'Contatti',
                  icon: Icons.person_outline,
                  color: GussoniBrand.info,
                  action: TextButton.icon(
                    onPressed: _submitting ? null : () => setState(() {
                      _contacts.add(CommercialLeadContactDraft(
                          assignedTo: _oppAssignedTo ?? widget.currentUserId));
                    }),
                    icon: const Icon(Icons.add, size: 15),
                    label: const Text('Aggiungi contatto'),
                  ),
                  child: Column(children: [
                    for (int i = 0; i < _contacts.length; i++) ...[
                      _ContactCard(
                        key: ValueKey('c-$i'),
                        data: _contacts[i],
                        members: widget.members,
                        index: i,
                        allowRemove: _contacts.length > 1,
                        isRequired: _doOpportunity && i == 0,
                        onRemove: _submitting ? null : () => setState(() {
                          _contacts.removeAt(i).dispose();
                        }),
                      ),
                      if (i < _contacts.length - 1) const SizedBox(height: 10),
                    ],
                  ]),
                ),
                const SizedBox(height: 16),
              ],

              // ── Sezione Opportunità ───────────────────────────────
              if (_doOpportunity) ...[
                _SectionBox(
                  title: 'Opportunità / Bando',
                  icon: Icons.trending_up_outlined,
                  color: GussoniBrand.gold,
                  child: Column(children: [
                    _tf(_oppTitleCtrl, 'Titolo bando / opportunità *', validator: _req),
                    const SizedBox(height: 12),
                    _row(_tf(_bandoSourceCtrl, 'Ente / Portale'), _tf(_rifOffertaCtrl, 'Rif. offerta (es. 01.2025)')),
                    const SizedBox(height: 12),
                    _row(_tf(_contCommCtrl, 'Contatto commerciale'), _tf(_daFaturareCtrl, 'Da fatturare a')),
                    const SizedBox(height: 12),
                    _row(_tf(_partnerCtrl, 'Partner commerciale'), _tf(_valueCtrl, 'Valore stimato (€)', type: TextInputType.number)),
                    const SizedBox(height: 12),
                    _row(
                      _DateField(label: 'Scadenza bando', value: _bandoDeadline,
                          onPicked: (d) => setState(() => _bandoDeadline = d)),
                      _DateField(label: 'Scadenza presentazione', value: _scadPres,
                          onPicked: (d) => setState(() => _scadPres = d)),
                    ),
                    const SizedBox(height: 12),
                    _row(
                      _DateField(label: 'Scadenza operativa', value: _scadOp,
                          onPicked: (d) => setState(() => _scadOp = d)),
                      widget.members.isEmpty
                          ? const SizedBox()
                          : DropdownButtonFormField<String>(
                              value: _oppAssignedTo,
                              decoration: const InputDecoration(
                                  labelText: 'Responsabile', border: OutlineInputBorder()),
                              items: widget.members.map((m) => DropdownMenuItem(
                                value: m.userId,
                                child: Text(m.displayName.isNotEmpty ? m.displayName : m.email),
                              )).toList(),
                              onChanged: _submitting ? null : (v) => setState(() => _oppAssignedTo = v),
                            ),
                    ),
                    const SizedBox(height: 12),
                    _tf(_oppNotesCtrl, 'Note opportunità', maxLines: 3),
                  ]),
                ),
                const SizedBox(height: 16),
              ],

              // ── Nota informativa se niente selezionato ────────────
              if (!_doCompany && !_doContact && !_doOpportunity)
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: GussoniBrand.surfaceSubtle,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: GussoniBrand.border),
                  ),
                  child: Row(children: [
                    Icon(Icons.info_outline, color: GussoniBrand.textMuted, size: 18),
                    const SizedBox(width: 10),
                    const Text('Attiva almeno una sezione per procedere.',
                        style: TextStyle(color: GussoniBrand.textSecondary, fontSize: 13)),
                  ]),
                ),

              const SizedBox(height: 8),

              // ── Bottone submit ────────────────────────────────────
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  onPressed: _submitting ? null : _submit,
                  icon: _submitting
                      ? const SizedBox(width: 16, height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.check_circle_outline, size: 18),
                  label: Text(_submitting ? 'Creazione...' : 'Conferma inserimento'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── helpers ──

  Widget _row(Widget l, Widget r) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [Expanded(child: l), const SizedBox(width: 12), Expanded(child: r)],
  );

  Widget _tf(TextEditingController c, String label, {
    String? Function(String?)? validator, int maxLines = 1, TextInputType? type,
  }) => TextFormField(
    controller: c, validator: validator, maxLines: maxLines, keyboardType: type,
    decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
  );

  String? _req(String? v) =>
      (v == null || v.trim().isEmpty) ? 'Campo obbligatorio' : null;
}

// ─── Toggle row ───────────────────────────────────────────────────────────

class _ToggleRow extends StatelessWidget {
  const _ToggleRow({
    required this.doCompany, required this.doContact, required this.doOpportunity,
    required this.onCompany, required this.onContact, required this.onOpportunity,
  });
  final bool doCompany, doContact, doOpportunity;
  final ValueChanged<bool> onCompany, onContact, onOpportunity;

  @override
  Widget build(BuildContext context) => Wrap(spacing: 10, children: [
    _Pill(
      label: 'Azienda', icon: Icons.apartment_outlined,
      active: doCompany, color: GussoniBrand.primary,
      onTap: () => onCompany(!doCompany),
    ),
    _Pill(
      label: 'Contatto', icon: Icons.person_outline,
      active: doContact, color: GussoniBrand.info,
      onTap: () => onContact(!doContact),
    ),
    _Pill(
      label: 'Opportunità', icon: Icons.trending_up_outlined,
      active: doOpportunity, color: GussoniBrand.gold,
      onTap: () => onOpportunity(!doOpportunity),
      subtitle: doOpportunity ? null : '(richiede Contatto)',
    ),
  ]);
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.label, required this.icon, required this.active,
    required this.color, required this.onTap, this.subtitle,
  });
  final String label;
  final IconData icon;
  final bool active;
  final Color color;
  final VoidCallback onTap;
  final String? subtitle;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: active ? color.withValues(alpha: 0.08) : GussoniBrand.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: active ? color : GussoniBrand.border, width: active ? 2 : 1),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(active ? Icons.check_circle : icon,
            size: 16, color: active ? color : GussoniBrand.textMuted),
        const SizedBox(width: 8),
        Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text(label, style: TextStyle(
            fontSize: 13, fontWeight: FontWeight.w700,
            color: active ? color : GussoniBrand.textSecondary,
          )),
          if (subtitle != null && !active)
            Text(subtitle!, style: const TextStyle(fontSize: 10, color: GussoniBrand.textMuted)),
        ]),
      ]),
    ),
  );
}

// ─── Section box ─────────────────────────────────────────────────────────

class _SectionBox extends StatelessWidget {
  const _SectionBox({
    required this.title, required this.icon, required this.color,
    required this.child, this.action,
  });
  final String title;
  final IconData icon;
  final Color color;
  final Widget child;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: GussoniBrand.surface,
      border: Border.all(color: color.withValues(alpha: 0.3)),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 8),
        Expanded(child: Text(title, style: TextStyle(
          fontSize: 15, fontWeight: FontWeight.w700, color: color,
        ))),
        if (action != null) action!,
      ]),
      const SizedBox(height: 14),
      child,
    ]),
  );
}

// ─── Contact card ─────────────────────────────────────────────────────────

class _ContactCard extends StatelessWidget {
  const _ContactCard({
    super.key, required this.data, required this.members,
    required this.index, required this.allowRemove,
    required this.isRequired, this.onRemove,
  });
  final CommercialLeadContactDraft data;
  final List<TeamMember> members;
  final int index;
  final bool allowRemove;
  final bool isRequired;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: GussoniBrand.surfaceSubtle,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: GussoniBrand.border),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Text('Contatto ${index + 1}',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
                color: GussoniBrand.textMuted)),
        if (isRequired)
          const Padding(
            padding: EdgeInsets.only(left: 6),
            child: Text('• obbligatorio per l\'opportunità',
                style: TextStyle(fontSize: 11, color: GussoniBrand.warning)),
          ),
        const Spacer(),
        if (allowRemove)
          IconButton(onPressed: onRemove, icon: const Icon(Icons.close, size: 16),
              padding: EdgeInsets.zero, constraints: const BoxConstraints()),
      ]),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(child: TextFormField(
          controller: data.firstNameCtrl,
          validator: isRequired ? (v) => (v == null || v.trim().isEmpty) ? 'Obbligatorio' : null : null,
          decoration: const InputDecoration(labelText: 'Nome *', border: OutlineInputBorder(), isDense: true),
        )),
        const SizedBox(width: 8),
        Expanded(child: TextFormField(
          controller: data.lastNameCtrl,
          validator: isRequired ? (v) => (v == null || v.trim().isEmpty) ? 'Obbligatorio' : null : null,
          decoration: const InputDecoration(labelText: 'Cognome *', border: OutlineInputBorder(), isDense: true),
        )),
      ]),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(child: TextFormField(
          controller: data.emailCtrl,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(labelText: 'Email', border: OutlineInputBorder(), isDense: true),
        )),
        const SizedBox(width: 8),
        Expanded(child: TextFormField(
          controller: data.phoneCtrl,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(labelText: 'Telefono', border: OutlineInputBorder(), isDense: true),
        )),
      ]),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(child: TextFormField(
          controller: data.roleCtrl,
          decoration: const InputDecoration(labelText: 'Ruolo', border: OutlineInputBorder(), isDense: true),
        )),
        if (members.isNotEmpty) ...[
          const SizedBox(width: 8),
          Expanded(child: DropdownButtonFormField<String>(
            value: data.assignedTo,
            decoration: const InputDecoration(labelText: 'Responsabile', border: OutlineInputBorder(), isDense: true),
            items: members.map((m) => DropdownMenuItem(
              value: m.userId,
              child: Text(m.displayName.isNotEmpty ? m.displayName : m.email,
                  overflow: TextOverflow.ellipsis),
            )).toList(),
            onChanged: (v) => data.assignedTo = v,
          )),
        ],
      ]),
    ]),
  );
}

// ─── Date field helper ────────────────────────────────────────────────────

class _DateField extends StatelessWidget {
  const _DateField({required this.label, required this.value, required this.onPicked});
  final String label;
  final DateTime? value;
  final ValueChanged<DateTime> onPicked;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: () async {
      final picked = await showDatePicker(
        context: context,
        initialDate: value ?? DateTime.now(),
        firstDate: DateTime(DateTime.now().year - 1),
        lastDate: DateTime(DateTime.now().year + 5),
      );
      if (picked != null) onPicked(picked);
    },
    child: InputDecorator(
      decoration: InputDecoration(
        labelText: label, border: const OutlineInputBorder(),
        suffixIcon: const Icon(Icons.calendar_today_outlined, size: 16),
      ),
      child: Text(
        value != null
            ? '${value!.day.toString().padLeft(2, '0')}/${value!.month.toString().padLeft(2, '0')}/${value!.year}'
            : '—',
        style: TextStyle(
          fontSize: 13,
          color: value != null ? GussoniBrand.textPrimary : GussoniBrand.textDisabled,
        ),
      ),
    ),
  );
}
