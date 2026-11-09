import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import 'chat_event_stream.dart';
import 'chat_event_stream_base.dart';
import '../models/chat_models.dart';
import 'api_client.dart';

class ChatApiRepository {
  ChatApiRepository({ApiClient? client, http.Client? httpClient})
    : _api = client ?? ApiClient.instance,
      _http = httpClient ?? http.Client();

  final ApiClient _api;
  final http.Client _http;

  static const String _baseUrl = 'https://nexora.sviluppo.host/api/chat';

  Uri _buildUri(String script, [Map<String, String>? query]) {
    final base = '$_baseUrl/$script';
    if (query == null || query.isEmpty) {
      return Uri.parse(base);
    }
    return Uri.parse(base).replace(queryParameters: query);
  }

  Future<List<ChatGroup>> fetchGroups() async {
    final userId = FirebaseAuth.instance.currentUser?.uid ?? '';
    final response = await _http.get(
      _buildUri('groups/index.php', {'userId': userId}),
      headers: await _api.authorizedHeaders(
        extra: {'X-User-Id': userId},
        includeJsonContentType: false,
      ),
    );
    final payload = _decode(response);
    final rows = (payload['groups'] as List<dynamic>? ?? const []);
    return rows
        .map((item) => ChatGroup.fromMap(item as Map<String, dynamic>))
        .toList();
  }

  Future<ChatGroup> createGroup({
    required String name,
    String description = '',
    required List<Map<String, String>> members,
  }) async {
    final userId = FirebaseAuth.instance.currentUser?.uid ?? '';
    final response = await _http.post(
      _buildUri('groups/index.php'),
      headers: await _api.authorizedHeaders(extra: {'X-User-Id': userId}),
      body: jsonEncode({
        'userId': userId,
        'name': name,
        'description': description,
        'members': members,
      }),
    );
    final payload = _decode(response);
    return ChatGroup.fromMap(payload['group'] as Map<String, dynamic>);
  }

  Future<List<ChatMessage>> fetchMessages(String groupId) async {
    final userId = FirebaseAuth.instance.currentUser?.uid ?? '';
    final response = await _http.get(
      _buildUri('messages/index.php', {'groupId': groupId, 'userId': userId}),
      headers: await _api.authorizedHeaders(
        extra: {'X-User-Id': userId},
        includeJsonContentType: false,
      ),
    );
    final payload = _decode(response);
    final rows = (payload['messages'] as List<dynamic>? ?? const []);
    return rows
        .map(
          (item) => ChatMessage.fromMap(
            item as Map<String, dynamic>,
            currentUserId: userId,
          ),
        )
        .toList();
  }

  Future<ChatMessage> sendMessage({
    required String groupId,
    required String body,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    final userId = user?.uid ?? '';
    final response = await _http.post(
      _buildUri('messages/index.php'),
      headers: await _api.authorizedHeaders(extra: {'X-User-Id': userId}),
      body: jsonEncode({'userId': userId, 'groupId': groupId, 'body': body}),
    );
    final payload = _decode(response);
    return ChatMessage.fromMap(
      payload['message'] as Map<String, dynamic>,
      currentUserId: userId,
    );
  }

  Future<void> markGroupRead(String groupId) async {
    final userId = FirebaseAuth.instance.currentUser?.uid ?? '';
    final response = await _http.post(
      _buildUri('read.php'),
      headers: await _api.authorizedHeaders(extra: {'X-User-Id': userId}),
      body: jsonEncode({'userId': userId, 'groupId': groupId}),
    );
    _decode(response);
  }

  Future<ChatEventStream> openRealtimeStream() async {
    final token = await _api.ensureAccessToken();
    final uri = _buildUri('stream.php', {'access_token': token});
    return connectChatEventStream(uri);
  }

  Map<String, dynamic> _decode(http.Response response) {
    final body = response.body.isEmpty ? '{}' : response.body;
    final decoded = jsonDecode(body) as Map<String, dynamic>;
    if (response.statusCode >= 400) {
      throw ApiException(
        (decoded['error'] ?? 'Errore chat').toString(),
        statusCode: response.statusCode,
      );
    }
    return decoded;
  }
}
