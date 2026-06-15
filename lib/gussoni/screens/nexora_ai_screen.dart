import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../brand_config.dart';
import '../../models/ai_models.dart';
import '../../services/ai_service.dart';
import '../../services/ai_local_storage_stub.dart'
    if (dart.library.html) '../../services/ai_local_storage_web.dart';

class NexoraAiScreen extends StatefulWidget {
  const NexoraAiScreen({
    super.key,
    required this.workspaceContext,
    this.onOpenApp,
    this.onOpenCompany,
    this.onCreateOpportunity,
    this.onCreateProject,
    this.onCreateTask,
    this.onCreateCompany,
    this.onCreateContact,
    this.onCreateQuote,
    this.onCreateTicket,
    this.onUpdateCompany,
    this.onUpdateContact,
    this.onUpdateOpportunity,
    this.onUpdateProject,
    this.onUpdateTask,
    this.onUpdateQuote,
    this.onDeleteContact,
    this.onDeleteOpportunity,
    this.onDeleteTask,
    this.onDeleteQuote,
    this.onAcceptQuote,
    this.onScheduleTask,
  });

  final AiWorkspaceContext workspaceContext;
  final void Function(String appId)? onOpenApp;
  final void Function(String companyId, String companyName)? onOpenCompany;
  final Future<void> Function({
    required String title,
    required String companyId,
    required String companyName,
    double estimatedValue,
    String notes,
  })? onCreateOpportunity;
  final Future<void> Function({
    required String name,
    required String companyId,
    required String companyName,
    String notes,
    String code,
  })? onCreateProject;
  final Future<String> Function({
    required String name,
    String companyId,
    String companyName,
    double estimatedHours,
    int deadlineDays,
    String notes,
  })? onCreateTask;
  final Future<void> Function({
    required String name,
    String email,
    String phone,
    String city,
    String vatNumber,
    String taxCode,
    String notes,
  })? onCreateCompany;
  final Future<void> Function({
    required String name,
    required String companyId,
    required String companyName,
    String email,
    String phone,
    String role,
  })? onCreateContact;
  final Future<void> Function({
    required String title,
    required String companyId,
    required String companyName,
    double estimatedValue,
    List<Map<String, dynamic>> lines,
    String notes,
  })? onCreateQuote;
  final Future<void> Function({
    required String companyId,
    required String companyName,
    required String title,
    String body,
  })? onCreateTicket;
  // Update callbacks
  final Future<void> Function({
    required String companyId,
    required Map<String, dynamic> changes,
  })? onUpdateCompany;
  final Future<void> Function({
    required String contactId,
    required Map<String, dynamic> changes,
  })? onUpdateContact;
  final Future<void> Function({
    required String opportunityId,
    required Map<String, dynamic> changes,
  })? onUpdateOpportunity;
  final Future<void> Function({
    required String projectId,
    required Map<String, dynamic> changes,
  })? onUpdateProject;
  final Future<void> Function({
    required String taskId,
    required Map<String, dynamic> changes,
  })? onUpdateTask;
  final Future<void> Function({
    required String quoteId,
    required Map<String, dynamic> changes,
  })? onUpdateQuote;
  // Delete callbacks
  final Future<void> Function(String contactId)? onDeleteContact;
  final Future<void> Function(String opportunityId)? onDeleteOpportunity;
  final Future<void> Function(String taskId)? onDeleteTask;
  final Future<void> Function(String quoteId)? onDeleteQuote;
  // Special actions
  final Future<void> Function({
    required String quoteId,
    required String opportunityId,
  })? onAcceptQuote;
  // Calendar
  final Future<void> Function({
    required String taskId,
    required String taskName,
    required List<Map<String, dynamic>> slots,
  })? onScheduleTask;

  @override
  State<NexoraAiScreen> createState() => _NexoraAiScreenState();
}

class _NexoraAiScreenState extends State<NexoraAiScreen> {
  final AiService _service = AiService();
  final _input = TextEditingController();
  final _scrollCtrl = ScrollController();
  final _inputFocus = FocusNode();

  List<AiConversation> _conversations = [];
  String? _selectedId;
  bool _sending = false;
  bool _isStreaming = false;
  // Cache dei task appena creati via AI — permette schedule immediato prima del sync Firestore.
  ({String id, String name})? _lastCreatedTask;

  static const String _storageKey = 'nexora_ai_conversations_v1';

  AiConversation? get _selected =>
      _conversations.where((c) => c.id == _selectedId).firstOrNull;

  bool _suppressNextRevision = false;

  @override
  void initState() {
    super.initState();
    _load();
    aiConversationsRevision.addListener(_handleExternalRevision);
  }

  @override
  void dispose() {
    aiConversationsRevision.removeListener(_handleExternalRevision);
    _input.dispose();
    _scrollCtrl.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  /// Ricarica le conversazioni quando il chatbot flottante le modifica.
  void _handleExternalRevision() {
    if (_suppressNextRevision) {
      _suppressNextRevision = false;
      return;
    }
    if (!mounted || _sending) return;
    _load();
  }

  void _load() {
    try {
      final raw = aiLocalStorageGet(_storageKey);
      if (raw != null && raw.isNotEmpty) {
        setState(() => _conversations = AiConversation.listFromJson(raw));
      }
    } catch (_) {}
  }

  void _save() {
    try {
      aiLocalStorageSet(_storageKey, AiConversation.listToJson(_conversations));
      _suppressNextRevision = true;
      aiConversationsRevision.value += 1;
    } catch (_) {}
  }

  void _newConversation() {
    final id = _generateId();
    final conv = AiConversation(
      id: id,
      title: 'Nuova chat',
      messages: [],
      createdAt: DateTime.now(),
    );
    setState(() {
      _conversations.insert(0, conv);
      _selectedId = id;
    });
    _save();
    WidgetsBinding.instance.addPostFrameCallback((_) => _inputFocus.requestFocus());
  }

  void _deleteConversation(String id) {
    setState(() {
      _conversations.removeWhere((c) => c.id == id);
      if (_selectedId == id) {
        _selectedId = _conversations.firstOrNull?.id;
      }
    });
    _save();
  }

  // Local routing: handle simple navigation commands without calling AI (0 tokens).
  bool _tryLocalRoute(String text, AiConversation conv) {
    if (text.length > 72) return false;
    final lower = text.toLowerCase();
    const prefix = r'(apri|vai|mostra|visualizza|apri la sezione)';
    final navMap = <RegExp, (String, String)>{
      RegExp('$prefix.*(preventiv)'): ('quotations', 'Preventivi'),
      RegExp('$prefix.*(societ)'): ('companies', 'Società'),
      RegExp('$prefix.*(contatt)'): ('contacts', 'Contatti'),
      RegExp('$prefix.*(opportunit)'): ('opportunities', 'Opportunità'),
      RegExp('$prefix.*(progett)'): ('projects', 'Progetti'),
      RegExp('$prefix.*(\\btask\\b|attivit)'): ('tasks', 'Task'),
      RegExp('$prefix.*(archiv)'): ('archive', 'Archivio'),
      RegExp('$prefix.*(finanz)'): ('finanze', 'Finanziamenti'),
      RegExp('$prefix.*(segnatempo|timesheet)'): ('segnatempo', 'Segnatempo'),
      RegExp('$prefix.*(statistic|\\bstat\\b)'): ('stats', 'Statistiche'),
      RegExp('$prefix.*(\\bchat\\b|messaggi)'): ('chat', 'Chat'),
    };
    for (final entry in navMap.entries) {
      if (entry.key.hasMatch(lower)) {
        final (section, label) = entry.value;
        widget.onOpenApp?.call(section);
        setState(() {
          conv.messages.add(AiMessage(
            role: AiRole.assistant,
            text: 'Sezione $label aperta.',
            timestamp: DateTime.now(),
          ));
        });
        return true;
      }
    }
    return false;
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending || _selected == null) return;

    final conv = _selected!;
    _input.clear();
    setState(() {
      conv.messages.add(AiMessage(role: AiRole.user, text: text, timestamp: DateTime.now()));
      _sending = true;
      if (conv.title == 'Nuova chat') {
        conv.title = text.length > 42 ? '${text.substring(0, 42)}…' : text;
      }
    });
    _scrollToBottom();

    if (_tryLocalRoute(text, conv)) {
      setState(() => _sending = false);
      _save();
      return;
    }

    await _streamAndExecute(conv);

    if (mounted) setState(() => _sending = false);
    _save();
  }

