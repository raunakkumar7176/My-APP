import '../../../core/errors/app_error.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/models/group.dart';
import '../../../core/models/group_member.dart';
import '../../../core/services/auth_service.dart';
import '../../test/state/disposable_notifier.dart';
import '../data/group_repository.dart';
import '../domain/group_errors.dart';
import '../domain/group_privacy.dart';
import '../domain/group_permission.dart';
import '../domain/group_role.dart';

/// One group's core state: profile, roster, the caller's own role, and the
/// membership mutations of G1 (leave, remove member, edit basics).
///
/// Access rule: the hub opens only for a member. A public group's row is
/// readable by any signed-in user under the live "public groups are
/// discoverable" policy, so readability is never treated as access.
class GroupHubController extends DisposableNotifier {
  GroupHubController({
    required this.groupId,
    GroupRepository? repository,
    String? currentUserId,
  }) : _repo = repository ?? const SupabaseGroupRepository(),
       _currentUserId = currentUserId ?? AuthService.currentUser?.id;

  final String groupId;
  final GroupRepository _repo;
  final String? _currentUserId;

  Group? _group;
  List<GroupMember> _members = const [];
  bool _loading = false;
  bool _loadedOnce = false;
  bool _busy = false;
  bool _accessDenied = false;
  bool _leftGroup = false;
  GroupPermissions _permissions = GroupPermissions.none;
  String? _error;

  Group? get group => _group;
  List<GroupMember> get members => _members;
  bool get isLoading => _loading;
  bool get hasLoaded => _loadedOnce;
  bool get isBusy => _busy;
  String? get error => _error;
  String? get currentUserId => _currentUserId;

  /// True when the group does not exist, was deleted, or the caller is not
  /// (or is no longer) a member of it. The screen shows one honest state for
  /// all three: the server does not distinguish them, and guessing would leak
  /// the existence of groups the caller cannot see.
  bool get accessDenied => _accessDenied;

  /// True once the caller has left this group in this session.
  bool get hasLeft => _leftGroup;

  GroupRole get myRole => GroupRole.fromDb(_group?.userRole);
  GroupPrivacy get privacy => GroupPrivacy.fromDb(_group?.privacy);
  bool get isOwner => myRole.isOwner;
  int get memberCount => _group?.memberCount ?? _members.length;

  /// The caller's server-reported permissions in this group (one
  /// `fn_has_permission` probe per value; owner is true for all of them by the
  /// function's own owner branch). UX mirror only — the server decides.
  GroupPermissions get permissions => _permissions;

  /// Server-confirmed `MANAGE_MEMBERS`. Used only to decide whether to offer
  /// the action.
  bool get canManageMembers => _permissions.canManageMembers;

  /// Server-confirmed `MANAGE_ROLES`.
  bool get canManageRoles => _permissions.canManageRoles;

  /// Server-confirmed `GROUP_SETTINGS`, which is exactly the live `groups`
  /// UPDATE policy (`GROUP_SETTINGS` OR owner). Owner is also accepted locally
  /// so a failed probe never hides the owner's own settings.
  bool get canEditBasics => _permissions.canEditSettings || isOwner;

  /// Roles an authorised manager may assign through ordinary role editing.
  /// `owner` is never assignable here: it is an invariant, not a permission
  /// (no ownership-transfer mechanism exists live).
  static const assignableRoles = [
    GroupRole.leader,
    GroupRole.moderator,
    GroupRole.member,
  ];

  /// The owner cannot leave: live `trg_owner_guard` (fn_prevent_owner_removal,
  /// verified in the G3 audit) raises CANNOT_REMOVE_OWNER on deleting an owner
  /// row, and no ownership-transfer function exists. The client refuses up
  /// front with the same outcome the server would give.
  bool get canLeave => _group != null && !isOwner;

  String get leaveBlockedReason =>
      'You own this group. Ownership transfer is not available yet, so the '
      'owner cannot leave. Delete the group or transfer ownership once that '
      'is supported.';

