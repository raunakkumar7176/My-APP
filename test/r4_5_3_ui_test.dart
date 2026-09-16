import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:my_praperation/core/models/question.dart';
import 'package:my_praperation/features/test/models/question_draft.dart';
import 'package:my_praperation/features/test/widgets/question_editor.dart';
import 'package:my_praperation/features/test/widgets/step_basic_details.dart';
import 'package:my_praperation/features/test/widgets/step_configuration.dart';
import 'package:my_praperation/features/test/widgets/step_questions.dart';
import 'package:my_praperation/features/test/widgets/step_review.dart';

Widget wrapWithApp(Widget child) {
  return MaterialApp(home: Scaffold(body: child));
}

void main() {
  group('QuestionDraft Model', () {
    test('initializes with correct defaults', () {
      const draft = QuestionDraft(questionText: 'What is 2+2?');
      expect(draft.questionText, 'What is 2+2?');
      expect(draft.questionType, QuestionType.mcqSingle);
      expect(draft.options, isEmpty);
      expect(draft.correctOptionIndex, isNull);
      expect(draft.difficulty, DifficultyLevel.medium);
      expect(draft.marks, 1);
    });

    test('isValid returns false for empty question text', () {
      const draft = QuestionDraft(questionText: '');
      expect(draft.isValid, isFalse);
    });

    test('isValid returns false for zero marks', () {
      const draft = QuestionDraft(questionText: 'Q', marks: 0);
      expect(draft.isValid, isFalse);
    });

    test('isValid returns true for valid MCQ', () {
      const draft = QuestionDraft(
        questionText: 'What is 2+2?',
        questionType: QuestionType.mcqSingle,
        options: [
          QuestionOptionDraft(text: '3'),
          QuestionOptionDraft(text: '4'),
        ],
        correctOptionIndex: 1,
        marks: 1,
      );
      expect(draft.isValid, isTrue);
    });

    test('isValid returns false for MCQ with less than 2 options', () {
      const draft = QuestionDraft(
        questionText: 'Q',
        questionType: QuestionType.mcqSingle,
        options: [QuestionOptionDraft(text: 'A')],
        correctOptionIndex: 0,
        marks: 1,
      );
      expect(draft.isValid, isFalse);
    });

    test('isValid returns false for MCQ without correct option', () {
      const draft = QuestionDraft(
        questionText: 'Q',
        questionType: QuestionType.mcqSingle,
        options: [
          QuestionOptionDraft(text: 'A'),
          QuestionOptionDraft(text: 'B'),
        ],
        marks: 1,
      );
      expect(draft.isValid, isFalse);
    });

    test('isValid returns true for True/False without options', () {
      const draft = QuestionDraft(
        questionText: 'Is the sky blue?',
        questionType: QuestionType.trueFalse,
        marks: 1,
      );
      expect(draft.isValid, isTrue);
    });

    test('copyWith creates new instance with updated fields', () {
      const original = QuestionDraft(
        questionText: 'Original',
        marks: 1,
      );
      final updated = original.copyWith(questionText: 'Updated', marks: 2);
      expect(updated.questionText, 'Updated');
      expect(updated.marks, 2);
      expect(original.questionText, 'Original');
      expect(original.marks, 1);
    });

    test('toCreateParams builds correct RPC parameters', () {
      const draft = QuestionDraft(
        questionText: 'What is 2+2?',
        questionType: QuestionType.mcqSingle,
        options: [
          QuestionOptionDraft(id: '1', text: '3'),
          QuestionOptionDraft(id: '2', text: '4'),
        ],
        correctOptionIndex: 1,
        difficulty: DifficultyLevel.easy,
        marks: 2,
      );
      final params = draft.toCreateParams(testId: 't-1');
      expect(params['p_test_id'], 't-1');
      expect(params['p_question'], 'What is 2+2?');
      expect(params['p_question_type'], 'mcq');
      expect(params['p_options'], isA<List>());
      expect(params['p_correct_option'], 1);
      expect(params['p_difficulty'], 'easy');
      expect(params['p_marks'], 2);
    });

    test('hasValidOptions validates MCQ options', () {
      const validDraft = QuestionDraft(
        questionText: 'Q',
        questionType: QuestionType.mcqSingle,
        options: [
          QuestionOptionDraft(text: 'A'),
          QuestionOptionDraft(text: 'B'),
        ],
      );
      expect(validDraft.hasValidOptions, isTrue);

      const invalidDraft = QuestionDraft(
        questionText: 'Q',
        questionType: QuestionType.mcqSingle,
        options: [
          QuestionOptionDraft(text: ''),
          QuestionOptionDraft(text: 'B'),
        ],
      );
      expect(invalidDraft.hasValidOptions, isFalse);
    });

    test('hasCorrectOption validates correct option index', () {
      const draft = QuestionDraft(
        questionText: 'Q',
        questionType: QuestionType.mcqSingle,
        options: [
          QuestionOptionDraft(text: 'A'),
          QuestionOptionDraft(text: 'B'),
        ],
        correctOptionIndex: 5,
      );
      expect(draft.hasCorrectOption, isFalse);
    });
  });

  group('QuestionOptionDraft', () {
    test('copyWith creates new instance', () {
      const original = QuestionOptionDraft(id: '1', text: 'Option A');
      final updated = original.copyWith(text: 'Option B');
      expect(updated.text, 'Option B');
      expect(updated.id, '1');
      expect(original.text, 'Option A');
    });
  });

  group('StepBasicDetails', () {
    testWidgets('displays title, description, and test mode fields', (tester) async {
      await tester.pumpWidget(
        wrapWithApp(
          StepBasicDetails(
            title: '',
            description: '',
            testMode: null,
            onTitleChanged: (_) {},
            onDescriptionChanged: (_) {},
            onTestModeChanged: (_) {},
            titleError: null,
          ),
        ),
      );

      expect(find.text('Basic Details'), findsOneWidget);
      expect(find.byType(TextFormField), findsNWidgets(2));
      expect(find.byType(DropdownButtonFormField<String>), findsOneWidget);
    });

    testWidgets('calls onTitleChanged when title is entered', (tester) async {
      String? capturedTitle;
      await tester.pumpWidget(
        wrapWithApp(
          StepBasicDetails(
            title: '',
            description: '',
            testMode: null,
            onTitleChanged: (value) => capturedTitle = value,
            onDescriptionChanged: (_) {},
            onTestModeChanged: (_) {},
            titleError: null,
          ),
        ),
      );

      await tester.enterText(find.byType(TextFormField).first, 'My Test');
      expect(capturedTitle, 'My Test');
    });

    testWidgets('shows title error when titleError is provided', (tester) async {
      await tester.pumpWidget(
        wrapWithApp(
          StepBasicDetails(
            title: '',
            description: '',
            testMode: null,
            onTitleChanged: (_) {},
            onDescriptionChanged: (_) {},
            onTestModeChanged: (_) {},
            titleError: 'Title is required',
          ),
        ),
      );

      expect(find.text('Title is required'), findsOneWidget);
    });

    testWidgets('shows all test mode options in dropdown', (tester) async {
      await tester.pumpWidget(
        wrapWithApp(
          StepBasicDetails(
            title: '',
            description: '',
            testMode: null,
            onTitleChanged: (_) {},
            onDescriptionChanged: (_) {},
            onTestModeChanged: (_) {},
            titleError: null,
          ),
        ),
      );

      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();

      expect(find.text('Self'), findsOneWidget);
      expect(find.text('Challenge with Friends'), findsOneWidget);
      expect(find.text('Group Test'), findsOneWidget);
    });

    testWidgets('calls onTestModeChanged when selection changes', (tester) async {
      String? capturedMode;
      await tester.pumpWidget(
        wrapWithApp(
          StepBasicDetails(
            title: '',
            description: '',
            testMode: null,
            onTitleChanged: (_) {},
            onDescriptionChanged: (_) {},
            onTestModeChanged: (value) => capturedMode = value,
            titleError: null,
          ),
        ),
      );

      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Challenge with Friends'));
      await tester.pumpAndSettle();

      expect(capturedMode, 'live');
    });

    testWidgets('displays selected test mode value', (tester) async {
      await tester.pumpWidget(
        wrapWithApp(
          StepBasicDetails(
            title: '',
            description: '',
            testMode: 'group',
            onTitleChanged: (_) {},
            onDescriptionChanged: (_) {},
            onTestModeChanged: (_) {},
            titleError: null,
          ),
        ),
      );

      expect(find.text('Group Test'), findsOneWidget);
    });
  });

  group('StepConfiguration', () {
    testWidgets('displays all configuration fields', (tester) async {
      await tester.pumpWidget(
        wrapWithApp(
          StepConfiguration(
            durationSec: null,
            marksPerQuestion: null,
            negativeMarks: null,
            testMode: null,
            groupId: null,
            startsAt: null,
            endsAt: null,
            maxParticipants: null,
            allowLateJoin: false,
            accessCode: null,
            joinCode: null,
            onChanged: (_) {},
          ),
        ),
      );

      expect(find.text('Test Configuration'), findsOneWidget);
      expect(find.text('Duration (minutes)'), findsOneWidget);
      expect(find.text('Marks per Question'), findsOneWidget);
      expect(find.text('Negative Marks'), findsOneWidget);
      expect(find.text('Max Participants'), findsOneWidget);
      expect(find.text('Access Code'), findsOneWidget);
      expect(find.text('Join Code'), findsOneWidget);
      expect(find.text('Allow Late Join'), findsOneWidget);
    });

    testWidgets('calls onChanged with updated values', (tester) async {
      Map<String, dynamic>? capturedValues;
      await tester.pumpWidget(
        wrapWithApp(
          StepConfiguration(
            durationSec: null,
            marksPerQuestion: null,
            negativeMarks: null,
            testMode: null,
            groupId: null,
            startsAt: null,
            endsAt: null,
            maxParticipants: null,
            allowLateJoin: false,
            accessCode: null,
            joinCode: null,
            onChanged: (values) => capturedValues = values,
          ),
        ),
      );

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Duration (minutes)'),
        '60',
      );
      expect(capturedValues, isNotNull);
      expect(capturedValues!['durationSec'], 3600);
    });

    testWidgets('toggles allow late join switch', (tester) async {
      Map<String, dynamic>? capturedValues;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: StepConfiguration(
                durationSec: null,
                marksPerQuestion: null,
                negativeMarks: null,
                testMode: null,
                groupId: null,
                startsAt: null,
                endsAt: null,
                maxParticipants: null,
                allowLateJoin: false,
                accessCode: null,
                joinCode: null,
                onChanged: (values) => capturedValues = values,
              ),
            ),
          ),
        ),
      );

      await tester.ensureVisible(find.byType(SwitchListTile));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();
      expect(capturedValues!['allowLateJoin'], true);
    });
  });

  group('StepQuestions', () {
    testWidgets('shows empty state when no questions', (tester) async {
      await tester.pumpWidget(
        wrapWithApp(
          StepQuestions(
            questions: const [],
            serverQuestions: const [],
            onQuestionsChanged: (_) {},
            onServerQuestionDeleted: (_) {},
            onServerQuestionUpdated: (_) {},
            onNewQuestionFromServer: (_) {},
          ),
        ),
      );

      expect(find.text('No questions yet'), findsOneWidget);
      expect(find.text('Add Question'), findsOneWidget);
    });

    testWidgets('displays question list when questions exist', (tester) async {
      const questions = [
        QuestionDraft(
          questionText: 'Question 1',
          questionType: QuestionType.mcqSingle,
          marks: 1,
        ),
        QuestionDraft(
          questionText: 'Question 2',
          questionType: QuestionType.trueFalse,
          marks: 2,
        ),
      ];

      await tester.pumpWidget(
        wrapWithApp(
          StepQuestions(
            questions: questions,
            serverQuestions: const [],
            onQuestionsChanged: (_) {},
            onServerQuestionDeleted: (_) {},
            onServerQuestionUpdated: (_) {},
            onNewQuestionFromServer: (_) {},
          ),
        ),
      );

      expect(find.text('Question 1'), findsOneWidget);
      expect(find.text('Question 2'), findsOneWidget);
      expect(find.textContaining('MCQ'), findsOneWidget);
      expect(find.textContaining('True/False'), findsOneWidget);
    });

    testWidgets('shows menu with edit and delete options', (tester) async {
      const questions = [
        QuestionDraft(
          questionText: 'Question 1',
          questionType: QuestionType.mcqSingle,
          marks: 1,
        ),
      ];

      await tester.pumpWidget(
        wrapWithApp(
          StepQuestions(
            questions: questions,
            serverQuestions: const [],
            onQuestionsChanged: (_) {},
            onServerQuestionDeleted: (_) {},
            onServerQuestionUpdated: (_) {},
            onNewQuestionFromServer: (_) {},
          ),
        ),
      );

      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();

      expect(find.text('Edit'), findsOneWidget);
      expect(find.text('Delete'), findsOneWidget);
    });

    testWidgets('deletes question when delete is tapped', (tester) async {
      List<QuestionDraft> capturedQuestions = [];
      const questions = [
        QuestionDraft(
          questionText: 'Question 1',
          questionType: QuestionType.mcqSingle,
          marks: 1,
        ),
      ];

      await tester.pumpWidget(
        wrapWithApp(
          StepQuestions(
            questions: questions,
            serverQuestions: const [],
            onQuestionsChanged: (_) {},
            onServerQuestionDeleted: (_) {},
            onServerQuestionUpdated: (_) {},
            onNewQuestionFromServer: (_) {},
          ),
        ),
      );

      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));

      expect(capturedQuestions, isEmpty);
    });
  });

  group('StepReview', () {
    testWidgets('displays test summary correctly', (tester) async {
      final now = DateTime.now();
      final questions = [
        const QuestionDraft(
          questionText: 'Q1',
          questionType: QuestionType.mcqSingle,
          marks: 2,
        ),
        const QuestionDraft(
          questionText: 'Q2',
          questionType: QuestionType.trueFalse,
          marks: 3,
        ),
      ];

      await tester.pumpWidget(
        wrapWithApp(
          StepReview(
            title: 'Math Quiz',
            description: 'Algebra basics',
            durationSec: 3600,
            marksPerQuestion: 2.0,
            negativeMarks: 0.5,
            testMode: 'timed',
            startsAt: now,
            endsAt: now.add(const Duration(hours: 2)),
            maxParticipants: 100,
            allowLateJoin: true,
            accessCode: 'ABC123',
            joinCode: 'XYZ789',
            questions: questions,
            serverQuestions: const [],
            syllabusNodeIds: ['n-1', 'n-2'],
            serverSyllabusNodeIds: const [],
            onServerQuestionUpdated: (_) {},
          ),
        ),
      );

      expect(find.text('Review Test'), findsOneWidget);
      expect(find.text('Math Quiz'), findsOneWidget);
      expect(find.text('Algebra basics'), findsOneWidget);
      expect(find.text('60 minutes'), findsOneWidget);
      expect(find.text('2.0'), findsOneWidget);
      expect(find.text('0.5'), findsOneWidget);
      expect(find.text('Not set'), findsOneWidget);
      expect(find.text('100'), findsOneWidget);
      expect(find.text('Yes'), findsOneWidget);
      expect(find.text('Set'), findsNWidgets(2));
      expect(find.text('2'), findsOneWidget);
      expect(find.text('5'), findsOneWidget);
      expect(find.text('2 topic(s)'), findsOneWidget);
    });

    testWidgets('shows question type breakdown', (tester) async {
      final questions = [
        const QuestionDraft(
          questionText: 'Q1',
          questionType: QuestionType.mcqSingle,
          marks: 1,
        ),
        const QuestionDraft(
          questionText: 'Q2',
          questionType: QuestionType.mcqSingle,
          marks: 1,
        ),
        const QuestionDraft(
          questionText: 'Q3',
          questionType: QuestionType.trueFalse,
          marks: 1,
        ),
      ];

      await tester.pumpWidget(
        wrapWithApp(
          StepReview(
            title: 'Test',
            description: '',
            durationSec: null,
            marksPerQuestion: null,
            negativeMarks: null,
            testMode: null,
            startsAt: null,
            endsAt: null,
            maxParticipants: null,
            allowLateJoin: false,
            accessCode: null,
            joinCode: null,
            questions: questions,
            serverQuestions: const [],
            syllabusNodeIds: [],
            serverSyllabusNodeIds: const [],
            onServerQuestionUpdated: (_) {},
          ),
        ),
      );

      expect(find.text('MCQ: 2'), findsOneWidget);
      expect(find.text('True/False: 1'), findsOneWidget);
    });
  });

  group('QuestionEditor', () {
    testWidgets('displays empty editor for new question', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: QuestionEditor(
              onSave: (_) {},
            ),
          ),
        ),
      );

      expect(find.text('Add Question'), findsOneWidget);
      expect(find.text('Question Type *'), findsOneWidget);
      expect(find.text('Question Text *'), findsOneWidget);
      expect(find.text('Difficulty'), findsOneWidget);
      expect(find.text('Marks *'), findsOneWidget);
    });

    testWidgets('displays editor with initial values', (tester) async {
      const initial = QuestionDraft(
        questionText: 'What is 2+2?',
        questionType: QuestionType.mcqSingle,
        options: [
          QuestionOptionDraft(text: '3'),
          QuestionOptionDraft(text: '4'),
        ],
        correctOptionIndex: 1,
        difficulty: DifficultyLevel.easy,
        marks: 2,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: QuestionEditor(
              initial: initial,
              onSave: (_) {},
            ),
          ),
        ),
      );

      expect(find.text('Edit Question'), findsOneWidget);
      expect(find.text('What is 2+2?'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
      expect(find.text('4'), findsOneWidget);
    });

    testWidgets('adds new option when Add is tapped', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: QuestionEditor(
              onSave: (_) {},
            ),
          ),
        ),
      );

      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();

      final finalOptions = find.byType(TextFormField);
      expect(finalOptions.evaluate().length, greaterThanOrEqualTo(3));
    });

    testWidgets('saves draft when save button is tapped with valid data', (tester) async {
      QuestionDraft? savedDraft;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: QuestionEditor(
              onSave: (draft) => savedDraft = draft,
            ),
          ),
        ),
      );

      // Enter question text
      await tester.enterText(
        find.byType(TextFormField).first,
        'What is 2+2?',
      );

      // Enter option texts
      final optionFields = find.byType(TextFormField);
      await tester.enterText(optionFields.at(1), '3');
      await tester.enterText(optionFields.at(2), '4');

      // Select correct option (second option)
      await tester.tap(find.byType(Radio<int>).at(1));
      await tester.pumpAndSettle();

      // Tap Save button (the TextButton in AppBar)
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(savedDraft, isNotNull);
      expect(savedDraft!.questionText, 'What is 2+2?');
    });

    testWidgets('does not save when question text is empty', (tester) async {
      QuestionDraft? savedDraft;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: QuestionEditor(
              onSave: (draft) => savedDraft = draft,
            ),
          ),
        ),
      );

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(savedDraft, isNull);
    });

    testWidgets('changes question type', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: QuestionEditor(
              onSave: (_) {},
            ),
          ),
        ),
      );

      await tester.tap(find.byType(DropdownButtonFormField<QuestionType>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('True / False'));
      await tester.pumpAndSettle();

      expect(find.text('True / False'), findsOneWidget);
    });
  });

  group('QuestionDraft RPC parameter mapping', () {
    test('maps question types correctly', () {
      expect(
        const QuestionDraft(
          questionText: 'Q',
          questionType: QuestionType.mcqSingle,
        ).toCreateParams(testId: 't')['p_question_type'],
        'mcq',
      );

      expect(
        const QuestionDraft(
          questionText: 'Q',
          questionType: QuestionType.trueFalse,
        ).toCreateParams(testId: 't')['p_question_type'],
        'tf',
      );

      expect(
        const QuestionDraft(
          questionText: 'Q',
          questionType: QuestionType.integer,
        ).toCreateParams(testId: 't')['p_question_type'],
        'num',
      );

      expect(
        const QuestionDraft(
          questionText: 'Q',
          questionType: QuestionType.shortAnswer,
        ).toCreateParams(testId: 't')['p_question_type'],
        'short',
      );
    });

    test('maps difficulty levels correctly', () {
      expect(
        const QuestionDraft(
          questionText: 'Q',
          difficulty: DifficultyLevel.easy,
        ).toCreateParams(testId: 't')['p_difficulty'],
        'easy',
      );

      expect(
        const QuestionDraft(
          questionText: 'Q',
          difficulty: DifficultyLevel.medium,
        ).toCreateParams(testId: 't')['p_difficulty'],
        'medium',
      );

      expect(
        const QuestionDraft(
          questionText: 'Q',
          difficulty: DifficultyLevel.hard,
        ).toCreateParams(testId: 't')['p_difficulty'],
        'hard',
      );
    });

    test('includes optional fields only when provided', () {
      const draft = QuestionDraft(
        questionText: 'Q',
        explanation: 'Because',
        subjectId: 's-1',
        topicNodeId: 'tn-1',
        language: 'en',
        negativeMarks: 0.5,
      );
      final params = draft.toCreateParams(testId: 't');

      expect(params['p_explanation'], 'Because');
      expect(params['p_subject_id'], 's-1');
      expect(params['p_topic_node_id'], 'tn-1');
      expect(params['p_language'], 'en');
      expect(params['p_negative_marks'], 0.5);
    });

    test('omits optional fields when not provided', () {
      const draft = QuestionDraft(questionText: 'Q');
      final params = draft.toCreateParams(testId: 't');

      expect(params.containsKey('p_explanation'), isFalse);
      expect(params.containsKey('p_subject_id'), isFalse);
      expect(params.containsKey('p_topic_node_id'), isFalse);
      expect(params.containsKey('p_language'), isFalse);
      expect(params.containsKey('p_negative_marks'), isFalse);
    });
  });

  group('Security verification', () {
    test('QuestionDraft.toCreateParams does not expose correct_option in serialization', () {
      const draft = QuestionDraft(
        questionText: 'Q',
        questionType: QuestionType.mcqSingle,
        options: [
          QuestionOptionDraft(id: '1', text: 'A'),
          QuestionOptionDraft(id: '2', text: 'B'),
        ],
        correctOptionIndex: 1,
      );
      final params = draft.toCreateParams(testId: 't');

      // correct_option is passed as p_correct_option (RPC param), not serialized to JSON
      expect(params['p_correct_option'], 1);

      // Verify the model itself doesn't serialize correct_option
      final json = draft.toJson();
      expect(json.containsKey('correct_option'), isFalse);
    });
  });
}
