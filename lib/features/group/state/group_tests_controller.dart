import '../../../core/errors/app_error.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/models/group.dart';
import '../../../core/models/test.dart';
import '../../../core/services/auth_service.dart';
import '../../test/data/test_repository.dart';
import '../../test/domain/test_errors.dart';
import '../../test/state/disposable_notifier.dart';
import '../data/group_repository.dart';
import '../domain/group_errors.dart';
import '../domain/group_permission.dart';
import '../domain/group_role.dart';
import '../domain/group_test_management.dart';

/// One group's test-management state (G10): the group-scoped test list in
/// management sections, the caller's server-reported test permissions, and
/// the lifecycle actions the live backend already offers (publish, schedule,
/// archive, delete draft). Creation and question editing stay in the R4
/// wizard; this controller only opens it pre-scoped to the group.
///
/// Every gate here is UX: the live RPCs / RLS re-check creator, permission,
/// group scope and status on every call, and the list is re-read from the
/// server after every mutation (success or failure).
class GroupTestsController extends DisposableNotifier {
  GroupTestsController({
    required this.groupId,
    TestRepository? tests,
    GroupRepository? groups,
    String? currentUserId,
    DateTime Function()? now,
  }) : _tests = tests ?? const SupabaseTestRepository(),
       _groups = groups ?? const SupabaseGroupRepository(),
       _currentUserId = currentUserId ?? AuthService.currentUser?.id,
       _now = now ?? DateTime.now;

  final String groupId;
  final TestRepository _tests;
  final GroupRepository _groups;
  final String? _currentUserId;
  final DateTime Function() _now;

  static const _probe = [
    GroupPermission.createTest,
    GroupPermission.editTest,
    GroupPermission.publishTest,
    GroupPermission.scheduleTest,
  ];

  Group? _group;
  List<Test> _all = const [];
  GroupPermissions _permissions = GroupPermissions.none;
  bool _loading = false;
  bool _loadedOnce = false;
  bool _accessDenied = false;
  String? _error;
  String? _actingTestId;
  bool _busy = false;

  Group? get group => _group;
  bool get isLoading => _loading;
  bool get hasLoaded => _loadedOnce;
  bool get accessDenied => _accessDenied;
  String? get error => _error;
  String? get currentUserId => _currentUserId;
  bool get isBusy => _busy;

  /// Test currently being mutated (per-test single-flight).
  String? get actingTestId => _actingTestId;

  /// All group tests the server returned (RLS-scoped), newest first.
  List<Test> get tests => _all;
  bool get isEmpty => _all.isEmpty;

  GroupPermissions get permissions => _permissions;
  bool get isOwner => GroupRole.fromDb(_group?.userRole).isOwner;

  // Server-reported permissions; owner accepted locally so a failed probe
  // never hides the owner's own controls (the function's owner bypass makes
  // the server agree).
  bool get canCreateTest =>
      _permissions.has(GroupPermission.createTest) || isOwner;
  bool get canEditTests =>
      _permissions.has(GroupPermission.editTest) || isOwner;
  bool get canPublishTests =>
      _permissions.has(GroupPermission.publishTest) || isOwner;
  bool get canScheduleTests =>
      _permissions.has(GroupPermission.scheduleTest) || isOwner;

  /// True when the caller may manage anything at all (drives the management
  /// affordances; members without any test permission get a read-only list).
  bool get canManage =>
      canCreateTest || canEditTests || canPublishTests || canScheduleTests;

  bool isCreator(Test t) =>
      _currentUserId != null && t.createdBy == _currentUserId;

  Map<GroupTestSection, List<Test>> get sections {
    final now = _now();
    final out = {for (final s in GroupTestSection.values) s: <Test>[]};
    for (final t in _all) {
      out[GroupTestManagement.sectionFor(t, now)]!.add(t);
    }
    return out;
  }

  List<Test> section(GroupTestSection s) => sections[s]!;

  bool canEdit(Test t) =>
      canEditTests &&
      GroupTestManagement.canEdit(isCreator: isCreator(t), status: t.status);

  bool canPublish(Test t) => GroupTestManagement.canPublish(
    isCreator: isCreator(t),
    hasPublishPermission: canPublishTests,
    status: t.status,
  );

  bool canSchedule(Test t) => GroupTestManagement.canSchedule(
    isCreator: isCreator(t),
    hasSchedulePermission: canScheduleTests,
    status: t.status,
  );

  bool canArchive(Test t) => GroupTestManagement.canArchive(
    isCreator: isCreator(t),
    hasEditPermission: canEditTests,
    status: t.status,
    isSoftDeleted: t.isSoftDeleted,
  );

  bool canDeleteDraft(Test t) => GroupTestManagement.canDeleteDraft(
    isCreator: isCreator(t),
    status: t.status,
    isSoftDeleted: t.isSoftDeleted,
  );

