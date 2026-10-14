/// One row of `public.group_messages`. Base columns since 0001_init:
/// `id, group_id, sender_id, body, created_at`. `sender_id` is nullable live
/// (0047 dropped NOT NULL so system notices such as "History Cleared" can be
/// inserted without an actor). `deleted_at`/`deleted_by` let the client show a
/// truthful "Message deleted" placeholder. `reply_to_id`/`edited_at` (0062)
/// and `pinned_at`/`pinned_by` (0120) back reply/edit/pin (Phase 3A).
/// `is_doubt`/`doubt_solved`/`solved_by`/`solved_reply_id`/`solved_at` (0122)
/// back Doubts (Phase 3B) — server CHECK constraints guarantee `is_doubt`
/// forbids `reply_to_id`, and the solved fields imply `doubt_solved` implies
/// `is_doubt`, so the client never needs to defend against those
/// combinations being inconsistent.
final class GroupMessage {
  const GroupMessage({
    required this.id,
    required this.groupId,
    required this.senderId,
    required this.body,
    required this.createdAt,
    this.messageType = 'text',
    this.deletedAt,
    this.deletedBy,
    this.metadata = const {},
    this.replyToId,
    this.editedAt,
    this.pinnedAt,
    this.pinnedBy,
    this.isDoubt = false,
    this.doubtSolved = false,
    this.solvedBy,
    this.solvedReplyId,
    this.solvedAt,
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

  /// Who deleted it (own-message delete or admin/owner delete-any, 0120).
  final String? deletedBy;

  /// The message this one is replying to, if any (`reply_to_id`, 0062).
  /// `ON DELETE SET NULL` server-side, so a reply whose parent was later
  /// deleted simply has this become null — the client never assumes the
  /// parent still exists just because this was once set.
  final String? replyToId;

  /// Set when the body was edited via `fn_edit_group_message` (0120).
  final DateTime? editedAt;

  /// Non-null while pinned (admin/owner only, max 3 per group, 0120).
  final DateTime? pinnedAt;
  final String? pinnedBy;

  /// Marked a doubt by its sender (own top-level message only, 0122).
  final bool isDoubt;

  /// True once the asker or an admin/owner has accepted a reply.
  final bool doubtSolved;

  /// Who accepted the reply (asker or admin/owner).
  final String? solvedBy;

  /// The accepted reply's message id. Server-side, deleting that reply
  /// clears this and flips [doubtSolved] back to false (0122 trigger).
  final String? solvedReplyId;
  final DateTime? solvedAt;

  bool get isSystem =>
      senderId == null ||
      messageType == 'system_event' ||
      messageType == 'system';
  bool get isSystemEvent => isSystem;
  bool get isAnnouncement => messageType == 'announcement';
  bool get isTestAnnouncement => messageType == 'test';
  bool get isDeleted => deletedAt != null;
  bool get isEdited => editedAt != null;
  bool get isPinned => pinnedAt != null;
  bool get isReply => replyToId != null;
  bool get isOpenDoubt => isDoubt && !doubtSolved;
  bool get isSolvedDoubt => isDoubt && doubtSolved;

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
      deletedBy: json['deleted_by'] as String?,
      metadata: (json['metadata'] as Map<String, dynamic>?) ?? const {},
      replyToId: json['reply_to_id'] as String?,
      editedAt: json['edited_at'] == null
          ? null
          : DateTime.parse(json['edited_at'] as String).toLocal(),
      pinnedAt: json['pinned_at'] == null
          ? null
          : DateTime.parse(json['pinned_at'] as String).toLocal(),
      pinnedBy: json['pinned_by'] as String?,
      isDoubt: json['is_doubt'] as bool? ?? false,
      doubtSolved: json['doubt_solved'] as bool? ?? false,
      solvedBy: json['solved_by'] as String?,
      solvedReplyId: json['solved_reply_id'] as String?,
      solvedAt: json['solved_at'] == null
          ? null
          : DateTime.parse(json['solved_at'] as String).toLocal(),
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
    if (deletedBy != null) 'deleted_by': deletedBy,
    if (metadata.isNotEmpty) 'metadata': metadata,
    if (replyToId != null) 'reply_to_id': replyToId,
    if (editedAt != null) 'edited_at': editedAt!.toUtc().toIso8601String(),
    if (pinnedAt != null) 'pinned_at': pinnedAt!.toUtc().toIso8601String(),
    if (pinnedBy != null) 'pinned_by': pinnedBy,
    if (isDoubt) 'is_doubt': isDoubt,
    if (doubtSolved) 'doubt_solved': doubtSolved,
    if (solvedBy != null) 'solved_by': solvedBy,
    if (solvedReplyId != null) 'solved_reply_id': solvedReplyId,
    if (solvedAt != null) 'solved_at': solvedAt!.toUtc().toIso8601String(),
  };

  /// `null` for a nullable field means "keep the current value" — pass the
  /// `Value`-wrapper-free sentinel pattern isn't worth it here since every
  /// call site clearing a field (unpin, parent-deleted) does so by copying
  /// the whole object fresh rather than via this helper.
  GroupMessage copyWith({
    String? body,
    DateTime? deletedAt,
    String? deletedBy,
    DateTime? editedAt,
    DateTime? pinnedAt,
    String? pinnedBy,
    bool? isDoubt,
    bool? doubtSolved,
    String? solvedBy,
    String? solvedReplyId,
    DateTime? solvedAt,
  }) => GroupMessage(
    id: id,
    groupId: groupId,
    senderId: senderId,
    body: body ?? this.body,
    createdAt: createdAt,
    messageType: messageType,
    deletedAt: deletedAt ?? this.deletedAt,
    deletedBy: deletedBy ?? this.deletedBy,
    metadata: metadata,
    replyToId: replyToId,
    editedAt: editedAt ?? this.editedAt,
    pinnedAt: pinnedAt ?? this.pinnedAt,
    pinnedBy: pinnedBy ?? this.pinnedBy,
    isDoubt: isDoubt ?? this.isDoubt,
    doubtSolved: doubtSolved ?? this.doubtSolved,
    solvedBy: solvedBy ?? this.solvedBy,
    solvedReplyId: solvedReplyId ?? this.solvedReplyId,
    solvedAt: solvedAt ?? this.solvedAt,
  );

  /// Clears is_doubt/doubt_solved/solved_* to their unmarked/unsolved
  /// state. Same reason pin-clear bypasses [copyWith] elsewhere in this
  /// class: `?? this.x` can never express "set back to null/false".
  GroupMessage clearDoubtState({bool clearIsDoubt = false}) => GroupMessage(
    id: id,
    groupId: groupId,
    senderId: senderId,
    body: body,
    createdAt: createdAt,
    messageType: messageType,
    deletedAt: deletedAt,
    deletedBy: deletedBy,
    metadata: metadata,
    replyToId: replyToId,
    editedAt: editedAt,
    pinnedAt: pinnedAt,
    pinnedBy: pinnedBy,
    isDoubt: clearIsDoubt ? false : isDoubt,
    doubtSolved: false,
    solvedBy: null,
    solvedReplyId: null,
    solvedAt: null,
  );

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
