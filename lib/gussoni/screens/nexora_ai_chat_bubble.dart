import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../../brand_config.dart';
import '../../models/ai_models.dart';
import '../../services/ai_service.dart';
import '../../services/ai_local_storage_stub.dart'
    if (dart.library.html) '../../services/ai_local_storage_web.dart';

/// Chatbot Nexora AI flottante, fisso in basso a destra in tutta la webapp.
///
/// Le conversazioni vengono salvate nello stesso storage del modulo Nexora AI
/// (compaiono nella sua lista), ma la sessione del chatbot dura al massimo
/// 8 ore dal primo messaggio: dopo, il widget riparte pulito mentre la
/// conversazione resta consultabile nel modulo.
class NexoraAiChatBubble extends StatefulWidget {
  const NexoraAiChatBubble({
    super.key,
    required this.workspaceContext,
    this.onOpenModule,
  });

  final AiWorkspaceContext workspaceContext;
  final VoidCallback? onOpenModule;

  @override
  State<NexoraAiChatBubble> createState() => _NexoraAiChatBubbleState();
}

class _NexoraAiChatBubbleState extends State<NexoraAiChatBubble> {
  static const String _conversationsKey = 'nexora_ai_conversations_v1';
  static const String _sessionKey = 'nexora_ai_bubble_session_v1';
  static const Duration _sessionDuration = Duration(hours: 8);

  final AiService _service = AiService();
  final TextEditingController _input = TextEditingController();
  final FocusNode _inputFocus = FocusNode();

  bool _open = false;
  bool _sending = false;
  String? _conversationId;
  DateTime? _firstMessageAt;
  List<AiMessage> _messages = [];
  Timer? _expiryTimer;

