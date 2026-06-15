import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';

import '../brand_config.dart';
import '../models/domain_models.dart';
import '../data/team_repository.dart';
import '../data/template_repository.dart';
import '../models/template_models.dart';
import 'pdf_generator.dart';

/// Genera il PDF di un documento reale (preventivo o fattura) usando i
/// template creati nel builder: scelta template per categoria, compilazione
/// dei campi personalizzati, anteprima stampabile/scaricabile.
class DocumentPdfService {
  static final _euro = NumberFormat('#,##0.00', 'it_IT');
  static final _date = DateFormat('dd/MM/yyyy');

  // ─── Entry point: Preventivo ───────────────────────────────────────────────

  static Future<void> generateForPreventivo(
    BuildContext context, {
    required String userId,
    String? teamId,
    required Preventivo preventivo,
    Company? company,
    required BillingProfile emittente,
  }) async {
    final preferred = await TemplateRepository().getDocTemplateChoice(
      userId,
      preventivo.id,
    );
    final shortId = preventivoShortId(preventivo);
    if (!context.mounted) return;
    return _run(
      context,
      userId: userId,
      teamId: teamId,
      category: kPreventivo,
      fileName: 'preventivo_$shortId.pdf',
      preferredTemplateId: preferred,
      data: preventivoData(
        preventivo: preventivo,
        company: company,
        emittente: emittente,
      ),
    );
  }

  static String preventivoShortId(Preventivo preventivo) =>
      preventivo.id.length >= 6
      ? preventivo.id.substring(preventivo.id.length - 6).toUpperCase()
      : preventivo.id.toUpperCase();

  /// Mappa variabili del preventivo: condivisa tra PDF e template email.
  static Map<String, dynamic> preventivoData({
    required Preventivo preventivo,
    Company? company,
    required BillingProfile emittente,
  }) {
    final righe = <Map<String, String>>[
      for (final line in preventivo.lines)
        {
          'descrizione': line.description,
          'qta': _qty(line.quantity),
          'prezzo': _euro.format(line.unitPrice),
          'totale': _euro.format(line.total),
        },
      if (preventivo.istruttoriaFee > 0)
        {
          'descrizione': 'Fee di istruttoria',
          'qta': '1',
          'prezzo': _euro.format(preventivo.istruttoriaFee),
          'totale': _euro.format(preventivo.istruttoriaFee),
        },
    ];
    final shortId = preventivoShortId(preventivo);
    return {
      'emittente': _emittenteMap(emittente),
      'cliente': _clienteMap(company),
      'documento': {
        'numero': 'PRV-$shortId',
        'data': _date.format(preventivo.createdAt),
        'validita': preventivo.expiresAt != null
            ? 'fino al ${_date.format(preventivo.expiresAt!)}'
            : '30 giorni',
        'scadenza': preventivo.expiresAt != null
            ? _date.format(preventivo.expiresAt!)
            : '',
        'totale': '€ ${_euro.format(preventivo.total)}',
        'pagamento': '',
        'iban': '',
        'note': preventivo.notes,
      },
      'righe': righe,
    };
  }

  // ─── Entry point: Fattura ──────────────────────────────────────────────────

  static Future<void> generateForInvoice(
    BuildContext context, {
    required String userId,
    String? teamId,
    required InvoiceDraft invoice,
    Company? company,
    required BillingProfile emittente,
  }) async {
    final preferred = await TemplateRepository().getDocTemplateChoice(
      userId,
      invoice.id,
    );
    if (!context.mounted) return;
    return _run(
      context,
      userId: userId,
      teamId: teamId,
      category: kFattura,
      fileName: 'fattura_${invoice.number.replaceAll('/', '-')}.pdf',
      preferredTemplateId: preferred,
      data: invoiceData(
        invoice: invoice,
        company: company,
        emittente: emittente,
      ),
    );
  }

