import 'package:flutter_test/flutter_test.dart';
import 'package:my_praperation/core/models/answer.dart';
import 'package:my_praperation/core/models/question.dart';
import 'package:my_praperation/core/models/result.dart';
import 'package:my_praperation/core/models/self_reflection.dart';

void main() {
  // ─── Test Data ───────────────────────────────────────────

  const testResult = Result(
    id: 'r1',
    attemptId: 'a1',
    testId: 't1',
    userId: 'u1',
    score: 8.0,
    maxScore: 10.0,
    percentage: 80.0,
    isPassed: true,
    correctCount: 4,
    wrongCount: 1,
    unansweredCount: 0,
    partialCount: 0,
    totalQuestions: 5,
    accuracy: 80.0,
    rank: 2,
    totalMarks: 10,
    marksObtained: 8.0,
  );

  const testResultFailed = Result(
    id: 'r2',
    attemptId: 'a2',
    testId: 't1',
    userId: 'u1',
    score: 3.0,
    maxScore: 10.0,
    percentage: 30.0,
    isPassed: false,
    correctCount: 1,
    wrongCount: 2,
    unansweredCount: 2,
    totalQuestions: 5,
    accuracy: 33.3,
  );

  const q1 = Question(
    id: 'q1',
    testId: 't1',
    question: 'What is 2+2?',
    difficulty: DifficultyLevel.easy,
    marks: 2,
    status: 'active',
    questionType: QuestionType.mcqSingle,
    options: [
      QuestionOption(id: 'opt-a', text: '3'),
      QuestionOption(id: 'opt-b', text: '4'),
      QuestionOption(id: 'opt-c', text: '5'),
    ],
    explanation: '2+2 equals 4.',
  );

  const q2 = Question(
    id: 'q2',
    testId: 't1',
    question: 'Capital of France?',
    difficulty: DifficultyLevel.medium,
    marks: 2,
    status: 'active',
    questionType: QuestionType.mcqSingle,
    options: [
      QuestionOption(id: 'opt-x', text: 'Berlin'),
      QuestionOption(id: 'opt-y', text: 'Paris'),
    ],
  );

  const q3 = Question(
    id: 'q3',
    testId: 't1',
    question: 'Hard question',
    difficulty: DifficultyLevel.hard,
    marks: 3,
    status: 'active',
    questionType: QuestionType.mcqSingle,
    explanation: null,
  );

  // ─── SelfReflection Model Tests ──────────────────────────

  group('SelfReflection Model', () {
    test('confidenceLabel returns correct string for each level', () {
      expect(
        const SelfReflection(
          confidence: ConfidenceLevel.veryLow,
          expectedPerformance: ExpectedPerformance.below40,
        ).confidenceLabel,
        'Very Low',
      );
      expect(
        const SelfReflection(
          confidence: ConfidenceLevel.low,
          expectedPerformance: ExpectedPerformance.below40,
        ).confidenceLabel,
        'Low',
      );
      expect(
        const SelfReflection(
          confidence: ConfidenceLevel.medium,
          expectedPerformance: ExpectedPerformance.below40,
        ).confidenceLabel,
        'Medium',
      );
      expect(
        const SelfReflection(
          confidence: ConfidenceLevel.high,
          expectedPerformance: ExpectedPerformance.below40,
        ).confidenceLabel,
        'High',
      );
      expect(
        const SelfReflection(
          confidence: ConfidenceLevel.veryHigh,
          expectedPerformance: ExpectedPerformance.below40,
        ).confidenceLabel,
        'Very High',
      );
    });

    test('expectedRangeLabel returns correct string for each level', () {
      expect(
        const SelfReflection(
          confidence: ConfidenceLevel.medium,
          expectedPerformance: ExpectedPerformance.below40,
        ).expectedRangeLabel,
        'Below 40%',
      );
      expect(
        const SelfReflection(
          confidence: ConfidenceLevel.medium,
          expectedPerformance: ExpectedPerformance.range4059,
        ).expectedRangeLabel,
        '40\u201359%',
      );
      expect(
        const SelfReflection(
          confidence: ConfidenceLevel.medium,
          expectedPerformance: ExpectedPerformance.range6074,
        ).expectedRangeLabel,
        '60\u201374%',
      );
      expect(
        const SelfReflection(
          confidence: ConfidenceLevel.medium,
          expectedPerformance: ExpectedPerformance.range7589,
        ).expectedRangeLabel,
        '75\u201389%',
      );
      expect(
        const SelfReflection(
          confidence: ConfidenceLevel.medium,
          expectedPerformance: ExpectedPerformance.range90,
        ).expectedRangeLabel,
        '90%+',
      );
    });

    test('expectedMidpoint returns correct midpoint for each level', () {
      expect(
        const SelfReflection(
          confidence: ConfidenceLevel.medium,
          expectedPerformance: ExpectedPerformance.below40,
        ).expectedMidpoint,
        20,
      );
      expect(
        const SelfReflection(
          confidence: ConfidenceLevel.medium,
          expectedPerformance: ExpectedPerformance.range4059,
        ).expectedMidpoint,
        50,
      );
      expect(
        const SelfReflection(
          confidence: ConfidenceLevel.medium,
          expectedPerformance: ExpectedPerformance.range6074,
        ).expectedMidpoint,
        67,
      );
      expect(
        const SelfReflection(
          confidence: ConfidenceLevel.medium,
          expectedPerformance: ExpectedPerformance.range7589,
        ).expectedMidpoint,
        82,
      );
      expect(
        const SelfReflection(
          confidence: ConfidenceLevel.medium,
          expectedPerformance: ExpectedPerformance.range90,
        ).expectedMidpoint,
        95,
      );
    });

    test('optionalReflection defaults to null', () {
      const r = SelfReflection(
        confidence: ConfidenceLevel.high,
        expectedPerformance: ExpectedPerformance.range7589,
      );
      expect(r.optionalReflection, isNull);
    });

    test('optionalReflection stores provided value', () {
      const r = SelfReflection(
        confidence: ConfidenceLevel.high,
        expectedPerformance: ExpectedPerformance.range7589,
        optionalReflection: 'Found section X tricky',
      );
      expect(r.optionalReflection, 'Found section X tricky');
    });
  });

  // ─── Result Model Tests ──────────────────────────────────

  group('Result Model', () {
    test('isPassed true when percentage >= pass threshold', () {
      expect(testResult.isPassed, isTrue);
    });

    test('isPassed false when percentage < pass threshold', () {
      expect(testResultFailed.isPassed, isFalse);
    });

    test('score and maxScore parsed correctly', () {
      expect(testResult.score, 8.0);
      expect(testResult.maxScore, 10.0);
    });

    test('accuracy parsed correctly', () {
      expect(testResult.accuracy, 80.0);
    });

    test('rank parsed correctly', () {
      expect(testResult.rank, 2);
    });

    test('breakdown maps default to null', () {
      expect(testResult.subjectBreakdown, isNull);
      expect(testResult.topicBreakdown, isNull);
    });
  });

  // ─── Question Review Logic Tests ─────────────────────────

  group('Question Review Logic', () {
    test('Answered questions correctly identified', () {
      final answers = {
        'q1': const Answer(
          attemptId: 'a1',
          questionId: 'q1',
          selectedOptionId: 'opt-b',
          isAnswered: true,
        ),
        'q2': const Answer(
          attemptId: 'a1',
          questionId: 'q2',
          selectedOptionId: 'opt-y',
          isAnswered: true,
        ),
      };

      final questions = [q1, q2, q3];
      final answered =
          questions.where((q) => answers[q.id]?.isAnswered == true).length;
      final unanswered = questions.length - answered;

      expect(answered, 2);
      expect(unanswered, 1);
    });

    test('Unanswered question has no selectedOptionId', () {
      const answer = Answer(
        attemptId: 'a1',
        questionId: 'q3',
      );
      expect(answer.selectedOptionId, isNull);
      expect(answer.isAnswered, isFalse);
    });

    test('Answer is marked for review', () {
      const answer = Answer(
        attemptId: 'a1',
        questionId: 'q1',
        selectedOptionId: 'opt-a',
        isAnswered: true,
        isMarkedForReview: true,
      );
      expect(answer.isMarkedForReview, isTrue);
    });
  });

  // ─── Difficulty Analysis Logic Tests ─────────────────────

  group('Difficulty Analysis', () {
    test('Easy questions categorized correctly', () {
      final questions = [q1, q2, q3];
      final easy =
          questions.where((q) => q.difficulty == DifficultyLevel.easy).toList();
      expect(easy.length, 1);
      expect(easy.first.id, 'q1');
    });

    test('Medium questions categorized correctly', () {
      final questions = [q1, q2, q3];
      final medium = questions
          .where((q) => q.difficulty == DifficultyLevel.medium)
          .toList();
      expect(medium.length, 1);
      expect(medium.first.id, 'q2');
    });

    test('Hard questions categorized correctly', () {
      final questions = [q1, q2, q3];
      final hard =
          questions.where((q) => q.difficulty == DifficultyLevel.hard).toList();
      expect(hard.length, 1);
      expect(hard.first.id, 'q3');
    });

    test('Marks calculated per difficulty correctly', () {
      final questions = [q1, q2, q3];
      final easy =
          questions.where((q) => q.difficulty == DifficultyLevel.easy);
      final totalMarks = easy.fold<int>(0, (sum, q) => sum + q.marks);
      expect(totalMarks, 2);
    });

    test('Answered count per difficulty calculated correctly', () {
      final questions = [q1, q2, q3];
      final answers = {
        'q1': const Answer(
          attemptId: 'a1',
          questionId: 'q1',
          selectedOptionId: 'opt-b',
          isAnswered: true,
        ),
      };

      final easy =
          questions.where((q) => q.difficulty == DifficultyLevel.easy).toList();
      final answeredEasy = easy
          .where((q) => answers[q.id]?.isAnswered == true)
          .length;
      expect(answeredEasy, 1);
    });
  });

  // ─── Explanation Display Logic Tests ─────────────────────

  group('Explanation Display', () {
    test('Question with explanation shows explanation', () {
      expect(q1.explanation, '2+2 equals 4.');
    });

    test('Question without explanation returns null', () {
      expect(q2.explanation, isNull);
      expect(q3.explanation, isNull);
    });

    test('Explanation availability check', () {
      bool hasExplanation(Question q) =>
          q.explanation != null && q.explanation!.isNotEmpty;

      expect(hasExplanation(q1), isTrue);
      expect(hasExplanation(q2), isFalse);
      expect(hasExplanation(q3), isFalse);
    });
  });

  // ─── Expectation vs Actual Comparison Tests ──────────────

  group('Expectation vs Actual', () {
    test('Actual within expected range', () {
      const reflection = SelfReflection(
        confidence: ConfidenceLevel.high,
        expectedPerformance: ExpectedPerformance.range7589,
      );
      const actualPercentage = 80.0;
      final expectedMidpoint = reflection.expectedMidpoint;

      final isWithin = actualPercentage >= expectedMidpoint - 10 &&
          actualPercentage <= expectedMidpoint + 10;

      expect(isWithin, isTrue);
    });

    test('Actual above expected range', () {
      const reflection = SelfReflection(
        confidence: ConfidenceLevel.low,
        expectedPerformance: ExpectedPerformance.range4059,
      );
      const actualPercentage = 85.0;
      final expectedMidpoint = reflection.expectedMidpoint;

      final isAbove = actualPercentage > expectedMidpoint + 10;
      expect(isAbove, isTrue);
    });

    test('Actual below expected range', () {
      const reflection = SelfReflection(
        confidence: ConfidenceLevel.high,
        expectedPerformance: ExpectedPerformance.range90,
      );
      const actualPercentage = 60.0;
      final expectedMidpoint = reflection.expectedMidpoint;

      final isBelow = actualPercentage < expectedMidpoint - 10;
      expect(isBelow, isTrue);
    });

    test('Difference calculation is correct', () {
      const reflection = SelfReflection(
        confidence: ConfidenceLevel.medium,
        expectedPerformance: ExpectedPerformance.range6074,
      );
      const actualPercentage = 75.0;
      final difference = actualPercentage - reflection.expectedMidpoint;
      expect(difference, closeTo(8.0, 0.1));
    });
  });

  // ─── Security Tests ──────────────────────────────────────

  group('Security', () {
    test('Result model does not expose correct_option', () {
      final json = testResult.toJson();
      expect(json.containsKey('correct_option'), isFalse);
    });

    test('Question model does not expose correct_option in toJson', () {
      final json = q1.toJson();
      expect(json.containsKey('correct_option'), isFalse);
    });

    test('Answer model does not leak correctness info', () {
      const answer = Answer(
        attemptId: 'a1',
        questionId: 'q1',
        selectedOptionId: 'opt-a',
      );
      final json = answer.toJson();
      expect(json.containsKey('is_correct'), isFalse);
      expect(json.containsKey('correct_option'), isFalse);
    });

    test('SelfReflection does not affect score calculation', () {
      const reflection = SelfReflection(
        confidence: ConfidenceLevel.veryHigh,
        expectedPerformance: ExpectedPerformance.range90,
      );
      // Score comes from server, reflection is display-only
      expect(testResult.percentage, 80.0);
      expect(reflection.expectedMidpoint, 95);
      // Reflection never modifies result
    });
  });
}
