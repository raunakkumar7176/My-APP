import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/errors/app_error.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/models/routine.dart';
import '../../../core/models/routine_log.dart';
import '../../../core/services/academic_alarm_service.dart';
import '../../../core/services/profile_service.dart';
import '../../calendar/domain/calendar_clock.dart';
import '../../test/state/disposable_notifier.dart';
import '../data/routine_repository.dart';
import '../domain/routine_schedule.dart';

/// Completion summary of one routine over a window of days.
final class RoutineStats {
  const RoutineStats({
    required this.scheduledDays,
    required this.completedDays,
    required this.skippedDays,
    required this.loggedMinutes,
  });

  final int scheduledDays;
  final int completedDays;
  final int skippedDays;
  final int loggedMinutes;

  /// 0..1 — completed over scheduled days (0 when nothing was scheduled).
  double get completionRate =>
      scheduledDays == 0 ? 0 : completedDays / scheduledDays;
}

/// State for the Routine feature: today's items with completion, the full
/// routine list, create/edit/pause/delete, completion logging, history and
/// conflict validation.
///
/// "Today" is the user's calendar day in the **profile timezone** (via
/// [CalendarClock], default `Asia/Kolkata`), never the device clock, so a
/// completion logged at 23:30 IST lands on the IST date regardless of where
/// the phone thinks it is.
class RoutineController extends DisposableNotifier {
  RoutineController({
    RoutineRepository? repository,
    CalendarClock? clock,
    DateTime Function()? now,
  }) : _repository = repository ?? const SupabaseRoutineRepository(),
       clock = clock ?? CalendarClock(ProfileService.currentProfile?.timezone),
       _now = now ?? DateTime.now;

  final RoutineRepository _repository;
  final CalendarClock clock;
  final DateTime Function() _now;

  /// Bumped after every successful mutation so independent widgets (the home
  /// card, the list screen) can reload without sharing a controller.
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  // ── State ──
  List<RoutineWithLog> _todayItems = [];
  List<Routine> _allRoutines = [];
  bool _loadingToday = false;
  bool _loadingAll = false;
  String? _error;

  // ── Getters ──
  List<RoutineWithLog> get todayItems => List.unmodifiable(_todayItems);
  List<Routine> get allRoutines => List.unmodifiable(_allRoutines);
  List<Routine> get activeRoutines =>
      [for (final r in _allRoutines) if (r.isActive) r];
  List<Routine> get pausedRoutines =>
      [for (final r in _allRoutines) if (!r.isActive) r];
  bool get isLoading => _loadingToday || _loadingAll;
  String? get error => _error;

  int get completedCount => _todayItems.where((r) => r.isCompleted).length;
  int get totalCount => _todayItems.length;
  double get completionPercentage =>
      totalCount == 0 ? 0 : completedCount / totalCount;

  /// Today's user-zone date as `YYYY-MM-DD` (the `routine_logs.log_date` key).
  String get todayDate => _iso(clock.today());

  /// Today's live weekday: 0 = Sunday … 6 = Saturday.
  int get todayWeekday => clock.today().weekday % 7;

  /// The next pending item of today by wall-clock start time (the first one
  /// that has not started yet, else the earliest pending).
  RoutineWithLog? get upNext {
    final pending = [for (final i in _todayItems) if (!i.isCompleted && !i.isSkipped) i]
      ..sort((a, b) => a.routine.startTime.compareTo(b.routine.startTime));
    if (pending.isEmpty) return null;
    final now = clock.toUserWall(_now());
    final nowMin = now.hour * 60 + now.minute;
    for (final i in pending) {
      if ((RoutineSchedule.toMinutes(i.routine.startTime) ?? 0) >= nowMin) {
        return i;
      }
    }
    return pending.first;
  }

  /// Active routines scheduled on the given weekday (for "upcoming" views).
  List<Routine> scheduledOn(int weekday) =>
      RoutineSchedule.scheduledOn(_allRoutines, weekday);