  /// Streams one AI response turn, updates the UI incrementally, then executes tool calls.
  Future<void> _streamAndExecute(AiConversation conv) async {
    final snapshot = List<AiMessage>.from(conv.messages);
    final ts = DateTime.now();
    final accText = StringBuffer();
    final toolCalls = <AiToolCall>[];
    bool hasError = false;

    setState(() {
      conv.messages.add(AiMessage(role: AiRole.assistant, text: '', timestamp: ts));
      _isStreaming = true;
    });

    try {
      await for (final event in _service.chatStream(
        messages: snapshot,
        workspaceContext: widget.workspaceContext,
      )) {
        if (!mounted) return;
        switch (event.type) {
          case AiStreamEventType.text:
            accText.write(event.text);
            setState(() {
              conv.messages[conv.messages.length - 1] = AiMessage(
                role: AiRole.assistant,
                text: accText.toString(),
                timestamp: ts,
              );
            });
            // No explicit scroll needed: reverse:true keeps latest message at bottom.;
          case AiStreamEventType.toolUse:
            toolCalls.add(event.toolCall!);
          case AiStreamEventType.done:
            break;
          case AiStreamEventType.error:
            hasError = true;
            setState(() {
              conv.messages[conv.messages.length - 1] = AiMessage(
                role: AiRole.assistant,
                text: event.error ?? 'Errore sconosciuto.',
                isError: true,
                timestamp: ts,
              );
            });
        }
      }
    } catch (e) {
      if (!mounted) return;
      hasError = true;
      setState(() {
        conv.messages[conv.messages.length - 1] = AiMessage(
          role: AiRole.assistant,
          text: 'Errore: $e',
          isError: true,
          timestamp: ts,
        );
      });
    }

    if (mounted) setState(() => _isStreaming = false);
    if (!mounted || hasError) return;

    if (toolCalls.isNotEmpty) {
      setState(() {
        conv.messages[conv.messages.length - 1] = AiMessage(
          role: AiRole.assistant,
          text: accText.toString(),
          toolCalls: toolCalls,
          timestamp: ts,
        );
      });
      await _executeTools(conv, toolCalls);
    } else if (accText.isEmpty) {
      setState(() => conv.messages.removeLast());
    }
  }

  // Tools that require a follow-up AI call to generate meaningful output.
  static const _toolsNeedingFollowUp = {'search_entity', 'generate_document', 'generate_csv'};

  // Local confirmation messages — no API call needed.
  String _localConfirm(AiToolCall tc) => switch (tc.name) {
    'open_crm_section'   => 'Sezione aperta.',
    'open_company'       => 'Scheda aperta: ${tc.input['company_name']}.',
    'create_company'     => 'Società "${tc.input['name']}" creata.',
    'create_contact'     => 'Contatto "${tc.input['name']}" aggiunto.',
    'create_opportunity' => 'Opportunità "${tc.input['title']}" creata.',
    'create_project'     => 'Progetto "${tc.input['name']}" creato.',
    'create_task'        => 'Task "${tc.input['name']}" creato.',
    'create_quote'       => 'Preventivo "${tc.input['title']}" creato.',
    'create_ticket'      => 'Ticket "${tc.input['title']}" creato.',
    'update_company'     => 'Dati di "${tc.input['company_name']}" aggiornati.',
    'update_contact'     => '"${tc.input['contact_name']}" aggiornato.',
    'update_opportunity' => '"${tc.input['opportunity_title']}" aggiornata.',
    'update_project'     => '"${tc.input['project_name']}" aggiornato.',
    'update_task'        => '"${tc.input['task_name']}" aggiornato.',
    'update_quote'       => 'Preventivo aggiornato.',
    'delete_contact'     => '"${tc.input['contact_name']}" eliminato.',
    'delete_opportunity' => '"${tc.input['opportunity_title']}" eliminata.',
    'delete_task'        => '"${tc.input['task_name']}" eliminato.',
    'delete_quote'       => 'Preventivo eliminato.',
    'accept_quote'       => 'Preventivo "${tc.input['quote_title']}" accettato.',
    'schedule_task'      => 'Task "${tc.input['task_name']}" pianificato nel calendario.',
    'search_crm'         => '',
    _                    => 'Fatto.',
  };

