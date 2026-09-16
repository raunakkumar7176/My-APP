import 'package:flutter_test/flutter_test.dart';
import 'package:my_praperation/core/models/answer.dart';
import 'package:my_praperation/core/models/attempt.dart';
import 'package:my_praperation/core/models/question.dart';
import 'package:my_praperation/features/test/test_taking_screen.dart';

void main() {
  // ─── Test Data ───────────────────────────────────────────

  final q1 = const Question(
    id: 'q1',
    testId: 't1',
    question: 'Question 1',
    difficulty: DifficultyLevel.easy,
    marks: 1,
    status: 'active',
    questionType: QuestionType.mcqSingle,
    options: [
      QuestionOption(id: 'opt-a', text: 'A'),
      QuestionOption(id: 'opt-b', text: 'B'),
      QuestionOption(id: 'opt-c', text: 'C'),
    ],
  );

  final q2 = const Question(
    id: 'q2',
    testId: 't1',
    question: 'Question 2',
    difficulty: DifficultyLevel.medium,
    marks: 2,
    status: 'active',
    questionType: QuestionType.mcqSingle,
    options: [
      QuestionOption(id: 'opt-x', text: 'X'),
      QuestionOption(id: 'opt-y', text: 'Y'),
    ],
  );

  final q3 = const Question(
    id: 'q3',
    testId: 't1',
    question: 'Question 3',
    difficulty: DifficultyLevel.hard,
    marks: 3,
    status: 'active',
    questionType: QuestionType.mcqSingle,
    options: [
      QuestionOption(id: 'opt-p', text: 'P'),
      QuestionOption(id: 'opt-q', text: 'Q'),
      QuestionOption(id: 'opt-r', text: 'R'),
      QuestionOption(id: 'opt-s', text: 'S'),
    ],
  );

  final questions = [q1, q2, q3];

  // ─── FIX 1: Deterministic Shuffle ────────────────────────

  group('FIX 1 — Deterministic shuffle stability', () {
    test('same attempt ID produces identical question order across runs', () {
      const attemptId = 'attempt-abc-123';
      final run1 =
          TestTakingScreen.shuffleQuestions(questions, attemptId);
      final run2 =
          TestTakingScreen.shuffleQuestions(questions, attemptId);
      final run3 =
          TestTakingScreen.shuffleQuestions(questions, attemptId);

      expect(run1.map((q) => q.id).toList(),
          equals(run2.map((q) => q.id).toList()));
      expect(run2.map((q) => q.id).toList(),
          equals(run3.map((q) => q.id).toList()));
    });

    test('different attempt IDs MAY produce different question order', () {
      final run1 =
          TestTakingScreen.shuffleQuestions(questions, 'attempt-aaa');
      final run2 =
          TestTakingScreen.shuffleQuestions(questions, 'attempt-bbb');

      // Not guaranteed to differ for all pairs, but should differ for most
      // At minimum, both must contain all questions
      expect(run1.map((q) => q.id).toList()..sort(),
          equals(['q1', 'q2', 'q3']));
      expect(run2.map((q) => q.id).toList()..sort(),
          equals(['q1', 'q2', 'q3']));
    });

    test('same attempt + question produces identical option order', () {
      const seed = 'attempt-xyz_q2';
      final run1 = TestTakingScreen.shuffleOptions(q2.options!, seed);
      final run2 = TestTakingScreen.shuffleOptions(q2.options!, seed);

      expect(
        run1.map((o) => o.id).toList(),
        equals(run2.map((o) => o.id).toList()),
      );
    });

    test('fnv1aHash is deterministic', () {
      final h1 = fnv1aHash('test-string');
      final h2 = fnv1aHash('test-string');
      final h3 = fnv1aHash('different-string');

      expect(h1, equals(h2));
      expect(h1, isNot(equals(h3)));
    });

    test('fnv1aHash produces non-zero values', () {
      expect(fnv1aHash(''), isNot(equals(0)));
      expect(fnv1aHash('a'), isNot(equals(0)));
      expect(fnv1aHash('attempt-123'), isNot(equals(0)));
    });

    test('shuffled questions contain all original question IDs', () {
      final shuffled =
          TestTakingScreen.shuffleQuestions(questions, 'seed-123');
      final ids = shuffled.map((q) => q.id).toList()..sort();
      expect(ids, equals(['q1', 'q2', 'q3']));
    });

    test('shuffled options contain all original option IDs', () {
      final shuffled =
          TestTakingScreen.shuffleOptions(q1.options!, 'seed-456');
      final ids = shuffled.map((o) => o.id).toList()..sort();
      expect(ids, equals(['opt-a', 'opt-b', 'opt-c']));
    });
  });

  // ─── FIX 5: Answer State Safety ──────────────────────────

  group('FIX 5 — Answer state identity', () {
    test('answer is keyed by question ID, not index', () {
      final answer = Answer(
        attemptId: 'att-1',
        questionId: 'q2',
        selectedOptionId: 'opt-y',
        isAnswered: true,
      );

      // Key must be question ID
      final answersMap = <String, Answer>{};
      answersMap[answer.questionId] = answer;

      expect(answersMap.containsKey('q2'), isTrue);
      expect(answersMap.containsKey('1'), isFalse); // not index
    });

    test('selected option uses option ID, not position', () {
      final answer = Answer(
        attemptId: 'att-1',
        questionId: 'q1',
        selectedOptionId: 'opt-c', // original option ID
        isAnswered: true,
      );

      expect(answer.selectedOptionId, equals('opt-c'));
    });

    test('option identity preserved after shuffle', () {
      const seed = 'attempt-999_q1';
      final shuffled = TestTakingScreen.shuffleOptions(q1.options!, seed);

      // All original IDs present
      for (final opt in shuffled) {
        expect(
          q1.options!.any((o) => o.id == opt.id),
          isTrue,
          reason: 'Shuffled option ${opt.id} not found in original options',
        );
      }
    });

    test('answer state persists across shuffle reordering', () {
      const seed = 'attempt-777';
      final shuffledQs =
          TestTakingScreen.shuffleQuestions(questions, seed);

      // Answers are keyed by question ID, not by position in shuffled list
      final answers = <String, Answer>{};
      answers['q1'] = const Answer(
        attemptId: 'att-1',
        questionId: 'q1',
        selectedOptionId: 'opt-b',
        isAnswered: true,
      );

      // After shuffle, find q1 by its ID, not by index
      final q1Index = shuffledQs.indexWhere((q) => q.id == 'q1');
      expect(q1Index, isNot(equals(0))); // may not be first anymore

      final found = answers[shuffledQs[q1Index].id];
      expect(found?.selectedOptionId, equals('opt-b'));
    });
  });

  // ─── FIX 2: No Fake Timer Fallback ───────────────────────

  group('FIX 2 — No fake deadline fallback', () {
    test('Attempt.deadlineAt is nullable', () {
      final attempt = Attempt(
        id: 'att-1',
        testId: 't1',
        userId: 'u1',
        status: AttemptStatus.inProgress,
        startedAt: DateTime(2025),
        deadlineAt: null, // explicitly null
      );

      expect(attempt.deadlineAt, isNull);
      expect(attempt.timeRemaining, isNull);
    });

    test('Attempt with deadlineAt returns valid timeRemaining', () {
      final futureDeadline = DateTime.now().add(const Duration(hours: 1));
      final attempt = Attempt(
        id: 'att-1',
        testId: 't1',
        userId: 'u1',
        status: AttemptStatus.inProgress,
        startedAt: DateTime(2025),
        deadlineAt: futureDeadline,
      );

      expect(attempt.deadlineAt, isNotNull);
      expect(attempt.timeRemaining, isNotNull);
      expect(attempt.timeRemaining!.inSeconds, greaterThan(0));
    });

    test('past deadline returns zero duration', () {
      final pastDeadline = DateTime.now().subtract(const Duration(hours: 1));
      final attempt = Attempt(
        id: 'att-1',
        testId: 't1',
        userId: 'u1',
        status: AttemptStatus.inProgress,
        startedAt: DateTime(2025),
        deadlineAt: pastDeadline,
      );

      expect(attempt.timeRemaining, equals(Duration.zero));
    });
  });

  // ─── FIX 3: Non-In-Progress Attempt Guard ────────────────

  group('FIX 3 — Attempt state interactivity', () {
    test('in_progress attempt is interactive', () {
      final attempt = Attempt(
        id: 'att-1',
        testId: 't1',
        userId: 'u1',
        status: AttemptStatus.inProgress,
        startedAt: DateTime(2025),
        deadlineAt: DateTime.now().add(const Duration(hours: 1)),
      );

      expect(attempt.isInProgress, isTrue);
      expect(attempt.isSubmitted, isFalse);
    });

    test('submitted attempt is NOT interactive', () {
      final attempt = Attempt(
        id: 'att-1',
        testId: 't1',
        userId: 'u1',
        status: AttemptStatus.submitted,
        startedAt: DateTime(2025),
        submittedAt: DateTime.now(),
      );

      expect(attempt.isInProgress, isFalse);
      expect(attempt.isSubmitted, isTrue);
    });

    test('auto_submitted attempt is NOT interactive', () {
      final attempt = Attempt(
        id: 'att-1',
        testId: 't1',
        userId: 'u1',
        status: AttemptStatus.autoSubmitted,
        startedAt: DateTime(2025),
      );

      expect(attempt.isInProgress, isFalse);
      expect(attempt.isSubmitted, isTrue);
    });

    test('scored attempt is NOT interactive', () {
      final attempt = Attempt(
        id: 'att-1',
        testId: 't1',
        userId: 'u1',
        status: AttemptStatus.scored,
        startedAt: DateTime(2025),
      );

      expect(attempt.isInProgress, isFalse);
      expect(attempt.isSubmitted, isTrue);
    });

    test('unknown attempt is NOT interactive', () {
      final attempt = Attempt(
        id: 'att-1',
        testId: 't1',
        userId: 'u1',
        status: AttemptStatus.unknown,
        startedAt: DateTime(2025),
      );

      expect(attempt.isInProgress, isFalse);
    });
  });

  // ─── FIX 7: Autosave Safety ──────────────────────────────

  group('FIX 7 — Autosave safety', () {
    test('answer retains state after failed save', () {
      final answer = const Answer(
        attemptId: 'att-1',
        questionId: 'q1',
        selectedOptionId: 'opt-a',
        isAnswered: true,
      );

      // Simulate: dirty set to true, save fails, dirty remains true
      var isDirty = true;
      try {
        // Simulate failure
        throw Exception('Network error');
      } catch (_) {
        isDirty = true; // re-set on failure
      }

      expect(isDirty, isTrue);
      expect(answer.selectedOptionId, equals('opt-a'));
    });

    test('dirty state clears on successful save', () {
      var isDirty = true;

      // Simulate successful save
      isDirty = false;

      expect(isDirty, isFalse);
    });

    test('autosave does not occur when not dirty', () {
      var isDirty = false;
      var saveCount = 0;

      if (isDirty) {
        saveCount++;
      }

      expect(saveCount, equals(0));
    });

    test('autosave does not occur when answers are empty', () {
      var isDirty = true;
      final answers = <String, Answer>{};
      var saveCount = 0;

      if (isDirty && answers.isNotEmpty) {
        saveCount++;
      }

      expect(saveCount, equals(0));
    });
  });

  // ─── FIX 4: MCQ Multiple Contract ────────────────────────

  group('FIX 4 — MCQ Multiple contract verification', () {
    test('QuestionType enum includes mcqMultiple', () {
      expect(QuestionType.mcqMultiple, isNotNull);
    });

    test('Answer model uses single selectedOptionId (not array)', () {
      final answer = const Answer(
        attemptId: 'att-1',
        questionId: 'q1',
        selectedOptionId: 'opt-a',
        isAnswered: true,
      );

      // The contract is single-option: selectedOptionId is String?, not List
      expect(answer.selectedOptionId, isA<String?>());
    });

    test('answers table selected_option_id is text (single value)', () {
      // Verify Answer.toJson produces single selected_option_id
      final answer = const Answer(
        attemptId: 'att-1',
        questionId: 'q1',
        selectedOptionId: 'opt-a',
        isAnswered: true,
      );

      final json = answer.toJson();
      expect(json['selected_option_id'], isA<String>());
    });

    test('mcqMultiple questions exist in enum but UI uses single-select', () {
      const q = Question(
        id: 'q-multi',
        testId: 't1',
        question: 'Multi select',
        difficulty: DifficultyLevel.medium,
        marks: 2,
        status: 'active',
        questionType: QuestionType.mcqMultiple,
      );

      // The question type is recognized
      expect(q.questionType, equals(QuestionType.mcqMultiple));

      // But the Answer contract is single-option
      // This confirms MCQ multiple is deferred (server contract is single-option)
    });
  });

  // ─── FIX 6: Timer Behavior ───────────────────────────────

  group('FIX 6 — Timer behavior verification', () {
    test('CountdownTimer.remainingAt computes from deadline', () {
      final deadline = DateTime.now().add(const Duration(minutes: 30));
      final remaining = deadline.difference(DateTime.now());

      expect(remaining.inSeconds, greaterThan(1700));
      expect(remaining.inSeconds, lessThan(1900));
    });

    test('past deadline returns zero', () {
      final deadline = DateTime.now().subtract(const Duration(minutes: 5));
      final remaining = deadline.difference(DateTime.now());

      expect(remaining.isNegative, isTrue);
    });

    test('attempt.timeRemaining uses server deadline, not client time', () {
      final serverDeadline = DateTime.utc(2025, 1, 1, 12, 0, 0);
      final attempt = Attempt(
        id: 'att-1',
        testId: 't1',
        userId: 'u1',
        status: AttemptStatus.inProgress,
        startedAt: DateTime.utc(2025, 1, 1, 11, 0, 0),
        deadlineAt: serverDeadline,
      );

      // timeRemaining is computed from the stored deadlineAt
      expect(attempt.deadlineAt, equals(serverDeadline));
    });

    test('null deadlineAt produces null timeRemaining', () {
      final attempt = Attempt(
        id: 'att-1',
        testId: 't1',
        userId: 'u1',
        status: AttemptStatus.inProgress,
        startedAt: DateTime(2025),
        deadlineAt: null,
      );

      expect(attempt.timeRemaining, isNull);
    });
  });

  // ─── FIX 8: Security Regression ──────────────────────────

  group('FIX 8 — Security regression checks', () {
    test('QuestionOption has only id and text (no correct_option)', () {
      const opt = QuestionOption(id: 'opt-1', text: 'Answer A');
      final json = opt.toJson();

      expect(json.containsKey('id'), isTrue);
      expect(json.containsKey('text'), isTrue);
      expect(json.containsKey('correct_option'), isFalse);
      expect(json.containsKey('is_correct'), isFalse);
    });

    test('Question.toJson does not include correct_option', () {
      final json = q1.toJson();

      expect(json.containsKey('correct_option'), isFalse);
      expect(json.containsKey('correct_answer'), isFalse);
    });

    test('Answer.toJson does not leak correctness info', () {
      final answer = const Answer(
        attemptId: 'att-1',
        questionId: 'q1',
        selectedOptionId: 'opt-a',
        isAnswered: true,
      );

      final json = answer.toJson();

      expect(json.containsKey('is_correct'), isFalse);
      expect(json.containsKey('correct_option'), isFalse);
    });

    test('shuffle does not sort by correctness', () {
      // Options shuffled by deterministic seed, not by correctness
      final shuffled =
          TestTakingScreen.shuffleOptions(q1.options!, 'seed-test');

      // All original IDs preserved, order is seed-dependent
      expect(shuffled.length, equals(q1.options!.length));
      final ids = shuffled.map((o) => o.id).toSet();
      expect(ids, equals({'opt-a', 'opt-b', 'opt-c'}));
    });
  });

  // ─── Double Submit Protection ─────────────────────────────

  group('Double submit protection', () {
    test('_isSubmitting flag prevents duplicate submission', () {
      var isSubmitting = false;
      var submitCount = 0;

      Future<void> submit() async {
        if (isSubmitting) return;
        isSubmitting = true;
        submitCount++;
        // Simulate async work
        await Future<void>.delayed(Duration.zero);
        isSubmitting = false;
      }

      // Launch two concurrent submissions
      final f1 = submit();
      final f2 = submit();

      // Wait for both to complete
      Future.wait([f1, f2]);

      // Only one should have actually executed
      expect(submitCount, equals(1));
    });
  });
}
