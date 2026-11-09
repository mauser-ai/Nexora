import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/ai_models.dart';

class AiWorkspaceContext {
  const AiWorkspaceContext({
    this.companies = const [],
    this.deals = const [],
    this.projects = const [],
    this.tasks = const [],
    this.quotes = const [],
    this.tickets = const [],
    this.contacts = const [],
    this.pinnedSectionId,
    this.pinnedSectionLabel,
  });

  final List<Map<String, String>> companies;
  final List<Map<String, String>> deals;
  final List<Map<String, String>> projects;
  final List<Map<String, String>> tasks;
  final List<Map<String, String>> quotes;
  final List<Map<String, String>> tickets;
  final List<Map<String, String>> contacts;
  final String? pinnedSectionId;
  final String? pinnedSectionLabel;

  // Only send entity counts — full data stays on client for local search_entity resolution.
  Map<String, dynamic> toJson() => {
    'counts': {
      'companies': companies.length,
      'contacts': contacts.length,
      'opportunities': deals.length,
      'projects': projects.length,
      'tasks': tasks.length,
      'quotes': quotes.length,
      'tickets': tickets.length,
    },
    if (pinnedSectionId != null) 'pinned_section': pinnedSectionId,
    if (pinnedSectionLabel != null) 'pinned_section_label': pinnedSectionLabel,
  };
}

class AiService {
  AiService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const String _basePath = String.fromEnvironment(
    'AI_API_BASE',
    defaultValue: '/ai/api',
  );
  static const String _apiOrigin = String.fromEnvironment(
    'ARCHIVE_API_ORIGIN',
    defaultValue: 'https://nexora.sviluppo.host',
  );

  Uri _uri(String script) {
    final base = _basePath.endsWith('/') ? _basePath : '$_basePath/';
    final target = '$base$script';
    if (target.startsWith('http') || kIsWeb) return Uri.parse(target);
    return Uri.parse('$_apiOrigin$target');
  }

  List<Map<String, dynamic>> _buildApiMessages(List<AiMessage> messages) {
    final result = <Map<String, dynamic>>[];
    for (final msg in messages) {
      final content = msg.toApiContent();
      result.add({
        'role': msg.isUser ? 'user' : 'assistant',
        'content': content.length == 1 && content.first['type'] == 'text'
            ? content.first['text']
            : content,
      });
    }
    return result;
  }

  /// Streaming chat — yields text deltas word by word, then tool calls, then done.
  Stream<AiStreamEvent> chatStream({
    required List<AiMessage> messages,
    required AiWorkspaceContext workspaceContext,
  }) async* {
    final request = http.Request('POST', _uri('chat.php'));
    request.headers['Content-Type'] = 'application/json; charset=utf-8';
    request.body = jsonEncode({
      'messages': _buildApiMessages(messages),
      'workspace_context': workspaceContext.toJson(),
      'stream': true,
    });

    http.StreamedResponse response;
    try {
      response = await _client.send(request);
    } catch (e) {
      yield AiStreamEvent.error('Errore connessione: $e');
      return;
    }

    if (response.statusCode >= 400) {
      String msg = 'Errore HTTP ${response.statusCode}';
      try {
        final body = await response.stream.bytesToString();
        final json = jsonDecode(body) as Map;
        msg = (json['error'] ?? msg) as String;
      } catch (_) {}
      yield AiStreamEvent.error(msg);
      return;
    }

    final lineBuf = StringBuffer();

    await for (final chunk in response.stream.transform(utf8.decoder)) {
      lineBuf.write(chunk);

      while (true) {
        final str = lineBuf.toString();
        final pos = str.indexOf('\n');
        if (pos == -1) break;

        final line = str.substring(0, pos).trim();
        lineBuf.clear();
        lineBuf.write(str.substring(pos + 1));
        if (line.isEmpty) continue;

        try {
          final evt = jsonDecode(line) as Map<String, dynamic>;
          switch (evt['type'] as String?) {
            case 'text':
              yield AiStreamEvent.text((evt['delta'] as String?) ?? '');
            case 'tool_use':
              yield AiStreamEvent.toolUse(
                AiToolCall(
                  id: (evt['id'] as String?) ?? '',
                  name: (evt['name'] as String?) ?? '',
                  input: (evt['input'] as Map?)?.cast<String, dynamic>() ?? {},
                ),
              );
            case 'done':
              yield AiStreamEvent.done((evt['stop_reason'] as String?) ?? '');
            case 'error':
              yield AiStreamEvent.error(
                (evt['message'] as String?) ?? 'Errore',
              );
          }
        } catch (_) {}
      }
    }
  }
}
