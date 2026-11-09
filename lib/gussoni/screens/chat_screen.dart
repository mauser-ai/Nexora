import 'dart:async';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:intl/intl.dart';

import '../../brand_config.dart';
import '../../data/chat_api_repository.dart';
import '../../data/chat_event_stream_base.dart';
import '../../models/chat_models.dart';
import '../../data/team_repository.dart';

class TeamChatScreen extends StatefulWidget {
  const TeamChatScreen({
    super.key,
    required this.currentUserId,
    required this.repository,
    required this.members,
  });

  final String currentUserId;
  final ChatApiRepository repository;
  final List<TeamMember> members;

  @override
  State<TeamChatScreen> createState() => _TeamChatScreenState();
}

enum _ChatCollectionFilter { home, direct, group }

enum _AvailabilityStatus { available, breakTime, unavailable }

class _TeamChatScreenState extends State<TeamChatScreen> {
  static const double _minRailWidth = 220;
  static const double _maxRailWidth = 360;
  static const double _minListWidth = 300;
  static const double _maxListWidth = 520;
  static FlutterSecureStorage get _storage => const FlutterSecureStorage(
    webOptions: WebOptions(dbName: 'nexora_crm', publicKey: 'NexoraCRM'),
  );

  final _composerCtrl = TextEditingController();
  final _searchCtrl = TextEditingController();
  final _messageScrollCtrl = ScrollController();
  ChatEventStream? _realtimeStream;
  StreamSubscription<ChatRealtimeEvent>? _realtimeSub;
  Timer? _reconnectTimer;

  bool _loading = true;
  bool _sending = false;
  String? _lastError;
  List<ChatGroup> _groups = const [];
  List<ChatMessage> _messages = const [];
  String? _selectedGroupId;
  String _searchQuery = '';
  _ChatCollectionFilter _collectionFilter = _ChatCollectionFilter.home;
  _AvailabilityStatus _availabilityStatus = _AvailabilityStatus.available;
  Set<String> _pinnedGroupIds = const {};
  double _railWidth = 278;
  double _listWidth = 372;

  static const _chatBg = Color(0xFFF7F7F7);
  static const _chatRail = Color(0xEEF7F7F7);
  static const _chatPanel = Color(0xFFFDFDFD);
  static const _chatPanelAlt = Color(0xFFF4F7F5);
  static const _chatBorder = Color(0xFFD4E1DC);
  static const _chatText = Color(0xFF02332A);
  static const _chatMuted = Color(0xFF6B847E);
  static const _chatAccent = Color(0xFFACCF78);
  static const _chatAccentSoft = Color(0xFFF1F8E7);
  static const _chatMe = Color(0xFFF2F7F5);
  static const _chatThem = Color(0xFFF4F7F5);

  ChatGroup? get _selectedGroup =>
      _groups.where((group) => group.id == _selectedGroupId).firstOrNull;

  List<TeamMember> get _activeMembers =>
      widget.members.where((member) => member.status == 'active').toList()
        ..sort(
          (a, b) => a.displayName.toLowerCase().compareTo(
            b.displayName.toLowerCase(),
          ),
        );

  List<ChatGroup> get _directGroups =>
      _groups.where(_isDirectGroup).toList()..sort(_sortGroupsByActivity);

  List<ChatGroup> get _spaceGroups =>
      _groups.where((group) => !_isDirectGroup(group)).toList()
        ..sort(_sortGroupsByActivity);

