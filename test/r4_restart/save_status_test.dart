// R4.5 — autosave sync status + unsaved-answer protection on the taking
// screen. Client-side only: the server row stays the truth; these tests
// cover the status machine, manual retry, and the Leave / Submit dialogs.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_praperation/core/errors/app_error.dart';
import 'package:my_praperation/core/models/answer.dart';
import 'package:my_praperation/core/models/attempt.dart';
import 'package:my_praperation/core/models/question.dart';
import 'package:my_praperation/core/models/test.dart';
import 'package:my_praperation/features/test/data/answer_repository.dart';
import 'package:my_praperation/features/test/screens/test_taking_screen.dart';
import 'package:my_praperation/features/test/state/attempt_controller.dart';
import 'package:my_praperation/features/test/state/attempt_launch_store.dart';

import 'fakes.dart';

/// Answer repository whose saves fail while [offline] is true.
class FlakyAnswerRepository implements AnswerRepository {
  bool offline = false;
  final List<List<Answer>> saves = [];

  @override
  Future<void> save(String attemptId, List<Answer> answers) async {
    if (offline) throw const NetworkError(message: 'Network error.');
    saves.add(List.of(answers));
  }

  @override
  Future<List<Answer>> forAttempt(String attemptId) async => const [];
}

const _q = Question(
  id: 'q-1',
  testId: 't-1',
  ordinal: 1,
  question: 'What is 2 + 2?',
  options: [
    QuestionOption(id: 'a', text: '3', index: 0),
    QuestionOption(id: 'b', text: '4', index: 1),
    QuestionOption(id: 'c', text: '5', index: 2),
    QuestionOption(id: 'd', text: '6', index: 3),
  ],
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
  settings: {'test_kind': 'practice'},
);

Attempt _attempt() => Attempt(
  id: 'a-1',
  testId: 't-1',
  userId: 'u-1',
  status: AttemptStatus.inProgress,
  startedAt: DateTime.now(),
  deadlineAt: DateTime.now().add(const Duration(hours: 1)),
);

AttemptController _controller(AnswerRepository answers) {
  AttemptLaunchStore.putLaunch(
    started: (attempt: _attempt(), testTitle: null),
    questions: const [_q],
    test: _test(),
  );
  return AttemptController(
    attemptId: 'a-1',
    testId: 't-1',
    attempts: FakeAttemptRepository(),
    questions: FakeQuestionRepository(),
    answers: answers,
    tests: FakeTestRepository(),
    autosaveInterval: const Duration(hours: 1),
  );
}

