import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../brand_config.dart';
import '../../data/api_workspace_repository.dart';
import '../../models/domain_models.dart';
import '../widgets/g_table.dart';

String _companyTypeLabel(CompanyType t) => switch (t) {
  CompanyType.profit => 'P — Profit',
  CompanyType.nonProfit => 'NP — Non Profit',
  CompanyType.pa => 'PA — Pubblica Amministrazione',
  CompanyType.pf => 'PF — Profit/Fondazione',
};

String _companySizeLabel(CompanySize s) => switch (s) {
  CompanySize.micro => 'Micro',
  CompanySize.piccola => 'Piccola',
  CompanySize.media => 'Media',
  CompanySize.grande => 'Grande',
};

class SocietaGussoniScreen extends StatefulWidget {
  const SocietaGussoniScreen({
    super.key,
    required this.workspace,
    required this.userId,
    required this.repository,
    this.onOpenCompanyDialog,
    this.onEditCompany,
    this.onOpenCompany,
    this.showHeader = true,
    this.showCreateButton = true,
    this.isPinned = false,
    this.onPinContext,
  });
  final WorkspaceSnapshot workspace;
  final String userId;
  final ApiWorkspaceRepository repository;
  final VoidCallback? onOpenCompanyDialog;
  final void Function(Company)? onEditCompany;
  final void Function(Company)? onOpenCompany;
  final bool showHeader;
  final bool showCreateButton;
  final bool isPinned;
  final VoidCallback? onPinContext;

  @override
  State<SocietaGussoniScreen> createState() => _SocietaGussoniScreenState();
}

class _SocietaGussoniScreenState extends State<SocietaGussoniScreen> {
  String _search = '';
  Company? _mobileSelected;

  List<Company> get _filtered => widget.workspace.companies
      .where(
        (c) =>
            _search.isEmpty ||
            c.name.toLowerCase().contains(_search.toLowerCase()) ||
            c.city.toLowerCase().contains(_search.toLowerCase()) ||
            c.vatNumber.contains(_search),
      )
      .toList();

  int _contactCount(String companyId) => widget.workspace.companyContacts
      .where((c) => c.companyId == companyId)
      .length;

  int _projectCount(String companyId) =>
      widget.workspace.projects.where((p) => p.companyId == companyId).length;