  // Client-side entity search (no API call, no tokens).
  String _searchEntityLocally(String entityType, String query) {
    final q = query.toLowerCase();
    final pool = switch (entityType) {
      'company'     => widget.workspaceContext.companies,
      'contact'     => widget.workspaceContext.contacts,
      'opportunity' => widget.workspaceContext.deals,
      'project'     => widget.workspaceContext.projects,
      'task'        => widget.workspaceContext.tasks,
      'quote'       => widget.workspaceContext.quotes,
      'ticket'      => widget.workspaceContext.tickets,
      _             => <Map<String, String>>[],
    };
    final nameKey = entityType == 'opportunity' ? 'title' : 'name';
    final matches = pool
        .where((e) => (e[nameKey] ?? e['name'] ?? '').toLowerCase().contains(q))
        .take(5)
        .toList();
    if (matches.isEmpty) return 'Nessuna corrispondenza per "$query".';
    return jsonEncode(matches);
  }

  // Client-side cross-entity search for search_crm.
  List<Map<String, String>> _searchAllLocally(String query) {
    final q = query.toLowerCase();
    final results = <Map<String, String>>[];
    void scan(List<Map<String, String>> pool, String type, String nameKey) {
      for (final e in pool.take(25)) {
        final name = (e[nameKey] ?? e['name'] ?? '').toLowerCase();
        if (name.contains(q) || q.split(' ').where((w) => w.length > 2).any(name.contains)) {
          results.add({...e, 'type': type, 'detail': e['status'] ?? e['stage'] ?? e['role'] ?? ''});
        }
      }
    }
    scan(widget.workspaceContext.companies, 'company', 'name');
    scan(widget.workspaceContext.deals, 'opportunity', 'title');
    scan(widget.workspaceContext.projects, 'project', 'name');
    scan(widget.workspaceContext.tasks, 'task', 'name');
    scan(widget.workspaceContext.contacts, 'contact', 'name');
    return results;
  }

