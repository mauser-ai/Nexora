import '../models/chat_models.dart';

abstract class ChatEventStream {
  Stream<ChatRealtimeEvent> get events;
  void close();
}
