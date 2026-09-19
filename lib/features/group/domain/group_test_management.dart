import '../../../core/models/test.dart';
import '../../test/domain/test_lifecycle.dart';

/// Management sections of a group's tests (G10). Derived from the LIVE
/// `test_status` values and the schedule window; no new status exists.
enum GroupTestSection {
  drafts,
  upcoming,
  live,
  previous,
  archived;

  String get label {
    switch (this) {
      case GroupTestSection.drafts:
        return 'Drafts';
      case GroupTestSection.upcoming:
        return 'Upcoming';
      case GroupTestSection.live:
        return 'Ongoing';
      case GroupTestSection.previous:
        return 'Previous';
      case GroupTestSection.archived:
        return 'Archived / Cancelled';
    }
  }
}

/// UX gates for group-test management. Every rule here mirrors a LIVE
/// server rule (the RPC bodies / policies named in each comment); the server
/// re-checks everything, so these only decide what to offer.
abstract final class GroupTestManagement {
  /// Live `_fn_validate_test_timing`: only `ends_at > starts_at` is enforced.
  static const scheduleEndBeforeStart = 'End time must be after start time.';
  static const scheduleNothingToSet = 'Set a start or an end time.';

  static GroupTestSection sectionFor(Test t, DateTime now) {
    if (t.isSoftDeleted ||
        t.status == TestStatus.archived ||
        t.status == TestStatus.cancelled) {
      return GroupTestSection.archived;
    }
    if (t.status == TestStatus.draft) return GroupTestSection.drafts;
    if (TestLifecycle.isTerminal(t.status)) return GroupTestSection.previous;
    final phase = TestLifecycle.phase(
      startsAt: t.startsAt,
      endsAt: t.endsAt,
      now: now,
    );
    switch (phase) {
      case SchedulePhase.ended:
        return GroupTestSection.previous;
      case SchedulePhase.notStarted:
        return GroupTestSection.upcoming;
      case SchedulePhase.active:
        // `scheduled` becomes `live` only through the server sweep at
        // starts_at; until then it is upcoming even without a window.
        return t.status == TestStatus.scheduled
            ? GroupTestSection.upcoming
            : GroupTestSection.live;
    }
  }

  /// Live `rpc_update_test` → `_fn_can_update_test`: creator AND status in
  /// (draft, published). The R4 edit screen itself supports drafts only.
  static bool canEdit({required bool isCreator, required TestStatus status}) =>
      isCreator && status == TestStatus.draft;

  /// Live `rpc_publish_test`: creator AND draft. `PUBLISH_TEST` is the
  /// product permission; the live RPC additionally requires the creator, so
  /// both are needed for the action to succeed.
  static bool canPublish({
    required bool isCreator,
    required bool hasPublishPermission,
    required TestStatus status,
  }) => isCreator && hasPublishPermission && status == TestStatus.draft;

  /// Scheduling = setting `starts_at` / `ends_at` through the live
  /// `rpc_update_test` (creator; draft or published). `SCHEDULE_TEST` is the
  /// product permission gate on top.
  static bool canSchedule({
    required bool isCreator,
    required bool hasSchedulePermission,
    required TestStatus status,
  }) =>
      isCreator &&
      hasSchedulePermission &&
      (status == TestStatus.draft || status == TestStatus.published);

  /// Live `fn_soft_delete_test`: creator OR (group owner OR EDIT_TEST);
  /// refused for `live` / `scheduled`; idempotent when already deleted.
  /// Sets status = archived + is_soft_deleted (attempts/answers/results are
  /// untouched).
  static bool canArchive({
    required bool isCreator,
    required bool hasEditPermission,
    required TestStatus status,
    required bool isSoftDeleted,
  }) =>
      !isSoftDeleted &&
      status != TestStatus.live &&
      status != TestStatus.scheduled &&
      status != TestStatus.archived &&
      (isCreator || hasEditPermission);

  /// Live `rpc_delete_test`: creator AND draft AND not deleted.
  static bool canDeleteDraft({
    required bool isCreator,
    required TestStatus status,
    required bool isSoftDeleted,
  }) => TestLifecycle.canDelete(
    isOwner: isCreator,
    status: status,
    isSoftDeleted: isSoftDeleted,
  );

  /// Client mirror of `_fn_validate_test_timing` plus "something to set".
  static String? validateSchedule({
    required DateTime? startsAt,
    required DateTime? endsAt,
  }) {
    if (startsAt == null && endsAt == null) return scheduleNothingToSet;
    if (startsAt != null && endsAt != null && !endsAt.isAfter(startsAt)) {
      return scheduleEndBeforeStart;
    }
    return null;
  }
}
