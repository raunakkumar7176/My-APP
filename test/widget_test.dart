import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:my_praperation/core/models/question.dart';
import 'package:my_praperation/core/models/subject.dart';
import 'package:my_praperation/core/models/syllabus_node.dart';
import 'package:my_praperation/core/models/test.dart';
import 'package:my_praperation/core/models/test_syllabus.dart';

Widget wrapWithApp(Widget child) {
  return MaterialApp(home: child);
}

void main() {
  group('Subject Model', () {
    test('parses from JSON correctly', () {
      final json = {'id': 'subj-1', 'name': 'Mathematics'};
      final subject = Subject.fromJson(json);
      expect(subject.id, 'subj-1');
      expect(subject.name, 'Mathematics');
    });

    test('serializes to JSON correctly', () {
      const subject = Subject(id: 'subj-1', name: 'Mathematics');
      final json = subject.toJson();
      expect(json['id'], 'subj-1');
      expect(json['name'], 'Mathematics');
    });

    test('equality works', () {
      const a = Subject(id: '1', name: 'Math');
      const b = Subject(id: '1', name: 'Math');
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });

    test('inequality works', () {
      const a = Subject(id: '1', name: 'Math');
      const b = Subject(id: '2', name: 'Science');
      expect(a, isNot(equals(b)));
    });
  });

  group('SyllabusNode Model', () {
    test('parses from JSON correctly', () {
      final json = {
        'id': 'node-1',
        'subject_id': 'subj-1',
        'parent_id': null,
        'class_level': 'Class 12',
        'name': 'Algebra',
        'created_at': '2025-01-15T10:30:00Z',
      };
      final node = SyllabusNode.fromJson(json);
      expect(node.id, 'node-1');
      expect(node.subjectId, 'subj-1');
      expect(node.parentId, isNull);
      expect(node.classLevel, 'Class 12');
      expect(node.name, 'Algebra');
      expect(node.isRoot, isTrue);
    });

    test('child node has parent_id', () {
      final json = {
        'id': 'node-2',
        'subject_id': 'subj-1',
        'parent_id': 'node-1',
        'class_level': null,
        'name': 'Linear Equations',
        'created_at': '2025-01-15T10:30:00Z',
      };
      final node = SyllabusNode.fromJson(json);
      expect(node.parentId, 'node-1');
      expect(node.isRoot, isFalse);
    });

    test('handles nullable fields', () {
      final json = {
        'id': 'node-1',
        'subject_id': 'subj-1',
        'parent_id': null,
        'class_level': null,
        'name': 'Algebra',
        'created_at': '2025-01-15T10:30:00Z',
      };
      final node = SyllabusNode.fromJson(json);
      expect(node.parentId, isNull);
      expect(node.classLevel, isNull);
    });
  });

  group('Question Model', () {
    test('parses from JSON with live RPC values', () {
      final json = {
        'id': 'q-1',
        'test_id': 't-1',
        'ordinal': 1,
        'question': 'What is 2+2?',
        'options': [
          {'id': '1', 'text': '3'},
          {'id': '2', 'text': '4'},
          {'id': '3', 'text': '5'},
        ],
        'difficulty': 'easy',
        'marks': 1,
        'status': 'active',
        'question_type': 'mcq',
      };
      final q = Question.fromJson(json);
      expect(q.id, 'q-1');
      expect(q.testId, 't-1');
      expect(q.ordinal, 1);
      expect(q.question, 'What is 2+2?');
      expect(q.options?.length, 3);
      expect(q.difficulty, DifficultyLevel.easy);
      expect(q.marks, 1);
      expect(q.status, 'active');
      expect(q.questionType, QuestionType.mcqSingle);
    });

    test('toJson does not include correct_option', () {
      final json = {
        'id': 'q-1',
        'test_id': 't-1',
        'question': 'Q',
        'difficulty': 'easy',
        'marks': 1,
        'status': 'active',
        'question_type': 'mcq',
        'correct_option': 2,
      };
      final q = Question.fromJson(json);
      final serialized = q.toJson();
      expect(serialized.containsKey('correct_option'), isFalse);
    });

    test('equality works', () {
      final a = Question(
        id: '1',
        testId: 't-1',
        question: 'Q',
        difficulty: DifficultyLevel.easy,
        marks: 1,
        status: 'active',
      );
      final b = Question(
        id: '1',
        testId: 't-1',
        question: 'Q',
        difficulty: DifficultyLevel.easy,
        marks: 1,
        status: 'active',
      );
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });
  });

  group('Test Model', () {
    test('parses from JSON correctly', () {
      final json = {
        'id': 't-1',
        'created_by': 'user-1',
        'title': 'Math Quiz',
        'description': 'Algebra',
        'duration_sec': 3600,
        'status': 'draft',
        'created_at': '2025-01-15T10:30:00Z',
      };
      final test = Test.fromJson(json);
      expect(test.id, 't-1');
      expect(test.createdBy, 'user-1');
      expect(test.title, 'Math Quiz');
      expect(test.description, 'Algebra');
      expect(test.durationSec, 3600);
      expect(test.status, TestStatus.draft);
    });

    test('parses published status', () {
      final json = {
        'id': 't-1',
        'created_by': 'user-1',
        'title': 'Math Quiz',
        'status': 'published',
        'created_at': '2025-01-15T10:30:00Z',
      };
      final test = Test.fromJson(json);
      expect(test.status, TestStatus.published);
    });
  });

  group('TestSyllabus Model', () {
    test('parses from JSON correctly', () {
      final json = {
        'id': 'ts-1',
        'test_id': 't-1',
        'syllabus_node_id': 'n-1',
        'material_ids': ['m-1', 'm-2'],
        'created_at': '2025-01-15T10:30:00Z',
      };
      final ts = TestSyllabus.fromJson(json);
      expect(ts.id, 'ts-1');
      expect(ts.testId, 't-1');
      expect(ts.syllabusNodeId, 'n-1');
      expect(ts.materialIds, ['m-1', 'm-2']);
    });

    test('handles null material_ids', () {
      final json = {
        'id': 'ts-1',
        'test_id': 't-1',
        'syllabus_node_id': 'n-1',
        'created_at': '2025-01-15T10:30:00Z',
      };
      final ts = TestSyllabus.fromJson(json);
      expect(ts.materialIds, isNull);
    });
  });
}
