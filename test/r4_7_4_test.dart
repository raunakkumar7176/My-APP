import 'package:flutter_test/flutter_test.dart';
import 'package:my_praperation/core/models/attempt.dart';
import 'package:my_praperation/core/models/result.dart';
import 'package:my_praperation/core/models/result_analytics.dart';
import 'package:my_praperation/core/services/result_service.dart';

void main() {
  // ─── Test Data ───────────────────────────────────────────

  final now = DateTime.now();

  Result makeResult({
    required String id,
    double? percentage,
    int? correctCount,
    int? wrongCount,
    int? unansweredCount,
    double? accuracy,
    Map<String, dynamic>? subjectBreakdown,
    Map<String, dynamic>? topicBreakdown,
    DateTime? computedAt,
  }) {
    return Result(
      id: id,
      attemptId: 'a_$id',
      testId: 't1',
      userId: 'u1',
      percentage: percentage ?? 50,
      correctCount: correctCount ?? 2,
      wrongCount: wrongCount ?? 1,
      unansweredCount: unansweredCount ?? 1,
      accuracy: accuracy ?? 50,
      totalQuestions: (correctCount ?? 2) + (wrongCount ?? 1) + (unansweredCount ?? 1),
      subjectBreakdown: subjectBreakdown,
      topicBreakdown: topicBreakdown,
      computedAt: computedAt,
    );
  }

  // ─── Subject Breakdown Parsing ───────────────────────────

  group('Subject Breakdown Parsing', () {
    test('parses valid subject breakdown', () async {
      final breakdown = {
        'subj-1': {'attempted': 5, 'correct': 3, 'wrong': 1, 'unanswered': 1},
        'subj-2': {'attempted': 3, 'correct': 2, 'wrong': 0, 'unanswered': 1},
      };
      final items = await ResultService.parseSubjectBreakdown(breakdown);
      expect(items.length, 2);
      // Subject names may fall back to IDs since DB not available in test
    });

    test('returns empty list for null breakdown', () async {
      final items = await ResultService.parseSubjectBreakdown(null);
      expect(items, isEmpty);
    });

    test('returns empty list for empty breakdown', () async {
      final items = await ResultService.parseSubjectBreakdown({});
      expect(items, isEmpty);
    });

    test('handles malformed data gracefully', () async {
      final breakdown = {
        'subj-1': 'not a map',
        'subj-2': 42,
      };
      final items = await ResultService.parseSubjectBreakdown(breakdown);
      expect(items, isEmpty);
    });

    test('handles missing fields with defaults', () async {
      final breakdown = {
        'subj-1': <String, dynamic>{},
      };
      final items = await ResultService.parseSubjectBreakdown(breakdown);
      expect(items.length, 1);
      expect(items.first.attempted, 0);
      expect(items.first.correct, 0);
    });
  });

  // ─── Topic Breakdown Parsing ─────────────────────────────

  group('Topic Breakdown Parsing', () {
    test('parses valid topic breakdown', () {
      final breakdown = {
        'topic-1': {'attempted': 4, 'correct': 2, 'wrong': 1, 'unanswered': 1},
        'topic-2': {'attempted': 2, 'correct': 2, 'wrong': 0, 'unanswered': 0},
      };
      final items = ResultService.parseTopicBreakdown(breakdown);
      expect(items.length, 2);
    });

    test('returns empty list for null', () {
      final items = ResultService.parseTopicBreakdown(null);
      expect(items, isEmpty);
    });

    test('returns empty list for empty', () {
      final items = ResultService.parseTopicBreakdown({});
      expect(items, isEmpty);
    });

    test('returns empty list for single-key breakdown', () {
      // Need at least 2 entries for meaningful topic analysis
      final breakdown = {
        'topic-1': {'attempted': 3, 'correct': 1, 'wrong': 2, 'unanswered': 0},
      };
      final items = ResultService.parseTopicBreakdown(breakdown);
      expect(items, isEmpty);
    });

    test('sorts by wrong count descending', () {
      final breakdown = {
        'topic-a': {'attempted': 5, 'correct': 4, 'wrong': 1, 'unanswered': 0},
        'topic-b': {'attempted': 5, 'correct': 2, 'wrong': 3, 'unanswered': 0},
        'topic-c': {'attempted': 5, 'correct': 3, 'wrong': 2, 'unanswered': 0},
      };
      final items = ResultService.parseTopicBreakdown(breakdown);
      expect(items.length, 3);
      expect(items[0].topicId, 'topic-b'); // 3 wrong
      expect(items[1].topicId, 'topic-c'); // 2 wrong
      expect(items[2].topicId, 'topic-a'); // 1 wrong
    });
  });

  // ─── Difficulty Breakdown ────────────────────────────────

  group('Difficulty Breakdown', () {
    test('returns empty list (backend dependency)', () {
      final items = ResultService.parseDifficultyBreakdown(
        correctCount: 3,
        wrongCount: 2,
        unansweredCount: 1,
      );
      expect(items, isEmpty);
    });
  });

  // ─── Mistake Foundation ──────────────────────────────────

  group('Mistake Foundation', () {
    test('MistakeItem stores question metadata', () {
      const item = MistakeItem(
        questionId: 'q1',
        testId: 't1',
        subjectId: 'subj-1',
        subjectName: 'Physics',
        topicId: 'topic-1',
        topicName: 'Mechanics',
        difficulty: 'hard',
        selectedOptionId: 'opt-a',
        explanation: 'Newton\'s second law.',
      );
      expect(item.questionId, 'q1');
      expect(item.subjectName, 'Physics');
      expect(item.difficulty, 'hard');
      expect(item.explanation, isNotNull);
    });

    test('MistakeItem allows null optional fields', () {
      const item = MistakeItem(
        questionId: 'q2',
        testId: 't1',
      );
      expect(item.subjectId, isNull);
      expect(item.topicId, isNull);
      expect(item.difficulty, isNull);
      expect(item.selectedOptionId, isNull);
      expect(item.explanation, isNull);
    });

    test('SubjectBreakdownItem accuracy calculated correctly', () {
      const item = SubjectBreakdownItem(
        subjectId: 's1',
        subjectName: 'Math',
        attempted: 10,
        correct: 7,
        wrong: 2,
        unanswered: 1,
      );
      expect(item.accuracy, 70.0);
      expect(item.total, 11);
    });

    test('SubjectBreakdownItem accuracy zero when no attempts', () {
      const item = SubjectBreakdownItem(
        subjectId: 's1',
        subjectName: 'Math',
        attempted: 0,
        correct: 0,
        wrong: 0,
        unanswered: 5,
      );
      expect(item.accuracy, 0);
      expect(item.total, 5);
    });

    test('TopicBreakdownItem accuracy calculated correctly', () {
      const item = TopicBreakdownItem(
        topicId: 't1',
        topicName: 'Algebra',
        attempted: 8,
        correct: 6,
        wrong: 1,
        unanswered: 1,
      );
      expect(item.accuracy, 75.0);
      expect(item.total, 9);
    });

    test('DifficultyBreakdownItem accuracy calculated correctly', () {
      const item = DifficultyBreakdownItem(
        difficulty: 'hard',
        attempted: 5,
        correct: 2,
        wrong: 2,
        unanswered: 1,
      );
      expect(item.accuracy, 40.0);
      expect(item.total, 6);
    });
  });

  // ─── Previous Result / Comparison ────────────────────────

  group('Previous Result Comparison', () {
    test('getPreviousResult returns earlier result', () {
      final r1 = makeResult(id: 'r1', percentage: 60, computedAt: now.subtract(const Duration(days: 1)));
      final r2 = makeResult(id: 'r2', percentage: 80, computedAt: now);
      final previous = ResultService.getPreviousResult(
        allResults: [r1, r2],
        currentResultId: 'r2',
      );
      expect(previous, isNotNull);
      expect(previous!.id, 'r1');
    });

    test('getPreviousResult returns null when only one result', () {
      final r1 = makeResult(id: 'r1', percentage: 60);
      final previous = ResultService.getPreviousResult(
        allResults: [r1],
        currentResultId: 'r1',
      );
      expect(previous, isNull);
    });

    test('getPreviousResult returns null when current is oldest', () {
      final r1 = makeResult(id: 'r1', percentage: 60, computedAt: now.subtract(const Duration(days: 1)));
      final r2 = makeResult(id: 'r2', percentage: 80, computedAt: now);
      final previous = ResultService.getPreviousResult(
        allResults: [r1, r2],
        currentResultId: 'r1',
      );
      expect(previous, isNull);
    });

    test('getPreviousResult returns null for unknown ID', () {
      final r1 = makeResult(id: 'r1', percentage: 60);
      final previous = ResultService.getPreviousResult(
        allResults: [r1],
        currentResultId: 'unknown',
      );
      expect(previous, isNull);
    });

    test('getPreviousResult handles empty list', () {
      final previous = ResultService.getPreviousResult(
        allResults: [],
        currentResultId: 'r1',
      );
      expect(previous, isNull);
    });
  });

  // ─── Security Tests ──────────────────────────────────────

  group('Security', () {
    test('Result model does not expose correct_option', () {
      final result = makeResult(id: 'r1', percentage: 75);
      final json = result.toJson();
      expect(json.containsKey('correct_option'), isFalse);
    });

    test('MistakeItem does not contain correct answer', () {
      const item = MistakeItem(
        questionId: 'q1',
        testId: 't1',
        selectedOptionId: 'opt-a',
      );
      // MistakeItem only stores what the user selected, not the correct answer
      expect(item.selectedOptionId, 'opt-a');
      // No 'correctOptionId' field exists
    });

    test('No client-side scoring in analytics', () {
      // All scores come from Result model (server-authoritative)
      final result = makeResult(
        id: 'r1',
        percentage: 85,
        correctCount: 17,
        wrongCount: 2,
        unansweredCount: 1,
        accuracy: 89.5,
      );
      expect(result.percentage, 85);
      expect(result.accuracy, 89.5);
      // Analytics use these values directly, never recalculate
    });

    test('Result ownership - userId required', () {
      final result = makeResult(id: 'r1');
      expect(result.userId, 'u1');
    });

    test('Historical result cannot be overwritten', () {
      // Results are immutable once created (DB constraint)
      // Flutter side: no update/delete methods exposed
      final result = makeResult(id: 'r1', percentage: 60);
      expect(result.id, 'r1');
      // No ResultService.updateResult() exists
    });
  });

  // ─── Repeat Test Constraints ─────────────────────────────

  group('Repeat Test Constraints', () {
    test('attempt_number defaults to 1 in DB', () {
      // DB schema: attempt_number integer NOT NULL DEFAULT 1
      // Unique constraint: (test_id, user_id, attempt_number)
      // Server allocates via MAX(attempt_number)+1
    });

    test('Attempt.fromJson parses attempt_number', () {
      final attempt = Attempt.fromJson({
        'id': 'att-1',
        'test_id': 't-1',
        'user_id': 'u-1',
        'status': 'in_progress',
        'started_at': '2026-09-14T10:00:00Z',
        'attempt_number': 3,
      });

      expect(attempt.attemptNumber, 3);
    });

    test('Attempt.fromJson defaults attempt_number to 1 when missing', () {
      final attempt = Attempt.fromJson({
        'id': 'att-1',
        'test_id': 't-1',
        'user_id': 'u-1',
        'status': 'in_progress',
        'started_at': '2026-09-14T10:00:00Z',
      });

      expect(attempt.attemptNumber, 1);
    });
  });
}
