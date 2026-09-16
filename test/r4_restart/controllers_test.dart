// R4.4 / R4.5 — controller behaviour with in-memory repositories.

import 'package:flutter_test/flutter_test.dart';
import 'package:my_praperation/core/errors/app_error.dart';
import 'package:my_praperation/core/models/question.dart';
import 'package:my_praperation/core/models/test.dart';
import 'package:my_praperation/features/test/domain/test_kind.dart';
import 'package:my_praperation/features/test/domain/test_lifecycle.dart';
import 'package:my_praperation/features/test/models/question_draft.dart';
import 'package:my_praperation/features/test/state/test_creation_controller.dart';
import 'package:my_praperation/features/test/state/test_detail_controller.dart';
import 'package:my_praperation/features/test/state/test_listing_controller.dart';

import 'fakes.dart';

QuestionDraft _draft(String text) => QuestionDraft(
      questionText: text,
      options: const [QuestionOptionDraft(text: 'A'), QuestionOptionDraft(text: 'B')],
      correctOptionIndex: 0,
    );

Test _test(String id,
        {TestStatus status = TestStatus.published,
        String mode = 'self',
        String owner = 'u-1',
        DateTime? starts,
        DateTime? ends,
        Map<String, dynamic>? settings}) =>
    Test(
      id: id,
      createdBy: owner,
      title: id,
      status: status,
      testMode: mode,
      startsAt: starts,
      endsAt: ends,
      settings: settings,
    );

