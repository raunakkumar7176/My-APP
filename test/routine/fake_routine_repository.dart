// In-memory routine repository fake for controller and widget tests.
//
// Mirrors the live contract: rows are owned by `currentUser` (RLS analogue),
// the repository never computes "today" — callers pass the user-zone date
// and weekday — and `upsertLog` is keyed on (routine_id, log_date).

import 'package:my_praperation/core/models/routine.dart';
import 'package:my_praperation/core/models/routine_log.dart';
import 'package:my_praperation/features/routine/data/routine_repository.dart';
import 'package:my_praperation/features/routine/domain/routine_schedule.dart';

class FakeRoutineRepository implements RoutineRepository {
  final Map<String, Routine> routines = {};
  final Map<String, RoutineLog> logs = {};
  final List<String> calls = [];
  int nextRoutineId = 1;
  int nextLogId = 1;
  String currentUser = 'u-1';

  Object? failListWith;
  Object? failTodayWith;
  Object? failCreateWith;
  Object? failUpdateWith;
  Object? failDeleteWith;
  Object? failConflictWith;
  Object? failLogWith;
  Object? failHistoryWith;

  /// Convenience for tests: seed a routine owned by [currentUser].
  Routine seed({
    String? id,
    String title = 'Study routine',
    String startTime = '09:00',
    String endTime = '10:00',
    List<int> weekdays = const [0, 1, 2, 3, 4, 5, 6],
    String? subjectId,
    bool isActive = true,
    int? targetDurationMinutes,
    DateTime? createdAt,
    String? userId,
  }) {
    final rid = id ?? 'r-${nextRoutineId++}';
    final r = Routine(
      id: rid,
      userId: userId ?? currentUser,
      subjectId: subjectId,
      title: title,
      startTime: startTime,
      endTime: endTime,
      weekdays: weekdays,
      isActive: isActive,
      targetDurationMinutes: targetDurationMinutes,
      createdAt: createdAt ?? DateTime.utc(2020, 1, 1),
    );
    routines[rid] = r;
    return r;
  }

  Iterable<Routine> get _own =>
      routines.values.where((r) => r.userId == currentUser);

  Iterable<RoutineLog> get _ownLogs =>
      logs.values.where((l) => routines[l.routineId]?.userId == currentUser);

  @override
  Future<List<Routine>> list() async {
    calls.add('list');
    if (failListWith != null) throw failListWith!;
    final out = _own.toList()
      ..sort((a, b) {
        if (a.isActive != b.isActive) return a.isActive ? -1 : 1;
        return a.startTime.compareTo(b.startTime);
      });
    return out;
  }

  @override
  Future<Routine?> getById(String id) async {
    calls.add('getById:$id');
    final r = routines[id];
    return r != null && r.userId == currentUser ? r : null;
  }

  @override
  Future<String> create({
    required String title,
    required String startTime,
    required String endTime,
    List<int> weekdays = const [0, 1, 2, 3, 4, 5, 6],
    String? subjectId,
    bool reminderEnabled = true,
    int? targetDurationMinutes,
  }) async {
    calls.add('create:$title');
    if (failCreateWith != null) throw failCreateWith!;
    final id = 'r-${nextRoutineId++}';
    routines[id] = Routine(
      id: id,
      userId: currentUser,
      subjectId: subjectId,
      title: title,
      startTime: startTime,
      endTime: endTime,
      weekdays: weekdays,
      reminderEnabled: reminderEnabled,
      targetDurationMinutes: targetDurationMinutes,
      isActive: true,
      createdAt: DateTime.now().toUtc(),
    );
    return id;
  }

  Routine _copy(
    Routine e, {
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
  }) => Routine(
    id: e.id,
    userId: e.userId,
    subjectId: clearSubject ? null : (subjectId ?? e.subjectId),
    title: title ?? e.title,
    startTime: startTime ?? e.startTime,
    endTime: endTime ?? e.endTime,
    weekdays: weekdays ?? e.weekdays,
    reminderEnabled: reminderEnabled ?? e.reminderEnabled,
    isActive: isActive ?? e.isActive,
    targetDurationMinutes: clearTargetDuration
        ? null
        : (targetDurationMinutes ?? e.targetDurationMinutes),
    createdAt: e.createdAt,
    updatedAt: DateTime.now(),
  );