  @override
  Widget build(BuildContext context) {
    final cols = <GCol<Company>>[
      GCol(
        label: 'Azienda',
        flex: 4,
        cell: (c) => Row(
          children: [
            GAvatar(c.name),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  GCellText(c.name, bold: true),
                  if (c.city.isNotEmpty) GCellText(c.city, muted: true),
                ],
              ),
            ),
          ],
        ),
      ),
      GCol(
        label: 'Tipo',
        flex: 2,
        cell: (c) => GCellText(_companyTypeLabel(c.companyType), muted: true),
      ),
      GCol(
        label: 'P.IVA / CF',
        flex: 3,
        cell: (c) => GCellText(
          c.vatNumber.isNotEmpty ? c.vatNumber : c.taxCode,
          muted: true,
        ),
      ),
      GCol(
        label: 'Email',
        flex: 3,
        cell: (c) => GCellText(c.email.isNotEmpty ? c.email : '—', muted: true),
      ),
      GCol(
        label: 'Contatti',
        flex: 1,
        cell: (c) => _CountBadge(_contactCount(c.id), Icons.people_outline),
      ),
      GCol(
        label: 'Progetti',
        flex: 1,
        cell: (c) =>
            _CountBadge(_projectCount(c.id), Icons.folder_open_outlined),
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < 560;

        final listPane = GScreenLayout(
          title: 'Società',
          count: _filtered.length,
          showHeader: widget.showHeader,
          isPinned: widget.isPinned,
          onPinContext: widget.onPinContext,
          contextActions: () => [
            if (widget.onOpenCompanyDialog != null)
              GContextMenuAction(
                label: 'Nuova società',
                icon: Icons.add_business_outlined,
                onSelected: widget.onOpenCompanyDialog!,
              ),
          ],
          action: widget.showCreateButton
              ? FilledButton.icon(
                  onPressed: widget.onOpenCompanyDialog,
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Nuova società'),
                )
              : null,
          searchHint: 'Cerca per nome, città, P.IVA…',
          onSearch: (v) => setState(() {
            _search = v;
            _mobileSelected = null;
          }),
          body: GTable<Company>(
            columns: cols,
            rows: _filtered,
            isSelected: (_) => false,
            onRowTap: (c) {
              if (isMobile) {
                setState(() => _mobileSelected = c);
              } else {
                widget.onOpenCompany?.call(c);
              }
            },
            contextActionsForRow: (c) => [
              GContextMenuAction(
                label: 'Apri società',
                icon: Icons.open_in_new_rounded,
                onSelected: () {
                  if (isMobile) {
                    setState(() => _mobileSelected = c);
                  } else {
                    widget.onOpenCompany?.call(c);
                  }
                },
              ),
              if (widget.onEditCompany != null)
                GContextMenuAction(
                  label: 'Modifica',
                  icon: Icons.edit_outlined,
                  onSelected: () => widget.onEditCompany!(c),
                ),
            ],
            emptyLabel: 'Nessuna società trovata.',
            emptyIcon: Icons.apartment_outlined,
          ),
        );

        if (!isMobile) return listPane;

        return GMobileNavWrapper(
          showDetail: _mobileSelected != null,
          list: listPane,
          detail: _mobileSelected == null
              ? const SizedBox.shrink()
              : Column(
                  children: [
                    GMobileBackBar(
                      backLabel: 'Società',
                      title: _mobileSelected!.name,
                      onBack: () => setState(() => _mobileSelected = null),
                      action: widget.onEditCompany != null
                          ? IconButton(
                              onPressed: () =>
                                  widget.onEditCompany!(_mobileSelected!),
                              icon: Icon(
                                Icons.edit_outlined,
                                size: 18,
                                color: GussoniBrand.primary,
                              ),
                            )
                          : null,
                    ),
                    Expanded(
                      child: GDetailPanel(
                        title: _mobileSelected!.name,
                        subtitle: _companyTypeLabel(
                          _mobileSelected!.companyType,
                        ),
                        icon: GAvatar(_mobileSelected!.name, size: 32),
                        children: [
                          GDetailSection(
                            title: 'Dati aziendali',
                            children: [
                              GInfoRow('Nome', _mobileSelected!.name),
                              GInfoRow(
                                'Tipo',
                                _companyTypeLabel(_mobileSelected!.companyType),
                              ),
                              if (_mobileSelected!.city.isNotEmpty)
                                GInfoRow('Città', _mobileSelected!.city),
                              if (_mobileSelected!.vatNumber.isNotEmpty)
                                GInfoRow('P.IVA', _mobileSelected!.vatNumber),
                              if (_mobileSelected!.taxCode.isNotEmpty)
                                GInfoRow('CF', _mobileSelected!.taxCode),
                              if (_mobileSelected!.email.isNotEmpty)
                                GInfoRow('Email', _mobileSelected!.email),
                              if (_mobileSelected!.phone.isNotEmpty)
                                GInfoRow('Telefono', _mobileSelected!.phone),
                            ],
                          ),
                          GDetailSection(
                            title: 'Attività',
                            children: [
                              GInfoRow(
                                'Contatti',
                                '${_contactCount(_mobileSelected!.id)}',
                              ),
                              GInfoRow(
                                'Progetti',
                                '${_projectCount(_mobileSelected!.id)}',
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
        );
      },
    );
  }
}

class _CountBadge extends StatelessWidget {
  const _CountBadge(this.count, this.icon);
  final int count;
  final IconData icon;

  @override
  Widget build(BuildContext context) => count == 0
      ? GCellText('—', muted: true)
      : Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: GussoniBrand.textMuted),
            const SizedBox(width: 4),
            GCellText('$count'),
          ],
        );
}
