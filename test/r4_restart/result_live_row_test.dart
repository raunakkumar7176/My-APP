// Live `results` row (verified 2026-09-17 via Chrome log): no `id` column —
// the primary key is attempt_id. The model must parse exactly this row.
import 'package:flutter_test/flutter_test.dart';
import 'package:my_praperation/core/models/result.dart';

void main() {
  test('Result.fromJson parses the live results row (no id column)', () {
    final r = Result.fromJson({
      'attempt_id': 'a-1',
      'test_id': 't-1',
      'user_id': 'u-1',
      'score': 2,
      'max_score': 2,
      'percentage': 100,
      'accuracy': 100,
      'rank': null,
      'correct_count': 1,
      'wrong_count': 0,
      'unanswered_count': 0,
      'subject_breakdown': {},
      'topic_breakdown': {},
      'computed_at': '2026-09-17T05:10:00+00:00',
    });
    expect(r.id, 'a-1'); // identity falls back to attempt_id
    expect(r.attemptId, 'a-1');
    expect(r.score, 2);
    expect(r.maxScore, 2);
    expect(r.percentage, 100);
    expect(r.correctCount, 1);
    expect(r.isPassed, isNull);
    expect(r.batchId, isNull);
  });

  test('an explicit id still wins when present', () {
    final r = Result.fromJson({
      'id': 'r-9',
      'attempt_id': 'a-1',
      'test_id': 't',
      'user_id': 'u',
    });
    expect(r.id, 'r-9');
  });
}
