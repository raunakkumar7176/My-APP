import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:my_praperation/core/models/group.dart';
import 'package:my_praperation/core/models/question.dart';
import 'package:my_praperation/features/test/domain/test_kind.dart';
import 'package:my_praperation/features/test/models/question_draft.dart';
import 'package:my_praperation/features/test/widgets/basic_details_step.dart';
import 'package:my_praperation/features/test/widgets/configuration_step.dart';
import 'package:my_praperation/features/test/widgets/questions_step.dart';
import 'package:my_praperation/features/test/widgets/question_editor.dart';
import 'package:my_praperation/features/test/widgets/review_step.dart';

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
      // V1 rule: MCQ requires at least QuestionDraft.minOptions (4) options.
      const draft = QuestionDraft(
        questionText: 'What is 2+2?',
        questionType: QuestionType.mcqSingle,
        options: [
          QuestionOptionDraft(text: '2'),
          QuestionOptionDraft(text: '3'),
          QuestionOptionDraft(text: '4'),
          QuestionOptionDraft(text: '5'),
        ],
        correctOptionIndex: 2,
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

    test('isValid returns false for True/False (unsupported type in V1)', () {
      // V1 rule: QuestionDraft.isSupportedType only accepts mcqSingle; every
      // other type is shown as "Coming soon" and can never be valid.
      const draft = QuestionDraft(
        questionText: 'Is the sky blue?',
        questionType: QuestionType.trueFalse,
        marks: 1,
      );
      expect(draft.isValid, isFalse);
    });

    test('copyWith creates new instance with updated fields', () {
      const original = QuestionDraft(questionText: 'Original', marks: 1);
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
      // V1 rule: hasValidOptions requires >= QuestionDraft.minOptions (4).
      const validDraft = QuestionDraft(
        questionText: 'Q',
        questionType: QuestionType.mcqSingle,
        options: [
          QuestionOptionDraft(text: 'A'),
          QuestionOptionDraft(text: 'B'),
          QuestionOptionDraft(text: 'C'),
          QuestionOptionDraft(text: 'D'),
        ],
      );
      expect(validDraft.hasValidOptions, isTrue);

      const invalidDraft = QuestionDraft(
        questionText: 'Q',
        questionType: QuestionType.mcqSingle,
        options: [
          QuestionOptionDraft(text: ''),
          QuestionOptionDraft(text: 'B'),
          QuestionOptionDraft(text: 'C'),
          QuestionOptionDraft(text: 'D'),
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

  group('BasicDetailsStep', () {
    testWidgets('displays title, description, and test kind fields', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrapWithApp(
          BasicDetailsStep(
            title: '',
            description: '',
            kind: TestKind.self,
            onTitleChanged: (_) {},
            onDescriptionChanged: (_) {},
            onKindChanged: (_) {},
            titleError: null,
          ),
        ),
      );

      expect(find.text('Basic Details'), findsOneWidget);
      // Two TextFormField widgets: title and description.
      expect(find.byType(TextFormField), findsNWidgets(2));
      // The redesign replaced the DropdownButtonFormField with a tile-based
      // picker rendered as InkWell widgets; verify the selected kind label
      // is present instead of asserting a DropdownButtonFormField type.
      expect(find.text('Self'), findsOneWidget);
    });

    testWidgets('calls onTitleChanged when title is entered', (tester) async {
      String? capturedTitle;
      await tester.pumpWidget(
        wrapWithApp(
          BasicDetailsStep(
            title: '',
            description: '',
            kind: TestKind.self,
            onTitleChanged: (value) => capturedTitle = value,
            onDescriptionChanged: (_) {},
            onKindChanged: (_) {},
            titleError: null,
          ),
        ),
      );

      await tester.enterText(find.byType(TextFormField).first, 'My Test');
      expect(capturedTitle, 'My Test');
    });

    testWidgets('shows title error when titleError is provided', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrapWithApp(
          BasicDetailsStep(
            title: '',
            description: '',
            kind: TestKind.self,
            onTitleChanged: (_) {},
            onDescriptionChanged: (_) {},
            onKindChanged: (_) {},
            titleError: 'Title is required',
          ),
        ),
      );

      expect(find.text('Title is required'), findsOneWidget);
    });

    testWidgets('shows all test kind options', (tester) async {
      await tester.pumpWidget(
        wrapWithApp(
          BasicDetailsStep(
            title: '',
            description: '',
            kind: TestKind.self,
            onTitleChanged: (_) {},
            onDescriptionChanged: (_) {},
            onKindChanged: (_) {},
            titleError: null,
          ),
        ),
      );

      // The redesign renders every kind as a visible tile (no dropdown
      // popup). Verify all kind labels are present in the tree.
      expect(find.text('Self'), findsOneWidget);
      expect(find.text('Practice Test'), findsOneWidget);
      expect(find.text('Quick Test'), findsOneWidget);
      expect(find.text('Challenge with Friends'), findsOneWidget);
      expect(find.text('Group Test'), findsOneWidget);
    });

    testWidgets('calls onKindChanged when selection changes', (tester) async {
      TestKind? capturedKind;
      await tester.pumpWidget(
        wrapWithApp(
          BasicDetailsStep(
            title: '',
            description: '',
            kind: TestKind.self,
            onTitleChanged: (_) {},
            onDescriptionChanged: (_) {},
            onKindChanged: (value) => capturedKind = value,
            titleError: null,
          ),
        ),
      );

      // Tap the "Challenge with Friends" tile directly (tile-based picker).
      // Use ensureVisible because the tile list may be longer than the viewport.
      await tester.ensureVisible(find.text('Challenge with Friends'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Challenge with Friends'));
      await tester.pumpAndSettle();

      expect(capturedKind, TestKind.challengeWithFriends);
    });

    testWidgets('displays selected test kind value', (tester) async {
      await tester.pumpWidget(
        wrapWithApp(
          BasicDetailsStep(
            title: '',
            description: '',
            kind: TestKind.group,
            onTitleChanged: (_) {},
            onDescriptionChanged: (_) {},
            onKindChanged: (_) {},
            titleError: null,
          ),
        ),
      );

      expect(find.text('Group Test'), findsOneWidget);
    });
  });

  group('ConfigurationStep', () {
    testWidgets('displays all configuration fields', (tester) async {
      // Max Participants / Allow Late Joining only render for scheduled
      // kinds; Join Code / Access Code only render when the kind requires a
      // join code. challengeWithFriends is both, so it exercises every
      // field in one pump.
      await tester.pumpWidget(
        wrapWithApp(
          ConfigurationStep(
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
            kind: TestKind.challengeWithFriends,
            onChanged: (_) {},
          ),
        ),
      );

      expect(find.text('Test Configuration'), findsOneWidget);
      expect(find.text('Duration (minutes)'), findsOneWidget);
      // The redesign renamed "Marks per Question" → "Correct Answer" and
      // placed it side-by-side with "Negative Marks" inside a Row.
      expect(find.text('Correct Answer'), findsOneWidget);
      expect(find.text('Negative Marks'), findsOneWidget);
      expect(find.text('Max Participants'), findsOneWidget);
      expect(find.text('Access Code'), findsOneWidget);
      expect(find.text('Join Code *'), findsOneWidget);
      expect(find.text('Allow Late Joining'), findsOneWidget);
    });

    testWidgets('calls onChanged with updated values', (tester) async {
      Map<String, dynamic>? capturedValues;
      await tester.pumpWidget(
        wrapWithApp(
          ConfigurationStep(
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
              child: ConfigurationStep(
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

      // The redesign replaced SwitchListTile with a Switch inside a
      // SettingTile; the semantic label "Allow Late Joining" is still
      // present, but the toggle widget is now a bare Switch.
      await tester.ensureVisible(find.byType(Switch));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(capturedValues!['allowLateJoin'], true);
    });

    // Regression coverage for "Cannot hit test a render box with no size":
    // the group-selection section's content height changes twice outside
    // any user gesture — on self<->group mode switch, and again when
    // groupsLoading flips after the async group fetch resolves. These
    // tests verify both transitions render cleanly (via pumpAndSettle,
    // which drives the AnimatedSize wrapper to completion) rather than
    // throwing during layout/hit-testing. They cannot reproduce the exact
    // framework-level gesture-vs-relayout race a live device hits, but they
    // do prove the state plumbing and the animated-resize path are sound.
    testWidgets(
      'switching self -> group and back renders without throwing',
      (tester) async {
        String testMode = 'self';
        late StateSetter setLocalState;
        await tester.pumpWidget(
          wrapWithApp(
            StatefulBuilder(
              builder: (context, setState) {
                setLocalState = setState;
                return ConfigurationStep(
                  durationSec: null,
                  marksPerQuestion: null,
                  negativeMarks: null,
                  testMode: testMode,
                  groupId: null,
                  startsAt: null,
                  endsAt: null,
                  maxParticipants: null,
                  allowLateJoin: false,
                  accessCode: null,
                  joinCode: null,
                  kind: TestKind.group,
                  groups: const [],
                  onChanged: (_) {},
                );
              },
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        setLocalState(() => testMode = 'group');
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('Group Selection'), findsOneWidget);

        setLocalState(() => testMode = 'self');
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('Group Selection'), findsNothing);
      },
    );

    testWidgets(
      'groups arriving after the initial (empty) build renders without throwing',
      (tester) async {
        List<Group> groups = const [];
        bool loading = true;
        late StateSetter setLocalState;
        await tester.pumpWidget(
          wrapWithApp(
            StatefulBuilder(
              builder: (context, setState) {
                setLocalState = setState;
                return ConfigurationStep(
                  durationSec: null,
                  marksPerQuestion: null,
                  negativeMarks: null,
                  testMode: 'group',
                  groupId: null,
                  startsAt: null,
                  endsAt: null,
                  maxParticipants: null,
                  allowLateJoin: false,
                  accessCode: null,
                  joinCode: null,
                  kind: TestKind.group,
                  groups: groups,
                  groupsLoading: loading,
                  onChanged: (_) {},
                );
              },
            ),
          ),
        );
        // Not pumpAndSettle: CircularProgressIndicator animates forever.
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));
        expect(find.byType(CircularProgressIndicator), findsOneWidget);

        // Simulate loadGroups() resolving mid-scroll-session: groups arrive
        // and the loading spinner is replaced by a populated dropdown, all
        // driven by a setState from outside any user gesture.
        setLocalState(() {
          loading = false;
          groups = [
            Group(
              id: 'g-1',
              name: 'Physics Batch',
              ownerId: 'u-owner',
              createdAt: DateTime(2026),
              memberCount: 12,
            ),
          ];
        });
        // Bounded pumps, not pumpAndSettle: this StatefulBuilder-driven tree
        // can have long-lived animations elsewhere in the widget catalog
        // unrelated to this fix; a handful of pumps past the 200ms
        // AnimatedSize duration is enough to prove the transition completes
        // without throwing.
        await tester.pump();
        for (var i = 0; i < 5; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(tester.takeException(), isNull);
        expect(find.byType(DropdownButtonFormField<String>), findsOneWidget);
      },
    );
  });

  group('QuestionsStep', () {
    testWidgets('shows empty state when no questions', (tester) async {
      await tester.pumpWidget(
        wrapWithApp(
          QuestionsStep(
            localQuestions: const [],
            serverQuestions: const [],
            onLocalQuestionsChanged: (_) {},
            onDeleteServerQuestion: (_) async {},
            onUpdateServerQuestion: (_, _) async {},
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
          QuestionsStep(
            localQuestions: questions,
            serverQuestions: const [],
            onLocalQuestionsChanged: (_) {},
            onDeleteServerQuestion: (_) async {},
            onUpdateServerQuestion: (_, _) async {},
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
          QuestionsStep(
            localQuestions: questions,
            serverQuestions: const [],
            onLocalQuestionsChanged: (_) {},
            onDeleteServerQuestion: (_) async {},
            onUpdateServerQuestion: (_, _) async {},
          ),
        ),
      );

      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();

      expect(find.text('Edit'), findsOneWidget);
      expect(find.text('Delete'), findsOneWidget);
    });

    testWidgets('deletes question when delete is tapped', (tester) async {
      final List<QuestionDraft> capturedQuestions = [];
      const questions = [
        QuestionDraft(
          questionText: 'Question 1',
          questionType: QuestionType.mcqSingle,
          marks: 1,
        ),
      ];

      await tester.pumpWidget(
        wrapWithApp(
          QuestionsStep(
            localQuestions: questions,
            serverQuestions: const [],
            onLocalQuestionsChanged: (q) => capturedQuestions.addAll(q),
            onDeleteServerQuestion: (_) async {},
            onUpdateServerQuestion: (_, _) async {},
          ),
        ),
      );

      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));

      expect(capturedQuestions, isEmpty);
    });
  });

  group('ReviewStep', () {
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
          ReviewStep(
            title: 'Math Quiz',
            kind: TestKind.self,
            durationSec: 3600,
            marksPerQuestion: 2.0,
            negativeMarks: 0.5,
            startsAt: now,
            endsAt: now.add(const Duration(hours: 2)),
            readiness: const [],
            serverQuestions: const [],
            localQuestions: questions,
            syllabusCount: 2,
            onApprove: (_) async {},
            onApproveAll: () async => 0,
          ),
        ),
      );

      expect(find.text('Review Test'), findsOneWidget);
      expect(find.text('Math Quiz'), findsOneWidget);
      // TestFormatters.duration(3600) → '1h' (hours-only formatting).
      expect(find.text('1h'), findsOneWidget);
      expect(find.text('2.0'), findsOneWidget);
      expect(find.text('0.5'), findsOneWidget);
      expect(find.text('2'), findsWidgets);
    });

    testWidgets('shows question count', (tester) async {
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
          ReviewStep(
            title: 'Test',
            kind: TestKind.self,
            durationSec: null,
            marksPerQuestion: null,
            negativeMarks: null,
            startsAt: null,
            endsAt: null,
            readiness: const [],
            serverQuestions: const [],
            localQuestions: questions,
            syllabusCount: 0,
            onApprove: (_) async {},
            onApproveAll: () async => 0,
          ),
        ),
      );

      expect(find.text('3'), findsOneWidget);
    });
  });

  group('QuestionEditor', () {
    testWidgets('displays empty editor for new question', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: QuestionEditor(onSave: (_) {})),
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
            body: QuestionEditor(initial: initial, onSave: (_) {}),
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
          home: Scaffold(body: QuestionEditor(onSave: (_) {})),
        ),
      );

      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();

      final finalOptions = find.byType(TextFormField);
      expect(finalOptions.evaluate().length, greaterThanOrEqualTo(3));
    });

    testWidgets('saves draft when save button is tapped with valid data', (
      tester,
    ) async {
      QuestionDraft? savedDraft;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: QuestionEditor(onSave: (draft) => savedDraft = draft),
          ),
        ),
      );

      // Enter question text
      await tester.enterText(find.byType(TextFormField).first, 'What is 2+2?');

      // Enter option texts. V1 always shows QuestionDraft.minOptions (4)
      // option fields; all must be filled for the draft to be valid.
      final optionFields = find.byType(TextFormField);
      await tester.enterText(optionFields.at(1), '1');
      await tester.enterText(optionFields.at(2), '2');
      await tester.enterText(optionFields.at(3), '3');
      await tester.enterText(optionFields.at(4), '4');

      // Select correct option (second option)
      await tester.ensureVisible(find.byType(Radio<int>).at(1));
      await tester.pumpAndSettle();
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
            body: QuestionEditor(onSave: (draft) => savedDraft = draft),
          ),
        ),
      );

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(savedDraft, isNull);
    });

    testWidgets(
      'other question types are shown as Coming soon and stay unselectable',
      (tester) async {
        // V1: QuestionDraft.isSupportedType only accepts mcqSingle. Every
        // other type is listed but disabled, so tapping it must not change
        // the selection away from MCQ.
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(body: QuestionEditor(onSave: (_) {})),
          ),
        );

        await tester.tap(find.byType(DropdownButtonFormField<QuestionType>));
        await tester.pumpAndSettle();
        expect(find.text('True / False — Coming soon'), findsOneWidget);

        await tester.tap(find.text('True / False — Coming soon'));
        await tester.pumpAndSettle();

        // Disabled item ignores the tap; the dropdown stays open with MCQ
        // still selected (shown once in the field, once in the menu).
        expect(find.text('MCQ (Single Answer)'), findsWidgets);
      },
    );
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
