import '../../../core/errors/app_error.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/models/group.dart';
import '../../../core/models/group_invitation.dart';
import '../../../core/models/group_join_request.dart';
import '../../../core/models/group_member.dart';
import '../../../core/models/group_rule.dart';
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

  /// The data source this hub uses, so flows opened from it (invite sheet)
  /// share it instead of constructing a second one.
  GroupRepository get repository => _repo;

  Group? _group;
  List<GroupMember> _members = const [];
  bool _loading = false;
  bool _loadedOnce = false;
  bool _busy = false;
  bool _accessDenied = false;
  bool _leftGroup = false;
  GroupPermissions _permissions = GroupPermissions.none;

  // ── manager join-request queue (G5.3) ──
  List<GroupJoinRequest> _joinRequests = const [];
  bool _joinRequestsLoading = false;
  String? _joinRequestsError;
  String? _actingRequestId;

  // ── outgoing / managed invitations (G5.5) ──
  List<GroupInvitation> _outgoingInvitations = const [];
  bool _outgoingLoading = false;
  String? _outgoingError;
  String? _actingInvitationId;

  /// Invitations of this group, all statuses, loaded only when the
  /// server-reported MANAGE_MEMBERS is true. Kept separate from the incoming
  /// (invitee) list and from join requests — different lifecycle entities.
  List<GroupInvitation> get outgoingInvitations => _outgoingInvitations;
  bool get outgoingLoading => _outgoingLoading;
  String? get outgoingError => _outgoingError;
  String? get actingInvitationId => _actingInvitationId;

  // ── group rules (G6) ──
  List<GroupRule> _rules = const [];
  bool _rulesLoading = false;
  String? _rulesError;
  String? _actingRuleId;
  bool _rulesSaving = false;

  List<GroupRule> get rules => _rules;
  bool get rulesLoading => _rulesLoading;
  String? get rulesError => _rulesError;
  String? get actingRuleId => _actingRuleId;
  bool get rulesSaving => _rulesSaving;
  bool get hasRules => _rules.isNotEmpty;

  /// Re-invite is offered only for a `declined` row whose invitee is not
  /// already in the roster. Pending/accepted/expired rows are never re-sent.
  bool canReinvite(GroupInvitation inv) =>
      canManageMembers &&
      inv.status == GroupInvitation.statusDeclined &&
      !_members.any((m) => m.userId == inv.inviteeId);

  /// Pending requests for this group. Loaded only when the server-reported
  /// MANAGE_MEMBERS is true; otherwise never queried. A requester is not a
  /// member and their profile is not readable, so rows carry no identity.
  List<GroupJoinRequest> get joinRequests => _joinRequests;
  int get pendingRequestCount => _joinRequests.length;
  bool get joinRequestsLoading => _joinRequestsLoading;
  String? get joinRequestsError => _joinRequestsError;

  /// Request currently being decided (single-flight per request; other
  /// items stay enabled unless a global mutation is running).
  String? get actingRequestId => _actingRequestId;
  String? _error;

  Group? get group => _group;
  List<GroupMember> get members => _members;

  // ── members hub: local search + role filter over the permitted roster ──
  String _memberQuery = '';
  GroupRole? _roleFilter;

  String get memberQuery => _memberQuery;
  GroupRole? get roleFilter => _roleFilter;
  bool get hasMemberFilter =>
      _memberQuery.trim().isNotEmpty || _roleFilter != null;

  void setMemberQuery(String value) {
    if (value == _memberQuery) return;
    _memberQuery = value;
    notifyListeners();
  }

  /// null = all roles.
  void setRoleFilter(GroupRole? role) {
    if (role == _roleFilter) return;
    _roleFilter = role;
    notifyListeners();
  }

  void clearMemberFilters() {
    if (!hasMemberFilter) return;
    _memberQuery = '';
    _roleFilter = null;
    notifyListeners();
  }

  /// Roster narrowed by [memberQuery] (case-insensitive, trimmed; name first,
  /// then student code) and [roleFilter]. Purely local over rows RLS already
  /// returned — it never widens what the server permitted.
  List<GroupMember> get filteredMembers {
    final q = _memberQuery.trim().toLowerCase();
    final r = _roleFilter;
    if (q.isEmpty && r == null) return _members;
    return [
      for (final m in _members)
        if ((r == null || GroupRole.fromDb(m.role) == r) &&
            (q.isEmpty ||
                m.displayName.toLowerCase().contains(q) ||
                (m.studentCode ?? '').toLowerCase().contains(q)))
          m,
    ];
  }

  /// The caller's own membership row, when loaded.
  GroupMember? get me =>
      _members.where((m) => m.userId == _currentUserId).firstOrNull;
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
        // Manager queue: loaded only when the server says MANAGE_MEMBERS.
        if (_permissions.canManageMembers) {
          await _loadJoinRequests();
          await _loadOutgoingInvitations();
        } else {
          _joinRequests = const [];
          _joinRequestsError = null;
          _outgoingInvitations = const [];
          _outgoingError = null;
        }
        // Rules: loaded for all members (RLS enforces member-only read).
        await _loadRules();
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

  Future<void> _loadJoinRequests() async {
    _joinRequestsLoading = true;
    _joinRequestsError = null;
    try {
      _joinRequests = await _repo.pendingJoinRequests(groupId);
    } on AppError catch (e) {
      _joinRequestsError = e.message;
    } catch (e, st) {
      AppLogger.error('Join requests load failed: $e', stackTrace: st);
      _joinRequestsError = GroupErrors.map(
        e.toString(),
        context: GroupErrorContext.joinRequest,
      );
    }
    _joinRequestsLoading = false;
  }

  Future<void> _loadOutgoingInvitations() async {
    _outgoingLoading = true;
    _outgoingError = null;
    try {
      _outgoingInvitations = await _repo.groupInvitations(groupId);
    } on AppError catch (e) {
      _outgoingError = e.message;
    } catch (e, st) {
      AppLogger.error('Outgoing invitations load failed: $e', stackTrace: st);
      _outgoingError = GroupErrors.map(
        e.toString(),
        context: GroupErrorContext.invitation,
      );
    }
    _outgoingLoading = false;
  }

  Future<void> retryOutgoingInvitations() async {
    if (!canManageMembers || _outgoingLoading) return;
    notifyListeners();
    await _loadOutgoingInvitations();
    notifyListeners();
  }

  /// Cancels a pending invitation (exact-row DELETE under the live policy).
  /// The list is re-read from the server afterwards, success or failure.
  Future<bool> cancelInvitation(GroupInvitation inv) async {
    if (!inv.isPending) {
      _error = 'Only a pending invitation can be cancelled.';
      notifyListeners();
      return false;
    }
    return _actOnInvitation(inv, () => _repo.cancelInvitation(inv.id));
  }

  /// Re-invites a declined invitee: DELETE the declined row, INSERT a new
  /// pending one (two steps; the repository reports an incomplete second step
  /// explicitly). Never offered for pending / accepted / expired rows or for
  /// someone who is already a member.
  Future<bool> reinvite(GroupInvitation inv) async {
    if (!canReinvite(inv)) {
      _error = inv.status == GroupInvitation.statusDeclined
          ? 'This person is already a member.'
          : 'Only a declined invitation can be sent again.';
      notifyListeners();
      return false;
    }
    return _actOnInvitation(inv, () => _repo.reinvite(inv));
  }

  Future<bool> _actOnInvitation(
    GroupInvitation inv,
    Future<void> Function() body,
  ) async {
    if (!canManageMembers) {
      _error = GroupErrors.map(
        'NOT_AUTHORIZED',
        context: GroupErrorContext.invitation,
      );
      notifyListeners();
      return false;
    }
    if (_actingInvitationId == inv.id || _busy) return false;
    _actingInvitationId = inv.id;
    _error = null;
    notifyListeners();
    try {
      await body();
      await _loadOutgoingInvitations();
      return true;
    } on AppError catch (e) {
      _error = e.message;
      await _loadOutgoingInvitations(); // server truth, never a guess
      return false;
    } catch (e, st) {
      AppLogger.error('Invitation action failed: $e', stackTrace: st);
      _error = GroupErrors.map(
        e.toString(),
        context: GroupErrorContext.invitation,
      );
      await _loadOutgoingInvitations();
      return false;
    } finally {
      _actingInvitationId = null;
      notifyListeners();
    }
  }

  Future<void> retryJoinRequests() async {
    if (!canManageMembers || _joinRequestsLoading) return;
    notifyListeners();
    await _loadJoinRequests();
    notifyListeners();
  }

  /// Approves or declines via `fn_approve_group_join_request(id, approve)`.
  /// Only the request id is sent — the server derives the group from the
  /// row and checks MANAGE_MEMBERS there. On approval the whole hub reloads
  /// (members, count, queue) so the new member comes from the server row the
  /// function inserted; on decline only the queue is re-read. Any error is
  /// mapped and followed by a server re-read — nothing is fabricated.
  Future<bool> decideJoinRequest(
    GroupJoinRequest request, {
    required bool approve,
  }) async {
    if (!canManageMembers) {
      _error = GroupErrors.map(
        'NOT_AUTHORIZED',
        context: GroupErrorContext.joinRequest,
      );
      notifyListeners();
      return false;
    }
    if (_actingRequestId == request.id || _busy) return false;
    _actingRequestId = request.id;
    _error = null;
    notifyListeners();
    try {
      await _repo.decideJoinRequest(request.id, approve: approve);
      if (approve) {
        await load();
      } else {
        await _loadJoinRequests();
      }
      return true;
    } on AppError catch (e) {
      _error = e.message;
      await _loadJoinRequests();
      return false;
    } catch (e, st) {
      AppLogger.error('Join request decision failed: $e', stackTrace: st);
      _error = GroupErrors.map(
        e.toString(),
        context: GroupErrorContext.joinRequest,
      );
      await _loadJoinRequests();
      return false;
    } finally {
      _actingRequestId = null;
      notifyListeners();
    }
  }

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

  // ── Group Rules (G6) ──

  Future<void> _loadRules() async {
    _rulesLoading = true;
    _rulesError = null;
    try {
      _rules = await _repo.groupRules(groupId);
    } on AppError catch (e) {
      _rules = const [];
      _rulesError = e.message;
    } catch (e, st) {
      AppLogger.error('Group rules load failed: $e', stackTrace: st);
      _rules = const [];
      _rulesError = GroupErrors.map(
        e.toString(),
        context: GroupErrorContext.load,
      );
    }
    _rulesLoading = false;
  }

  Future<void> retryRules() async {
    if (_rulesLoading) return;
    notifyListeners();
    await _loadRules();
    notifyListeners();
  }

  /// UX-only pre-check mirroring the live gate (GROUP_SETTINGS or owner);
  /// the `group_rules` RLS is the boundary and is exercised regardless.
  bool _ruleMutationAllowed() {
    if (canEditBasics) return true;
    _error = GroupErrors.map(
      'NOT_AUTHORIZED',
      context: GroupErrorContext.update,
    );
    notifyListeners();
    return false;
  }

  /// Creates a rule. Single-flight. Re-reads after success or failure.
  Future<bool> createRule(String ruleText) async {
    if (_rulesSaving || _busy) return false;
    if (!_ruleMutationAllowed()) return false;
    final trimmed = ruleText.trim();
    if (trimmed.isEmpty) {
      _error = 'Rule text cannot be empty.';
      notifyListeners();
      return false;
    }
    _rulesSaving = true;
    _error = null;
    notifyListeners();
    try {
      await _repo.createRule(groupId: groupId, ruleText: trimmed);
      await _loadRules();
      return true;
    } on AppError catch (e) {
      _error = e.message;
      await _loadRules();
      return false;
    } catch (e, st) {
      AppLogger.error('Create rule failed: $e', stackTrace: st);
      _error = GroupErrors.map(e.toString(), context: GroupErrorContext.update);
      await _loadRules();
      return false;
    } finally {
      _rulesSaving = false;
      notifyListeners();
    }
  }

  /// Updates a rule's text. Single-flight per rule. Re-reads after.
  Future<bool> updateRule(GroupRule rule, String ruleText) async {
    if (_rulesSaving || _actingRuleId == rule.id || _busy) return false;
    if (!_ruleMutationAllowed()) return false;
    final trimmed = ruleText.trim();
    if (trimmed.isEmpty) {
      _error = 'Rule text cannot be empty.';
      notifyListeners();
      return false;
    }
    _actingRuleId = rule.id;
    _rulesSaving = true;
    _error = null;
    notifyListeners();
    try {
      await _repo.updateRule(ruleId: rule.id, ruleText: trimmed);
      await _loadRules();
      return true;
    } on AppError catch (e) {
      _error = e.message;
      await _loadRules();
      return false;
    } catch (e, st) {
      AppLogger.error('Update rule failed: $e', stackTrace: st);
      _error = GroupErrors.map(e.toString(), context: GroupErrorContext.update);
      await _loadRules();
      return false;
    } finally {
      _actingRuleId = null;
      _rulesSaving = false;
      notifyListeners();
    }
  }

  /// Deletes a rule. Single-flight per rule. Re-reads after.
  Future<bool> deleteRule(GroupRule rule) async {
    if (_rulesSaving || _actingRuleId == rule.id || _busy) return false;
    if (!_ruleMutationAllowed()) return false;
    _actingRuleId = rule.id;
    _rulesSaving = true;
    _error = null;
    notifyListeners();
    try {
      await _repo.deleteRule(rule.id);
      await _loadRules();
      return true;
    } on AppError catch (e) {
      _error = e.message;
      await _loadRules();
      return false;
    } catch (e, st) {
      AppLogger.error('Delete rule failed: $e', stackTrace: st);
      _error = GroupErrors.map(e.toString(), context: GroupErrorContext.update);
      await _loadRules();
      return false;
    } finally {
      _actingRuleId = null;
      _rulesSaving = false;
      notifyListeners();
    }
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