  Future<void> _executeTools(
    AiConversation conv,
    List<AiToolCall> toolCalls,
  ) async {
    for (final tc in toolCalls) {
      String result = 'eseguito';
      switch (tc.name) {
        case 'open_crm_section':
          final section = (tc.input['section'] ?? '') as String;
          widget.onOpenApp?.call(section);
          result = 'sezione aperta';
        case 'open_company':
          final id = (tc.input['company_id'] ?? '') as String;
          final name = (tc.input['company_name'] ?? '') as String;
          widget.onOpenCompany?.call(id, name);
          result = 'scheda aperta';
        case 'create_opportunity':
          try {
            await widget.onCreateOpportunity?.call(
              title: (tc.input['title'] ?? '') as String,
              companyId: (tc.input['company_id'] ?? '') as String,
              companyName: (tc.input['company_name'] ?? '') as String,
              estimatedValue: ((tc.input['estimated_value'] ?? 0) as num).toDouble(),
              notes: (tc.input['notes'] ?? '') as String,
            );
            result = 'opportunità creata';
          } catch (e) {
            result = 'errore: $e';
          }
        case 'create_project':
          try {
            await widget.onCreateProject?.call(
              name: (tc.input['name'] ?? '') as String,
              companyId: (tc.input['company_id'] ?? '') as String,
              companyName: (tc.input['company_name'] ?? '') as String,
              notes: (tc.input['notes'] ?? '') as String,
              code: (tc.input['code'] ?? '') as String,
            );
            result = 'progetto creato';
          } catch (e) {
            result = 'errore: $e';
          }
        case 'create_task':
          try {
            final taskName = (tc.input['name'] ?? '') as String;
            final createdId = await widget.onCreateTask?.call(
              name: taskName,
              companyId: (tc.input['company_id'] ?? '') as String,
              companyName: (tc.input['company_name'] ?? '') as String,
              estimatedHours: ((tc.input['estimated_hours'] ?? 1) as num).toDouble(),
              deadlineDays: ((tc.input['deadline_days'] ?? 7) as num).toInt(),
              notes: (tc.input['notes'] ?? '') as String,
            );
            if (createdId != null && createdId.isNotEmpty) {
              _lastCreatedTask = (id: createdId, name: taskName);
            }
            result = 'task creato${createdId != null ? " (task_id: $createdId)" : ""}';
          } catch (e) {
            result = 'errore: $e';
          }
        case 'create_company':
          try {
            await widget.onCreateCompany?.call(
              name: (tc.input['name'] ?? '') as String,
              email: (tc.input['email'] ?? '') as String,
              phone: (tc.input['phone'] ?? '') as String,
              city: (tc.input['city'] ?? '') as String,
              vatNumber: (tc.input['vatNumber'] ?? '') as String,
              taxCode: (tc.input['taxCode'] ?? '') as String,
              notes: (tc.input['notes'] ?? '') as String,
            );
            result = 'società creata';
          } catch (e) {
            result = 'errore: $e';
          }
        case 'create_contact':
          try {
            await widget.onCreateContact?.call(
              name: (tc.input['name'] ?? '') as String,
              companyId: (tc.input['company_id'] ?? '') as String,
              companyName: (tc.input['company_name'] ?? '') as String,
              email: (tc.input['email'] ?? '') as String,
              phone: (tc.input['phone'] ?? '') as String,
              role: (tc.input['role'] ?? '') as String,
            );
            result = 'contatto creato';
          } catch (e) {
            result = 'errore: $e';
          }
        case 'create_quote':
          try {
            final lines = ((tc.input['lines'] as List?) ?? [])
                .whereType<Map>()
                .map((l) => Map<String, dynamic>.from(l))
                .toList();
            await widget.onCreateQuote?.call(
              title: (tc.input['title'] ?? '') as String,
              companyId: (tc.input['company_id'] ?? '') as String,
              companyName: (tc.input['company_name'] ?? '') as String,
              estimatedValue: ((tc.input['estimated_value'] ?? 0) as num).toDouble(),
              lines: lines,
              notes: (tc.input['notes'] ?? '') as String,
            );
            result = 'preventivo creato';
          } catch (e) {
            result = 'errore: $e';
          }
        case 'create_ticket':
          try {
            await widget.onCreateTicket?.call(
              companyId: (tc.input['company_id'] ?? '') as String,
              companyName: (tc.input['company_name'] ?? '') as String,
              title: (tc.input['title'] ?? '') as String,
              body: (tc.input['body'] ?? '') as String,
            );
            result = 'ticket creato';
          } catch (e) {
            result = 'errore: $e';
          }
        case 'update_company':
          try {
            final changes = (tc.input['changes'] as Map?)?.cast<String, dynamic>() ?? {};
            await widget.onUpdateCompany?.call(
              companyId: (tc.input['company_id'] ?? '') as String,
              changes: changes,
            );
            result = 'società aggiornata';
          } catch (e) {
            result = 'errore: $e';
          }
        case 'update_contact':
          try {
            final changes = (tc.input['changes'] as Map?)?.cast<String, dynamic>() ?? {};
            await widget.onUpdateContact?.call(
              contactId: (tc.input['contact_id'] ?? '') as String,
              changes: changes,
            );
            result = 'contatto aggiornato';
          } catch (e) {
            result = 'errore: $e';
          }
        case 'update_opportunity':
          try {
            final changes = (tc.input['changes'] as Map?)?.cast<String, dynamic>() ?? {};
            await widget.onUpdateOpportunity?.call(
              opportunityId: (tc.input['opportunity_id'] ?? '') as String,
              changes: changes,
            );
            result = 'opportunità aggiornata';
          } catch (e) {
            result = 'errore: $e';
          }
        case 'update_project':
          try {
            final changes = (tc.input['changes'] as Map?)?.cast<String, dynamic>() ?? {};
            await widget.onUpdateProject?.call(
              projectId: (tc.input['project_id'] ?? '') as String,
              changes: changes,
            );
            result = 'progetto aggiornato';
          } catch (e) {
            result = 'errore: $e';
          }
        case 'update_task':
          try {
            final changes = (tc.input['changes'] as Map?)?.cast<String, dynamic>() ?? {};
            await widget.onUpdateTask?.call(
              taskId: (tc.input['task_id'] ?? '') as String,
              changes: changes,
            );
            result = 'task aggiornato';
          } catch (e) {
            result = 'errore: $e';
          }
        case 'update_quote':
          try {
            final changes = (tc.input['changes'] as Map?)?.cast<String, dynamic>() ?? {};
            await widget.onUpdateQuote?.call(
              quoteId: (tc.input['quote_id'] ?? '') as String,
              changes: changes,
            );
            result = 'preventivo aggiornato';
          } catch (e) {
            result = 'errore: $e';
          }
        case 'delete_contact':
          try {
            await widget.onDeleteContact?.call((tc.input['contact_id'] ?? '') as String);
            result = 'contatto eliminato';
          } catch (e) {
            result = 'errore: $e';
          }
        case 'delete_opportunity':
          try {
            await widget.onDeleteOpportunity?.call((tc.input['opportunity_id'] ?? '') as String);
            result = 'opportunità eliminata';
          } catch (e) {
            result = 'errore: $e';
          }
        case 'delete_task':
          try {
            await widget.onDeleteTask?.call((tc.input['task_id'] ?? '') as String);
            result = 'task eliminato';
          } catch (e) {
            result = 'errore: $e';
          }
        case 'delete_quote':
          try {
            await widget.onDeleteQuote?.call((tc.input['quote_id'] ?? '') as String);
            result = 'preventivo eliminato';
          } catch (e) {
            result = 'errore: $e';
          }
        case 'accept_quote':
          try {
            await widget.onAcceptQuote?.call(
              quoteId: (tc.input['quote_id'] ?? '') as String,
              opportunityId: (tc.input['opportunity_id'] ?? '') as String,
            );
            result = 'preventivo accettato';
          } catch (e) {
            result = 'errore: $e';
          }
        case 'schedule_task':
          try {
            final taskName = (tc.input['task_name'] ?? '') as String;
            String taskId = (tc.input['task_id'] ?? '') as String;

            // 1. Search workspace by ID.
            if (taskId.isEmpty && taskName.isNotEmpty) {
              final q = taskName.toLowerCase();
              final match = widget.workspaceContext.tasks
                  .where((t) => (t['name'] ?? '').toLowerCase().contains(q))
                  .firstOrNull;
              if (match != null) taskId = match['id'] ?? '';
            }

            // 2. Fallback: task appena creato in questo stesso turno AI (Firestore non ha ancora sincronizzato).
            if (taskId.isEmpty && _lastCreatedTask != null) {
              final last = _lastCreatedTask!;
              final q = taskName.toLowerCase();
              if (q.isEmpty ||
                  last.name.toLowerCase().contains(q) ||
                  q.contains('appena') ||
                  q.contains('creato') ||
                  q.contains('precedente') ||
                  q.contains('ultimo')) {
                taskId = last.id;
              }
            }

            if (taskId.isEmpty) {
              result = 'Task "$taskName" non trovato. Verifica il nome e riprova.';
            } else {
              final slots = ((tc.input['slots'] as List?) ?? [])
                  .whereType<Map>()
                  .map((s) => Map<String, dynamic>.from(s))
                  .toList();
              await widget.onScheduleTask?.call(
                taskId: taskId,
                taskName: taskName,
                slots: slots,
              );
              result = 'task pianificato';
            }
          } catch (e) {
            result = 'errore: $e';
          }
        case 'search_entity':
          // Executed entirely client-side — zero API tokens.
          result = _searchEntityLocally(
            (tc.input['entity_type'] ?? '') as String,
            (tc.input['query'] ?? '') as String,
          );
        case 'search_crm':
          // Executed client-side; add a synthetic results card.
          final srQuery = (tc.input['query'] ?? '') as String;
          final srResults = _searchAllLocally(srQuery);
          result = srResults.isEmpty ? 'Nessun risultato' : '${srResults.length} risultati trovati';
          if (!mounted) return;
          setState(() {
            conv.messages.add(AiMessage(
              role: AiRole.assistant,
              text: '',
              toolCalls: [
                AiToolCall(
                  id: 'local_sr_${DateTime.now().millisecondsSinceEpoch}',
                  name: 'search_crm',
                  input: {'query': srQuery, 'results': srResults},
                ),
              ],
              timestamp: DateTime.now(),
            ));
          });
        case 'generate_document':
        case 'generate_csv':
          result = 'documento generato';
      }

      final toolResultMsg = AiMessage(
        role: AiRole.user,
        text: result,
        toolResultFor: tc.id,
        timestamp: DateTime.now(),
      );
      if (!mounted) return;
      setState(() => conv.messages.add(toolResultMsg));
    }

    if (!mounted) return;

    final needsFollowUp = toolCalls.any((tc) => _toolsNeedingFollowUp.contains(tc.name));

    if (needsFollowUp) {
      // AI must see tool results (entity search, generated content) to continue — stream the follow-up.
      await _streamAndExecute(conv);
    } else {
      // No AI call needed: show local confirmation (0 tokens).
      final confirmTexts = toolCalls.map(_localConfirm).where((s) => s.isNotEmpty).join(' ');
      if (confirmTexts.isNotEmpty && mounted) {
        setState(() {
          conv.messages.add(AiMessage(
            role: AiRole.assistant,
            text: confirmTexts,
            timestamp: DateTime.now(),
          ));
        });
      }
    }
  }

