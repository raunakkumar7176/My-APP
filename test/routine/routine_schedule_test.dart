// Routine V1 — pure schedule helpers: time parsing, validation, conflicts and
// the structured title that carries Subject → Topic → Activity.

import 'package:flutter_test/flutter_test.dart';
import 'package:my_praperation/core/models/routine.dart';
import 'package:my_praperation/features/routine/domain/routine_schedule.dart';

void main() {
  group('time parsing', () {
    test('HH:MM and HH:MM:SS parse to minutes; garbage is null', () {
      expect(RoutineSchedule.toMinutes('09:30'), 570);
      expect(RoutineSchedule.toMinutes('09:30:00'), 570);
      expect(RoutineSchedule.toMinutes('00:00'), 0);
      expect(RoutineSchedule.toMinutes('23:59'), 1439);
      expect(RoutineSchedule.toMinutes('24:00'), isNull);
      expect(RoutineSchedule.toMinutes('09:60'), isNull);
      expect(RoutineSchedule.toMinutes('nine'), isNull);
      expect(RoutineSchedule.toMinutes(''), isNull);
    });

    test('toHHmm and format12h', () {
      expect(RoutineSchedule.toHHmm(570), '09:30');
      expect(RoutineSchedule.toHHmm(0), '00:00');
      expect(RoutineSchedule.format12h('00:05'), '12:05 AM');
      expect(RoutineSchedule.format12h('12:00'), '12:00 PM');
      expect(RoutineSchedule.format12h('18:30:00'), '6:30 PM');
    });

    test('weekdaysLabel', () {
      expect(RoutineSchedule.weekdaysLabel([0, 1, 2, 3, 4, 5, 6]), 'Every day');
      expect(RoutineSchedule.weekdaysLabel([1, 2, 3, 4, 5]), 'Weekdays');
      expect(RoutineSchedule.weekdaysLabel([0, 6]), 'Weekends');
      expect(RoutineSchedule.weekdaysLabel([3, 1]), 'Mon, Wed');
    });
  });

  group('validate', () {
    test('valid slot passes', () {
      expect(
        RoutineSchedule.validate(startTime: '09:00', endTime: '10:00', weekdays: [1]),
        isNull,
      );
      expect(
        RoutineSchedule.validate(
          startTime: '09:00',
          endTime: '10:00',
          weekdays: [1],
          targetDurationMinutes: 60,
        ),
        isNull,
      );
    });

    test('invalid start/end: end before or equal to start, malformed', () {
      expect(
        RoutineSchedule.validate(startTime: '10:00', endTime: '09:00', weekdays: [1]),
        'End time must be after start time',
      );
      expect(
        RoutineSchedule.validate(startTime: '10:00', endTime: '10:00', weekdays: [1]),
        'End time must be after start time',
      );
      expect(
        RoutineSchedule.validate(startTime: '25:00', endTime: '10:00', weekdays: [1]),
        'Enter a valid start and end time',
      );
    });

    test('invalid duration: zero, negative, longer than the slot', () {
      expect(
        RoutineSchedule.validate(
          startTime: '09:00',
          endTime: '10:00',
          weekdays: [1],
          targetDurationMinutes: 0,
        ),
        contains('positive'),
      );
      expect(
        RoutineSchedule.validate(
          startTime: '09:00',
          endTime: '10:00',
          weekdays: [1],
          targetDurationMinutes: -5,
        ),
        contains('positive'),
      );
      expect(
        RoutineSchedule.validate(
          startTime: '09:00',
          endTime: '10:00',
          weekdays: [1],
          targetDurationMinutes: 61,
        ),
        contains('longer than the time slot (60 min)'),
      );
    });

    test('weekdays: empty or out of range', () {
      expect(
        RoutineSchedule.validate(startTime: '09:00', endTime: '10:00', weekdays: []),
        'Select at least one day',
      );
      expect(
        RoutineSchedule.validate(startTime: '09:00', endTime: '10:00', weekdays: [7]),
        'Select valid days',
      );
    });
  });

  group('overlaps (conflict rule)', () {
    test('same day, overlapping times → conflict', () {
      expect(
        RoutineSchedule.overlaps(
          aStart: '09:00', aEnd: '10:00', aDays: [1, 2],
          bStart: '09:30', bEnd: '11:00', bDays: [2, 3],
        ),
        isTrue,
      );
    });

    test('touching slots do not overlap ([start, end) semantics)', () {
      expect(
        RoutineSchedule.overlaps(
          aStart: '09:00', aEnd: '10:00', aDays: [1],
          bStart: '10:00', bEnd: '11:00', bDays: [1],
        ),
        isFalse,
      );
    });

    test('no shared weekday → no conflict even at the same time', () {
      expect(
        RoutineSchedule.overlaps(
          aStart: '09:00', aEnd: '10:00', aDays: [1],
          bStart: '09:00', bEnd: '10:00', bDays: [2],
        ),
        isFalse,
      );
    });

    test('containment counts as overlap', () {
      expect(
        RoutineSchedule.overlaps(
          aStart: '08:00', aEnd: '12:00', aDays: [5],
          bStart: '09:00', bEnd: '10:00', bDays: [5],
        ),
        isTrue,
      );
    });
  });

  group('structured title (Subject → Topic → Activity)', () {
    test('compose joins base, topic, activity with the separator', () {
      expect(
        RoutineSchedule.composeTitle(base: 'Morning', topic: 'Number System', activity: 'Lecture'),
        'Morning · Number System · Lecture',
      );
      expect(RoutineSchedule.composeTitle(topic: 'Cell', activity: 'Revision'), 'Cell · Revision');
      expect(RoutineSchedule.composeTitle(activity: 'Memorization'), 'Memorization');
      expect(RoutineSchedule.composeTitle(), RoutineSchedule.defaultTitle);
      expect(RoutineSchedule.composeTitle(base: '  '), RoutineSchedule.defaultTitle);
    });

    test('compose does not repeat a topic typed as the title', () {
      expect(RoutineSchedule.composeTitle(base: 'Cell', topic: 'Cell'), 'Cell');
    });

    test('parse round-trips when topic names are known', () {
      const title = 'Morning · Number System · Lecture';
      final p = RoutineSchedule.parseTitle(title, knownTopics: ['Number System', 'Algebra']);
      expect(p.base, 'Morning');
      expect(p.topic, 'Number System');
      expect(p.activity, 'Lecture');
      expect(
        RoutineSchedule.composeTitle(base: p.base, topic: p.topic, activity: p.activity),
        title,
      );
    });

    test('parse without topic names keeps the topic in the base, activity still found', () {
      final p = RoutineSchedule.parseTitle('Ancient India · Memorization');
      expect(p.base, 'Ancient India');
      expect(p.topic, isNull);
      expect(p.activity, 'Memorization');
    });

    test('parse of default and plain titles', () {
      final d = RoutineSchedule.parseTitle(RoutineSchedule.defaultTitle);
      expect(d.base, '');
      expect(d.activity, isNull);
      final plain = RoutineSchedule.parseTitle('Evening reading');
      expect(plain.base, 'Evening reading');
      expect(plain.topic, isNull);
      expect(plain.activity, isNull);
    });

    test('editing never re-appends the activity (compose ∘ parse is idempotent)', () {
      var title = RoutineSchedule.composeTitle(base: 'Maths', activity: 'Revision');
      for (var i = 0; i < 3; i++) {
        final p = RoutineSchedule.parseTitle(title);
        title = RoutineSchedule.composeTitle(base: p.base, topic: p.topic, activity: p.activity);
      }
      expect(title, 'Maths · Revision');
    });
  });

  test('scheduledOn filters active routines by live weekday and sorts by start', () {
    Routine r(String id, List<int> days, String start, {bool active = true}) => Routine(
      id: id,
      userId: 'u',
      startTime: start,
      endTime: '23:00',
      weekdays: days,
      isActive: active,
      createdAt: DateTime.utc(2026),
    );
    final out = RoutineSchedule.scheduledOn(
      [
        r('late', [0, 1], '18:00'),
        r('early', [1], '06:00'),
        r('paused', [1], '05:00', active: false),
        r('sunday', [0], '07:00'),
      ],
      1,
    );
    expect(out.map((e) => e.id), ['early', 'late']);
  });
}