  /// Mappa variabili della fattura: condivisa tra PDF e template email.
  static Map<String, dynamic> invoiceData({
    required InvoiceDraft invoice,
    Company? company,
    required BillingProfile emittente,
  }) {
    final righe = <Map<String, String>>[
      for (final line in invoice.lines)
        {
          'descrizione': line.description,
          'qta': _qty(line.quantity),
          'prezzo': _euro.format(line.unitPrice),
          'totale': _euro.format(line.net),
        },
      if (invoice.lines.isEmpty)
        {
          'descrizione': invoice.isSuccessFee
              ? 'Success fee su contributo riconosciuto'
              : (invoice.notes.isNotEmpty
                    ? invoice.notes
                    : 'Prestazioni professionali'),
          'qta': '1',
          'prezzo': _euro.format(invoice.amount),
          'totale': _euro.format(invoice.amount),
        },
    ];
    return {
      'emittente': _emittenteMap(emittente),
      'cliente': _clienteMap(company),
      'documento': {
        'numero': invoice.number,
        'data': invoice.createdAt != null
            ? _date.format(invoice.createdAt!)
            : _date.format(DateTime.now()),
        'validita': '',
        'scadenza': '',
        'totale': '€ ${_euro.format(invoice.amount)}',
        'pagamento': '',
        'iban': '',
        'note': invoice.notes,
      },
      'righe': righe,
    };
  }

  // ─── Helpers dati ──────────────────────────────────────────────────────────

  static String _qty(double q) =>
      q == q.roundToDouble() ? q.toStringAsFixed(0) : q.toStringAsFixed(2);

  static Map<String, String> _emittenteMap(BillingProfile p) => {
    'nome': p.businessName,
    'piva': p.vatNumber.isNotEmpty ? 'P.IVA ${p.vatNumber}' : '',
    'cf': p.taxCode,
    'indirizzo': p.addressLine,
    'cap': p.postalCode,
    'comune': [
      p.postalCode,
      p.city,
    ].where((s) => s.trim().isNotEmpty).join(' '),
    'email': p.email,
    'pec': p.pec,
    'telefono': p.phone,
  };

  static Map<String, String> _clienteMap(Company? c) => {
    'nome': c?.name ?? '',
    'piva': (c?.vatNumber ?? '').isNotEmpty ? 'P.IVA ${c!.vatNumber}' : '',
    'cf': c?.taxCode ?? '',
    'indirizzo': c?.addressLine ?? '',
    'cap': c?.postalCode ?? '',
    'comune': [
      c?.postalCode ?? '',
      c?.city ?? '',
    ].where((s) => s.trim().isNotEmpty).join(' '),
    'email': c?.email ?? '',
  };

  // ─── Flusso comune ─────────────────────────────────────────────────────────

  /// Esegue l'intera pipeline (scelta template, campi personalizzati,
  /// asset remoti, logo team) e ritorna i byte del PDF, senza mostrarlo.
  /// Ritorna `null` se l'utente annulla o non ci sono template.
  static Future<Uint8List?> buildDocumentPdfBytes(
    BuildContext context, {
    required String userId,
    String? teamId,
    required String category,
    String? docId,
    required Map<String, dynamic> data,
  }) async {
    String? preferredTemplateId;
    if (docId != null && docId.isNotEmpty) {
      preferredTemplateId = await TemplateRepository().getDocTemplateChoice(
        userId,
        docId,
      );
    }
    if (!context.mounted) return null;
    return _buildBytes(
      context,
      userId: userId,
      teamId: teamId,
      category: category,
      preferredTemplateId: preferredTemplateId,
      data: data,
    );
  }

