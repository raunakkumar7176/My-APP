import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:my_praperation/core/models/material_chunk.dart';
import 'package:my_praperation/core/models/progress_snapshot.dart';
import 'package:my_praperation/core/models/study_material.dart';
import 'package:my_praperation/core/models/subject.dart';
import 'package:my_praperation/core/models/syllabus_node.dart';
import 'package:my_praperation/core/services/material_service.dart';
import 'package:my_praperation/core/services/profile_service.dart';
import 'package:my_praperation/features/auth/splash_screen.dart';
import 'package:my_praperation/features/auth/login_screen.dart';
import 'package:my_praperation/features/auth/signup_screen.dart';

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

  group('StudyMaterial Model', () {
    test('parses from JSON correctly', () {
      final json = {
        'id': 'mat-1',
        'group_id': 'grp-1',
        'uploaded_by': 'user-1',
        'title': 'Chapter 1 Notes',
        'storage_path': 'materials/ch1.pdf',
        'mime_type': 'application/pdf',
        'status': 'ready',
        'created_at': '2025-01-15T10:30:00Z',
      };
      final material = StudyMaterial.fromJson(json);
      expect(material.id, 'mat-1');
      expect(material.title, 'Chapter 1 Notes');
      expect(material.status, MaterialStatus.ready);
      expect(material.isPdf, isTrue);
      expect(material.isReady, isTrue);
    });

    test('handles unknown status', () {
      final json = {
        'id': 'mat-1',
        'group_id': 'grp-1',
        'uploaded_by': 'user-1',
        'title': 'Notes',
        'storage_path': 'path',
        'mime_type': 'application/pdf',
        'status': 'unknown_status',
        'created_at': '2025-01-15T10:30:00Z',
      };
      final material = StudyMaterial.fromJson(json);
      expect(material.status, MaterialStatus.unknown);
    });

    test('handles nullable mime_type', () {
      final json = {
        'id': 'mat-1',
        'group_id': 'grp-1',
        'uploaded_by': 'user-1',
        'title': 'Notes',
        'storage_path': 'path',
        'mime_type': null,
        'status': 'uploaded',
        'created_at': '2025-01-15T10:30:00Z',
      };
      final material = StudyMaterial.fromJson(json);
      expect(material.mimeType, 'application/pdf');
    });
  });

  group('MaterialChunk Model', () {
    test('parses from JSON correctly', () {
      final json = {
        'id': 'chunk-1',
        'material_id': 'mat-1',
        'idx': 0,
        'content': 'Hello World',
      };
      final chunk = MaterialChunk.fromJson(json);
      expect(chunk.id, 'chunk-1');
      expect(chunk.materialId, 'mat-1');
      expect(chunk.idx, 0);
      expect(chunk.content, 'Hello World');
    });

    test('equality works', () {
      const a = MaterialChunk(
        id: '1',
        materialId: 'm1',
        idx: 0,
        content: 'text',
      );
      const b = MaterialChunk(
        id: '1',
        materialId: 'm1',
        idx: 0,
        content: 'text',
      );
      expect(a, equals(b));
    });
  });

  group('ProgressSnapshot Model', () {
    test('parses from JSON correctly', () {
      final json = {
        'id': 'prog-1',
        'user_id': 'user-1',
        'period_type': 'weekly',
        'period_start': '2025-01-13',
        'stats': {
          'completed_topics': 5,
          'total_topics': 20,
          'study_minutes': 120,
        },
        'computed_at': '2025-01-15T10:30:00Z',
      };
      final snapshot = ProgressSnapshot.fromJson(json);
      expect(snapshot.id, 'prog-1');
      expect(snapshot.periodType, 'weekly');
      expect(snapshot.completedTopics, 5);
      expect(snapshot.totalTopics, 20);
      expect(snapshot.studyMinutes, 120);
      expect(snapshot.completionPercentage, 25.0);
    });

    test('defaults for missing stats', () {
      final json = {
        'id': 'prog-1',
        'user_id': 'user-1',
        'period_type': 'weekly',
        'period_start': '2025-01-13',
        'stats': {},
        'computed_at': '2025-01-15T10:30:00Z',
      };
      final snapshot = ProgressSnapshot.fromJson(json);
      expect(snapshot.completedTopics, 0);
      expect(snapshot.totalTopics, 0);
      expect(snapshot.studyMinutes, 0);
      expect(snapshot.completionPercentage, 0.0);
    });

    test('handles null stats', () {
      final json = {
        'id': 'prog-1',
        'user_id': 'user-1',
        'period_type': 'weekly',
        'period_start': '2025-01-13',
        'stats': null,
        'computed_at': '2025-01-15T10:30:00Z',
      };
      final snapshot = ProgressSnapshot.fromJson(json);
      expect(snapshot.completedTopics, 0);
      expect(snapshot.totalTopics, 0);
    });
  });

  group('MaterialService', () {
    test('getFullContent joins chunks in order', () {
      final chunks = [
        const MaterialChunk(id: '1', materialId: 'm1', idx: 2, content: 'C'),
        const MaterialChunk(id: '2', materialId: 'm1', idx: 0, content: 'A'),
        const MaterialChunk(id: '3', materialId: 'm1', idx: 1, content: 'B'),
      ];
      final content = MaterialService.getFullContent(chunks);
      expect(content, 'A\n\nB\n\nC');
    });

    test('getFullContent handles empty list', () {
      final content = MaterialService.getFullContent([]);
      expect(content, isEmpty);
    });
  });

  group('ProfileStatus', () {
    test('has all expected states', () {
      expect(
        ProfileStatus.values,
        containsAll([
          ProfileStatus.initial,
          ProfileStatus.loading,
          ProfileStatus.loaded,
          ProfileStatus.error,
          ProfileStatus.empty,
        ]),
      );
    });
  });

  group('SplashScreen', () {
    testWidgets('renders correctly', (WidgetTester tester) async {
      await tester.pumpWidget(wrapWithApp(const SplashScreen()));
      expect(find.text('My Preparation'), findsOneWidget);
      expect(find.byIcon(Icons.school), findsOneWidget);
    });
  });

  group('LoginScreen', () {
    testWidgets('renders email and password fields', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(wrapWithApp(const LoginScreen()));
      expect(find.byType(TextFormField), findsNWidgets(2));
      expect(find.text('Sign In'), findsOneWidget);
    });

    testWidgets('shows validation errors for empty fields', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(wrapWithApp(const LoginScreen()));
      await tester.tap(find.text('Sign In'));
      await tester.pump();
      expect(find.text('Please enter your email'), findsOneWidget);
      expect(find.text('Please enter your password'), findsOneWidget);
    });

    testWidgets('shows validation error for invalid email', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(wrapWithApp(const LoginScreen()));
      await tester.enterText(find.byType(TextFormField).first, 'invalid-email');
      await tester.tap(find.text('Sign In'));
      await tester.pump();
      expect(find.text('Please enter a valid email address'), findsOneWidget);
    });

    testWidgets('shows validation error for short password', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(wrapWithApp(const LoginScreen()));
      await tester.enterText(
        find.byType(TextFormField).first,
        'test@example.com',
      );
      await tester.enterText(find.byType(TextFormField).last, '123');
      await tester.tap(find.text('Sign In'));
      await tester.pump();
      expect(
        find.text('Password must be at least 6 characters'),
        findsOneWidget,
      );
    });
  });

  group('SignUpScreen', () {
    testWidgets('renders all form fields', (WidgetTester tester) async {
      await tester.pumpWidget(wrapWithApp(const SignUpScreen()));
      expect(find.byType(TextFormField), findsNWidgets(3));
      expect(find.byType(ElevatedButton), findsOneWidget);
    });

    testWidgets('shows validation errors for empty fields', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(wrapWithApp(const SignUpScreen()));
      await tester.tap(find.byType(ElevatedButton));
      await tester.pump();
      expect(find.text('Please enter your email'), findsOneWidget);
      expect(find.text('Please enter your password'), findsOneWidget);
      expect(find.text('Please confirm your password'), findsOneWidget);
    });

    testWidgets('shows password mismatch error', (WidgetTester tester) async {
      await tester.pumpWidget(wrapWithApp(const SignUpScreen()));
      await tester.enterText(
        find.byType(TextFormField).first,
        'test@example.com',
      );
      await tester.enterText(find.byType(TextFormField).at(1), 'password123');
      await tester.enterText(find.byType(TextFormField).at(2), 'password456');
      await tester.tap(find.byType(ElevatedButton));
      await tester.pump();
      expect(find.text('Passwords do not match'), findsOneWidget);
    });
  });
}