  List<ChatGroup> get _visibleGroups {
    final base = switch (_collectionFilter) {
      _ChatCollectionFilter.home => _groups,
      _ChatCollectionFilter.direct => _directGroups,
      _ChatCollectionFilter.group => _spaceGroups,
    }..sort(_sortGroupsByActivity);
    if (_searchQuery.isEmpty) {
      return base;
    }
    final query = _searchQuery.toLowerCase();
    return base.where((group) {
      final haystacks = <String>[
        _groupTitle(group),
        group.lastMessageSnippet,
        group.description,
        ...group.members.map((member) => member.displayName),
      ];
      return haystacks.any((value) => value.toLowerCase().contains(query));
    }).toList();
  }

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(_handleSearchChanged);
    unawaited(_loadUiPreferences());
    unawaited(_initializeChat());
  }

  @override
  void dispose() {
    _realtimeSub?.cancel();
    _realtimeStream?.close();
    _reconnectTimer?.cancel();
    _composerCtrl.dispose();
    _searchCtrl
      ..removeListener(_handleSearchChanged)
      ..dispose();
    _messageScrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _initializeChat() async {
    await _refresh();
    await _connectRealtime();
  }

  Future<void> _connectRealtime() async {
    await _realtimeSub?.cancel();
    _realtimeStream?.close();
    try {
      final stream = await widget.repository.openRealtimeStream();
      _realtimeStream = stream;
      _realtimeSub = stream.events.listen(_handleRealtimeEvent);
    } catch (_) {
      _scheduleRealtimeReconnect();
    }
  }

  void _scheduleRealtimeReconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 5), () {
      if (!mounted) {
        return;
      }
      unawaited(_connectRealtime());
    });
  }

  void _handleRealtimeEvent(ChatRealtimeEvent event) {
    if (!mounted) {
      return;
    }
    if (event.type == 'stream_error' || event.type == 'redis_unavailable') {
      _scheduleRealtimeReconnect();
      return;
    }
    if (event.type == 'connected') {
      return;
    }
    unawaited(_refresh());
  }

  void _handleSearchChanged() {
    final query = _searchCtrl.text.trim();
    if (query == _searchQuery) {
      return;
    }
    setState(() => _searchQuery = query);
  }

  Future<void> _refresh() async {
    try {
      final groups = await widget.repository.fetchGroups();
      String? selectedId = _selectedGroupId;
      if (selectedId != null &&
          !groups.any((group) => group.id == selectedId)) {
        selectedId = null;
      }
      if (selectedId == null && groups.isNotEmpty) {
        selectedId = _pickPreferredGroup(groups).id;
      }
      List<ChatMessage> messages = const [];
      if (selectedId != null) {
        messages = await widget.repository.fetchMessages(selectedId);
        await widget.repository.markGroupRead(selectedId);
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _groups = groups;
        _selectedGroupId = selectedId;
        _messages = messages;
        _loading = false;
        _lastError = null;
      });
      _scrollMessagesToBottom();
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _lastError = error.toString();
      });
    }
  }

  ChatGroup _pickPreferredGroup(List<ChatGroup> groups) {
    final sorted = [...groups]..sort(_sortGroupsByActivity);
    return sorted.first;
  }

  Future<void> _selectGroup(ChatGroup group) async {
    if (_selectedGroupId == group.id) {
      return;
    }
    setState(() => _selectedGroupId = group.id);
    await _refresh();
  }

  Future<void> _sendMessage() async {
    final text = _composerCtrl.text.trim();
    final groupId = _selectedGroupId;
    if (text.isEmpty || groupId == null || _sending) {
      return;
    }
    setState(() => _sending = true);
    try {
      await widget.repository.sendMessage(groupId: groupId, body: text);
      _composerCtrl.clear();
      await _refresh();
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Invio messaggio: $error')));
    } finally {
      if (mounted) {
        setState(() => _sending = false);
      }
    }
  }

  Future<void> _openCreateChatDialog() async {
    final action = await showDialog<_ChatDialogAction>(
      context: context,
      builder: (_) => _CreateChatDialog(
        members: _activeMembers,
        currentUserId: widget.currentUserId,
        repository: widget.repository,
      ),
    );
    if (action == null) {
      return;
    }
    switch (action) {
      case _OpenExistingDirectAction(:final memberId):
        await _openDirectChat(memberId);
      case _CreatedGroupAction(:final groupId):
        await _refresh();
        if (!mounted) {
          return;
        }
        setState(() {
          _selectedGroupId = groupId;
          _collectionFilter = _ChatCollectionFilter.group;
        });
        await _refresh();
    }
  }

  Future<void> _openDirectChat(String memberId) async {
    final member = _activeMembers
        .where((item) => item.userId == memberId)
        .firstOrNull;
    if (member == null) {
      return;
    }
    final existing = _directGroups.firstWhere(
      (group) => group.members.any((item) => item.userId == memberId),
      orElse: () => ChatGroup(
        id: '',
        name: '',
        description: '',
        createdAt: DateTime.fromMillisecondsSinceEpoch(0),
        members: [],
      ),
    );
    if (existing.id.isNotEmpty) {
      setState(() {
        _collectionFilter = _ChatCollectionFilter.direct;
      });
      await _selectGroup(existing);
      return;
    }
    try {
      final self = _activeMembers.firstWhere(
        (item) => item.userId == widget.currentUserId,
        orElse: () => TeamMember(
          userId: widget.currentUserId,
          email: '',
          displayName: 'Tu',
          role: '',
          status: 'active',
        ),
      );
      final sortedIds = [widget.currentUserId, memberId]..sort();
      final created = await widget.repository.createGroup(
        name: member.displayName,
        description: '__direct__:${sortedIds.join(':')}',
        members: [self, member]
            .map(
              (item) => {
                'userId': item.userId,
                'displayName': item.displayName,
                'email': item.email,
                'role': item.role,
              },
            )
            .toList(),
      );
      await _refresh();
      if (!mounted) {
        return;
      }
      setState(() {
        _collectionFilter = _ChatCollectionFilter.direct;
        _selectedGroupId = created.id;
      });
      await _refresh();
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Apertura chat diretta: $error')));
    }
  }

  bool _isDirectGroup(ChatGroup group) {
    if (group.description.startsWith('__direct__')) {
      return true;
    }
    return group.members.length == 2;
  }

  int _sortGroupsByActivity(ChatGroup a, ChatGroup b) {
    final aPinned = _pinnedGroupIds.contains(a.id);
    final bPinned = _pinnedGroupIds.contains(b.id);
    if (aPinned != bPinned) {
      return aPinned ? -1 : 1;
    }
    final aDate = a.lastMessageAt ?? a.createdAt;
    final bDate = b.lastMessageAt ?? b.createdAt;
    return bDate.compareTo(aDate);
  }

  Future<void> _loadUiPreferences() async {
    try {
      final pinnedRaw = await _storage.read(
        key: 'chat_pinned_${widget.currentUserId}',
      );
      final statusRaw = await _storage.read(
        key: 'chat_status_${widget.currentUserId}',
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _pinnedGroupIds = pinnedRaw == null || pinnedRaw.trim().isEmpty
            ? <String>{}
            : pinnedRaw
                  .split(',')
                  .map((item) => item.trim())
                  .where((item) => item.isNotEmpty)
                  .toSet();
        _availabilityStatus = _AvailabilityStatus.values.firstWhere(
          (value) => value.name == statusRaw,
          orElse: () => _AvailabilityStatus.available,
        );
      });
    } catch (_) {}
  }

  Future<void> _savePinnedPreferences() async {
    try {
      await _storage.write(
        key: 'chat_pinned_${widget.currentUserId}',
        value: _pinnedGroupIds.join(','),
      );
    } catch (_) {}
  }

  Future<void> _saveStatusPreference() async {
    try {
      await _storage.write(
        key: 'chat_status_${widget.currentUserId}',
        value: _availabilityStatus.name,
      );
    } catch (_) {}
  }

  void _togglePin(String groupId) {
    setState(() {
      final next = {..._pinnedGroupIds};
      if (!next.add(groupId)) {
        next.remove(groupId);
      }
      _pinnedGroupIds = next;
    });
    unawaited(_savePinnedPreferences());
  }

  String _groupTitle(ChatGroup group) {
    if (_isDirectGroup(group)) {
      return _otherMember(group)?.displayName ?? group.name;
    }
    return group.name;
  }

  String _groupSubtitle(ChatGroup group) {
    final lastSnippet = group.lastMessageSnippet.trim();
    if (lastSnippet.isNotEmpty) {
      return lastSnippet;
    }
    if (_isDirectGroup(group)) {
      final other = _otherMember(group);
      return other?.email ?? 'Nessun messaggio';
    }
    final members = group.members
        .map((member) => member.displayName)
        .join(', ');
    return members.isEmpty ? 'Nessun messaggio' : members;
  }

  ChatGroupMember? _otherMember(ChatGroup group) {
    return group.members
        .where((member) => member.userId != widget.currentUserId)
        .firstOrNull;
  }

  TeamMember? _memberById(String userId) {
    return _activeMembers
        .where((member) => member.userId == userId)
        .firstOrNull;
  }

  String _displayTimestamp(DateTime? timestamp) {
    if (timestamp == null) {
      return '';
    }
    final now = DateTime.now();
    final sameDay =
        now.year == timestamp.year &&
        now.month == timestamp.month &&
        now.day == timestamp.day;
    if (sameDay) {
      return DateFormat('HH:mm').format(timestamp);
    }
    final yesterday = now.subtract(const Duration(days: 1));
    final isYesterday =
        yesterday.year == timestamp.year &&
        yesterday.month == timestamp.month &&
        yesterday.day == timestamp.day;
    if (isYesterday) {
      return 'Ieri';
    }
    return DateFormat('dd MMM', 'it_IT').format(timestamp);
  }

  void _resizeRail(double delta) {
    setState(() {
      _railWidth = (_railWidth + delta).clamp(_minRailWidth, _maxRailWidth);
    });
  }

  void _resizeList(double delta, double maxWidth) {
    setState(() {
      final limit = math.min(_maxListWidth, math.max(_minListWidth, maxWidth));
      _listWidth = (_listWidth + delta).clamp(_minListWidth, limit);
    });
  }

  void _scrollMessagesToBottom() {
    if (!_messageScrollCtrl.hasClients) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_messageScrollCtrl.hasClients) {
          return;
        }
        _messageScrollCtrl.jumpTo(_messageScrollCtrl.position.maxScrollExtent);
      });
      return;
    }
    _messageScrollCtrl.jumpTo(_messageScrollCtrl.position.maxScrollExtent);
  }

  Future<void> _insertTextToken(String token) async {
    final value = _composerCtrl.value;
    final selection = value.selection;
    final text = value.text;
    final start = selection.isValid ? selection.start : text.length;
    final end = selection.isValid ? selection.end : text.length;
    final prefix = start > 0 && !text.substring(0, start).endsWith(' ')
        ? ' '
        : '';
    final insert = '$prefix$token';
    final newText = text.replaceRange(start, end, insert);
    _composerCtrl.value = value.copyWith(
      text: newText,
      selection: TextSelection.collapsed(offset: start + insert.length),
    );
  }

  Future<void> _pickAttachment() async {
    final result = await FilePicker.platform.pickFiles(allowMultiple: false);
    final file = result?.files.singleOrNull;
    if (file == null) {
      return;
    }
    await _insertTextToken('[ALLEGATO:${file.name}]');
  }

  String get _availabilityLabel => switch (_availabilityStatus) {
    _AvailabilityStatus.available => 'Disponibile',
    _AvailabilityStatus.breakTime => 'In pausa',
    _AvailabilityStatus.unavailable => 'Non disponibile',
  };

  Color get _availabilityColor => switch (_availabilityStatus) {
    _AvailabilityStatus.available => Color(0xFF1F7A55),
    _AvailabilityStatus.breakTime => Color(0xFF9B7A17),
    _AvailabilityStatus.unavailable => Color(0xFFB43D34),
  };

  // Mobile: true = mostra thread, false = mostra lista conversazioni
  bool _mobileShowThread = false;

  @override
  Widget build(BuildContext context) {
    final selectedGroup = _selectedGroup;
    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < 600;

        if (isMobile) {
          return _buildMobileLayout(selectedGroup, isMobile: true);
        }

        final maxListWidth = math.max(
          _minListWidth,
          constraints.maxWidth - _railWidth - 420,
        );
        if (_listWidth > maxListWidth) {
          _listWidth = maxListWidth;
        }
        return Container(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [_chatBg, _chatPanelAlt],
            ),
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            children: [
              _ChatTopBar(
                searchController: _searchCtrl,
                statusLabel: _availabilityLabel,
                statusColor: _availabilityColor,
                onStatusSelected: (status) {
                  setState(() => _availabilityStatus = status);
                  unawaited(_saveStatusPreference());
                },
              ),
              Expanded(
                child: Row(
                  children: [
                    SizedBox(width: _railWidth, child: _buildLeftRail()),
                    _HorizontalResizeHandle(onDrag: _resizeRail),
                    SizedBox(
                      width: _listWidth,
                      child: _buildConversationList(),
                    ),
                    _HorizontalResizeHandle(
                      onDrag: (delta) => _resizeList(delta, maxListWidth),
                    ),
                    Expanded(child: _buildThreadPanel(selectedGroup)),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMobileLayout(
    ChatGroup? selectedGroup, {
    required bool isMobile,
  }) {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_chatBg, _chatPanelAlt],
        ),
        borderRadius: BorderRadius.circular(24),
      ),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 260),
        transitionBuilder: (child, anim) => SlideTransition(
          position: Tween<Offset>(
            begin: Offset(child.key == const ValueKey('list') ? -1 : 1, 0),
            end: Offset.zero,
          ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
          child: child,
        ),
        child: _mobileShowThread && selectedGroup != null
            ? KeyedSubtree(
                key: const ValueKey('thread'),
                child: _buildMobileThread(selectedGroup),
              )
            : KeyedSubtree(
                key: const ValueKey('list'),
                child: _buildMobileConversationPane(),
              ),
      ),
    );
  }

  Widget _buildMobileConversationPane() {
    final visibleGroups = _visibleGroups;
    return Column(
      children: [
        // Top bar compatto per mobile
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
          child: Row(
            children: [
              Expanded(
                child: Container(
                  height: 42,
                  decoration: BoxDecoration(
                    color: _chatPanel,
                    border: Border.all(color: _chatBorder),
                    borderRadius: BorderRadius.circular(21),
                  ),
                  child: TextField(
                    controller: _searchCtrl,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(
                        Icons.search_rounded,
                        color: _chatMuted,
                        size: 18,
                      ),
                      hintText: 'Cerca…',
                      hintStyle: TextStyle(color: _chatMuted, fontSize: 13),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      disabledBorder: InputBorder.none,
                      errorBorder: InputBorder.none,
                      focusedErrorBorder: InputBorder.none,
                      filled: false,
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(vertical: 12),
                    ),
                    style: const TextStyle(fontSize: 13, color: _chatText),
                    cursorColor: _chatAccent,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              GestureDetector(
                onTap: _openCreateChatDialog,
                child: Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: _chatAccent,
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: const Icon(
                    Icons.edit_square,
                    color: Colors.white,
                    size: 18,
                  ),
                ),
              ),
            ],
          ),
        ),
        // Filter chips
        SizedBox(
          height: 36,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              _FilterChipButton(
                label: 'Tutto',
                selected: _collectionFilter == _ChatCollectionFilter.home,
                onTap: () => setState(
                  () => _collectionFilter = _ChatCollectionFilter.home,
                ),
              ),
              const SizedBox(width: 8),
              _FilterChipButton(
                label: 'Diretti',
                selected: _collectionFilter == _ChatCollectionFilter.direct,
                onTap: () => setState(
                  () => _collectionFilter = _ChatCollectionFilter.direct,
                ),
              ),
              const SizedBox(width: 8),
              _FilterChipButton(
                label: 'Gruppi',
                selected: _collectionFilter == _ChatCollectionFilter.group,
                onTap: () => setState(
                  () => _collectionFilter = _ChatCollectionFilter.group,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        // Lista conversazioni
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _lastError != null
              ? _ErrorState(message: _lastError!)
              : visibleGroups.isEmpty
              ? const _EmptyInboxState()
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
                  itemCount: visibleGroups.length,
                  separatorBuilder: (_, __) =>
                      Divider(height: 1, indent: 56, color: _chatBorder),
                  itemBuilder: (_, i) {
                    final group = visibleGroups[i];
                    return _MobileConversationTile(
                      title: _groupTitle(group),
                      subtitle: _groupSubtitle(group),
                      timestamp: _displayTimestamp(group.lastMessageAt),
                      unreadCount: group.unreadCount,
                      selected: group.id == _selectedGroupId,
                      isDirect: _isDirectGroup(group),
                      iconText: _avatarText(group),
                      iconAccent: _avatarAccent(group),
                      pinned: _pinnedGroupIds.contains(group.id),
                      onTap: () {
                        _selectGroup(group);
                        setState(() => _mobileShowThread = true);
                      },
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildMobileThread(ChatGroup selectedGroup) {
    final isDirect = _isDirectGroup(selectedGroup);
    final participants = selectedGroup.members
        .where((m) => m.userId != widget.currentUserId)
        .map((m) => m.displayName)
        .join(', ');

    return Container(
      decoration: const BoxDecoration(
        color: _chatPanel,
        borderRadius: BorderRadius.all(Radius.circular(24)),
      ),
      child: Column(
        children: [
          // Header con back button
          Container(
            padding: const EdgeInsets.fromLTRB(8, 14, 16, 14),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: _chatBorder)),
            ),
            child: Row(
              children: [
                IconButton(
                  onPressed: () => setState(() => _mobileShowThread = false),
                  icon: const Icon(
                    Icons.chevron_left_rounded,
                    color: _chatAccent,
                    size: 28,
                  ),
                ),
                _HeaderBadge(
                  text: _avatarText(selectedGroup),
                  accent: _avatarAccent(selectedGroup),
                  isDirect: isDirect,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _groupTitle(selectedGroup),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: _chatText,
                        ),
                      ),
                      if (participants.isNotEmpty)
                        Text(
                          participants,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11,
                            color: _chatMuted,
                          ),
                        ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: _refresh,
                  icon: const Icon(
                    Icons.refresh_rounded,
                    size: 20,
                    color: _chatMuted,
                  ),
                ),
              ],
            ),
          ),
          // Messaggi
          Expanded(
            child: _messages.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        Icon(
                          Icons.chat_bubble_outline_rounded,
                          size: 32,
                          color: _chatAccent,
                        ),
                        SizedBox(height: 10),
                        Text(
                          'Nessun messaggio ancora',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: _chatText,
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    controller: _messageScrollCtrl,
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      final message = _messages[index];
                      final previous = index > 0 ? _messages[index - 1] : null;
                      final showDayMarker =
                          previous == null ||
                          !_isSameDay(previous.createdAt, message.createdAt);
                      final prev = previous;
                      final isGrouped =
                          !showDayMarker &&
                          prev != null &&
                          prev.userId == message.userId &&
                          message.createdAt
                                  .difference(prev.createdAt)
                                  .inMinutes <
                              5;
                      return Column(
                        children: [
                          if (showDayMarker)
                            _DayDivider(
                              label: _dayMarkerLabel(message.createdAt),
                            ),
                          _ChatBubble(
                            message: message,
                            currentUserId: widget.currentUserId,
                            member: _memberById(message.userId),
                            isGrouped: isGrouped,
                          ),
                        ],
                      );
                    },
                  ),
          ),
          // Composer
          _buildMobileComposer(),
        ],
      ),
    );
  }

  Widget _buildMobileComposer() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 14),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: _chatBorder)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Container(
              constraints: const BoxConstraints(maxHeight: 120),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: _chatPanelAlt,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: _chatBorder),
              ),
              child: TextField(
                controller: _composerCtrl,
                minLines: 1,
                maxLines: 5,
                onSubmitted: (_) => _sendMessage(),
                decoration: const InputDecoration(
                  hintText: 'Scrivi un messaggio…',
                  hintStyle: TextStyle(color: _chatMuted, fontSize: 14),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  disabledBorder: InputBorder.none,
                  errorBorder: InputBorder.none,
                  focusedErrorBorder: InputBorder.none,
                  isDense: true,
                  filled: false,
                  contentPadding: EdgeInsets.zero,
                ),
                style: const TextStyle(
                  fontSize: 14,
                  height: 1.4,
                  color: _chatText,
                ),
                cursorColor: _chatAccent,
              ),
            ),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: _sending ? null : _sendMessage,
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: _chatAccent,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                _sending ? Icons.more_horiz_rounded : Icons.send_rounded,
                color: Colors.white,
                size: 20,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLeftRail() {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 14, 18),
      decoration: BoxDecoration(
        color: _chatRail,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(24),
          bottomLeft: Radius.circular(24),
        ),
        border: Border(
          right: BorderSide(color: _chatBorder.withValues(alpha: .9)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FilledButton.icon(
            onPressed: _openCreateChatDialog,
            style: FilledButton.styleFrom(
              backgroundColor: _chatAccent,
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            icon: const Icon(Icons.edit_square, size: 18),
            label: const Text(
              'Nuova conversazione',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(height: 22),
          _SidebarActionTile(
            selected: _collectionFilter == _ChatCollectionFilter.home,
            icon: Icons.inbox_outlined,
            label: 'Tutte le chat',
            onTap: () =>
                setState(() => _collectionFilter = _ChatCollectionFilter.home),
          ),
          const SizedBox(height: 20),
          const _SectionTitle(title: 'Colleghi'),
          const SizedBox(height: 10),
          Expanded(
            child: ListView(
              children: [
                ..._activeMembers
                    .where((member) => member.userId != widget.currentUserId)
                    .map(
                      (member) => Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: _MemberShortcutTile(
                          member: member,
                          selected:
                              _selectedGroup != null &&
                              _isDirectGroup(_selectedGroup!) &&
                              _selectedGroup!.members.any(
                                (item) => item.userId == member.userId,
                              ),
                          onTap: () {
                            setState(
                              () => _collectionFilter =
                                  _ChatCollectionFilter.direct,
                            );
                            _openDirectChat(member.userId);
                          },
                        ),
                      ),
                    ),
                if (_spaceGroups.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  const _SectionTitle(title: 'Spazi'),
                  const SizedBox(height: 10),
                  ..._spaceGroups.map(
                    (group) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: _SpaceShortcutTile(
                        group: group,
                        title: _groupTitle(group),
                        selected: _selectedGroupId == group.id,
                        onTap: () {
                          setState(
                            () =>
                                _collectionFilter = _ChatCollectionFilter.group,
                          );
                          _selectGroup(group);
                        },
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConversationList() {
    final visibleGroups = _visibleGroups;
    return Container(
      decoration: const BoxDecoration(
        color: _chatPanelAlt,
        border: Border(right: BorderSide(color: _chatBorder)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        switch (_collectionFilter) {
                          _ChatCollectionFilter.home => 'Home',
                          _ChatCollectionFilter.direct => 'Messaggi diretti',
                          _ChatCollectionFilter.group => 'Spazi',
                        },
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: _chatText,
                        ),
                      ),
                    ),
                    _FilterChipButton(
                      label: 'Tutto',
                      selected: _collectionFilter == _ChatCollectionFilter.home,
                      onTap: () => setState(
                        () => _collectionFilter = _ChatCollectionFilter.home,
                      ),
                    ),
                    const SizedBox(width: 6),
                    _FilterChipButton(
                      label: 'Diretti',
                      selected:
                          _collectionFilter == _ChatCollectionFilter.direct,
                      onTap: () => setState(
                        () => _collectionFilter = _ChatCollectionFilter.direct,
                      ),
                    ),
                    const SizedBox(width: 6),
                    _FilterChipButton(
                      label: 'Gruppi',
                      selected:
                          _collectionFilter == _ChatCollectionFilter.group,
                      onTap: () => setState(
                        () => _collectionFilter = _ChatCollectionFilter.group,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _lastError != null
                ? _ErrorState(message: _lastError!)
                : visibleGroups.isEmpty
                ? const _EmptyInboxState()
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                    itemCount: visibleGroups.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(height: 4),
                    itemBuilder: (context, index) {
                      final group = visibleGroups[index];
                      final selected = group.id == _selectedGroupId;
                      return _ConversationCard(
                        title: _groupTitle(group),
                        subtitle: _groupSubtitle(group),
                        timestamp: _displayTimestamp(group.lastMessageAt),
                        unreadCount: group.unreadCount,
                        selected: selected,
                        pinned: _pinnedGroupIds.contains(group.id),
                        iconText: _avatarText(group),
                        iconAccent: _avatarAccent(group),
                        isDirect: _isDirectGroup(group),
                        onTogglePin: () => _togglePin(group.id),
                        onTap: () => _selectGroup(group),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  String _avatarText(ChatGroup group) {
    if (_isDirectGroup(group)) {
      final other = _otherMember(group);
      if (other != null && other.displayName.isNotEmpty) {
        return other.displayName[0].toUpperCase();
      }
    }
    final title = _groupTitle(group);
    return title.isEmpty ? '#' : title[0].toUpperCase();
  }

  Color _avatarAccent(ChatGroup group) {
    return _isDirectGroup(group)
        ? const Color(0xFF8A9B76)
        : GussoniBrand.primary;
  }

  Widget _buildThreadPanel(ChatGroup? selectedGroup) {
    if (_loading && selectedGroup == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_lastError != null && selectedGroup == null) {
      return _ErrorState(message: _lastError!);
    }
    if (selectedGroup == null) {
      return const _NoChatSelectedState();
    }
    final isDirect = _isDirectGroup(selectedGroup);
    final participants = selectedGroup.members
        .where((member) => member.userId != widget.currentUserId)
        .map((member) => member.displayName)
        .join(', ');

    return Container(
      decoration: const BoxDecoration(
        color: _chatPanel,
        borderRadius: BorderRadius.only(
          topRight: Radius.circular(24),
          bottomRight: Radius.circular(24),
        ),
      ),
      child: Column(
        children: [
          // Thread header
          Container(
            padding: const EdgeInsets.fromLTRB(22, 16, 16, 16),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: _chatBorder)),
            ),
            child: Row(
              children: [
                _HeaderBadge(
                  text: _avatarText(selectedGroup),
                  accent: _avatarAccent(selectedGroup),
                  isDirect: isDirect,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _groupTitle(selectedGroup),
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: _chatText,
                        ),
                      ),
                      const SizedBox(height: 2),
                      if (participants.isNotEmpty)
                        Text(
                          isDirect
                              ? participants
                              : '${selectedGroup.members.length} partecipanti — $participants',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            color: _chatMuted,
                          ),
                        ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: _refresh,
                  icon: const Icon(Icons.refresh_rounded, size: 20),
                  tooltip: 'Aggiorna',
                  color: _chatMuted,
                ),
                IconButton(
                  onPressed: () => _togglePin(selectedGroup.id),
                  icon: Icon(
                    _pinnedGroupIds.contains(selectedGroup.id)
                        ? Icons.push_pin
                        : Icons.push_pin_outlined,
                    size: 20,
                    color: _pinnedGroupIds.contains(selectedGroup.id)
                        ? GussoniBrand.primary
                        : _chatMuted,
                  ),
                  tooltip: _pinnedGroupIds.contains(selectedGroup.id)
                      ? 'Rimuovi pin'
                      : 'Fissa in cima',
                ),
                IconButton(
                  onPressed: null,
                  icon: const Icon(
                    Icons.download_outlined,
                    size: 20,
                    color: _chatMuted,
                  ),
                  tooltip: 'Esporta conversazione',
                ),
              ],
            ),
          ),

          // Message list
          Expanded(
            child: _messages.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            color: _chatAccentSoft,
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: const Icon(
                            Icons.chat_bubble_outline_rounded,
                            size: 28,
                            color: _chatAccent,
                          ),
                        ),
                        const SizedBox(height: 14),
                        const Text(
                          'Nessun messaggio ancora',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                            color: _chatText,
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Inizia la conversazione qui sotto.',
                          style: TextStyle(fontSize: 13, color: _chatMuted),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    controller: _messageScrollCtrl,
                    padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      final message = _messages[index];
                      final previous = index > 0 ? _messages[index - 1] : null;
                      final showDayMarker =
                          previous == null ||
                          !_isSameDay(previous.createdAt, message.createdAt);
                      final prev = previous;
                      final isGrouped =
                          !showDayMarker &&
                          prev != null &&
                          prev.userId == message.userId &&
                          message.createdAt
                                  .difference(prev.createdAt)
                                  .inMinutes <
                              5;
                      return Column(
                        children: [
                          if (showDayMarker)
                            _DayDivider(
                              label: _dayMarkerLabel(message.createdAt),
                            ),
                          _ChatBubble(
                            message: message,
                            currentUserId: widget.currentUserId,
                            member: _memberById(message.userId),
                            isGrouped: isGrouped,
                          ),
                        ],
                      );
                    },
                  ),
          ),

          // Composer
          Container(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: _chatBorder)),
            ),
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 12, 10),
              decoration: BoxDecoration(
                color: _chatPanelAlt,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: _chatBorder),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x100B2034),
                    blurRadius: 14,
                    offset: Offset(0, 6),
                  ),
                ],
              ),
              child: Column(
                children: [
                  TextField(
                    controller: _composerCtrl,
                    minLines: 1,
                    maxLines: 6,
                    onSubmitted: (_) => _sendMessage(),
                    decoration: const InputDecoration(
                      hintText: 'Scrivi un messaggio…',
                      hintStyle: TextStyle(color: _chatMuted, fontSize: 14),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      disabledBorder: InputBorder.none,
                      errorBorder: InputBorder.none,
                      focusedErrorBorder: InputBorder.none,
                      isDense: true,
                      filled: false,
                      contentPadding: EdgeInsets.zero,
                    ),
                    style: const TextStyle(
                      fontSize: 14,
                      height: 1.4,
                      color: _chatText,
                    ),
                    cursorColor: _chatAccent,
                  ),
                  const SizedBox(height: 8),
                  Container(height: 1, color: _chatBorder),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      _ComposerToolbarButton(
                        icon: Icons.alternate_email_rounded,
                        tooltip: 'Menziona un collega',
                        onTap: () => _insertTextToken('@'),
                      ),
                      const SizedBox(width: 2),
                      PopupMenuButton<String>(
                        tooltip: 'Inserisci emoji',
                        onSelected: _insertTextToken,
                        itemBuilder: (context) => const [
                          PopupMenuItem(value: '✅', child: Text('✅  Fatto')),
                          PopupMenuItem(value: '👍', child: Text('👍  Ok')),
                          PopupMenuItem(value: '🔥', child: Text('🔥  Top')),
                          PopupMenuItem(value: '🙏', child: Text('🙏  Grazie')),
                          PopupMenuItem(value: '❗', child: Text('❗  Urgente')),
                          PopupMenuItem(
                            value: '⏳',
                            child: Text('⏳  In attesa'),
                          ),
                          PopupMenuItem(value: '📋', child: Text('📋  Nota')),
                          PopupMenuItem(
                            value: '🎯',
                            child: Text('🎯  Obiettivo'),
                          ),
                        ],
                        child: const Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 5,
                          ),
                          child: Icon(
                            Icons.emoji_emotions_outlined,
                            size: 20,
                            color: _chatMuted,
                          ),
                        ),
                      ),
                      const SizedBox(width: 2),
                      _ComposerToolbarButton(
                        icon: Icons.attach_file_rounded,
                        tooltip: 'Allega file',
                        onTap: _pickAttachment,
                      ),
                      const Spacer(),
                      FilledButton.icon(
                        onPressed: _sending ? null : _sendMessage,
                        style: FilledButton.styleFrom(
                          backgroundColor: _chatAccent,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        icon: Icon(
                          _sending
                              ? Icons.more_horiz_rounded
                              : Icons.send_rounded,
                          size: 16,
                        ),
                        label: Text(
                          _sending ? 'Invio…' : 'Invia',
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
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
    );
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  String _dayMarkerLabel(DateTime date) {
    final now = DateTime.now();
    if (_isSameDay(date, now)) {
      return 'Oggi';
    }
    final yesterday = now.subtract(const Duration(days: 1));
    if (_isSameDay(date, yesterday)) {
      return 'Ieri';
    }
    return DateFormat('dd MMMM yyyy', 'it_IT').format(date);
  }
}

// ─── Top bar ──────────────────────────────────────────────────────────────────

class _ChatTopBar extends StatelessWidget {
  const _ChatTopBar({
    required this.searchController,
    required this.statusLabel,
    required this.statusColor,
    required this.onStatusSelected,
  });

  final TextEditingController searchController;
  final String statusLabel;
  final Color statusColor;
  final ValueChanged<_AvailabilityStatus> onStatusSelected;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 12),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            decoration: BoxDecoration(
              color: _TeamChatScreenState._chatPanel,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _TeamChatScreenState._chatBorder),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.forum_rounded,
                  color: _TeamChatScreenState._chatAccent,
                  size: 18,
                ),
                const SizedBox(width: 8),
                const Text(
                  'Team Chat',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                    color: _TeamChatScreenState._chatText,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Container(
              height: 44,
              decoration: BoxDecoration(
                color: _TeamChatScreenState._chatPanel,
                border: Border.all(color: _TeamChatScreenState._chatBorder),
                borderRadius: BorderRadius.circular(22),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x100B2034),
                    blurRadius: 10,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              child: TextField(
                controller: searchController,
                decoration: const InputDecoration(
                  prefixIcon: Icon(
                    Icons.search_rounded,
                    color: _TeamChatScreenState._chatMuted,
                    size: 20,
                  ),
                  hintText: 'Cerca conversazioni e messaggi…',
                  hintStyle: TextStyle(
                    color: _TeamChatScreenState._chatMuted,
                    fontSize: 13,
                  ),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  disabledBorder: InputBorder.none,
                  errorBorder: InputBorder.none,
                  focusedErrorBorder: InputBorder.none,
                  filled: false,
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(vertical: 14),
                ),
                style: const TextStyle(
                  fontSize: 13,
                  color: _TeamChatScreenState._chatText,
                ),
                cursorColor: _TeamChatScreenState._chatAccent,
              ),
            ),
          ),
          const SizedBox(width: 14),
          PopupMenuButton<_AvailabilityStatus>(
            tooltip: 'Cambia stato',
            onSelected: onStatusSelected,
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: _AvailabilityStatus.available,
                child: Text('Disponibile'),
              ),
              PopupMenuItem(
                value: _AvailabilityStatus.breakTime,
                child: Text('In pausa'),
              ),
              PopupMenuItem(
                value: _AvailabilityStatus.unavailable,
                child: Text('Non disponibile'),
              ),
            ],
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              decoration: BoxDecoration(
                color: _TeamChatScreenState._chatPanel,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: _TeamChatScreenState._chatBorder),
              ),
              child: Row(
                children: [
                  Container(
                    width: 9,
                    height: 9,
                    decoration: BoxDecoration(
                      color: statusColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    statusLabel,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      color: _TeamChatScreenState._chatText,
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Icon(
                    Icons.expand_more_rounded,
                    size: 18,
                    color: _TeamChatScreenState._chatMuted,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          CircleAvatar(
            radius: 19,
            backgroundColor: _TeamChatScreenState._chatAccentSoft,
            child: const Text(
              'G',
              style: TextStyle(
                color: _TeamChatScreenState._chatText,
                fontWeight: FontWeight.w800,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Resize handle ────────────────────────────────────────────────────────────

class _HorizontalResizeHandle extends StatelessWidget {
  const _HorizontalResizeHandle({required this.onDrag});

  final ValueChanged<double> onDrag;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragUpdate: (details) => onDrag(details.delta.dx),
        child: Container(
          width: 10,
          color: Colors.transparent,
          alignment: Alignment.center,
          child: Container(
            width: 2,
            height: double.infinity,
            color: _TeamChatScreenState._chatBorder.withValues(alpha: 0.9),
          ),
        ),
      ),
    );
  }
}

// ─── Sidebar components ───────────────────────────────────────────────────────

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title.toUpperCase(),
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.8,
        color: _TeamChatScreenState._chatMuted,
      ),
    );
  }
}

class _SidebarActionTile extends StatelessWidget {
  const _SidebarActionTile({
    required this.selected,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final bool selected;
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final fg = selected
        ? const Color(0xFF486B6B)
        : _TeamChatScreenState._chatText;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: selected
              ? _TeamChatScreenState._chatAccentSoft
              : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: fg),
            const SizedBox(width: 12),
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: fg,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MemberShortcutTile extends StatelessWidget {
  const _MemberShortcutTile({
    required this.member,
    required this.selected,
    required this.onTap,
  });

  final TeamMember member;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: selected
              ? _TeamChatScreenState._chatPanel
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Stack(
              children: [
                CircleAvatar(
                  radius: 14,
                  backgroundColor: _TeamChatScreenState._chatAccentSoft,
                  child: Text(
                    member.initials,
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: _TeamChatScreenState._chatText,
                    ),
                  ),
                ),
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: member.status == 'active'
                          ? const Color(0xFF2BA24C)
                          : const Color(0xFFB33A2C),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: _TeamChatScreenState._chatRail,
                        width: 1.5,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                member.displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  color: _TeamChatScreenState._chatText,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SpaceShortcutTile extends StatelessWidget {
  const _SpaceShortcutTile({
    required this.group,
    required this.title,
    required this.selected,
    required this.onTap,
  });

  final ChatGroup group;
  final String title;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: selected
              ? _TeamChatScreenState._chatPanel
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: _TeamChatScreenState._chatAccentSoft,
                borderRadius: BorderRadius.circular(9),
              ),
              child: const Icon(
                Icons.tag_rounded,
                size: 15,
                color: _TeamChatScreenState._chatAccent,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  color: _TeamChatScreenState._chatText,
                ),
              ),
            ),
            if (group.unreadCount > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: _TeamChatScreenState._chatAccent,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '${group.unreadCount}',
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ─── Filter chip ──────────────────────────────────────────────────────────────

class _FilterChipButton extends StatelessWidget {
  const _FilterChipButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? _TeamChatScreenState._chatAccentSoft
              : _TeamChatScreenState._chatPanel,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected
                ? _TeamChatScreenState._chatAccent.withValues(alpha: .36)
                : _TeamChatScreenState._chatBorder,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
            color: selected
                ? const Color(0xFF486B6B)
                : _TeamChatScreenState._chatText,
          ),
        ),
      ),
    );
  }
}

// ─── Conversation card ────────────────────────────────────────────────────────

class _ConversationCard extends StatelessWidget {
  const _ConversationCard({
    required this.title,
    required this.subtitle,
    required this.timestamp,
    required this.unreadCount,
    required this.selected,
    required this.pinned,
    required this.iconText,
    required this.iconAccent,
    required this.isDirect,
    required this.onTogglePin,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final String timestamp;
  final int unreadCount;
  final bool selected;
  final bool pinned;
  final String iconText;
  final Color iconAccent;
  final bool isDirect;
  final VoidCallback onTogglePin;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: selected
              ? _TeamChatScreenState._chatAccentSoft
              : Colors.transparent,
          borderRadius: BorderRadius.circular(18),
          border: selected
              ? Border.all(
                  color: _TeamChatScreenState._chatAccent.withValues(
                    alpha: .28,
                  ),
                )
              : null,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: iconAccent.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(isDirect ? 99 : 14),
              ),
              alignment: Alignment.center,
              child: isDirect
                  ? Text(
                      iconText,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: iconAccent,
                      ),
                    )
                  : Icon(Icons.tag_rounded, size: 20, color: iconAccent),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (pinned)
                        Padding(
                          padding: const EdgeInsets.only(right: 4),
                          child: Icon(
                            Icons.push_pin,
                            size: 12,
                            color: _TeamChatScreenState._chatAccent,
                          ),
                        ),
                      Expanded(
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: unreadCount > 0
                                ? FontWeight.w800
                                : FontWeight.w600,
                            color: _TeamChatScreenState._chatText,
                          ),
                        ),
                      ),
                      if (timestamp.isNotEmpty)
                        Text(
                          timestamp,
                          style: TextStyle(
                            fontSize: 11,
                            color: unreadCount > 0
                                ? _TeamChatScreenState._chatAccent
                                : _TeamChatScreenState._chatMuted,
                            fontWeight: unreadCount > 0
                                ? FontWeight.w700
                                : FontWeight.w400,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            color: _TeamChatScreenState._chatMuted,
                            fontWeight: unreadCount > 0
                                ? FontWeight.w600
                                : FontWeight.w400,
                          ),
                        ),
                      ),
                      if (unreadCount > 0) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: _TeamChatScreenState._chatAccent,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            '$unreadCount',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ],
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