  // ── Selected-date browsing (day view with prev/today/next navigation) ──
  //
  // Independent of [todayItems]/[loadToday] above (kept untouched so every
  // existing caller — the dashboard card, existing tests — is unaffected).
  // Defaults to today and reuses the same repository call, just for an
  // arbitrary user-zone date instead of always "today".

  DateTime? _selectedDate;
  List<RoutineWithLog> _selectedItems = [];
  bool _loadingSelected = false;
  String? _selectedError;

  /// The day currently being viewed (user-zone, date-only). Defaults to
  /// today until [loadSelectedDate] is called with another date.
  DateTime get selectedDate => _selectedDate ?? clock.today();

  bool get isSelectedToday => CalendarDates.sameDay(selectedDate, clock.today());

  List<RoutineWithLog> get selectedItems => List.unmodifiable(_selectedItems);
  bool get isLoadingSelected => _loadingSelected;
  String? get selectedError => _selectedError;

  int get selectedCompletedCount =>
      _selectedItems.where((i) => i.isCompleted).length;
  int get selectedTotalCount => _selectedItems.length;
  double get selectedCompletionPercentage =>
      selectedTotalCount == 0 ? 0 : selectedCompletedCount / selectedTotalCount;

  /// Sum of logged minutes across the selected date's items (0 for items
  /// with no log yet, e.g. skipped or not-yet-completed).
  int get selectedLoggedMinutes =>
      _selectedItems.fold(0, (sum, i) => sum + (i.log?.durationMinutes ?? 0));

  /// The item whose `[start, end)` wall-clock window contains the current
  /// moment — only meaningful (non-null) while viewing today.
  RoutineWithLog? get currentItem {
    if (!isSelectedToday) return null;
    final now = clock.toUserWall(_now());
    final nowMin = now.hour * 60 + now.minute;
    for (final i in _selectedItems) {
      final s = RoutineSchedule.toMinutes(i.routine.startTime);
      final e = RoutineSchedule.toMinutes(i.routine.endTime);
      if (s == null || e == null) continue;
      if (nowMin >= s && nowMin < e) return i;
    }
    return null;
  }

  /// The next pending item on the selected date by start time — time-aware
  /// (first not-yet-started item) only while viewing today, else simply the
  /// earliest pending item of that day.
  RoutineWithLog? get selectedUpNext {
    final pending = [
      for (final i in _selectedItems) if (!i.isCompleted && !i.isSkipped) i,
    ]..sort((a, b) => a.routine.startTime.compareTo(b.routine.startTime));
    if (pending.isEmpty) return null;
    if (!isSelectedToday) return pending.first;
    final now = clock.toUserWall(_now());
    final nowMin = now.hour * 60 + now.minute;
    for (final i in pending) {
      if ((RoutineSchedule.toMinutes(i.routine.startTime) ?? 0) >= nowMin) {
        return i;
      }
    }
    return pending.first;
  }

  /// Loads the given date (defaults to the currently selected/today date).
  Future<void> loadSelectedDate([DateTime? date]) async {
    final d = date ?? selectedDate;
    _selectedDate = d;
    if (_loadingSelected) return;
    _loadingSelected = true;
    _selectedError = null;
    notifyListeners();
    try {
      _selectedItems = await _repository.getToday(
        date: CalendarDates.iso(d),
        weekday: CalendarDates.liveWeekday(d),
      );
    } on AppError catch (e) {
      _selectedError = e.message;
      AppLogger.error('RoutineController.loadSelectedDate: $e');
    } catch (e, st) {
      _selectedError = "Failed to load that day's routine";
      AppLogger.error(
        'RoutineController.loadSelectedDate unexpected: $e',
        stackTrace: st,
      );
    } finally {
      _loadingSelected = false;
      if (!isDisposed) notifyListeners();
    }
  }

  Future<void> selectPreviousDay() =>
      loadSelectedDate(CalendarDates.addDays(selectedDate, -1));

  Future<void> selectNextDay() =>
      loadSelectedDate(CalendarDates.addDays(selectedDate, 1));

  Future<void> selectToday() => loadSelectedDate(clock.today());

