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
    this.dedupeKey,
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

  /// Deterministic idempotency key for deduplication (server-generated).
  final String? dedupeKey;

  bool get isRead => readAt != null;

  /// `data->>'group_id'` — the group-scope key the live triggers always set.
  String? get groupId => data['group_id'] as String?;

  /// `data->>'type'` as written live: `group_message`, `group_announcement`,
  /// `group_join`, `group_test`. Null for rows without it.
  String? get type => data['type'] as String?;

  String? get messageId => data['message_id'] as String?;
  String? get announcementId => data['announcement_id'] as String?;
  String? get testId => data['test_id'] as String?;

  /// Deep link path from `data->>'deep_link'`. Used for notification tap
  /// navigation. Must be validated server-side before navigation.
  String? get deepLink => data['deep_link'] as String?;

  /// Routine ID from `data->>'routine_id'`.
  String? get routineId => data['routine_id'] as String?;

  /// Idempotency key from `data->>'idempotency_key'`.
  String? get idempotencyKey => data['idempotency_key'] as String?;

  /// Reminder key from `data->>'reminder'` (e.g. '24h', '1h', '10m').
  String? get reminderKey => data['reminder'] as String?;

  /// Spec type from `data->>'spec_type'` (e.g. 'test_reminder', 'routine_reminder').
  String? get specType => data['spec_type'] as String?;

  /// Notification category as a normalized enum-like string.
  NotificationCategory get parsedCategory =>
      NotificationCategory.fromString(category);

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
      dedupeKey: json['dedupe_key'] as String?,
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
    dedupeKey: dedupeKey,
  );
}

/// Canonical notification categories. Maps to the `notif_category` PostgreSQL
/// enum. Kept as a Dart enum for type safety; `fromString` is tolerant of
/// unknown values so the client never drops rows.
enum NotificationCategory {
  groupMessage('GROUP_MESSAGE'),
  groupAnnouncement('GROUP_ANNOUNCEMENT'),
  groupJoin('GROUP_JOIN'),
  testReminder('TEST_REMINDER'),
  testLive('TEST_LIVE'),
  testCompleted('TEST_COMPLETED'),
  testInvitation('TEST_INVITATION'),
  testScheduled('TEST_SCHEDULED'),
  testStartingSoon('TEST_STARTING_SOON'),
  testStarted('TEST_STARTED'),
  testEnded('TEST_ENDED'),
  resultsAvailable('RESULTS_AVAILABLE'),
  leaderboardUpdated('LEADERBOARD_UPDATED'),
  routineReminder('ROUTINE_REMINDER'),
  routineDue('ROUTINE_DUE'),
  routineMissed('ROUTINE_MISSED'),
  routineCompleted('ROUTINE_COMPLETED'),
  streakMilestone('STREAK_MILESTONE'),
  groupTestAssigned('GROUP_TEST_ASSIGNED'),
  groupTestReminder('GROUP_TEST_REMINDER'),
  contentReviewResult('CONTENT_REVIEW_RESULT'),
  reportReady('REPORT_READY'),
  systemNotification('SYSTEM_NOTIFICATION'),
  groupJoinRequest('GROUP_JOIN_REQUEST'),
  joinAccepted('JOIN_ACCEPTED'),
  joinRejected('JOIN_REJECTED'),
  roleChanged('ROLE_CHANGED'),
  memberRemoved('MEMBER_REMOVED'),
  unknown('UNKNOWN');

  const NotificationCategory(this.label);
  final String label;

  static NotificationCategory fromString(String? value) {
    if (value == null) return unknown;
    for (final cat in values) {
      if (cat.label == value.toUpperCase()) return cat;
    }
    return unknown;
  }

  bool get isGroupRelated => switch (this) {
    groupMessage || groupAnnouncement || groupJoin || groupTestAssigned ||
    groupTestReminder || groupJoinRequest || joinAccepted || joinRejected ||
    roleChanged || memberRemoved => true,
    _ => false,
  };

  bool get isTestRelated => switch (this) {
    testReminder || testLive || testCompleted || testInvitation || testScheduled ||
    testStartingSoon || testStarted || testEnded || resultsAvailable ||
    leaderboardUpdated || groupTestAssigned || groupTestReminder => true,
    _ => false,
  };

  bool get isRoutineRelated => switch (this) {
    routineReminder || routineDue || routineMissed || routineCompleted || streakMilestone => true,
    _ => false,
  };

  /// The 4 broad buckets the Notification Center's filter chips group into.
  /// Derived from the existing `is*Related` flags — routine wins over group
  /// (a group-test reminder is still fundamentally "when do I sit the
  /// test", i.e. test-related, which `isTestRelated` already covers first).
  NotificationBroadCategory get broadCategory {
    if (isTestRelated) return NotificationBroadCategory.tests;
    if (isRoutineRelated) return NotificationBroadCategory.routine;
    if (isGroupRelated) return NotificationBroadCategory.groups;
    return NotificationBroadCategory.system;
  }

  /// A short call-to-action label for the notification card's action
  /// button, or null when tapping the card itself (default: open the deep
  /// link) is the only real action — never invents an action that doesn't
  /// correspond to where the deep link actually goes.
  String? get actionLabel => switch (this) {
    testLive || testStarted || testStartingSoon => 'Start Test',
    resultsAvailable => 'View Result',
    leaderboardUpdated => 'View Leaderboard',
    routineReminder || routineDue => 'Open Routine',
    groupMessage || groupAnnouncement => 'Open Chat',
    groupJoinRequest => 'Review Request',
    _ => null,
  };
}

/// The 4 broad groupings shown as filter chips in the Notification Center.
/// Deliberately just a label here (no `Color`/`IconData`) so this model file
/// stays pure Dart, matching every other model in `core/models/` — the
/// widget layer (`notification_tile.dart`) owns the visual mapping.
enum NotificationBroadCategory {
  tests('Tests'),
  routine('Routine'),
  groups('Groups'),
  system('System');

  const NotificationBroadCategory(this.label);
  final String label;
}
