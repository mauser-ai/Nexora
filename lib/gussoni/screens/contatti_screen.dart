import 'package:flutter/material.dart';
import '../../app/nexora_dialog.dart';
import '../../brand_config.dart';
import '../../data/api_workspace_repository.dart';
import '../../models/domain_models.dart';
import '../widgets/g_table.dart';

class ContattiGussoniScreen extends StatefulWidget {
  const ContattiGussoniScreen({
    super.key,
    required this.workspace,
    required this.userId,
    required this.repository,
    this.onCreateContact,
    this.onEditContact,
    this.onOpenContact,
    this.showHeader = true,
    this.showCreateButton = true,
    this.isPinned = false,
    this.onPinContext,
  });
  final WorkspaceSnapshot workspace;
  final String userId;
  final ApiWorkspaceRepository repository;
  final VoidCallback? onCreateContact;
  final void Function(CompanyContact)? onEditContact;
  final void Function(CompanyContact)? onOpenContact;
  final bool showHeader;
  final bool showCreateButton;
  final bool isPinned;
  final VoidCallback? onPinContext;

  @override
  State<ContattiGussoniScreen> createState() => _ContattiGussoniScreenState();
}

class _ContattiGussoniScreenState extends State<ContattiGussoniScreen> {
  String _search = '';
  CompanyContact? _selected;

  List<CompanyContact> get _filtered => widget.workspace.companyContacts
      .where(
        (c) =>
            _search.isEmpty ||
            c.name.toLowerCase().contains(_search.toLowerCase()) ||
            c.email.toLowerCase().contains(_search.toLowerCase()) ||
            c.role.toLowerCase().contains(_search.toLowerCase()),
      )
      .toList();

  String _companyName(String id) {
    if (id.isEmpty) return '—';
    return widget.workspace.companies
            .where((c) => c.id == id)
            .firstOrNull
            ?.name ??
        '—';
  }

