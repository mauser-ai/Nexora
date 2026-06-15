import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

import '../data/firestore_workspace_repository.dart';
import '../models/domain_models.dart';
import '../services/ticket_mail_service.dart';

class MobileWorkspaceScaffold extends StatefulWidget {
  const MobileWorkspaceScaffold({
    super.key,
    required this.workspace,
    required this.currentUserName,
    required this.emailSignatureHtml,
    required this.onCreateTicket,
    required this.onUpdateTicket,
    required this.onEditTask,
    required this.onLogTime,
    required this.onToggleTaskDone,
    required this.onDeleteTimelineSlot,
    required this.onRepeatTaskUntilDeadline,
    required this.onAddTask,
  });

  final WorkspaceSnapshot workspace;
  final String currentUserName;
  final String emailSignatureHtml;
  final Future<void> Function(Ticket ticket) onCreateTicket;
  final Future<void> Function(Ticket ticket) onUpdateTicket;
  final Future<void> Function(WorkTask task) onEditTask;
  final Future<void> Function(WorkTask task) onLogTime;
  final Future<void> Function(WorkTask task, bool done) onToggleTaskDone;
  final Future<void> Function(TimelineSlot slot) onDeleteTimelineSlot;
  final Future<void> Function(WorkTask task, TimelineSlot slot)
  onRepeatTaskUntilDeadline;
  final Future<void> Function() onAddTask;

  @override
  State<MobileWorkspaceScaffold> createState() =>
      _MobileWorkspaceScaffoldState();
}

class _MobileWorkspaceScaffoldState extends State<MobileWorkspaceScaffold> {
  int _tabIndex = 0;

  bool get _showIosLogout => defaultTargetPlatform == TargetPlatform.iOS;

  @override
  Widget build(BuildContext context) {
    final pages = [
      _MobileTodayScreen(
        workspace: widget.workspace,
        onEditTask: widget.onEditTask,
        onLogTime: widget.onLogTime,
        onToggleTaskDone: widget.onToggleTaskDone,
        onDeleteTimelineSlot: widget.onDeleteTimelineSlot,
        onRepeatTaskUntilDeadline: widget.onRepeatTaskUntilDeadline,
        onAddTask: widget.onAddTask,
      ),
      _MobileTicketScreen(
        workspace: widget.workspace,
        currentUserName: widget.currentUserName,
        emailSignatureHtml: widget.emailSignatureHtml,
        onCreateTicket: widget.onCreateTicket,
        onUpdateTicket: widget.onUpdateTicket,
      ),
      _MobileStatsScreen(workspace: widget.workspace),
    ];

    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFEAF2EE), Color(0xFFF6F4F1), Color(0xFFF6F4F1)],
            stops: [0.0, 0.2, 1.0],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              if (_showIosLogout)
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
                  child: Row(
                    children: [
                      const Spacer(),
                      OutlinedButton.icon(
                        onPressed: FirebaseAuth.instance.signOut,
                        icon: const Icon(Icons.logout, size: 16),
                        label: const Text('Logout'),
                      ),
                    ],
                  ),
                ),
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  child: pages[_tabIndex],
                ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: NavigationBar(
        height: 76,
        selectedIndex: _tabIndex,
        onDestinationSelected: (value) => setState(() => _tabIndex = value),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.today_outlined),
            selectedIcon: Icon(Icons.today),
            label: 'Oggi',
          ),
          NavigationDestination(
            icon: Icon(Icons.support_agent_outlined),
            selectedIcon: Icon(Icons.support_agent),
            label: 'Ticket',
          ),
          NavigationDestination(
            icon: Icon(Icons.bar_chart_outlined),
            selectedIcon: Icon(Icons.bar_chart),
            label: 'Statistiche',
          ),
        ],
      ),
    );
  }
}

class _MobileTodayScreen extends StatefulWidget {
  const _MobileTodayScreen({
    required this.workspace,
    required this.onEditTask,
    required this.onLogTime,
    required this.onToggleTaskDone,
    required this.onDeleteTimelineSlot,
    required this.onRepeatTaskUntilDeadline,
    required this.onAddTask,
  });

  final WorkspaceSnapshot workspace;
  final Future<void> Function(WorkTask task) onEditTask;
  final Future<void> Function(WorkTask task) onLogTime;
  final Future<void> Function(WorkTask task, bool done) onToggleTaskDone;
  final Future<void> Function(TimelineSlot slot) onDeleteTimelineSlot;
  final Future<void> Function(WorkTask task, TimelineSlot slot)
  onRepeatTaskUntilDeadline;
  final Future<void> Function() onAddTask;

