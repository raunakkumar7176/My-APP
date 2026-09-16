import 'package:flutter_test/flutter_test.dart';
import 'package:my_praperation/core/models/test.dart';

/// Mirrors the filtering logic from TestListingScreen
class TestCategoryFilter {
  static bool isUpcoming(Test test, DateTime now) {
    if (test.isSoftDeleted) return false;
    switch (test.status) {
      case TestStatus.scheduled:
        return true;
      case TestStatus.published:
        if (test.startsAt != null && test.startsAt!.isAfter(now)) {
          return true;
        }
        return false;
      default:
        return false;
    }
  }

  static bool isChallengeWithFriends(Test test, DateTime now) {
    if (test.isSoftDeleted) return false;
    if (test.testMode != 'live') return false;
    switch (test.status) {
      case TestStatus.live:
      case TestStatus.ready:
        return true;
      case TestStatus.published:
        if (test.startsAt != null && test.startsAt!.isAfter(now)) {
          return false;
        }
        if (test.endsAt != null && test.endsAt!.isBefore(now)) {
          return false;
        }
        return true;
      case TestStatus.scheduled:
        return false;
      default:
        return false;
    }
  }

  static bool isPrevious(Test test, DateTime now) {
    if (test.isSoftDeleted) return false;
    switch (test.status) {
      case TestStatus.completed:
      case TestStatus.ended:
      case TestStatus.evaluated:
      case TestStatus.cancelled:
      case TestStatus.archived:
      case TestStatus.expired:
        return true;
      case TestStatus.published:
        if (test.endsAt != null && test.endsAt!.isBefore(now)) {
          return true;
        }
        return false;
      case TestStatus.live:
      case TestStatus.ready:
        if (test.endsAt != null && test.endsAt!.isBefore(now)) {
          return true;
        }
        return false;
      default:
        return false;
    }
  }

  static bool isMyDraft(Test test) {
    return test.status == TestStatus.draft;
  }
}

Test _createTest({
  required String status,
  String? testMode,
  DateTime? startsAt,
  DateTime? endsAt,
  bool isSoftDeleted = false,
}) {
  return Test.fromJson({
    'id': 'test-1',
    'created_by': 'user-1',
    'title': 'Test',
    'status': status,
    'test_mode': testMode,
    'starts_at': startsAt?.toIso8601String(),
    'ends_at': endsAt?.toIso8601String(),
    'is_soft_deleted': isSoftDeleted,
  });
}