  void _scrollToBottom() {
    // With reverse:true, offset 0 = bottom of chat (newest messages).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients && _scrollCtrl.position.pixels != 0) {
        _scrollCtrl.jumpTo(0);
      }
    });
  }

  String _generateId() =>
      DateTime.now().millisecondsSinceEpoch.toString() +
      math.Random().nextInt(9999).toString();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 680;
        if (narrow) return _buildMobile();
        return _buildDesktop();
      },
    );
  }

  Widget _buildDesktop() {
    return Row(
      children: [
        _Sidebar(
          conversations: _conversations,
          selectedId: _selectedId,
          onNew: _newConversation,
          onSelect: (id) => setState(() => _selectedId = id),
          onDelete: _deleteConversation,
        ),
        Expanded(child: _buildChat()),
      ],
    );
  }

  Widget _buildMobile() {
    if (_selectedId == null) {
      return _Sidebar(
        conversations: _conversations,
        selectedId: null,
        onNew: _newConversation,
        onSelect: (id) => setState(() => _selectedId = id),
        onDelete: _deleteConversation,
        fullWidth: true,
      );
    }
    return Column(
      children: [
        Container(
          height: 48,
          color: Colors.white.withValues(alpha: .72),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: () => setState(() => _selectedId = null),
              ),
              Expanded(
                child: Text(
                  _selected?.title ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(child: _buildChat()),
      ],
    );
  }

  Widget _buildChat() {
    final conv = _selected;
    if (conv == null) {
      return _EmptyState(onNew: _newConversation);
    }
    return Container(
      color: const Color(0xFFF7FBFF),
      child: Column(
        children: [
          Expanded(
            child: conv.messages.isEmpty
                ? _WelcomeHints(
                    onHint: (hint) {
                      _input.text = hint;
                      _send();
                    },
                  )
                : ListView.builder(
                    controller: _scrollCtrl,
                    reverse: true,
                    padding: const EdgeInsets.fromLTRB(0, 8, 0, 16),
                    itemCount: conv.messages.length,
                    itemBuilder: (context, i) {
                      // reverse: true → i=0 è l'ultimo messaggio (in fondo allo schermo)
                      final msgIndex = conv.messages.length - 1 - i;
                      final msg = conv.messages[msgIndex];
                      final streamingThis = msgIndex == conv.messages.length - 1 &&
                          _isStreaming && !msg.isUser;
                      return _buildMessage(msg, isStreaming: streamingThis);
                    },
                  ),
          ),
          if (widget.workspaceContext.pinnedSectionLabel != null)
            _ContextBanner(label: widget.workspaceContext.pinnedSectionLabel!),
          _InputBar(
            controller: _input,
            focusNode: _inputFocus,
            sending: _sending,
            onSend: _send,
          ),
        ],
      ),
    );
  }

  Widget _buildMessage(AiMessage msg, {bool isStreaming = false}) {
    if (msg.toolResultFor != null) return const SizedBox.shrink();

    if (msg.hasToolCalls) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (msg.text.isNotEmpty) _TextBubble(msg: msg, isStreaming: isStreaming),
          for (final tc in msg.toolCalls)
            _ToolCard(
              toolCall: tc,
              onOpenApp: widget.onOpenApp,
              onOpenCompany: widget.onOpenCompany,
            ),
        ],
      );
    }

    return _TextBubble(msg: msg, isStreaming: isStreaming);
  }
}
// ── Sidebar ─────────────────────────────────────────────────

class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.conversations,
    required this.selectedId,
    required this.onNew,
    required this.onSelect,
    required this.onDelete,
    this.fullWidth = false,
  });

  final List<AiConversation> conversations;
  final String? selectedId;
  final VoidCallback onNew;
  final ValueChanged<String> onSelect;
  final ValueChanged<String> onDelete;
  final bool fullWidth;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: fullWidth ? double.infinity : 240,
      decoration: BoxDecoration(
        color: GussoniBrand.surface,
        border: fullWidth
            ? null
            : const Border(right: BorderSide(color: GussoniBrand.border)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 16, 12, 8),
            child: InkWell(
              onTap: onNew,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: GussoniBrand.primaryBg,
                  border: Border.all(color: GussoniBrand.primaryBorder),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.add_rounded,
                      size: 18,
                      color: GussoniBrand.primary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Nuova chat',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: GussoniBrand.primary,
                      ),
                    ),
                    const Spacer(),
                    Icon(
                      Icons.edit_rounded,
                      size: 14,
                      color: GussoniBrand.textMuted,
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (conversations.isEmpty)
            Padding(
              padding: const EdgeInsets.all(20),
              child: Text(
                'Nessuna conversazione.\nPremi "Nuova chat" per iniziare.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  color: GussoniBrand.textMuted,
                  height: 1.5,
                ),
              ),
            )
          else
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 16),
                itemCount: conversations.length,
                itemBuilder: (context, i) {
                  final conv = conversations[i];
                  final selected = conv.id == selectedId;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Material(
                      color: selected
                          ? GussoniBrand.primaryBg
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(9),
                      child: InkWell(
                        onTap: () => onSelect(conv.id),
                        borderRadius: BorderRadius.circular(9),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(11, 9, 6, 9),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      conv.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                        color: selected
                                            ? GussoniBrand.primary
                                            : GussoniBrand.textPrimary,
                                      ),
                                    ),
                                    Text(
                                      _formatDate(conv.createdAt),
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: GussoniBrand.textMuted,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                onPressed: () => onDelete(conv.id),
                                icon: const Icon(
                                  Icons.close_rounded,
                                  size: 15,
                                  color: GussoniBrand.textMuted,
                                ),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(
                                  minWidth: 28,
                                  minHeight: 28,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: const BoxDecoration(
              border: Border(
                top: BorderSide(color: GussoniBrand.divider),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(999),
                    gradient: const LinearGradient(
                      colors: [Color(0xFF8B1A1A), Color(0xFFD2B48C)],
                    ),
                  ),
                  child: const Icon(
                    Icons.auto_awesome_rounded,
                    size: 16,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Nexora AI',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: GussoniBrand.textPrimary,
                      ),
                    ),
                    Text(
                      'Claude Sonnet',
                      style: TextStyle(
                        fontSize: 10,
                        color: GussoniBrand.textMuted,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inDays == 0) return 'Oggi';
    if (diff.inDays == 1) return 'Ieri';
    return '${dt.day}/${dt.month}/${dt.year}';
  }
}

// ── Empty state ──────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onNew});
  final VoidCallback onNew;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: const LinearGradient(
              colors: [Color(0xFF8B1A1A), Color(0xFFD2B48C)],
            ),
          ),
          child: const Icon(
            Icons.auto_awesome_rounded,
            size: 36,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 20),
        const Text(
          'Nexora AI',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w900,
            color: GussoniBrand.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Seleziona una conversazione o creane una nuova.',
          style: TextStyle(color: GussoniBrand.textMuted),
        ),
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: onNew,
          icon: const Icon(Icons.add_rounded, size: 18),
          label: const Text('Nuova chat'),
        ),
      ],
    ),
  );
}

