import 'package:flutter_test/flutter_test.dart';
import 'package:my_praperation/core/models/question.dart';

void main() {
  group('Question.questionSource', () {
    test('is null when the JSON has no question_source key (no live column confirmed)', () {
      final q = Question.fromJson({
        'id': 'q-1',
        'test_id': 't-1',
        'question': 'What is 2+2?',
        'difficulty': 'easy',
        'marks': 1,
        'status': 'active',
      });
      expect(q.questionSource, isNull);
    });

    test('round-trips through fromJson/toJson when present', () {
      final q = Question.fromJson({
        'id': 'q-1',
        'test_id': 't-1',
        'question': 'What is 2+2?',
        'difficulty': 'easy',
        'marks': 1,
        'status': 'active',
        'question_source': 'ai_generated',
      });
      expect(q.questionSource, 'ai_generated');
      expect(q.toJson()['question_source'], 'ai_generated');
    });

    test('is distinct from sourceBatch (different concepts, both preserved)', () {
      final q = Question.fromJson({
        'id': 'q-1',
        'test_id': 't-1',
        'question': 'What is 2+2?',
        'difficulty': 'easy',
        'marks': 1,
        'status': 'active',
        'source_batch': 7,
        'question_source': 'manual',
      });
      expect(q.sourceBatch, '7');
      expect(q.questionSource, 'manual');
    });

    test('copyWith preserves questionSource', () {
      final q = Question.fromJson({
        'id': 'q-1',
        'test_id': 't-1',
        'question': 'What is 2+2?',
        'difficulty': 'easy',
        'marks': 1,
        'status': 'active',
        'question_source': 'pyq',
      });
      final updated = q.copyWith(status: 'archived');
      expect(updated.questionSource, 'pyq');
      expect(updated.status, 'archived');
    });
  });
}
