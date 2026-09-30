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
    this.chapterId,
    this.topicId,
    this.sessionType = 'study',
    this.hasAlarm = false,
    this.alarmLeadMinutes = 0,
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

  /// `public.chapters.id` (Study module) this session covers, if linked.
  final String? chapterId;

  /// `public.topics.id` (Study module) this session covers, if linked.
  final String? topicId;

  /// 'study' | 'revision' | 'memorization' | 'practice' | 'test' | 'break' | 'chore'.
  final String sessionType;

  /// Whether [AcademicAlarmService] should schedule a local alarm for this
  /// session's start time.
  final bool hasAlarm;

  /// 0 = alarm at the exact start time; >0 = that many minutes before.
  final int alarmLeadMinutes;

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

  /// Whether [endTime] has already passed, given [nowInUserZone]'s
  /// hour/minute (e.g. `CalendarClock.toUserWall(DateTime.now())`) — the
  /// caller supplies "now" so this never reads the raw device clock itself.
  bool hasEndedBy(DateTime nowInUserZone) {
    final end = _parseTime(endTime);
    if (end == null) return false;
    final nowMinutes = nowInUserZone.hour * 60 + nowInUserZone.minute;
    final start = _parseTime(startTime);
    if (start != null && end < start) {
      // Overnight slot (e.g. 23:00 -> 01:00)
      // Has ended only if now is between end and start
      return nowMinutes >= end && nowMinutes < start;
    }
    return nowMinutes >= end;
  }

  /// Whether current time in [nowInUserZone] has passed or reached [startTime].
  bool hasStartedBy(DateTime nowInUserZone) {
    final start = _parseTime(startTime);
    if (start == null) return false;
    final nowMinutes = nowInUserZone.hour * 60 + nowInUserZone.minute;
    final end = _parseTime(endTime);
    if (end != null && end < start) {
      // Overnight slot: started if now >= start or now < end
      return nowMinutes >= start || nowMinutes < end;
    }
    return nowMinutes >= start;
  }

  /// Whether this routine is actively in progress right now at [nowInUserZone].
  bool isOngoingAt(DateTime nowInUserZone) {
    final start = _parseTime(startTime);
    final end = _parseTime(endTime);
    if (start == null || end == null) return false;
    final nowMinutes = nowInUserZone.hour * 60 + nowInUserZone.minute;
    if (end > start) {
      return nowMinutes >= start && nowMinutes < end;
    } else if (end < start) {
      // Overnight slot
      return nowMinutes >= start || nowMinutes < end;
    } else {
      return false;
    }
  }

  /// Real-time progress between [startTime] and [endTime] (0.0 to 1.0)
  /// given [nowInUserZone].
  double elapsedProgressAt(DateTime nowInUserZone) {
    final start = _parseTime(startTime);
    final end = _parseTime(endTime);
    if (start == null || end == null) return 0.0;
    var total = end - start;
    if (total <= 0) total += 24 * 60;
    if (total == 0) return 0.0;

    final nowMinutes = nowInUserZone.hour * 60 + nowInUserZone.minute;
    if (isOngoingAt(nowInUserZone)) {
      var elapsed = nowMinutes - start;
      if (elapsed < 0) elapsed += 24 * 60;
      return (elapsed / total).clamp(0.0, 1.0);
    } else if (hasEndedBy(nowInUserZone)) {
      return 1.0;
    } else {
      return 0.0;
    }
  }

  /// Remaining minutes in this routine slot if ongoing; 0 otherwise.
  int remainingMinutesAt(DateTime nowInUserZone) {
    if (!isOngoingAt(nowInUserZone)) return 0;
    final end = _parseTime(endTime);
    if (end == null) return 0;
    final nowMinutes = nowInUserZone.hour * 60 + nowInUserZone.minute;
    var diff = end - nowMinutes;
    if (diff < 0) diff += 24 * 60;
    return diff;
  }

  /// Minutes until this routine begins; 0 if already started.
  int minutesUntilStart(DateTime nowInUserZone) {
    if (hasStartedBy(nowInUserZone)) return 0;
    final start = _parseTime(startTime);
    if (start == null) return 0;
    final nowMinutes = nowInUserZone.hour * 60 + nowInUserZone.minute;
    var diff = start - nowMinutes;
    if (diff < 0) diff += 24 * 60;
    return diff;
  }

  /// Minutes elapsed since this routine ended; 0 if not ended yet.
  int minutesSinceEnded(DateTime nowInUserZone) {
    if (!hasEndedBy(nowInUserZone)) return 0;
    final end = _parseTime(endTime);
    if (end == null) return 0;
    final nowMinutes = nowInUserZone.hour * 60 + nowInUserZone.minute;
    var diff = nowMinutes - end;
    if (diff < 0) diff += 24 * 60;
    return diff;
  }

  static const sessionTypes = ['study', 'revision', 'memorization', 'practice', 'test', 'break', 'chore'];

  String get sessionTypeLabel => labelForSessionType(sessionType);

  static String labelForSessionType(String type) {
    switch (type) {
      case 'revision':
        return 'Revision';
      case 'memorization':
        return 'Memorization';
      case 'practice':
        return 'Practice';
      case 'test':
        return 'Test';
      case 'break':
        return 'Break';
      case 'chore':
        return 'Chore';
      case 'study':
      default:
        return 'Study';
    }
  }

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
      chapterId: json['chapter_id'] as String?,
      topicId: json['topic_id'] as String?,
      sessionType: json['session_type'] as String? ?? 'study',
      hasAlarm: json['has_alarm'] as bool? ?? false,
      alarmLeadMinutes: (json['alarm_lead_minutes'] as num?)?.toInt() ?? 0,
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
      'chapter_id': chapterId,
      'topic_id': topicId,
      'session_type': sessionType,
      'has_alarm': hasAlarm,
      'alarm_lead_minutes': alarmLeadMinutes,
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
