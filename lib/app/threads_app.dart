import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../brand_config.dart';
import '../data/workspace_snapshot.dart';
import '../models/domain_models.dart';

class ThreadsApp extends StatefulWidget {
  const ThreadsApp({
    super.key,
    required this.workspace,
    required this.userEmail,
  });

  final WorkspaceSnapshot workspace;
  final String userEmail;

  @override
  State<ThreadsApp> createState() => _ThreadsAppState();
}

class _ThreadsAppState extends State<ThreadsApp> {
  String _mailboxId = 'inbox-all';
  String _query = '';
  late String _selectedThreadId;

  // Mobile navigation: false = lista thread, true = lettore thread
  bool _mobileShowReader = false;

  late final List<_ThreadsAccount> _accounts = _buildAccounts();
  late final List<_ThreadMessage> _threads = _buildThreads();

  @override
  void initState() {
    super.initState();
    _selectedThreadId = _threads.first.id;
  }

  List<_ThreadsAccount> _buildAccounts() {
    final email = widget.userEmail.trim().isEmpty
        ? 'info@nexora.cloud'
        : widget.userEmail.trim();
    return const [
      _ThreadsAccount(
        id: 'nexora',
        label: 'Nexora',
        domain: 'nexora.cloud',
        color: Color(0xFFD2B48C),
        unread: 18,
      ),
      _ThreadsAccount(
        id: 'exchange',
        label: 'Interscambio',
        domain: 'mail gateway',
        color: Color(0xFF7C5CFA),
        unread: 7,
      ),
      _ThreadsAccount(
        id: 'operations',
        label: 'Operations',
        domain: 'team workspace',
        color: Color(0xFF5FD1B5),
        unread: 11,
      ),
    ].map((account) {
      if (account.id != 'nexora') return account;
      return account.copyWith(domain: email);
    }).toList();
  }

