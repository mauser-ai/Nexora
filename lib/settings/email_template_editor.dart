import 'package:flutter/material.dart';

import '../models/template_models.dart';

// ─── Email template editor ────────────────────────────────────────────────────
// Usato nelle impostazioni per creare/modificare template email.

class EmailTemplateEditorDialog extends StatefulWidget {
  const EmailTemplateEditorDialog({
    super.key,
    required this.template,
    required this.category,
    required this.onSave,
    this.extraVariables = const [],
  });

  final EmailTemplate? template; // null = nuovo
  final String category;
  final Future<void> Function(EmailTemplate) onSave;
  final List<TemplateVariable> extraVariables; // custom fields del PDF template

  @override
  State<EmailTemplateEditorDialog> createState() => _EmailTemplateEditorDialogState();
}

class _EmailTemplateEditorDialogState extends State<EmailTemplateEditorDialog> {
  late final TextEditingController _name;
  late final TextEditingController _subject;
  late final TextEditingController _body;
  final _subjectFocus = FocusNode();
  final _bodyFocus    = FocusNode();
  bool _focusOnBody = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _name    = TextEditingController(text: widget.template?.name    ?? '');
    _subject = TextEditingController(text: widget.template?.subject ?? '');
    _body    = TextEditingController(text: widget.template?.body    ?? '');
  }

  @override
  void dispose() {
    _name.dispose(); _subject.dispose(); _body.dispose();
    _subjectFocus.dispose(); _bodyFocus.dispose();
    super.dispose();
  }

  List<TemplateVariable> get _allVars => [
    ...kEmailVariables,
    ...widget.extraVariables,
  ];

  void _insertVar(String key) {
    final ctrl = _focusOnBody ? _body : _subject;
    final focus = _focusOnBody ? _bodyFocus : _subjectFocus;
    final sel = ctrl.selection;
    final text = ctrl.text;
    final tag = '{{$key}}';
    final newText = sel.isValid
        ? text.replaceRange(sel.start, sel.end, tag)
        : text + tag;
    ctrl.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(
        offset: sel.isValid ? sel.start + tag.length : newText.length,
      ),
    );
    focus.requestFocus();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) return;
    setState(() => _saving = true);
    try {
      final t = EmailTemplate(
        id: widget.template?.id ?? 'etpl_${DateTime.now().microsecondsSinceEpoch}',
        name: _name.text.trim(),
        category: widget.category,
        subject: _subject.text.trim(),
        body: _body.text.trim(),
      );
      await widget.onSave(t);
      if (mounted) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final groups = _allVars.map((v) => v.group).toSet().toList();
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 860, maxHeight: 700),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(children: [
                Expanded(
                  child: Text(
                    widget.template == null ? 'Nuovo template email' : 'Modifica template email',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Color(0xFFE4E8FF)),
                  ),
                ),
                IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.of(context).pop()),
              ]),
              const SizedBox(height: 16),

              // Body
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Left: fields
                    Expanded(
                      flex: 3,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          TextFormField(
                            controller: _name,
                            decoration: const InputDecoration(
                              labelText: 'Nome template',
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Focus(
                            onFocusChange: (f) { if (f) setState(() => _focusOnBody = false); },
                            child: TextFormField(
                              controller: _subject,
                              focusNode: _subjectFocus,
                              decoration: const InputDecoration(
                                labelText: 'Oggetto email',
                                hintText: 'es. Preventivo {{documento.numero}} — {{emittente.nome}}',
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Expanded(
                            child: Focus(
                              onFocusChange: (f) { if (f) setState(() => _focusOnBody = true); },
                              child: TextFormField(
                                controller: _body,
                                focusNode: _bodyFocus,
                                maxLines: null,
                                expands: true,
                                textAlignVertical: TextAlignVertical.top,
                                decoration: const InputDecoration(
                                  labelText: 'Corpo email',
                                  hintText: 'Ciao {{cliente.nome}},\n\nti inviamo il preventivo ...',
                                  border: OutlineInputBorder(),
                                  alignLabelWithHint: true,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),

                    // Right: variable picker
                    SizedBox(
                      width: 200,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Variabili disponibili',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF7D89A8)),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Clicca per inserire nel campo attivo (Oggetto o Corpo).',
                            style: const TextStyle(fontSize: 11, color: Color(0xFF525D78)),
                          ),
                          const SizedBox(height: 8),
                          Expanded(
                            child: ListView(
                              children: groups.map((g) => Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(0, 8, 0, 4),
                                    child: Text(g, style: const TextStyle(
                                      fontSize: 10, fontWeight: FontWeight.w700,
                                      color: Color(0xFF7D89A8), letterSpacing: .5,
                                    )),
                                  ),
                                  ..._allVars.where((v) => v.group == g).map((v) =>
                                    InkWell(
                                      borderRadius: BorderRadius.circular(4),
                                      onTap: () => _insertVar(v.key),
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 4),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(v.label, style: const TextStyle(fontSize: 12, color: Color(0xFFE4E8FF))),
                                            Text('{{${v.key}}}', style: const TextStyle(
                                              fontSize: 10, color: Color(0xFF3B82F6), fontFamily: 'monospace',
                                            )),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              )).toList(),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Footer
              Row(children: [
                const Spacer(),
                TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Annulla')),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _saving ? null : _save,
                  child: Text(_saving ? 'Salvataggio...' : 'Salva template'),
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}
