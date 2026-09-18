// RULE 1/2: opening a taking URL (cold start / deep link) must never allocate
// an attempt. Only an existing in_progress attempt may be resumed.
import 'package:flutter_test/flutter_test.dart';
import 'package:my_praperation/core/models/answer.dart';
import 'package:my_praperation/core/models/test.dart';
import 'package:my_praperation/features/test/data/answer_repository.dart';
import 'package:my_praperation/features/test/state/attempt_controller.dart';
import 'package:my_praperation/features/test/state/attempt_launch_store.dart';

import 'fakes.dart';

class _NoAnswers implements AnswerRepository {
  @override
  Future<void> save(String attemptId, List<Answer> answers) async {}
  @override
  Future<List<Answer>> forAttempt(String attemptId) async => const [];
}

AttemptController _c(FakeAttemptRepository a, {String attemptId = 'a-100'}) =>
    AttemptController(
      attemptId: attemptId,
      testId: 't-1',
      attempts: a,
      questions: FakeQuestionRepository(),
      answers: _NoAnswers(),
      tests: FakeTestRepository()
        ..rows['t-1'] = Test(
          id: 't-1',
          createdBy: 'c',
          title: 'T',
          status: TestStatus.published,
          testMode: 'self',
        ),
      autosaveInterval: const Duration(hours: 1),
    );

void main() {
  setUp(AttemptLaunchStore.clear);

  test(
    'in_progress attempt: cold start resumes the same attempt (no allocation)',
    () async {
      final a = FakeAttemptRepository();
      final started = await a.start('t-1'); // a-100 in progress
      final c = _c(a, attemptId: started.attempt.id);
      await c.load();
      expect(c.error, isNull);
      expect(c.attempt!.id, started.attempt.id);
      expect(a.rows.length, 1);
      c.dispose();
    },
  );

  test(
    'terminal attempt: cold start stops with a message and never calls start',
    () async {
      final a = FakeAttemptRepository();
      final started = await a.start('t-1');
      a.complete(started.attempt.id);
      a.calls.clear();
      final c = _c(a, attemptId: started.attempt.id);
      await c.load();
      expect(c.error, contains('already been submitted'));
      expect(a.calls.where((x) => x.startsWith('start:')), isEmpty);
      expect(a.rows.length, 1);
      c.dispose();
    },
  );

  test('no attempt at all: taking URL does not create attempt 1', () async {
    final a = FakeAttemptRepository();
    final c = _c(a, attemptId: 'a-unknown');
    await c.load();
    expect(c.error, contains('No attempt is in progress'));
    expect(a.rows, isEmpty);
    expect(a.calls.where((x) => x.startsWith('start:')), isEmpty);
    c.dispose();
  });
}