void main() {
  final now = DateTime(2026, 9, 14, 12, 0);
  final past = now.subtract(const Duration(days: 1));
  final future = now.add(const Duration(days: 1));

  group('Upcoming category', () {
    test('scheduled tests are upcoming', () {
      final test = _createTest(status: 'scheduled');
      expect(TestCategoryFilter.isUpcoming(test, now), true);
    });

    test('published tests with future start are upcoming', () {
      final test = _createTest(status: 'published', startsAt: future);
      expect(TestCategoryFilter.isUpcoming(test, now), true);
    });

    test('published tests without start are not upcoming', () {
      final test = _createTest(status: 'published');
      expect(TestCategoryFilter.isUpcoming(test, now), false);
    });

    test('published tests with past start are not upcoming', () {
      final test = _createTest(status: 'published', startsAt: past);
      expect(TestCategoryFilter.isUpcoming(test, now), false);
    });

    test('draft tests are not upcoming', () {
      final test = _createTest(status: 'draft');
      expect(TestCategoryFilter.isUpcoming(test, now), false);
    });

    test('live tests are not upcoming', () {
      final test = _createTest(status: 'live');
      expect(TestCategoryFilter.isUpcoming(test, now), false);
    });

    test('completed tests are not upcoming', () {
      final test = _createTest(status: 'completed');
      expect(TestCategoryFilter.isUpcoming(test, now), false);
    });

    test('soft deleted tests are not upcoming', () {
      final test = _createTest(status: 'scheduled', isSoftDeleted: true);
      expect(TestCategoryFilter.isUpcoming(test, now), false);
    });
  });

  group('Challenge with Friends category', () {
    test('live mode published test within window is challenge', () {
      final test = _createTest(
        status: 'published',
        testMode: 'live',
        startsAt: past,
        endsAt: future,
      );
      expect(TestCategoryFilter.isChallengeWithFriends(test, now), true);
    });

    test('live mode published test with no times is challenge', () {
      final test = _createTest(status: 'published', testMode: 'live');
      expect(TestCategoryFilter.isChallengeWithFriends(test, now), true);
    });

    test('live status test with live mode is challenge', () {
      final test = _createTest(status: 'live', testMode: 'live');
      expect(TestCategoryFilter.isChallengeWithFriends(test, now), true);
    });

    test('ready status test with live mode is challenge', () {
      final test = _createTest(status: 'ready', testMode: 'live');
      expect(TestCategoryFilter.isChallengeWithFriends(test, now), true);
    });

    test('self mode tests are not challenge', () {
      final test = _createTest(status: 'published', testMode: 'self');
      expect(TestCategoryFilter.isChallengeWithFriends(test, now), false);
    });

    test('group mode tests are not challenge', () {
      final test = _createTest(status: 'published', testMode: 'group');
      expect(TestCategoryFilter.isChallengeWithFriends(test, now), false);
    });

    test('published test with future start is not challenge', () {
      final test = _createTest(
        status: 'published',
        testMode: 'live',
        startsAt: future,
      );
      expect(TestCategoryFilter.isChallengeWithFriends(test, now), false);
    });

    test('published test with past end is not challenge', () {
      final test = _createTest(
        status: 'published',
        testMode: 'live',
        startsAt: past,
        endsAt: past,
      );
      expect(TestCategoryFilter.isChallengeWithFriends(test, now), false);
    });

    test('scheduled live mode is not challenge', () {
      final test = _createTest(status: 'scheduled', testMode: 'live');
      expect(TestCategoryFilter.isChallengeWithFriends(test, now), false);
    });

    test('soft deleted test is not challenge', () {
      final test = _createTest(
        status: 'live',
        testMode: 'live',
        isSoftDeleted: true,
      );
      expect(TestCategoryFilter.isChallengeWithFriends(test, now), false);
    });
  });

  group('Previous category', () {
    test('completed tests are previous', () {
      final test = _createTest(status: 'completed');
      expect(TestCategoryFilter.isPrevious(test, now), true);
    });

    test('ended tests are previous', () {
      final test = _createTest(status: 'ended');
      expect(TestCategoryFilter.isPrevious(test, now), true);
    });

    test('evaluated tests are previous', () {
      final test = _createTest(status: 'evaluated');
      expect(TestCategoryFilter.isPrevious(test, now), true);
    });

    test('cancelled tests are previous', () {
      final test = _createTest(status: 'cancelled');
      expect(TestCategoryFilter.isPrevious(test, now), true);
    });

    test('archived tests are previous', () {
      final test = _createTest(status: 'archived');
      expect(TestCategoryFilter.isPrevious(test, now), true);
    });

    test('expired tests are previous', () {
      final test = _createTest(status: 'expired');
      expect(TestCategoryFilter.isPrevious(test, now), true);
    });

    test('published tests with past end are previous', () {
      final test = _createTest(
        status: 'published',
        endsAt: past,
      );
      expect(TestCategoryFilter.isPrevious(test, now), true);
    });

    test('published tests without end are not previous', () {
      final test = _createTest(status: 'published');
      expect(TestCategoryFilter.isPrevious(test, now), false);
    });

    test('live tests with past end are previous', () {
      final test = _createTest(
        status: 'live',
        endsAt: past,
      );
      expect(TestCategoryFilter.isPrevious(test, now), true);
    });

    test('draft tests are not previous', () {
      final test = _createTest(status: 'draft');
      expect(TestCategoryFilter.isPrevious(test, now), false);
    });

    test('scheduled tests are not previous', () {
      final test = _createTest(status: 'scheduled');
      expect(TestCategoryFilter.isPrevious(test, now), false);
    });

    test('soft deleted tests are not previous', () {
      final test = _createTest(status: 'completed', isSoftDeleted: true);
      expect(TestCategoryFilter.isPrevious(test, now), false);
    });
  });

  group('My Drafts category', () {
    test('draft tests are drafts', () {
      final test = _createTest(status: 'draft');
      expect(TestCategoryFilter.isMyDraft(test), true);
    });

    test('published tests are not drafts', () {
      final test = _createTest(status: 'published');
      expect(TestCategoryFilter.isMyDraft(test), false);
    });

    test('live tests are not drafts', () {
      final test = _createTest(status: 'live');
      expect(TestCategoryFilter.isMyDraft(test), false);
    });

    test('completed tests are not drafts', () {
      final test = _createTest(status: 'completed');
      expect(TestCategoryFilter.isMyDraft(test), false);
    });
  });

  group('Test mode text mapping', () {
    test('self maps to Self', () {
      expect(_getTestModeText('self'), 'Self');
    });

    test('live maps to Challenge with Friends', () {
      expect(_getTestModeText('live'), 'Challenge with Friends');
    });

    test('group maps to Group Test', () {
      expect(_getTestModeText('group'), 'Group Test');
    });

    test('unknown mode returns mode as-is', () {
      expect(_getTestModeText('custom'), 'custom');
    });

    test('null returns mode as-is', () {
      expect(_getTestModeText(null), 'null');
    });
  });

  group('Start test disabled reasons', () {
    test('draft test has disabled reason', () {
      final test = _createTest(status: 'draft');
      final reason = _getStartTestDisabledReason(test, now);
      expect(reason, isNotNull);
      expect(reason!.contains('draft'), true);
    });

    test('scheduled test with future start has disabled reason', () {
      final test = _createTest(status: 'scheduled', startsAt: future);
      final reason = _getStartTestDisabledReason(test, now);
      expect(reason, isNotNull);
      expect(reason!.contains('not started yet'), true);
    });

    test('scheduled test without start can start', () {
      final test = _createTest(status: 'scheduled');
      final reason = _getStartTestDisabledReason(test, now);
      expect(reason, isNull);
    });

    test('published test with future start has disabled reason', () {
      final test = _createTest(status: 'published', startsAt: future);
      final reason = _getStartTestDisabledReason(test, now);
      expect(reason, isNotNull);
      expect(reason!.contains('not started yet'), true);
    });

    test('published test with past end has disabled reason', () {
      final test = _createTest(status: 'published', endsAt: past);
      final reason = _getStartTestDisabledReason(test, now);
      expect(reason, isNotNull);
      expect(reason!.contains('ended'), true);
    });

    test('published test in window can start', () {
      final test = _createTest(
        status: 'published',
        startsAt: past,
        endsAt: future,
      );
      final reason = _getStartTestDisabledReason(test, now);
      expect(reason, isNull);
    });

    test('live test can start', () {
      final test = _createTest(status: 'live');
      final reason = _getStartTestDisabledReason(test, now);
      expect(reason, isNull);
    });

    test('live test with past end has disabled reason', () {
      final test = _createTest(status: 'live', endsAt: past);
      final reason = _getStartTestDisabledReason(test, now);
      expect(reason, isNotNull);
      expect(reason!.contains('ended'), true);
    });

    test('completed test has disabled reason', () {
      final test = _createTest(status: 'completed');
      final reason = _getStartTestDisabledReason(test, now);
      expect(reason, isNotNull);
      expect(reason!.contains('ended'), true);
    });

    test('cancelled test has disabled reason', () {
      final test = _createTest(status: 'cancelled');
      final reason = _getStartTestDisabledReason(test, now);
      expect(reason, isNotNull);
      expect(reason!.contains('cancelled'), true);
    });

    test('archived test has disabled reason', () {
      final test = _createTest(status: 'archived');
      final reason = _getStartTestDisabledReason(test, now);
      expect(reason, isNotNull);
      expect(reason!.contains('archived'), true);
    });

    test('expired test has disabled reason', () {
      final test = _createTest(status: 'expired');
      final reason = _getStartTestDisabledReason(test, now);
      expect(reason, isNotNull);
      expect(reason!.contains('expired'), true);
    });
  });
}

