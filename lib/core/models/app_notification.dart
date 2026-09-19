/// One row of the live `public.notifications` table (G16 audit, 2026-09-20):
/// `id, user_id, category notif_category, title, body, data jsonb, read_at,
/// created_at, priority, dedupe_key`. Rows are written server-side only
/// (`fn_notify_group` from the group triggers); the client reads its own rows
/// and sets `read_at`. Unread == `read_at IS NULL` — the live representation,
/// never a local flag.
final class AppNotification {
  const AppNotification({
    required this.id,
    required this.userId,
    required this.category,
    required this.title,
    required this.body,
    required this.data,
    required this.createdAt,
    this.readAt,
    this.priority = 'medium',
  });

  final String id;
  final String userId;

  /// Live `notif_category` label, e.g. `GROUP_MESSAGE`, `GROUP_ANNOUNCEMENT`,
  /// `TEST_INVITATION`. Kept as text: the enum has 23 values and the client
  /// must not drop rows it does not know.
  final String category;
  final String title;
  final String body;

  /// Server payload. Every group notification carries `group_id` (added by
  /// `fn_notify_group`) and a `type` written by the trigger.
  final Map<String, dynamic> data;
  final DateTime createdAt;
  final DateTime? readAt;
  final String priority;

  bool get isRead => readAt != null;

  /// `data->>'group_id'` — the group-scope key the live triggers always set.
  String? get groupId => data['group_id'] as String?;

  /// `data->>'type'` as written live: `group_message`, `group_announcement`,
  /// `group_join`, `group_test`. Null for rows without it.
  String? get type => data['type'] as String?;

  String? get messageId => data['message_id'] as String?;
  String? get announcementId => data['announcement_id'] as String?;
  String? get testId => data['test_id'] as String?;

  factory AppNotification.fromJson(Map<String, dynamic> json) {
    final raw = json['data'];
    return AppNotification(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      category: (json['category'] as String?) ?? '',
      title: (json['title'] as String?) ?? '',
      body: (json['body'] as String?) ?? '',
      data: raw is Map<String, dynamic> ? raw : const {},
      createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
      readAt: json['read_at'] == null
          ? null
          : DateTime.parse(json['read_at'] as String).toLocal(),
      priority: (json['priority'] as String?) ?? 'medium',
    );
  }

  AppNotification copyWith({DateTime? readAt}) => AppNotification(
    id: id,
    userId: userId,
    category: category,
    title: title,
    body: body,
    data: data,
    createdAt: createdAt,
    readAt: readAt ?? this.readAt,
    priority: priority,
  );
}
