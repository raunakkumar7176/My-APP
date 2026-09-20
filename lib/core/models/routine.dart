/// A daily study routine task (maps to `routines` table).
///
/// RLS ensures users can only access their own routines.
/// Wall-clock times (`start_time`, `end_time`) are `time without time zone`.
/// `weekdays` uses PG/JS numbering: 0 = Sunday … 6 = Saturday.
final class Routine {
  const Routine({
    required this.id,
    required this.userId,
    this.subjectId,
    this.title = '',
    required this.startTime,
    required this.endTime,
    this.weekdays = const [0, 1, 2, 3, 4, 5, 6],
    this.reminderEnabled = true,
    this.isActive = true,
    this.targetDurationMinutes,
    required this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String userId;
  final String? subjectId;
  final String title;

  /// `HH:MM` or `HH:MM:SS` wall-clock string.
  final String startTime;
  final String endTime;

  /// 0 = Sunday … 6 = Saturday.
  final List<int> weekdays;
  final bool reminderEnabled;
  final bool isActive;
  final int? targetDurationMinutes;
  final DateTime createdAt;
  final DateTime? updatedAt;

  /// Duration in minutes derived from start/end times.
  int? get computedDurationMinutes {
    final start = _parseTime(startTime);
    final end = _parseTime(endTime);
    if (start == null || end == null) return null;
    var diff = end - start;
    if (diff <= 0) diff += 24 * 60; // overnight span
    return diff;
  }

  /// Whether this routine recurs on the given live weekday (0 = Sunday …
  /// 6 = Saturday). The caller decides what "today" is (user timezone).
  bool isScheduledOn(int weekday) => weekdays.contains(weekday);

  factory Routine.fromJson(Map<String, dynamic> json) {
    return Routine(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      subjectId: json['subject_id'] as String?,
      title: (json['title'] as String?)?.trim().isEmpty == true
          ? 'Study routine'
          : (json['title'] as String?) ?? 'Study routine',
      startTime: json['start_time'] as String? ?? '00:00',
      endTime: json['end_time'] as String? ?? '00:00',
      weekdays: [
        for (final w in (json['weekdays'] as List? ?? const []))
          (w as num).toInt(),
      ],
      reminderEnabled: json['reminder_enabled'] as bool? ?? true,
      isActive: json['is_active'] as bool? ?? true,
      targetDurationMinutes: (json['target_duration_minutes'] as num?)?.toInt(),
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      updatedAt: json['updated_at'] != null
          ? DateTime.tryParse(json['updated_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toInsertJson() {
    return {
      'subject_id': subjectId,
      'title': title,
      'start_time': startTime,
      'end_time': endTime,
      'weekdays': weekdays,
      'reminder_enabled': reminderEnabled,
      'is_active': isActive,
      if (targetDurationMinutes != null)
        'target_duration_minutes': targetDurationMinutes,
    };
  }

  /// Parses `HH:MM` or `HH:MM:SS` to total minutes since midnight.
  static int? _parseTime(String t) {
    final parts = t.split(':');
    if (parts.length < 2) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) return null;
    return h * 60 + m;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Routine &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}
