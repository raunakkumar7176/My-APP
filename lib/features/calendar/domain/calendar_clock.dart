/// Calendar day arithmetic in the **user's** timezone (profile `timezone`,
/// default `Asia/Kolkata`), independent of the device clock.
///
/// The app ships no tz database, so zones are resolved through a table of
/// fixed-offset (no-DST) IANA names. For a zone that is not in the table the
/// clock falls back to the device's local time and reports
/// [usesDeviceFallback] so the UI/report can say so — it never silently
/// pretends. `Asia/Kolkata` (every live profile) is fixed-offset.
final class CalendarClock {
  CalendarClock(String? timezoneName, {DateTime Function()? now})
    : timezoneName = (timezoneName ?? '').trim().isEmpty
          ? defaultTimezone
          : timezoneName!.trim(),
      _now = now ?? DateTime.now {
    _offset = fixedOffsets[this.timezoneName];
  }

  static const defaultTimezone = 'Asia/Kolkata';

  /// IANA zones without daylight-saving time that the app may store.
  static const Map<String, Duration> fixedOffsets = {
    'UTC': Duration.zero,
    'Etc/UTC': Duration.zero,
    'Asia/Kolkata': Duration(hours: 5, minutes: 30),
    'Asia/Calcutta': Duration(hours: 5, minutes: 30),
    'Asia/Kathmandu': Duration(hours: 5, minutes: 45),
    'Asia/Dhaka': Duration(hours: 6),
    'Asia/Colombo': Duration(hours: 5, minutes: 30),
    'Asia/Karachi': Duration(hours: 5),
    'Asia/Dubai': Duration(hours: 4),
    'Asia/Riyadh': Duration(hours: 3),
    'Asia/Singapore': Duration(hours: 8),
    'Asia/Kuala_Lumpur': Duration(hours: 8),
    'Asia/Tokyo': Duration(hours: 9),
    'Asia/Shanghai': Duration(hours: 8),
    'Asia/Hong_Kong': Duration(hours: 8),
  };

  final String timezoneName;
  final DateTime Function() _now;
  Duration? _offset;

  /// True when the zone is not in [fixedOffsets] and device time is used.
  bool get usesDeviceFallback => _offset == null;

  /// Wall-clock time in the user's zone, returned as a **UTC-flagged**
  /// DateTime whose fields (year, month, day, hour …) are the user's local
  /// values. Callers must only read fields from it, never compare it with
  /// real instants.
  DateTime toUserWall(DateTime instant) {
    final utc = instant.toUtc();
    final off = _offset;
    if (off == null) {
      final l = instant.toLocal();
      return DateTime.utc(l.year, l.month, l.day, l.hour, l.minute, l.second);
    }
    return utc.add(off);
  }

  /// The real instant for a user-zone wall-clock date and time.
  DateTime fromUserWall(int year, int month, int day, [int hour = 0, int minute = 0]) {
    final off = _offset;
    if (off == null) return DateTime(year, month, day, hour, minute).toUtc();
    return DateTime.utc(year, month, day, hour, minute).subtract(off);
  }

  /// The user's calendar day (date-only, UTC-flagged) of an instant.
  DateTime dayOf(DateTime instant) {
    final w = toUserWall(instant);
    return DateTime.utc(w.year, w.month, w.day);
  }

  DateTime today() => dayOf(_now());

  /// [start, end) instants covering the user's calendar month — the range to
  /// ask the server for.
  ({DateTime start, DateTime end}) monthRange(int year, int month) => (
    start: fromUserWall(year, month, 1),
    end: fromUserWall(month == 12 ? year + 1 : year, month == 12 ? 1 : month + 1, 1),
  );

  /// Wall-clock `HH:MM` in the user's zone.
  String timeLabel(DateTime instant) {
    final w = toUserWall(instant);
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(w.hour)}:${two(w.minute)}';
  }
}

/// Date-only helpers (all on UTC-flagged date values from [CalendarClock]).
abstract final class CalendarDates {
  static DateTime date(int y, int m, int d) => DateTime.utc(y, m, d);
  static bool sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
  static DateTime addDays(DateTime d, int n) => DateTime.utc(d.year, d.month, d.day + n);
  static int daysInMonth(int year, int month) => DateTime.utc(year, month + 1, 0).day;

  /// `weekdays` as stored live: 0 = Sunday … 6 = Saturday.
  static int liveWeekday(DateTime d) => d.weekday % 7;

  static const monthNames = [
    'January', 'February', 'March', 'April', 'May', 'June', 'July', 'August',
    'September', 'October', 'November', 'December',
  ];
  static String monthTitle(int year, int month) => '${monthNames[month - 1]} $year';

  /// `YYYY-MM-DD` for server date columns / keys.
  static String iso(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static DateTime parseIso(String s) {
    final p = s.split('T').first.split('-');
    return DateTime.utc(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]));
  }

  /// 6 rows × 7 columns (Monday first) covering the month, with leading /
  /// trailing days from the neighbouring months.
  static List<DateTime> monthGrid(int year, int month) {
    final first = DateTime.utc(year, month, 1);
    final lead = (first.weekday - DateTime.monday) % 7;
    final start = addDays(first, -lead);
    return [for (var i = 0; i < 42; i++) addDays(start, i)];
  }
}
