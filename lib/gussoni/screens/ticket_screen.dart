import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../app/nexora_dialog.dart';
import '../../brand_config.dart';
import '../../data/api_workspace_repository.dart';
import '../../models/domain_models.dart';
import '../widgets/g_table.dart';

class TicketGussoniScreen extends StatefulWidget {
  const TicketGussoniScreen({
    super.key,
    required this.workspace,
    required this.userId,
    required this.repository,
    this.onCreateTicket,
    this.onOpenTicket,
  });
  final WorkspaceSnapshot workspace;
  final String userId;
  final ApiWorkspaceRepository repository;
  final VoidCallback? onCreateTicket;
  final void Function(Ticket)? onOpenTicket;

  @override
  State<TicketGussoniScreen> createState() => _TicketGussoniScreenState();
}

class _TicketGussoniScreenState extends State<TicketGussoniScreen> {
  TicketStatus? _statusFilter;
  String _search = '';
  Ticket? _selected;

  List<Ticket> get _filtered =>
      widget.workspace.tickets
          .where(
            (t) =>
                (_statusFilter == null || t.status == _statusFilter) &&
                (_search.isEmpty ||
                    t.title.toLowerCase().contains(_search.toLowerCase()) ||
                    _companyName(
                      t.companyId,
                    ).toLowerCase().contains(_search.toLowerCase())),
          )
          .toList()
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

  String _companyName(String id) =>
      widget.workspace.companies.where((c) => c.id == id).firstOrNull?.name ??
      '—';