  static Future<void> _run(
    BuildContext context, {
    required String userId,
    String? teamId,
    required String category,
    required String fileName,
    String? preferredTemplateId,
    required Map<String, dynamic> data,
  }) async {
    final bytes = await _buildBytes(
      context,
      userId: userId,
      teamId: teamId,
      category: category,
      preferredTemplateId: preferredTemplateId,
      data: data,
    );
    if (bytes == null || !context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            _DocumentPdfPreviewPage(bytes: bytes, fileName: fileName),
      ),
    );
  }

  static Future<Uint8List?> _buildBytes(
    BuildContext context, {
    required String userId,
    String? teamId,
    required String category,
    String? preferredTemplateId,
    required Map<String, dynamic> data,
  }) async {
    // 1. Template disponibili per la categoria (MySQL, fallback Firestore).
    final templates = await TemplateRepository().getTemplates(
      userId,
      category: category,
    );

    if (!context.mounted) return null;
    if (templates.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Nessun template ${category == kFattura ? 'fattura' : 'preventivo'} '
            'disponibile. Crealo da Impostazioni → Template.',
          ),
        ),
      );
      return null;
    }

    // 2. Template preferito del documento, altrimenti scelta manuale.
    final preferred = preferredTemplateId == null
        ? null
        : templates.where((t) => t.id == preferredTemplateId).firstOrNull;
    DocumentTemplate? template =
        preferred ??
        (templates.length == 1
            ? templates.first
            : await showDialog<DocumentTemplate>(
                context: context,
                builder: (ctx) => SimpleDialog(
                  title: const Text('Scegli il template'),
                  children: templates
                      .map(
                        (t) => SimpleDialogOption(
                          onPressed: () => Navigator.of(ctx).pop(t),
                          child: Row(
                            children: [
                              Icon(
                                Icons.description_outlined,
                                size: 18,
                                color: GussoniBrand.primary,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  t.name,
                                  style: const TextStyle(fontSize: 14),
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                      .toList(),
                ),
              ));
    if (template == null || !context.mounted) return null;

    // 3. Campi personalizzati.
    if (template.customFields.isNotEmpty) {
      final custom = await _askCustomFields(context, template.customFields);
      if (custom == null || !context.mounted) return null;
      data['custom'] = custom;
    }

    // 4. Risorse remote (sfondo pagina, immagini elemento, logo brand team).
    await prefetchTemplateAssets(template, data);
    if (teamId != null) {
      try {
        final logoUrl = await TeamRepository().fetchTeamBrandLogo(teamId);
        if (logoUrl != null && logoUrl.isNotEmpty) {
          data['logo'] = await _fetchBytes(logoUrl);
        }
      } catch (_) {}
    }

    // 5. Genera.
    return generatePdf(template, data);
  }

  static Future<Uint8List?> _fetchBytes(String url) async {
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return response.bodyBytes;
      }
    } catch (_) {}
    return null;
  }

  static Future<Map<String, String>?> _askCustomFields(
    BuildContext context,
    List<TemplateCustomField> fields,
  ) {
    final controllers = {
      for (final f in fields) f.key: TextEditingController(),
    };
    return showDialog<Map<String, String>>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Completa i campi del documento'),
        content: SizedBox(
          width: 380,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final f in fields)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: TextField(
                      controller: controllers[f.key],
                      maxLines: f.inputType == 'textarea' ? 3 : 1,
                      keyboardType: f.inputType == 'number'
                          ? const TextInputType.numberWithOptions(decimal: true)
                          : null,
                      decoration: InputDecoration(labelText: f.label),
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Annulla'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop({
              for (final entry in controllers.entries)
                entry.key: entry.value.text.trim(),
            }),
            child: const Text('Genera PDF'),
          ),
        ],
      ),
    );
  }
}

class _DocumentPdfPreviewPage extends StatelessWidget {
  const _DocumentPdfPreviewPage({required this.bytes, required this.fileName});

  final Uint8List bytes;
  final String fileName;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(fileName)),
      body: PdfPreview(
        build: (_) async => bytes,
        pdfFileName: fileName,
        allowPrinting: true,
        allowSharing: true,
        canDebug: false,
      ),
    );
  }
}
