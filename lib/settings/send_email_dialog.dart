import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../data/template_repository.dart';
import '../models/template_models.dart';
import '../services/ticket_mail_service.dart';

/// Dialog per inviare un'email di preventivo o fattura usando un template.
/// [category] = kPreventivo | kFattura
/// [data] = mappa variabili già risolta (stessa struttura del PDF generator)
/// [toEmail] = email destinatario pre-compilata
/// [signatureHtml] = firma HTML dell'emittente
/// Ritorna `true` se l'email è stata inviata.
Future<bool?> showSendEmailDialog({
  required BuildContext context,
  required String userId,
  required String category,
  required Map<String, dynamic> data,
  required String toEmail,
  required String signatureHtml,
  required TemplateRepository templateRepo,
  Future<Uint8List?> Function()? buildPdfAttachment,
  String attachmentFileName = 'documento.pdf',
  String? fromEmail,
  String? fromName,
}) async {
  return showDialog<bool>(
    context: context,
    builder: (ctx) => _SendEmailDialog(
      userId: userId,
      category: category,
      data: data,
      toEmail: toEmail,
      signatureHtml: signatureHtml,
      templateRepo: templateRepo,
      buildPdfAttachment: buildPdfAttachment,
      attachmentFileName: attachmentFileName,
      fromEmail: fromEmail,
      fromName: fromName,
    ),
  );
}

class _SendEmailDialog extends StatefulWidget {
  const _SendEmailDialog({
    required this.userId,
    required this.category,
    required this.data,
    required this.toEmail,
    required this.signatureHtml,
    required this.templateRepo,
    this.buildPdfAttachment,
    this.attachmentFileName = 'documento.pdf',
    this.fromEmail,
    this.fromName,
  });

  final String userId;
  final String category;
  final Map<String, dynamic> data;
  final String toEmail;
  final String signatureHtml;
  final TemplateRepository templateRepo;

  /// Genera al volo il PDF del documento da allegare (pipeline template).
  final Future<Uint8List?> Function()? buildPdfAttachment;
  final String attachmentFileName;
  final String? fromEmail;
  final String? fromName;

  @override
  State<_SendEmailDialog> createState() => _SendEmailDialogState();
}

class _SendEmailDialogState extends State<_SendEmailDialog> {
  List<EmailTemplate>? _templates;
  EmailTemplate? _selected;
  late final TextEditingController _to;
  late final TextEditingController _subject;
  late final TextEditingController _body;
  bool _loading = true;
  bool _sending = false;
  bool _preview = false;
  late bool _attachPdf = widget.buildPdfAttachment != null;

  @override
  void initState() {
    super.initState();
    _to = TextEditingController(text: widget.toEmail);
    _subject = TextEditingController();
    _body = TextEditingController();
    _loadTemplates();
  }

