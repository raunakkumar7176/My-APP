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
    this.metadata = const {},
  });

  /// Live CHECK: `char_length(body) BETWEEN 1 AND 2000`.
  static const maxBodyLength = 2000;

  final String id;
  final String groupId;

  /// Null for server-inserted system notices.
  final String? senderId;
  final String body;
  final DateTime createdAt;

  /// `'text' | 'system_event' | 'system' | 'announcement' | 'test' |
  /// 'activity' | 'question' | 'solution'` (live CHECK, migration 0062).
  /// `'system'`/`'announcement'`/`'test'` are auto-posted by
  /// `fn_insert_system_message` (migration 0039) with real sender ids (the
  /// acting user, falling back to the group owner) — never null — so
  /// [isSystem] cannot key on a null sender alone.
  final String messageType;

  /// `group_messages.metadata` (jsonb, migration 0039+). Carries the extra
  /// fields a system-posted message needs to render richly — e.g. a test
  /// announcement's `test_id`/`title`; empty for an ordinary text message.
  final Map<String, dynamic> metadata;

  /// Non-null when the message has been soft-deleted. The client must show
  /// "Message deleted" instead of [body] and must not expose the original
  /// content.
  final DateTime? deletedAt;

  bool get isSystem =>
      senderId == null ||
      messageType == 'system_event' ||
      messageType == 'system';
  bool get isSystemEvent => isSystem;
  bool get isAnnouncement => messageType == 'announcement';
  bool get isTestAnnouncement => messageType == 'test';
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
      metadata: (json['metadata'] as Map<String, dynamic>?) ?? const {},
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
    if (metadata.isNotEmpty) 'metadata': metadata,
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
