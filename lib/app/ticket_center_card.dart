import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../data/firestore_workspace_repository.dart';
import '../models/domain_models.dart';
import '../services/ticket_mail_service.dart';

class TicketCenterCard extends StatefulWidget {
  const TicketCenterCard({
    super.key,
    required this.workspace,
    required this.currentUserName,
    required this.onCreateContact,
    required this.onUpdateContact,
    required this.onDeleteContact,
    required this.onCreateTicket,
    required this.onUpdateTicket,
    required this.onDeleteTicket,
    required this.emailSignatureHtml,
  });

  final WorkspaceSnapshot workspace;
  final String currentUserName;
  final Future<void> Function(CompanyContact contact) onCreateContact;
  final Future<void> Function(CompanyContact contact) onUpdateContact;
  final Future<void> Function(String contactId) onDeleteContact;
  final Future<void> Function(Ticket ticket) onCreateTicket;
  final Future<void> Function(Ticket ticket) onUpdateTicket;
  final Future<void> Function(String ticketId) onDeleteTicket;
  final String emailSignatureHtml;

  @override
  State<TicketCenterCard> createState() => _TicketCenterCardState();
}

class _TicketCenterCardState extends State<TicketCenterCard> {
  final TicketMailService _mailService = TicketMailService();

  String? _openedTicketId;
  String? _editorTicketId;

  final _emailBodyController = TextEditingController();
  final _ticketSubjectController = TextEditingController();
  final _ticketRecipientController = TextEditingController();
  final _ticketSearchController = TextEditingController();

  TicketStatus _ticketStatusEditor = TicketStatus.newTicket;
  final List<String> _pendingAttachmentPaths = [];
  bool _publicReplyMode = true;