  @override
  Widget build(BuildContext context) {
    final cols = <GCol<Ticket>>[
      GCol(
        label: 'Oggetto',
        flex: 4,
        cell: (t) => GCellText(t.title, bold: true),
      ),
      GCol(
        label: 'Cliente',
        flex: 3,
        cell: (t) => GCellText(_companyName(t.companyId), muted: true),
      ),
      GCol(
        label: 'Messaggi',
        flex: 1,
        cell: (t) => t.entries.isNotEmpty
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.chat_bubble_outline,
                    size: 12,
                    color: GussoniBrand.textMuted,
                  ),
                  const SizedBox(width: 4),
                  GCellText('${t.entries.length}'),
                ],
              )
            : GCellText('—', muted: true),
      ),
      GCol(
        label: 'Aggiornato',
        flex: 2,
        cell: (t) => GCellText(
          DateFormat('dd/MM/yy HH:mm').format(t.updatedAt),
          muted: true,
        ),
      ),
      GCol(
        label: 'Stato',
        flex: 2,
        cell: (t) => GStatusChip(
          label: _statusLabel(t.status),
          color: _statusColor(t.status),
          small: true,
        ),
      ),
    ];

    final listPane = GScreenLayout(
      title: 'Ticket',
      count: _filtered.length,
      contextActions: () => [
        if (widget.onCreateTicket != null)
          GContextMenuAction(
            label: 'Nuovo ticket',
            icon: Icons.add_rounded,
            onSelected: widget.onCreateTicket!,
          ),
      ],
      action: FilledButton.icon(
        onPressed: widget.onCreateTicket,
        icon: const Icon(Icons.add, size: 16),
        label: const Text('Nuovo ticket'),
      ),
      filters: GFilterPills<TicketStatus?>(
        items: const [
          null,
          TicketStatus.newTicket,
          TicketStatus.open,
          TicketStatus.waitingCustomer,
          TicketStatus.closed,
        ],
        selected: _statusFilter,
        onSelect: (s) => setState(() {
          _statusFilter = s;
          _selected = null;
        }),
        labelOf: (s) => s == null ? 'Tutti' : _statusLabel(s),
        countOf: (s) => s == null
            ? widget.workspace.tickets.length
            : widget.workspace.tickets.where((t) => t.status == s).length,
      ),
      searchHint: 'Cerca ticket…',
      onSearch: (v) => setState(() {
        _search = v;
        _selected = null;
      }),
      body: GTable<Ticket>(
        columns: cols,
        rows: _filtered,
        isSelected: (t) => _selected?.id == t.id,
        onRowTap: (t) => setState(() => _selected = t),
        contextActionsForRow: (t) => [
          GContextMenuAction(
            label: 'Apri dettaglio',
            icon: Icons.open_in_new_rounded,
            onSelected: () => setState(() => _selected = t),
          ),
          if (widget.onOpenTicket != null)
            GContextMenuAction(
              label: 'Apri thread',
              icon: Icons.forum_outlined,
              onSelected: () => widget.onOpenTicket!(t),
            ),
          GContextMenuAction(
            label: 'Elimina',
            icon: Icons.delete_outline_rounded,
            destructive: true,
            onSelected: () => _deleteTicket(t),
          ),
        ],
        emptyLabel: 'Nessun ticket trovato.',
        emptyIcon: Icons.support_agent_outlined,
      ),
    );

    Widget detailPanel(Ticket ticket) => GDetailPanel(
      title: ticket.title,
      subtitle: _companyName(ticket.companyId),
      icon: Icon(
        Icons.support_agent_outlined,
        size: 18,
        color: _statusColor(ticket.status),
      ),
      onClose: () => setState(() => _selected = null),
      actions: [
        if (widget.onOpenTicket != null)
          IconButton(
            onPressed: () => widget.onOpenTicket!(ticket),
            icon: Icon(
              Icons.open_in_new,
              size: 16,
              color: GussoniBrand.textMuted,
            ),
            tooltip: 'Apri thread',
          ),
      ],
      children: [
        GDetailSection(
          title: 'Info ticket',
          children: [
            GInfoRow('Cliente', _companyName(ticket.companyId)),
            GInfoRow(
              'Stato',
              _statusLabel(ticket.status),
              valueColor: _statusColor(ticket.status),
            ),
            GInfoRow(
              'Creato il',
              DateFormat('dd/MM/yyyy HH:mm').format(ticket.createdAt),
            ),
            GInfoRow(
              'Aggiornato',
              DateFormat('dd/MM/yyyy HH:mm').format(ticket.updatedAt),
            ),
            GInfoRow('Messaggi', '${ticket.entries.length}'),
          ],
        ),
        if (ticket.entries.isNotEmpty)
          GDetailSection(
            title: 'Ultimo messaggio',
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: GussoniBrand.surfaceSubtle,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        GCellText(ticket.entries.last.authorName, bold: true),
                        const Spacer(),
                        GCellText(
                          DateFormat(
                            'dd/MM/yy',
                          ).format(ticket.entries.last.createdAt),
                          muted: true,
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      ticket.entries.last.body,
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: GussoniBrand.textSecondary,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
      ],
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < 760;
        if (isMobile) {
          return GMobileNavWrapper(
            showDetail: _selected != null,
            list: listPane,
            detail: _selected == null
                ? const SizedBox.shrink()
                : Column(
                    children: [
                      GMobileBackBar(
                        backLabel: 'Ticket',
                        title: _selected!.title,
                        onBack: () => setState(() => _selected = null),
                      ),
                      Expanded(child: detailPanel(_selected!)),
                    ],
                  ),
          );
        }

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

  static String _statusLabel(TicketStatus s) => switch (s) {
    TicketStatus.newTicket => 'Nuovo',
    TicketStatus.open => 'Aperto',
    TicketStatus.waitingCustomer => 'In attesa',
    TicketStatus.closed => 'Chiuso',
  };

  static Color _statusColor(TicketStatus s) => switch (s) {
    TicketStatus.newTicket => GussoniBrand.info,
    TicketStatus.open => GussoniBrand.warning,
    TicketStatus.waitingCustomer => GussoniBrand.gold,
    TicketStatus.closed => GussoniBrand.textMuted,
  };

  Future<void> _deleteTicket(Ticket ticket) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => NexoraConfirmDialog(
        title: 'Elimina ticket?',
        icon: Icons.delete_outline_rounded,
        message: 'Eliminare "${ticket.title}"?',
        confirmLabel: 'Elimina',
        isDanger: true,
      ),
    );
    if (confirmed != true) return;
    await widget.repository.deleteTicket(widget.userId, ticket.id);
    if (mounted && _selected?.id == ticket.id) {
      setState(() => _selected = null);
    }
  }
}