  @override
  Future<void> update({
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
  }) async {
    calls.add('update:$id');
    if (failUpdateWith != null) throw failUpdateWith!;
    final existing = routines[id];
    if (existing == null || existing.userId != currentUser) {
      // RLS: an update on a row you cannot see affects 0 rows, silently.
      return;
    }
    routines[id] = _copy(
      existing,
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
    );
  }

  @override
  Future<void> deactivate(String id) async {
    calls.add('deactivate:$id');
    final e = routines[id];
    if (e == null || e.userId != currentUser) return;
    routines[id] = _copy(e, isActive: false);
  }

  @override
  Future<void> activate(String id) async {
    calls.add('activate:$id');
    final e = routines[id];
    if (e == null || e.userId != currentUser) return;
    routines[id] = _copy(e, isActive: true);
  }

  @override
  Future<void> delete(String id) async {
    calls.add('delete:$id');
    if (failDeleteWith != null) throw failDeleteWith!;
    final e = routines[id];
    if (e == null || e.userId != currentUser) return;
    routines.remove(id);
    logs.removeWhere((_, l) => l.routineId == id);
  }

  @override
  Future<bool> hasConflict({
    required String startTime,
    required String endTime,
    required List<int> weekdays,
    String? excludeId,
  }) async {
    calls.add('hasConflict');
    if (failConflictWith != null) throw failConflictWith!;
    for (final r in _own) {
      if (!r.isActive) continue;
      if (excludeId != null && r.id == excludeId) continue;
      if (RoutineSchedule.overlaps(
        aStart: startTime,
        aEnd: endTime,
        aDays: weekdays,
        bStart: r.startTime,
        bEnd: r.endTime,
        bDays: r.weekdays,
      )) {
        return true;
      }
    }
    return false;
  }

  @override
  Future<List<RoutineLog>> getLogs({
    required String startDate,
    required String endDate,
    String? routineId,
  }) async {
    calls.add('getLogs:$startDate:$endDate');
    return _ownLogs
        .where(
          (l) =>
              l.logDate.compareTo(startDate) >= 0 &&
              l.logDate.compareTo(endDate) <= 0 &&
              (routineId == null || l.routineId == routineId),
        )
        .toList()
      ..sort((a, b) => b.logDate.compareTo(a.logDate));
  }

  @override
  Future<void> upsertLog({
    required String routineId,
    required String logDate,
    required String status,
    int? durationMinutes,
  }) async {
    calls.add('upsertLog:$routineId:$logDate:$status');
    if (failLogWith != null) throw failLogWith!;
    final owner = routines[routineId];
    if (owner == null || owner.userId != currentUser) {
      throw StateError('RLS: cannot log for a routine you do not own');
    }
    final key = '$routineId:$logDate';
    final existing = logs[key];
    logs[key] = RoutineLog(
      id: existing?.id ?? 'log-${nextLogId++}',
      routineId: routineId,
      logDate: logDate,
      completed: status == 'COMPLETED',
      status: status,
      durationMinutes: durationMinutes,
      completedAt: status == 'COMPLETED' ? DateTime.now() : null,
      createdAt: existing?.createdAt ?? DateTime.now(),
      updatedAt: DateTime.now(),
    );
  }

  @override
  Future<List<RoutineWithLog>> getToday({
    required String date,
    required int weekday,
  }) async {
    calls.add('getToday:$date:$weekday');
    if (failTodayWith != null) throw failTodayWith!;
    final scheduled = RoutineSchedule.scheduledOn(_own, weekday);
    return [
      for (final r in scheduled)
        RoutineWithLog(routine: r, log: logs['${r.id}:$date']),
    ];
  }

  @override
  Future<List<RoutineLog>> getHistory({
    int limit = 30,
    int offset = 0,
    String? routineId,
  }) async {
    calls.add('getHistory:$offset');
    if (failHistoryWith != null) throw failHistoryWith!;
    final sorted = _ownLogs
        .where((l) => routineId == null || l.routineId == routineId)
        .toList()
      ..sort((a, b) => b.logDate.compareTo(a.logDate));
    return sorted.skip(offset).take(limit).toList();
  }
}
