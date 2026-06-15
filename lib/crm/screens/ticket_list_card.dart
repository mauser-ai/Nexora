import '../../brand_config.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/domain_models.dart';
import '../../data/firestore_workspace_repository.dart';
import 'tl_table.dart';

class TicketListCard extends StatefulWidget {
  const TicketListCard({
    super.key,
    required this.workspace,
    required this.onCreateTicket,
    required this.onOpenTicket,
    required this.onDeleteTicket,
  });

  final WorkspaceSnapshot workspace;
  final VoidCallback onCreateTicket;
  final Future<void> Function(Ticket) onOpenTicket;
  final Future<void> Function(String) onDeleteTicket;

  @override
  State<TicketListCard> createState() => _TicketListCardState();
}

class _TicketListCardState extends State<TicketListCard> {
  String? _statusFilter;
  final _dateFmt = DateFormat('dd/MM/yyyy HH:mm');

  static const _statusFilters = [
    TlStatusFilter(label: 'Nuovo', value: 'newTicket', color: Color(0xFF0369A1)),
    TlStatusFilter(label: 'Aperto', value: 'open', color: Color(0xFF034F3B)),
    TlStatusFilter(label: 'In attesa', value: 'waitingCustomer', color: Color(0xFFD97706)),
    TlStatusFilter(label: 'Chiuso', value: 'closed', color: Color(0xFF7D89A8)),
  ];

  Color _statusColor(TicketStatus s) {
    switch (s) {
      case TicketStatus.newTicket: return const Color(0xFF0369A1);
      case TicketStatus.open: return GussoniBrand.primary;
      case TicketStatus.waitingCustomer: return const Color(0xFFD97706);
      case TicketStatus.closed: return const Color(0xFF7D89A8);
    }
  }

  String _statusLabel(TicketStatus s) {
    switch (s) {
      case TicketStatus.newTicket: return 'Nuovo';
      case TicketStatus.open: return 'Aperto';
      case TicketStatus.waitingCustomer: return 'In attesa';
      case TicketStatus.closed: return 'Chiuso';
    }
  }

  String _companyName(Ticket t) =>
      widget.workspace.companies.where((c) => c.id == t.companyId).firstOrNull?.name ?? '—';

  String _lastMessage(Ticket t) {
    if (t.entries.isEmpty) return '—';
    final last = t.entries.last;
    final body = last.body.replaceAll('\n', ' ').trim();
    return body.length > 60 ? '${body.substring(0, 60)}…' : body;
  }

  List<TlRow> get _rows {
    var tickets = widget.workspace.tickets;
    if (_statusFilter != null) {
      final s = TicketStatus.values.firstWhere((v) => v.name == _statusFilter, orElse: () => TicketStatus.newTicket);
      tickets = tickets.where((t) => t.status == s).toList();
    }
    return tickets.map((t) => TlRow(
      key: t.id,
      onTap: () => widget.onOpenTicket(t),
      cells: [
        TlCell(widget: TlPrimaryCell(text: t.title, sub: _lastMessage(t))),
        TlCell(text: _companyName(t)),
        TlCell(text: t.recipientEmail),
        TlCell(widget: TlBadge(label: _statusLabel(t.status), color: _statusColor(t.status))),
        TlCell(widget: Row(children: [
          const Icon(Icons.chat_bubble_outline, size: 13, color: Color(0xFF525D78)),
          const SizedBox(width: 4),
          Text('${t.entries.length}', style: const TextStyle(fontSize: 13, color: Color(0xFFB8C0D8))),
        ])),
        TlCell(text: _dateFmt.format(t.updatedAt)),
        TlCell(widget: TlRowActions(items: [
          PopupMenuItem(value: 'open', child: const Text('Apri'), onTap: () => widget.onOpenTicket(t)),
          const PopupMenuDivider(),
          PopupMenuItem(value: 'delete', child: const Text('Elimina', style: TextStyle(color: Color(0xFFB91C1C))), onTap: () => widget.onDeleteTicket(t.id)),
        ])),
      ],
    )).toList();
  }

  @override
  Widget build(BuildContext context) {
    return TlTable(
      searchHint: 'Cerca ticket...',
      columns: const [
        TlColumn(label: 'Oggetto', flex: 3),
        TlColumn(label: 'Azienda', flex: 2),
        TlColumn(label: 'Email', flex: 2),
        TlColumn(label: 'Stato', flex: 1),
        TlColumn(label: 'Messaggi', flex: 1),
        TlColumn(label: 'Ultimo aggiornamento', flex: 2),
        TlColumn(label: '', minWidth: 40),
      ],
      rows: _rows,
      statusFilters: _statusFilters,
      selectedStatus: _statusFilter,
      onStatusChanged: (v) => setState(() => _statusFilter = v),
      onAdd: widget.onCreateTicket,
      addLabel: 'Nuovo ticket',
      emptyMessage: 'Nessun ticket trovato.',
    );
  }
}