void main() {
  setUp(AttemptLaunchStore.clear);

  group('AttemptController save status', () {
    test(
      'idle → saving → saved with timestamp; no unsaved answers after',
      () async {
        final repo = FlakyAnswerRepository();
        final c = _controller(repo);
        await c.load();
        expect(c.saveStatus, SaveStatus.idle);
        expect(c.hasUnsavedAnswers, isFalse, reason: 'nothing answered yet');

        c.selectOption('q-1', 1);
        expect(c.hasUnsavedAnswers, isTrue);

        final statuses = <SaveStatus>[];
        c.addListener(() => statuses.add(c.saveStatus));
        await c.autosaveIfDirty();
        expect(statuses, [SaveStatus.saving, SaveStatus.saved]);
        expect(c.lastSavedAt, isNotNull);
        expect(c.saveError, isNull);
        expect(c.saveFailures, 0);
        expect(c.hasUnsavedAnswers, isFalse);
        expect(repo.saves.length, 1);
        c.dispose();
      },
    );

    test(
      'failure → failed with mapped message, counts, keeps answers dirty',
      () async {
        final repo = FlakyAnswerRepository()..offline = true;
        final c = _controller(repo);
        await c.load();
        c.selectOption('q-1', 1);

        await c.autosaveIfDirty();
        expect(c.saveStatus, SaveStatus.failed);
        expect(c.saveError, 'Network error.');
        expect(c.saveFailures, 1);
        expect(c.isDirty, isTrue);
        expect(c.hasUnsavedAnswers, isTrue);

        await c.autosaveIfDirty(); // next tick retries
        expect(c.saveFailures, 2);

        repo.offline = false;
        await c.autosaveIfDirty();
        expect(c.saveStatus, SaveStatus.saved);
        expect(c.saveFailures, 0);
        expect(c.saveError, isNull);
        expect(
          repo.saves.single.single.selectedOption,
          1,
          reason: 'no data lost',
        );
        c.dispose();
      },
    );

    test('retrySave forces a send and reports success/failure', () async {
      final repo = FlakyAnswerRepository()..offline = true;
      final c = _controller(repo);
      await c.load();
      expect(await c.retrySave(), isTrue, reason: 'nothing to save');

      c.selectOption('q-1', 2);
      expect(await c.retrySave(), isFalse);
      expect(c.saveStatus, SaveStatus.failed);

      repo.offline = false;
      expect(await c.retrySave(), isTrue);
      expect(c.saveStatus, SaveStatus.saved);
      expect(repo.saves.length, 1);
      c.dispose();
    });

    test(
      'manual submit with a failing flush rethrows and keeps answers',
      () async {
        final repo = FlakyAnswerRepository()..offline = true;
        final attempts = FakeAttemptRepository();
        AttemptLaunchStore.putLaunch(
          started: (attempt: _attempt(), testTitle: null),
          questions: const [_q],
          test: _test(),
        );
        final c = AttemptController(
          attemptId: 'a-1',
          testId: 't-1',
          attempts: attempts,
          questions: FakeQuestionRepository(),
          answers: repo,
          tests: FakeTestRepository(),
          autosaveInterval: const Duration(hours: 1),
        );
        await c.load();
        c.selectOption('q-1', 3);

        await expectLater(c.submit(timedOut: false), throwsA(isA<AppError>()));
        expect(c.saveStatus, SaveStatus.failed);
        expect(c.isSubmitting, isFalse);
        expect(c.isInteractive, isTrue, reason: 'attempt still open');
        expect(attempts.calls.where((x) => x.startsWith('submit')), isEmpty);
        expect(c.answerFor('q-1')!.selectedOption, 3);

        repo.offline = false;
        await c.submit(timedOut: false);
        expect(c.saveStatus, SaveStatus.saved);
        expect(c.isInteractive, isFalse);
        c.dispose();
      },
    );
  });

  group('TestTakingScreen save status UI', () {
    Future<AttemptController> pumpScreen(
      WidgetTester tester,
      AnswerRepository repo,
    ) async {
      final c = _controller(repo);
      await tester.pumpWidget(
        MaterialApp(
          home: TestTakingScreen(
            attemptId: 'a-1',
            testId: 't-1',
            controller: c,
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      return c;
    }

    testWidgets('saved line, failed strip with Retry now, recovers', (
      tester,
    ) async {
      final repo = FlakyAnswerRepository();
      final c = await pumpScreen(tester, repo);
      expect(find.byKey(const Key('save_status_saved')), findsNothing);

      await tester.tap(find.text('4'));
      await tester.pump();
      await c.autosaveIfDirty();
      await tester.pump();
      expect(find.byKey(const Key('save_status_saved')), findsOneWidget);
      expect(find.textContaining('Saved '), findsOneWidget);

      repo.offline = true;
      await tester.tap(find.text('5'));
      await tester.pump();
      await c.autosaveIfDirty();
      await tester.pump();
      expect(find.byKey(const Key('save_status_failed')), findsOneWidget);
      expect(find.textContaining('Answers not saved yet'), findsOneWidget);

      repo.offline = false;
      await tester.tap(find.byKey(const Key('save_retry_now')));
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const Key('save_status_saved')), findsOneWidget);
      expect(repo.saves.last.single.selectedOption, 2);

      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });

    testWidgets('Leave with unsaved answers: Save & Leave stays on failure', (
      tester,
    ) async {
      final repo = FlakyAnswerRepository()..offline = true;
      final c = await pumpScreen(tester, repo);
      await tester.tap(find.text('4'));
      await tester.pump();

      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('leave_unsaved_note')), findsOneWidget);
      expect(find.text('Save & Leave'), findsOneWidget);

      await tester.tap(find.byKey(const Key('leave_action')));
      await tester.pumpAndSettle();
      // Still on the taking screen (no router in this harness → a go()
      // would throw); the failure is surfaced and the answer is kept.
      expect(find.text('What is 2 + 2?'), findsOneWidget);
      expect(find.text('Network error.'), findsOneWidget);
      expect(c.answerFor('q-1')!.selectedOption, 1);
      expect(c.saveStatus, SaveStatus.failed);

      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });

    testWidgets('Leave with everything saved shows the plain note', (
      tester,
    ) async {
      final repo = FlakyAnswerRepository();
      final c = await pumpScreen(tester, repo);
      await tester.tap(find.text('4'));
      await tester.pump();
      await c.autosaveIfDirty();
      await tester.pump();

      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('leave_saved_note')), findsOneWidget);
      expect(find.text('Leave'), findsOneWidget);
      await tester.tap(find.text('Stay'));
      await tester.pumpAndSettle();

      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });

    testWidgets('Submit dialog warns about unsaved answers', (tester) async {
      final repo = FlakyAnswerRepository()..offline = true;
      final c = await pumpScreen(tester, repo);
      await tester.tap(find.text('4'));
      await tester.pump();
      await c.autosaveIfDirty();
      await tester.pump();

      await tester.tap(find.byKey(const Key('submit_button')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('submit_unsaved_note')), findsOneWidget);
      await tester.tap(find.text('Continue Test'));
      await tester.pumpAndSettle();

      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });
  });
}
