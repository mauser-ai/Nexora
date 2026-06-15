import '../../brand_config.dart';
import 'package:flutter/material.dart';

import '../../models/domain_models.dart';
import '../../data/firestore_workspace_repository.dart';
import '../models/crm_extra_models.dart';
import 'tl_table.dart';

class SocietaCard extends StatefulWidget {
  const SocietaCard({
    super.key,
    required this.workspace,
    required this.crmData,
    required this.onAddCompany,
    required this.onEditCompany,
    this.onOpenDetail,
  });

  final WorkspaceSnapshot workspace;
  final CrmData crmData;
  final VoidCallback onAddCompany;
  final Future<void> Function(Company) onEditCompany;
  final void Function(Company)? onOpenDetail;

  @override
  State<SocietaCard> createState() => _SocietaCardState();
}

class _SocietaCardState extends State<SocietaCard> {
  static final DateTime _epoch = DateTime.fromMillisecondsSinceEpoch(0);

  String _initials(String name) {
    final parts = name.trim().split(' ');
    if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    return name.isNotEmpty ? name[0].toUpperCase() : '?';
  }

  Color _colorForName(String name) {
    const p = [
      Color(0xFF0369A1),
      Color(0xFF7C3AED),
      Color(0xFF034F3B),
      Color(0xFFD97706),
      Color(0xFF0891B2),
      Color(0xFFB91C1C),
    ];
    return p[name.codeUnits.fold<int>(0, (a, c) => a * 31 + c).abs() %
        p.length];
  }

  // Workspace contacts (CompanyContact) + CRM contacts (CrmFirestoreContact)
  int _contactsCount(Company company) {
    final workspace = widget.workspace.companyContacts
        .where((c) => c.companyId == company.id)
        .length;
    final crm = widget.crmData.contactsForCompany(company.id).length;
    return workspace + crm;
  }

  int _projectsCount(Company company) =>
      widget.workspace.projects.where((p) => p.companyId == company.id).length;

  // Deal CRM aperti collegati all'azienda
  int _openDealsCount(Company company) => widget.crmData
      .dealsForCustomer(company.id)
      .where((d) => d.status == DealFirestoreStatus.open)
      .length;

  DateTime _latestCompanyActivity(Company company) {
    DateTime latest = _epoch;

    for (final ticket in widget.workspace.tickets) {
      if (ticket.companyId == company.id && ticket.updatedAt.isAfter(latest)) {
        latest = ticket.updatedAt;
      }
    }

    for (final contact in widget.crmData.contactsForCompany(company.id)) {
      final candidate = contact.updatedAt ?? contact.createdAt;
      if (candidate != null && candidate.isAfter(latest)) {
        latest = candidate;
      }
    }

    for (final deal in widget.crmData.dealsForCustomer(company.id)) {
      final candidate = deal.updatedAt ?? deal.createdAt;
      if (candidate != null && candidate.isAfter(latest)) {
        latest = candidate;
      }
    }

    for (final task in widget.workspace.tasks) {
      if (task.companyId == company.id) {
        if (task.startDate.isAfter(latest)) {
          latest = task.startDate;
        }
        if (task.deadline.isAfter(latest)) {
          latest = task.deadline;
        }
      }
    }

    return latest;
  }

  List<TlRow> get _rows {
    final companies = [...widget.workspace.companies]
      ..sort((a, b) {
        final byRecent = _latestCompanyActivity(
          b,
        ).compareTo(_latestCompanyActivity(a));
        if (byRecent != 0) {
          return byRecent;
        }
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });

    return companies.map((company) {
      final color = _colorForName(company.name);
      final contacts = _contactsCount(company);
      final projects = _projectsCount(company);
      final deals = _openDealsCount(company);
      return TlRow(
        key: company.id,
        onTap: () => widget.onOpenDetail != null
            ? widget.onOpenDetail!(company)
            : widget.onEditCompany(company),
        cells: [
          TlCell(
            widget: Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: color.withValues(alpha: 0.14),
                    border: Border.all(color: color.withValues(alpha: 0.35)),
                  ),
                  child: Center(
                    child: Text(
                      _initials(company.name),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: color,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TlPrimaryCell(
                    text: company.name,
                    sub: company.city.isNotEmpty ? company.city : null,
                  ),
                ),
              ],
            ),
          ),
          TlCell(text: company.vatNumber.isEmpty ? '—' : company.vatNumber),
          TlCell(text: company.email.isEmpty ? '—' : company.email),
          TlCell(text: company.phone.isEmpty ? '—' : company.phone),
          // Contatti (workspace + CRM)
          TlCell(
            widget: contacts > 0
                ? Row(
                    children: [
                      const Icon(
                        Icons.people_outline,
                        size: 13,
                        color: Color(0xFF0369A1),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '$contacts',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF0369A1),
                        ),
                      ),
                    ],
                  )
                : const Text('—', style: TextStyle(color: Color(0xFF525D78))),
          ),
          // Deal CRM aperti
          TlCell(
            widget: deals > 0
                ? Row(
                    children: [
                      Icon(
                        Icons.trending_up_outlined,
                        size: 13,
                        color: GussoniBrand.primary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '$deals',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: GussoniBrand.primary,
                        ),
                      ),
                    ],
                  )
                : const Text('—', style: TextStyle(color: Color(0xFF525D78))),
          ),
          // Progetti
          TlCell(
            widget: projects > 0
                ? Row(
                    children: [
                      const Icon(
                        Icons.folder_open_outlined,
                        size: 13,
                        color: Color(0xFF034F3B),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '$projects',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF034F3B),
                        ),
                      ),
                    ],
                  )
                : const Text('—', style: TextStyle(color: Color(0xFF525D78))),
          ),
          TlCell(
            widget: TlRowActions(
              items: [
                PopupMenuItem(
                  value: 'edit',
                  child: const Text('Modifica'),
                  onTap: () => widget.onEditCompany(company),
                ),
              ],
            ),
          ),
        ],
      );
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return TlTable(
      searchHint: 'Cerca società...',
      columns: const [
        TlColumn(label: 'Ragione sociale', flex: 3),
        TlColumn(label: 'P.IVA', flex: 2),
        TlColumn(label: 'Email', flex: 2),
        TlColumn(label: 'Telefono', flex: 2),
        TlColumn(label: 'Contatti', flex: 1),
        TlColumn(label: 'Deal aperti', flex: 1),
        TlColumn(label: 'Progetti', flex: 1),
        TlColumn(label: '', minWidth: 40),
      ],
      rows: _rows,
      onAdd: widget.onAddCompany,
      addLabel: 'Aggiungi società',
      emptyMessage: 'Nessuna società trovata.',
    );
  }
}
