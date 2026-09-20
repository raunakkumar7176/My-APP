// Routine V1 — model tests.

import 'package:flutter_test/flutter_test.dart';
import 'package:my_praperation/core/models/routine.dart';
import 'package:my_praperation/core/models/routine_log.dart';
import 'package:my_praperation/features/routine/data/routine_repository.dart';

void main() {
  group('Routine', () {
    test('fromJson parses all fields correctly', () {
      final json = {
        'id': 'r-1',
        'user_id': 'u-1',
        'subject_id': 's-1',
        'title': 'Maths Lecture',
        'start_time': '09:00',
        'end_time': '10:30',
        'weekdays': [1, 2, 3, 4, 5],
        'reminder_enabled': true,
        'is_active': true,
        'target_duration_minutes': 60,
        'created_at': '2026-09-19T10:00:00Z',
        'updated_at': '2026-09-19T11:00:00Z',
      };

      final routine = Routine.fromJson(json);

      expect(routine.id, 'r-1');
      expect(routine.userId, 'u-1');
      expect(routine.subjectId, 's-1');
      expect(routine.title, 'Maths Lecture');
      expect(routine.startTime, '09:00');
      expect(routine.endTime, '10:30');
      expect(routine.weekdays, [1, 2, 3, 4, 5]);
      expect(routine.reminderEnabled, true);
      expect(routine.isActive, true);
      expect(routine.targetDurationMinutes, 60);
    });

    test('fromJson defaults empty title to Study routine', () {
      final json = {
        'id': 'r-1',
        'user_id': 'u-1',
        'title': '',
        'start_time': '09:00',
        'end_time': '10:00',
        'weekdays': [0, 1, 2, 3, 4, 5, 6],
        'created_at': '2026-09-19T10:00:00Z',
      };

      final routine = Routine.fromJson(json);
      expect(routine.title, 'Study routine');
    });

    test('fromJson defaults missing title to Study routine', () {
      final json = {
        'id': 'r-1',
        'user_id': 'u-1',
        'start_time': '09:00',
        'end_time': '10:00',
        'weekdays': [0, 1, 2, 3, 4, 5, 6],
        'created_at': '2026-09-19T10:00:00Z',
      };

      final routine = Routine.fromJson(json);
      expect(routine.title, 'Study routine');
    });

    test('computedDurationMinutes returns correct value', () {
      final routine = Routine(
        id: 'r-1',
        userId: 'u-1',
        startTime: '09:00',
        endTime: '10:30',
        weekdays: const [1],
        createdAt: DateTime(2026),
      );

      expect(routine.computedDurationMinutes, 90);
    });

    test('computedDurationMinutes handles overnight span', () {
      final routine = Routine(
        id: 'r-1',
        userId: 'u-1',
        startTime: '23:00',
        endTime: '01:00',
        weekdays: const [1],
        createdAt: DateTime(2026),
      );

      expect(routine.computedDurationMinutes, 120);
    });

    test('computedDurationMinutes returns null for invalid time', () {
      final routine = Routine(
        id: 'r-1',
        userId: 'u-1',
        startTime: 'invalid',
        endTime: '10:00',
        weekdays: const [1],
        createdAt: DateTime(2026),
      );

      expect(routine.computedDurationMinutes, isNull);
    });

    test('isScheduledOn checks the given live weekday (0 = Sunday)', () {
      const todayDow = 3; // Wednesday — the caller decides "today"

      final routineToday = Routine(
        id: 'r-1',
        userId: 'u-1',
        startTime: '09:00',
        endTime: '10:00',
        weekdays: [todayDow],
        createdAt: DateTime(2026),
      );

      final routineNotToday = Routine(
        id: 'r-2',
        userId: 'u-1',
        startTime: '09:00',
        endTime: '10:00',
        weekdays: [(todayDow + 1) % 7],
        createdAt: DateTime(2026),
      );

      expect(routineToday.isScheduledOn(todayDow), true);
      expect(routineNotToday.isScheduledOn(todayDow), false);
      expect(routineNotToday.isScheduledOn((todayDow + 1) % 7), true);
    });

    test('equality is based on id only', () {
      final a = Routine(
        id: 'r-1',
        userId: 'u-1',
        startTime: '09:00',
        endTime: '10:00',
        createdAt: DateTime(2026),
      );
      final b = Routine(
        id: 'r-1',
        userId: 'u-2',
        startTime: '11:00',
        endTime: '12:00',
        createdAt: DateTime(2027),
      );

      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });

    test('toInsertJson includes non-null fields', () {
      final routine = Routine(
        id: 'r-1',
        userId: 'u-1',
        subjectId: 's-1',
        title: 'Maths',
        startTime: '09:00',
        endTime: '10:00',
        weekdays: const [1, 2, 3],
        targetDurationMinutes: 60,
        createdAt: DateTime(2026),
      );

      final json = routine.toInsertJson();
      expect(json['subject_id'], 's-1');
      expect(json['title'], 'Maths');
      expect(json['target_duration_minutes'], 60);
      expect(json.containsKey('id'), false);
    });
  });

  group('RoutineLog', () {
    test('fromJson parses all fields correctly', () {
      final json = {
        'id': 'log-1',
        'routine_id': 'r-1',
        'log_date': '2026-09-19',
        'completed': true,
        'status': 'COMPLETED',
        'duration_minutes': 45,
        'completed_at': '2026-09-19T10:00:00Z',
        'created_at': '2026-09-19T10:00:00Z',
        'updated_at': '2026-09-19T10:00:00Z',
      };

      final log = RoutineLog.fromJson(json);

      expect(log.id, 'log-1');
      expect(log.routineId, 'r-1');
      expect(log.logDate, '2026-09-19');
      expect(log.completed, true);
      expect(log.status, 'COMPLETED');
      expect(log.durationMinutes, 45);
      expect(log.isCompleted, true);
      expect(log.isSkipped, false);
      expect(log.isMissed, false);
      expect(log.isPending, false);
    });

    test('fromJson defaults completed from boolean when status missing', () {
      final json = {
        'id': 'log-1',
        'routine_id': 'r-1',
        'log_date': '2026-09-19',
        'completed': true,
        'created_at': '2026-09-19T10:00:00Z',
      };

      final log = RoutineLog.fromJson(json);
      expect(log.status, 'COMPLETED');
    });

    test('fromJson defaults to PENDING when completed is false', () {
      final json = {
        'id': 'log-1',
        'routine_id': 'r-1',
        'log_date': '2026-09-19',
        'completed': false,
        'created_at': '2026-09-19T10:00:00Z',
      };

      final log = RoutineLog.fromJson(json);
      expect(log.status, 'PENDING');
    });

    test('status getters work correctly', () {
      final completed = RoutineLog(
        id: '1',
        routineId: 'r-1',
        logDate: '2026-09-19',
        status: 'COMPLETED',
        completed: true,
        createdAt: DateTime(2026),
      );
      final skipped = RoutineLog(
        id: '2',
        routineId: 'r-1',
        logDate: '2026-09-19',
        status: 'SKIPPED',
        completed: false,
        createdAt: DateTime(2026),
      );
      final missed = RoutineLog(
        id: '3',
        routineId: 'r-1',
        logDate: '2026-09-19',
        status: 'MISSED',
        completed: false,
        createdAt: DateTime(2026),
      );
      final pending = RoutineLog(
        id: '4',
        routineId: 'r-1',
        logDate: '2026-09-19',
        status: 'PENDING',
        completed: false,
        createdAt: DateTime(2026),
      );

      expect(completed.isCompleted, true);
      expect(skipped.isSkipped, true);
      expect(missed.isMissed, true);
      expect(pending.isPending, true);
    });

    test('equality is based on routineId and logDate', () {
      final a = RoutineLog(
        id: 'log-1',
        routineId: 'r-1',
        logDate: '2026-09-19',
        completed: false,
        createdAt: DateTime(2026),
      );
      final b = RoutineLog(
        id: 'log-2',
        routineId: 'r-1',
        logDate: '2026-09-19',
        completed: false,
        createdAt: DateTime(2027),
      );
      final c = RoutineLog(
        id: 'log-3',
        routineId: 'r-1',
        logDate: '2026-09-20',
        completed: false,
        createdAt: DateTime(2026),
      );

      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
      expect(a == c, false);
    });
  });

  group('RoutineWithLog', () {
    test('isCompleted reflects log status', () {
      final routine = Routine(
        id: 'r-1',
        userId: 'u-1',
        startTime: '09:00',
        endTime: '10:00',
        createdAt: DateTime(2026),
      );
      final completedLog = RoutineLog(
        id: 'log-1',
        routineId: 'r-1',
        logDate: '2026-09-19',
        status: 'COMPLETED',
        completed: true,
        createdAt: DateTime(2026),
      );

      final withLog = RoutineWithLog(routine: routine, log: completedLog);
      final withoutLog = RoutineWithLog(routine: routine);

      expect(withLog.isCompleted, true);
      expect(withoutLog.isCompleted, false);
      expect(withoutLog.isPending, true);
    });
  });
}
