import 'package:flutter_test/flutter_test.dart';
import 'package:my_praperation/core/services/question_service.dart';

void main() {
  group('QuestionService.mapErrorMessage', () {
    test('maps permission denied error', () {
      expect(
        QuestionService.mapErrorMessage('permission denied for table questions'),
        'You do not have access to these questions.',
      );
    });

    test('maps row-level security error', () {
      expect(
        QuestionService.mapErrorMessage(
            'new row violates row-level security policy'),
        'You do not have permission to access these questions.',
      );
    });

    test('maps not found error', () {
      expect(
        QuestionService.mapErrorMessage('record not found'),
        'Questions not found for this test.',
      );
    });

    test('maps network error', () {
      expect(
        QuestionService.mapErrorMessage('network timeout'),
        'Network error. Please check your connection and try again.',
      );
    });

    test('maps unknown error to generic message', () {
      expect(
        QuestionService.mapErrorMessage('something unexpected happened'),
        'Failed to load questions. Please try again.',
      );
    });
  });

  group('QuestionService.buildUpdateQuestionParams', () {
    test('includes p_question_id always', () {
      final params = QuestionService.buildUpdateQuestionParams(
        questionId: 'q-1',
      );
      expect(params['p_question_id'], 'q-1');
    });

    test('includes p_status when questionStatus is provided', () {
      final params = QuestionService.buildUpdateQuestionParams(
        questionId: 'q-1',
        questionStatus: 'approved',
      );
      expect(params['p_status'], 'approved');
    });

    test('excludes p_status when questionStatus is null', () {
      final params = QuestionService.buildUpdateQuestionParams(
        questionId: 'q-1',
      );
      expect(params.containsKey('p_status'), isFalse);
    });

    test('includes optional fields when provided', () {
      final params = QuestionService.buildUpdateQuestionParams(
        questionId: 'q-1',
        questionText: 'Updated?',
        marks: 5,
        negativeMarks: 0.25,
        difficulty: 'hard',
      );
      expect(params['p_question'], 'Updated?');
      expect(params['p_marks'], 5);
      expect(params['p_negative_marks'], 0.25);
      expect(params['p_difficulty'], 'hard');
    });
  });

  group('QuestionService.buildCreateQuestionParams', () {
    test('includes p_test_id and p_question', () {
      final params = QuestionService.buildCreateQuestionParams(
        testId: 't-1',
        questionText: 'What is 2+2?',
      );
      expect(params['p_test_id'], 't-1');
      expect(params['p_question'], 'What is 2+2?');
    });
  });

  group('QuestionService.questionTypeToRpc', () {
    test('maps mcqSingle to mcq', () {
      expect(QuestionService.questionTypeToRpc(null), 'mcq');
    });
  });

  group('QuestionService.buildDeleteQuestionParams', () {
    test('includes p_question_id', () {
      final params = QuestionService.buildDeleteQuestionParams('q-1');
      expect(params['p_question_id'], 'q-1');
    });
  });
}