String _getTestModeText(String? mode) {
  switch (mode) {
    case 'self':
      return 'Self';
    case 'live':
      return 'Challenge with Friends';
    case 'group':
      return 'Group Test';
    default:
      return '$mode';
  }
}

String? _getStartTestDisabledReason(Test test, DateTime now) {
  switch (test.status) {
    case TestStatus.draft:
      return 'This test is still a draft.';
    case TestStatus.scheduled:
      if (test.startsAt != null && test.startsAt!.isAfter(now)) {
        return 'Test has not started yet.';
      }
      return null;
    case TestStatus.published:
      if (test.startsAt != null && test.startsAt!.isAfter(now)) {
        return 'Test has not started yet.';
      }
      if (test.endsAt != null && test.endsAt!.isBefore(now)) {
        return 'This test has ended.';
      }
      return null;
    case TestStatus.live:
    case TestStatus.ready:
      if (test.endsAt != null && test.endsAt!.isBefore(now)) {
        return 'This test has ended.';
      }
      return null;
    case TestStatus.completed:
    case TestStatus.ended:
    case TestStatus.evaluated:
      return 'This test has ended.';
    case TestStatus.cancelled:
      return 'This test has been cancelled.';
    case TestStatus.archived:
      return 'This test has been archived and is no longer available.';
    case TestStatus.expired:
      return 'This test has expired and is no longer available.';
    case TestStatus.unknown:
      return 'This test is in an unknown state.';
  }
}
