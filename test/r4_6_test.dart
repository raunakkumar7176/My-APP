import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:my_praperation/core/models/test.dart';

Widget wrapWithApp(Widget child) {
  return MaterialApp(home: Scaffold(body: child));
}

void main() {
  group('Test Model - Category Classification', () {
    test('scheduled test is upcoming', () {
      final test = Test(
        id: 't-1',
        createdBy: 'user-1',
        title: 'Scheduled Test',
        status: TestStatus.scheduled,
        startsAt: DateTime.now().add(const Duration(days: 1)),
      );

      expect(test.status, TestStatus.scheduled);
      expect(test.isSoftDeleted, isFalse);
    });

    test('published test with future startsAt is upcoming', () {
      final test = Test(
        id: 't-1',
        createdBy: 'user-1',
        title: 'Published Test',
        status: TestStatus.published,
        startsAt: DateTime.now().add(const Duration(days: 1)),
      );

      expect(test.status, TestStatus.published);
      expect(test.startsAt!.isAfter(DateTime.now()), isTrue);
    });

    test('live test is live', () {
      final test = Test(
        id: 't-1',
        createdBy: 'user-1',
        title: 'Live Test',
        status: TestStatus.live,
      );

      expect(test.status, TestStatus.live);
    });

    test('ready test is live', () {
      final test = Test(
        id: 't-1',
        createdBy: 'user-1',
        title: 'Ready Test',
        status: TestStatus.ready,
      );

      expect(test.status, TestStatus.ready);
    });

    test('completed test is previous', () {
      final test = Test(
        id: 't-1',
        createdBy: 'user-1',
        title: 'Completed Test',
        status: TestStatus.completed,
      );

      expect(test.status, TestStatus.completed);
    });

    test('ended test is previous', () {
      final test = Test(
        id: 't-1',
        createdBy: 'user-1',
        title: 'Ended Test',
        status: TestStatus.ended,
      );

      expect(test.status, TestStatus.ended);
    });

    test('evaluated test is previous', () {
      final test = Test(
        id: 't-1',
        createdBy: 'user-1',
        title: 'Evaluated Test',
        status: TestStatus.evaluated,
      );

      expect(test.status, TestStatus.evaluated);
    });

    test('cancelled test is previous', () {
      final test = Test(
        id: 't-1',
        createdBy: 'user-1',
        title: 'Cancelled Test',
        status: TestStatus.cancelled,
      );

      expect(test.status, TestStatus.cancelled);
    });

    test('archived test is previous', () {
      final test = Test(
        id: 't-1',
        createdBy: 'user-1',
        title: 'Archived Test',
        status: TestStatus.archived,
      );

      expect(test.status, TestStatus.archived);
    });

    test('expired test is previous', () {
      final test = Test(
        id: 't-1',
        createdBy: 'user-1',
        title: 'Expired Test',
        status: TestStatus.expired,
      );

      expect(test.status, TestStatus.expired);
    });

    test('draft test should not appear in any public category', () {
      final test = Test(
        id: 't-1',
        createdBy: 'user-1',
        title: 'Draft Test',
        status: TestStatus.draft,
      );

      expect(test.status, TestStatus.draft);
    });
  });

  group('Test Model - FromJSON', () {
    test('parses test with all fields', () {
      final json = {
        'id': 't-1',
        'created_by': 'user-1',
        'title': 'Math Quiz',
        'description': 'Algebra test',
        'instructions': 'Answer all questions',
        'subject_id': 'subj-1',
        'class_level': 'Class 12',
        'status': 'live',
        'duration_sec': 3600,
        'marks_per_question': 4,
        'negative_marks': 1,
        'starts_at': '2025-01-15T10:00:00Z',
        'ends_at': '2025-01-15T12:00:00Z',
        'group_id': 'g-1',
        'access_code': 'ABC123',
        'join_code': 'XYZ789',
        'test_mode': 'group',
        'max_participants': 50,
        'allow_late_join': true,
        'is_soft_deleted': false,
        'deleted_at': null,
        'archived_at': null,
        'tags': ['math', 'algebra'],
        'language': 'en',
        'difficulty': 'medium',
        'total_marks': 100,
        'passing_marks': 40,
        'total_questions': 25,
        'shuffle_questions': true,
        'show_answers_after': false,
        'is_public': true,
        'created_at': '2025-01-10T10:30:00Z',
        'updated_at': '2025-01-12T10:30:00Z',
      };

      final test = Test.fromJson(json);

      expect(test.id, 't-1');
      expect(test.createdBy, 'user-1');
      expect(test.title, 'Math Quiz');
      expect(test.description, 'Algebra test');
      expect(test.instructions, 'Answer all questions');
      expect(test.subjectId, 'subj-1');
      expect(test.classLevel, 'Class 12');
      expect(test.status, TestStatus.live);
      expect(test.durationSec, 3600);
      expect(test.marksPerQuestion, 4);
      expect(test.negativeMarks, 1);
      expect(test.startsAt, isNotNull);
      expect(test.endsAt, isNotNull);
      expect(test.groupId, 'g-1');
      expect(test.accessCode, 'ABC123');
      expect(test.joinCode, 'XYZ789');
      expect(test.testMode, 'group');
      expect(test.maxParticipants, 50);
      expect(test.allowLateJoin, isTrue);
      expect(test.isSoftDeleted, isFalse);
      expect(test.tags, ['math', 'algebra']);
      expect(test.language, 'en');
      expect(test.difficulty, 'medium');
      expect(test.totalMarks, 100);
      expect(test.passingMarks, 40);
      expect(test.totalQuestions, 25);
      expect(test.shuffleQuestions, isTrue);
      expect(test.showAnswersAfter, isFalse);
      expect(test.isPublic, isTrue);
    });

    test('parses test with null optional fields', () {
      final json = {
        'id': 't-1',
        'created_by': 'user-1',
        'title': 'Simple Test',
        'status': 'draft',
        'created_at': '2025-01-15T10:30:00Z',
      };

      final test = Test.fromJson(json);

      expect(test.id, 't-1');
      expect(test.title, 'Simple Test');
      expect(test.description, isNull);
      expect(test.instructions, isNull);
      expect(test.subjectId, isNull);
      expect(test.classLevel, isNull);
      expect(test.status, TestStatus.draft);
      expect(test.durationSec, isNull);
      expect(test.marksPerQuestion, isNull);
      expect(test.negativeMarks, isNull);
      expect(test.startsAt, isNull);
      expect(test.endsAt, isNull);
      expect(test.groupId, isNull);
      expect(test.accessCode, isNull);
      expect(test.joinCode, isNull);
      expect(test.testMode, isNull);
      expect(test.maxParticipants, isNull);
      expect(test.allowLateJoin, isFalse);
      expect(test.isSoftDeleted, isFalse);
      expect(test.tags, isNull);
      expect(test.language, isNull);
      expect(test.difficulty, isNull);
      expect(test.totalMarks, isNull);
      expect(test.passingMarks, isNull);
      expect(test.totalQuestions, isNull);
      expect(test.shuffleQuestions, isFalse);
      expect(test.showAnswersAfter, isFalse);
      expect(test.isPublic, isTrue);
    });
  });

  group('Test Model - Equality', () {
    test('equality works', () {
      final a = Test(
        id: 't-1',
        createdBy: 'user-1',
        title: 'Math Quiz',
        status: TestStatus.live,
      );
      final b = Test(
        id: 't-1',
        createdBy: 'user-1',
        title: 'Math Quiz',
        status: TestStatus.live,
      );
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });

    test('inequality works', () {
      final a = Test(
        id: 't-1',
        createdBy: 'user-1',
        title: 'Math Quiz',
        status: TestStatus.live,
      );
      final b = Test(
        id: 't-2',
        createdBy: 'user-1',
        title: 'Science Quiz',
        status: TestStatus.live,
      );
      expect(a, isNot(equals(b)));
    });
  });

  group('Test Model - Serialization', () {
    test('toJson serializes correctly', () {
      final test = Test(
        id: 't-1',
        createdBy: 'user-1',
        title: 'Math Quiz',
        description: 'Algebra test',
        status: TestStatus.live,
        durationSec: 3600,
        marksPerQuestion: 4,
        totalQuestions: 25,
        totalMarks: 100,
        passingMarks: 40,
      );

      final json = test.toJson();

      expect(json['id'], 't-1');
      expect(json['created_by'], 'user-1');
      expect(json['title'], 'Math Quiz');
      expect(json['description'], 'Algebra test');
      expect(json['status'], 'live');
      expect(json['duration_sec'], 3600);
      expect(json['marks_per_question'], 4);
      expect(json['total_questions'], 25);
      expect(json['total_marks'], 100);
      expect(json['passing_marks'], 40);
    });
  });

  group('TestStatus Enum', () {
    test('all enum values exist', () {
      expect(TestStatus.values.length, 12);
      expect(TestStatus.values, contains(TestStatus.draft));
      expect(TestStatus.values, contains(TestStatus.scheduled));
      expect(TestStatus.values, contains(TestStatus.live));
      expect(TestStatus.values, contains(TestStatus.ready));
      expect(TestStatus.values, contains(TestStatus.published));
      expect(TestStatus.values, contains(TestStatus.completed));
      expect(TestStatus.values, contains(TestStatus.ended));
      expect(TestStatus.values, contains(TestStatus.evaluated));
      expect(TestStatus.values, contains(TestStatus.cancelled));
      expect(TestStatus.values, contains(TestStatus.archived));
      expect(TestStatus.values, contains(TestStatus.expired));
      expect(TestStatus.values, contains(TestStatus.unknown));
    });
  });
}