  // ── loading ──

  Future<void> load() async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final group = await _groups.groupForMember(groupId);
      if (group == null) {
        _group = null;
        _all = const [];
        _permissions = GroupPermissions.none;
        _accessDenied = true;
      } else {
        _group = group;
        _accessDenied = false;
        _permissions = await _groups.permissionsFor(groupId, of: _probe);
        _all = await _tests.listForGroup(groupId);
      }
    } on AppError catch (e) {
      _error = e.message;
    } catch (e, st) {
      AppLogger.error('Group tests load failed: $e', stackTrace: st);
      _error = GroupErrors.map(e.toString(), context: GroupErrorContext.load);
    }
    _loading = false;
    _loadedOnce = true;
    notifyListeners();
  }

  Future<void> refresh() => load();

  /// Re-reads only the test list (after a mutation). Errors are surfaced
  /// through [error] but never hide the last good list.
  Future<void> _reloadTests() async {
    try {
      _all = await _tests.listForGroup(groupId);
    } on AppError catch (e) {
      _error ??= e.message;
    } catch (e, st) {
      AppLogger.error('Group tests reload failed: $e', stackTrace: st);
      _error ??= GroupErrors.map(
        e.toString(),
        context: GroupErrorContext.load,
      );
    }
  }

  // ── mutations (single-flight; server re-read after success and failure) ──

  Future<bool> _run(
    Test target,
    bool Function() allowed,
    String deniedMessage,
    Future<void> Function() body,
  ) async {
    if (_busy || _actingTestId == target.id) return false;
    if (target.groupId != groupId) {
      // A row from another group can never be managed from this screen —
      // the server would refuse too, but the client does not even try.
      _error = 'This test does not belong to this group.';
      notifyListeners();
      return false;
    }
    if (!allowed()) {
      _error = deniedMessage;
      notifyListeners();
      return false;
    }
    _busy = true;
    _actingTestId = target.id;
    _error = null;
    notifyListeners();
    try {
      await body();
      await _reloadTests();
      return true;
    } on AppError catch (e) {
      _error = e.message;
      await _reloadTests();
      return false;
    } catch (e, st) {
      AppLogger.error('Group test mutation failed: $e', stackTrace: st);
      _error = TestErrors.map(e.toString());
      await _reloadTests();
      return false;
    } finally {
      _busy = false;
      _actingTestId = null;
      notifyListeners();
    }
  }

  /// `rpc_publish_test` (creator, draft, ≥1 approved question — all
  /// server-checked).
  Future<bool> publish(Test t) => _run(
    t,
    () => canPublish(t),
    'Only the creator of a draft with the publish permission can publish it.',
    () => _tests.publish(t.id),
  );

  /// Sets `starts_at` / `ends_at` through `rpc_update_test` (creator; draft
  /// or published; `ends_at > starts_at` server-validated). Every other
  /// field is re-sent unchanged so nothing else moves.
  Future<bool> schedule(
    Test t, {
    required DateTime? startsAt,
    required DateTime? endsAt,
  }) {
    final invalid = GroupTestManagement.validateSchedule(
      startsAt: startsAt,
      endsAt: endsAt,
    );
    if (invalid != null) {
      _error = invalid;
      notifyListeners();
      return Future.value(false);
    }
    return _run(
      t,
      () => canSchedule(t),
      'Only the creator with the schedule permission can schedule a draft or published test.',
      () => _tests.update(
        t.id,
        TestWriteInput(
          title: t.title,
          description: t.description,
          durationSec: t.durationSec,
          marksPerQuestion: t.marksPerQuestion,
          negativeMarks: t.negativeMarks,
          startsAt: startsAt ?? t.startsAt,
          endsAt: endsAt ?? t.endsAt,
          maxParticipants: t.maxParticipants,
          allowLateJoin: t.allowLateJoin,
          settings: t.settings,
          config: t.config,
        ),
      ),
    );
  }

  /// `fn_soft_delete_test` — archive (status = archived, soft-deleted);
  /// attempts, answers and results are preserved by the server.
  Future<bool> archive(Test t, {String? reason}) => _run(
    t,
    () => canArchive(t),
    'This test cannot be archived (ongoing/scheduled tests, or no permission).',
    () => _tests.archive(t.id, reason: reason),
  );

  /// `rpc_delete_test` — draft soft delete by the creator.
  Future<bool> deleteDraft(Test t, {String? reason}) => _run(
    t,
    () => canDeleteDraft(t),
    'Only your own draft tests can be deleted.',
    () => _tests.deleteDraft(t.id, reason: reason),
  );

  void clearError() {
    if (_error == null) return;
    _error = null;
    notifyListeners();
  }
}
