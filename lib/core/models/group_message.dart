/// One row of `public.group_messages` — only the base columns the migration
/// set has carried since 0001_init:
/// `id, group_id, sender_id, body, created_at`.
/// Later optional columns (message_type, metadata) are never selected, so the
/// client stays correct whether or not they exist live. `sender_id` is nullable
/// live (0047 dropped NOT NULL so system notices such as "History Cleared" can
/// be inserted without an actor). `deleted_at` is selected so the client can
/// show a truthful "Message deleted" placeholder instead of the original body.
final class GroupMessage {
  const GroupMessage({
    required this.id,
    required this.groupId,
    required this.senderId,
    required this.body,
    required this.createdAt,
    this.messageType = 'text',
    this.deletedAt,
  });

  /// Live CHECK: `char_length(body) BETWEEN 1 AND 2000`.
  static const maxBodyLength = 2000;

  final String id;
  final String groupId;

  /// Null for server-inserted system notices.
  final String? senderId;
  final String body;
  final DateTime createdAt;
  final String messageType;

  /// Non-null when the message has been soft-deleted. The client must show
  /// "Message deleted" instead of [body] and must not expose the original
  /// content.
  final DateTime? deletedAt;

  bool get isSystem => senderId == null || messageType == 'system_event';
  bool get isSystemEvent => isSystem;
  bool get isDeleted => deletedAt != null;

  factory GroupMessage.fromJson(Map<String, dynamic> json) {
    return GroupMessage(
      id: json['id'] as String,
      groupId: json['group_id'] as String,
      senderId: json['sender_id'] as String?,
      body: json['body'] as String,
      createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
      messageType: (json['message_type'] as String?) ?? 'text',
      deletedAt: json['deleted_at'] == null
          ? null
          : DateTime.parse(json['deleted_at'] as String).toLocal(),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'group_id': groupId,
    'sender_id': senderId,
    'body': body,
    'message_type': messageType,
    'created_at': createdAt.toUtc().toIso8601String(),
    if (deletedAt != null) 'deleted_at': deletedAt!.toUtc().toIso8601String(),
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GroupMessage &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          body == other.body &&
          createdAt == other.createdAt;

  @override
  int get hashCode => Object.hash(id, body, createdAt);
}
