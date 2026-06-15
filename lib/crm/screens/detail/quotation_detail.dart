import '../../../brand_config.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../data/firestore_workspace_repository.dart';
import '../../../data/template_repository.dart';
import '../../../models/domain_models.dart';
import '../../../models/template_models.dart';
import '../../../settings/send_email_dialog.dart';
import '../../data/firestore_crm_repository.dart';
import '../../models/crm_extra_models.dart';
import 'detail_widgets.dart';

class QuotationDetailPage extends StatefulWidget {
  const QuotationDetailPage({
    super.key,
    required this.quotation,
    required this.workspace,
    required this.crmData,
    required this.crmRepo,
    required this.userId,
    required this.onBack,
    required this.onDelete,
  });

  final Quotation quotation;
  final WorkspaceSnapshot workspace;
  final CrmData crmData;
  final FirestoreCrmRepository crmRepo;
  final String userId;
  final VoidCallback onBack;
  final Future<void> Function() onDelete;

  @override
  State<QuotationDetailPage> createState() => _QuotationDetailPageState();
}

class _QuotationDetailPageState extends State<QuotationDetailPage> {
  late Quotation _q;
  final _currFmt = NumberFormat.currency(locale: 'it_IT', symbol: '€', decimalDigits: 2);
  final _dateFmt = DateFormat('dd/MM/yyyy');
  final _templateRepo = TemplateRepository();

  @override
  void initState() { super.initState(); _q = widget.quotation; }

  String get _customerName => _q.customerType == 'contact'
      ? widget.crmData.contactById(_q.customerId)?.fullName ?? '—'
      : widget.workspace.companies.where((c) => c.id == _q.customerId).firstOrNull?.name ?? '—';

  String get _customerEmail {
    if (_q.customerType == 'contact') {
      return widget.crmData.contactById(_q.customerId)?.email ?? '';
    }
    return widget.workspace.companies.where((c) => c.id == _q.customerId).firstOrNull?.email ?? '';
  }

  Deal? get _linkedDeal => widget.crmData.dealById(_q.dealId);

  Map<String, dynamic> _buildEmailData() {
    final billing = widget.workspace.billingProfile;
    final customer = _q.customerType == 'contact'
        ? widget.crmData.contactById(_q.customerId)
        : null;
    final company = widget.workspace.companies.where((c) => c.id == _q.customerId).firstOrNull;
    return {
      'emittente': {
        'nome': billing.businessName, 'piva': billing.vatNumber,
        'indirizzo': billing.addressLine, 'cap': billing.postalCode,
        'comune': billing.city, 'email': billing.email,
        'pec': billing.pec, 'telefono': billing.phone,
      },
      'cliente': {
        'nome': customer?.fullName ?? company?.name ?? _customerName,
        'email': _customerEmail,
        'piva': company?.vatNumber ?? '',
        'indirizzo': company?.addressLine ?? '',
        'cap': company?.postalCode ?? '', 'comune': company?.city ?? '',
      },
      'documento': {
        'numero': _q.number,
        'data': _q.createdAt != null ? _dateFmt.format(_q.createdAt!) : '',
        'validita': _q.validUntil != null ? _dateFmt.format(_q.validUntil!) : '',
        'totale': _currFmt.format(_q.total),
        'note': _q.notes,
      },
    };
  }

  Future<void> _openSendDialog(BuildContext context) async {
    await showSendEmailDialog(
      context: context,
      userId: widget.userId,
      category: kPreventivo,
      data: _buildEmailData(),
      toEmail: _customerEmail,
      signatureHtml: widget.workspace.emailSignatureHtml,
      templateRepo: _templateRepo,
    );
    // Aggiorna lo stato a "inviato" se non lo era già
    if (_q.status == QuotationStatus.draft && context.mounted) {
      final updated = _q.copyWith(status: QuotationStatus.sent);
      await widget.crmRepo.updateQuotation(widget.userId, updated);
      setState(() => _q = updated);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        DetailBackBar(label: 'Panoramica preventivi', onBack: widget.onBack, actions: [
          if (_q.status == QuotationStatus.draft)
            FilledButton.icon(
              onPressed: () => _openSendDialog(context),
              icon: const Icon(Icons.send_outlined, size: 16),
              label: const Text('Invia al cliente'),
            ),
          if (_q.status == QuotationStatus.sent) ...[
            const SizedBox(width: 8),
            FilledButton(onPressed: () async { final updated = _q.copyWith(status: QuotationStatus.accepted); await widget.crmRepo.updateQuotation(widget.userId, updated); setState(() => _q = updated); }, style: FilledButton.styleFrom(backgroundColor: GussoniBrand.primary), child: const Text('Segna accettato')),
          ],
          const SizedBox(width: 8),
          OutlinedButton.icon(onPressed: () async { await widget.onDelete(); widget.onBack(); }, icon: const Icon(Icons.delete_outline, size: 15), label: const Text('Elimina'), style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFFB91C1C), side: const BorderSide(color: Color(0xFFB91C1C)))),
        ]),

