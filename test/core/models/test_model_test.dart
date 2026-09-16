import 'package:flutter_test/flutter_test.dart';
import 'package:my_praperation/core/models/test.dart';

void main() {
  group('Test model', () {
    test('parses status from JSON correctly', () {
      final test = Test.fromJson({
        'id': '1',
        'created_by': 'user-1',
        'title': 'Test',
        'status': 'draft',
      });
      expect(test.status, TestStatus.draft);
    });

    test('parses all status values', () {
      final statuses = {
        'draft': TestStatus.draft,
        'scheduled': TestStatus.scheduled,
        'live': TestStatus.live,
        'ready': TestStatus.ready,
        'published': TestStatus.published,
        'completed': TestStatus.completed,
        'ended': TestStatus.ended,
        'evaluated': TestStatus.evaluated,
        'cancelled': TestStatus.cancelled,
        'archived': TestStatus.archived,
        'expired': TestStatus.expired,
        'unknown': TestStatus.unknown,
      };

      for (final entry in statuses.entries) {
        final test = Test.fromJson({
          'id': '1',
          'created_by': 'user-1',
          'title': 'Test',
          'status': entry.key,
        });
        expect(test.status, entry.value, reason: 'Failed for status: ${entry.key}');
      }
    });

    test('defaults to unknown for invalid status', () {
      final test = Test.fromJson({
        'id': '1',
        'created_by': 'user-1',
        'title': 'Test',
        'status': 'invalid_status',
      });
      expect(test.status, TestStatus.unknown);
    });

    test('isScheduled returns true for scheduled status', () {
      final test = Test.fromJson({
        'id': '1',
        'created_by': 'user-1',
        'title': 'Test',
        'status': 'scheduled',
      });
      expect(test.isScheduled, true);
    });

    test('isLive returns true for live status', () {
      final test = Test.fromJson({
        'id': '1',
        'created_by': 'user-1',
        'title': 'Test',
        'status': 'live',
      });
      expect(test.isLive, true);
    });

    test('isCompleted returns true for completed and ended', () {
      final completed = Test.fromJson({
        'id': '1',
        'created_by': 'user-1',
        'title': 'Test',
        'status': 'completed',
      });
      expect(completed.isCompleted, true);

      final ended = Test.fromJson({
        'id': '2',
        'created_by': 'user-1',
        'title': 'Test',
        'status': 'ended',
      });
      expect(ended.isCompleted, true);
    });

    test('isActive returns true for active statuses', () {
      final activeStatuses = ['scheduled', 'live', 'ready', 'published'];
      for (final status in activeStatuses) {
        final test = Test.fromJson({
          'id': '1',
          'created_by': 'user-1',
          'title': 'Test',
          'status': status,
        });
        expect(test.isActive, true, reason: 'Failed for status: $status');
      }
    });

    test('isActive returns false for non-active statuses', () {
      final inactiveStatuses = ['draft', 'completed', 'ended', 'cancelled'];
      for (final status in inactiveStatuses) {
        final test = Test.fromJson({
          'id': '1',
          'created_by': 'user-1',
          'title': 'Test',
          'status': status,
        });
        expect(test.isActive, false, reason: 'Failed for status: $status');
      }
    });

    test('parses testMode correctly', () {
      final test = Test.fromJson({
        'id': '1',
        'created_by': 'user-1',
        'title': 'Test',
        'status': 'published',
        'test_mode': 'live',
      });
      expect(test.testMode, 'live');
    });

    test('parses datetime fields correctly', () {
      final now = DateTime.now();
      final test = Test.fromJson({
        'id': '1',
        'created_by': 'user-1',
        'title': 'Test',
        'status': 'published',
        'starts_at': now.toIso8601String(),
        'ends_at': now.add(const Duration(hours: 1)).toIso8601String(),
      });
      expect(test.startsAt, isNotNull);
      expect(test.endsAt, isNotNull);
      expect(test.endsAt!.isAfter(test.startsAt!), true);
    });

    test('handles null optional fields', () {
      final test = Test.fromJson({
        'id': '1',
        'created_by': 'user-1',
        'title': 'Test',
        'status': 'draft',
      });
      expect(test.description, isNull);
      expect(test.durationSec, isNull);
      expect(test.marksPerQuestion, isNull);
      expect(test.negativeMarks, isNull);
      expect(test.startsAt, isNull);
      expect(test.endsAt, isNull);
      expect(test.groupId, isNull);
      expect(test.testMode, isNull);
    });

    test('equality is based on id, createdBy, title, status', () {
      final test1 = Test.fromJson({
        'id': '1',
        'created_by': 'user-1',
        'title': 'Test',
        'status': 'draft',
      });
      final test2 = Test.fromJson({
        'id': '1',
        'created_by': 'user-1',
        'title': 'Test',
        'status': 'draft',
      });
      expect(test1, test2);

      final test3 = Test.fromJson({
        'id': '2',
        'created_by': 'user-1',
        'title': 'Test',
        'status': 'draft',
      });
      expect(test1 == test3, false);
    });

    test('toJson produces valid JSON', () {
      final now = DateTime(2026, 1, 15, 10, 30);
      final test = Test(
        id: '1',
        createdBy: 'user-1',
        title: 'My Test',
        description: 'A description',
        status: TestStatus.draft,
        durationSec: 3600,
        marksPerQuestion: 4.0,
        testMode: 'self',
        createdAt: now,
      );
      final json = test.toJson();
      expect(json['id'], '1');
      expect(json['created_by'], 'user-1');
      expect(json['title'], 'My Test');
      expect(json['description'], 'A description');
      expect(json['status'], 'draft');
      expect(json['duration_sec'], 3600);
      expect(json['marks_per_question'], 4.0);
      expect(json['test_mode'], 'self');
    });
  });
}
