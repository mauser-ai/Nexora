import 'chat_event_stream_base.dart';
import 'chat_event_stream_stub.dart'
    if (dart.library.html) 'chat_event_stream_web.dart'
    as impl;

ChatEventStream connectChatEventStream(Uri uri) =>
    impl.connectChatEventStream(uri);
