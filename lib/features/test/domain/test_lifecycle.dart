import '../../../core/models/test.dart' show TestStatus;
import 'test_mode.dart';

/// Where a test shows up in the listing.
enum ListingCategory {
  upcoming,
  challengeWithFriends,
  previous,
  drafts,
  hidden,
}

/// Position of "now" relative to a test's `starts_at` / `ends_at` window.
enum SchedulePhase { notStarted, active, ended }

/// Centralized, server-mirroring lifecycle rules for tests.
///
/// These are UX gates only: every action is re-checked by the server
/// (`rpc_publish_test`, `_fn_start_attempt_core`, ...). Keep the rules here in
/// sync with the backend contract; never fork them inside a screen.
abstract final class TestLifecycle {
  static const _terminal = {
    TestStatus.completed,
    TestStatus.ended,
    TestStatus.evaluated,
    TestStatus.cancelled,
    TestStatus.archived,
    TestStatus.expired,
  };

  static bool isTerminal(TestStatus status) => _terminal.contains(status);

  /// Statuses in which the server's start function accepts a new attempt
  /// (subject to the time window).
  static bool isStartableStatus(TestStatus status) =>
      status == TestStatus.scheduled ||
      status == TestStatus.live ||
      status == TestStatus.ready ||
      status == TestStatus.published;

  /// The edit screen only supports drafts.
  static bool canEdit({required bool isOwner, required TestStatus status}) =>
      isOwner && status == TestStatus.draft;

  static bool canPublish({required bool isOwner, required TestStatus status}) =>
      isOwner && status == TestStatus.draft;

  /// V1 delete: creator + draft + not already soft-deleted. Mirrors
  /// `rpc_delete_test`, which enforces the same rule server-side.
  static bool canDelete({
    required bool isOwner,
    required TestStatus status,
    required bool isSoftDeleted,
  }) => isOwner && status == TestStatus.draft && !isSoftDeleted;

  /// Owner may request batch results once the test is over.
  static bool canGenerateResults({
    required bool isOwner,
    required TestStatus status,
  }) =>
      isOwner && (status == TestStatus.completed || status == TestStatus.ended);

  /// Effective schedule phase from the window alone (instants compared, so
  /// the zone of [now] / [startsAt] / [endsAt] does not matter). Mirrors
  /// the live `_fn_start_attempt_core` (R4_7_6 body): TEST_NOT_STARTED while
  /// `now() < starts_at`, TEST_ENDED once `now() >= ends_at` (hard block, not
  /// bypassed by allow_late_join). Exactly at starts_at is available; exactly
  /// at ends_at is ended — the same closed boundary the attempt deadline
  /// (`LEAST(now() + duration, ends_at)`) uses.
  static SchedulePhase phase({
    required DateTime? startsAt,
    required DateTime? endsAt,
    required DateTime now,
  }) {
    if (startsAt != null && now.isBefore(startsAt))
      return SchedulePhase.notStarted;
    if (endsAt != null && !now.isBefore(endsAt)) return SchedulePhase.ended;
    return SchedulePhase.active;
  }

  /// Null when the test can be started now; otherwise a user-facing reason.
  ///
  /// UX gate only, evaluated with the device clock; the server re-checks the
  /// same rules with `now()` when the attempt is actually started. Every
  /// startable status is subject to the window (the server does not special-
  /// case `published` vs `scheduled` vs `live`).
  static String? startBlockReason({
    required TestStatus status,
    required DateTime? startsAt,
    required DateTime? endsAt,
    required DateTime now,
    String Function(DateTime)? formatDateTime,
  }) {
    String fmt(DateTime d) => formatDateTime?.call(d) ?? d.toString();
    switch (status) {
      case TestStatus.draft:
        return 'This test is still a draft.';
      case TestStatus.scheduled:
      case TestStatus.published:
      case TestStatus.live:
      case TestStatus.ready:
        switch (phase(startsAt: startsAt, endsAt: endsAt, now: now)) {
          case SchedulePhase.notStarted:
            return 'Test starts at ${fmt(startsAt!)}.';
          case SchedulePhase.ended:
            return 'Test ended.';
          case SchedulePhase.active:
            return null;
        }
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

  /// Listing tab for a test. Soft-deleted rows are hidden; drafts go to the
  /// drafts tab (the listing only receives the creator's own drafts).
  static ListingCategory categorize({
    required TestStatus status,
    required String? testMode,
    required DateTime? startsAt,
    required DateTime? endsAt,
    required bool isSoftDeleted,
    required DateTime now,
  }) {
    if (isSoftDeleted) return ListingCategory.hidden;
    if (status == TestStatus.draft) return ListingCategory.drafts;
    if (isTerminal(status)) return ListingCategory.previous;

    final mode = TestMode.fromDb(testMode);
    final window = phase(startsAt: startsAt, endsAt: endsAt, now: now);
    final notYetStarted = window == SchedulePhase.notStarted;
    final ended = window == SchedulePhase.ended;

    switch (status) {
      case TestStatus.scheduled:
        return ListingCategory.upcoming;
      case TestStatus.live:
      case TestStatus.ready:
        if (ended) return ListingCategory.previous;
        return mode == TestMode.live
            ? ListingCategory.challengeWithFriends
            : ListingCategory.upcoming;
      case TestStatus.published:
        if (ended) return ListingCategory.previous;
        if (notYetStarted) return ListingCategory.upcoming;
        return mode == TestMode.live
            ? ListingCategory.challengeWithFriends
            : ListingCategory.upcoming;
      default:
        return ListingCategory.hidden;
    }
  }

  static String statusLabel(TestStatus status) {
    switch (status) {
      case TestStatus.draft:
        return 'Draft';
      case TestStatus.scheduled:
        return 'Scheduled';
      case TestStatus.live:
        return 'Ongoing';
      case TestStatus.ready:
        return 'Ready';
      case TestStatus.published:
        return 'Published';
      case TestStatus.completed:
        return 'Completed';
      case TestStatus.ended:
        return 'Ended';
      case TestStatus.evaluated:
        return 'Evaluated';
      case TestStatus.cancelled:
        return 'Cancelled';
      case TestStatus.archived:
        return 'Archived';
      case TestStatus.expired:
        return 'Expired';
      case TestStatus.unknown:
        return 'Unknown';
    }
  }
}