  List<_ThreadMessage> _buildThreads() {
    final companies = widget.workspace.companies.take(4).toList();
    final fallback = [
      const Company(
        id: 'demo-1',
        name: 'Gweb Agency',
        vatNumber: '',
        taxCode: '',
        pec: '',
        sdiCode: '',
        email: 'amministrazione@gweb.agency',
        phone: '',
        website: '',
        addressLine: '',
        city: 'Milano',
        postalCode: '',
        country: 'IT',
        contactPerson: 'Riccardo Sacchetto',
        notes: '',
      ),
      const Company(
        id: 'demo-2',
        name: 'Studio Fornitori',
        vatNumber: '',
        taxCode: '',
        pec: '',
        sdiCode: '',
        email: 'fornitori@example.com',
        phone: '',
        website: '',
        addressLine: '',
        city: 'Verona',
        postalCode: '',
        country: 'IT',
        contactPerson: 'Ufficio Acquisti',
        notes: '',
      ),
    ];
    final pool = companies.isEmpty ? fallback : companies;
    final now = DateTime.now();
    return [
      _ThreadMessage(
        id: 't-1',
        accountId: 'nexora',
        mailbox: 'inbox',
        sender: pool[0].contactPerson.isEmpty
            ? pool[0].name
            : pool[0].contactPerson,
        senderEmail: pool[0].email.isEmpty
            ? 'cliente@azienda.it'
            : pool[0].email,
        subject: 'Documentazione aggiornata per ${pool[0].name}',
        preview:
            'Abbiamo raccolto i file mancanti. Ti lascio qui un riepilogo operativo e le prossime azioni da confermare.',
        body:
            'Ciao,\n\nabbiamo caricato la documentazione aggiornata e preparato il riepilogo per la pratica. Mancano solo la conferma del referente e l ultimo prospetto firmato.\n\nNel prossimo step Threads potra collegare automaticamente questo messaggio alla societa, al progetto e al task collegato.\n\nA presto.',
        time: now.subtract(const Duration(minutes: 18)),
        unread: true,
        flagged: true,
        tags: const ['Cliente', 'Documenti'],
      ),
      _ThreadMessage(
        id: 't-2',
        accountId: 'exchange',
        mailbox: 'inbox',
        sender: 'Gateway Interscambio',
        senderEmail: 'dns@nexora.cloud',
        subject: 'Setup DNS e verifica dominio',
        preview:
            'Record MX, SPF, DKIM e DMARC pronti per essere verificati quando abiliteremo il canale email reale.',
        body:
            'Simulazione tecnica:\n\n- MX dedicato per Nexora Threads\n- SPF allineato al gateway\n- DKIM per firma messaggi\n- DMARC in monitoraggio\n\nQuesta vista anticipa il pannello che useremo per collegare i domini cliente al sistema di interscambio.',
        time: now.subtract(const Duration(hours: 2)),
        unread: true,
        flagged: false,
        tags: const ['DNS', 'Setup'],
      ),
      _ThreadMessage(
        id: 't-3',
        accountId: 'operations',
        mailbox: 'inbox',
        sender: 'Team Operations',
        senderEmail: 'operations@nexora.cloud',
        subject: 'Follow-up opportunita in preventivazione',
        preview:
            'Tre opportunita richiedono risposta entro questa settimana. Ho preparato le bozze di thread da inviare.',
        body:
            'Buongiorno,\n\nle opportunita in preventivazione sono state raggruppate in thread operativi. Ogni conversazione potra diventare un task, un memo o un preventivo senza uscire dal desktop.\n\nPriorita: alta.',
        time: now.subtract(const Duration(hours: 5)),
        unread: false,
        flagged: true,
        tags: const ['Commerciale'],
      ),
      _ThreadMessage(
        id: 't-4',
        accountId: 'nexora',
        mailbox: 'sent',
        sender: 'Nexora',
        senderEmail: widget.userEmail,
        subject: 'Invio riepilogo operativo',
        preview:
            'Ti confermo che abbiamo preso in carico la richiesta e collegato il thread al progetto.',
        body:
            'Messaggio inviato:\n\nconfermiamo la presa in carico. Il thread resta collegato alla scheda progetto e sara consultabile dal sistema operativo Nexora.',
        time: now.subtract(const Duration(days: 1, hours: 3)),
        unread: false,
        flagged: false,
        tags: const ['Inviata'],
      ),
      _ThreadMessage(
        id: 't-5',
        accountId: 'exchange',
        mailbox: 'drafts',
        sender: 'Bozza',
        senderEmail: widget.userEmail,
        subject: 'Richiesta integrazione documenti',
        preview:
            'Gentile cliente, per procedere abbiamo bisogno dei seguenti allegati...',
        body:
            'Bozza messaggio:\n\nGentile cliente,\nper procedere abbiamo bisogno dei documenti integrativi indicati nel riepilogo allegato.\n\nCordiali saluti.',
        time: now.subtract(const Duration(days: 2)),
        unread: false,
        flagged: false,
        tags: const ['Bozza'],
      ),
    ];
  }

  List<_ThreadMessage> get _filteredThreads {
    final mailbox = _mailboxId;
    final query = _query.trim().toLowerCase();
    return _threads.where((thread) {
      final mailboxOk = switch (mailbox) {
        'inbox-all' => thread.mailbox == 'inbox',
        'flagged' => thread.flagged,
        'drafts-all' => thread.mailbox == 'drafts',
        'sent-all' => thread.mailbox == 'sent',
        'trash-all' => thread.mailbox == 'trash',
        _ when mailbox.startsWith('account:') =>
          thread.accountId == mailbox.substring('account:'.length) &&
              thread.mailbox == 'inbox',
        _ when mailbox.startsWith('sent-') =>
          thread.accountId == mailbox.substring('sent-'.length) &&
              thread.mailbox == 'sent',
        _ when mailbox.startsWith('drafts-') =>
          thread.accountId == mailbox.substring('drafts-'.length) &&
              thread.mailbox == 'drafts',
        _ => true,
      };
      if (!mailboxOk) return false;
      if (query.isEmpty) return true;
      return thread.sender.toLowerCase().contains(query) ||
          thread.subject.toLowerCase().contains(query) ||
          thread.preview.toLowerCase().contains(query);
    }).toList();
  }