  @override
  void dispose() {
    _to.dispose();
    _subject.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _loadTemplates() async {
    final all = await widget.templateRepo.getEmailTemplates(widget.userId);
    final filtered = all.where((t) => t.category == widget.category).toList();
    setState(() {
      _templates = filtered;
      _loading = false;
      if (filtered.isNotEmpty) _selectTemplate(filtered.first);
    });
  }

  void _selectTemplate(EmailTemplate t) {
    setState(() {
      _selected = t;
      _subject.text = t.renderSubject(widget.data);
      _body.text = t.renderBody(widget.data);
    });
  }

  Future<void> _send() async {
    if (_to.text.trim().isEmpty) return;
    if ((widget.fromEmail ?? '').trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Configura l’email mittente in Impostazioni → Profilo prima di inviare.',
          ),
          backgroundColor: Color(0xFFEF4444),
        ),
      );
      return;
    }
    setState(() => _sending = true);
    try {
      var attachments = const <Map<String, String>>[];
      if (_attachPdf && widget.buildPdfAttachment != null) {
        final bytes = await widget.buildPdfAttachment!();
        if (bytes == null) {
          // Generazione annullata (es. scelta template chiusa): non inviare.
          if (mounted) setState(() => _sending = false);
          return;
        }
        attachments = [
          {
            'filename': widget.attachmentFileName,
            'mimeType': 'application/pdf',
            'base64': base64Encode(bytes),
          },
        ];
      }
      await TicketMailService().sendTicketEmail(
        toEmail: _to.text.trim(),
        subject: _subject.text.trim(),
        body: _body.text.trim(),
        attachmentPaths: const [],
        attachmentsBase64: attachments,
        signatureHtml: widget.signatureHtml,
        fromEmail: widget.fromEmail,
        fromName: widget.fromName,
      );
      if (mounted) {
        Navigator.of(context).pop(true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Email inviata con successo.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Errore invio: $e'),
            backgroundColor: const Color(0xFFEF4444),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final categoryLabel = widget.category == kPreventivo
        ? 'preventivo'
        : 'fattura';

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 700, maxHeight: 680),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Invia $categoryLabel al cliente',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF1C1D1F),
                      ),
                    ),
                  ),
                  // Preview toggle
                  if (_selected != null)
                    TextButton.icon(
                      onPressed: () => setState(() => _preview = !_preview),
                      icon: Icon(
                        _preview ? Icons.edit_outlined : Icons.preview_outlined,
                        size: 16,
                      ),
                      label: Text(_preview ? 'Modifica' : 'Anteprima'),
                    ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              if (_loading)
                const Expanded(
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_templates!.isEmpty)
                Expanded(child: _noTemplatesPlaceholder(categoryLabel))
              else ...[
                // Template selector
                DropdownButtonFormField<EmailTemplate>(
                  value: _selected,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Template email',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.email_outlined, size: 18),
                  ),
                  items: _templates!
                      .map(
                        (t) => DropdownMenuItem(value: t, child: Text(t.name)),
                      )
                      .toList(),
                  onChanged: (t) {
                    if (t != null) _selectTemplate(t);
                  },
                ),
                const SizedBox(height: 12),

                // To
                TextFormField(
                  controller: _to,
                  decoration: const InputDecoration(
                    labelText: 'Destinatario',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.person_outline, size: 18),
                  ),
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: 12),

                _senderPreview(),
                const SizedBox(height: 12),

                if (widget.buildPdfAttachment != null) ...[
                  CheckboxListTile(
                    value: _attachPdf,
                    onChanged: (v) => setState(() => _attachPdf = v ?? true),
                    controlAffinity: ListTileControlAffinity.leading,
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: Text(
                      'Allega PDF (${widget.attachmentFileName})',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: const Text(
                      'Generato col template del documento al momento dell\'invio',
                      style: TextStyle(fontSize: 11),
                    ),
                  ),
                  const SizedBox(height: 4),
                ],

                // Subject
                _preview
                    ? _previewField('Oggetto', _subject.text)
                    : TextFormField(
                        controller: _subject,
                        decoration: const InputDecoration(
                          labelText: 'Oggetto',
                          border: OutlineInputBorder(),
                        ),
                      ),
                const SizedBox(height: 12),

                // Body
                Expanded(
                  child: _preview
                      ? _previewBody(_body.text)
                      : TextFormField(
                          controller: _body,
                          maxLines: null,
                          expands: true,
                          textAlignVertical: TextAlignVertical.top,
                          decoration: const InputDecoration(
                            labelText: 'Corpo email',
                            border: OutlineInputBorder(),
                            alignLabelWithHint: true,
                          ),
                        ),
                ),
                const SizedBox(height: 16),

                // Actions
                Row(
                  children: [
                    const Spacer(),
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Annulla'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      onPressed: _sending ? null : _send,
                      icon: _sending
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.send_outlined, size: 16),
                      label: Text(
                        _sending ? 'Invio in corso...' : 'Invia email',
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _previewField(String label, String value) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    decoration: BoxDecoration(
      color: const Color(0xFF080A14),
      border: Border.all(color: const Color(0xFFE2D7C9)),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Row(
      children: [
        Text(
          '$label: ',
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Color(0xFF7D89A8),
          ),
        ),
        Expanded(child: Text(value, style: const TextStyle(fontSize: 13))),
      ],
    ),
  );

  Widget _senderPreview() {
    final fromEmail = (widget.fromEmail ?? '').trim();
    final fromName = (widget.fromName ?? '').trim();
    final missing = fromEmail.isEmpty;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: missing ? const Color(0xFFFFF2F2) : const Color(0xFFF4FAF8),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: missing ? const Color(0xFFFCA5A5) : const Color(0xFFB8DDD2),
        ),
      ),
      child: Row(
        children: [
          Icon(
            missing ? Icons.error_outline_rounded : Icons.outgoing_mail,
            size: 18,
            color: missing ? const Color(0xFFDC2626) : const Color(0xFF2E7D4F),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              missing
                  ? 'Mittente non configurato. Imposta l’email in Impostazioni → Profilo.'
                  : 'Mittente: ${fromName.isEmpty ? fromEmail : '$fromName <$fromEmail>'}',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: missing
                    ? const Color(0xFF991B1B)
                    : const Color(0xFF1F5F4A),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _previewBody(String value) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: const Color(0xFF080A14),
      border: Border.all(color: const Color(0xFFE2D7C9)),
      borderRadius: BorderRadius.circular(8),
    ),
    child: SingleChildScrollView(
      child: Text(value, style: const TextStyle(fontSize: 13, height: 1.6)),
    ),
  );

  Widget _noTemplatesPlaceholder(String categoryLabel) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.email_outlined, size: 48, color: Color(0xFFE2D7C9)),
        const SizedBox(height: 12),
        Text(
          'Nessun template email per $categoryLabel.',
          style: const TextStyle(color: Color(0xFF7D89A8)),
        ),
        const SizedBox(height: 8),
        const Text(
          'Vai in Impostazioni → Template → Email per crearne uno.',
          style: TextStyle(fontSize: 12, color: Color(0xFF525D78)),
          textAlign: TextAlign.center,
        ),
      ],
    ),
  );
}
