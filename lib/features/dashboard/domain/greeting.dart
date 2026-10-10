/// Pure greeting/date-time formatting for the dashboard header. Kept
/// side-effect free and separate from the widget so the "Good Morning /
/// Afternoon / Evening" boundary logic is unit-testable without pumping a
/// widget tree.
abstract final class Greeting {
  /// hour is 0-23 in the user's wall-clock time (see CalendarClock).
  /// Evening previously had no upper bound, so it also covered 10 PM,
  /// 11 PM, and midnight — now closes at 9 PM, with Night covering the
  /// rest (9 PM–5 AM) instead of Morning claiming the small hours too.
  static String forHour(int hour) {
    if (hour < 5) return 'Good Night';
    if (hour < 12) return 'Good Morning';
    if (hour < 17) return 'Good Afternoon';
    if (hour < 21) return 'Good Evening';
    return 'Good Night';
  }

  static String time12h(int hour, int minute) {
    final h = hour % 12 == 0 ? 12 : hour % 12;
    final period = hour < 12 ? 'AM' : 'PM';
    return '$h:${minute.toString().padLeft(2, '0')} $period';
  }

  static const _weekdays = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];

  /// weekday is 1 (Monday) - 7 (Sunday), matching DateTime.weekday.
  static String weekdayName(int weekday) => _weekdays[weekday - 1];

  static const _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  /// month is 1-12, matching DateTime.month.
  static String monthName(int month) => _months[month - 1];
}
