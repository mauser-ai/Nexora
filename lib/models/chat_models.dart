class ChatGroupMember {
  const ChatGroupMember({
    required this.userId,
    required this.displayName,
    required this.email,
    this.role = '',
    this.isOnline = false,
  });

  final String userId;
  final String displayName;
  final String email;
  final String role;
  final bool isOnline;

  factory ChatGroupMember.fromMap(Map<String, dynamic> map) {
    return ChatGroupMember(
      userId: (map['userId'] ?? '') as String,
      displayName: (map['displayName'] ?? '') as String,
      email: (map['email'] ?? '') as String,
      role: (map['role'] ?? '') as String,
      isOnline: map['isOnline'] == true || map['isOnline'] == 1,
    );
  }
}

class ChatGroup {
  const ChatGroup({
    required this.id,
    required this.name,
    required this.description,
    required this.createdAt,
    required this.members,
    this.lastMessageSnippet = '',
    this.lastMessageAt,
    this.unreadCount = 0,
  });

  final String id;
  final String name;
  final String description;
  final DateTime createdAt;
  final List<ChatGroupMember> members;
  final String lastMessageSnippet;
  final DateTime? lastMessageAt;
  final int unreadCount;

  factory ChatGroup.fromMap(Map<String, dynamic> map) {
    final membersRaw = (map['members'] as List<dynamic>? ?? const []);
    return ChatGroup(
      id: (map['id'] ?? '') as String,
      name: (map['name'] ?? '') as String,
      description: (map['description'] ?? '') as String,
      createdAt:
          DateTime.tryParse((map['createdAt'] ?? '') as String) ??
          DateTime.now(),
      members: membersRaw
          .map((item) => ChatGroupMember.fromMap(item as Map<String, dynamic>))
          .toList(),
      lastMessageSnippet: (map['lastMessageSnippet'] ?? '') as String,
      lastMessageAt: map['lastMessageAt'] == null
          ? null
          : DateTime.tryParse(map['lastMessageAt'] as String),
      unreadCount: (map['unreadCount'] as num?)?.toInt() ?? 0,
    );
  }
}

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.groupId,
    required this.userId,
    required this.authorName,
    required this.body,
    required this.createdAt,
    this.isMine = false,
  });

  final String id;
  final String groupId;
  final String userId;
  final String authorName;
  final String body;
  final DateTime createdAt;
  final bool isMine;

  factory ChatMessage.fromMap(
    Map<String, dynamic> map, {
    required String currentUserId,
  }) {
    final userId = (map['userId'] ?? '') as String;
    return ChatMessage(
      id: (map['id'] ?? '') as String,
      groupId: (map['groupId'] ?? '') as String,
      userId: userId,
      authorName: (map['authorName'] ?? '') as String,
      body: (map['body'] ?? '') as String,
      createdAt:
          DateTime.tryParse((map['createdAt'] ?? '') as String) ??
          DateTime.now(),
      isMine: userId == currentUserId,
    );
  }
}

class ChatRealtimeEvent {
  const ChatRealtimeEvent({
    required this.type,
    this.groupId,
    this.messageId,
    this.raw = const {},
  });

  final String type;
  final String? groupId;
  final String? messageId;
  final Map<String, dynamic> raw;

  factory ChatRealtimeEvent.fromMap(Map<String, dynamic> map) {
    return ChatRealtimeEvent(
      type: (map['type'] ?? '') as String,
      groupId: map['groupId'] as String?,
      messageId: map['messageId'] as String?,
      raw: map,
    );
  }
}
