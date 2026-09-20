import '../../../core/errors/app_error.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/services/profile_service.dart';
import '../../test/state/disposable_notifier.dart';
import '../data/calendar_repository.dart';
import '../domain/calendar_clock.dart';
import '../domain/calendar_event.dart';

/// Calendar V1 state: one visible month (user-zone), a selected day and the
/// derived events of that month. Reads only; one bounded load per month;
/// single-flight; the profile timezone decides which day an instant is on.
class CalendarController extends DisposableNotifier {
  CalendarController({
    CalendarRepository? repository,
    CalendarClock? clock,
    DateTime? initialDay,
  }) : _repo = repository ?? const SupabaseCalendarRepository(),
       clock = clock ?? CalendarClock(ProfileService.currentProfile?.timezone) {
    final today = this.clock.today();
    _selected = initialDay ?? today;
    _year = _selected.year;
    _month = _selected.month;
  }

  final CalendarRepository _repo;
  final CalendarClock clock;

  late int _year;
  late int _month;
  late DateTime _selected;
  List<CalendarEvent> _events = const [];
  bool _loading = false;
  bool _loadedOnce = false;
  String? _error;
  int _loadSeq = 0;

  int get year => _year;
  int get month => _month;
  String get monthTitle => CalendarDates.monthTitle(_year, _month);
  DateTime get selectedDay => _selected;
  DateTime get today => clock.today();
  bool get isLoading => _loading;
  bool get hasLoaded => _loadedOnce;
  String? get error => _error;

  /// All events of the visible month, sorted by day then time.
  List<CalendarEvent> get events => _events;

  /// Events of the selected day (empty ⇒ the "nothing planned" state).
  List<CalendarEvent> get selectedDayEvents =>
      [for (final e in _events) if (CalendarDates.sameDay(e.day, _selected)) e];

  /// Events per day of the visible month, for the grid markers.
  Map<String, List<CalendarEvent>> get eventsByDay {
    final m = <String, List<CalendarEvent>>{};
    for (final e in _events) {
      (m[CalendarDates.iso(e.day)] ??= []).add(e);
    }
    return m;
  }

  List<CalendarEvent> eventsOn(DateTime day) => eventsByDay[CalendarDates.iso(day)] ?? const [];

  List<DateTime> get grid => CalendarDates.monthGrid(_year, _month);

  bool isInVisibleMonth(DateTime day) => day.year == _year && day.month == _month;

  // ── navigation ──

  void selectDay(DateTime day) {
    _selected = CalendarDates.date(day.year, day.month, day.day);
    if (!isInVisibleMonth(_selected)) {
      _year = _selected.year;
      _month = _selected.month;
      notifyListeners();
      load();
      return;
    }
    notifyListeners();
  }

  Future<void> nextMonth() => _showMonth(_month == 12 ? _year + 1 : _year, _month == 12 ? 1 : _month + 1);
  Future<void> previousMonth() => _showMonth(_month == 1 ? _year - 1 : _year, _month == 1 ? 12 : _month - 1);

  Future<void> goToToday() async {
    final t = clock.today();
    _selected = t;
    if (t.year == _year && t.month == _month) {
      notifyListeners();
      return;
    }
    await _showMonth(t.year, t.month);
  }

  Future<void> _showMonth(int year, int month) async {
    _year = year;
    _month = month;
    // Keep a selected day inside the visible month so the agenda never shows
    // a day the grid does not.
    if (!isInVisibleMonth(_selected)) {
      final t = clock.today();
      _selected = (t.year == year && t.month == month) ? t : CalendarDates.date(year, month, 1);
    }
    notifyListeners();
    await load();
  }

  // ── loading (reads only) ──

  Future<void> load() async {
    final seq = ++_loadSeq;
    final year = _year, month = _month;
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final range = clock.monthRange(year, month);
      final from = CalendarDates.date(year, month, 1);
      final to = CalendarDates.date(year, month, CalendarDates.daysInMonth(year, month));
      final routines = await _repo.routines();
      final logs = await _repo.routineLogs(from: from, to: to);
      final tests = await _repo.testsBetween(startUtc: range.start, endUtc: range.end);
      if (seq != _loadSeq || isDisposed) return; // a newer month load superseded this one
      _events = CalendarEventBuilder.build(
        clock: clock,
        year: year,
        month: month,
        routines: routines,
        logs: logs,
        tests: tests,
      );
    } on AppError catch (e) {
      if (seq != _loadSeq) return;
      _error = e.message;
    } catch (e, st) {
      if (seq != _loadSeq) return;
      AppLogger.error('Calendar load failed: $e', stackTrace: st);
      _error = 'Could not load your calendar. Please try again.';
    }
    if (seq != _loadSeq) return;
    _loading = false;
    _loadedOnce = true;
    notifyListeners();
  }

  Future<void> refresh() => load();
}