  /// Marks completion for an item on the currently selected date (which may
  /// not be today) and reloads that date's items.
  Future<void> markSelectedComplete(String routineId, {int? durationMinutes}) =>
      _logForSelected(routineId, 'COMPLETED', durationMinutes: durationMinutes);

  Future<void> markSelectedIncomplete(String routineId) =>
      _logForSelected(routineId, 'PENDING');

  Future<void> skipSelectedRoutine(String routineId) =>
      _logForSelected(routineId, 'SKIPPED');

  Future<void> _logForSelected(
    String routineId,
    String status, {
    int? durationMinutes,
  }) async {
    try {
      await _repository.upsertLog(
        routineId: routineId,
        logDate: CalendarDates.iso(selectedDate),
        status: status,
        durationMinutes: durationMinutes,
      );
      revision.value++;
      await loadSelectedDate();
    } catch (e) {
      AppLogger.error('RoutineController.$status (selected): $e');
      rethrow;
    }
  }

  // ── Loading ──

  Future<void> loadToday() async {
    if (_loadingToday) return;
    _loadingToday = true;
    _error = null;
    notifyListeners();
    try {
      _todayItems = await _repository.getToday(
        date: todayDate,
        weekday: todayWeekday,
      );
    } on AppError catch (e) {
      _error = e.message;
      AppLogger.error('RoutineController.loadToday: $e');
    } catch (e, st) {
      _error = "Failed to load today's routine";
      AppLogger.error('RoutineController.loadToday unexpected: $e', stackTrace: st);
    } finally {
      _loadingToday = false;
      if (!isDisposed) notifyListeners();
    }
  }

  Future<void> loadAll() async {
    if (_loadingAll) return;
    _loadingAll = true;
    _error = null;
    notifyListeners();
    try {
      _allRoutines = await _repository.list();
    } on AppError catch (e) {
      _error = e.message;
      AppLogger.error('RoutineController.loadAll: $e');
    } catch (e, st) {
      _error = 'Failed to load routines';
      AppLogger.error('RoutineController.loadAll unexpected: $e', stackTrace: st);
    } finally {
      _loadingAll = false;
      if (!isDisposed) notifyListeners();
    }
  }

  // ── Mutations (all rethrow so the screen can show the message) ──

  Future<String?> createRoutine({
    required String title,
    required String startTime,
    required String endTime,
    List<int> weekdays = const [0, 1, 2, 3, 4, 5, 6],
    String? subjectId,
    bool reminderEnabled = true,
    int? targetDurationMinutes,
    String sessionType = 'study',
    bool hasAlarm = false,
    int alarmLeadMinutes = 0,
  }) async {
    try {
      final id = await _repository.create(
        title: title,
        startTime: startTime,
        endTime: endTime,
        weekdays: weekdays,
        subjectId: subjectId,
        reminderEnabled: reminderEnabled,
        targetDurationMinutes: targetDurationMinutes,
        sessionType: sessionType,
        hasAlarm: hasAlarm,
        alarmLeadMinutes: alarmLeadMinutes,
      );
      await _changed();
      return id;
    } catch (e) {
      AppLogger.error('RoutineController.createRoutine: $e');
      rethrow;
    }
  }

  Future<void> updateRoutine({
    required String id,
    String? title,
    String? startTime,
    String? endTime,
    List<int>? weekdays,
    String? subjectId,
    bool clearSubject = false,
    bool? reminderEnabled,
    bool? isActive,
    int? targetDurationMinutes,
    bool clearTargetDuration = false,
    String? sessionType,
    bool? hasAlarm,
    int? alarmLeadMinutes,
  }) async {
    try {
      await _repository.update(
        id: id,
        title: title,
        startTime: startTime,
        endTime: endTime,
        weekdays: weekdays,
        subjectId: subjectId,
        clearSubject: clearSubject,
        reminderEnabled: reminderEnabled,
        isActive: isActive,
        targetDurationMinutes: targetDurationMinutes,
        clearTargetDuration: clearTargetDuration,
        sessionType: sessionType,
        hasAlarm: hasAlarm,
        alarmLeadMinutes: alarmLeadMinutes,
      );
      await _changed();
    } catch (e) {
      AppLogger.error('RoutineController.updateRoutine: $e');
      rethrow;
    }
  }

