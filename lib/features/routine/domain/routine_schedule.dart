import '../../../core/models/routine.dart';

/// Pure helpers for the routine feature: wall-clock time parsing, form
/// validation and the structured title that carries topic/activity.
///
/// `routines` has no topic/activity columns (live schema: `subject_id`,
/// `title`, `start_time`, `end_time`, `weekdays`, `target_duration_minutes`,
/// …) and no migration can be applied from this lane, so the study context
/// (Subject → Chapter/Topic → Activity) is carried by `subject_id` plus a
/// deterministic title `"<base> · <topic> · <activity>"` that this class
/// composes and parses back. Nothing else is persisted.
abstract final class RoutineSchedule {
  /// Study activities offered by the form (labels, not data — nothing is
  /// seeded into the database).
  static const activities = <String>[
    'Lecture',
    'Revision',
    'Practice',
    'Memorization',
    'Problem Solving',
    'Reading',
    'Note Taking',
    'Self Study',
  ];

  static const titleSeparator = ' · ';
  static const defaultTitle = 'Study routine';

  /// Live `weekdays` encoding: 0 = Sunday … 6 = Saturday.
  static const weekdayShort = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

  /// `HH:MM[:SS]` → minutes since midnight, or null when malformed.
  static int? toMinutes(String t) {
    final p = t.split(':');
    if (p.length < 2) return null;
    final h = int.tryParse(p[0]);
    final m = int.tryParse(p[1]);
    if (h == null || m == null || h < 0 || h > 23 || m < 0 || m > 59) {
      return null;
    }
    return h * 60 + m;
  }

  /// Minutes since midnight → `HH:MM` as stored in `time` columns.
  static String toHHmm(int minutes) {
    final h = (minutes ~/ 60) % 24;
    final m = minutes % 60;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
  }

  /// `HH:MM[:SS]` → `h:MM AM/PM` for display.
  static String format12h(String t) {
    final p = t.split(':');
    if (p.length < 2) return t;
    final h = int.tryParse(p[0]) ?? 0;
    final period = h >= 12 ? 'PM' : 'AM';
    final hour12 = h == 0 ? 12 : (h > 12 ? h - 12 : h);
    return '$hour12:${p[1]} $period';
  }

  /// Human label for a weekday set ("Every day", "Weekdays", "Mon, Wed").
  static String weekdaysLabel(List<int> weekdays) {
    final s = weekdays.toSet();
    if (s.length == 7) return 'Every day';
    if (s.length == 5 && !s.contains(0) && !s.contains(6)) return 'Weekdays';
    if (s.length == 2 && s.contains(0) && s.contains(6)) return 'Weekends';
    final sorted = s.toList()..sort();
    return sorted.map((i) => weekdayShort[i]).join(', ');
  }

  /// Two `[start, end)` wall-clock slots overlap on a shared weekday.
  static bool overlaps({
    required String aStart,
    required String aEnd,
    required List<int> aDays,
    required String bStart,
    required String bEnd,
    required List<int> bDays,
  }) {
    if (!aDays.any(bDays.contains)) return false;
    final as = toMinutes(aStart), ae = toMinutes(aEnd);
    final bs = toMinutes(bStart), be = toMinutes(bEnd);
    if (as == null || ae == null || bs == null || be == null) return false;
    return as < be && bs < ae;
  }

  /// Form validation. Returns the first problem, or null when valid.
  ///
  /// Rules: well-formed times; end strictly after start on the same day
  /// (V1 has no overnight slots — `time` columns cannot say which day the
  /// end belongs to); at least one weekday; target duration, when given,
  /// positive and no longer than the slot.
  static String? validate({
    required String startTime,
    required String endTime,
    required List<int> weekdays,
    int? targetDurationMinutes,
  }) {
    final s = toMinutes(startTime);
    final e = toMinutes(endTime);
    if (s == null || e == null) return 'Enter a valid start and end time';
    if (e <= s) return 'End time must be after start time';
    if (weekdays.isEmpty) return 'Select at least one day';
    if (weekdays.any((d) => d < 0 || d > 6)) return 'Select valid days';
    if (targetDurationMinutes != null) {
      if (targetDurationMinutes <= 0) {
        return 'Duration must be a positive number of minutes';
      }
      if (targetDurationMinutes > e - s) {
        return 'Duration cannot be longer than the time slot (${e - s} min)';
      }
    }
    return null;
  }

  /// Builds the stored title from its parts. Falls back to the topic, then
  /// [defaultTitle], when the user typed no title.
  static String composeTitle({String? base, String? topic, String? activity}) {
    final b = (base ?? '').trim();
    final t = (topic ?? '').trim();
    final a = (activity ?? '').trim();
    final parts = <String>[
      if (b.isNotEmpty) b,
      if (t.isNotEmpty && t != b) t,
      if (a.isNotEmpty) a,
    ];
    if (parts.isEmpty) return defaultTitle;
    return parts.join(titleSeparator);
  }

  /// Splits a stored title back into its parts. The activity is recognised
  /// from [activities]; the topic from [knownTopics] (the selected subject's
  /// syllabus node names). Anything unrecognised stays in the base title.
  static ({String base, String? topic, String? activity}) parseTitle(
    String title, {
    Iterable<String> knownTopics = const [],
  }) {
    final segments = title
        .split(titleSeparator)
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    String? activity;
    if (segments.isNotEmpty && activities.contains(segments.last)) {
      activity = segments.removeLast();
    }
    String? topic;
    final topics = knownTopics.toSet();
    if (segments.isNotEmpty && topics.contains(segments.last)) {
      topic = segments.removeLast();
    }
    var base = segments.join(titleSeparator);
    if (base == defaultTitle) base = '';
    return (base: base, topic: topic, activity: activity);
  }

  /// Routines scheduled on the given live weekday, ordered by start time.
  static List<Routine> scheduledOn(Iterable<Routine> routines, int weekday) =>
      routines.where((r) => r.isActive && r.isScheduledOn(weekday)).toList()
        ..sort((a, b) => a.startTime.compareTo(b.startTime));
}