  @override
  Widget build(BuildContext context) {
    final cols = <GCol<CompanyContact>>[
      GCol(
        label: 'Nome',
        flex: 3,
        cell: (c) => Row(
          children: [
            GAvatar(c.name, color: GussoniBrand.gold),
            const SizedBox(width: 10),
            Expanded(child: GCellText(c.name, bold: true)),
          ],
        ),
      ),
      GCol(
        label: 'Azienda',
        flex: 3,
        cell: (c) => c.companyId.isNotEmpty
            ? GCellText(_companyName(c.companyId), muted: true)
            : GCellText('Nessuna azienda', muted: true),
      ),
      GCol(
        label: 'Ruolo',
        flex: 2,
        cell: (c) => c.role.isNotEmpty
            ? GStatusChip(
                label: c.role,
                color: GussoniBrand.primary,
                small: true,
              )
            : GCellText('—', muted: true),
      ),
      GCol(
        label: 'Email',
        flex: 3,
        cell: (c) => GCellText(c.email.isNotEmpty ? c.email : '—', muted: true),
      ),
      GCol(
        label: 'Telefono',
        flex: 2,
        cell: (c) => GCellText(c.phone.isNotEmpty ? c.phone : '—', muted: true),
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < 560;

        // ── Widgets riutilizzati in entrambe le modalità ───────────────────────
        final listPane = GScreenLayout(
          title: 'Contatti',
          count: _filtered.length,
          showHeader: widget.showHeader,
          isPinned: widget.isPinned,
          onPinContext: widget.onPinContext,
          contextActions: () => [
            if (widget.onCreateContact != null)
              GContextMenuAction(
                label: 'Nuovo contatto',
                icon: Icons.person_add_outlined,
                onSelected: widget.onCreateContact!,
              ),
          ],
          action: widget.showCreateButton
              ? FilledButton.icon(
                  onPressed: widget.onCreateContact,
                  icon: const Icon(Icons.person_add_outlined, size: 16),
                  label: const Text('Nuovo contatto'),
                )
              : null,
          searchHint: 'Cerca per nome, email, ruolo…',
          onSearch: (v) => setState(() {
            _search = v;
            _selected = null;
          }),
          body: GTable<CompanyContact>(
            columns: cols,
            rows: _filtered,
            isSelected: (c) => _selected?.id == c.id,
            onRowTap: (c) {
              if (!isMobile && widget.onOpenContact != null) {
                widget.onOpenContact!(c);
                return;
              }
              setState(() => _selected = c);
            },
            contextActionsForRow: (c) => [
              GContextMenuAction(
                label: 'Apri contatto',
                icon: Icons.open_in_new_rounded,
                onSelected: () {
                  if (!isMobile && widget.onOpenContact != null) {
                    widget.onOpenContact!(c);
                  } else {
                    setState(() => _selected = c);
                  }
                },
              ),
              if (widget.onEditContact != null)
                GContextMenuAction(
                  label: 'Modifica',
                  icon: Icons.edit_outlined,
                  onSelected: () => widget.onEditContact!(c),
                ),
              GContextMenuAction(
                label: 'Elimina',
                icon: Icons.delete_outline_rounded,
                destructive: true,
                onSelected: () => _deleteContact(c),
              ),
            ],
            emptyLabel: 'Nessun contatto trovato.',
            emptyIcon: Icons.people_outline,
          ),
        );

        Widget detailPanel(CompanyContact c) => GDetailPanel(
          title: c.name,
          subtitle: c.role.isNotEmpty ? c.role : _companyName(c.companyId),
          icon: GAvatar(c.name, size: 32, color: GussoniBrand.gold),
          onClose: isMobile ? null : () => setState(() => _selected = null),
          actions: [
            if (widget.onEditContact != null)
              IconButton(
                onPressed: () => widget.onEditContact!(c),
                icon: const Icon(
                  Icons.edit_outlined,
                  size: 16,
                  color: GussoniBrand.textMuted,
                ),
                tooltip: 'Modifica',
              ),
          ],
          children: [
            GDetailSection(
              title: 'Informazioni',
              children: [
                GInfoRow('Azienda', _companyName(c.companyId)),
                GInfoRow('Ruolo', c.role.isNotEmpty ? c.role : '—'),
                GInfoRow('Email', c.email.isNotEmpty ? c.email : '—'),
                GInfoRow('Telefono', c.phone.isNotEmpty ? c.phone : '—'),
              ],
            ),
            if (c.companyId.isEmpty)
              GDetailSection(
                title: 'Azienda',
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: GussoniBrand.surfaceSubtle,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: GussoniBrand.border),
                    ),
                    child: const Row(
                      children: [
                        Icon(
                          Icons.info_outline,
                          size: 14,
                          color: GussoniBrand.textMuted,
                        ),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Contatto senza azienda. Puoi collegarlo a un\'azienda modificandolo.',
                            style: TextStyle(
                              fontSize: 12,
                              color: GussoniBrand.textSecondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
          ],
        );

        // ── Mobile ─────────────────────────────────────────────────────────────
        if (isMobile) {
          return GMobileNavWrapper(
            showDetail: _selected != null,
            list: listPane,
            detail: _selected == null
                ? const SizedBox.shrink()
                : Column(
                    children: [
                      GMobileBackBar(
                        backLabel: 'Contatti',
                        title: _selected!.name,
                        onBack: () => setState(() => _selected = null),
                        action: widget.onEditContact != null
                            ? IconButton(
                                onPressed: () =>
                                    widget.onEditContact!(_selected!),
                                icon: Icon(
                                  Icons.edit_outlined,
                                  size: 18,
                                  color: GussoniBrand.primary,
                                ),
                              )
                            : null,
                      ),
                      Expanded(child: detailPanel(_selected!)),
                    ],
                  ),
          );
        }

        // ── Desktop ────────────────────────────────────────────────────────────
        return Row(
          children: [
            Expanded(flex: _selected != null ? 6 : 10, child: listPane),
            if (_selected != null) ...[
              const VerticalDivider(width: 1),
              Expanded(flex: 4, child: detailPanel(_selected!)),
            ],
          ],
        );
      },
    );
  }

  Future<void> _deleteContact(CompanyContact contact) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => NexoraConfirmDialog(
        title: 'Elimina contatto?',
        icon: Icons.delete_outline_rounded,
        message: 'Eliminare "${contact.name}"?',
        confirmLabel: 'Elimina',
        isDanger: true,
      ),
    );
    if (confirmed != true) return;
    await widget.repository.deleteCompanyContact(widget.userId, contact.id);
    if (mounted && _selected?.id == contact.id) {
      setState(() => _selected = null);
    }
  }
}