void main() {
  final now = DateTime(2026, 9, 16, 12);

  group('TestListingController', () {
    test('buckets via lifecycle and exposes drafts separately', () async {
      final repo = FakeTestRepository()
        ..rows.addAll({
          'd': _test('d', status: TestStatus.draft),
          'u': _test('u'),
          'c': _test('c', mode: 'live'),
          'p': _test('p', ends: now.subtract(const Duration(hours: 1))),
        });
      final c = TestListingController(repository: repo, clock: () => now);
      await c.load();

      expect(c.hasLoaded, isTrue);
      expect(c.error, isNull);
      expect(c.drafts.map((t) => t.id), ['d']);
      expect(c.testsFor(ListingCategory.upcoming).map((t) => t.id), ['u']);
      expect(c.testsFor(ListingCategory.challengeWithFriends).map((t) => t.id), ['c']);
      expect(c.testsFor(ListingCategory.previous).map((t) => t.id), ['p']);
      expect(c.testsFor(ListingCategory.drafts).map((t) => t.id), ['d'],
          reason: 'drafts come from listMyDrafts, not categorisation');
    });
  });

  group('TestDetailController', () {
    test('loads by id, derives owner/lifecycle flags, starts with safe questions',
        () async {
      final tests = FakeTestRepository()..rows['t-1'] = _test('t-1');
      final qs = FakeQuestionRepository()
        ..byTest['t-1'] = [
          const Question(
              id: 'q-1', testId: 't-1', question: 'Q', difficulty: DifficultyLevel.easy,
              marks: 1, status: 'approved'),
        ];
      final attempts = FakeAttemptRepository();
      final c = TestDetailController(
        testId: 't-1',
        tests: tests,
        questions: qs,
        attempts: attempts,
        results: FakeResultRepository(),
        currentUserId: () => 'u-1',
        clock: () => now,
      );
      await c.load();

      expect(c.test?.id, 't-1');
      expect(c.isOwner, isTrue);
      expect(c.canEdit, isFalse, reason: 'published');
      expect(c.canPublish, isFalse);
      expect(c.startBlockReason(), isNull);
      expect(c.kind, TestKind.self);

      final launched = await c.start();
      expect(attempts.calls, ['start:t-1']);
      expect(launched.questions.single.id, 'q-1');
      expect(launched.started.attempt.testId, 't-1');
    });

    test('draft: edit/publish allowed for owner, start blocked; non-owner nothing',
        () async {
      final tests = FakeTestRepository()..rows['t-1'] = _test('t-1', status: TestStatus.draft);
      TestDetailController make(String uid) => TestDetailController(
            testId: 't-1',
            tests: tests,
            questions: FakeQuestionRepository(),
            attempts: FakeAttemptRepository(),
            results: FakeResultRepository(),
            currentUserId: () => uid,
            clock: () => now,
          );
      final owner = make('u-1');
      await owner.load();
      expect(owner.canEdit, isTrue);
      expect(owner.canPublish, isTrue);
      expect(owner.startBlockReason(), contains('draft'));

      final other = make('u-2');
      await other.load();
      expect(other.canEdit, isFalse);
      expect(other.canPublish, isFalse);
    });

    test('start errors surface as AppError and busy flag resets', () async {
      final tests = FakeTestRepository()..rows['t-1'] = _test('t-1');
      final attempts = FakeAttemptRepository()
        ..failStartWith = const DataError(message: 'This test has ended.');
      final c = TestDetailController(
        testId: 't-1',
        tests: tests,
        questions: FakeQuestionRepository(),
        attempts: attempts,
        results: FakeResultRepository(),
        currentUserId: () => 'u-1',
        clock: () => now,
      );
      await c.load();
      await expectLater(c.start(), throwsA(isA<DataError>()));
      expect(c.isBusy, isFalse);
    });
  });

  group('TestCreationController', () {
    late FakeTestRepository tests;
    late FakeQuestionRepository qs;
    late TestCreationController c;

    setUp(() {
      tests = FakeTestRepository();
      qs = FakeQuestionRepository();
      c = TestCreationController(
        tests: tests,
        questions: qs,
        groups: FakeGroupRepository(),
        currentUserId: () => 'u-1',
      );
      c.setTitle('My test');
      c.setConfiguration(
        durationSec: 600,
        marksPerQuestion: 1,
        negativeMarks: 0,
        groupId: null,
        startsAt: null,
        endsAt: null,
        maxParticipants: null,
        allowLateJoin: false,
        accessCode: null,
        joinCode: null,
      );
    });

    test('Save Draft → Save Draft creates ONE test and each question once',
        () async {
      c.setLocalQuestions([_draft('q1'), _draft('q2')]);
      c.setSyllabusNodeIds(['n1']);

      final id1 = await c.saveDraft();
      final id2 = await c.saveDraft();

      expect(id1, id2);
      expect(tests.createCount, 1);
      expect(tests.calls.where((x) => x == 'create').length, 1);
      expect(tests.calls.where((x) => x.startsWith('update')).length, 1);
      expect(qs.calls.where((x) => x.startsWith('create')).length, 2);
      expect(tests.calls.where((x) => x.startsWith('addSyllabus')).length, 1);
      expect(c.localQuestions, isEmpty);
      expect(c.serverQuestions.length, 2, reason: 'reloaded via safe RPC');
      expect(c.isPersisted, isTrue);
    });

    test('partial question failure: created ones are not re-created on retry',
        () async {
      c.setLocalQuestions([_draft('q1'), _draft('q2'), _draft('q3')]);
      qs.failOnce.add('q2');

      await expectLater(c.saveDraft(), throwsA(isA<DataError>()));
      expect(qs.calls.where((x) => x.startsWith('create')).toList(),
          ['create:q1', 'create:q2']);
      expect(c.localQuestions.map((d) => d.questionText), ['q2', 'q3']);
      expect(c.isPersisted, isTrue, reason: 'test row was created before the failure');

      await c.saveDraft();
      expect(qs.calls.where((x) => x.startsWith('create')).toList(),
          ['create:q1', 'create:q2', 'create:q2', 'create:q3']);
      expect(tests.createCount, 1);
      expect(c.localQuestions, isEmpty);
    });

    test('publish: readiness blocks before any server call', () async {
      // no questions
      await expectLater(c.publish(), throwsA(isA<ValidationError>()));
      expect(tests.calls, isEmpty);
    });

    test('publish: creates, approves new questions, publishes once', () async {
      c.setLocalQuestions([_draft('q1')]);
      final id = await c.publish();

      expect(tests.createCount, 1);
      expect(qs.calls, containsAllInOrder(['create:q1', 'approve:q-1', 'safe:$id']));
      expect(tests.calls.last, 'publish:$id');
      expect(tests.rows[id]!.status, TestStatus.published);
    });

    test('publish: approval failure surfaces and does not publish', () async {
      c.setLocalQuestions([_draft('q1')]);
      qs.failApprove.add('q-1');

      await expectLater(c.publish(), throwsA(isA<DataError>()));
      expect(tests.calls.any((x) => x.startsWith('publish')), isFalse);
      expect(c.localQuestions, isEmpty, reason: 'q1 was persisted');
      expect(c.isPersisted, isTrue);
    });

    test('approveQuestion updates readiness immediately', () async {
      c.setLocalQuestions([_draft('q1')]);
      await c.saveDraft();
      expect(c.isReadyToPublish, isFalse);
      expect(c.readiness.firstWhere((i) => i.label == 'All questions approved').isValid,
          isFalse);

      await c.approveQuestion('q-1');
      expect(c.serverQuestions.single.status, 'approved');
      expect(c.isReadyToPublish, isTrue);
    });

    test('kinds map to backend once: Practice → self + settings; Challenge → live',
        () async {
      c.setKind(TestKind.practice);
      expect(c.durationSec, TestCreationController.practiceDefaultDurationSec);
      c.setLocalQuestions([_draft('q1')]);
      final id = await c.saveDraft();
      expect(tests.rows[id]!.testMode, 'self');
      expect(tests.rows[id]!.settings, {'test_kind': 'practice'});

      final c2 = TestCreationController(
        tests: tests,
        questions: qs,
        groups: FakeGroupRepository(),
        currentUserId: () => 'u-1',
      )
        ..setTitle('C')
        ..setKind(TestKind.challengeWithFriends)
        ..setLocalQuestions([_draft('x')]);
      final id2 = await c2.saveDraft();
      expect(tests.rows[id2]!.testMode, 'live');
      expect(tests.rows[id2]!.settings, isNull);
    });

    test('Quick persists target_question_count without clobbering settings',
        () async {
      c.setKind(TestKind.quick);
      c.setLocalQuestions([_draft('q1')]);
      final id = await c.saveDraft();
      expect(tests.rows[id]!.settings,
          {'test_kind': 'quick', 'target_question_count': 10});
      expect(c.questionsGuidance, contains('5–10'));
    });

    test('loadForEdit restores kind, questions and syllabus; rejects non-drafts',
        () async {
      tests.rows['t-9'] = _test('t-9',
          status: TestStatus.draft, settings: {'test_kind': 'sectional'});
      tests.syllabus['t-9'] = {'n1', 'n2'};
      qs.byTest['t-9'] = [
        const Question(
            id: 'q-9', testId: 't-9', question: 'Q', difficulty: DifficultyLevel.easy,
            marks: 1, status: 'pending_review'),
      ];
      final edit = TestCreationController(
        editingTestId: 't-9',
        tests: tests,
        questions: qs,
        groups: FakeGroupRepository(),
        currentUserId: () => 'u-1',
      );
      await edit.loadForEdit();
      expect(edit.loadError, isNull);
      expect(edit.kind, TestKind.sectional);
      expect(edit.serverQuestions.single.id, 'q-9');
      expect(edit.syllabusNodeIds, containsAll(['n1', 'n2']));

      // Deselect n2, add n3, save: exactly one remove and one add.
      edit.setSyllabusNodeIds(['n1', 'n3']);
      await edit.saveDraft();
      expect(tests.calls.where((x) => x == 'removeSyllabus:n2').length, 1);
      expect(tests.calls.where((x) => x == 'addSyllabus:n3').length, 1);
      expect(tests.createCount, 0);

      tests.rows['t-p'] = _test('t-p', status: TestStatus.published);
      final bad = TestCreationController(
          editingTestId: 't-p',
          tests: tests,
          questions: qs,
          groups: FakeGroupRepository(),
          currentUserId: () => 'u-1');
      await bad.loadForEdit();
      expect(bad.loadError, 'Only draft tests can be edited');
    });
  });
}
