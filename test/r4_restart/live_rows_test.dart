// Live row shapes observed on Chrome (2026-09-17) that the models must accept.
import 'package:flutter_test/flutter_test.dart';
import 'package:my_praperation/core/models/question.dart';
import 'package:my_praperation/core/models/test_syllabus.dart';

void main() {
  test('questions.source_batch is an integer live', () {
    final q = Question.fromJson({
      'id': 'q', 'test_id': 't', 'ordinal': 1, 'question': 'Q?', 'options': ['a', 'b'],
      'difficulty': 'easy', 'marks': 1, 'status': 'approved', 'question_type': 'mcq',
      'source_batch': 1, 'bank_id': null, 'language': 'en',
    });
    expect(q.sourceBatch, '1');
  });

  test('test_syllabus row has no id column live', () {
    final s = TestSyllabus.fromJson({
      'test_id': 't-1', 'syllabus_node_id': 'n-1', 'material_ids': null,
      'created_at': '2026-09-17T05:00:00+00:00',
    });
    expect(s.id, 't-1:n-1');
    expect(s.syllabusNodeId, 'n-1');
  });
}
