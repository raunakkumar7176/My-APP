// Resume against the LIVE answers contract (2026-09-16):
//   GRANT SELECT ON public.answers TO authenticated + policy "own answers";
//   columns attempt_id, question_id, selected_option (int index),
//   marked_for_review, updated_at.

import 'package:flutter_test/flutter_test.dart';
import 'package:my_praperation/core/errors/app_error.dart';
import 'package:my_praperation/core/models/answer.dart';
import 'package:my_praperation/core/models/attempt.dart';
import 'package:my_praperation/core/models/question.dart';
import 'package:my_praperation/core/models/test.dart';
import 'package:my_praperation/features/test/data/answer_repository.dart';
import 'package:my_praperation/features/test/state/attempt_controller.dart';
import 'package:my_praperation/features/test/state/attempt_launch_store.dart';

import 'fakes.dart';

class _Answers implements AnswerRepository {
  _Answers({this.rows = const [], this.failReads = false});
  List<Answer> rows;
  bool failReads;
  int reads = 0;

  @override
  Future<void> save(String attemptId, List<Answer> answers) async {}

  @override
  Future<List<Answer>> forAttempt(String attemptId) async {
    reads++;
    if (failReads) throw const DataError(message: 'Failed to load.');
    return rows;
  }
}

const _mcq1 = Question(
  id: 'q-1', testId: 't-1', ordinal: 1, question: 'Q1',
  options: [QuestionOption(id: '', text: 'A', index: 0), QuestionOption(id: '', text: 'B', index: 1)],
  difficulty: DifficultyLevel.easy, marks: 1, status: 'approved',
  questionType: QuestionType.mcqSingle,
);
const _typed = Question(
  id: 'q-2', testId: 't-1', ordinal: 2, question: 'Q2', options: null,
  difficulty: DifficultyLevel.easy, marks: 1, status: 'approved',
  questionType: QuestionType.integer,
);
const _mcq3 = Question(
  id: 'q-3', testId: 't-1', ordinal: 3, question: 'Q3',
  options: [QuestionOption(id: '', text: 'A', index: 0), QuestionOption(id: '', text: 'B', index: 1)],
  difficulty: DifficultyLevel.easy, marks: 1, status: 'approved',
  questionType: QuestionType.mcqSingle,
);

Test _test({bool shuffle = false}) => Test(
      id: 't-1', createdBy: 'u-1', title: 'T', status: TestStatus.published,
      testMode: 'self', shuffleQuestions: shuffle,
    );

Attempt _attempt() => Attempt(
      id: 'a-1', testId: 't-1', userId: 'u-1', status: AttemptStatus.inProgress,
      startedAt: DateTime(2026, 9, 16), deadlineAt: DateTime(2026, 9, 16, 1),
    );

AttemptController _controller(AnswerRepository answers, {required List<Question> qs, bool shuffle = false}) {
  return AttemptController(
    attemptId: 'a-1', testId: 't-1',
    attempts: FakeAttemptRepository()..next = _attempt(),
    questions: FakeQuestionRepository()..byTest['t-1'] = qs,
    answers: answers,
    tests: FakeTestRepository()..rows['t-1'] = _test(shuffle: shuffle),
    autosaveInterval: const Duration(hours: 1),
  );
}