  _ThreadMessage get _selectedThread {
    final visible = _filteredThreads;
    if (visible.any((thread) => thread.id == _selectedThreadId)) {
      return visible.firstWhere((thread) => thread.id == _selectedThreadId);
    }
    if (visible.isNotEmpty) return visible.first;
    return _threads.first;
  }

  // ── Mailbox label helper ───────────────────────────────────────────────────

  String get _mailboxLabel {
    return switch (_mailboxId) {
      'inbox-all' => 'In arrivo',
      'flagged' => 'In evidenza',
      'sent-all' => 'Inviata',
      'drafts-all' => 'Bozze',
      'trash-all' => 'Cestino',
      _ when _mailboxId.startsWith('account:') =>
        _accounts
            .where((a) => a.id == _mailboxId.substring('account:'.length))
            .firstOrNull
            ?.label ??
        'Casella',
      _ => 'In arrivo',
    };
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final visibleThreads = _filteredThreads;
    final selected = _selectedThread;

    final outerDecoration = BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          GussoniBrand.glassSurfaceStrong.withValues(alpha: .88),
          GussoniBrand.glassSurfaceMuted.withValues(alpha: .70),
          const Color(0xFFD2B48C).withValues(alpha: .08),
        ],
      ),
      borderRadius: BorderRadius.circular(24),
      border: Border.all(color: Colors.white.withValues(alpha: .70)),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < 600;

        if (isMobile) {
          return Container(
            decoration: outerDecoration,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 280),
                transitionBuilder: (child, anim) {
                  final isReader =
                      child.key == const ValueKey('reader');
                  return SlideTransition(
                    position: Tween<Offset>(
                      begin: Offset(isReader ? 1 : -0.3, 0),
                      end: Offset.zero,
                    ).animate(
                      CurvedAnimation(
                        parent: anim,
                        curve: Curves.easeOutCubic,
                      ),
                    ),
                    child: FadeTransition(opacity: anim, child: child),
                  );
                },
                child: _mobileShowReader
                    ? KeyedSubtree(
                        key: const ValueKey('reader'),
                        child: _buildMobileReader(selected),
                      )
                    : KeyedSubtree(
                        key: const ValueKey('list'),
                        child: _buildMobileList(visibleThreads),
                      ),
              ),
            ),
          );
        }

        // ── Desktop / tablet: layout a 3 colonne ──────────────────────────
        final compact = constraints.maxWidth < 760;
        final sidebarWidth = compact ? 188.0 : 238.0;
        final listWidth = compact ? 266.0 : 350.0;
        return Container(
          decoration: outerDecoration,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: Row(
              children: [
                SizedBox(
                  width: sidebarWidth,
                  child: _ThreadsSidebar(
                    accounts: _accounts,
                    selectedMailbox: _mailboxId,
                    onSelect: (id) => setState(() => _mailboxId = id),
                  ),
                ),
                _ThreadsDivider(),
                SizedBox(
                  width: listWidth,
                  child: _ThreadsListPane(
                    threads: visibleThreads,
                    selectedId: selected.id,
                    query: _query,
                    onQueryChanged: (value) => setState(() => _query = value),
                    onSelect: (thread) =>
                        setState(() => _selectedThreadId = thread.id),
                  ),
                ),
                _ThreadsDivider(),
                Expanded(child: _ThreadReader(thread: selected)),
              ],
            ),
          ),
        );
      },
    );
  }

  // ── Mobile: lista thread ──────────────────────────────────────────────────

  Widget _buildMobileList(List<_ThreadMessage> threads) {
    return Column(
      children: [
        // Header con mailbox selector
        Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 12, 12),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: .34),
            border: Border(
              bottom: BorderSide(color: Colors.white.withValues(alpha: .50)),
            ),
          ),
          child: Row(
            children: [
              // Mailbox selector (dropdown)
              Expanded(
                child: PopupMenuButton<String>(
                  onSelected: (id) => setState(() {
                    _mailboxId = id;
                    _mobileShowReader = false;
                  }),
                  itemBuilder: (_) => [
                    _mailboxItem('inbox-all', Icons.inbox_rounded, 'In arrivo (tutte)'),
                    _mailboxItem('flagged', Icons.flag_rounded, 'In evidenza'),
                    const PopupMenuDivider(),
                    for (final acc in _accounts)
                      _mailboxItem(
                        'account:${acc.id}',
                        Icons.circle,
                        acc.label,
                      ),
                    const PopupMenuDivider(),
                    _mailboxItem('sent-all', Icons.send_rounded, 'Inviata'),
                    _mailboxItem('drafts-all', Icons.edit_rounded, 'Bozze'),
                    _mailboxItem('trash-all', Icons.delete_outline_rounded, 'Cestino'),
                  ],
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _mailboxLabel,
                        style: const TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w900,
                          color: GussoniBrand.textPrimary,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(
                        Icons.expand_more_rounded,
                        size: 20,
                        color: GussoniBrand.textMuted,
                      ),
                    ],
                  ),
                ),
              ),
              _ToolbarButton(
                icon: Icons.tune_rounded,
                tooltip: 'Filtri',
                onTap: () {},
              ),
              const SizedBox(width: 4),
              _ToolbarButton(
                icon: Icons.edit_square,
                tooltip: 'Nuovo thread',
                onTap: () {},
              ),
            ],
          ),
        ),

        // Search
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
          child: TextField(
            onChanged: (v) => setState(() => _query = v),
            decoration: InputDecoration(
              hintText: 'Cerca...',
              prefixIcon: const Icon(Icons.search_rounded, size: 18),
              filled: true,
              fillColor: Colors.white.withValues(alpha: .50),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.white.withValues(alpha: .60)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.white.withValues(alpha: .60)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: GussoniBrand.primary),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
              isDense: true,
            ),
          ),
        ),

        // Thread list
        Expanded(
          child: threads.isEmpty
              ? const Center(
                  child: Text(
                    'Nessun thread trovato.',
                    style: TextStyle(
                      color: GussoniBrand.textMuted,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(10, 0, 10, 16),
                  itemCount: threads.length,
                  separatorBuilder: (_, __) => Divider(
                    height: 1,
                    indent: 56,
                    color: Colors.white.withValues(alpha: .40),
                  ),
                  itemBuilder: (_, i) {
                    final thread = threads[i];
                    return _ThreadListTile(
                      thread: thread,
                      selected: thread.id == _selectedThreadId,
                      onTap: () => setState(() {
                        _selectedThreadId = thread.id;
                        _mobileShowReader = true;
                      }),
                    );
                  },
                ),
        ),
      ],
    );
  }

  PopupMenuItem<String> _mailboxItem(String id, IconData icon, String label) {
    return PopupMenuItem<String>(
      value: id,
      child: Row(
        children: [
          Icon(icon, size: 16, color: GussoniBrand.textMuted),
          const SizedBox(width: 10),
          Text(label),
        ],
      ),
    );
  }

  // ── Mobile: lettore thread ────────────────────────────────────────────────

  Widget _buildMobileReader(_ThreadMessage thread) {
    return Container(
      color: Colors.white.withValues(alpha: .26),
      child: Column(
        children: [
          // Nav bar
          Container(
            height: 56,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .28),
              border: Border(
                bottom: BorderSide(color: Colors.white.withValues(alpha: .54)),
              ),
            ),
            child: Row(
              children: [
                // Back button
                TextButton.icon(
                  onPressed: () => setState(() => _mobileShowReader = false),
                  icon: Icon(
                    Icons.chevron_left_rounded,
                    color: GussoniBrand.primary,
                    size: 22,
                  ),
                  label: Text(
                    _mailboxLabel,
                    style: TextStyle(
                      color: GussoniBrand.primary,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 6,
                    ),
                  ),
                ),
                const Spacer(),
                // Azioni compatte
                _ToolbarButton(
                  icon: Icons.reply_rounded,
                  tooltip: 'Rispondi',
                  onTap: () {},
                ),
                const SizedBox(width: 4),
                _ToolbarButton(
                  icon: Icons.archive_rounded,
                  tooltip: 'Archivia',
                  onTap: () {},
                ),
                const SizedBox(width: 4),
                _ToolbarButton(
                  icon: Icons.more_horiz_rounded,
                  tooltip: 'Altro',
                  onTap: () {},
                ),
              ],
            ),
          ),
          // Contenuto
          Expanded(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Tags
                  if (thread.tags.isNotEmpty) ...[
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final tag in thread.tags) _ThreadTag(label: tag),
                      ],
                    ),
                    const SizedBox(height: 14),
                  ],
                  // Subject
                  Text(
                    thread.subject,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      color: GussoniBrand.textPrimary,
                      height: 1.25,
                    ),
                  ),
                  const SizedBox(height: 14),
                  // Message card
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          GussoniBrand.glassSurfaceStrong.withValues(alpha: .88),
                          GussoniBrand.glassSurfaceMuted.withValues(alpha: .70),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: .72),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Sender row
                        Row(
                          children: [
                            _SenderAvatar(name: thread.sender),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    thread.sender,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 14,
                                      color: GussoniBrand.textPrimary,
                                    ),
                                  ),
                                  Text(
                                    thread.senderEmail,
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: GussoniBrand.textMuted,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                            Text(
                              _formatTime(thread.time),
                              style: const TextStyle(
                                fontSize: 11,
                                color: GussoniBrand.textMuted,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Container(
                          height: 1,
                          color: Colors.white.withValues(alpha: .60),
                        ),
                        const SizedBox(height: 14),
                        // Body
                        Text(
                          thread.body,
                          style: const TextStyle(
                            fontSize: 14,
                            height: 1.6,
                            color: GussoniBrand.textPrimary,
                          ),
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

  String _formatTime(DateTime t) {
    final now = DateTime.now();
    final diff = now.difference(t);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    if (diff.inDays < 7) return '${diff.inDays}g';
    return DateFormat('dd MMM').format(t);
  }
}

class _ThreadsSidebar extends StatelessWidget {
  const _ThreadsSidebar({
    required this.accounts,
    required this.selectedMailbox,
    required this.onSelect,
  });

  final List<_ThreadsAccount> accounts;
  final String selectedMailbox;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 14),
      decoration: BoxDecoration(color: Colors.white.withValues(alpha: .34)),
      child: ListView(
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFFD2B48C).withValues(alpha: .16),
                  border: Border.all(
                    color: const Color(0xFFD2B48C).withValues(alpha: .32),
                  ),
                ),
                child: const Icon(
                  Icons.mark_email_unread_rounded,
                  color: Color(0xFF168FA2),
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Threads',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        color: GussoniBrand.textPrimary,
                      ),
                    ),
                    Text(
                      'Mail workspace',
                      style: TextStyle(
                        fontSize: 11,
                        color: GussoniBrand.textMuted,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          const _ThreadsGroupLabel('Preferiti'),
          _MailboxTile(
            id: 'inbox-all',
            label: 'In entrata',
            icon: Icons.inbox_rounded,
            count: 82,
            selected: selectedMailbox == 'inbox-all',
            onTap: onSelect,
          ),
          _MailboxTile(
            id: 'flagged',
            label: 'Contrassegnate',
            icon: Icons.flag_rounded,
            count: 17,
            selected: selectedMailbox == 'flagged',
            onTap: onSelect,
          ),
          _MailboxTile(
            id: 'drafts-all',
            label: 'Bozze',
            icon: Icons.drafts_rounded,
            count: 9,
            selected: selectedMailbox == 'drafts-all',
            onTap: onSelect,
          ),
          _MailboxTile(
            id: 'sent-all',
            label: 'Inviate',
            icon: Icons.send_rounded,
            selected: selectedMailbox == 'sent-all',
            onTap: onSelect,
          ),
          const SizedBox(height: 18),
          const _ThreadsGroupLabel('Caselle smart'),
          for (final account in accounts) ...[
            _AccountHeader(account: account),
            _MailboxTile(
              id: 'account:${account.id}',
              label: 'In entrata',
              icon: Icons.all_inbox_rounded,
              count: account.unread,
              selected: selectedMailbox == 'account:${account.id}',
              onTap: onSelect,
              dense: true,
            ),
            _MailboxTile(
              id: 'sent-${account.id}',
              label: 'Inviata',
              icon: Icons.near_me_rounded,
              selected: selectedMailbox == 'sent-${account.id}',
              onTap: onSelect,
              dense: true,
            ),
            _MailboxTile(
              id: 'drafts-${account.id}',
              label: 'Bozze',
              icon: Icons.note_alt_rounded,
              selected: selectedMailbox == 'drafts-${account.id}',
              onTap: onSelect,
              dense: true,
            ),
            const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}

class _ThreadsListPane extends StatelessWidget {
  const _ThreadsListPane({
    required this.threads,
    required this.selectedId,
    required this.query,
    required this.onQueryChanged,
    required this.onSelect,
  });

  final List<_ThreadMessage> threads;
  final String selectedId;
  final String query;
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<_ThreadMessage> onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white.withValues(alpha: .18),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Conversazioni',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                          color: GussoniBrand.textPrimary,
                        ),
                      ),
                    ),
                    _ToolbarButton(
                      icon: Icons.tune_rounded,
                      tooltip: 'Filtri',
                      onTap: () {},
                    ),
                    const SizedBox(width: 6),
                    _ToolbarButton(
                      icon: Icons.edit_square,
                      tooltip: 'Nuovo thread',
                      onTap: () {},
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  onChanged: onQueryChanged,
                  decoration: const InputDecoration(
                    hintText: 'Cerca thread, mittenti, oggetti...',
                    prefixIcon: Icon(Icons.search_rounded, size: 18),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: threads.isEmpty
                ? const Center(
                    child: Text(
                      'Nessun thread trovato.',
                      style: TextStyle(
                        color: GussoniBrand.textMuted,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(10, 0, 10, 14),
                    itemCount: threads.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final thread = threads[index];
                      return _ThreadListTile(
                        thread: thread,
                        selected: thread.id == selectedId,
                        onTap: () => onSelect(thread),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _ThreadReader extends StatelessWidget {
  const _ThreadReader({required this.thread});

  final _ThreadMessage thread;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white.withValues(alpha: .26),
      child: Column(
        children: [
          Container(
            height: 62,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .28),
              border: Border(
                bottom: BorderSide(color: Colors.white.withValues(alpha: .54)),
              ),
            ),
            child: Row(
              children: [
                _ToolbarButton(
                  icon: Icons.archive_rounded,
                  tooltip: 'Archivia',
                  onTap: () {},
                ),
                const SizedBox(width: 6),
                _ToolbarButton(
                  icon: Icons.delete_outline_rounded,
                  tooltip: 'Elimina',
                  onTap: () {},
                ),
                const SizedBox(width: 6),
                _ToolbarButton(
                  icon: Icons.reply_rounded,
                  tooltip: 'Rispondi',
                  onTap: () {},
                ),
                const SizedBox(width: 6),
                _ToolbarButton(
                  icon: Icons.forward_rounded,
                  tooltip: 'Inoltra',
                  onTap: () {},
                ),
                const Spacer(),
                _ToolbarButton(
                  icon: Icons.flag_rounded,
                  tooltip: 'Contrassegna',
                  onTap: () {},
                ),
                const SizedBox(width: 6),
                _ToolbarButton(
                  icon: Icons.more_horiz_rounded,
                  tooltip: 'Altro',
                  onTap: () {},
                ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final tag in thread.tags) _ThreadTag(label: tag),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    thread.subject,
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                      color: GussoniBrand.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          GussoniBrand.glassSurfaceStrong.withValues(
                            alpha: .88,
                          ),
                          GussoniBrand.glassSurfaceMuted.withValues(alpha: .70),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: .72),
                      ),
                    ),
                    child: Row(
                      children: [
                        _SenderAvatar(name: thread.sender),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                thread.sender,
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w900,
                                  color: GussoniBrand.textPrimary,
                                ),
                              ),
                              Text(
                                thread.senderEmail,
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: GussoniBrand.textMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          DateFormat('dd/MM HH:mm').format(thread.time),
                          style: const TextStyle(
                            fontSize: 12,
                            color: GussoniBrand.textMuted,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: .48),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: .72),
                      ),
                    ),
                    child: Text(
                      thread.body,
                      style: const TextStyle(
                        fontSize: 14,
                        height: 1.58,
                        color: GussoniBrand.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _ThreadSystemHint(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MailboxTile extends StatelessWidget {
  const _MailboxTile({
    required this.id,
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
    this.count,
    this.dense = false,
  });

  final String id;
  final String label;
  final IconData icon;
  final int? count;
  final bool selected;
  final bool dense;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: dense ? 3 : 5),
    child: InkWell(
      onTap: () => onTap(id),
      borderRadius: BorderRadius.circular(14),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: EdgeInsets.symmetric(
          horizontal: dense ? 8 : 10,
          vertical: dense ? 7 : 9,
        ),
        decoration: BoxDecoration(
          color: selected
              ? GussoniBrand.primary.withValues(alpha: .14)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected
                ? GussoniBrand.primary.withValues(alpha: .26)
                : Colors.transparent,
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 16,
              color: selected ? GussoniBrand.primary : const Color(0xFF168FA2),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: dense ? 12 : 13,
                  fontWeight: selected ? FontWeight.w900 : FontWeight.w700,
                  color: selected
                      ? GussoniBrand.textPrimary
                      : GussoniBrand.textSecondary,
                ),
              ),
            ),
            if (count != null && count! > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .58),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '$count',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    color: GussoniBrand.textMuted,
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

class _ThreadListTile extends StatelessWidget {
  const _ThreadListTile({
    required this.thread,
    required this.selected,
    required this.onTap,
  });

  final _ThreadMessage thread;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(18),
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        gradient: selected
            ? LinearGradient(
                colors: [
                  Colors.white.withValues(alpha: .78),
                  const Color(0xFFF6E9E3).withValues(alpha: .64),
                ],
              )
            : null,
        color: selected ? null : Colors.white.withValues(alpha: .40),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: selected
              ? GussoniBrand.primary.withValues(alpha: .28)
              : Colors.white.withValues(alpha: .58),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _SenderAvatar(name: thread.sender, small: true),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  thread.sender,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: thread.unread
                        ? FontWeight.w900
                        : FontWeight.w700,
                    color: GussoniBrand.textPrimary,
                  ),
                ),
              ),
              Text(
                DateFormat('HH:mm').format(thread.time),
                style: const TextStyle(
                  fontSize: 11,
                  color: GussoniBrand.textMuted,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 9),
          Text(
            thread.subject,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              fontWeight: thread.unread ? FontWeight.w900 : FontWeight.w700,
              color: GussoniBrand.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            thread.preview,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 12,
              height: 1.25,
              color: GussoniBrand.textMuted,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    ),
  );
}

class _ThreadsDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) =>
      Container(width: 1, color: Colors.white.withValues(alpha: .56));
}

class _ToolbarButton extends StatelessWidget {
  const _ToolbarButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(13),
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: .48),
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: Colors.white.withValues(alpha: .66)),
        ),
        child: Icon(icon, size: 17, color: GussoniBrand.textSecondary),
      ),
    ),
  );
}

