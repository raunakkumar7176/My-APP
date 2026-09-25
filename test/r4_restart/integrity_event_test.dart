// FINAL AUDIT — anti-cheat/test-integrity: AttemptController.recordIntegrityEvent
// against the client's contract with rpc_record_integrity_event (mirrored by
// FakeAttemptRepository — ownership/test-relationship/terminal-state/dedup/
// threshold rules, not the real Postgres function itself; see
// docs/FINAL_AUDIT_INTEGRITY_EVENTS_REPORT.md for what this can and cannot
// prove without a live database).

import 'package:flutter_test/flutter_test.dart';
import 'package:my_praperation/core/models/answer.dart';
import 'package:my_praperation/core/models/attempt.dart';
import 'package:my_praperation/core/models/question.dart';
import 'package:my_praperation/core/models/test.dart';
import 'package:my_praperation/features/test/data/answer_repository.dart';
import 'package:my_praperation/features/test/state/attempt_controller.dart';
import 'package:my_praperation/features/test/state/attempt_launch_store.dart';

import 'fakes.dart';

class _FakeAnswerRepository implements AnswerRepository {
  @override
  Future<void> save(String attemptId, List<Answer> answers) async {}
  @override
  Future<List<Answer>> forAttempt(String attemptId) async => const [];
}

const _q1 = Question(
  id: 'q-1',
  testId: 't-1',
  ordinal: 1,
  question: 'Q1',
  options: [QuestionOption(id: 'a', text: 'A'), QuestionOption(id: 'b', text: 'B')],
  difficulty: DifficultyLevel.easy,
  marks: 1,
  status: 'approved',
  questionType: QuestionType.mcqSingle,
);

Test _test() => const Test(
  id: 't-1',
  createdBy: 'u-1',
  title: 'T',
  status: TestStatus.published,
  testMode: 'self',
);

Attempt _attempt(
  String id, {
  AttemptStatus status = AttemptStatus.inProgress,
  int? integrityEventCount,
  int? autoSubmitThreshold,
}) => Attempt(
  id: id,
  testId: 't-1',
  userId: 'u-1',
  status: status,
  startedAt: DateTime(2026, 9, 16),
  deadlineAt: DateTime(2026, 9, 16, 1),
  integrityEventCount: integrityEventCount,
  autoSubmitThreshold: autoSubmitThreshold,
);

