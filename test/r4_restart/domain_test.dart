// R4.2 — domain foundation behaviour tests.

import 'package:flutter_test/flutter_test.dart';
import 'package:my_praperation/core/models/attempt.dart';
import 'package:my_praperation/core/models/test.dart' show TestStatus;
import 'package:my_praperation/features/test/domain/attempt_lifecycle.dart';
import 'package:my_praperation/features/test/domain/backend_mapping.dart';
import 'package:my_praperation/features/test/domain/publish_readiness.dart';
import 'package:my_praperation/features/test/domain/test_errors.dart';
import 'package:my_praperation/features/test/domain/test_kind.dart';
import 'package:my_praperation/features/test/domain/test_lifecycle.dart';
import 'package:my_praperation/features/test/domain/test_mode.dart';

void main() {
  group('TestKind labels', () {
    test('canonical user-facing names, never "Live Test"', () {
      expect(TestKind.challengeWithFriends.label, 'Challenge with Friends');
      expect(TestKind.group.label, 'Group Test');
      expect(TestKind.self.label, 'Self');
      expect(TestKind.practice.label, 'Practice Test');
      expect(TestKind.quick.label, 'Quick Test');
      expect(TestKind.sectional.label, 'Sectional Test');
      expect(TestKind.adaptive.label, 'Adaptive Test');
      for (final k in TestKind.values) {
        expect(k.label.contains('Live'), isFalse, reason: k.name);
      }
    });

    test('creatable kinds exclude adaptive', () {
      expect(TestKind.creatable, isNot(contains(TestKind.adaptive)));
      expect(TestKind.creatable.length, 6);
    });
  });

  group('BackendMapping', () {
    test('toBackend: Challenge → live, Group → group, Self family → self+settings',
        () {
      expect(BackendMapping.toBackend(TestKind.challengeWithFriends),
          (mode: TestMode.live, settingsKind: null));
      expect(BackendMapping.toBackend(TestKind.group),
          (mode: TestMode.group, settingsKind: null));
      for (final k in [
        TestKind.self,
        TestKind.practice,
        TestKind.quick,
        TestKind.sectional,
        TestKind.adaptive,
      ]) {
        final b = BackendMapping.toBackend(k);
        expect(b.mode, TestMode.self);
        expect(b.settingsKind, k.name);
      }
    });

    test('fromBackend round-trips every kind', () {
      for (final k in TestKind.values) {
        final b = BackendMapping.toBackend(k);
        final settings =
            b.settingsKind == null ? null : {'test_kind': b.settingsKind};
        expect(BackendMapping.fromBackend(b.mode.dbValue, settings), k);
      }
    });

    test('fromBackend: missing / null / junk settings → self; non-self modes ignore settings',
        () {
      expect(BackendMapping.fromBackend('self', null), TestKind.self);
      expect(BackendMapping.fromBackend('self', {}), TestKind.self);
      expect(BackendMapping.fromBackend('self', {'test_kind': 7}), TestKind.self);
      expect(BackendMapping.fromBackend('self', {'test_kind': 'marketplace'}),
          TestKind.self);
      expect(BackendMapping.fromBackend(null, {'test_kind': 'quick'}),
          TestKind.quick);
      expect(BackendMapping.fromBackend('live', {'test_kind': 'practice'}),
          TestKind.challengeWithFriends);
      expect(BackendMapping.fromBackend('group', {'test_kind': 'quick'}),
          TestKind.group);
      expect(BackendMapping.fromBackend('bogus', null), TestKind.self);
    });

    test('settingsFor preserves unrelated keys and strips test_kind for non-self',
        () {
      final existing = {'test_kind': 'self', 'keep': true};
      expect(BackendMapping.settingsFor(TestKind.practice, existing),
          {'test_kind': 'practice', 'keep': true});
      expect(existing['test_kind'], 'self');
      expect(BackendMapping.settingsFor(TestKind.challengeWithFriends, existing),
          {'keep': true});
      expect(BackendMapping.settingsFor(TestKind.group, null), isNull);
      expect(BackendMapping.settingsFor(TestKind.quick, null),
          {'test_kind': 'quick'});
    });
  });

  group('TestLifecycle', () {
    final now = DateTime(2026, 9, 16, 12);
    final past = now.subtract(const Duration(hours: 1));
    final future = now.add(const Duration(hours: 1));

    test('edit/publish are owner + draft only', () {
      expect(TestLifecycle.canEdit(isOwner: true, status: TestStatus.draft), isTrue);
      expect(TestLifecycle.canEdit(isOwner: false, status: TestStatus.draft), isFalse);
      expect(TestLifecycle.canEdit(isOwner: true, status: TestStatus.published), isFalse);
      expect(TestLifecycle.canPublish(isOwner: true, status: TestStatus.draft), isTrue);
      expect(TestLifecycle.canPublish(isOwner: true, status: TestStatus.live), isFalse);
    });

    test('drafts and terminal statuses are never startable', () {
      for (final s in [
        TestStatus.draft,
        TestStatus.completed,
        TestStatus.ended,
        TestStatus.evaluated,
        TestStatus.cancelled,
        TestStatus.archived,
        TestStatus.expired,
        TestStatus.unknown,
      ]) {
        expect(
          TestLifecycle.startBlockReason(
              status: s, startsAt: null, endsAt: null, now: now),
          isNotNull,
          reason: s.name,
        );
      }
    });

    test('published: window enforced; live/ready: end enforced', () {
      String? r(TestStatus s, {DateTime? starts, DateTime? ends}) =>
          TestLifecycle.startBlockReason(
              status: s, startsAt: starts, endsAt: ends, now: now);
      expect(r(TestStatus.published), isNull);
      expect(r(TestStatus.published, starts: future), contains('not started'));
      expect(r(TestStatus.published, ends: past), contains('ended'));
      expect(r(TestStatus.scheduled, starts: future), contains('not started'));
      expect(r(TestStatus.scheduled, starts: past), isNull);
      expect(r(TestStatus.live, ends: past), contains('ended'));
      expect(r(TestStatus.live), isNull);
      expect(r(TestStatus.ready, ends: future), isNull);
    });

    test('categorize mirrors the four listing tabs', () {
      ListingCategory c(TestStatus s, String mode,
              {DateTime? starts, DateTime? ends, bool deleted = false}) =>
          TestLifecycle.categorize(
              status: s,
              testMode: mode,
              startsAt: starts,
              endsAt: ends,
              isSoftDeleted: deleted,
              now: now);

      expect(c(TestStatus.draft, 'self'), ListingCategory.drafts);
      expect(c(TestStatus.published, 'self', deleted: true), ListingCategory.hidden);
      expect(c(TestStatus.scheduled, 'live'), ListingCategory.upcoming);
      expect(c(TestStatus.published, 'self'), ListingCategory.upcoming);
      expect(c(TestStatus.published, 'group', ends: future), ListingCategory.upcoming);
      expect(c(TestStatus.published, 'self', ends: past), ListingCategory.previous);
      expect(c(TestStatus.published, 'live'), ListingCategory.challengeWithFriends);
      expect(c(TestStatus.published, 'live', starts: future), ListingCategory.upcoming);
      expect(c(TestStatus.live, 'live'), ListingCategory.challengeWithFriends);
      expect(c(TestStatus.live, 'live', ends: past), ListingCategory.previous);
      expect(c(TestStatus.completed, 'self'), ListingCategory.previous);
      expect(c(TestStatus.cancelled, 'live'), ListingCategory.previous);
    });

    test('status labels use "Ongoing", not "Live"', () {
      expect(TestLifecycle.statusLabel(TestStatus.live), 'Ongoing');
      for (final s in TestStatus.values) {
        expect(TestLifecycle.statusLabel(s), isNot('Live'));
      }
    });
  });

  group('AttemptLifecycle', () {
    test('only in_progress is interactive; submitted family may have result', () {
      expect(AttemptLifecycle.isInteractive(AttemptStatus.inProgress), isTrue);
      expect(AttemptLifecycle.isInteractive(AttemptStatus.submitted), isFalse);
      expect(AttemptLifecycle.mayHaveResult(AttemptStatus.inProgress), isFalse);
      expect(AttemptLifecycle.mayHaveResult(AttemptStatus.autoSubmitted), isTrue);
      expect(AttemptLifecycle.mayHaveResult(AttemptStatus.scored), isTrue);
    });
  });

  group('PublishReadiness', () {
    PublishReadinessInput input({
      String title = 'T',
      TestKind kind = TestKind.self,
      String? groupId,
      int? duration = 600,
      double? marks = 1,
      DateTime? starts,
      DateTime? ends,
      List<String> server = const ['approved'],
      List<bool> local = const [],
    }) =>
        PublishReadinessInput(
          title: title,
          kind: kind,
          groupId: groupId,
          durationSec: duration,
          marksPerQuestion: marks,
          startsAt: starts,
          endsAt: ends,
          serverQuestionStatuses: server,
          localDraftValidity: local,
        );

    test('ready when everything is satisfied', () {
      expect(PublishReadiness.isReady(input()), isTrue);
      expect(PublishReadiness.blockingReasons(input()), isEmpty);
    });

    test('pending server questions block with a count', () {
      final reasons = PublishReadiness.blockingReasons(
          input(server: ['approved', 'pending_review', 'pending_review']));
      expect(reasons, ['2 question(s) need approval before publishing']);
    });

    test('group required only for Group Test', () {
      expect(PublishReadiness.isReady(input(kind: TestKind.group)), isFalse);
      expect(PublishReadiness.isReady(input(kind: TestKind.group, groupId: 'g')),
          isTrue);
      expect(PublishReadiness.isReady(input(kind: TestKind.challengeWithFriends)),
          isTrue);
    });

    test('no questions, invalid local drafts, bad schedule all block', () {
      expect(PublishReadiness.blockingReasons(input(server: [])),
          contains('Add at least one question'));
      expect(PublishReadiness.blockingReasons(input(local: [true, false])),
          contains('1 question(s) need fixing'));
      final now = DateTime(2026);
      expect(
          PublishReadiness.blockingReasons(
              input(starts: now, ends: now.subtract(const Duration(hours: 1)))),
          contains('End time must be after start time'));
      expect(PublishReadiness.blockingReasons(input(title: '  ')),
          contains('Enter a test title'));
      expect(PublishReadiness.blockingReasons(input(duration: 0)),
          contains('Set a valid duration'));
    });
  });

  group('TestErrors', () {
    test('live publish rejection is actionable, not generic', () {
      const live =
          'VALIDATION_ERROR: Test must have at least one approved question to publish';
      expect(TestErrors.map(live, context: TestErrorContext.publish),
          contains('Approve all questions'));
    });

    test('server codes map to specific messages', () {
      expect(TestErrors.map('TEST_CODE_INVALID'), contains('Invalid test code'));
      expect(TestErrors.map('TEST_CODE_AMBIGUOUS'), contains('more than one'));
      expect(TestErrors.map('TEST_ENDED: ...'), contains('ended'));
      expect(TestErrors.map('TEST_FULL'), contains('maximum'));
      expect(TestErrors.map('LATE_JOIN_NOT_ALLOWED'), contains('late joining'));
      expect(TestErrors.map('NOT_AUTHENTICATED'), contains('session'));
      expect(TestErrors.map('TEST_ACCESS_DENIED', context: TestErrorContext.start),
          contains('access'));
    });

    test('unknown errors keep short server detail instead of hiding it', () {
      expect(TestErrors.map('SOME_CODE: Question 3 has no options'),
          'Question 3 has no options.');
      expect(TestErrors.map('x' * 200), 'Something went wrong. Please try again.');
      expect(TestErrors.map('{"json":true}', context: TestErrorContext.save),
          'Failed to save. Please try again.');
    });
  });
}