// ─── Thread header badge ──────────────────────────────────────────────────────

class _HeaderBadge extends StatelessWidget {
  const _HeaderBadge({
    required this.text,
    required this.accent,
    required this.isDirect,
  });

  final String text;
  final Color accent;
  final bool isDirect;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(isDirect ? 99 : 14),
      ),
      alignment: Alignment.center,
      child: isDirect
          ? Text(
              text,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: accent,
              ),
            )
          : Icon(Icons.tag_rounded, size: 20, color: accent),
    );
  }
}

// ─── Day divider ──────────────────────────────────────────────────────────────

class _DayDivider extends StatelessWidget {
  const _DayDivider({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Row(
        children: [
          Expanded(
            child: Divider(
              height: 1,
              thickness: 1,
              color: _TeamChatScreenState._chatBorder,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.4,
                color: _TeamChatScreenState._chatMuted,
              ),
            ),
          ),
          Expanded(
            child: Divider(
              height: 1,
              thickness: 1,
              color: _TeamChatScreenState._chatBorder,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Chat bubble ─────────────────────────────────────────────────────────────

class _ChatBubble extends StatelessWidget {
  const _ChatBubble({
    required this.message,
    required this.currentUserId,
    required this.member,
    this.isGrouped = false,
  });

  final ChatMessage message;
  final String currentUserId;
  final TeamMember? member;
  final bool isGrouped;

  bool get _isAttachment =>
      message.body.startsWith('[ALLEGATO:') && message.body.endsWith(']');

  String get _attachmentName =>
      message.body.replaceFirst('[ALLEGATO:', '').replaceFirst(']', '');

  @override
  Widget build(BuildContext context) {
    final isMine = message.userId == currentUserId;
    final avatar =
        member?.initials ?? message.authorName.characters.first.toUpperCase();

    return Padding(
      padding: EdgeInsets.only(bottom: isGrouped ? 3 : 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisAlignment: isMine
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        children: [
          if (!isMine) ...[
            if (isGrouped)
              const SizedBox(width: 46)
            else
              CircleAvatar(
                radius: 18,
                backgroundColor: _TeamChatScreenState._chatAccentSoft,
                child: Text(
                  avatar,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: _TeamChatScreenState._chatText,
                  ),
                ),
              ),
            const SizedBox(width: 10),
          ],
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 540),
            child: Column(
              crossAxisAlignment: isMine
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              children: [
                if (!isGrouped)
                  Padding(
                    padding: EdgeInsets.only(
                      left: isMine ? 0 : 4,
                      right: isMine ? 4 : 0,
                      bottom: 5,
                    ),
                    child: Text(
                      isMine
                          ? DateFormat('HH:mm').format(message.createdAt)
                          : '${message.authorName}   ${DateFormat('HH:mm').format(message.createdAt)}',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: _TeamChatScreenState._chatMuted,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 15,
                    vertical: 11,
                  ),
                  decoration: BoxDecoration(
                    color: isMine
                        ? _TeamChatScreenState._chatMe
                        : _TeamChatScreenState._chatThem,
                    border: Border.all(
                      color: isMine
                          ? _TeamChatScreenState._chatAccent.withValues(
                              alpha: .22,
                            )
                          : _TeamChatScreenState._chatBorder,
                    ),
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(20),
                      topRight: const Radius.circular(20),
                      bottomLeft: Radius.circular(isMine ? 20 : 6),
                      bottomRight: Radius.circular(isMine ? 6 : 20),
                    ),
                  ),
                  child: _buildBody(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_isAttachment) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: _TeamChatScreenState._chatAccentSoft,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.insert_drive_file_outlined,
              size: 18,
              color: _TeamChatScreenState._chatAccent,
            ),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              _attachmentName,
              style: const TextStyle(
                fontSize: 14,
                height: 1.35,
                color: _TeamChatScreenState._chatText,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      );
    }
    return Text(
      message.body,
      style: const TextStyle(
        fontSize: 14,
        height: 1.45,
        color: _TeamChatScreenState._chatText,
      ),
    );
  }
}

// ─── Composer toolbar button ──────────────────────────────────────────────────

class _ComposerToolbarButton extends StatelessWidget {
  const _ComposerToolbarButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
          child: Icon(icon, size: 20, color: _TeamChatScreenState._chatMuted),
        ),
      ),
    );
  }
}

// ─── Empty / error states ─────────────────────────────────────────────────────

// ─── Mobile conversation tile ─────────────────────────────────────────────────

class _MobileConversationTile extends StatelessWidget {
  const _MobileConversationTile({
    required this.title,
    required this.subtitle,
    required this.timestamp,
    required this.unreadCount,
    required this.selected,
    required this.isDirect,
    required this.iconText,
    required this.iconAccent,
    required this.pinned,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final String timestamp;
  final int unreadCount;
  final bool selected;
  final bool isDirect;
  final String iconText;
  final Color iconAccent;
  final bool pinned;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        color: selected
            ? _TeamChatScreenState._chatAccentSoft
            : Colors.transparent,
        child: Row(
          children: [
            // Avatar
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: iconAccent.withValues(alpha: .14),
                borderRadius: BorderRadius.circular(isDirect ? 99 : 14),
              ),
              alignment: Alignment.center,
              child: isDirect
                  ? Text(
                      iconText,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: iconAccent,
                      ),
                    )
                  : Icon(Icons.tag_rounded, size: 20, color: iconAccent),
            ),
            const SizedBox(width: 12),
            // Content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (pinned)
                        Padding(
                          padding: const EdgeInsets.only(right: 4),
                          child: Icon(
                            Icons.push_pin,
                            size: 11,
                            color: _TeamChatScreenState._chatAccent,
                          ),
                        ),
                      Expanded(
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: unreadCount > 0
                                ? FontWeight.w800
                                : FontWeight.w600,
                            color: _TeamChatScreenState._chatText,
                          ),
                        ),
                      ),
                      if (timestamp.isNotEmpty)
                        Text(
                          timestamp,
                          style: TextStyle(
                            fontSize: 12,
                            color: unreadCount > 0
                                ? _TeamChatScreenState._chatAccent
                                : _TeamChatScreenState._chatMuted,
                            fontWeight: unreadCount > 0
                                ? FontWeight.w700
                                : FontWeight.w400,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            color: _TeamChatScreenState._chatMuted,
                            fontWeight: unreadCount > 0
                                ? FontWeight.w600
                                : FontWeight.w400,
                          ),
                        ),
                      ),
                      if (unreadCount > 0)
                        Container(
                          margin: const EdgeInsets.only(left: 8),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: _TeamChatScreenState._chatAccent,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            '$unreadCount',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            Icon(
              Icons.chevron_right_rounded,
              size: 18,
              color: _TeamChatScreenState._chatMuted,
            ),
          ],
        ),
      ),
    );
  }
}