// ── Welcome hints ────────────────────────────────────────────

class _WelcomeHints extends StatelessWidget {
  const _WelcomeHints({required this.onHint});
  final ValueChanged<String> onHint;

  static const _hints = [
    (
      Icons.receipt_long_rounded,
      'Crea preventivo',
      'Crea un preventivo per consulenza marketing da €3.500',
    ),
    (
      Icons.business_rounded,
      'Crea società',
      'Crea la società Bianchi Srl con email info@bianchi.it',
    ),
    (
      Icons.search_rounded,
      'Cerca nel CRM',
      'Cerca tutti i clienti con opportunità aperte',
    ),
    (
      Icons.email_outlined,
      'Scrivi un\'email',
      'Scrivi un\'email di follow-up per un cliente che non risponde da 2 settimane',
    ),
    (
      Icons.calendar_month_rounded,
      'Pianifica task',
      'Pianificami il task di revisione SEO domani dalle 9:00 alle 11:00',
    ),
  ];

  @override
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              gradient: const LinearGradient(
                colors: [Color(0xFF8B1A1A), Color(0xFFD2B48C)],
              ),
            ),
            child: const Icon(
              Icons.auto_awesome_rounded,
              size: 32,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Come posso aiutarti oggi?',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w900,
              color: GussoniBrand.textPrimary,
            ),
          ),
          const SizedBox(height: 28),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            alignment: WrapAlignment.center,
            children: [
              for (final hint in _hints)
                _HintChip(
                  icon: hint.$1,
                  label: hint.$2,
                  onTap: () => onHint(hint.$3),
                ),
            ],
          ),
        ],
      ),
    ),
  );
}

class _HintChip extends StatelessWidget {
  const _HintChip({
    required this.icon,
    required this.label,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    borderRadius: BorderRadius.circular(14),
    elevation: 0,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: GussoniBrand.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: GussoniBrand.primary),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: GussoniBrand.textPrimary,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

// ── Text bubble ──────────────────────────────────────────────

class _TextBubble extends StatelessWidget {
  const _TextBubble({required this.msg, this.isStreaming = false});
  final AiMessage msg;
  final bool isStreaming;

  @override
  Widget build(BuildContext context) {
    final isUser = msg.isUser;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        isUser ? 60 : 20,
        4,
        isUser ? 20 : 60,
        4,
      ),
      child: Align(
        alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
        child: Column(
          crossAxisAlignment:
              isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            if (!isUser)
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 6),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(7),
                        gradient: const LinearGradient(
                          colors: [Color(0xFF8B1A1A), Color(0xFFD2B48C)],
                        ),
                      ),
                      child: const Icon(
                        Icons.auto_awesome_rounded,
                        size: 12,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Text(
                      'Nexora AI',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: GussoniBrand.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18).copyWith(
                  bottomRight: isUser
                      ? const Radius.circular(4)
                      : const Radius.circular(18),
                  bottomLeft: isUser
                      ? const Radius.circular(18)
                      : const Radius.circular(4),
                ),
                color: isUser ? GussoniBrand.primary : Colors.white,
                border: isUser
                    ? null
                    : Border.all(color: GussoniBrand.border),
                boxShadow: isUser
                    ? null
                    : [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: .05),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
              ),
              child: _FormattedText(
                text: msg.text,
                color: isUser ? Colors.white : GussoniBrand.textPrimary,
                isError: msg.isError,
                isStreaming: isStreaming,
              ),
            ),
            if (!isUser && msg.text.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4, left: 4),
                child: InkWell(
                  onTap: () => Clipboard.setData(ClipboardData(text: msg.text)),
                  borderRadius: BorderRadius.circular(6),
                  child: const Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(
                      Icons.copy_rounded,
                      size: 13,
                      color: GussoniBrand.textMuted,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _FormattedText extends StatefulWidget {
  const _FormattedText({
    required this.text,
    required this.color,
    this.isError = false,
    this.isStreaming = false,
  });
  final String text;
  final Color color;
  final bool isError;
  final bool isStreaming;

  @override
  State<_FormattedText> createState() => _FormattedTextState();
}

class _FormattedTextState extends State<_FormattedText>
    with SingleTickerProviderStateMixin {
  late final AnimationController _cursorCtrl;

  @override
  void initState() {
    super.initState();
    _cursorCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 530),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _cursorCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isError) {
      return Text(
        widget.text,
        style: TextStyle(fontSize: 14, color: GussoniBrand.error, height: 1.55),
      );
    }

    if (widget.isStreaming) {
      return AnimatedBuilder(
        animation: _cursorCtrl,
        builder: (context, _) {
          final showCursor = _cursorCtrl.value > 0.5;
          return Text(
            widget.text.isEmpty && showCursor
                ? '▌'
                : widget.text + (showCursor ? '▌' : ''),
            style: TextStyle(fontSize: 14, color: widget.color, height: 1.55),
          );
        },
      );
    }

    return SelectableText(
      widget.text,
      style: TextStyle(fontSize: 14, color: widget.color, height: 1.55),
    );
  }
}

// ── Tool card ────────────────────────────────────────────────

class _ToolCard extends StatelessWidget {
  const _ToolCard({
    required this.toolCall,
    this.onOpenApp,
    this.onOpenCompany,
  });
  final AiToolCall toolCall;
  final void Function(String)? onOpenApp;
  final void Function(String, String)? onOpenCompany;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 6, 60, 6),
      child: switch (toolCall.name) {
        'generate_document' => _DocumentCard(toolCall: toolCall),
        'generate_csv'      => _CsvCard(toolCall: toolCall),
        'search_crm'        => _SearchResultCard(
            toolCall: toolCall,
            onOpenApp: onOpenApp,
            onOpenCompany: onOpenCompany,
          ),
        _                   => _ActionCard(toolCall: toolCall),
      },
    );
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({required this.toolCall});
  final AiToolCall toolCall;

