import '../../../core/errors/app_error.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/models/group.dart';
import '../../../core/models/group_member.dart';
import '../../../core/services/auth_service.dart';
import '../../test/state/disposable_notifier.dart';
import '../data/group_repository.dart';
import '../domain/group_errors.dart';
import '../domain/group_privacy.dart';
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
  bool _canManageMembers = false;
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

  /// Server-confirmed `MANAGE_MEMBERS` (`fn_has_permission`), not a guess
  /// from the role string. Used only to decide whether to offer the action.
  bool get canManageMembers => _canManageMembers;

  /// The live `groups` UPDATE policy is `GROUP_SETTINGS` or owner, and
  /// `GROUP_SETTINGS` is seeded for no role, so this mirrors it as owner-only.
  bool get canEditBasics => isOwner;

  /// The owner has no way out today: the live `self leave group` policy would
  /// happily delete the owner's membership row and orphan the group, and no
  /// ownership-transfer function exists. The client therefore refuses, and
  /// the restriction is reported as a backend dependency rather than
  /// inventing a transfer.
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
        _canManageMembers = await _repo.canManageMembers(groupId);
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

  /// Updates name / description. Server policy decides; a refusal surfaces as
  /// a permission message.
  Future<bool> updateBasics({
    required String name,
    String description = '',
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
      ),
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
