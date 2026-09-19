/// One row of `public.group_announcements` — only the base columns the
/// migration set has carried since 0020 (and the 0033 repair re-creates):
/// `id, group_id, author_id, title, body, created_at, updated_at`.
/// Later optional columns (category, priority, status, pins, attachments…)
/// are never selected: the client stays correct whether or not they exist.
/// Every announcement belongs to exactly one group; `group_id` is the scope.
final class GroupAnnouncement {
  const GroupAnnouncement({
    required this.id,
    required this.groupId,
    required this.authorId,
    required this.title,
    required this.body,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Live CHECKs: title 1..120, body 1..2000 (char_length).
  static const maxTitleLength = 120;
  static const maxBodyLength = 2000;

  final String id;
  final String groupId;
  final String authorId;
  final String title;
  final String body;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory GroupAnnouncement.fromJson(Map<String, dynamic> json) {
    final created = DateTime.parse(json['created_at'] as String).toLocal();
    final updatedRaw = json['updated_at'] as String?;
    return GroupAnnouncement(
      id: json['id'] as String,
      groupId: json['group_id'] as String,
      authorId: json['author_id'] as String,
      title: json['title'] as String,
      body: json['body'] as String,
      createdAt: created,
      updatedAt: updatedRaw == null
          ? created
          : DateTime.parse(updatedRaw).toLocal(),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'group_id': groupId,
    'author_id': authorId,
    'title': title,
    'body': body,
    'created_at': createdAt.toUtc().toIso8601String(),
    'updated_at': updatedAt.toUtc().toIso8601String(),
  };

  bool get wasEdited => updatedAt.isAfter(createdAt);

  GroupAnnouncement copyWith({
    String? title,
    String? body,
    DateTime? updatedAt,
  }) {
    return GroupAnnouncement(
      id: id,
      groupId: groupId,
      authorId: authorId,
      title: title ?? this.title,
      body: body ?? this.body,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GroupAnnouncement &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          title == other.title &&
          body == other.body &&
          updatedAt == other.updatedAt;

  @override
  int get hashCode => Object.hash(id, title, body, updatedAt);
}