void main() {
  setUp(AttemptLaunchStore.clear);

  AttemptController build(
    FakeAttemptRepository attempts, {
    int? integrityEventCount,
    int? autoSubmitThreshold,
    AttemptStatus status = AttemptStatus.inProgress,
  }) {
    AttemptLaunchStore.putLaunch(
      started: (
        attempt: _attempt(
          'a-1',
          status: status,
          integrityEventCount: integrityEventCount,
          autoSubmitThreshold: autoSubmitThreshold,
        ),
        testTitle: null,
      ),
      questions: const [_q1],
      test: _test(),
    );
    return AttemptController(
      attemptId: 'a-1',
      testId: 't-1',
      attempts: attempts,
      questions: FakeQuestionRepository(),
      answers: _FakeAnswerRepository(),
      tests: FakeTestRepository(),
      autosaveInterval: const Duration(hours: 1),
    );
  }

  group('recordIntegrityEvent', () {
    test('reports an event and reflects the server-held count', () async {
      final attempts = FakeAttemptRepository()
        ..rows.add(_attempt('a-1', integrityEventCount: 0, autoSubmitThreshold: 3));
      final c = build(attempts, integrityEventCount: 0, autoSubmitThreshold: 3);
      await c.load();

      c.recordIntegrityEvent('app_backgrounded');
      await Future<void>.delayed(Duration.zero);

      expect(attempts.calls, ['integrity:a-1:app_backgrounded']);
      expect(c.integrityEventCount, 1);
      expect(c.integrityAutoSubmitted, isFalse);
      c.dispose();
    });

    test('does nothing once the attempt is no longer interactive', () async {
      final attempts = FakeAttemptRepository()
        ..rows.add(_attempt('a-1', status: AttemptStatus.scored));
      final c = build(attempts, status: AttemptStatus.scored);
      await c.load();
      expect(c.isInteractive, isFalse);

      c.recordIntegrityEvent('app_backgrounded');
      await Future<void>.delayed(Duration.zero);

      expect(
        attempts.calls,
        isEmpty,
        reason: 'the controller never calls the server once its own attempt state is terminal',
      );
      c.dispose();
    });

    test('single-flight: a report already in progress suppresses a concurrent one', () async {
      final attempts = FakeAttemptRepository()
        ..rows.add(_attempt('a-1', integrityEventCount: 0, autoSubmitThreshold: 5));
      final c = build(attempts, integrityEventCount: 0, autoSubmitThreshold: 5);
      await c.load();

      c.recordIntegrityEvent('app_backgrounded');
      c.recordIntegrityEvent('app_backgrounded'); // fired before the first resolves
      await Future<void>.delayed(Duration.zero);

      expect(
        attempts.calls,
        ['integrity:a-1:app_backgrounded'],
        reason: 'only one network call for the burst',
      );
      expect(c.integrityEventCount, 1);
      c.dispose();
    });

    test('server-side duplicate suppression is reflected (count does not double-increment)', () async {
      final attempts = FakeAttemptRepository();
      attempts.now = () => DateTime(2026, 9, 16, 0, 30);
      attempts.rows.add(_attempt('a-1', integrityEventCount: 0, autoSubmitThreshold: 5));
      final c = build(attempts, integrityEventCount: 0, autoSubmitThreshold: 5);
      await c.load();

      c.recordIntegrityEvent('app_backgrounded');
      await Future<void>.delayed(Duration.zero);
      expect(c.integrityEventCount, 1);

      // A second, distinct call (not blocked by single-flight since the
      // first has already resolved) for the same event type, still within
      // the server's 3-second dedup window (fake clock held constant).
      c.recordIntegrityEvent('app_backgrounded');
      await Future<void>.delayed(Duration.zero);

      expect(attempts.calls.length, 2, reason: 'both calls reached the server');
      expect(c.integrityEventCount, 1, reason: 'second was suppressed as a duplicate, not counted twice');
      c.dispose();
    });

    test('reaching the threshold auto-submits and stops further answering', () async {
      final attempts = FakeAttemptRepository()
        ..rows.add(_attempt('a-1', integrityEventCount: 2, autoSubmitThreshold: 3));
      final c = build(attempts, integrityEventCount: 2, autoSubmitThreshold: 3);
      await c.load();
      expect(c.isInteractive, isTrue);

      c.recordIntegrityEvent('multi_window_entered');
      await Future<void>.delayed(Duration.zero);

      expect(c.integrityEventCount, 3);
      expect(c.integrityAutoSubmitted, isTrue);
      expect(c.isInteractive, isFalse, reason: 'server auto-submitted the attempt');

      // A further event after auto-submit must not call the server again.
      c.recordIntegrityEvent('app_backgrounded');
      await Future<void>.delayed(Duration.zero);
      expect(attempts.calls.length, 1);
      c.dispose();
    });

    test('a repository failure is swallowed and never surfaces as a controller error', () async {
      final attempts = FakeAttemptRepository()
        ..rows.add(_attempt('a-1', integrityEventCount: 0, autoSubmitThreshold: 3))
        ..failIntegrityWith = Exception('network down');
      final c = build(attempts, integrityEventCount: 0, autoSubmitThreshold: 3);
      await c.load();

      c.recordIntegrityEvent('app_backgrounded');
      await Future<void>.delayed(Duration.zero);

      expect(c.error, isNull, reason: 'a lost integrity report must not block answering');
      expect(c.integrityEventCount, 0, reason: 'unchanged — the server never confirmed it');
      c.dispose();
    });
  });
}
