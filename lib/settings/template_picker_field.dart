import 'package:flutter/material.dart';

import '../brand_config.dart';
import '../data/template_repository.dart';
import '../models/template_models.dart';

/// Dropdown di scelta del template PDF per un documento.
///
/// Due modalità:
/// - **controllata** (creazione, [docId] assente): usa [value]/[onChanged];
/// - **autosalvataggio** ([docId] presente): carica la scelta corrente da
///   Firestore e la salva da sola ad ogni cambio.
class TemplatePickerField extends StatefulWidget {
  const TemplatePickerField({
    super.key,
    required this.userId,
    required this.category,
    this.docId,
    this.value,
    this.onChanged,
    this.label = 'Template PDF',
  });

  final String userId;
  final String category; // kPreventivo | kFattura
  final String? docId;
  final String? value;
  final ValueChanged<String?>? onChanged;
  final String label;

  @override
  State<TemplatePickerField> createState() => _TemplatePickerFieldState();
}

class _TemplatePickerFieldState extends State<TemplatePickerField> {
  final _repo = TemplateRepository();
  List<DocumentTemplate>? _templates;
  String? _selectedId;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _selectedId = widget.value;
    _load();
  }

  Future<void> _load() async {
    final templates = await _repo.getTemplates(
      widget.userId,
      category: widget.category,
    );
    String? choice = widget.value;
    if (widget.docId != null) {
      choice = await _repo.getDocTemplateChoice(widget.userId, widget.docId!);
    }
    if (!mounted) return;
    setState(() {
      _templates = templates;
      if (choice != null && templates.any((t) => t.id == choice)) {
        _selectedId = choice;
      }
    });
  }

  Future<void> _select(String? id) async {
    setState(() => _selectedId = id);
    widget.onChanged?.call(id);
    if (widget.docId != null) {
      setState(() => _saving = true);
      await _repo.setDocTemplateChoice(widget.userId, widget.docId!, id);
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final templates = _templates;
    if (templates == null) {
      return const SizedBox(
        height: 40,
        child: Center(
          child: SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    if (templates.isEmpty) {
      return Text(
        'Nessun template ${widget.category} disponibile: crealo da '
        'Impostazioni → Template.',
        style: const TextStyle(
          fontSize: 11.5,
          color: GussoniBrand.textMuted,
          height: 1.4,
        ),
      );
    }
    return Row(
      children: [
        Expanded(
          child: DropdownButtonFormField<String?>(
            initialValue: templates.any((t) => t.id == _selectedId)
                ? _selectedId
                : null,
            isDense: true,
            decoration: InputDecoration(
              labelText: widget.label,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
            ),
            items: [
              const DropdownMenuItem<String?>(
                value: null,
                child: Text(
                  'Chiedi alla generazione',
                  style: TextStyle(fontSize: 13),
                ),
              ),
              for (final t in templates)
                DropdownMenuItem<String?>(
                  value: t.id,
                  child: Text(
                    t.name,
                    style: const TextStyle(fontSize: 13),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: _saving ? null : _select,
          ),
        ),
        if (_saving) ...[
          const SizedBox(width: 8),
          const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ],
      ],
    );
  }
}