  @override
  Widget build(BuildContext context) {
    final changes = toolCall.input['changes'] as Map?;
    final changesStr = changes != null
        ? changes.keys.take(3).join(', ')
        : '';
    final label = switch (toolCall.name) {
      'open_crm_section'    => 'Aperta: ${toolCall.input['label'] ?? toolCall.input['section']}',
      'open_company'        => 'Aperta scheda: ${toolCall.input['company_name']}',
      'create_opportunity'  => 'Opportunità creata: ${toolCall.input['title']}',
      'create_project'      => 'Progetto creato: ${toolCall.input['name']}',
      'create_task'         => 'Task creato: ${toolCall.input['name']}',
      'create_company'      => 'Società creata: ${toolCall.input['name']}',
      'create_contact'      => 'Contatto creato: ${toolCall.input['name']}',
      'create_quote'        => 'Preventivo creato: ${toolCall.input['title']}',
      'create_ticket'       => 'Ticket creato: ${toolCall.input['title']}',
      'update_company'      => 'Società aggiornata: ${toolCall.input['company_name']} ($changesStr)',
      'update_contact'      => 'Contatto aggiornato: ${toolCall.input['contact_name']} ($changesStr)',
      'update_opportunity'  => 'Opportunità aggiornata: ${toolCall.input['opportunity_title']} ($changesStr)',
      'update_project'      => 'Progetto aggiornato: ${toolCall.input['project_name']} ($changesStr)',
      'update_task'         => 'Task aggiornato: ${toolCall.input['task_name']} ($changesStr)',
      'update_quote'        => 'Preventivo aggiornato: ${toolCall.input['quote_title']} ($changesStr)',
      'delete_contact'      => 'Contatto eliminato: ${toolCall.input['contact_name']}',
      'delete_opportunity'  => 'Opportunità eliminata: ${toolCall.input['opportunity_title']}',
      'delete_task'         => 'Task eliminato: ${toolCall.input['task_name']}',
      'delete_quote'        => 'Preventivo eliminato: ${toolCall.input['quote_title']}',
      'accept_quote'        => 'Preventivo accettato: ${toolCall.input['quote_title']}',
      'schedule_task'       => 'Pianificato: ${toolCall.input['task_name']} (${(toolCall.input['slots'] as List?)?.length ?? 0} slot)',
      _                     => toolCall.name,
    };
    final icon = switch (toolCall.name) {
      'create_opportunity'                 => Icons.trending_up_rounded,
      'create_project'                     => Icons.folder_open_rounded,
      'create_task'                        => Icons.task_alt_rounded,
      'create_company'                     => Icons.business_rounded,
      'create_contact'                     => Icons.person_add_rounded,
      'create_quote'                       => Icons.receipt_long_rounded,
      'create_ticket'                      => Icons.confirmation_number_rounded,
      'update_company' || 'update_contact' ||
      'update_opportunity' || 'update_project' ||
      'update_task' || 'update_quote'      => Icons.edit_rounded,
      'delete_contact' || 'delete_opportunity' ||
      'delete_task' || 'delete_quote'      => Icons.delete_outline_rounded,
      'accept_quote'                       => Icons.check_circle_rounded,
      'schedule_task'                      => Icons.calendar_month_rounded,
      _                                    => Icons.bolt_rounded,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: GussoniBrand.primary.withValues(alpha: .06),
        border: Border.all(color: GussoniBrand.primary.withValues(alpha: .20)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: GussoniBrand.primary),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: GussoniBrand.primary,
            ),
          ),
        ],
      ),
    );
  }
}

class _DocumentCard extends StatelessWidget {
  const _DocumentCard({required this.toolCall});
  final AiToolCall toolCall;