class _SenderAvatar extends StatelessWidget {
  const _SenderAvatar({required this.name, this.small = false});

  final String name;
  final bool small;

  @override
  Widget build(BuildContext context) {
    final size = small ? 28.0 : 42.0;
    final initials = name
        .trim()
        .split(' ')
        .where((part) => part.isNotEmpty)
        .take(2)
        .map((part) => part[0].toUpperCase())
        .join();
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: [
            GussoniBrand.primary.withValues(alpha: .22),
            const Color(0xFFD2B48C).withValues(alpha: .18),
          ],
        ),
        border: Border.all(color: Colors.white.withValues(alpha: .72)),
      ),
      child: Center(
        child: Text(
          initials.isEmpty ? '?' : initials,
          style: TextStyle(
            color: GussoniBrand.primary,
            fontSize: small ? 10 : 14,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}

class _ThreadTag extends StatelessWidget {
  const _ThreadTag({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: GussoniBrand.primary.withValues(alpha: .10),
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: GussoniBrand.primary.withValues(alpha: .22)),
    ),
    child: Text(
      label,
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w900,
        color: GussoniBrand.primary,
      ),
    ),
  );
}

class _ThreadSystemHint extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: const Color(0xFFD2B48C).withValues(alpha: .10),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: const Color(0xFFD2B48C).withValues(alpha: .22)),
    ),
    child: const Row(
      children: [
        Icon(Icons.dns_rounded, size: 18, color: Color(0xFF168FA2)),
        SizedBox(width: 10),
        Expanded(
          child: Text(
            'Preview client: in seguito qui collegheremo domini, record DNS e caselle reali al sistema di interscambio Nexora.',
            style: TextStyle(
              fontSize: 12,
              color: GussoniBrand.textSecondary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    ),
  );
}

class _ThreadsGroupLabel extends StatelessWidget {
  const _ThreadsGroupLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 0, 4, 7),
    child: Text(
      label,
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w900,
        color: GussoniBrand.textMuted,
      ),
    ),
  );
}