        // Info + lines cards
        LayoutBuilder(builder: (context, c) {
          final wide = c.maxWidth > 800;
          final infoCard = DetailInfoCard(
            title: 'Dettagli preventivo',
            avatar: Row(children: [
              Builder(builder: (ctx){ final c=GussoniBrand.primary; return Container(width:48,height:48,decoration:BoxDecoration(borderRadius:BorderRadius.circular(12),color:c.withOpacity(.12)),child:Icon(Icons.description_outlined,size:24,color:c));}),
              const SizedBox(width: 14),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(_q.number, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Color(0xFFE4E8FF))),
                DetailBadge(label: _q.status.label, color: _q.status.color),
              ])),
            ]),
            rows: [
              DetailInfoRow(label: 'Cliente', value: _customerName),
              if (_linkedDeal != null) DetailInfoRow(label: 'Opportunità', value: _linkedDeal!.title),
              DetailInfoRow(label: 'Totale', value: _currFmt.format(_q.total)),
              DetailInfoRow(label: 'Subtotale', value: _currFmt.format(_q.subtotal)),
              DetailInfoRow(label: 'IVA', value: _currFmt.format(_q.vatTotal)),
              if (_q.createdAt != null) DetailInfoRow(label: 'Data creazione', value: _dateFmt.format(_q.createdAt!)),
              if (_q.validUntil != null) DetailInfoRow(label: 'Valido fino al', value: _dateFmt.format(_q.validUntil!)),
              if (_q.notes.isNotEmpty) DetailInfoRow(label: 'Note', value: _q.notes),
            ],
          );

          final linesCard = _QuotationLinesCard(quotation: _q, crmData: widget.crmData, currFmt: _currFmt);

          if (wide) return IntrinsicHeight(child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(flex: 2, child: infoCard), const SizedBox(width: 16), Expanded(flex: 3, child: linesCard)]));
          return Column(children: [infoCard, const SizedBox(height: 12), linesCard]);
        }),

        const SizedBox(height: 32),
      ]),
    );
  }
}

class _QuotationLinesCard extends StatelessWidget {
  const _QuotationLinesCard({required this.quotation, required this.crmData, required this.currFmt});
  final Quotation quotation; final CrmData crmData; final NumberFormat currFmt;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0xFFE2D7C9))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(20, 16, 20, 12),
          child: Text('Righe preventivo', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Color(0xFFE4E8FF))),
        ),
        const Divider(height: 1, color: Color(0xFF1C1D1F)),
        // Header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          color: const Color(0xFF1C1D1F),
          child: const Row(children: [
            Expanded(flex: 4, child: Text('Descrizione', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF7D89A8)))),
            SizedBox(width: 60, child: Text('Qtà', textAlign: TextAlign.right, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF7D89A8)))),
            SizedBox(width: 90, child: Text('Prezzo', textAlign: TextAlign.right, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF7D89A8)))),
            SizedBox(width: 90, child: Text('Totale', textAlign: TextAlign.right, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF7D89A8)))),
          ]),
        ),
        // Lines
        ...quotation.lines.map((l) {
          final product = l.productId != null ? crmData.productById(l.productId) : null;
          return Column(children: [
            const Divider(height: 1, color: Color(0xFF1C1D1F)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Row(children: [
                Expanded(flex: 4, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(l.description, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  if (product != null) Row(children: [
                    const Icon(Icons.inventory_2_outlined, size: 11, color: Color(0xFF525D78)),
                    const SizedBox(width: 3),
                    Text('${product.name} · ${product.sku}', style: const TextStyle(fontSize: 11, color: Color(0xFF525D78))),
                  ]),
                ])),
                SizedBox(width: 60, child: Text('${l.quantity}', textAlign: TextAlign.right, style: const TextStyle(fontSize: 13, color: Color(0xFF7D89A8)))),
                SizedBox(width: 90, child: Text(currFmt.format(l.unitPrice), textAlign: TextAlign.right, style: const TextStyle(fontSize: 13, color: Color(0xFF7D89A8)))),
                SizedBox(width: 90, child: Text(currFmt.format(l.total), textAlign: TextAlign.right, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700))),
              ]),
            ),
          ]);
        }),
        // Total footer
        const Divider(height: 1, color: Color(0xFFE2D7C9)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          child: Row(children: [
            const Spacer(),
            Text('Subtotale: ${currFmt.format(quotation.subtotal)}', style: const TextStyle(fontSize: 13, color: Color(0xFF7D89A8))),
            const SizedBox(width: 16),
            Text('IVA: ${currFmt.format(quotation.vatTotal)}', style: const TextStyle(fontSize: 13, color: Color(0xFF7D89A8))),
            const SizedBox(width: 16),
            Text('Totale: ${currFmt.format(quotation.total)}', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: Color(0xFF034F3B))),
          ]),
        ),
      ]),
    );
  }
}