  bool _submittingComposer = false;
  bool _savingMeta = false;
  bool _syncingInbound = false;
  TicketStatus? _ticketFilterStatus;
  String? _ticketFilterClient;
  int _ticketPage = 0;
  static const int _ticketPageSize = 10;
  static final RegExp _ticketRefRegex = RegExp(
    r'#ticket-([A-Za-z0-9_-]+)',
    caseSensitive: false,
  );
  static const Set<String> _selfAliases = {
    'mbroggini37@gmail.com',
    'info@matteobroggini.it',
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _syncInboundEmails();
      }
    });
  }

  @override
  void dispose() {
    _emailBodyController.dispose();
    _ticketSubjectController.dispose();
    _ticketRecipientController.dispose();
    _ticketSearchController.dispose();
    super.dispose();
  }

  Ticket? get _openedTicket {
    if (_openedTicketId == null) {
      return null;
    }
    for (final ticket in widget.workspace.tickets) {
      if (ticket.id == _openedTicketId) {
        return ticket;
      }
    }
    return null;
  }

  Company? _companyById(String id) {
    for (final company in widget.workspace.companies) {
      if (company.id == id) {
        return company;
      }
    }
    return null;
  }

  String _normalizeSubject(String value) {
    var next = value.trim().toLowerCase();
    next = _stripTicketRef(next);
    next = next.replaceAll(RegExp(r'^(re|fw|fwd)\s*:\s*'), '');
    next = next.replaceAll(RegExp(r'\s+'), ' ');
    return next;
  }

  String _ticketRef(Ticket ticket) => '#ticket-${ticket.id}';

  String _stripTicketRef(String value) {
    var next = value.replaceAll(_ticketRefRegex, '').trim();
    next = next.replaceAll(RegExp(r'^\[\s*]'), '');
    next = next.replaceAll(RegExp(r'\s{2,}'), ' ');
    next = next.replaceAll(RegExp(r'^\s*[-:|]\s*'), '');
    return next.trim();
  }

  String? _extractTicketIdFromSubject(String value) {
    final match = _ticketRefRegex.firstMatch(value);
    if (match == null) {
      return null;
    }
    return (match.group(1) ?? '').trim();
  }

  String _withTicketRefInSubject(Ticket ticket, String subject) {
    final clean = _stripTicketRef(subject);
    final ref = _ticketRef(ticket);
    if (clean.isEmpty) {
      return ref;
    }
    return '$clean [$ref]';
  }

  String _displayTicketBody(String raw) {
    var text = raw.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    text = text.replaceAll(
      RegExp(
        r'\n---\s*Messaggio inviato da G-Flux.*$',
        caseSensitive: false,
        dotAll: true,
      ),
      '',
    );
    text = text.replaceAll(
      RegExp(
        r'Messaggio inviato da G-Flux.*$',
        caseSensitive: false,
        dotAll: true,
      ),
      '',
    );
    final lines = text.split('\n');
    final cleaned = <String>[];
    for (final line in lines) {
      final trimmed = line.trim();
      if (RegExp(
        r'^(Il giorno|On)\b.*\b(ha scritto:|wrote:)$',
        caseSensitive: false,
      ).hasMatch(trimmed)) {
        break;
      }
      if (trimmed.startsWith('>')) {
        continue;
      }
      if (trimmed == '--' || trimmed == '__') {
        break;
      }
      if (RegExp(r'^Inviato da', caseSensitive: false).hasMatch(trimmed)) {
        break;
      }
      cleaned.add(line);
    }
    final compact = cleaned.join('\n').replaceAll(RegExp(r'\n{3,}'), '\n\n');
    return compact.trim();
  }

  bool _isSelfIdentity(String raw) {
    final normalized = raw.trim().toLowerCase();
    if (normalized.isEmpty) {
      return false;
    }
    final currentUser = widget.currentUserName.trim().toLowerCase();
    if (currentUser.isNotEmpty && normalized == currentUser) {
      return true;
    }
    return _selfAliases.contains(normalized);
  }

  String _entryDisplayAuthor(TicketEntry entry) {
    if (entry.type == TicketEntryType.outboundEmail) {
      return 'Io';
    }
    if (_isSelfIdentity(entry.authorName) ||
        _isSelfIdentity(entry.recipientEmail)) {
      return 'Io';
    }
    final author = entry.authorName.trim();
    if (author.isEmpty) {
      return 'Sconosciuto';
    }
    return author;
  }

  String _statusLabel(TicketStatus status) {
    switch (status) {
      case TicketStatus.newTicket:
        return 'Nuovo';
      case TicketStatus.open:
        return 'Aperto';
      case TicketStatus.waitingCustomer:
        return 'In attesa del cliente';
      case TicketStatus.closed:
        return 'Chiuso';
    }
  }

  Color _statusColor(TicketStatus status) {
    switch (status) {
      case TicketStatus.newTicket:
        return const Color(0xFF0EA5E9);
      case TicketStatus.open:
        return const Color(0xFF16A34A);
      case TicketStatus.waitingCustomer:
        return const Color(0xFFCA8A04);
      case TicketStatus.closed:
        return const Color(0xFF8C8478);
    }
  }

  void _openTicket(Ticket ticket) {
    setState(() {
      _openedTicketId = ticket.id;
      _syncEditorsWithTicket(ticket, force: true);
    });
  }

  void _syncEditorsWithTicket(Ticket ticket, {bool force = false}) {
    if (!force && _editorTicketId == ticket.id) {
      return;
    }
    _editorTicketId = ticket.id;
    _ticketSubjectController.text = ticket.title;
    _ticketRecipientController.text = ticket.recipientEmail;
    _emailBodyController.clear();
    _ticketStatusEditor = ticket.status;
    _pendingAttachmentPaths.clear();
  }

  Future<void> _openContactsDialog() async {
    await showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 860, maxHeight: 640),
          child: _ContactsManagerDialog(
            companies: widget.workspace.companies,
            contacts: widget.workspace.companyContacts,
            onCreate: widget.onCreateContact,
            onUpdate: widget.onUpdateContact,
            onDelete: widget.onDeleteContact,
          ),
        ),
      ),
    );
  }

  Future<void> _openCreateTicketDialog() async {
    if (widget.workspace.companies.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Crea prima almeno un azienda.')),
      );
      return;
    }

    String selectedCompanyId = widget.workspace.companies.first.id;
    String? selectedRecipient;
    final subjectController = TextEditingController();

    List<String> recipientOptions(String companyId) {
      final company = _companyById(companyId);
      final out = <String>[];
      if (company != null && company.email.trim().isNotEmpty) {
        out.add(company.email.trim());
      }
      final contacts = widget.workspace.companyContacts
          .where((item) => item.companyId == companyId)
          .map((item) => item.email.trim())
          .where((item) => item.isNotEmpty);
      for (final email in contacts) {
        if (!out.contains(email)) {
          out.add(email);
        }
      }
      return out;
    }

    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          final recipients = recipientOptions(selectedCompanyId);
          selectedRecipient ??= recipients.isNotEmpty ? recipients.first : null;
          if (selectedRecipient != null &&
              !recipients.contains(selectedRecipient)) {
            selectedRecipient = recipients.isNotEmpty ? recipients.first : null;
          }
          return AlertDialog(
            title: const Text('Nuovo ticket'),
            content: SizedBox(
              width: 560,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: selectedCompanyId,
                    decoration: const InputDecoration(
                      labelText: 'Azienda',
                      border: OutlineInputBorder(),
                    ),
                    items: widget.workspace.companies
                        .map(
                          (company) => DropdownMenuItem(
                            value: company.id,
                            child: Text(company.name),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value == null) {
                        return;
                      }
                      setModalState(() {
                        selectedCompanyId = value;
                        selectedRecipient = null;
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: selectedRecipient,
                    decoration: const InputDecoration(
                      labelText: 'Destinatario',
                      border: OutlineInputBorder(),
                    ),
                    items: recipients
                        .map(
                          (email) => DropdownMenuItem(
                            value: email,
                            child: Text(email),
                          ),
                        )
                        .toList(),
                    onChanged: (value) =>
                        setModalState(() => selectedRecipient = value),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: subjectController,
                    decoration: const InputDecoration(
                      labelText: 'Oggetto ticket / mail',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Annulla'),
              ),
              FilledButton(
                onPressed: () async {
                  final subject = subjectController.text.trim();
                  final recipient = selectedRecipient?.trim() ?? '';
                  if (subject.isEmpty || recipient.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Compila oggetto e destinatario.'),
                      ),
                    );
                    return;
                  }

                  final now = DateTime.now();
                  final ticket = Ticket(
                    id: 'tkt-${now.microsecondsSinceEpoch}',
                    companyId: selectedCompanyId,
                    title: subject,
                    recipientEmail: recipient,
                    status: TicketStatus.newTicket,
                    createdAt: now,
                    updatedAt: now,
                    entries: const [],
                  );
                  await widget.onCreateTicket(ticket);

                  if (mounted) {
                    _openTicket(ticket);
                  }
                  if (context.mounted) {
                    Navigator.of(context).pop();
                  }
                },
                child: const Text('Crea ticket'),
              ),
            ],
          );
        },
      ),
    );

    subjectController.dispose();
  }

  Future<void> _pickAndUploadAttachments(Ticket ticket) async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Allegati ticket temporaneamente disattivati.'),
      ),
    );
  }

  Future<void> _saveTicketMeta(Ticket ticket) async {
    final nextSubject = _ticketSubjectController.text.trim();
    final nextRecipient = _ticketRecipientController.text.trim();
    if (nextSubject.isEmpty || nextRecipient.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Oggetto e destinatario sono obbligatori.'),
        ),
      );
      return;
    }

    setState(() => _savingMeta = true);
    try {
      final updated = ticket.copyWith(
        title: nextSubject,
        recipientEmail: nextRecipient,
        status: _ticketStatusEditor,
        updatedAt: DateTime.now(),
      );
      await widget.onUpdateTicket(updated);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Ticket aggiornato.')));
      }
    } finally {
      if (mounted) {
        setState(() => _savingMeta = false);
      }
    }
  }

  Future<void> _submitComposer(Ticket ticket) async {
    final subjectInput = _ticketSubjectController.text.trim();
    final body = _emailBodyController.text.trim();
    final recipient = _ticketRecipientController.text.trim();

    if (body.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Scrivi un contenuto prima di inviare.')),
      );
      return;
    }
    if (_publicReplyMode && (recipient.isEmpty || subjectInput.isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Compila destinatario e oggetto della risposta.'),
        ),
      );
      return;
    }

    setState(() => _submittingComposer = true);
    try {
      if (_publicReplyMode) {
        final effectiveSubject = _withTicketRefInSubject(ticket, subjectInput);
        final footer =
            '\n\n---\n'
            'Messaggio inviato da G-Flux (${_ticketRef(ticket)}).\n'
            'Per favore non modificare l\'oggetto quando rispondi a questa email.';
        final effectiveBody = '$body$footer';
        await _mailService.sendTicketEmail(
          toEmail: recipient,
          subject: effectiveSubject,
          body: effectiveBody,
          attachmentPaths: _pendingAttachmentPaths,
          signatureHtml: widget.emailSignatureHtml,
        );
        final entry = TicketEntry(
          id: 'tentry-${DateTime.now().microsecondsSinceEpoch}',
          type: TicketEntryType.outboundEmail,
          body: body,
          createdAt: DateTime.now(),
          authorName: widget.currentUserName,
          recipientEmail: recipient,
          subject: effectiveSubject,
          attachmentPaths: List<String>.from(_pendingAttachmentPaths),
        );
        await widget.onUpdateTicket(
          ticket.copyWith(
            title: _stripTicketRef(subjectInput),
            recipientEmail: recipient,
            status: TicketStatus.waitingCustomer,
            updatedAt: DateTime.now(),
            entries: [...ticket.entries, entry],
          ),
        );
      } else {
        final entry = TicketEntry(
          id: 'tentry-${DateTime.now().microsecondsSinceEpoch}',
          type: TicketEntryType.internalNote,
          body: body,
          createdAt: DateTime.now(),
          authorName: widget.currentUserName,
        );
        await widget.onUpdateTicket(
          ticket.copyWith(
            updatedAt: DateTime.now(),
            status: _ticketStatusEditor,
            entries: [...ticket.entries, entry],
          ),
        );
      }

      _pendingAttachmentPaths.clear();
      _emailBodyController.clear();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _publicReplyMode
                  ? 'Risposta pubblica inviata.'
                  : 'Nota interna salvata.',
            ),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Errore invio/salvataggio: $error')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _submittingComposer = false);
      }
    }
  }

  String? _resolveCompanyIdBySender(String senderEmail) {
    final normalized = senderEmail.trim().toLowerCase();
    if (normalized.isEmpty) {
      return null;
    }

    for (final contact in widget.workspace.companyContacts) {
      if (contact.email.trim().toLowerCase() == normalized) {
        return contact.companyId;
      }
    }
    for (final company in widget.workspace.companies) {
      if (company.email.trim().toLowerCase() == normalized) {
        return company.id;
      }
    }
    return null;
  }

  String _fallbackContactName(String email) {
    final trimmed = email.trim();
    if (trimmed.isEmpty || !trimmed.contains('@')) {
      return trimmed.isEmpty ? 'Contatto sconosciuto' : trimmed;
    }
    return trimmed.split('@').first;
  }

  Future<List<String>> _storeInboundAttachments(
    InboundTicketEmail inbound, {
    required String companyId,
    required String senderEmail,
  }) async {
    return const [];
  }

  String _ticketLeadLabel(Ticket ticket) {
    final company = _companyById(ticket.companyId);
    if (company != null) {
      return company.name;
    }
    final inbound = ticket.entries.where(
      (entry) => entry.type == TicketEntryType.inboundEmail,
    );
    if (inbound.isNotEmpty) {
      final lastInbound = inbound.last;
      final author = lastInbound.authorName.trim();
      if (author.isNotEmpty) {
        return author;
      }
    }
    return ticket.recipientEmail.trim().isEmpty
        ? 'Contatto sconosciuto'
        : ticket.recipientEmail.trim();
  }

  List<Ticket> _filteredTickets(List<Ticket> tickets) {
    final query = _ticketSearchController.text.trim().toLowerCase();
    return tickets.where((ticket) {
      if (_ticketFilterStatus != null && ticket.status != _ticketFilterStatus) {
        return false;
      }
      final clientLabel = _ticketLeadLabel(ticket);
      if (_ticketFilterClient != null &&
          _ticketFilterClient!.isNotEmpty &&
          clientLabel != _ticketFilterClient) {
        return false;
      }
      if (query.isEmpty) {
        return true;
      }
      final haystack =
          '${ticket.title} ${ticket.recipientEmail} $clientLabel ${_ticketRef(ticket)}'
              .toLowerCase();
      return haystack.contains(query);
    }).toList();
  }

  Ticket? _findExistingTicketForInbound({
    required String? companyId,
    required String senderEmail,
    required String normalizedSubject,
  }) {
    final candidates = widget.workspace.tickets.where((ticket) {
      if (companyId != null &&
          companyId.isNotEmpty &&
          ticket.companyId != companyId) {
        return false;
      }
      final sameSubject =
          _normalizeSubject(ticket.title) == normalizedSubject &&
          normalizedSubject.isNotEmpty;
      if (sameSubject) {
        return true;
      }
      for (final entry in ticket.entries) {
        final entrySubject = _normalizeSubject(entry.subject);
        if (entrySubject.isNotEmpty && entrySubject == normalizedSubject) {
          return true;
        }
        if (entry.recipientEmail.trim().toLowerCase() == senderEmail) {
          return true;
        }
      }
      return ticket.recipientEmail.trim().toLowerCase() == senderEmail;
    }).toList();

    if (candidates.isEmpty) {
      return null;
    }
    candidates.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return candidates.first;
  }

  Future<void> _syncInboundEmails() async {
    setState(() => _syncingInbound = true);
    try {
      final inboundItems = await _mailService.pullInboundEmails();
      if (inboundItems.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Nessuna nuova email in ingresso.')),
          );
        }
        return;
      }

      var created = 0;
      var updated = 0;
      var skipped = 0;

      for (final inbound in inboundItems) {
        final sender = inbound.from.trim().toLowerCase();
        final companyId = _resolveCompanyIdBySender(sender);
        final linkedCompanyId = companyId ?? '';

        final safeSubject = inbound.subject.trim().isEmpty
            ? '(Senza oggetto)'
            : inbound.subject.trim();
        final ticketIdFromSubject = _extractTicketIdFromSubject(safeSubject);
        Ticket? existingByRef;
        if (ticketIdFromSubject != null && ticketIdFromSubject.isNotEmpty) {
          for (final ticket in widget.workspace.tickets) {
            if (ticket.id == ticketIdFromSubject) {
              existingByRef = ticket;
              break;
            }
          }
        }
        final normalizedInboundSubject = _normalizeSubject(safeSubject);

        final existing =
            existingByRef ??
            _findExistingTicketForInbound(
              companyId: companyId,
              senderEmail: sender,
              normalizedSubject: normalizedInboundSubject,
            );

        final inboundEntry = TicketEntry(
          id: 'tentry-${DateTime.now().microsecondsSinceEpoch}-${created + updated}',
          type: TicketEntryType.inboundEmail,
          body: inbound.body,
          createdAt: inbound.receivedAt,
          authorName: inbound.fromName.isNotEmpty ? inbound.fromName : sender,
          recipientEmail: sender,
          subject: safeSubject,
          attachmentPaths: await _storeInboundAttachments(
            inbound,
            companyId: linkedCompanyId,
            senderEmail: sender,
          ),
        );

        if (existing == null) {
          final now = DateTime.now();
          final ticket = Ticket(
            id: 'tkt-${now.microsecondsSinceEpoch}-${created + updated}',
            companyId: linkedCompanyId,
            title: _stripTicketRef(safeSubject),
            recipientEmail: sender,
            status: TicketStatus.newTicket,
            createdAt: inbound.receivedAt,
            updatedAt: inbound.receivedAt,
            entries: [inboundEntry],
          );
          await widget.onCreateTicket(ticket);
          final knownContact = widget.workspace.companyContacts.any(
            (contact) => contact.email.trim().toLowerCase() == sender,
          );
          if (!knownContact) {
            final newContact = CompanyContact(
              id: 'cc-${DateTime.now().microsecondsSinceEpoch}-${created + updated}',
              companyId: linkedCompanyId,
              name: inbound.fromName.isNotEmpty
                  ? inbound.fromName
                  : _fallbackContactName(sender),
              email: sender,
              phone: '',
              role: '',
            );
            await widget.onCreateContact(newContact);
          }
          created += 1;
        } else {
          await widget.onUpdateTicket(
            existing.copyWith(
              status: TicketStatus.newTicket,
              updatedAt: inbound.receivedAt,
              entries: [...existing.entries, inboundEntry],
            ),
          );
          updated += 1;
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Inbox sincronizzata: $created nuovi, $updated aggiornati, $skipped ignorati.',
            ),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Errore sincronizzazione inbound: $error')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _syncingInbound = false);
      }
    }
  }

  Widget _buildEntryBubble(TicketEntry entry) {
    final isInternal = entry.type == TicketEntryType.internalNote;
    final isOutbound = entry.type == TicketEntryType.outboundEmail;

    final align = isOutbound
        ? Alignment.centerRight
        : isInternal
        ? Alignment.center
        : Alignment.centerLeft;

    final bgColor = isOutbound
        ? const Color(0xFFE6F4EF)
        : isInternal
        ? const Color(0xFFF6F4F1)
        : const Color(0xFFFFFFFF);

    final borderColor = isOutbound
        ? const Color(0xFF5B1205).withValues(alpha: 0.30)
        : isInternal
        ? const Color(0xFFE9E5DF)
        : const Color(0xFFE9E5DF);

    final label = switch (entry.type) {
      TicketEntryType.internalNote => 'Nota interna',
      TicketEntryType.outboundEmail => 'Tu → Cliente',
      TicketEntryType.inboundEmail => 'Cliente → Tu',
    };
    final displayBody = _displayTicketBody(entry.body);

    return Align(
      alignment: align,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: borderColor),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      label,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1C1D1F),
                      ),
                    ),
                  ),
                  Text(
                    DateFormat('dd/MM/yyyy HH:mm').format(entry.createdAt),
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF8C8478),
                    ),
                  ),
                ],
              ),
              if (entry.subject.trim().isNotEmpty &&
                  _extractTicketIdFromSubject(entry.subject) != null) ...[
                const SizedBox(height: 2),
                Text(
                  _extractTicketIdFromSubject(entry.subject) != null
                      ? '#ticket-${_extractTicketIdFromSubject(entry.subject)}'
                      : '',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF5B1205),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
              if (entry.authorName.trim().isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  _entryDisplayAuthor(entry),
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF8C8478),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              if (entry.subject.trim().isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  'Oggetto: ${entry.subject}',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF54595F),
                  ),
                ),
              ],
              const SizedBox(height: 6),
              Text(displayBody.isEmpty ? '...' : displayBody),
              if (entry.attachmentPaths.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  'Allegati: ${entry.attachmentPaths.join(', ')}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF8C8478),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTicketListPage() {
    final tickets = widget.workspace.tickets;
    final filtered = _filteredTickets(tickets);
    final maxPage = filtered.isEmpty
        ? 0
        : ((filtered.length - 1) ~/ _ticketPageSize);
    if (_ticketPage > maxPage) {
      _ticketPage = maxPage;
    }
    final start = (_ticketPage * _ticketPageSize).clamp(0, filtered.length);
    final end = (start + _ticketPageSize).clamp(0, filtered.length);
    final pageItems = filtered.sublist(start, end);
    final clientOptions = tickets.map(_ticketLeadLabel).toSet().toList()
      ..sort();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Ticket',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
              ),
            ),
            OutlinedButton.icon(
              onPressed: _openContactsDialog,
              icon: const Icon(Icons.contacts_outlined),
              label: const Text('Contatti'),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: _syncingInbound ? null : _syncInboundEmails,
              icon: const Icon(Icons.mark_email_unread_outlined),
              label: const Text('Sincronizza mail in arrivo'),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: _openCreateTicketDialog,
              icon: const Icon(Icons.add),
              label: const Text('Nuovo ticket'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            SizedBox(
              width: 260,
              child: TextField(
                controller: _ticketSearchController,
                onChanged: (_) => setState(() => _ticketPage = 0),
                decoration: const InputDecoration(
                  labelText: 'Filtra per oggetto',
                  border: OutlineInputBorder(),
                  isDense: true,
                  prefixIcon: Icon(Icons.search),
                ),
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: 210,
              child: DropdownButtonFormField<TicketStatus?>(
                initialValue: _ticketFilterStatus,
                decoration: const InputDecoration(
                  labelText: 'Stato',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: [
                  const DropdownMenuItem<TicketStatus?>(
                    value: null,
                    child: Text('Tutti'),
                  ),
                  ...TicketStatus.values.map(
                    (status) => DropdownMenuItem<TicketStatus?>(
                      value: status,
                      child: Text(_statusLabel(status)),
                    ),
                  ),
                ],
                onChanged: (value) => setState(() {
                  _ticketFilterStatus = value;
                  _ticketPage = 0;
                }),
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: 260,
              child: DropdownButtonFormField<String?>(
                initialValue: _ticketFilterClient,
                decoration: const InputDecoration(
                  labelText: 'Cliente',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('Tutti'),
                  ),
                  ...clientOptions.map(
                    (item) => DropdownMenuItem<String?>(
                      value: item,
                      child: Text(item, overflow: TextOverflow.ellipsis),
                    ),
                  ),
                ],
                onChanged: (value) => setState(() {
                  _ticketFilterClient = value;
                  _ticketPage = 0;
                }),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFFFFFFFF),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFE9E5DF)),
            ),
            child: filtered.isEmpty
                ? const Center(
                    child: Text('Nessun ticket trovato con i filtri.'),
                  )
                : Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        decoration: const BoxDecoration(
                          border: Border(
                            bottom: BorderSide(color: Color(0xFFE9E5DF)),
                          ),
                        ),
                        child: const Row(
                          children: [
                            Expanded(flex: 3, child: Text('Oggetto')),
                            Expanded(flex: 2, child: Text('Cliente')),
                            Expanded(flex: 2, child: Text('Destinatario')),
                            Expanded(child: Text('Stato')),
                            Expanded(child: Text('Aggiornato')),
                            SizedBox(width: 86, child: Text('Azione')),
                          ],
                        ),
                      ),
                      Expanded(
                        child: ListView.separated(
                          itemCount: pageItems.length,
                          separatorBuilder: (_, _) => const Divider(
                            height: 1,
                            color: Color(0xFFE9E5DF),
                          ),
                          itemBuilder: (context, index) {
                            final ticket = pageItems[index];
                            return InkWell(
                              onTap: () => _openTicket(ticket),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 10,
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      flex: 3,
                                      child: Text(
                                        '${ticket.title}\n${_ticketRef(ticket)}',
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      flex: 2,
                                      child: Text(
                                        _ticketLeadLabel(ticket),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    Expanded(
                                      flex: 2,
                                      child: Text(
                                        ticket.recipientEmail,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    Expanded(
                                      child: Text(
                                        _statusLabel(ticket.status),
                                        style: TextStyle(
                                          color: _statusColor(ticket.status),
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      child: Text(
                                        DateFormat(
                                          'dd/MM HH:mm',
                                        ).format(ticket.updatedAt),
                                      ),
                                    ),
                                    SizedBox(
                                      width: 86,
                                      child: OutlinedButton(
                                        onPressed: () => _openTicket(ticket),
                                        child: const Text('Apri'),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        decoration: const BoxDecoration(
                          border: Border(
                            top: BorderSide(color: Color(0xFFE9E5DF)),
                          ),
                        ),
                        child: Row(
                          children: [
                            Text(
                              '${start + 1}-$end di ${filtered.length}',
                              style: const TextStyle(color: Color(0xFF8C8478)),
                            ),
                            const Spacer(),
                            IconButton(
                              onPressed: _ticketPage > 0
                                  ? () => setState(() => _ticketPage -= 1)
                                  : null,
                              icon: const Icon(Icons.chevron_left),
                            ),
                            Text('${_ticketPage + 1}/${maxPage + 1}'),
                            IconButton(
                              onPressed: _ticketPage < maxPage
                                  ? () => setState(() => _ticketPage += 1)
                                  : null,
                              icon: const Icon(Icons.chevron_right),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildTicketDetailPage(Ticket ticket) {
    _syncEditorsWithTicket(ticket);
    final company = _companyById(ticket.companyId);
    final contactName = _ticketLeadLabel(ticket);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            TextButton.icon(
              onPressed: () {
                setState(() {
                  _openedTicketId = null;
                  _editorTicketId = null;
                });
              },
              icon: const Icon(Icons.arrow_back),
              label: const Text('Torna al listing'),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: _statusColor(ticket.status).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: _statusColor(ticket.status)),
              ),
              child: Text(
                _statusLabel(ticket.status),
                style: TextStyle(
                  color: _statusColor(ticket.status),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: () async {
                await widget.onDeleteTicket(ticket.id);
                if (mounted) {
                  setState(() {
                    _openedTicketId = null;
                    _editorTicketId = null;
                  });
                }
              },
              icon: const Icon(Icons.delete_outline),
              label: const Text('Elimina ticket'),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Expanded(
          child: Column(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFFFFF),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFE9E5DF)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _ticketRef(ticket),
                            style: const TextStyle(
                              color: Color(0xFF5B1205),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 6),
                          TextField(
                            controller: _ticketSubjectController,
                            decoration: const InputDecoration(
                              labelText: 'Oggetto ticket',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'Contatto: $contactName',
                                  style: const TextStyle(
                                    color: Color(0xFF54595F),
                                  ),
                                ),
                              ),
                              Expanded(
                                child: Text(
                                  'Società: ${company?.name ?? '-'}',
                                  style: const TextStyle(
                                    color: Color(0xFF54595F),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFFFFF),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFE9E5DF)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          TextField(
                            controller: _ticketRecipientController,
                            decoration: const InputDecoration(
                              labelText: 'Destinatario',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                          ),
                          const SizedBox(height: 10),
                          DropdownButtonFormField<TicketStatus>(
                            initialValue: _ticketStatusEditor,
                            decoration: const InputDecoration(
                              labelText: 'Nuovo stato',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            items: TicketStatus.values
                                .map(
                                  (status) => DropdownMenuItem<TicketStatus>(
                                    value: status,
                                    child: Text(_statusLabel(status)),
                                  ),
                                )
                                .toList(),
                            onChanged: (value) {
                              if (value == null) {
                                return;
                              }
                              setState(() => _ticketStatusEditor = value);
                            },
                          ),
                          const SizedBox(height: 10),
                          Align(
                            alignment: Alignment.centerRight,
                            child: FilledButton.icon(
                              onPressed: _savingMeta
                                  ? null
                                  : () => _saveTicketMeta(ticket),
                              icon: const Icon(Icons.save_outlined),
                              label: const Text('Salva ticket'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFFFFF),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFE9E5DF)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Attività',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
                            ),
                          ),
                        ),
                        SegmentedButton<bool>(
                          segments: const [
                            ButtonSegment<bool>(
                              value: false,
                              label: Text('Nota interna'),
                            ),
                            ButtonSegment<bool>(
                              value: true,
                              label: Text('Risposta pubblica'),
                            ),
                          ],
                          selected: {_publicReplyMode},
                          onSelectionChanged: (next) {
                            if (next.isEmpty) {
                              return;
                            }
                            setState(() => _publicReplyMode = next.first);
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    if (_publicReplyMode) ...[
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Oggetto risposta: ${_ticketSubjectController.text}',
                              style: const TextStyle(
                                color: Color(0xFF8C8478),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          OutlinedButton.icon(
                            onPressed: () => _pickAndUploadAttachments(ticket),
                            icon: const Icon(Icons.attach_file),
                            label: const Text('Allegati'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                    ],
                    TextField(
                      controller: _emailBodyController,
                      minLines: 3,
                      maxLines: 6,
                      decoration: InputDecoration(
                        labelText: _publicReplyMode
                            ? 'Nuova risposta...'
                            : 'Nuova nota interna...',
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    if (_pendingAttachmentPaths.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        '${_pendingAttachmentPaths.length} allegati pronti in ALLEGATI',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF8C8478),
                        ),
                      ),
                    ],
                    const SizedBox(height: 10),
                    Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton.icon(
                        onPressed: _submittingComposer
                            ? null
                            : () => _submitComposer(ticket),
                        icon: Icon(
                          _publicReplyMode
                              ? Icons.send_outlined
                              : Icons.note_add_outlined,
                        ),
                        label: Text(
                          _publicReplyMode
                              ? 'Invia risposta'
                              : 'Salva nota interna',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFFFFF),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFE9E5DF)),
                  ),
                  child: ListView(
                    padding: const EdgeInsets.all(12),
                    children: ticket.entries.isEmpty
                        ? const [
                            Padding(
                              padding: EdgeInsets.all(20),
                              child: Text('Nessuna conversazione sul ticket.'),
                            ),
                          ]
                        : ticket.entries.map(_buildEntryBubble).toList(),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final openedTicket = _openedTicket;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: openedTicket == null
            ? _buildTicketListPage()
            : _buildTicketDetailPage(openedTicket),
      ),
    );
  }
}

class _ContactsManagerDialog extends StatelessWidget {
  const _ContactsManagerDialog({
    required this.companies,
    required this.contacts,
    required this.onCreate,
    required this.onUpdate,
    required this.onDelete,
  });

  final List<Company> companies;
  final List<CompanyContact> contacts;
  final Future<void> Function(CompanyContact contact) onCreate;
  final Future<void> Function(CompanyContact contact) onUpdate;
  final Future<void> Function(String contactId) onDelete;

  Future<void> _openEditor(
    BuildContext context, {
    CompanyContact? contact,
  }) async {
    if (companies.isEmpty) {
      return;
    }

    String companyId = contact?.companyId.isNotEmpty == true
        ? contact!.companyId
        : companies.first.id;
    final nameController = TextEditingController(text: contact?.name ?? '');
    final emailController = TextEditingController(text: contact?.email ?? '');
    final phoneController = TextEditingController(text: contact?.phone ?? '');
    final roleController = TextEditingController(text: contact?.role ?? '');

    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => AlertDialog(
          title: Text(contact == null ? 'Nuovo contatto' : 'Modifica contatto'),
          content: SizedBox(
            width: 520,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: companyId,
                  decoration: const InputDecoration(
                    labelText: 'Azienda',
                    border: OutlineInputBorder(),
                  ),
                  items: companies
                      .map(
                        (company) => DropdownMenuItem(
                          value: company.id,
                          child: Text(company.name),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value == null) {
                      return;
                    }
                    setModalState(() => companyId = value);
                  },
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'Nome',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: emailController,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: phoneController,
                  decoration: const InputDecoration(
                    labelText: 'Telefono',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: roleController,
                  decoration: const InputDecoration(
                    labelText: 'Ruolo',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Annulla'),
            ),
            FilledButton(
              onPressed: () async {
                final item = CompanyContact(
                  id:
                      contact?.id ??
                      'cc-${DateTime.now().microsecondsSinceEpoch}',
                  companyId: companyId,
                  name: nameController.text.trim(),
                  email: emailController.text.trim(),
                  phone: phoneController.text.trim(),
                  role: roleController.text.trim(),
                );
                if (contact == null) {
                  await onCreate(item);
                } else {
                  await onUpdate(item);
                }
                if (context.mounted) {
                  Navigator.of(context).pop();
                }
              },
              child: const Text('Salva'),
            ),
          ],
        ),
      ),
    );

    nameController.dispose();
    emailController.dispose();
    phoneController.dispose();
    roleController.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Contatti aziende',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
                ),
              ),
              FilledButton.icon(
                onPressed: () => _openEditor(context),
                icon: const Icon(Icons.add),
                label: const Text('Nuovo contatto'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: ListView.separated(
              itemCount: contacts.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final contact = contacts[index];
                final company = companies.firstWhere(
                  (item) => item.id == contact.companyId,
                  orElse: () => const Company(
                    id: '',
                    name: 'Azienda non trovata',
                    vatNumber: '',
                    taxCode: '',
                    pec: '',
                    sdiCode: '',
                    email: '',
                    phone: '',
                    website: '',
                    addressLine: '',
                    city: '',
                    postalCode: '',
                    country: '',
                    contactPerson: '',
                    notes: '',
                  ),
                );
                return ListTile(
                  title: Text('${contact.name} • ${company.name}'),
                  subtitle: Text(
                    '${contact.email}${contact.role.isNotEmpty ? ' • ${contact.role}' : ''}${contact.phone.isNotEmpty ? ' • ${contact.phone}' : ''}',
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        onPressed: () => _openEditor(context, contact: contact),
                        icon: const Icon(Icons.edit_outlined),
                      ),
                      IconButton(
                        onPressed: () => onDelete(contact.id),
                        icon: const Icon(Icons.delete_outline),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
