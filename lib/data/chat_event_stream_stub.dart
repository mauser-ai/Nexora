import '../models/chat_models.dart';
import 'chat_event_stream_base.dart';

class _StubChatEventStream implements ChatEventStream {
  @override
  Stream<ChatRealtimeEvent> get events => const Stream.empty();

  @override
  void close() {}
}

ChatEventStream connectChatEventStream(Uri uri) => _StubChatEventStream();
