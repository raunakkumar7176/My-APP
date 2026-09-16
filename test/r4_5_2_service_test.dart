import 'package:flutter_test/flutter_test.dart';

import 'package:my_praperation/core/models/question.dart';
import 'package:my_praperation/core/services/question_service.dart';
import 'package:my_praperation/core/services/test_service.dart';

void main() {
  group('TestService.buildCreateTestParams', () {
    test('includes required p_title', () {
      final params = TestService.buildCreateTestParams(title: 'Math Quiz');
      expect(params['p_title'], 'Math Quiz');
    });

    test('includes non-null optional parameters', () {
      final params = TestService.buildCreateTestParams(
        title: 'Math Quiz',
        description: 'Algebra basics',
        durationSec: 1800,
        marksPerQuestion: 2.0,
        negativeMarks: 0.5,
        testMode: 'timed',
        creationMethod: 'manual',
        groupId: 'g-1',
        startsAt: DateTime(2026, 1, 1),
        endsAt: DateTime(2026, 1, 2),
        maxParticipants: 100,
        allowLateJoin: true,
        config: {'theme': 'dark'},
        settings: {'shuffle': true},
        accessCode: 'ABC123',
        joinCode: 'XYZ789',
      );

      expect(params['p_title'], 'Math Quiz');
      expect(params['p_description'], 'Algebra basics');
      expect(params['p_duration_sec'], 1800);
      expect(params['p_marks_per_question'], 2.0);
      expect(params['p_negative_marks'], 0.5);
      expect(params['p_test_mode'], 'timed');
      expect(params['p_creation_method'], 'manual');
      expect(params['p_group_id'], 'g-1');
      expect(params['p_starts_at'], DateTime(2026, 1, 1).toIso8601String());
      expect(params['p_ends_at'], DateTime(2026, 1, 2).toIso8601String());
      expect(params['p_max_participants'], 100);
      expect(params['p_allow_late_join'], true);
      expect(params['p_config'], {'theme': 'dark'});
      expect(params['p_settings'], {'shuffle': true});
      expect(params['p_access_code'], 'ABC123');
      expect(params['p_join_code'], 'XYZ789');
    });

    test('omits null optional parameters', () {
      final params = TestService.buildCreateTestParams(title: 'Simple Test');
      expect(params.length, 1);
      expect(params.containsKey('p_description'), isFalse);
      expect(params.containsKey('p_duration_sec'), isFalse);
      expect(params.containsKey('p_marks_per_question'), isFalse);
      expect(params.containsKey('p_negative_marks'), isFalse);
      expect(params.containsKey('p_test_mode'), isFalse);
      expect(params.containsKey('p_creation_method'), isFalse);
      expect(params.containsKey('p_group_id'), isFalse);
      expect(params.containsKey('p_starts_at'), isFalse);
      expect(params.containsKey('p_ends_at'), isFalse);
      expect(params.containsKey('p_max_participants'), isFalse);
      expect(params.containsKey('p_allow_late_join'), isFalse);
      expect(params.containsKey('p_config'), isFalse);
      expect(params.containsKey('p_settings'), isFalse);
      expect(params.containsKey('p_access_code'), isFalse);
      expect(params.containsKey('p_join_code'), isFalse);
    });
  });

  group('TestService.buildUpdateTestParams', () {
    test('always includes p_test_id', () {
      final params = TestService.buildUpdateTestParams(testId: 't-1');
      expect(params['p_test_id'], 't-1');
      expect(params.length, 1);
    });

    test('includes provided optional parameters', () {
      final params = TestService.buildUpdateTestParams(
        testId: 't-1',
        title: 'Updated Title',
        durationSec: 3600,
        marksPerQuestion: 3.0,
      );

      expect(params['p_test_id'], 't-1');
      expect(params['p_title'], 'Updated Title');
      expect(params['p_duration_sec'], 3600);
      expect(params['p_marks_per_question'], 3.0);
      expect(params.containsKey('p_description'), isFalse);
    });
  });

  group('TestService.buildPublishTestParams', () {
    test('returns map with p_test_id', () {
      final params = TestService.buildPublishTestParams('t-1');
      expect(params, {'p_test_id': 't-1'});
    });
  });

  group('TestService.buildAddTestSyllabusParams', () {
    test('includes p_test_id and p_syllabus_node_id', () {
      final params = TestService.buildAddTestSyllabusParams(
        testId: 't-1',
        syllabusNodeId: 'n-1',
      );
      expect(params['p_test_id'], 't-1');
      expect(params['p_syllabus_node_id'], 'n-1');
      expect(params.containsKey('p_material_ids'), isFalse);
    });

    test('includes p_material_ids when provided', () {
      final params = TestService.buildAddTestSyllabusParams(
        testId: 't-1',
        syllabusNodeId: 'n-1',
        materialIds: ['m-1', 'm-2'],
      );
      expect(params['p_material_ids'], ['m-1', 'm-2']);
    });
  });

  group('TestService.buildRemoveTestSyllabusParams', () {
    test('returns map with p_test_id and p_syllabus_node_id', () {
      final params = TestService.buildRemoveTestSyllabusParams(
        testId: 't-1',
        syllabusNodeId: 'n-1',
      );
      expect(params, {
        'p_test_id': 't-1',
        'p_syllabus_node_id': 'n-1',
      });
    });
  });

  group('QuestionService.questionTypeToRpc', () {
    test('mcqSingle maps to "mcq"', () {
      expect(QuestionService.questionTypeToRpc(QuestionType.mcqSingle), 'mcq');
    });

    test('mcqMultiple maps to "mcq"', () {
      expect(
          QuestionService.questionTypeToRpc(QuestionType.mcqMultiple), 'mcq');
    });

    test('trueFalse maps to "tf"', () {
      expect(QuestionService.questionTypeToRpc(QuestionType.trueFalse), 'tf');
    });

    test('integer maps to "num"', () {
      expect(QuestionService.questionTypeToRpc(QuestionType.integer), 'num');
    });

    test('shortAnswer maps to "short"', () {
      expect(
          QuestionService.questionTypeToRpc(QuestionType.shortAnswer), 'short');
    });

    test('null defaults to "mcq"', () {
      expect(QuestionService.questionTypeToRpc(null), 'mcq');
    });

    test('unknown defaults to "mcq"', () {
      expect(QuestionService.questionTypeToRpc(QuestionType.unknown), 'mcq');
    });
  });

  group('QuestionService.buildCreateQuestionParams', () {
    test('includes required p_test_id and p_question', () {
      final params = QuestionService.buildCreateQuestionParams(
        testId: 't-1',
        questionText: 'What is 2+2?',
      );
      expect(params['p_test_id'], 't-1');
      expect(params['p_question'], 'What is 2+2?');
    });

    test('maps questionType to RPC value', () {
      final params = QuestionService.buildCreateQuestionParams(
        testId: 't-1',
        questionText: 'Q',
        questionType: QuestionType.mcqSingle,
      );
      expect(params['p_question_type'], 'mcq');
    });

    test('maps trueFalse to "tf"', () {
      final params = QuestionService.buildCreateQuestionParams(
        testId: 't-1',
        questionText: 'Q',
        questionType: QuestionType.trueFalse,
      );
      expect(params['p_question_type'], 'tf');
    });

    test('maps integer to "num"', () {
      final params = QuestionService.buildCreateQuestionParams(
        testId: 't-1',
        questionText: 'Q',
        questionType: QuestionType.integer,
      );
      expect(params['p_question_type'], 'num');
    });

    test('maps shortAnswer to "short"', () {
      final params = QuestionService.buildCreateQuestionParams(
        testId: 't-1',
        questionText: 'Q',
        questionType: QuestionType.shortAnswer,
      );
      expect(params['p_question_type'], 'short');
    });

    test('includes non-null optional parameters', () {
      final params = QuestionService.buildCreateQuestionParams(
        testId: 't-1',
        questionText: 'Q',
        questionType: QuestionType.mcqMultiple,
        questionTextTranslated: 'Translated Q',
        options: [
          {'id': '1', 'text': 'A'},
        ],
        correctOption: 0,
        explanation: 'Because',
        subjectId: 's-1',
        topicNodeId: 'tn-1',
        difficulty: 'hard',
        marks: 5,
        negativeMarks: 1.0,
        questionStatus: 'pending_review',
        questionImage: 'img.png',
        questionImageDark: 'img_dark.png',
        metadata: {'key': 'val'},
        language: 'en',
        sourceBatch: 'batch-1',
        bankId: 'bank-1',
      );

      expect(params['p_question_type'], 'mcq');
      expect(params['p_question_text_translated'], 'Translated Q');
      expect(params['p_options'], isA<List>());
      expect(params['p_correct_option'], 0);
      expect(params['p_explanation'], 'Because');
      expect(params['p_subject_id'], 's-1');
      expect(params['p_topic_node_id'], 'tn-1');
      expect(params['p_difficulty'], 'hard');
      expect(params['p_marks'], 5);
      expect(params['p_negative_marks'], 1.0);
      expect(params['p_status'], 'pending_review');
      expect(params['p_question_image'], 'img.png');
      expect(params['p_question_image_dark'], 'img_dark.png');
      expect(params['p_metadata'], {'key': 'val'});
      expect(params['p_language'], 'en');
      expect(params['p_source_batch'], 'batch-1');
      expect(params['p_bank_id'], 'bank-1');
    });

    test('omits null optional parameters', () {
      final params = QuestionService.buildCreateQuestionParams(
        testId: 't-1',
        questionText: 'Q',
      );

      expect(params.length, 2);
      expect(params.containsKey('p_question_type'), isFalse);
      expect(params.containsKey('p_options'), isFalse);
      expect(params.containsKey('p_correct_option'), isFalse);
      expect(params.containsKey('p_explanation'), isFalse);
      expect(params.containsKey('p_subject_id'), isFalse);
      expect(params.containsKey('p_difficulty'), isFalse);
      expect(params.containsKey('p_marks'), isFalse);
    });
  });

  group('QuestionService.buildUpdateQuestionParams', () {
    test('always includes p_question_id', () {
      final params =
          QuestionService.buildUpdateQuestionParams(questionId: 'q-1');
      expect(params['p_question_id'], 'q-1');
      expect(params.length, 1);
    });

    test('includes provided optional parameters', () {
      final params = QuestionService.buildUpdateQuestionParams(
        questionId: 'q-1',
        questionText: 'Updated Q',
        questionType: QuestionType.trueFalse,
        marks: 3,
      );
      expect(params['p_question_id'], 'q-1');
      expect(params['p_question'], 'Updated Q');
      expect(params['p_question_type'], 'tf');
      expect(params['p_marks'], 3);
      expect(params.containsKey('p_description'), isFalse);
    });
  });

  group('QuestionService.buildDeleteQuestionParams', () {
    test('returns map with p_question_id', () {
      final params = QuestionService.buildDeleteQuestionParams('q-1');
      expect(params, {'p_question_id': 'q-1'});
    });
  });

  group('TestService.mapErrorMessage', () {
    test('permission denied maps to permission message', () {
      expect(
        TestService.mapErrorMessage('permission denied for table tests'),
        'You do not have permission to perform this action.',
      );
    });

    test('not found maps to not found message', () {
      expect(
        TestService.mapErrorMessage('row not found'),
        'Test not found.',
      );
    });

    test('network timeout maps to network message', () {
      expect(
        TestService.mapErrorMessage('network timeout occurred'),
        'Network error. Please check your connection and try again.',
      );
    });

    test('unknown error maps to generic message', () {
      expect(
        TestService.mapErrorMessage('some internal error'),
        'Something went wrong. Please try again.',
      );
    });
  });

  group('QuestionService.mapErrorMessage', () {
    test('permission denied maps to access message', () {
      expect(
        QuestionService.mapErrorMessage('permission denied'),
        'You do not have access to these questions.',
      );
    });

    test('not found maps to not found message', () {
      expect(
        QuestionService.mapErrorMessage('not found'),
        'Questions not found for this test.',
      );
    });

    test('network error maps to network message', () {
      expect(
        QuestionService.mapErrorMessage('network error'),
        'Network error. Please check your connection and try again.',
      );
    });

    test('unknown error maps to generic message', () {
      expect(
        QuestionService.mapErrorMessage('some internal error'),
        'Failed to load questions. Please try again.',
      );
    });
  });

  group('Question parsing - correct_option not exposed', () {
    test('Question.fromJson excludes correct_option from toJson', () {
      final json = {
        'id': 'q-1',
        'test_id': 't-1',
        'question': 'What is 2+2?',
        'options': [
          {'id': '1', 'text': '3'},
          {'id': '2', 'text': '4'},
        ],
        'difficulty': 'easy',
        'marks': 1,
        'status': 'active',
        'question_type': 'mcq',
        'correct_option': 1,
      };

      final q = Question.fromJson(json);
      expect(q.id, 'q-1');
      expect(q.question, 'What is 2+2?');
      expect(q.options?.length, 2);

      final serialized = q.toJson();
      expect(serialized.containsKey('correct_option'), isFalse,
          reason:
              'correct_option must not be exposed in model serialization');
    });

    test('QuestionType parser handles live RPC values', () {
      expect(
        Question.fromJson({
          'id': '1',
          'test_id': 't',
          'question': 'q',
          'difficulty': 'easy',
          'marks': 1,
          'status': 'active',
          'question_type': 'mcq',
        }).questionType,
        QuestionType.mcqSingle,
      );

      expect(
        Question.fromJson({
          'id': '1',
          'test_id': 't',
          'question': 'q',
          'difficulty': 'easy',
          'marks': 1,
          'status': 'active',
          'question_type': 'tf',
        }).questionType,
        QuestionType.trueFalse,
      );

      expect(
        Question.fromJson({
          'id': '1',
          'test_id': 't',
          'question': 'q',
          'difficulty': 'easy',
          'marks': 1,
          'status': 'active',
          'question_type': 'num',
        }).questionType,
        QuestionType.integer,
      );

      expect(
        Question.fromJson({
          'id': '1',
          'test_id': 't',
          'question': 'q',
          'difficulty': 'easy',
          'marks': 1,
          'status': 'active',
          'question_type': 'short',
        }).questionType,
        QuestionType.shortAnswer,
      );
    });
  });
}
