import 'package:flutter_test/flutter_test.dart';

import 'package:my_praperation/core/models/answer.dart';
import 'package:my_praperation/core/models/attempt.dart';
import 'package:my_praperation/core/models/result.dart';

void main() {
  group('Answer model', () {
    test('fromJson parses all fields', () {
      final answer = Answer.fromJson({
        'attempt_id': 'a-1',
        'question_id': 'q-1',
        'selected_option_id': 'opt-2',
        'text_answer': null,
        'is_marked_for_review': true,
        'is_answered': true,
      });

      expect(answer.attemptId, 'a-1');
      expect(answer.questionId, 'q-1');
      expect(answer.selectedOptionId, 'opt-2');
      expect(answer.textAnswer, isNull);
      expect(answer.isMarkedForReview, true);
      expect(answer.isAnswered, true);
    });

    test('fromJson defaults booleans to false when null', () {
      final answer = Answer.fromJson({
        'attempt_id': 'a-1',
        'question_id': 'q-1',
        'selected_option_id': null,
        'text_answer': null,
        'is_marked_for_review': null,
        'is_answered': null,
      });

      expect(answer.isMarkedForReview, false);
      expect(answer.isAnswered, false);
    });

    test('toJson produces correct keys', () {
      const answer = Answer(
        attemptId: 'a-1',
        questionId: 'q-1',
        selectedOptionId: 'opt-1',
        isMarkedForReview: true,
        isAnswered: true,
      );

      final json = answer.toJson();
      expect(json['attempt_id'], 'a-1');
      expect(json['question_id'], 'q-1');
      expect(json['selected_option_id'], 'opt-1');
      expect(json['is_marked_for_review'], true);
      expect(json['is_answered'], true);
    });

    test('toJson does not contain correct_option', () {
      const answer = Answer(
        attemptId: 'a-1',
        questionId: 'q-1',
      );

      final json = answer.toJson();
      expect(json.containsKey('correct_option'), false);
    });

    test('fromJson/toJson roundtrip preserves all fields', () {
      const original = Answer(
        attemptId: 'a-1',
        questionId: 'q-1',
        selectedOptionId: 'opt-3',
        textAnswer: 'hello',
        isMarkedForReview: true,
        isAnswered: true,
      );

      final restored = Answer.fromJson(original.toJson());
      expect(restored, original);
    });

    test('copyWith overrides provided fields', () {
      const answer = Answer(
        attemptId: 'a-1',
        questionId: 'q-1',
        selectedOptionId: 'opt-1',
      );

      final updated = answer.copyWith(
        selectedOptionId: 'opt-2',
        isMarkedForReview: true,
      );

      expect(updated.selectedOptionId, 'opt-2');
      expect(updated.isMarkedForReview, true);
      expect(updated.attemptId, 'a-1');
      expect(updated.questionId, 'q-1');
    });

    test('copyWith keeps original when no args', () {
      const answer = Answer(
        attemptId: 'a-1',
        questionId: 'q-1',
        selectedOptionId: 'opt-1',
        isAnswered: true,
      );

      final copy = answer.copyWith();
      expect(copy, answer);
    });

    test('equality works correctly', () {
      const a1 = Answer(attemptId: 'a', questionId: 'q', selectedOptionId: 'o');
      const a2 = Answer(attemptId: 'a', questionId: 'q', selectedOptionId: 'o');
      const a3 = Answer(attemptId: 'a', questionId: 'q', selectedOptionId: 'x');

      expect(a1, a2);
      expect(a1 == a3, false);
    });
  });

  group('Attempt model', () {
    test('fromJson parses all fields', () {
      final attempt = Attempt.fromJson({
        'id': 'att-1',
        'test_id': 't-1',
        'user_id': 'u-1',
        'status': 'in_progress',
        'started_at': '2026-09-13T10:00:00Z',
        'deadline_at': '2026-09-13T11:00:00Z',
        'submitted_at': '2026-09-13T10:45:00Z',
        'integrity_event_count': 2,
        'auto_submit_threshold': 5,
      });

      expect(attempt.id, 'att-1');
      expect(attempt.testId, 't-1');
      expect(attempt.userId, 'u-1');
      expect(attempt.status, AttemptStatus.inProgress);
      expect(attempt.startedAt, DateTime.utc(2026, 9, 13, 10));
      expect(attempt.deadlineAt, DateTime.utc(2026, 9, 13, 11));
      expect(attempt.submittedAt, DateTime.utc(2026, 9, 13, 10, 45));
      expect(attempt.integrityEventCount, 2);
      expect(attempt.autoSubmitThreshold, 5);
    });

    test('fromJson handles null optional fields', () {
      final attempt = Attempt.fromJson({
        'id': 'att-1',
        'test_id': 't-1',
        'user_id': 'u-1',
        'status': 'in_progress',
        'started_at': '2026-09-13T10:00:00Z',
        'deadline_at': null,
        'submitted_at': null,
        'integrity_event_count': null,
        'auto_submit_threshold': null,
      });

      expect(attempt.deadlineAt, isNull);
      expect(attempt.submittedAt, isNull);
      expect(attempt.integrityEventCount, isNull);
      expect(attempt.autoSubmitThreshold, isNull);
    });

    test('toJson roundtrip preserves scalar fields', () {
      final original = Attempt(
        id: 'att-1',
        testId: 't-1',
        userId: 'u-1',
        status: AttemptStatus.inProgress,
        startedAt: DateTime.utc(2026, 9, 13, 10),
        deadlineAt: DateTime.utc(2026, 9, 13, 11),
        integrityEventCount: 1,
        autoSubmitThreshold: 3,
      );

      final restored = Attempt.fromJson(original.toJson());
      expect(restored.id, original.id);
      expect(restored.testId, original.testId);
      expect(restored.userId, original.userId);
      expect(restored.startedAt, original.startedAt);
      expect(restored.deadlineAt, original.deadlineAt);
      expect(restored.integrityEventCount, original.integrityEventCount);
      expect(restored.autoSubmitThreshold, original.autoSubmitThreshold);
    });

    test('isInProgress returns true only for in_progress status', () {
      final inProgress = Attempt(
        id: 'a',
        testId: 't',
        userId: 'u',
        status: AttemptStatus.inProgress,
        startedAt: DateTime.now(),
      );
      final submitted = Attempt(
        id: 'a',
        testId: 't',
        userId: 'u',
        status: AttemptStatus.submitted,
        startedAt: DateTime.now(),
      );

      expect(inProgress.isInProgress, true);
      expect(submitted.isInProgress, false);
    });

    test('isSubmitted returns true for submitted, auto_submitted, and scored', () {
      final submitted = Attempt(
        id: 'a',
        testId: 't',
        userId: 'u',
        status: AttemptStatus.submitted,
        startedAt: DateTime.now(),
      );
      final autoSubmitted = Attempt(
        id: 'a',
        testId: 't',
        userId: 'u',
        status: AttemptStatus.autoSubmitted,
        startedAt: DateTime.now(),
      );
      final scored = Attempt(
        id: 'a',
        testId: 't',
        userId: 'u',
        status: AttemptStatus.scored,
        startedAt: DateTime.now(),
      );
      final inProgress = Attempt(
        id: 'a',
        testId: 't',
        userId: 'u',
        status: AttemptStatus.inProgress,
        startedAt: DateTime.now(),
      );

      expect(submitted.isSubmitted, true);
      expect(autoSubmitted.isSubmitted, true);
      expect(scored.isSubmitted, true);
      expect(inProgress.isSubmitted, false);
    });

    test('timeRemaining returns null when no deadline', () {
      final attempt = Attempt(
        id: 'a',
        testId: 't',
        userId: 'u',
        status: AttemptStatus.inProgress,
        startedAt: DateTime.now(),
      );

      expect(attempt.timeRemaining, isNull);
    });

    test('timeRemaining returns Duration when deadline is future', () {
      final attempt = Attempt(
        id: 'a',
        testId: 't',
        userId: 'u',
        status: AttemptStatus.inProgress,
        startedAt: DateTime.now(),
        deadlineAt: DateTime.now().add(const Duration(minutes: 30)),
      );

      final remaining = attempt.timeRemaining;
      expect(remaining, isNotNull);
      expect(remaining!.inMinutes, greaterThanOrEqualTo(29));
      expect(remaining.inMinutes, lessThanOrEqualTo(30));
    });

    test('timeRemaining returns zero when deadline is past', () {
      final attempt = Attempt(
        id: 'a',
        testId: 't',
        userId: 'u',
        status: AttemptStatus.inProgress,
        startedAt: DateTime.now(),
        deadlineAt: DateTime.now().subtract(const Duration(minutes: 5)),
      );

      expect(attempt.timeRemaining, Duration.zero);
    });

    test('equality is based on id, testId, userId, status', () {
      final a1 = Attempt(
        id: 'a',
        testId: 't',
        userId: 'u',
        status: AttemptStatus.inProgress,
        startedAt: DateTime(2026, 1, 1),
      );
      final a2 = Attempt(
        id: 'a',
        testId: 't',
        userId: 'u',
        status: AttemptStatus.inProgress,
        startedAt: DateTime(2026, 1, 1),
      );
      final a3 = Attempt(
        id: 'a',
        testId: 't',
        userId: 'u',
        status: AttemptStatus.submitted,
        startedAt: DateTime(2026, 1, 1),
      );

      expect(a1, a2);
      expect(a1 == a3, false);
    });
  });

  group('Attempt RPC response parsing (AttemptService._parseAttemptResponse)', () {
    // NOTE: _parseAttemptResponse is private and static in AttemptService.
    // It handles two formats:
    //   1. RPC response: { attempt_id, test_id, status: "started"|"resumed", started_at, deadline_at }
    //   2. Full DB row: { id, test_id, user_id, status: "in_progress"|..., started_at, ... }
    //
    // Format 1 maps operation status ("started"/"resumed") → AttemptStatus.inProgress.
    // Format 2 uses _parseAttemptStatus() which expects snake_case DB values.
    //
    // These cannot be unit-tested without mocking Supabase. Integration tests
    // will verify correct behavior. The following tests verify the DB-format path
    // which is what Attempt.fromJson handles.

    test('Attempt.fromJson parses DB-format status "in_progress"', () {
      final attempt = Attempt.fromJson({
        'id': 'att-1',
        'test_id': 't-1',
        'user_id': 'u-1',
        'status': 'in_progress',
        'started_at': '2026-09-13T10:00:00Z',
      });

      expect(attempt.status, AttemptStatus.inProgress);
    });

    test('Attempt.fromJson maps "submitted" DB status correctly', () {
      final attempt = Attempt.fromJson({
        'id': 'att-1',
        'test_id': 't-1',
        'user_id': 'u-1',
        'status': 'submitted',
        'started_at': '2026-09-13T10:00:00Z',
      });

      expect(attempt.status, AttemptStatus.submitted);
    });

    test('Attempt.fromJson maps "auto_submitted" DB status correctly', () {
      final attempt = Attempt.fromJson({
        'id': 'att-1',
        'test_id': 't-1',
        'user_id': 'u-1',
        'status': 'auto_submitted',
        'started_at': '2026-09-13T10:00:00Z',
      });

      expect(attempt.status, AttemptStatus.autoSubmitted);
    });

    test('Attempt.fromJson maps "scored" DB status correctly', () {
      final attempt = Attempt.fromJson({
        'id': 'att-1',
        'test_id': 't-1',
        'user_id': 'u-1',
        'status': 'scored',
        'started_at': '2026-09-13T10:00:00Z',
      });

      expect(attempt.status, AttemptStatus.scored);
    });

    test('Attempt.toJson serializes status as enum name', () {
      final attempt = Attempt(
        id: 'att-1',
        testId: 't-1',
        userId: 'u-1',
        status: AttemptStatus.inProgress,
        startedAt: DateTime.utc(2026, 9, 13, 10),
      );

      final json = attempt.toJson();
      expect(json['status'], 'inProgress');
    });
  });

  group('Result model', () {
    test('fromJson parses required fields', () {
      final result = Result.fromJson({
        'id': 'r-1',
        'attempt_id': 'a-1',
        'test_id': 't-1',
        'user_id': 'u-1',
      });

      expect(result.id, 'r-1');
      expect(result.attemptId, 'a-1');
      expect(result.testId, 't-1');
      expect(result.userId, 'u-1');
    });

    test('fromJson parses optional numeric fields', () {
      final result = Result.fromJson({
        'id': 'r-1',
        'attempt_id': 'a-1',
        'test_id': 't-1',
        'user_id': 'u-1',
        'total_marks': 100,
        'marks_obtained': 75.5,
        'percentage': 75.5,
        'correct_count': 15,
        'wrong_count': 3,
        'unanswered_count': 2,
        'partial_count': 1,
        'total_questions': 20,
        'score': 75.5,
        'max_score': 100,
        'accuracy': 83.33,
        'rank': 5,
      });

      expect(result.totalMarks, 100);
      expect(result.marksObtained, 75.5);
      expect(result.percentage, 75.5);
      expect(result.correctCount, 15);
      expect(result.wrongCount, 3);
      expect(result.unansweredCount, 2);
      expect(result.partialCount, 1);
      expect(result.totalQuestions, 20);
      expect(result.score, 75.5);
      expect(result.maxScore, 100);
      expect(result.accuracy, closeTo(83.33, 0.01));
      expect(result.rank, 5);
    });

    test('fromJson parses optional boolean and string fields', () {
      final result = Result.fromJson({
        'id': 'r-1',
        'attempt_id': 'a-1',
        'test_id': 't-1',
        'user_id': 'u-1',
        'is_passed': true,
        'generation_method': 'server',
      });

      expect(result.isPassed, true);
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
      expect(result.isPassed, isNull);
      expect(result.subjectBreakdown, isNull);
      expect(result.topicBreakdown, isNull);
      expect(result.computedAt, isNull);
    });

    test('fromJson parses subject_breakdown map', () {
      final result = Result.fromJson({
        'id': 'r-1',
        'attempt_id': 'a-1',
        'test_id': 't-1',
        'user_id': 'u-1',
        'subject_breakdown': {'math': 80, 'science': 60},
      });

      expect(result.subjectBreakdown, {'math': 80, 'science': 60});
    });

    test('fromJson parses computed_at datetime', () {
      final result = Result.fromJson({
        'id': 'r-1',
        'attempt_id': 'a-1',
        'test_id': 't-1',
        'user_id': 'u-1',
        'computed_at': '2026-09-13T12:00:00Z',
      });

      expect(result.computedAt, DateTime.utc(2026, 9, 13, 12));
    });

    test('toJson excludes computedAt', () {
      final result = Result(
        id: 'r-1',
        attemptId: 'a-1',
        testId: 't-1',
        userId: 'u-1',
        computedAt: DateTime.utc(2026, 9, 13, 12),
      );

      final json = result.toJson();
      expect(json.containsKey('computed_at'), false);
    });

    test('equality is based on id, attemptId, testId', () {
      final r1 = Result(id: 'r', attemptId: 'a', testId: 't', userId: 'u');
      final r2 = Result(id: 'r', attemptId: 'a', testId: 't', userId: 'u');
      final r3 = Result(id: 'r', attemptId: 'a', testId: 'x', userId: 'u');

      expect(r1, r2);
      expect(r1 == r3, false);
    });
  });

  group('Answer validation', () {
    test('empty selectedOptionId and textAnswer is valid for unanswered', () {
      const answer = Answer(
        attemptId: 'a-1',
        questionId: 'q-1',
      );

      expect(answer.selectedOptionId, isNull);
      expect(answer.textAnswer, isNull);
      expect(answer.isAnswered, false);
    });

    test('selectedOptionId set marks answer as valid MCQ', () {
      const answer = Answer(
        attemptId: 'a-1',
        questionId: 'q-1',
        selectedOptionId: 'opt-2',
        isAnswered: true,
      );

      expect(answer.selectedOptionId, 'opt-2');
      expect(answer.isAnswered, true);
    });

    test('textAnswer set marks answer as valid short answer', () {
      const answer = Answer(
        attemptId: 'a-1',
        questionId: 'q-1',
        textAnswer: 'Paris is the capital of France',
        isAnswered: true,
      );

      expect(answer.textAnswer, 'Paris is the capital of France');
      expect(answer.isAnswered, true);
    });
  });

  group('Answer service payload structure', () {
    test('toJson list produces correct array for batch save', () {
      final answers = [
        const Answer(
          attemptId: 'a-1',
          questionId: 'q-1',
          selectedOptionId: 'opt-1',
          isAnswered: true,
        ),
        const Answer(
          attemptId: 'a-1',
          questionId: 'q-2',
          textAnswer: 'short answer',
          isAnswered: true,
        ),
        const Answer(
          attemptId: 'a-1',
          questionId: 'q-3',
          isMarkedForReview: true,
        ),
      ];

      final payload = answers.map((a) => a.toJson()).toList();
      expect(payload.length, 3);
      expect(payload[0]['question_id'], 'q-1');
      expect(payload[1]['question_id'], 'q-2');
      expect(payload[2]['question_id'], 'q-3');
    });

    test('empty list produces empty array', () {
      final answers = <Answer>[];
      final payload = answers.map((a) => a.toJson()).toList();
      expect(payload, isEmpty);
    });
  });

  group('Attempt status parsing edge cases', () {
    test('unknown status maps to AttemptStatus.unknown', () {
      final attempt = Attempt.fromJson({
        'id': 'att-1',
        'test_id': 't-1',
        'user_id': 'u-1',
        'status': 'bogus_status',
        'started_at': '2026-09-13T10:00:00Z',
      });

      expect(attempt.status, AttemptStatus.unknown);
    });

    test('null status maps to AttemptStatus.unknown', () {
      final attempt = Attempt.fromJson({
        'id': 'att-1',
        'test_id': 't-1',
        'user_id': 'u-1',
        'status': null,
        'started_at': '2026-09-13T10:00:00Z',
      });

      expect(attempt.status, AttemptStatus.unknown);
    });
  });
}