  @override
  State<_MobileTodayScreen> createState() => _MobileTodayScreenState();
}

class _MobileTodayScreenState extends State<_MobileTodayScreen> {
  DateTime _day = DateTime.now();

  DateTime _normalize(DateTime date) =>
      DateTime(date.year, date.month, date.day);

  @override
  Widget build(BuildContext context) {
    final normalizedDay = _normalize(_day);
    final daySlots = widget.workspace.plannedSlots.where((slot) {
      final slotDay = _normalize(slot.date);
      return slotDay == normalizedDay;
    }).toList()..sort((a, b) => a.startHour.compareTo(b.startHour));

    final dayTracks = widget.workspace.timeTracks.where((track) {
      final trackDay = _normalize(track.startAt);
      return trackDay == normalizedDay;
    }).toList()..sort((a, b) => a.startAt.compareTo(b.startAt));

    final tasksById = {
      for (final task in widget.workspace.tasks) task.id: task,
    };
    final companiesById = {
      for (final company in widget.workspace.companies) company.id: company,
    };

    final totalPlanned = daySlots.fold<double>(
      0,
      (sum, slot) => sum + slot.plannedHours,
    );
    final totalTracked = dayTracks.fold<double>(
      0,
      (sum, track) => sum + track.hours,
    );

    return _MobilePageScaffold(
      title: 'Agenda giornaliera',
      subtitle: 'Vista rapida del tuo carico quotidiano e dei tempi segnati.',
      trailing: OutlinedButton.icon(
        onPressed: widget.onAddTask,
        icon: const Icon(Icons.add, size: 16),
        label: const Text('Aggiungi task'),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _FrostCard(
            child: Row(
              children: [
                _RoundActionButton(
                  icon: Icons.chevron_left,
                  onTap: () => setState(
                    () => _day = _day.subtract(const Duration(days: 1)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        DateFormat(
                          'EEEE d MMMM yyyy',
                          'it_IT',
                        ).format(normalizedDay),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: _MobilePalette.text,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _isToday(normalizedDay)
                            ? 'Oggi'
                            : DateFormat('EEEE', 'it_IT').format(normalizedDay),
                        style: const TextStyle(
                          fontSize: 13,
                          color: _MobilePalette.muted,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                _RoundActionButton(
                  icon: Icons.chevron_right,
                  onTap: () =>
                      setState(() => _day = _day.add(const Duration(days: 1))),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _MetricCard(
                  label: 'Pianificato',
                  value: _formatHours(totalPlanned),
                  icon: Icons.view_timeline_rounded,
                  accent: _MobilePalette.primary,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _MetricCard(
                  label: 'Segnato',
                  value: _formatHours(totalTracked),
                  icon: Icons.schedule_rounded,
                  accent: _MobilePalette.accent,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Expanded(
            child: _FrostCard(
              padding: const EdgeInsets.all(10),
              child: _buildPlannedList(daySlots, tasksById, companiesById),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlannedList(
    List<TimelineSlot> daySlots,
    Map<String, WorkTask> tasksById,
    Map<String, Company> companiesById,
  ) {
    if (daySlots.isEmpty) {
      return const _EmptyLine('Nessun task pianificato per questo giorno.');
    }

    return ListView.separated(
      itemCount: daySlots.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final slot = daySlots[index];
        final task = tasksById[slot.taskId];
        final company = task == null ? null : companiesById[task.companyId];
        final from = slot.startHour;
        final to = slot.startHour + slot.plannedHours;
        final accent = _colorForKey(task?.id ?? slot.id);
        return _TimelineItemCard(
          accent: accent,
          title: task?.name ?? 'Task non trovato',
          subtitle: company?.name ?? 'Azienda non assegnata',
          badge: '${_hourLabel(from)} - ${_hourLabel(to)}',
          trailing: _formatHours(slot.plannedHours),
          icon: Icons.task_alt,
          onTap: () => _openSlotActions(slot: slot, task: task),
        );
      },
    );
  }

  Future<void> _openSlotActions({
    required TimelineSlot slot,
    required WorkTask? task,
  }) async {
    final action = await Navigator.of(context).push<_MobileSlotAction>(
      MaterialPageRoute(
        builder: (context) => _MobileSlotActionsPage(slot: slot, task: task),
        fullscreenDialog: true,
      ),
    );

    if (!mounted || action == null) {
      return;
    }

    switch (action) {
      case _MobileSlotAction.removePlanned:
        await widget.onDeleteTimelineSlot(slot);
        break;
      case _MobileSlotAction.editTask:
        if (task != null) {
          await widget.onEditTask(task);
        }
        break;
      case _MobileSlotAction.logTime:
        if (task != null) {
          await widget.onLogTime(task);
        }
        break;
      case _MobileSlotAction.repeatUntilDeadline:
        if (task != null) {
          await widget.onRepeatTaskUntilDeadline(task, slot);
        }
        break;
      case _MobileSlotAction.markDone:
        if (task != null) {
          await widget.onToggleTaskDone(task, task.status != TaskStatus.done);
        }
        break;
    }
  }

  String _hourLabel(double hour) {
    final h = hour.floor();
    final m = ((hour - h) * 60).round();
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
  }
}

enum _MobileSlotAction {
  removePlanned,
  editTask,
  logTime,
  repeatUntilDeadline,
  markDone,
}

class _MobileSlotActionsPage extends StatelessWidget {
  const _MobileSlotActionsPage({required this.slot, required this.task});

  final TimelineSlot slot;
  final WorkTask? task;

  @override
  Widget build(BuildContext context) {
    final isDone = task?.status == TaskStatus.done;
    final title = task?.name ?? 'Task non trovato';
    final subtitle =
        '${_formatHour(slot.startHour)} - ${_formatHour(slot.startHour + slot.plannedHours)} • ${_formatHours(slot.plannedHours)}';

    return Scaffold(
      backgroundColor: const Color(0xFFF6F4F1),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Azioni task'),
      ),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFFFFFFF),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFDCE2E8)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: _MobilePalette.text,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: _MobilePalette.muted,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView(
                children: [
                  _SlotActionTile(
                    icon: Icons.edit_outlined,
                    title: 'Modifica task',
                    subtitle: 'Apri popup modifica',
                    enabled: task != null,
                    onTap: () =>
                        Navigator.of(context).pop(_MobileSlotAction.editTask),
                  ),
                  _SlotActionTile(
                    icon: Icons.schedule_send_outlined,
                    title: 'Segna tempo',
                    subtitle: 'Aggiungi segnatempo sul task',
                    enabled: task != null,
                    onTap: () =>
                        Navigator.of(context).pop(_MobileSlotAction.logTime),
                  ),
                  _SlotActionTile(
                    icon: Icons.event_repeat_outlined,
                    title: 'Ripeti fino a scadenza',
                    subtitle: 'Replica negli altri giorni disponibili',
                    enabled: task != null,
                    onTap: () => Navigator.of(
                      context,
                    ).pop(_MobileSlotAction.repeatUntilDeadline),
                  ),
                  _SlotActionTile(
                    icon: isDone ? Icons.lock_open : Icons.check_circle_outline,
                    title: isDone ? 'Riapri' : 'Segna task come fatto',
                    subtitle: isDone
                        ? 'Riporta il task in lavorazione'
                        : 'Imposta task completato',
                    enabled: task != null,
                    onTap: () =>
                        Navigator.of(context).pop(_MobileSlotAction.markDone),
                  ),
                  _SlotActionTile(
                    icon: Icons.delete_outline,
                    title: 'Rimuovi evento pianificato',
                    subtitle: 'Elimina solo questo slot in planning',
                    danger: true,
                    onTap: () => Navigator.of(
                      context,
                    ).pop(_MobileSlotAction.removePlanned),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SlotActionTile extends StatelessWidget {
  const _SlotActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.enabled = true,
    this.danger = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool enabled;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final color = danger ? const Color(0xFFB42318) : _MobilePalette.text;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: enabled ? onTap : null,
        child: Ink(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: enabled ? Colors.white : const Color(0xFFF1F5F9),
            border: Border.all(color: const Color(0xFFDCE2E8)),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: (enabled ? color : const Color(0xFF94A3B8)).withValues(
                    alpha: 0.12,
                  ),
                ),
                child: Icon(
                  icon,
                  size: 18,
                  color: enabled ? color : const Color(0xFF94A3B8),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: enabled ? color : const Color(0xFF94A3B8),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: _MobilePalette.muted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: enabled
                    ? const Color(0xFF94A3B8)
                    : const Color(0xFFCBD5E1),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MobileTicketScreen extends StatefulWidget {
  const _MobileTicketScreen({
    required this.workspace,
    required this.currentUserName,
    required this.emailSignatureHtml,
    required this.onCreateTicket,
    required this.onUpdateTicket,
  });

  final WorkspaceSnapshot workspace;
  final String currentUserName;
  final String emailSignatureHtml;
  final Future<void> Function(Ticket ticket) onCreateTicket;
  final Future<void> Function(Ticket ticket) onUpdateTicket;

  @override
  State<_MobileTicketScreen> createState() => _MobileTicketScreenState();
}

class _MobileTicketScreenState extends State<_MobileTicketScreen> {
  final TicketMailService _mailService = TicketMailService();
  final TextEditingController _composerController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _messagesScrollController = ScrollController();

  Ticket? _selected;
  bool _publicReply = true;
  bool _sending = false;
  String _query = '';

  static final RegExp _ticketRefRegex = RegExp(
    r'#ticket-([A-Za-z0-9_-]+)',
    caseSensitive: false,
  );
  static const Set<String> _selfAliases = {
    'mbroggini37@gmail.com',
    'info@matteobroggini.it',
  };

  @override
  void dispose() {
    _composerController.dispose();
    _searchController.dispose();
    _messagesScrollController.dispose();
    super.dispose();
  }

  void _scrollMessagesToBottom({bool animated = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_messagesScrollController.hasClients) {
        return;
      }
      final target = _messagesScrollController.position.maxScrollExtent;
      if (animated) {
        _messagesScrollController.animateTo(
          target,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
        );
      } else {
        _messagesScrollController.jumpTo(target);
      }
    });
  }

  String _ticketRef(Ticket ticket) => '#ticket-${ticket.id}';

  String _stripTicketRef(String value) {
    final next = value.replaceAll(_ticketRefRegex, '').trim();
    return next.replaceAll(RegExp(r'\s+'), ' ');
  }

  String _withTicketRefInSubject(Ticket ticket, String subject) {
    final clean = _stripTicketRef(subject);
    if (clean.isEmpty) {
      return _ticketRef(ticket);
    }
    return '$clean [${_ticketRef(ticket)}]';
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
        return 'In attesa';
      case TicketStatus.closed:
        return 'Chiuso';
    }
  }

  Color _statusColor(TicketStatus status) {
    switch (status) {
      case TicketStatus.newTicket:
        return const Color(0xFF0EA5E9);
      case TicketStatus.open:
        return const Color(0xFF5B1205);
      case TicketStatus.waitingCustomer:
        return const Color(0xFFD97706);
      case TicketStatus.closed:
        return const Color(0xFF8C8478);
    }
  }

  String _ticketAvatarInitial(Ticket ticket) {
    String source = '';
    for (final company in widget.workspace.companies) {
      if (company.id == ticket.companyId && company.name.trim().isNotEmpty) {
        source = company.name.trim();
        break;
      }
    }
    if (source.isEmpty) {
      source = ticket.recipientEmail.trim();
    }
    if (source.isEmpty) {
      return '?';
    }
    return source.substring(0, 1).toUpperCase();
  }

  String _ticketAvatarSeed(Ticket ticket) {
    for (final company in widget.workspace.companies) {
      if (company.id == ticket.companyId && company.name.trim().isNotEmpty) {
        return 'cmp:${company.name.trim().toLowerCase()}';
      }
    }
    return 'mail:${ticket.recipientEmail.trim().toLowerCase()}';
  }

  Future<void> _submit() async {
    final ticket = _selected;
    if (ticket == null) {
      return;
    }
    final body = _composerController.text.trim();
    if (body.isEmpty) {
      return;
    }

    setState(() => _sending = true);
    try {
      if (_publicReply) {
        final subject = _withTicketRefInSubject(ticket, ticket.title);
        final footer =
            '\n\n---\n'
            'Messaggio inviato da G-Flux (${_ticketRef(ticket)}).\n'
            'Per favore non modificare l\'oggetto quando rispondi a questa email.';
        final fullBody = '$body$footer';
        await _mailService.sendTicketEmail(
          toEmail: ticket.recipientEmail,
          subject: subject,
          body: fullBody,
          attachmentPaths: const [],
          signatureHtml: widget.emailSignatureHtml,
        );
        final outbound = TicketEntry(
          id: 'tentry-${DateTime.now().microsecondsSinceEpoch}',
          type: TicketEntryType.outboundEmail,
          body: body,
          createdAt: DateTime.now(),
          authorName: widget.currentUserName,
          recipientEmail: ticket.recipientEmail,
          subject: subject,
          attachmentPaths: const [],
        );
        await widget.onUpdateTicket(
          ticket.copyWith(
            status: TicketStatus.waitingCustomer,
            updatedAt: DateTime.now(),
            entries: [...ticket.entries, outbound],
          ),
        );
      } else {
        final note = TicketEntry(
          id: 'tentry-${DateTime.now().microsecondsSinceEpoch}',
          type: TicketEntryType.internalNote,
          body: body,
          createdAt: DateTime.now(),
          authorName: widget.currentUserName,
        );
        await widget.onUpdateTicket(
          ticket.copyWith(
            updatedAt: DateTime.now(),
            entries: [...ticket.entries, note],
          ),
        );
      }
      _composerController.clear();
      _scrollMessagesToBottom();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_publicReply ? 'Risposta inviata.' : 'Nota salvata.'),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _sending = false);
      }
    }
  }

  Future<void> _openCreateTicketDialog() async {
    if (widget.workspace.companies.isEmpty) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Crea prima almeno una azienda.')),
      );
      return;
    }

    String selectedCompanyId = widget.workspace.companies.first.id;
    String? selectedRecipient;
    final subjectController = TextEditingController();

    List<String> recipientsForCompany(String companyId) {
      final out = <String>[];
      for (final company in widget.workspace.companies) {
        if (company.id == companyId && company.email.trim().isNotEmpty) {
          out.add(company.email.trim());
        }
      }
      for (final contact in widget.workspace.companyContacts) {
        if (contact.companyId != companyId) {
          continue;
        }
        final email = contact.email.trim();
        if (email.isEmpty || out.contains(email)) {
          continue;
        }
        out.add(email);
      }
      return out;
    }

    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          final recipients = recipientsForCompany(selectedCompanyId);
          selectedRecipient ??= recipients.isNotEmpty ? recipients.first : null;
          if (selectedRecipient != null &&
              !recipients.contains(selectedRecipient)) {
            selectedRecipient = recipients.isNotEmpty ? recipients.first : null;
          }
          return AlertDialog(
            title: const Text('Nuovo ticket'),
            content: SizedBox(
              width: 520,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: selectedCompanyId,
                    isExpanded: true,
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
                    isExpanded: true,
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
                      labelText: 'Oggetto ticket',
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
                    if (!mounted) {
                      return;
                    }
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
                  if (!mounted) {
                    return;
                  }
                  setState(() => _selected = ticket);
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

  @override
  Widget build(BuildContext context) {
    final tickets = widget.workspace.tickets;
    final selected = _selected;

    if (selected == null) {
      final filtered = tickets.where((ticket) {
        final query = _query.trim().toLowerCase();
        if (query.isEmpty) {
          return true;
        }
        return ticket.title.toLowerCase().contains(query) ||
            ticket.recipientEmail.toLowerCase().contains(query) ||
            _statusLabel(ticket.status).toLowerCase().contains(query);
      }).toList()..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

      return _MobilePageScaffold(
        title: 'Ticket',
        subtitle: 'Gestisci conversazioni, note interne e risposte ai clienti.',
        trailing: OutlinedButton.icon(
          onPressed: _openCreateTicketDialog,
          icon: const Icon(Icons.add, size: 16),
          label: const Text('Aggiungi ticket'),
        ),
        child: Column(
          children: [
            _FrostCard(
              child: TextField(
                controller: _searchController,
                onChanged: (value) => setState(() => _query = value),
                decoration: const InputDecoration(
                  hintText: 'Cerca per oggetto, email o stato...',
                  prefixIcon: Icon(Icons.search),
                  border: InputBorder.none,
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: _FrostCard(
                padding: const EdgeInsets.all(10),
                child: filtered.isEmpty
                    ? const _EmptyLine('Nessun ticket trovato.')
                    : ListView.separated(
                        itemCount: filtered.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final ticket = filtered[index];
                          final statusColor = _statusColor(ticket.status);
                          final last = ticket.entries.isNotEmpty
                              ? ticket.entries.last
                              : null;
                          final lastPreview = last == null
                              ? ''
                              : _displayTicketBody(last.body);
                          return InkWell(
                            borderRadius: BorderRadius.circular(14),
                            onTap: () {
                              setState(() => _selected = ticket);
                              _scrollMessagesToBottom(animated: false);
                            },
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: const Color(0xFFE9E5DF),
                                ),
                                gradient: const LinearGradient(
                                  colors: [
                                    Color(0xFFFFFFFF),
                                    Color(0xFFF8FAFC),
                                  ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Expanded(
                                        child: Text(
                                          ticket.title,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w800,
                                            color: _MobilePalette.text,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      _StatusPill(
                                        label: _statusLabel(ticket.status),
                                        color: statusColor,
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    ticket.recipientEmail,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: _MobilePalette.muted,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Row(
                                    children: [
                                      Text(
                                        _ticketRef(ticket),
                                        style: const TextStyle(
                                          color: _MobilePalette.primary,
                                          fontWeight: FontWeight.w700,
                                          fontSize: 12,
                                        ),
                                      ),
                                      const Spacer(),
                                      Text(
                                        DateFormat(
                                          'dd/MM HH:mm',
                                        ).format(ticket.updatedAt),
                                        style: const TextStyle(
                                          color: _MobilePalette.muted,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (lastPreview.isNotEmpty) ...[
                                    const SizedBox(height: 6),
                                    Text(
                                      lastPreview,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: _MobilePalette.text,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ),
          ],
        ),
      );
    }

    final entries = [...selected.entries]
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    final avatarInitial = _ticketAvatarInitial(selected);
    final avatarColor = _colorForKey(
      'ticket-avatar-${_ticketAvatarSeed(selected)}',
    );
    _scrollMessagesToBottom(animated: false);

    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            decoration: BoxDecoration(
              color: const Color(0xFFFFFFFF),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFDCE2E8)),
            ),
            child: Row(
              children: [
                IconButton(
                  onPressed: () => setState(() => _selected = null),
                  icon: const Icon(Icons.arrow_back),
                  visualDensity: VisualDensity.compact,
                ),
                SizedBox(
                  width: 38,
                  height: 38,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: avatarColor.withValues(alpha: 0.18),
                          border: Border.all(
                            color: avatarColor.withValues(alpha: 0.50),
                          ),
                        ),
                        child: const Icon(
                          Icons.person_outline,
                          color: _MobilePalette.primary,
                        ),
                      ),
                      Positioned(
                        right: -2,
                        bottom: -2,
                        child: Container(
                          width: 18,
                          height: 18,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: avatarColor,
                            border: Border.all(
                              color: const Color(0xFFF6F4F1),
                              width: 1.5,
                            ),
                          ),
                          child: Text(
                            avatarInitial,
                            style: const TextStyle(
                              color: const Color(0xFFFFFFFF),
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        selected.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: _MobilePalette.text,
                        ),
                      ),
                      Text(
                        selected.recipientEmail,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          color: _MobilePalette.muted,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                _StatusPill(
                  label: _statusLabel(selected.status),
                  color: _statusColor(selected.status),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFDCE2E8)),
                color: const Color(0xFFEAF2EE),
              ),
              child: Column(
                children: [
                  Expanded(
                    child: entries.isEmpty
                        ? const _EmptyLine('Nessun messaggio nel ticket.')
                        : ListView.builder(
                            controller: _messagesScrollController,
                            padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
                            itemCount: entries.length,
                            itemBuilder: (context, index) {
                              final entry = entries[index];
                              final outbound =
                                  entry.type == TicketEntryType.outboundEmail;
                              final internal =
                                  entry.type == TicketEntryType.internalNote;
                              return _TicketChatBubble(
                                entry: entry,
                                outbound: outbound,
                                internal: internal,
                                bodyText: _displayTicketBody(entry.body),
                                authorLabel: _entryDisplayAuthor(entry),
                              );
                            },
                          ),
                  ),
                  Container(
                    padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                    decoration: const BoxDecoration(
                      color: Color(0xFFF7FAF9),
                      border: Border(top: BorderSide(color: Color(0xFFDCE2E8))),
                    ),
                    child: Column(
                      children: [
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            ChoiceChip(
                              selected: !_publicReply,
                              label: const Text('Nota interna'),
                              onSelected: (_) =>
                                  setState(() => _publicReply = false),
                            ),
                            ChoiceChip(
                              selected: _publicReply,
                              label: const Text('Risposta pubblica'),
                              onSelected: (_) =>
                                  setState(() => _publicReply = true),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _composerController,
                                minLines: 1,
                                maxLines: 6,
                                textInputAction: TextInputAction.newline,
                                decoration: InputDecoration(
                                  hintText: _publicReply
                                      ? 'Messaggio...'
                                      : 'Nota interna...',
                                  fillColor: const Color(0xFFF6F4F1),
                                  filled: true,
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 12,
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(999),
                                    borderSide: const BorderSide(
                                      color: Color(0xFFDCE2E8),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Material(
                              color: _publicReply
                                  ? _MobilePalette.primary
                                  : const Color(0xFF475569),
                              borderRadius: BorderRadius.circular(999),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(999),
                                onTap: _sending ? null : _submit,
                                child: SizedBox(
                                  width: 46,
                                  height: 46,
                                  child: Icon(
                                    _publicReply
                                        ? Icons.send_rounded
                                        : Icons.note_add_rounded,
                                    color: const Color(0xFFFFFFFF),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TicketChatBubble extends StatelessWidget {
  const _TicketChatBubble({
    required this.entry,
    required this.outbound,
    required this.internal,
    required this.bodyText,
    required this.authorLabel,
  });

  final TicketEntry entry;
  final bool outbound;
  final bool internal;
  final String bodyText;
  final String authorLabel;

  @override
  Widget build(BuildContext context) {
    final alignment = outbound ? Alignment.centerRight : Alignment.centerLeft;
    final maxWidth = MediaQuery.of(context).size.width * 0.76;
    final bubbleColor = internal
        ? const Color(0xFFE9E5DF)
        : outbound
        ? const Color(0xFFD9FDD3)
        : Colors.white;
    final radius = BorderRadius.only(
      topLeft: const Radius.circular(14),
      topRight: const Radius.circular(14),
      bottomLeft: Radius.circular(outbound ? 14 : 4),
      bottomRight: Radius.circular(outbound ? 4 : 14),
    );

    return Align(
      alignment: alignment,
      child: Container(
        margin: const EdgeInsets.only(bottom: 7),
        constraints: BoxConstraints(maxWidth: maxWidth),
        padding: const EdgeInsets.fromLTRB(11, 8, 11, 7),
        decoration: BoxDecoration(
          color: bubbleColor,
          borderRadius: radius,
          boxShadow: const [
            BoxShadow(
              color: Color(0x14000000),
              blurRadius: 6,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    internal ? 'Nota interna • $authorLabel' : authorLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: internal
                          ? const Color(0xFF334155)
                          : const Color(0xFF166534),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  DateFormat('HH:mm').format(entry.createdAt),
                  style: const TextStyle(
                    fontSize: 10,
                    color: Color(0xFF64748B),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 3),
            Text(
              bodyText.isEmpty ? '...' : bodyText,
              style: const TextStyle(color: _MobilePalette.text, height: 1.32),
            ),
          ],
        ),
      ),
    );
  }
}

class _MobileStatsScreen extends StatelessWidget {
  const _MobileStatsScreen({required this.workspace});

  final WorkspaceSnapshot workspace;

  @override
  Widget build(BuildContext context) {
    final companies = {for (final c in workspace.companies) c.id: c};
    final tasks = workspace.tasks;
    final plannedByTask = <String, double>{};
    for (final slot in workspace.plannedSlots) {
      plannedByTask.update(
        slot.taskId,
        (value) => value + slot.plannedHours,
        ifAbsent: () => slot.plannedHours,
      );
    }
    final spentByTask = <String, double>{};
    for (final track in workspace.timeTracks) {
      spentByTask.update(
        track.taskId,
        (value) => value + track.hours,
        ifAbsent: () => track.hours,
      );
    }

    final rows =
        <({String label, double estimated, double planned, double spent})>[];
    for (final task in tasks) {
      rows.add((
        label: '${companies[task.companyId]?.name ?? '-'} • ${task.name}',
        estimated: task.estimatedHours,
        planned: plannedByTask[task.id] ?? 0,
        spent: spentByTask[task.id] ?? task.loggedHours,
      ));
    }
    rows.sort((a, b) => b.spent.compareTo(a.spent));

    final totalEstimated = rows.fold<double>(
      0,
      (sum, row) => sum + row.estimated,
    );
    final totalPlanned = rows.fold<double>(0, (sum, row) => sum + row.planned);
    final totalSpent = rows.fold<double>(0, (sum, row) => sum + row.spent);

    return _MobilePageScaffold(
      title: 'Statistiche',
      subtitle: 'Previsto, pianificato e speso in un’unica vista mobile.',
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _MetricCard(
                  label: 'Previsto',
                  value: _formatHours(totalEstimated),
                  icon: Icons.flag_outlined,
                  accent: const Color(0xFF0EA5E9),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _MetricCard(
                  label: 'Pianificato',
                  value: _formatHours(totalPlanned),
                  icon: Icons.grid_view_rounded,
                  accent: _MobilePalette.primary,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _MetricCard(
                  label: 'Speso',
                  value: _formatHours(totalSpent),
                  icon: Icons.hourglass_bottom_rounded,
                  accent: const Color(0xFFD97706),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Expanded(
            child: _FrostCard(
              padding: const EdgeInsets.all(10),
              child: rows.isEmpty
                  ? const _EmptyLine('Nessun dato statistico disponibile.')
                  : ListView.separated(
                      itemBuilder: (context, index) {
                        final row = rows[index];
                        final denom = row.estimated <= 0 ? 1.0 : row.estimated;
                        final progress = (row.spent / denom).clamp(0.0, 1.0);
                        final accent = _colorForKey(row.label);
                        return Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: const Color(0xFFE9E5DF)),
                            color: const Color(0xFFFFFFFF),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                row.label,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  color: _MobilePalette.text,
                                ),
                              ),
                              const SizedBox(height: 8),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(999),
                                child: LinearProgressIndicator(
                                  minHeight: 8,
                                  value: progress,
                                  backgroundColor: const Color(0xFFE9E5DF),
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    accent,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Previsto ${_formatHours(row.estimated)} • Pianificato ${_formatHours(row.planned)} • Speso ${_formatHours(row.spent)}',
                                style: const TextStyle(
                                  color: _MobilePalette.muted,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemCount: rows.length,
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MobilePageScaffold extends StatelessWidget {
  const _MobilePageScaffold({
    required this.title,
    required this.subtitle,
    required this.child,
    this.trailing,
  });

  final String title;
  final String subtitle;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                        color: _MobilePalette.text,
                        letterSpacing: -0.4,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: _MobilePalette.muted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              if (trailing != null) ...[const SizedBox(width: 8), trailing!],
            ],
          ),
          const SizedBox(height: 10),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.accent,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE9E5DF)),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFFFFFF), Color(0xFFF7FAF9)],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: accent.withValues(alpha: 0.15),
                ),
                child: Icon(icon, size: 16, color: accent),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _MobilePalette.muted,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 20,
              color: _MobilePalette.text,
            ),
          ),
        ],
      ),
    );
  }
}

class _TimelineItemCard extends StatelessWidget {
  const _TimelineItemCard({
    required this.accent,
    required this.title,
    required this.subtitle,
    required this.badge,
    required this.trailing,
    required this.icon,
    this.onTap,
  });

  final Color accent;
  final String title;
  final String subtitle;
  final String badge;
  final String trailing;
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: accent.withValues(alpha: 0.45)),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [accent.withValues(alpha: 0.12), Colors.white],
          ),
        ),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                width: 6,
                decoration: BoxDecoration(
                  color: accent,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(14),
                    bottomLeft: Radius.circular(14),
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 24,
                            height: 24,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: accent.withValues(alpha: 0.16),
                            ),
                            child: Icon(icon, size: 14, color: accent),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                color: _MobilePalette.text,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 5),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: _MobilePalette.muted,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(999),
                              color: const Color(0xFFFFFFFF),
                              border: Border.all(color: const Color(0xFFD7DEE4)),
                            ),
                            child: Text(
                              badge,
                              style: const TextStyle(
                                fontSize: 12,
                                color: _MobilePalette.muted,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          const Spacer(),
                          Text(
                            trailing,
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              color: _MobilePalette.text,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: color.withValues(alpha: 0.12),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w800,
          fontSize: 11,
        ),
      ),
    );
  }
}

class _RoundActionButton extends StatelessWidget {
  const _RoundActionButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Ink(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: const Color(0xFFFFFFFF),
          border: Border.all(color: const Color(0xFFD8DEE5)),
        ),
        child: Icon(icon, color: _MobilePalette.text),
      ),
    );
  }
}

class _FrostCard extends StatelessWidget {
  const _FrostCard({
    required this.child,
    this.padding = const EdgeInsets.all(12),
  });

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: const Color(0xFFFCFDFE),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFDCE2E8)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x11000000),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _EmptyLine extends StatelessWidget {
  const _EmptyLine(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: _MobilePalette.muted,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _MobilePalette {
  static const Color primary = Color(0xFF5B1205);
  static const Color accent = Color(0xFF0C7A5C);
  static const Color text = Color(0xFF0F172A);
  static const Color muted = Color(0xFF64748B);
}

String _formatHours(double value) {
  if (value <= 0) {
    return '0h';
  }
  final totalMinutes = (value * 60).round();
  final hours = totalMinutes ~/ 60;
  final minutes = totalMinutes % 60;
  if (minutes == 0) {
    return '${hours}h';
  }
  if (hours == 0) {
    return '${minutes}min';
  }
  return '${hours}h ${minutes.toString().padLeft(2, '0')}';
}

String _formatHour(double hour) {
  final h = hour.floor();
  final m = ((hour - h) * 60).round();
  return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
}

bool _isToday(DateTime day) {
  final now = DateTime.now();
  return now.year == day.year && now.month == day.month && now.day == day.day;
}

Color _colorForKey(String key) {
  const palette = <Color>[
    Color(0xFF0EA5E9),
    Color(0xFF22C55E),
    Color(0xFFF97316),
    Color(0xFFA855F7),
    Color(0xFF14B8A6),
    Color(0xFFEAB308),
    Color(0xFF3B82F6),
    Color(0xFFEF4444),
    Color(0xFF10B981),
  ];
  final hash = key.codeUnits.fold<int>(0, (acc, c) => ((acc * 31) + c));
  final index = hash.abs() % palette.length;
  final base = palette[index];
  final brightener = (key.length % 4) * 0.05;
  return Color.lerp(base, Colors.white, brightener.clamp(0, 0.2)) ?? base;
}