class _NoChatSelectedState extends StatelessWidget {
  const _NoChatSelectedState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 68,
            height: 68,
            decoration: BoxDecoration(
              color: _TeamChatScreenState._chatAccentSoft,
              borderRadius: BorderRadius.circular(22),
            ),
            child: const Icon(
              Icons.forum_outlined,
              size: 34,
              color: _TeamChatScreenState._chatAccent,
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Seleziona una conversazione',
            style: TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w800,
              color: _TeamChatScreenState._chatText,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Apri una chat diretta con un collega\no accedi a uno spazio di team.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              height: 1.55,
              color: _TeamChatScreenState._chatMuted,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyInboxState extends StatelessWidget {
  const _EmptyInboxState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.mark_chat_read_outlined,
              size: 38,
              color: _TeamChatScreenState._chatMuted,
            ),
            SizedBox(height: 12),
            Text(
              'Nessuna conversazione trovata',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: _TeamChatScreenState._chatText,
              ),
            ),
            SizedBox(height: 6),
            Text(
              'Prova a cambiare filtro o crea una nuova conversazione.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: _TeamChatScreenState._chatMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.error_outline_rounded,
              size: 38,
              color: GussoniBrand.error,
            ),
            const SizedBox(height: 10),
            const Text(
              'Errore caricamento chat',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: GussoniBrand.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 12,
                color: GussoniBrand.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Create chat dialog ───────────────────────────────────────────────────────

sealed class _ChatDialogAction {
  const _ChatDialogAction();
}

class _CreatedGroupAction extends _ChatDialogAction {
  const _CreatedGroupAction(this.groupId);

  final String groupId;
}

class _OpenExistingDirectAction extends _ChatDialogAction {
  const _OpenExistingDirectAction(this.memberId);

  final String memberId;
}

class _CreateChatDialog extends StatefulWidget {
  const _CreateChatDialog({
    required this.members,
    required this.currentUserId,
    required this.repository,
  });

  final List<TeamMember> members;
  final String currentUserId;
  final ChatApiRepository repository;

  @override
  State<_CreateChatDialog> createState() => _CreateChatDialogState();
}

class _CreateChatDialogState extends State<_CreateChatDialog> {
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final Set<String> _selectedIds = {};
  bool _saving = false;
  bool _isDirectMode = true;
  String? _selectedDirectId;

  @override
  void initState() {
    super.initState();
    _selectedIds.add(widget.currentUserId);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_isDirectMode) {
      final directId = _selectedDirectId;
      if (directId == null) {
        return;
      }
      Navigator.of(context).pop(_OpenExistingDirectAction(directId));
      return;
    }
    final name = _nameCtrl.text.trim();
    if (name.isEmpty || _selectedIds.length < 2) {
      return;
    }
    setState(() => _saving = true);
    try {
      final members = widget.members
          .where((member) => _selectedIds.contains(member.userId))
          .map(
            (member) => {
              'userId': member.userId,
              'displayName': member.displayName,
              'email': member.email,
              'role': member.role,
            },
          )
          .toList();
      final group = await widget.repository.createGroup(
        name: name,
        description: _descCtrl.text.trim(),
        members: members,
      );
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(_CreatedGroupAction(group.id));
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Creazione chat: $error')));
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final selectableMembers = widget.members
        .where((member) => member.userId != widget.currentUserId)
        .toList();
    return AlertDialog(
      title: const Text('Nuova conversazione'),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment<bool>(value: true, label: Text('Chat diretta')),
                ButtonSegment<bool>(value: false, label: Text('Spazio gruppo')),
              ],
              selected: {_isDirectMode},
              onSelectionChanged: (selection) {
                setState(() => _isDirectMode = selection.first);
              },
            ),
            const SizedBox(height: 20),
            if (_isDirectMode)
              DropdownButtonFormField<String>(
                initialValue: _selectedDirectId,
                items: selectableMembers
                    .map(
                      (member) => DropdownMenuItem<String>(
                        value: member.userId,
                        child: Text(member.displayName),
                      ),
                    )
                    .toList(),
                onChanged: (value) => setState(() => _selectedDirectId = value),
                decoration: const InputDecoration(
                  labelText: 'Seleziona collega',
                  border: OutlineInputBorder(),
                ),
              )
            else ...[
              TextField(
                controller: _nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Nome spazio',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _descCtrl,
                decoration: const InputDecoration(
                  labelText: 'Descrizione (opzionale)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Aggiungi partecipanti',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: Colors.grey[700],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 240,
                child: ListView.separated(
                  itemCount: widget.members.length,
                  separatorBuilder: (context, index) =>
                      const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final member = widget.members[index];
                    final selected = _selectedIds.contains(member.userId);
                    return CheckboxListTile(
                      value: selected,
                      onChanged: (value) {
                        setState(() {
                          if (value == true) {
                            _selectedIds.add(member.userId);
                          } else if (member.userId != widget.currentUserId) {
                            _selectedIds.remove(member.userId);
                          }
                        });
                      },
                      title: Text(member.displayName),
                      subtitle: Text(member.email),
                      controlAffinity: ListTileControlAffinity.leading,
                      dense: true,
                    );
                  },
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Annulla'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(_saving ? 'Creazione…' : 'Apri'),
        ),
      ],
    );
  }
}