  Future<void> load() async {
    if (_loading) return;
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final group = await _repo.groupForMember(groupId);
      if (group == null) {
        _group = null;
        _members = const [];
        _accessDenied = true;
      } else {
        _group = group;
        _accessDenied = false;
        _members = await _repo.members(groupId);
        _permissions = await _repo.permissionsFor(
          groupId,
          of: const [
            GroupPermission.manageMembers,
            GroupPermission.manageRoles,
            GroupPermission.groupSettings,
          ],
        );
      }
    } on AppError catch (e) {
      _error = e.message;
    } catch (e, st) {
      AppLogger.error('Group hub load failed: $e', stackTrace: st);
      _error = GroupErrors.map(e.toString(), context: GroupErrorContext.load);
    }
    _loading = false;
    _loadedOnce = true;
    notifyListeners();
  }

  Future<void> refresh() => load();

  /// Leaves the group. Returns true when the membership is gone.
  Future<bool> leave() async {
    if (!canLeave) {
      _error = leaveBlockedReason;
      notifyListeners();
      return false;
    }
    final ok = await _run(GroupErrorContext.leave, () => _repo.leave(groupId));
    if (ok) {
      _leftGroup = true;
      _accessDenied = true;
      _group = null;
      _members = const [];
      notifyListeners();
    }
    return ok;
  }

  /// Changes another member's role. Client invariants (each also enforced by
  /// the live "role changes" policy / trg_owner_guard, verified in the G3
  /// audit): never yourself, never the owner, never *to* owner, only a live
  /// assignable role, and only a user who is in this group's roster.
  /// `MANAGE_ROLES` is enforced server-side; the client merely does not offer
  /// the action without it.
  Future<bool> changeRole(String userId, GroupRole role) async {
    if (!canManageRoles) {
      _error = GroupErrors.map(
        'NOT_AUTHORIZED',
        context: GroupErrorContext.changeRole,
      );
      notifyListeners();
      return false;
    }
    if (userId == _currentUserId) {
      _error = 'You cannot change your own role.';
      notifyListeners();
      return false;
    }
    final target = _members.where((m) => m.userId == userId).firstOrNull;
    if (target == null) {
      _error = 'That user is not a member of this group.';
      notifyListeners();
      return false;
    }
    if (GroupRole.fromDb(target.role).isOwner) {
      _error = 'The group owner cannot be demoted.';
      notifyListeners();
      return false;
    }
    if (!assignableRoles.contains(role)) {
      _error = 'That role cannot be assigned here.';
      notifyListeners();
      return false;
    }
    if (GroupRole.fromDb(target.role) == role) return true; // no-op
    final ok = await _run(
      GroupErrorContext.changeRole,
      () => _repo.setMemberRole(groupId: groupId, userId: userId, role: role),
    );
    if (ok) await load();
    return ok;
  }

  /// Removes another member. The server enforces `MANAGE_MEMBERS`; this only
  /// avoids offering an action that is certain to fail, and never lets the
  /// owner be removed (the owner row must survive for the group to have one).
  Future<bool> removeMember(String userId) async {
    if (userId == _currentUserId) {
      _error = 'Use Leave group to remove yourself.';
      notifyListeners();
      return false;
    }
    final target = _members.where((m) => m.userId == userId).firstOrNull;
    if (target != null && GroupRole.fromDb(target.role).isOwner) {
      _error = 'The group owner cannot be removed.';
      notifyListeners();
      return false;
    }
    final ok = await _run(
      GroupErrorContext.removeMember,
      () => _repo.removeMember(groupId: groupId, userId: userId),
    );
    if (ok) await load();
    return ok;
  }

  /// Updates name / description / privacy. Server policy decides; a refusal
  /// surfaces as a permission message. Privacy is validated against the live
  /// CHECK values before anything is sent.
  Future<bool> updateBasics({
    required String name,
    String description = '',
    GroupPrivacy? privacy,
  }) async {
    final invalid = GroupErrors.validateName(name);
    if (invalid != null) {
      _error = invalid;
      notifyListeners();
      return false;
    }
    final ok = await _run(
      GroupErrorContext.update,
      () => _repo.updateBasics(
        groupId: groupId,
        name: name,
        description: description,
        privacy: privacy?.db,
      ),
    );
    if (ok) await load();
    return ok;
  }

  /// Removes the group logo (`logo_url = NULL`). Upload/replace wait on a
  /// group-scoped storage policy that does not exist live yet.
  Future<bool> clearLogo() async {
    final ok = await _run(
      GroupErrorContext.update,
      () => _repo.clearLogo(groupId),
    );
    if (ok) await load();
    return ok;
  }

  Future<bool> _run(
    GroupErrorContext context,
    Future<void> Function() body,
  ) async {
    if (_busy) return false;
    _busy = true;
    _error = null;
    notifyListeners();
    try {
      await body();
      return true;
    } on AppError catch (e) {
      _error = e.message;
      return false;
    } catch (e, st) {
      AppLogger.error('Group mutation failed: $e', stackTrace: st);
      _error = GroupErrors.map(e.toString(), context: context);
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  void clearError() {
    if (_error == null) return;
    _error = null;
    notifyListeners();
  }
}