void main() {
  setUp(AttemptLaunchStore.clear);

  test('answers row parsing uses the live column names only', () {
    final a = Answer.fromRow({
      'attempt_id': 'a-1',
      'question_id': 'q-1',
      'selected_option': 1,
      'marked_for_review': true,
      'updated_at': '2026-09-16T10:00:00Z',
    });
    expect(a.selectedOption, 1);
    expect(a.markedForReview, isTrue);
    expect(a.isAnswered, isTrue);
    // Legacy keys are ignored, never read.
    final legacy = Answer.fromRow({
      'attempt_id': 'a-1', 'question_id': 'q-1',
      'selected_option_id': 'x', 'is_marked_for_review': true, 'is_answered': true, 'text_answer': 't',
    });
    expect(legacy.selectedOption, isNull);
    expect(legacy.markedForReview, isFalse);
    expect(legacy.isAnswered, isFalse);
  });

  test('the SELECT column list is exactly the live columns', () {
    expect(SupabaseAnswerRepository.selectColumns,
        'attempt_id, question_id, selected_option, marked_for_review, updated_at');
  });

  test('resume restores selected_option and marked_for_review by question_id; '
      'questions without a row stay unanswered', () async {
    final answers = _Answers(rows: [
      Answer.fromRow({'attempt_id': 'a-1', 'question_id': 'q-1', 'selected_option': 1, 'marked_for_review': false}),
      Answer.fromRow({'attempt_id': 'a-1', 'question_id': 'q-3', 'selected_option': null, 'marked_for_review': true}),
    ]);
    final c = _controller(answers, qs: const [_mcq1, _typed, _mcq3]);
    await c.load();

    expect(c.answersLoadFailed, isFalse);
    expect(answers.reads, 1);
    expect(c.answerFor('q-1')!.selectedOption, 1);
    expect(c.answerFor('q-1')!.isAnswered, isTrue);
    expect(c.answerFor('q-2'), isNull, reason: 'no row → unanswered, nothing fabricated');
    expect(c.answerFor('q-3')!.isAnswered, isFalse);
    expect(c.answerFor('q-3')!.markedForReview, isTrue);
    expect(c.answeredCount, 1);
    expect(c.markedCount, 1);
    c.dispose();
  });

  test('restored selected_option maps to the correct option after deterministic shuffle',
      () async {
    final six = Question(
      id: 'q-6', testId: 't-1', ordinal: 1, question: 'Pick',
      options: [for (var i = 0; i < 6; i++) QuestionOption(id: '', text: 'opt$i', index: i)],
      difficulty: DifficultyLevel.easy, marks: 1, status: 'approved',
      questionType: QuestionType.mcqSingle,
    );
    final answers = _Answers(rows: const [
      Answer(attemptId: 'a-1', questionId: 'q-6', selectedOption: 4),
    ]);
    final c = _controller(answers, qs: [six], shuffle: true);
    await c.load();

    final displayed = c.optionsFor(six);
    expect(displayed.map((o) => o.index).toSet(), {0, 1, 2, 3, 4, 5});
    expect(displayed.map((o) => o.index).toList(), isNot([0, 1, 2, 3, 4, 5]),
        reason: 'display order is shuffled');
    final restored = displayed.singleWhere((o) => o.index == c.answerFor('q-6')!.selectedOption);
    expect(restored.text, 'opt4', reason: 'server index 4 → the option that was index 4');

    // Selecting a displayed option saves its SERVER index, not its position.
    final third = displayed[2];
    c.selectOption('q-6', third.index);
    expect(c.answerFor('q-6')!.toRpcJson()['selected_option'], third.index);
    c.dispose();
  });

  test('read failure is surfaced, nothing fabricated, retry keeps unsaved local edits',
      () async {
    final answers = _Answers(failReads: true);
    final c = _controller(answers, qs: const [_mcq1]);
    await c.load();

    expect(c.error, isNull, reason: 'the attempt still works');
    expect(c.answersLoadFailed, isTrue);
    expect(c.answerFor('q-1'), isNull);

    c.selectOption('q-1', 0);
    answers
      ..failReads = false
      ..rows = const [Answer(attemptId: 'a-1', questionId: 'q-1', selectedOption: 1)];
    await c.reloadSavedAnswers();
    expect(c.answersLoadFailed, isFalse);
    expect(c.answerFor('q-1')!.selectedOption, 0, reason: 'unsaved local edit wins');
    c.dispose();
  });

  test('typed-answer questions remain unsupported (no storage/scoring contract)',
      () async {
    final c = _controller(_Answers(), qs: const [_typed]);
    await c.load();
    expect(_typed.hasOptions, isFalse);
    expect(c.optionsFor(_typed), isEmpty);
    expect(c.answerFor('q-2'), isNull);
    expect(c.answeredCount, 0);
    c.dispose();
  });
}