  /// Pauses (soft-deletes) a routine; its logs are kept.
  Future<void> deactivateRoutine(String id) async {
    try {
      await _repository.deactivate(id);
      await _changed();
    } catch (e) {
      AppLogger.error('RoutineController.deactivateRoutine: $e');
      rethrow;
    }
  }

  Future<void> activateRoutine(String id) async {
    try {
      await _repository.activate(id);
      await _changed();
    } catch (e) {
      AppLogger.error('RoutineController.activateRoutine: $e');
      rethrow;
    }
  }

  Future<void> deleteRoutine(String id) async {
    try {
      await _repository.delete(id);
      await _changed();
    } catch (e) {
      AppLogger.error('RoutineController.deleteRoutine: $e');
      rethrow;
    }
  }

  // ── Completion (persisted in routine_logs, keyed by user-zone date) ──

  Future<void> markComplete(String routineId, {int? durationMinutes}) =>
      _log(routineId, 'COMPLETED', durationMinutes: durationMinutes);

  Future<void> markIncomplete(String routineId) => _log(routineId, 'PENDING');

  Future<void> skipRoutine(String routineId) => _log(routineId, 'SKIPPED');

  Future<void> _log(String routineId, String status, {int? durationMinutes}) async {
    try {
      await _repository.upsertLog(
        routineId: routineId,
        logDate: todayDate,
        status: status,
        durationMinutes: durationMinutes,
      );
      revision.value++;
      await loadToday();
    } catch (e) {
      AppLogger.error('RoutineController.$status: $e');
      rethrow;
    }
  }

  // ── Validation ──

  /// True when the slot overlaps an existing active routine on a shared
  /// weekday. **Fails closed**: when the check itself cannot run the error is
  /// rethrown so the caller never saves over a possible conflict unknowingly.
  Future<bool> hasConflict({
    required String startTime,
    required String endTime,
    required List<int> weekdays,
    String? excludeId,
  }) => _repository.hasConflict(
    startTime: startTime,
    endTime: endTime,
    weekdays: weekdays,
    excludeId: excludeId,
  );

  // ── History / stats ──

  /// Logs newest first (all routines, or one). Throws on failure so the
  /// history screen can show retry.
  Future<List<RoutineLog>> getHistory({
    int limit = 30,
    int offset = 0,
    String? routineId,
  }) => _repository.getHistory(limit: limit, offset: offset, routineId: routineId);

  /// Completion over the last [days] user-zone days (today inclusive), counting
  /// only days the routine was scheduled on and not before it was created.
  Future<RoutineStats> statsFor(Routine routine, {int days = 30}) async {
    final today = clock.today();
    final from = DateTime.utc(today.year, today.month, today.day - (days - 1));
    final logs = await _repository.getLogs(
      startDate: _iso(from),
      endDate: _iso(today),
      routineId: routine.id,
    );
    final byDate = {for (final l in logs) l.logDate: l};
    final created = clock.dayOf(routine.createdAt);
    var scheduled = 0, completed = 0, skipped = 0, minutes = 0;
    for (var i = 0; i < days; i++) {
      final d = DateTime.utc(from.year, from.month, from.day + i);
      final log = byDate[_iso(d)];
      final onSchedule = routine.isScheduledOn(d.weekday % 7) && !d.isBefore(created);
      if (!onSchedule && log == null) continue;
      scheduled++;
      if (log?.isCompleted ?? false) completed++;
      if (log?.isSkipped ?? false) skipped++;
      minutes += log?.durationMinutes ?? 0;
    }
    return RoutineStats(
      scheduledDays: scheduled,
      completedDays: completed,
      skippedDays: skipped,
      loggedMinutes: minutes,
    );
  }

  Future<Routine?> getById(String id) => _repository.getById(id);

  Future<void> _changed() async {
    revision.value++;
    await loadAll();
    // Best-effort: a failed resync must never block the routine save the
    // user is actually waiting on.
    unawaited(AcademicAlarmService.resyncAlarms(_allRoutines));
  }

  static String _iso(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
