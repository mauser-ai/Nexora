import 'dart:convert';

import 'package:flutter/foundation.dart';

enum AiRole { user, assistant }

// ── Streaming events ─────────────────────────────────────────
enum AiStreamEventType { text, toolUse, done, error }

/// Bump per notificare alle altre viste (modulo AI ↔ chatbot flottante)
/// che la lista conversazioni in localStorage è cambiata.
final ValueNotifier<int> aiConversationsRevision = ValueNotifier<int>(0);

class AiStreamEvent {
  const AiStreamEvent._({
    required this.type,
    this.text,
    this.toolCall,
    this.stopReason,
    this.error,
  });

  final AiStreamEventType type;
  final String? text;
  final AiToolCall? toolCall;
  final String? stopReason;
  final String? error;

  factory AiStreamEvent.text(String delta) =>
      AiStreamEvent._(type: AiStreamEventType.text, text: delta);
  factory AiStreamEvent.toolUse(AiToolCall tc) =>
      AiStreamEvent._(type: AiStreamEventType.toolUse, toolCall: tc);
  factory AiStreamEvent.done(String stopReason) =>
      AiStreamEvent._(type: AiStreamEventType.done, stopReason: stopReason);
  factory AiStreamEvent.error(String msg) =>
      AiStreamEvent._(type: AiStreamEventType.error, error: msg);
}

class AiToolCall {
  const AiToolCall({
    required this.id,
    required this.name,
    required this.input,
  });

  final String id;
  final String name;
  final Map<String, dynamic> input;

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'input': input};

  factory AiToolCall.fromJson(Map<String, dynamic> json) => AiToolCall(
    id: (json['id'] ?? '') as String,
    name: (json['name'] ?? '') as String,
    input: (json['input'] as Map?)?.cast<String, dynamic>() ?? {},
  );
}

class AiMessage {
  const AiMessage({
    required this.role,
    required this.text,
    this.toolCalls = const [],
    this.toolResultFor,
    this.isError = false,
    this.timestamp,
  });

  final AiRole role;
  final String text;
  final List<AiToolCall> toolCalls;
  final String? toolResultFor;
  final bool isError;
  final DateTime? timestamp;

  bool get hasToolCalls => toolCalls.isNotEmpty;
  bool get isUser => role == AiRole.user;

  Map<String, dynamic> toJson() => {
    'role': role.name,
    'text': text,
    'tool_calls': toolCalls.map((t) => t.toJson()).toList(),
    'tool_result_for': toolResultFor,
    'is_error': isError,
    'timestamp': timestamp?.toIso8601String(),
  };

  factory AiMessage.fromJson(Map<String, dynamic> json) => AiMessage(
    role: AiRole.values.firstWhere(
      (r) => r.name == json['role'],
      orElse: () => AiRole.user,
    ),
    text: (json['text'] ?? '') as String,
    toolCalls: ((json['tool_calls'] as List?) ?? [])
        .map((t) => AiToolCall.fromJson(t as Map<String, dynamic>))
        .toList(),
    toolResultFor: json['tool_result_for'] as String?,
    isError: (json['is_error'] ?? false) as bool,
    timestamp: json['timestamp'] == null
        ? null
        : DateTime.tryParse(json['timestamp'] as String),
  );

  /// Serializes to the format expected by Claude API.
  List<Map<String, dynamic>> toApiContent() {
    if (toolCalls.isNotEmpty) {
      final blocks = <Map<String, dynamic>>[];
      if (text.isNotEmpty) blocks.add({'type': 'text', 'text': text});
      for (final tc in toolCalls) {
        blocks.add({'type': 'tool_use', 'id': tc.id, 'name': tc.name, 'input': tc.input});
      }
      return blocks;
    }
    if (toolResultFor != null) {
      return [{'type': 'tool_result', 'tool_use_id': toolResultFor, 'content': text}];
    }
    return [{'type': 'text', 'text': text}];
  }
}

class AiConversation {
  AiConversation({
    required this.id,
    required this.title,
    required this.messages,
    required this.createdAt,
  });

  final String id;
  String title;
  final List<AiMessage> messages;
  final DateTime createdAt;

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'messages': messages.map((m) => m.toJson()).toList(),
    'created_at': createdAt.toIso8601String(),
  };

  factory AiConversation.fromJson(Map<String, dynamic> json) => AiConversation(
    id: (json['id'] ?? '') as String,
    title: (json['title'] ?? 'Conversazione') as String,
    messages: ((json['messages'] as List?) ?? [])
        .map((m) => AiMessage.fromJson(m as Map<String, dynamic>))
        .toList(),
    createdAt: DateTime.tryParse((json['created_at'] ?? '') as String) ??
        DateTime.now(),
  );

  static List<AiConversation> listFromJson(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return decoded
          .map((e) => AiConversation.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static String listToJson(List<AiConversation> list) =>
      jsonEncode(list.map((c) => c.toJson()).toList());
}
