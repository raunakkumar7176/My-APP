import 'package:flutter_test/flutter_test.dart';
import 'package:my_praperation/core/models/question.dart';
import 'package:my_praperation/features/test/models/question_draft.dart';

void main() {
  group('QuestionDraft validation', () {
    test('isValid returns true for valid MCQ question', () {
      const draft = QuestionDraft(
        questionText: 'What is 2+2?',
        questionType: QuestionType.mcqSingle,
        options: [
          QuestionOptionDraft(text: '3'),
          QuestionOptionDraft(text: '4'),
          QuestionOptionDraft(text: '5'),
        ],
        correctOptionIndex: 1,
        marks: 1,
      );
      expect(draft.isValid, true);
    });

    test('isValid returns false when questionText is empty', () {
      const draft = QuestionDraft(
        questionText: '',
        questionType: QuestionType.mcqSingle,
        options: [
          QuestionOptionDraft(text: 'A'),
          QuestionOptionDraft(text: 'B'),
        ],
        correctOptionIndex: 0,
        marks: 1,
      );
      expect(draft.isValid, false);
    });

    test('isValid returns false when marks is 0', () {
      const draft = QuestionDraft(
        questionText: 'Question',
        questionType: QuestionType.mcqSingle,
        options: [
          QuestionOptionDraft(text: 'A'),
          QuestionOptionDraft(text: 'B'),
        ],
        correctOptionIndex: 0,
        marks: 0,
      );
      expect(draft.isValid, false);
    });

    test('isValid returns false for MCQ with less than 2 options', () {
      const draft = QuestionDraft(
        questionText: 'Question',
        questionType: QuestionType.mcqSingle,
        options: [QuestionOptionDraft(text: 'Only one')],
        correctOptionIndex: 0,
        marks: 1,
      );
      expect(draft.isValid, false);
    });

    test('isValid returns false for MCQ with empty option text', () {
      const draft = QuestionDraft(
        questionText: 'Question',
        questionType: QuestionType.mcqSingle,
        options: [
          QuestionOptionDraft(text: 'A'),
          QuestionOptionDraft(text: ''),
        ],
        correctOptionIndex: 0,
        marks: 1,
      );
      expect(draft.isValid, false);
    });

    test('isValid returns false for MCQ without correct option', () {
      const draft = QuestionDraft(
        questionText: 'Question',
        questionType: QuestionType.mcqSingle,
        options: [
          QuestionOptionDraft(text: 'A'),
          QuestionOptionDraft(text: 'B'),
        ],
        correctOptionIndex: null,
        marks: 1,
      );
      expect(draft.isValid, false);
    });

    test('isValid returns false for MCQ with out-of-range correct option', () {
      const draft = QuestionDraft(
        questionText: 'Question',
        questionType: QuestionType.mcqSingle,
        options: [
          QuestionOptionDraft(text: 'A'),
          QuestionOptionDraft(text: 'B'),
        ],
        correctOptionIndex: 5,
        marks: 1,
      );
      expect(draft.isValid, false);
    });

    test('isValid returns true for True/False without options', () {
      const draft = QuestionDraft(
        questionText: 'The sky is blue',
        questionType: QuestionType.trueFalse,
        marks: 1,
      );
      expect(draft.isValid, true);
    });

    test('isValid returns true for Short Answer', () {
      const draft = QuestionDraft(
        questionText: 'Explain photosynthesis',
        questionType: QuestionType.shortAnswer,
        marks: 5,
      );
      expect(draft.isValid, true);
    });

    test('isValid returns true for Numeric/Integer answer', () {
      const draft = QuestionDraft(
        questionText: 'Calculate 15 * 3',
        questionType: QuestionType.integer,
        marks: 2,
      );
      expect(draft.isValid, true);
    });
  });

  group('QuestionDraft copyWith', () {
    test('copies with new question text', () {
      const original = QuestionDraft(questionText: 'Original', marks: 1);
      final copied = original.copyWith(questionText: 'Updated');
      expect(copied.questionText, 'Updated');
      expect(copied.marks, 1);
    });

    test('copies with new marks', () {
      const original = QuestionDraft(questionText: 'Question', marks: 1);
      final copied = original.copyWith(marks: 5);
      expect(copied.questionText, 'Question');
      expect(copied.marks, 5);
    });

    test('copies with new options', () {
      const original = QuestionDraft(
        questionText: 'Question',
        options: [],
        marks: 1,
      );
      final newOptions = [
        const QuestionOptionDraft(text: 'A'),
        const QuestionOptionDraft(text: 'B'),
      ];
      final copied = original.copyWith(options: newOptions);
      expect(copied.options.length, 2);
    });
  });

  group('QuestionDraft toJson', () {
    test('produces valid JSON', () {
      const draft = QuestionDraft(
        questionText: 'What is 2+2?',
        questionType: QuestionType.mcqSingle,
        options: [
          QuestionOptionDraft(text: '3'),
          QuestionOptionDraft(text: '4'),
        ],
        correctOptionIndex: 1,
        explanation: 'Basic math',
        marks: 1,
      );
      final json = draft.toJson();
      expect(json['questionText'], 'What is 2+2?');
      expect(json['questionType'], 'mcqSingle');
      expect(json['options'], isA<List>());
      expect(json['correctOptionIndex'], 1);
      expect(json['explanation'], 'Basic math');
      expect(json['marks'], 1);
    });
  });
}