class _AccountHeader extends StatelessWidget {
  const _AccountHeader({required this.account});

  final _ThreadsAccount account;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 10, 4, 6),
    child: Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: account.color,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            '${account.label} / ${account.domain}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w900,
              color: GussoniBrand.textMuted,
            ),
          ),
        ),
      ],
    ),
  );
}

class _ThreadsAccount {
  const _ThreadsAccount({
    required this.id,
    required this.label,
    required this.domain,
    required this.color,
    required this.unread,
  });

  final String id;
  final String label;
  final String domain;
  final Color color;
  final int unread;

  _ThreadsAccount copyWith({String? domain}) => _ThreadsAccount(
    id: id,
    label: label,
    domain: domain ?? this.domain,
    color: color,
    unread: unread,
  );
}

class _ThreadMessage {
  const _ThreadMessage({
    required this.id,
    required this.accountId,
    required this.mailbox,
    required this.sender,
    required this.senderEmail,
    required this.subject,
    required this.preview,
    required this.body,
    required this.time,
    required this.unread,
    required this.flagged,
    required this.tags,
  });

  final String id;
  final String accountId;
  final String mailbox;
  final String sender;
  final String senderEmail;
  final String subject;
  final String preview;
  final String body;
  final DateTime time;
  final bool unread;
  final bool flagged;
  final List<String> tags;
}
