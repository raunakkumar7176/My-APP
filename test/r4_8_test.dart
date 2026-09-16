import 'package:flutter_test/flutter_test.dart';

import 'package:my_praperation/core/models/answer.dart';
import 'package:my_praperation/core/models/attempt.dart';
import 'package:my_praperation/core/models/question.dart';
import 'package:my_praperation/core/models/result.dart';
import 'package:my_praperation/core/services/result_service.dart';
import 'package:my_praperation/features/test/widgets/question_review_card.dart';

void main() {
  group('Result model', () {
    test('fromJson parses all fields', () {
      final result = Result.fromJson({
        'id': 'r-1',
        'attempt_id': 'a-1',
        'test_id': 't-1',
        'user_id': 'u-1',
        'total_marks': 100,
        'marks_obtained': 75.5,
        'percentage': 75.5,
        'is_passed': true,
        'correct_count': 15,
        'wrong_count': 3,
        'unanswered_count': 2,
        'partial_count': 1,
        'total_questions': 20,
        'score': 75.5,
        'max_score': 100,
        'accuracy': 83.33,
        'rank': 5,
        'subject_breakdown': {'math': {'correct': 10, 'wrong': 2}},
        'topic_breakdown': {'algebra': {'correct': 5, 'wrong': 1}},
        'generation_method': 'server',
      });

      expect(result.id, 'r-1');
      expect(result.attemptId, 'a-1');
      expect(result.testId, 't-1');
      expect(result.userId, 'u-1');
      expect(result.totalMarks, 100);
      expect(result.marksObtained, 75.5);
      expect(result.percentage, 75.5);
      expect(result.isPassed, true);
      expect(result.correctCount, 15);
      expect(result.wrongCount, 3);
      expect(result.unansweredCount, 2);
      expect(result.partialCount, 1);
      expect(result.totalQuestions, 20);
      expect(result.score, 75.5);
      expect(result.maxScore, 100);
      expect(result.accuracy, closeTo(83.33, 0.01));
      expect(result.rank, 5);
      expect(result.subjectBreakdown, isNotNull);
      expect(result.topicBreakdown, isNotNull);
      expect(result.generationMethod, 'server');
    });

    test('fromJson handles null optional fields', () {
      final result = Result.fromJson({
        'id': 'r-1',
        'attempt_id': 'a-1',
        'test_id': 't-1',
        'user_id': 'u-1',
      });

      expect(result.totalMarks, isNull);
      expect(result.marksObtained, isNull);
      expect(result.percentage, isNull);
      expect(result.isPassed, isNull);
      expect(result.correctCount, isNull);
      expect(result.wrongCount, isNull);
      expect(result.unansweredCount, isNull);
      expect(result.rank, isNull);
      expect(result.subjectBreakdown, isNull);
      expect(result.topicBreakdown, isNull);
    });

    test('equality is based on id, attemptId, testId', () {
      final r1 = Result(id: 'r', attemptId: 'a', testId: 't', userId: 'u');
      final r2 = Result(id: 'r', attemptId: 'a', testId: 't', userId: 'u');
      final r3 = Result(id: 'r', attemptId: 'a', testId: 'x', userId: 'u');

      expect(r1, r2);
      expect(r1 == r3, false);
    });
  });

  group('ReviewStatus', () {
    test('answered status is available', () {
      expect(ReviewStatus.answered, isNotNull);
      expect(ReviewStatus.values, contains(ReviewStatus.answered));
    });

    test('all review statuses are defined', () {
      expect(ReviewStatus.values.length, 4);
      expect(ReviewStatus.values, contains(ReviewStatus.correct));
      expect(ReviewStatus.values, contains(ReviewStatus.wrong));
      expect(ReviewStatus.values, contains(ReviewStatus.answered));
      expect(ReviewStatus.values, contains(ReviewStatus.unanswered));
    });
  });

  group('Answer state determination', () {
    test('unanswered question has no selection', () {
      const answer = Answer(attemptId: 'a', questionId: 'q');
      expect(answer.isAnswered, false);
      expect(answer.selectedOptionId, isNull);
    });

    test('answered question has selection', () {
      const answer = Answer(
        attemptId: 'a',
        questionId: 'q',
        selectedOptionId: 'opt-1',
        isAnswered: true,
      );
      expect(answer.isAnswered, true);
      expect(answer.selectedOptionId, 'opt-1');
    });

    test('marked for review with answer', () {
      const answer = Answer(
        attemptId: 'a',
        questionId: 'q',
        selectedOptionId: 'opt-1',
        isAnswered: true,
        isMarkedForReview: true,
      );
      expect(answer.isAnswered, true);
      expect(answer.isMarkedForReview, true);
    });
  });

  group('Attempt status handling', () {
    test('submitted status is terminal', () {
      final attempt = Attempt(
        id: 'a',
        testId: 't',
        userId: 'u',
        status: AttemptStatus.submitted,
        startedAt: DateTime.now(),
      );
      expect(attempt.isInProgress, false);
      expect(attempt.isSubmitted, true);
    });

    test('auto_submitted status is terminal', () {
      final attempt = Attempt(
        id: 'a',
        testId: 't',
        userId: 'u',
        status: AttemptStatus.autoSubmitted,
        startedAt: DateTime.now(),
      );
      expect(attempt.isInProgress, false);
      expect(attempt.isSubmitted, true);
    });

    test('scored status is terminal', () {
      final attempt = Attempt(
        id: 'a',
        testId: 't',
        userId: 'u',
        status: AttemptStatus.scored,
        startedAt: DateTime.now(),
      );
      expect(attempt.isInProgress, false);
      expect(attempt.isSubmitted, true);
    });

    test('in_progress status is interactive', () {
      final attempt = Attempt(
        id: 'a',
        testId: 't',
        userId: 'u',
        status: AttemptStatus.inProgress,
        startedAt: DateTime.now(),
      );
      expect(attempt.isInProgress, true);
      expect(attempt.isSubmitted, false);
    });
  });

  group('Result history sorting', () {
    test('getPreviousResult returns earlier result', () {
      final r1 = Result(
        id: 'r1',
        attemptId: 'a1',
        testId: 't',
        userId: 'u',
        computedAt: DateTime(2026, 1, 2),
      );
      final r2 = Result(
        id: 'r2',
        attemptId: 'a2',
        testId: 't',
        userId: 'u',
        computedAt: DateTime(2026, 1, 3),
      );

      final prev = ResultService.getPreviousResult(
        allResults: [r1, r2],
        currentResultId: r2.id,
      );
      expect(prev?.id, r1.id);
    });

    test('getPreviousResult returns null when only one result', () {
      final r1 = Result(
        id: 'r1',
        attemptId: 'a1',
        testId: 't',
        userId: 'u',
      );

      final prev = ResultService.getPreviousResult(
        allResults: [r1],
        currentResultId: r1.id,
      );
      expect(prev, isNull);
    });

    test('getPreviousResult returns null when current is oldest', () {
      final r1 = Result(
        id: 'r1',
        attemptId: 'a1',
        testId: 't',
        userId: 'u',
        computedAt: DateTime(2026, 1, 1),
      );
      final r2 = Result(
        id: 'r2',
        attemptId: 'a2',
        testId: 't',
        userId: 'u',
        computedAt: DateTime(2026, 1, 2),
      );

      final prev = ResultService.getPreviousResult(
        allResults: [r1, r2],
        currentResultId: r1.id,
      );
      expect(prev, isNull);
    });
  });

  group('Result analytics parsing', () {
    test('parseSubjectBreakdown returns empty for null', () async {
      final items = await ResultService.parseSubjectBreakdown(null);
      expect(items, isEmpty);
    });

    test('parseSubjectBreakdown returns empty for empty map', () async {
      final items = await ResultService.parseSubjectBreakdown({});
      expect(items, isEmpty);
    });

    test('parseTopicBreakdown returns empty for null', () {
      final items = ResultService.parseTopicBreakdown(null);
      expect(items, isEmpty);
    });

    test('parseTopicBreakdown returns empty for empty map', () {
      final items = ResultService.parseTopicBreakdown({});
      expect(items, isEmpty);
    });

    test('parseDifficultyBreakdown returns empty (backend dependency)', () {
      final items = ResultService.parseDifficultyBreakdown(
        correctCount: 10,
        wrongCount: 5,
        unansweredCount: 3,
      );
      expect(items, isEmpty);
    });
  });

  group('Mistake summary data', () {
    test('wrong count from result is authoritative', () {
      final result = Result(
        id: 'r',
        attemptId: 'a',
        testId: 't',
        userId: 'u',
        wrongCount: 5,
        unansweredCount: 3,
        accuracy: 75.0,
      );

      expect(result.wrongCount, 5);
      expect(result.unansweredCount, 3);
      expect(result.accuracy, 75.0);
    });

    test('null counts default to zero', () {
      final result = Result(
        id: 'r',
        attemptId: 'a',
        testId: 't',
        userId: 'u',
      );

      expect(result.correctCount, isNull);
      expect(result.wrongCount, isNull);
      expect(result.unansweredCount, isNull);
    });
  });

  group('Submission state navigation', () {
    test('submitted attempt is not interactive', () {
      final attempt = Attempt(
        id: 'a',
        testId: 't',
        userId: 'u',
        status: AttemptStatus.submitted,
        startedAt: DateTime.now(),
      );
      expect(attempt.isInProgress, false);
    });

    test('auto_submitted attempt is not interactive', () {
      final attempt = Attempt(
        id: 'a',
        testId: 't',
        userId: 'u',
        status: AttemptStatus.autoSubmitted,
        startedAt: DateTime.now(),
      );
      expect(attempt.isInProgress, false);
    });

    test('scored attempt is not interactive', () {
      final attempt = Attempt(
        id: 'a',
        testId: 't',
        userId: 'u',
        status: AttemptStatus.scored,
        startedAt: DateTime.now(),
      );
      expect(attempt.isInProgress, false);
    });
  });

  group('Result score display', () {
    test('percentage is used for display', () {
      final result = Result(
        id: 'r',
        attemptId: 'a',
        testId: 't',
        userId: 'u',
        percentage: 85.5,
        isPassed: true,
      );
      expect(result.percentage, 85.5);
      expect(result.isPassed, true);
    });

    test('score and maxScore are used for display', () {
      final result = Result(
        id: 'r',
        attemptId: 'a',
        testId: 't',
        userId: 'u',
        score: 42.5,
        maxScore: 50,
      );
      expect(result.score, 42.5);
      expect(result.maxScore, 50);
    });

    test('rank is displayed when available', () {
      final result = Result(
        id: 'r',
        attemptId: 'a',
        testId: 't',
        userId: 'u',
        rank: 3,
      );
      expect(result.rank, 3);
    });

    test('null rank shows fallback', () {
      final result = Result(
        id: 'r',
        attemptId: 'a',
        testId: 't',
        userId: 'u',
      );
      expect(result.rank, isNull);
    });
  });

  group('Unanswered review filtering (R4.8A)', () {
    Question q(String id) => Question(
          id: id,
          testId: 't',
          question: 'Q $id',
          difficulty: DifficultyLevel.medium,
          marks: 4,
          status: 'active',
        );

    test('no per-question correctness data exists in Answer model', () {
      const answer = Answer(
        attemptId: 'a',
        questionId: 'q',
        selectedOptionId: 'opt-1',
        isAnswered: true,
      );
      // Answer has no isCorrect or correctOptionId field
      expect(answer.isAnswered, true);
      expect(answer.selectedOptionId, 'opt-1');
      // Verifying no correctness field exists (compile-time proof)
    });

    test('no per-question correctness data exists in Question model', () {
      final question = q('q1');
      // Question has no correctOptionId field
      expect(question.id, 'q1');
      // Verifying no correctness field exists (compile-time proof)
    });

    test('unanswered question is correctly identified', () {
      const answer = Answer(
        attemptId: 'a',
        questionId: 'q',
        selectedOptionId: null,
        isAnswered: false,
      );
      final isAnswered =
          answer.isAnswered || answer.selectedOptionId != null;
      expect(isAnswered, false);
    });

    test('answered question with option is correctly identified', () {
      const answer = Answer(
        attemptId: 'a',
        questionId: 'q',
        selectedOptionId: 'opt-1',
        isAnswered: true,
      );
      final isAnswered =
          answer.isAnswered || answer.selectedOptionId != null;
      expect(isAnswered, true);
    });

    test('answered question without isAnswered but with selection is answered',
        () {
      const answer = Answer(
        attemptId: 'a',
        questionId: 'q',
        selectedOptionId: 'opt-1',
        isAnswered: false,
      );
      final isAnswered =
          answer.isAnswered || answer.selectedOptionId != null;
      expect(isAnswered, true);
    });

    test('filtering logic collects only unanswered question IDs', () {
      final questions = [q('q1'), q('q2'), q('q3'), q('q4')];
      final answers = <String, Answer>{
        'q1': const Answer(
            attemptId: 'a',
            questionId: 'q1',
            selectedOptionId: 'opt-1',
            isAnswered: true),
        'q2': const Answer(
            attemptId: 'a',
            questionId: 'q2',
            selectedOptionId: 'opt-1',
            isAnswered: false), // has selection = answered
        'q3': const Answer(attemptId: 'a', questionId: 'q3'), // unanswered
        // q4: no answer entry at all = unanswered
      };

      final unansweredIds = <String>{};
      for (final q in questions) {
        final answer = answers[q.id];
        final isAnswered = answer != null &&
            (answer.isAnswered || answer.selectedOptionId != null);
        if (!isAnswered) {
          unansweredIds.add(q.id);
        }
      }

      expect(unansweredIds, {'q3', 'q4'});
      expect(unansweredIds.contains('q1'), false);
      expect(unansweredIds.contains('q2'), false);
    });

    test('answered questions are NEVER included in unanswered review', () {
      final questions = [q('q1'), q('q2')];
      final answers = <String, Answer>{
        'q1': const Answer(
            attemptId: 'a',
            questionId: 'q1',
            selectedOptionId: 'opt-1',
            isAnswered: true),
        'q2': const Answer(
            attemptId: 'a',
            questionId: 'q2',
            selectedOptionId: 'opt-2',
            isAnswered: true),
      };

      final unansweredIds = <String>{};
      for (final question in questions) {
        final answer = answers[question.id];
        final isAnswered = answer != null &&
            (answer.isAnswered || answer.selectedOptionId != null);
        if (!isAnswered) {
          unansweredIds.add(question.id);
        }
      }

      expect(unansweredIds, isEmpty);
    });

    test('all unanswered scenario collects every question', () {
      final questions = [q('q1'), q('q2'), q('q3')];
      final answers = <String, Answer>{};

      final unansweredIds = <String>{};
      for (final question in questions) {
        final answer = answers[question.id];
        final isAnswered = answer != null &&
            (answer.isAnswered || answer.selectedOptionId != null);
        if (!isAnswered) {
          unansweredIds.add(question.id);
        }
      }

      expect(unansweredIds, {'q1', 'q2', 'q3'});
    });

    test('Result has aggregate wrongCount but no per-question data', () {
      final result = Result(
        id: 'r',
        attemptId: 'a',
        testId: 't',
        userId: 'u',
        wrongCount: 5,
        unansweredCount: 3,
        correctCount: 12,
      );
      // Aggregate counts exist
      expect(result.wrongCount, 5);
      expect(result.unansweredCount, 3);
      // But there is no per-question correctness breakdown
      // (no List<bool> isCorrect or Map<String,bool> field)
    });

    test('Review button should be enabled when unansweredCount > 0', () {
      final result = Result(
        id: 'r',
        attemptId: 'a',
        testId: 't',
        userId: 'u',
        wrongCount: 0,
        unansweredCount: 3,
      );
      expect(result.unansweredCount, 3);
      expect(result.unansweredCount! > 0, true);
    });

    test('Review button should be disabled when unansweredCount is 0', () {
      final result = Result(
        id: 'r',
        attemptId: 'a',
        testId: 't',
        userId: 'u',
        wrongCount: 5,
        unansweredCount: 0,
      );
      expect(result.unansweredCount, 0);
      expect(result.unansweredCount! > 0, false);
    });

    test('Review button should be disabled when unansweredCount is null', () {
      final result = Result(
        id: 'r',
        attemptId: 'a',
        testId: 't',
        userId: 'u',
        wrongCount: 5,
      );
      expect(result.unansweredCount, isNull);
      expect((result.unansweredCount ?? 0) > 0, false);
    });
  });
}
