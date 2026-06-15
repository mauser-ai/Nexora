import '../../brand_config.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../data/firestore_crm_repository.dart';
import '../models/crm_extra_models.dart';

class FormDiContattoCard extends StatefulWidget {
  const FormDiContattoCard({super.key, required this.crmData, required this.crmRepo, required this.userId});
  final CrmData crmData; final FirestoreCrmRepository crmRepo; final String userId;
  @override State<FormDiContattoCard> createState() => _FormDiContattoCardState();
}

class _FormDiContattoCardState extends State<FormDiContattoCard> {
  ContactFormStatus? _filter;
  ContactForm? _selected;

  List<ContactForm> get _filtered => _filter == null ? widget.crmData.contactForms : widget.crmData.contactForms.where((f) => f.status == _filter).toList();

  @override
  Widget build(BuildContext context) {
    final forms = _filtered;
    final byStatus = <ContactFormStatus, int>{};
    for (final f in widget.crmData.contactForms) byStatus[f.status] = (byStatus[f.status] ?? 0) + 1;

    return LayoutBuilder(builder: (context, constraints) {
      final showDetail = _selected != null && constraints.maxWidth > 720;

      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // ── Stats + filter ──
        Row(children: [
          ...[null, ...ContactFormStatus.values].map((s) {
            final label = s == null ? 'Tutti' : s.label;
            final color = s == null ? const Color(0xFFB8C0D8) : s.color;
            final count = s == null ? widget.crmData.contactForms.length : (byStatus[s] ?? 0);
            return Padding(padding: const EdgeInsets.only(right: 8), child: _FilterPill(label: '$label ($count)', color: color, selected: _filter == s, onTap: () => setState(() => _filter = s)));
          }),
        ]),
        const SizedBox(height: 16),
        Expanded(
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // List
            SizedBox(
              width: showDetail ? 380 : double.infinity,
              child: forms.isEmpty
                  ? const Center(child: Text('Nessun form di contatto.', style: TextStyle(color: Color(0xFF525D78))))
                  : ListView.separated(
                      itemCount: forms.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, i) {
                        final f = forms[i];
                        final isSel = _selected?.id == f.id;
                        return InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () => setState(() => _selected = f),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 120),
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: isSel ? GussoniBrand.primary.withValues(alpha: 0.06) : const Color(0xFF0E1020),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: isSel ? GussoniBrand.primary.withValues(alpha: 0.4) : const Color(0xFF1E2130), width: isSel ? 1.5 : 1),
                            ),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Row(children: [
                                Expanded(child: Text(f.name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Color(0xFF0F172A)))),
                                _StatusBadge(status: f.status),
                              ]),
                              const SizedBox(height: 4),
                              Text(f.email, style: const TextStyle(fontSize: 12, color: Color(0xFF7D89A8))),
                              if (f.message.isNotEmpty) ...[const SizedBox(height: 6), Text(f.message, style: const TextStyle(fontSize: 13, color: Color(0xFFB8C0D8)), maxLines: 2, overflow: TextOverflow.ellipsis)],
                              const SizedBox(height: 6),
                              Row(children: [
                                _SourceBadge(source: f.source),
                                const Spacer(),
                                if (f.createdAt != null) Text(DateFormat('dd/MM/yy HH:mm').format(f.createdAt!), style: const TextStyle(fontSize: 11, color: Color(0xFF525D78))),
                              ]),
                            ]),
                          ),
                        );
                      },
                    ),
            ),
            // Detail
            if (showDetail) ...[
              const SizedBox(width: 16),
              Expanded(child: _FormDetail(form: _selected!, crmRepo: widget.crmRepo, userId: widget.userId, onClose: () => setState(() => _selected = null))),
            ],
          ]),
        ),
      ]);
    });
  }
}

class _FormDetail extends StatelessWidget {
  const _FormDetail({required this.form, required this.crmRepo, required this.userId, required this.onClose});
  final ContactForm form; final FirestoreCrmRepository crmRepo; final String userId; final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFF1E2130))),
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(form.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Color(0xFF0F172A)))),
          _StatusBadge(status: form.status),
          const SizedBox(width: 8),
          IconButton(onPressed: onClose, icon: const Icon(Icons.close, size: 18, color: Color(0xFF525D78))),
        ]),
        const SizedBox(height: 16),
        _InfoLine(icon: Icons.email_outlined, label: form.email),
        if (form.phone.isNotEmpty) _InfoLine(icon: Icons.phone_outlined, label: form.phone),
        _InfoLine(icon: Icons.source_outlined, label: 'Fonte: ${form.source}'),
        if (form.createdAt != null) _InfoLine(icon: Icons.schedule_outlined, label: DateFormat('dd/MM/yyyy HH:mm').format(form.createdAt!)),
        const SizedBox(height: 16),
        const Text('Messaggio', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF525D78))),
        const SizedBox(height: 8),
        Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: const Color(0xFF080A14), borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFF1E2130))), child: Text(form.message.isEmpty ? '—' : form.message, style: const TextStyle(fontSize: 13, color: Color(0xFFB8C0D8), height: 1.5))),
        const SizedBox(height: 20),
        const Text('Aggiorna stato', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF525D78))),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: ContactFormStatus.values.map((s) => OutlinedButton(
          onPressed: form.status == s ? null : () => crmRepo.updateContactForm(userId, form.copyWith(status: s)),
          style: OutlinedButton.styleFrom(foregroundColor: s.color, side: BorderSide(color: s.color), disabledBackgroundColor: s.color.withValues(alpha: 0.10)),
          child: Text(s.label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: form.status == s ? s.color : null)),
        )).toList()),
      ]),
    );
  }
}

class _InfoLine extends StatelessWidget {
  const _InfoLine({required this.icon, required this.label});
  final IconData icon; final String label;
  @override Widget build(BuildContext context) => Padding(padding: const EdgeInsets.only(bottom: 8), child: Row(children: [Icon(icon, size: 15, color: const Color(0xFF525D78)), const SizedBox(width: 8), Expanded(child: Text(label, style: const TextStyle(fontSize: 13, color: Color(0xFFB8C0D8))))]));
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});
  final ContactFormStatus status;
  @override Widget build(BuildContext context) => Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3), decoration: BoxDecoration(borderRadius: BorderRadius.circular(999), color: status.color.withValues(alpha: 0.10), border: Border.all(color: status.color.withValues(alpha: 0.30))), child: Text(status.label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: status.color)));
}

class _SourceBadge extends StatelessWidget {
  const _SourceBadge({required this.source});
  final String source;
  String get _label {
    switch (source) {
      case 'website': return '🌐 Sito web';
      case 'google_ads': return '📢 Google Ads';
      case 'instagram': return '📷 Instagram';
      case 'passaparola': return '🗣 Passaparola';
      default: return source;
    }
  }
  @override Widget build(BuildContext context) => Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3), decoration: BoxDecoration(borderRadius: BorderRadius.circular(999), color: const Color(0xFF0C0E1A)), child: Text(_label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFFB8C0D8))));
}

class _FilterPill extends StatelessWidget {
  const _FilterPill({required this.label, required this.color, required this.selected, required this.onTap});
  final String label; final Color color; final bool selected; final VoidCallback onTap;
  @override Widget build(BuildContext context) => InkWell(borderRadius: BorderRadius.circular(8), onTap: onTap, child: Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6), decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), color: selected ? color.withValues(alpha: 0.10) : Colors.transparent, border: selected ? Border.all(color: color.withValues(alpha: 0.4)) : null), child: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: selected ? color : const Color(0xFF525D78)))));
}