  @override
  Widget build(BuildContext context) {
    final type = (toolCall.input['type'] ?? 'document') as String;
    final title = (toolCall.input['title'] ?? 'Documento') as String;
    final content = (toolCall.input['content'] ?? '') as String;
    final subject = toolCall.input['subject'] as String?;

    final icon = switch (type) {
      'email'  => Icons.email_outlined,
      'quote'  => Icons.request_quote_rounded,
      'report' => Icons.bar_chart_rounded,
      'letter' => Icons.description_rounded,
      _        => Icons.article_outlined,
    };

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: Colors.white,
        border: Border.all(color: GussoniBrand.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .05),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
            decoration: BoxDecoration(
              color: GussoniBrand.surfaceSubtle,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(15)),
            ),
            child: Row(
              children: [
                Icon(icon, size: 16, color: GussoniBrand.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: GussoniBrand.textPrimary,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () =>
                      Clipboard.setData(ClipboardData(text: content)),
                  icon: const Icon(Icons.copy_rounded, size: 15),
                  tooltip: 'Copia',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                  color: GussoniBrand.textMuted,
                ),
              ],
            ),
          ),
          if (subject != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
              child: Text(
                'Oggetto: $subject',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: GussoniBrand.textSecondary,
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: SelectableText(
              content,
              style: const TextStyle(
                fontSize: 13,
                height: 1.6,
                color: GussoniBrand.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CsvCard extends StatelessWidget {
  const _CsvCard({required this.toolCall});
  final AiToolCall toolCall;

  String _buildCsv() {
    final headers = ((toolCall.input['headers'] as List?) ?? [])
        .map((h) => '"${h.toString().replaceAll('"', '""')}"')
        .join(',');
    final rows = ((toolCall.input['rows'] as List?) ?? []).map((row) {
      if (row is! List) return '';
      return row.map((c) => '"${c.toString().replaceAll('"', '""')}"').join(',');
    }).join('\n');
    return '$headers\n$rows';
  }

  void _download(String csv, String filename) {
    aiDownloadCsv(csv, '$filename.csv');
  }

  @override
  Widget build(BuildContext context) {
    final filename = (toolCall.input['filename'] ?? 'nexora_export') as String;
    final headers = (toolCall.input['headers'] as List?)?.cast<String>() ?? [];
    final rows = (toolCall.input['rows'] as List?) ?? [];
    final csv = _buildCsv();

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: Colors.white,
        border: Border.all(color: GussoniBrand.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .05),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
            decoration: BoxDecoration(
              color: GussoniBrand.surfaceSubtle,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(15)),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.table_chart_rounded,
                  size: 16,
                  color: GussoniBrand.success,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '$filename.csv',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: GussoniBrand.textPrimary,
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: () => _download(csv, filename),
                  icon: const Icon(Icons.download_rounded, size: 14),
                  label: const Text('Scarica CSV'),
                  style: TextButton.styleFrom(
                    foregroundColor: GussoniBrand.success,
                    textStyle: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.all(14),
            child: Table(
              border: TableBorder.all(
                color: GussoniBrand.border,
                borderRadius: BorderRadius.circular(8),
              ),
              defaultColumnWidth: const IntrinsicColumnWidth(),
              children: [
                TableRow(
                  decoration: BoxDecoration(
                    color: GussoniBrand.surfaceSubtle,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(7),
                    ),
                  ),
                  children: [
                    for (final h in headers)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 7,
                        ),
                        child: Text(
                          h,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: GussoniBrand.textSecondary,
                          ),
                        ),
                      ),
                  ],
                ),
                for (final row in rows.take(8))
                  TableRow(
                    children: [
                      if (row is List)
                        for (final cell in row)
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            child: Text(
                              cell.toString(),
                              style: const TextStyle(
                                fontSize: 12,
                                color: GussoniBrand.textPrimary,
                              ),
                            ),
                          )
                      else
                        const SizedBox(),
                    ],
                  ),
              ],
            ),
          ),
          if (rows.length > 8)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
              child: Text(
                '+ ${rows.length - 8} altre righe nel file scaricabile.',
                style: const TextStyle(
                  fontSize: 11,
                  color: GussoniBrand.textMuted,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ── Search result card ───────────────────────────────────────

class _SearchResultCard extends StatelessWidget {
  const _SearchResultCard({
    required this.toolCall,
    this.onOpenApp,
    this.onOpenCompany,
  });
  final AiToolCall toolCall;
  final void Function(String)? onOpenApp;
  final void Function(String, String)? onOpenCompany;

  static const _sectionMap = {
    'opportunity': 'opportunities',
    'project': 'projects',
    'company': 'companies',
  };

  @override
  Widget build(BuildContext context) {
    final query = (toolCall.input['query'] ?? '') as String;
    final results = ((toolCall.input['results'] as List?) ?? [])
        .whereType<Map>()
        .toList();

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: Colors.white,
        border: Border.all(color: GussoniBrand.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .05),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
            decoration: BoxDecoration(
              color: GussoniBrand.surfaceSubtle,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(15)),
            ),
            child: Row(
              children: [
                Icon(Icons.search_rounded, size: 16, color: GussoniBrand.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Ricerca: $query',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: GussoniBrand.textPrimary,
                    ),
                  ),
                ),
                Text(
                  '${results.length} risultat${results.length == 1 ? 'o' : 'i'}',
                  style: const TextStyle(fontSize: 12, color: GussoniBrand.textMuted),
                ),
              ],
            ),
          ),
          if (results.isEmpty)
            const Padding(
              padding: EdgeInsets.all(14),
              child: Text(
                'Nessun risultato trovato.',
                style: TextStyle(fontSize: 13, color: GussoniBrand.textMuted),
              ),
            )
          else
            for (final r in results)
              _buildResultRow(r as Map<String, dynamic>),
        ],
      ),
    );
  }

  Widget _buildResultRow(Map<String, dynamic> r) {
    final type = (r['type'] ?? '') as String;
    final name = (r['name'] ?? '') as String;
    final detail = (r['detail'] ?? '') as String;
    final id = (r['id'] ?? '') as String;

    final icon = switch (type) {
      'company'     => Icons.business_rounded,
      'opportunity' => Icons.trending_up_rounded,
      'project'     => Icons.folder_open_rounded,
      _             => Icons.article_outlined,
    };

    return InkWell(
      onTap: () {
        if (type == 'company' && id.isNotEmpty) {
          onOpenCompany?.call(id, name);
        } else {
          final section = _sectionMap[type];
          if (section != null) onOpenApp?.call(section);
        }
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            Icon(icon, size: 16, color: GussoniBrand.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: GussoniBrand.textPrimary,
                    ),
                  ),
                  if (detail.isNotEmpty)
                    Text(
                      detail,
                      style: const TextStyle(
                        fontSize: 11,
                        color: GussoniBrand.textMuted,
                      ),
                    ),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios_rounded, size: 11, color: GussoniBrand.textMuted),
          ],
        ),
      ),
    );
  }
}

// ── Typing indicator ─────────────────────────────────────────

class _TypingIndicator extends StatefulWidget {
  const _TypingIndicator();

  @override
  State<_TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<_TypingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 60, 4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18).copyWith(
            bottomLeft: const Radius.circular(4),
          ),
          color: Colors.white,
          border: Border.all(color: GussoniBrand.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < 3; i++)
              AnimatedBuilder(
                animation: _ctrl,
                builder: (context, _) {
                  final phase = (_ctrl.value + i / 3) % 1.0;
                  final scale = 0.7 + 0.3 * math.sin(phase * math.pi);
                  return Container(
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    width: 7 * scale,
                    height: 7 * scale,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: GussoniBrand.textMuted,
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}

// ── Context banner ───────────────────────────────────────────

class _ContextBanner extends StatelessWidget {
  const _ContextBanner({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB),
        border: Border(
          top: BorderSide(color: const Color(0xFFFFB800).withValues(alpha: .28)),
          bottom: BorderSide(color: const Color(0xFFFFB800).withValues(alpha: .18)),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.star_rounded, size: 13, color: Color(0xFFFFB800)),
          const SizedBox(width: 6),
          Text(
            'Contesto: $label',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Color(0xFF7A5800),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Input bar ────────────────────────────────────────────────

class _InputBar extends StatelessWidget {
  const _InputBar({
    required this.controller,
    required this.focusNode,
    required this.sending,
    required this.onSend,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool sending;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          top: BorderSide(color: Colors.black.withValues(alpha: .07)),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: KeyboardListener(
              focusNode: FocusNode(),
              onKeyEvent: (event) {
                if (event is KeyDownEvent &&
                    event.logicalKey == LogicalKeyboardKey.enter &&
                    !HardwareKeyboard.instance.isShiftPressed) {
                  onSend();
                }
              },
              child: TextField(
                controller: controller,
                focusNode: focusNode,
                maxLines: 5,
                minLines: 1,
                enabled: !sending,
                style: const TextStyle(fontSize: 14),
                decoration: InputDecoration(
                  hintText:
                      'Chiedi qualcosa… (Invio per inviare, Shift+Invio per a capo)',
                  hintStyle: TextStyle(
                    fontSize: 13,
                    color: GussoniBrand.textMuted,
                  ),
                  filled: true,
                  fillColor: const Color(0xFFF4FAFF),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(
                      color: Colors.black.withValues(alpha: .08),
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(
                      color: Colors.black.withValues(alpha: .08),
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(
                      color: GussoniBrand.primary,
                      width: 1.5,
                    ),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            child: FilledButton(
              onPressed: sending ? null : onSend,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.all(14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: sending
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.arrow_upward_rounded, size: 20),
            ),
          ),
        ],
      ),
    );
  }
}
