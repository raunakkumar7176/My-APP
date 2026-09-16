import 'package:flutter_test/flutter_test.dart';

import 'package:my_praperation/core/models/test.dart';

/// Pure-logic mirrors of classification rules from test_listing_screen.dart.
/// These allow unit testing without widget pumping.
bool isListingUpcoming(Test test, DateTime now) {
  switch (test.status) {
    case TestStatus.scheduled:
      return true;
    case TestStatus.published:
      if (test.startsAt != null && test.startsAt!.isAfter(now)) {
        return true;
      }
      if (test.testMode == 'self' || test.testMode == 'group') {
        final ended = test.endsAt != null && test.endsAt!.isBefore(now);
        return !ended;
      }
      return false;
    default:
      return false;
  }
}

bool isListingLive(Test test, DateTime now) {
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
    default:
      return false;
  }
}

bool isListingPrevious(Test test, DateTime now) {
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
    default:
      return false;
  }
}

/// Pure-logic mirror of _getStartTestDisabledReason from test_detail_screen.dart.
String? getStartTestDisabledReason(Test test) {
  final now = DateTime.now();
  switch (test.status) {
    case TestStatus.draft:
      return 'This test is still a draft.';
    case TestStatus.scheduled:
      if (test.startsAt != null && test.startsAt!.isAfter(now)) {
        return 'This test has not started yet.';
      }
      return null;
    case TestStatus.published:
      if (test.startsAt != null && test.startsAt!.isAfter(now)) {
        return 'This test has not started yet.';
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
    case TestStatus.expired:
      return 'This test is no longer available.';
    case TestStatus.unknown:
      return 'This test is in an unknown state.';
  }
}

/// Pure-logic mirror of _canEdit from test_detail_screen.dart.
bool canEditTest({
  required String? currentUserId,
  required String createdBy,
  required TestStatus status,
  required DateTime? startsAt,
}) {
  if (currentUserId == null) return false;
  if (createdBy != currentUserId) return false;
  // Drafts only: the edit screen rejects every other status (P1-2 fix).
  return status == TestStatus.draft;
}

/// Test-mode display text mapping.
String getTestModeDisplayText(String? mode) {
  switch (mode) {
    case 'self':
      return 'Self Practice';
    case 'live':
      return 'Challenge with Friends';
    case 'group':
      return 'Group Test';
    default:
      return '--';
  }
}

Test makeTest({
  TestStatus status = TestStatus.published,
  DateTime? startsAt,
  DateTime? endsAt,
  String? testMode,
  String createdBy = 'user-1',
}) {
  return Test(
    id: 'test-1',
    createdBy: createdBy,
    title: 'Test',
    status: status,
    startsAt: startsAt,
    endsAt: endsAt,
    testMode: testMode,
  );
}

void main() {
  final now = DateTime.now();

  group('Listing classification — upcoming', () {
    test('scheduled test is upcoming', () {
      final test = makeTest(status: TestStatus.scheduled);
      expect(isListingUpcoming(test, now), true);
    });

    test('published test with future starts_at is upcoming', () {
      final test = makeTest(
        status: TestStatus.published,
        startsAt: now.add(const Duration(hours: 1)),
      );
      expect(isListingUpcoming(test, now), true);
    });

    test('published test with past starts_at is not upcoming', () {
      final test = makeTest(
        status: TestStatus.published,
        startsAt: now.subtract(const Duration(hours: 1)),
      );
      expect(isListingUpcoming(test, now), false);
    });

    test('published test with null starts_at is not upcoming', () {
      final test = makeTest(status: TestStatus.published, startsAt: null);
      expect(isListingUpcoming(test, now), false);
    });

    test('draft test is not upcoming', () {
      final test = makeTest(status: TestStatus.draft);
      expect(isListingUpcoming(test, now), false);
    });

    test('self mode published with past starts_at and no ends_at is upcoming', () {
      final test = makeTest(
        status: TestStatus.published,
        testMode: 'self',
        startsAt: now.subtract(const Duration(hours: 1)),
        endsAt: null,
      );
      expect(isListingUpcoming(test, now), true);
    });

    test('self mode published with active window is upcoming', () {
      final test = makeTest(
        status: TestStatus.published,
        testMode: 'self',
        startsAt: now.subtract(const Duration(hours: 1)),
        endsAt: now.add(const Duration(hours: 1)),
      );
      expect(isListingUpcoming(test, now), true);
    });

    test('self mode published with past ends_at is NOT upcoming', () {
      final test = makeTest(
        status: TestStatus.published,
        testMode: 'self',
        startsAt: now.subtract(const Duration(hours: 2)),
        endsAt: now.subtract(const Duration(hours: 1)),
      );
      expect(isListingUpcoming(test, now), false);
    });

    test('group mode published with past starts_at and no ends_at is upcoming', () {
      final test = makeTest(
        status: TestStatus.published,
        testMode: 'group',
        startsAt: now.subtract(const Duration(hours: 1)),
        endsAt: null,
      );
      expect(isListingUpcoming(test, now), true);
    });

    test('group mode published with active window is upcoming', () {
      final test = makeTest(
        status: TestStatus.published,
        testMode: 'group',
        startsAt: now.subtract(const Duration(hours: 1)),
        endsAt: now.add(const Duration(hours: 1)),
      );
      expect(isListingUpcoming(test, now), true);
    });

    test('group mode published with past ends_at is NOT upcoming', () {
      final test = makeTest(
        status: TestStatus.published,
        testMode: 'group',
        startsAt: now.subtract(const Duration(hours: 2)),
        endsAt: now.subtract(const Duration(hours: 1)),
      );
      expect(isListingUpcoming(test, now), false);
    });

    test('live mode published with past starts_at is NOT upcoming (stays in challenge tab)', () {
      final test = makeTest(
        status: TestStatus.published,
        testMode: 'live',
        startsAt: now.subtract(const Duration(hours: 1)),
        endsAt: now.add(const Duration(hours: 1)),
      );
      expect(isListingUpcoming(test, now), false);
    });

    test('null mode published with past starts_at is NOT upcoming', () {
      final test = makeTest(
        status: TestStatus.published,
        testMode: null,
        startsAt: now.subtract(const Duration(hours: 1)),
        endsAt: now.add(const Duration(hours: 1)),
      );
      expect(isListingUpcoming(test, now), false);
    });
  });

  group('Listing classification — live/startable', () {
    test('live status with testMode live is always live', () {
      final test = makeTest(status: TestStatus.live, testMode: 'live');
      expect(isListingLive(test, now), true);
    });

    test('ready status with testMode live is always live', () {
      final test = makeTest(status: TestStatus.ready, testMode: 'live');
      expect(isListingLive(test, now), true);
    });

    test('live status without testMode is NOT in challenge tab', () {
      final test = makeTest(status: TestStatus.live, testMode: null);
      expect(isListingLive(test, now), false);
    });

    test('published with null starts_at and testMode live is live (available immediately)', () {
      final test = makeTest(
        status: TestStatus.published,
        testMode: 'live',
        startsAt: null,
        endsAt: null,
      );
      expect(isListingLive(test, now), true);
    });

    test('published with past starts_at and no ends_at and testMode live is live', () {
      final test = makeTest(
        status: TestStatus.published,
        testMode: 'live',
        startsAt: now.subtract(const Duration(hours: 1)),
        endsAt: null,
      );
      expect(isListingLive(test, now), true);
    });

    test('published with future starts_at is not live', () {
      final test = makeTest(
        status: TestStatus.published,
        testMode: 'live',
        startsAt: now.add(const Duration(hours: 1)),
      );
      expect(isListingLive(test, now), false);
    });

    test('published with past ends_at is not live', () {
      final test = makeTest(
        status: TestStatus.published,
        testMode: 'live',
        startsAt: now.subtract(const Duration(hours: 2)),
        endsAt: now.subtract(const Duration(hours: 1)),
      );
      expect(isListingLive(test, now), false);
    });

    test('draft is not live', () {
      final test = makeTest(status: TestStatus.draft, testMode: 'live');
      expect(isListingLive(test, now), false);
    });

    test('scheduled is not live', () {
      final test = makeTest(status: TestStatus.scheduled, testMode: 'live');
      expect(isListingLive(test, now), false);
    });

    test('self mode published is NOT in challenge tab', () {
      final test = makeTest(
        status: TestStatus.published,
        testMode: 'self',
        startsAt: now.subtract(const Duration(hours: 1)),
        endsAt: now.add(const Duration(hours: 1)),
      );
      expect(isListingLive(test, now), false);
    });

    test('group mode published is NOT in challenge tab', () {
      final test = makeTest(
        status: TestStatus.published,
        testMode: 'group',
        startsAt: now.subtract(const Duration(hours: 1)),
        endsAt: now.add(const Duration(hours: 1)),
      );
      expect(isListingLive(test, now), false);
    });
  });

  group('Listing classification — previous', () {
    for (final status in [
      TestStatus.completed,
      TestStatus.ended,
      TestStatus.evaluated,
      TestStatus.cancelled,
      TestStatus.archived,
      TestStatus.expired,
    ]) {
      test('$status is previous', () {
        final test = makeTest(status: status);
        expect(isListingPrevious(test, now), true);
      });
    }

    test('published with past ends_at is previous', () {
      final test = makeTest(
        status: TestStatus.published,
        endsAt: now.subtract(const Duration(hours: 1)),
      );
      expect(isListingPrevious(test, now), true);
    });

    test('published with null ends_at is not previous', () {
      final test = makeTest(status: TestStatus.published, endsAt: null);
      expect(isListingPrevious(test, now), false);
    });

    test('published with future ends_at is not previous', () {
      final test = makeTest(
        status: TestStatus.published,
        endsAt: now.add(const Duration(hours: 1)),
      );
      expect(isListingPrevious(test, now), false);
    });

    test('draft is not previous', () {
      final test = makeTest(status: TestStatus.draft);
      expect(isListingPrevious(test, now), false);
    });
  });

  group('Listing mutual exclusion', () {
    test('published with null starts_at and testMode live appears in live only', () {
      final test = makeTest(
        status: TestStatus.published,
        testMode: 'live',
        startsAt: null,
        endsAt: null,
      );
      expect(isListingUpcoming(test, now), false);
      expect(isListingLive(test, now), true);
      expect(isListingPrevious(test, now), false);
    });

    test('published with future starts_at appears in upcoming only', () {
      final test = makeTest(
        status: TestStatus.published,
        testMode: 'live',
        startsAt: now.add(const Duration(hours: 1)),
      );
      expect(isListingUpcoming(test, now), true);
      expect(isListingLive(test, now), false);
      expect(isListingPrevious(test, now), false);
    });

    test('published with active window and testMode live appears in live only', () {
      final test = makeTest(
        status: TestStatus.published,
        testMode: 'live',
        startsAt: now.subtract(const Duration(hours: 1)),
        endsAt: now.add(const Duration(hours: 1)),
      );
      expect(isListingUpcoming(test, now), false);
      expect(isListingLive(test, now), true);
      expect(isListingPrevious(test, now), false);
    });

    test('published with past ends_at appears in previous only', () {
      final test = makeTest(
        status: TestStatus.published,
        startsAt: now.subtract(const Duration(hours: 2)),
        endsAt: now.subtract(const Duration(hours: 1)),
      );
      expect(isListingUpcoming(test, now), false);
      expect(isListingLive(test, now), false);
      expect(isListingPrevious(test, now), true);
    });

    test('self mode published with active window appears in upcoming only (not live)', () {
      final test = makeTest(
        status: TestStatus.published,
        testMode: 'self',
        startsAt: now.subtract(const Duration(hours: 1)),
        endsAt: now.add(const Duration(hours: 1)),
      );
      expect(isListingUpcoming(test, now), true);
      expect(isListingLive(test, now), false);
      expect(isListingPrevious(test, now), false);
    });

    test('group mode published with active window appears in upcoming only (not live)', () {
      final test = makeTest(
        status: TestStatus.published,
        testMode: 'group',
        startsAt: now.subtract(const Duration(hours: 1)),
        endsAt: now.add(const Duration(hours: 1)),
      );
      expect(isListingUpcoming(test, now), true);
      expect(isListingLive(test, now), false);
      expect(isListingPrevious(test, now), false);
    });

    test('self mode published with no ends_at appears in upcoming only', () {
      final test = makeTest(
        status: TestStatus.published,
        testMode: 'self',
        startsAt: now.subtract(const Duration(hours: 1)),
        endsAt: null,
      );
      expect(isListingUpcoming(test, now), true);
      expect(isListingLive(test, now), false);
      expect(isListingPrevious(test, now), false);
    });

    test('self mode published with past ends_at appears in previous only', () {
      final test = makeTest(
        status: TestStatus.published,
        testMode: 'self',
        startsAt: now.subtract(const Duration(hours: 2)),
        endsAt: now.subtract(const Duration(hours: 1)),
      );
      expect(isListingUpcoming(test, now), false);
      expect(isListingLive(test, now), false);
      expect(isListingPrevious(test, now), true);
    });

    test('live mode published with active window still appears in live (not upcoming)', () {
      final test = makeTest(
        status: TestStatus.published,
        testMode: 'live',
        startsAt: now.subtract(const Duration(hours: 1)),
        endsAt: now.add(const Duration(hours: 1)),
      );
      expect(isListingUpcoming(test, now), false);
      expect(isListingLive(test, now), true);
      expect(isListingPrevious(test, now), false);
    });
  });

  group('Start Test disabled reason', () {
    test('draft returns draft reason', () {
      final test = makeTest(status: TestStatus.draft);
      expect(getStartTestDisabledReason(test), 'This test is still a draft.');
    });

    test('published with null starts_at is startable (no reason)', () {
      final test = makeTest(
        status: TestStatus.published,
        startsAt: null,
        endsAt: null,
      );
      expect(getStartTestDisabledReason(test), isNull);
    });

    test('published with future starts_at returns not-started reason', () {
      final test = makeTest(
        status: TestStatus.published,
        startsAt: now.add(const Duration(hours: 1)),
      );
      expect(
        getStartTestDisabledReason(test),
        'This test has not started yet.',
      );
    });

    test('published with past ends_at returns ended reason', () {
      final test = makeTest(
        status: TestStatus.published,
        startsAt: now.subtract(const Duration(hours: 2)),
        endsAt: now.subtract(const Duration(hours: 1)),
      );
      expect(getStartTestDisabledReason(test), 'This test has ended.');
    });

    test('live with past ends_at returns ended reason', () {
      final test = makeTest(
        status: TestStatus.live,
        endsAt: now.subtract(const Duration(hours: 1)),
      );
      expect(getStartTestDisabledReason(test), 'This test has ended.');
    });

    test('live with null ends_at is startable', () {
      final test = makeTest(status: TestStatus.live, endsAt: null);
      expect(getStartTestDisabledReason(test), isNull);
    });

    test('completed returns ended reason', () {
      final test = makeTest(status: TestStatus.completed);
      expect(getStartTestDisabledReason(test), 'This test has ended.');
    });

    test('ended returns ended reason', () {
      final test = makeTest(status: TestStatus.ended);
      expect(getStartTestDisabledReason(test), 'This test has ended.');
    });

    test('evaluated returns ended reason', () {
      final test = makeTest(status: TestStatus.evaluated);
      expect(getStartTestDisabledReason(test), 'This test has ended.');
    });

    test('cancelled returns cancelled reason', () {
      final test = makeTest(status: TestStatus.cancelled);
      expect(
        getStartTestDisabledReason(test),
        'This test has been cancelled.',
      );
    });

    test('archived returns unavailable reason', () {
      final test = makeTest(status: TestStatus.archived);
      expect(
        getStartTestDisabledReason(test),
        'This test is no longer available.',
      );
    });

    test('expired returns unavailable reason', () {
      final test = makeTest(status: TestStatus.expired);
      expect(
        getStartTestDisabledReason(test),
        'This test is no longer available.',
      );
    });

    test('scheduled with future starts_at returns not-started reason', () {
      final test = makeTest(
        status: TestStatus.scheduled,
        startsAt: now.add(const Duration(hours: 1)),
      );
      expect(
        getStartTestDisabledReason(test),
        'This test has not started yet.',
      );
    });

    test('scheduled with past starts_at is startable', () {
      final test = makeTest(
        status: TestStatus.scheduled,
        startsAt: now.subtract(const Duration(hours: 1)),
      );
      expect(getStartTestDisabledReason(test), isNull);
    });
  });

  group('Edit permission', () {
    test('creator can edit own draft', () {
      expect(
        canEditTest(
          currentUserId: 'user-1',
          createdBy: 'user-1',
          status: TestStatus.draft,
          startsAt: null,
        ),
        true,
      );
    });

    test('creator cannot edit own published test (edit screen is draft-only)',
        () {
      expect(
        canEditTest(
          currentUserId: 'user-1',
          createdBy: 'user-1',
          status: TestStatus.published,
          startsAt: null,
        ),
        false,
      );
    });

    test('creator cannot edit own scheduled test even with future starts_at',
        () {
      expect(
        canEditTest(
          currentUserId: 'user-1',
          createdBy: 'user-1',
          status: TestStatus.scheduled,
          startsAt: DateTime.now().add(const Duration(hours: 1)),
        ),
        false,
      );
    });

    test('creator cannot edit own scheduled test with past starts_at', () {
      expect(
        canEditTest(
          currentUserId: 'user-1',
          createdBy: 'user-1',
          status: TestStatus.scheduled,
          startsAt: DateTime.now().subtract(const Duration(hours: 1)),
        ),
        false,
      );
    });

    test('non-creator cannot edit', () {
      expect(
        canEditTest(
          currentUserId: 'user-2',
          createdBy: 'user-1',
          status: TestStatus.draft,
          startsAt: null,
        ),
        false,
      );
    });

    test('null user cannot edit', () {
      expect(
        canEditTest(
          currentUserId: null,
          createdBy: 'user-1',
          status: TestStatus.draft,
          startsAt: null,
        ),
        false,
      );
    });

    test('creator cannot edit live test', () {
      expect(
        canEditTest(
          currentUserId: 'user-1',
          createdBy: 'user-1',
          status: TestStatus.live,
          startsAt: null,
        ),
        false,
      );
    });

    test('creator cannot edit completed test', () {
      expect(
        canEditTest(
          currentUserId: 'user-1',
          createdBy: 'user-1',
          status: TestStatus.completed,
          startsAt: null,
        ),
        false,
      );
    });

    test('creator cannot edit ended test', () {
      expect(
        canEditTest(
          currentUserId: 'user-1',
          createdBy: 'user-1',
          status: TestStatus.ended,
          startsAt: null,
        ),
        false,
      );
    });

    test('creator cannot edit cancelled test', () {
      expect(
        canEditTest(
          currentUserId: 'user-1',
          createdBy: 'user-1',
          status: TestStatus.cancelled,
          startsAt: null,
        ),
        false,
      );
    });

    test('creator cannot edit archived test', () {
      expect(
        canEditTest(
          currentUserId: 'user-1',
          createdBy: 'user-1',
          status: TestStatus.archived,
          startsAt: null,
        ),
        false,
      );
    });
  });

  group('Naming — test_mode display text', () {
    test('self mode shows Self Practice', () {
      expect(getTestModeDisplayText('self'), 'Self Practice');
    });

    test('live mode shows Challenge with Friends', () {
      expect(getTestModeDisplayText('live'), 'Challenge with Friends');
    });

    test('group mode shows Group Test', () {
      expect(getTestModeDisplayText('group'), 'Group Test');
    });

    test('null mode shows --', () {
      expect(getTestModeDisplayText(null), '--');
    });

    test('live mode does NOT show Live Test', () {
      expect(getTestModeDisplayText('live') == 'Live Test', false);
    });
  });
}
