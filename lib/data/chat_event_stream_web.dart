// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter

import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;

import '../models/chat_models.dart';
import 'chat_event_stream_base.dart';

class _WebChatEventStream implements ChatEventStream {
  _WebChatEventStream(Uri uri)
    : _source = html.EventSource(uri.toString()),
      _controller = StreamController<ChatRealtimeEvent>.broadcast() {
    _messageSub = _handleChatEvent;
    _connectedSub = _handleConnectedEvent;
    _source.addEventListener('chat', _messageSub);
    _source.addEventListener('connected', _connectedSub);
    _errorSub = _source.onError.listen((_) {
      if (!_controller.isClosed) {
        _controller.add(
          const ChatRealtimeEvent(
            type: 'stream_error',
            raw: {'type': 'stream_error'},
          ),
        );
      }
    });
  }

  final html.EventSource _source;
  final StreamController<ChatRealtimeEvent> _controller;
  StreamSubscription<html.Event>? _errorSub;
  late final html.EventListener _messageSub;
  late final html.EventListener _connectedSub;

  @override
  Stream<ChatRealtimeEvent> get events => _controller.stream;

  void _handleChatEvent(html.Event event) {
    if (event is! html.MessageEvent) return;
    final payload = _decodePayload(event.data);
    if (payload == null || _controller.isClosed) return;
    _controller.add(ChatRealtimeEvent.fromMap(payload));
  }

  void _handleConnectedEvent(html.Event event) {
    if (event is! html.MessageEvent) return;
    final payload = _decodePayload(event.data);
    if (payload == null || _controller.isClosed) return;
    _controller.add(ChatRealtimeEvent.fromMap(payload));
  }

  Map<String, dynamic>? _decodePayload(Object? raw) {
    if (raw is String && raw.isNotEmpty) {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
    }
    return null;
  }

  @override
  void close() {
    _errorSub?.cancel();
    _source.removeEventListener('chat', _messageSub);
    _source.removeEventListener('connected', _connectedSub);
    _source.close();
    _controller.close();
  }
}

ChatEventStream connectChatEventStream(Uri uri) => _WebChatEventStream(uri);