  @override
  void initState() {
    super.initState();
    _restoreSession();
    // Controllo periodico della scadenza (anche a pannello chiuso).
    _expiryTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (_isExpired) _clearSession();
    });
  }

  @override
  void dispose() {
    _expiryTimer?.cancel();
    _input.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  // ── Sessione 8h ─────────────────────────────────────────────────────────

  bool get _isExpired =>
      _firstMessageAt != null &&
      DateTime.now().difference(_firstMessageAt!) > _sessionDuration;

  void _restoreSession() {
    try {
      final raw = aiLocalStorageGet(_sessionKey);
      if (raw == null || raw.isEmpty) return;
      final data = jsonDecode(raw) as Map<String, dynamic>;
      _conversationId = data['conversationId'] as String?;
      _firstMessageAt = DateTime.tryParse(
        (data['firstMessageAt'] ?? '') as String,
      );
      if (_isExpired) {
        _clearSession();
        return;
      }
      _reloadMessages();
    } catch (_) {}
  }

  void _persistSession() {
    try {
      aiLocalStorageSet(
        _sessionKey,
        jsonEncode({
          'conversationId': _conversationId,
          'firstMessageAt': _firstMessageAt?.toIso8601String(),
        }),
      );
    } catch (_) {}
  }

  /// Chiude la sessione del widget: la conversazione resta nel modulo.
  void _clearSession() {
    if (!mounted) {
      return;
    }
    setState(() {
      _conversationId = null;
      _firstMessageAt = null;
      _messages = [];
    });
    try {
      aiLocalStorageSet(_sessionKey, '');
    } catch (_) {}
  }

  String get _sessionLabel {
    if (_firstMessageAt == null) return 'Sessione di 8 ore';
    final remaining =
        _sessionDuration - DateTime.now().difference(_firstMessageAt!);
    if (remaining.isNegative) return 'Sessione scaduta';
    final h = remaining.inHours;
    final m = remaining.inMinutes.remainder(60);
    return h > 0 ? 'Si rinnova tra ${h}h ${m}m' : 'Si rinnova tra ${m}m';
  }

  // ── Storage condiviso col modulo ────────────────────────────────────────

  List<AiConversation> _loadAll() {
    try {
      final raw = aiLocalStorageGet(_conversationsKey);
      if (raw != null && raw.isNotEmpty) {
        return AiConversation.listFromJson(raw);
      }
    } catch (_) {}
    return [];
  }

  void _saveAll(List<AiConversation> all) {
    try {
      aiLocalStorageSet(_conversationsKey, AiConversation.listToJson(all));
      aiConversationsRevision.value += 1;
    } catch (_) {}
  }

  void _reloadMessages() {
    if (_conversationId == null) return;
    final conv = _loadAll().where((c) => c.id == _conversationId).firstOrNull;
    if (conv == null) {
      // Eliminata dal modulo: il widget riparte pulito.
      _clearSession();
      return;
    }
    setState(() => _messages = List<AiMessage>.from(conv.messages));
  }

  AiConversation _ensureConversation(List<AiConversation> all, String text) {
    if (_conversationId != null) {
      final existing = all.where((c) => c.id == _conversationId).firstOrNull;
      if (existing != null) return existing;
    }
    final id = 'aib-${DateTime.now().microsecondsSinceEpoch}';
    final title = text.length > 42 ? '${text.substring(0, 42)}…' : text;
    final conv = AiConversation(
      id: id,
      title: title,
      messages: [],
      createdAt: DateTime.now(),
    );
    all.insert(0, conv);
    _conversationId = id;
    _firstMessageAt = DateTime.now();
    _persistSession();
    return conv;
  }

  // ── Invio messaggi ──────────────────────────────────────────────────────

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;
    if (_isExpired) _clearSession();

    _input.clear();
    final all = _loadAll();
    final conv = _ensureConversation(all, text);
    conv.messages.add(
      AiMessage(role: AiRole.user, text: text, timestamp: DateTime.now()),
    );
    setState(() {
      _messages = List<AiMessage>.from(conv.messages);
      _sending = true;
    });
    _saveAll(all);

    final ts = DateTime.now();
    final accText = StringBuffer();
    final toolCalls = <AiToolCall>[];
    var hasError = false;

    conv.messages.add(
      AiMessage(role: AiRole.assistant, text: '', timestamp: ts),
    );
    setState(() => _messages = List<AiMessage>.from(conv.messages));

    try {
      await for (final event in _service.chatStream(
        messages: conv.messages.sublist(0, conv.messages.length - 1),
        workspaceContext: widget.workspaceContext,
      )) {
        if (!mounted) return;
        switch (event.type) {
          case AiStreamEventType.text:
            accText.write(event.text);
            conv.messages[conv.messages.length - 1] = AiMessage(
              role: AiRole.assistant,
              text: accText.toString(),
              timestamp: ts,
            );
            setState(() => _messages = List<AiMessage>.from(conv.messages));
          case AiStreamEventType.toolUse:
            toolCalls.add(event.toolCall!);
          case AiStreamEventType.done:
            break;
          case AiStreamEventType.error:
            hasError = true;
            conv.messages[conv.messages.length - 1] = AiMessage(
              role: AiRole.assistant,
              text: event.error ?? 'Errore sconosciuto.',
              isError: true,
              timestamp: ts,
            );
            setState(() => _messages = List<AiMessage>.from(conv.messages));
        }
      }
    } catch (e) {
      hasError = true;
      conv.messages[conv.messages.length - 1] = AiMessage(
        role: AiRole.assistant,
        text: 'Errore: $e',
        isError: true,
        timestamp: ts,
      );
    }

    if (!hasError) {
      var finalText = accText.toString();
      if (toolCalls.isNotEmpty) {
        // Il widget non esegue azioni CRM: rimanda al modulo completo.
        final note =
            'Questa richiesta esegue azioni sul CRM: aprila in Nexora AI '
            '(in basso trovi "Apri il modulo") per completarla.';
        finalText = finalText.isEmpty ? note : '$finalText\n\n$note';
        conv.messages[conv.messages.length - 1] = AiMessage(
          role: AiRole.assistant,
          text: finalText,
          timestamp: ts,
        );
      } else if (finalText.isEmpty) {
        conv.messages.removeLast();
      }
    }

    _saveAll(all);
    if (!mounted) return;
    setState(() {
      _messages = List<AiMessage>.from(conv.messages);
      _sending = false;
    });
  }

  void _togglePanel() {
    if (_isExpired) _clearSession();
    setState(() => _open = !_open);
    if (_open) {
      _reloadMessages();
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _inputFocus.requestFocus(),
      );
    }
  }

  // ── UI ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.of(context).size;
    final panelWidth = (screen.width - 28).clamp(260.0, 380.0);
    final panelHeight = (screen.height - 170).clamp(300.0, 560.0);

    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        AnimatedSwitcher(
          duration: Duration(milliseconds: reduceMotion ? 0 : 220),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          transitionBuilder: (child, animation) => FadeTransition(
            opacity: animation,
            child: ScaleTransition(
              scale: Tween<double>(begin: .94, end: 1).animate(animation),
              alignment: Alignment.bottomRight,
              child: child,
            ),
          ),
          child: _open
              ? Padding(
                  key: const ValueKey('ai-panel'),
                  padding: const EdgeInsets.only(bottom: 12),
                  child: SizedBox(
                    width: panelWidth,
                    height: panelHeight,
                    child: _buildPanel(),
                  ),
                )
              : const SizedBox.shrink(key: ValueKey('ai-panel-closed')),
        ),
        _buildFab(),
      ],
    );
  }

  Widget _buildFab() {
    return Tooltip(
      message: _open ? 'Chiudi Nexora AI' : 'Chiedi a Nexora AI',
      child: Material(
        color: GussoniBrand.primary,
        shape: const CircleBorder(),
        elevation: 6,
        shadowColor: const Color(0x665B1205),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: _togglePanel,
          child: SizedBox(
            width: 54,
            height: 54,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              transitionBuilder: (child, animation) => RotationTransition(
                turns: Tween<double>(begin: .85, end: 1).animate(animation),
                child: FadeTransition(opacity: animation, child: child),
              ),
              child: Icon(
                _open ? Icons.close_rounded : Icons.auto_awesome_rounded,
                key: ValueKey(_open),
                color: Colors.white,
                size: 24,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPanel() {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: GussoniBrand.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: GussoniBrand.border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x29000000),
            blurRadius: 28,
            offset: Offset(0, 14),
          ),
        ],
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
            decoration: const BoxDecoration(
              border: Border(
                bottom: BorderSide(color: GussoniBrand.borderSubtle),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(9),
                    color: GussoniBrand.primary,
                  ),
                  child: const Icon(
                    Icons.auto_awesome_rounded,
                    color: Colors.white,
                    size: 17,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Nexora AI',
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w800,
                          color: GussoniBrand.textPrimary,
                        ),
                      ),
                      Text(
                        _sessionLabel,
                        style: const TextStyle(
                          fontSize: 10.5,
                          color: GussoniBrand.textMuted,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Nuova conversazione',
                  onPressed: _sending ? null : _clearSession,
                  icon: const Icon(
                    Icons.edit_square,
                    size: 16,
                    color: GussoniBrand.textSecondary,
                  ),
                ),
                if (widget.onOpenModule != null)
                  IconButton(
                    tooltip: 'Apri il modulo Nexora AI',
                    onPressed: () {
                      setState(() => _open = false);
                      widget.onOpenModule!();
                    },
                    icon: const Icon(
                      Icons.open_in_full_rounded,
                      size: 15,
                      color: GussoniBrand.textSecondary,
                    ),
                  ),
                IconButton(
                  tooltip: 'Chiudi',
                  onPressed: _togglePanel,
                  icon: const Icon(
                    Icons.keyboard_arrow_down_rounded,
                    size: 20,
                    color: GussoniBrand.textSecondary,
                  ),
                ),
              ],
            ),
          ),

          // Messaggi
          Expanded(
            child: _messages.isEmpty ? _buildEmptyState() : _buildMessages(),
          ),

          // Input
          Container(
            padding: const EdgeInsets.fromLTRB(10, 8, 8, 10),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: GussoniBrand.borderSubtle)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextField(
                    controller: _input,
                    focusNode: _inputFocus,
                    minLines: 1,
                    maxLines: 4,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _send(),
                    style: const TextStyle(fontSize: 13.5),
                    decoration: InputDecoration(
                      hintText: 'Chiedi qualcosa…',
                      hintStyle: const TextStyle(
                        fontSize: 13,
                        color: GussoniBrand.textMuted,
                      ),
                      filled: true,
                      fillColor: GussoniBrand.scaffoldBg,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(
                          color: GussoniBrand.border,
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(
                          color: GussoniBrand.borderSubtle,
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: GussoniBrand.primary),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Material(
                  color: GussoniBrand.primary,
                  borderRadius: BorderRadius.circular(10),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: _sending ? null : _send,
                    child: SizedBox(
                      width: 38,
                      height: 38,
                      child: _sending
                          ? const Padding(
                              padding: EdgeInsets.all(10),
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(
                              Icons.send_rounded,
                              color: Colors.white,
                              size: 17,
                            ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: GussoniBrand.primaryBg,
              ),
              child: Icon(
                Icons.auto_awesome_rounded,
                color: GussoniBrand.primary,
                size: 22,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Come posso aiutarti?',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: GussoniBrand.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Chiedi informazioni su clienti, opportunità, '
              'preventivi o task. La conversazione viene salvata '
              'anche nel modulo Nexora AI.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                height: 1.45,
                color: GussoniBrand.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessages() {
    final visible = _messages
        .where((m) => m.toolResultFor == null)
        .toList()
        .reversed
        .toList();
    return ListView.builder(
      reverse: true,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
      itemCount: visible.length,
      itemBuilder: (context, index) {
        final msg = visible[index];
        final isUser = msg.isUser;
        return Align(
          alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            constraints: const BoxConstraints(maxWidth: 290),
            decoration: BoxDecoration(
              color: isUser
                  ? GussoniBrand.primary
                  : msg.isError
                  ? GussoniBrand.errorBg
                  : GussoniBrand.surfaceSubtle,
              borderRadius: BorderRadius.circular(12).copyWith(
                bottomRight: isUser ? const Radius.circular(4) : null,
                bottomLeft: isUser ? null : const Radius.circular(4),
              ),
            ),
            child: SelectableText(
              msg.text.isEmpty && _sending && !isUser ? '…' : msg.text,
              style: TextStyle(
                fontSize: 13,
                height: 1.45,
                color: isUser
                    ? Colors.white
                    : msg.isError
                    ? GussoniBrand.error
                    : GussoniBrand.textPrimary,
              ),
            ),
          ),
        );
      },
    );
  }
}
