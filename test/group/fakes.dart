// In-memory GroupRepository that mirrors the live server rules, so the
// controller tests exercise the same outcomes the database produces:
//   * rpc_get_user_groups  → owned or joined groups only, never invite_code
//   * fn_create_group      → group + owner membership + leader permissions
//   * fn_join_group        → member for public/private, NULL (join request)
//                            for restricted, idempotent for an existing member
//   * group_members RLS    → self-delete (leave) always; deleting someone else
//                            needs MANAGE_MEMBERS
//   * groups UPDATE RLS    → GROUP_SETTINGS or owner; GROUP_SETTINGS is seeded
//                            for no role, so [settingsGrant] models an explicit
//                            role_permissions row
//   * groups.privacy CHECK → public | private | restricted

import 'package:my_praperation/core/errors/app_error.dart';
import 'package:my_praperation/core/models/group.dart';
import 'package:my_praperation/core/models/group_announcement.dart';
import 'package:my_praperation/core/models/group_invitation.dart';
import 'package:my_praperation/core/models/group_join_request.dart';
import 'package:my_praperation/core/models/group_member.dart';
import 'package:my_praperation/core/models/group_message.dart';
import 'package:my_praperation/core/models/group_rule.dart';
import 'package:my_praperation/core/models/profile_match.dart';
import 'package:my_praperation/features/group/data/group_repository.dart';
import 'package:my_praperation/features/group/domain/group_errors.dart';
import 'package:my_praperation/features/group/domain/group_permission.dart';
import 'package:my_praperation/features/group/domain/group_role.dart';

class FakeGroup {
  FakeGroup({
    required this.id,
    required this.name,
    required this.ownerId,
    this.description = '',
    this.privacy = 'public',
    this.inviteCode = 'CODE1234',
    this.logoUrl,
  });

  final String id;
  String name;
  String description;
  final String ownerId;
  String privacy;
  String inviteCode;
  String? logoUrl;
  final Map<String, String> roles = {}; // userId -> group_role
  final List<GroupRule> rules = [];
  final List<GroupAnnouncement> announcements = [];
  final List<GroupMessage> messages = [];
  DateTime createdAt = DateTime(2026, 9, 1);
}

class InMemoryGroupRepository implements GroupRepository {
  InMemoryGroupRepository({this.currentUser = 'u-me'});

  String currentUser;
  final Map<String, FakeGroup> groups = {};
  final List<String> calls = [];
  final List<String> joinRequests = [];
  int nextId = 1;

  /// Optional profile fields per user id, mirroring the profiles embed.
  final Map<String, String> profileNames = {};
  final Map<String, String> studentCodes = {};
  final Map<String, String> bios = {};

  /// Thrown by the next mutating call, to exercise the error paths.
  Object? failNextWith;

  /// `'<groupId>:<userId>'` pairs holding GROUP_SETTINGS (see header).
  final Set<String> settingsGrant = {};

  FakeGroup seed({
    String? id,
    String name = 'Physics Group',
    String ownerId = 'u-owner',
    String privacy = 'public',
    String inviteCode = 'CODE1234',
    String? logoUrl,
    Map<String, String> members = const {},
  }) {
    final g = FakeGroup(
      id: id ?? 'g-${nextId++}',
      name: name,
      ownerId: ownerId,
      privacy: privacy,
      inviteCode: inviteCode,
      logoUrl: logoUrl,
    );
    g.roles[ownerId] = 'owner';
    g.roles.addAll(members);
    groups[g.id] = g;
    return g;
  }

  void _maybeFail() {
    final f = failNextWith;
    if (f != null) {
      failNextWith = null;
      throw f;
    }
  }

  DataError _notAuthorized(GroupErrorContext ctx) =>
      DataError(message: GroupErrors.map('NOT_AUTHORIZED', context: ctx));

  Group _toGroup(FakeGroup g, {bool withProfile = false}) => Group(
    id: g.id,
    name: g.name,
    ownerId: g.ownerId,
    createdAt: g.createdAt,
    memberCount: g.roles.length,
    logoUrl: g.logoUrl,
    userRole: g.roles[currentUser] ?? 'member',
    description: withProfile ? g.description : null,
    privacy: withProfile ? g.privacy : null,
  );

  @override
  Future<List<Group>> myGroups() async {
    calls.add('myGroups');
    return [
      for (final g in groups.values)
        if (g.roles.containsKey(currentUser) || g.ownerId == currentUser)
          _toGroup(g),
    ];
  }

  @override
  Future<Group?> groupForMember(String groupId) async {
    calls.add('groupForMember:$groupId');
    final g = groups[groupId];
    // Membership, not readability: a public group is readable by anyone.
    if (g == null || !g.roles.containsKey(currentUser)) return null;
    return _toGroup(g, withProfile: true);
  }

  @override
  Future<List<GroupMember>> members(String groupId) async {
    calls.add('members:$groupId');
    final g = groups[groupId];
    if (g == null || !g.roles.containsKey(currentUser)) return const [];
    return [
      for (final e in g.roles.entries)
        GroupMember(
          groupId: groupId,
          userId: e.key,
          role: e.value,
          joinedAt: DateTime(2026, 9, 1),
          fullName: profileNames[e.key] ?? 'User ${e.key}',
          studentCode: studentCodes[e.key],
          bio: bios[e.key],
        ),
    ];
  }

  @override
  Future<String> create({
    required String name,
    String description = '',
    String privacy = 'public',
  }) async {
    calls.add('create:$name');
    _maybeFail();
    final trimmed = name.trim();
    if (trimmed.isEmpty || trimmed.length > 80) {
      throw DataError(
        message: GroupErrors.map(
          'INVALID_NAME',
          context: GroupErrorContext.create,
        ),
      );
    }
    if (!const ['public', 'private', 'restricted'].contains(privacy)) {
      throw DataError(
        message: GroupErrors.map(
          'INVALID_PRIVACY',
          context: GroupErrorContext.create,
        ),
      );
    }
    final g = seed(
      name: trimmed,
      ownerId: currentUser,
      privacy: privacy,
      inviteCode: 'CODE${nextId}000',
    );
    g.description = description.trim();
    return g.id;
  }

  @override
  Future<JoinOutcome> joinByCode(String inviteCode) async {
    calls.add('join:$inviteCode');
    _maybeFail();
    final code = inviteCode.trim().toUpperCase();
    final g = groups.values.where((x) => x.inviteCode == code).firstOrNull;
    if (g == null) {
      throw DataError(
        message: GroupErrors.map(
          'INVALID_INVITE_CODE',
          context: GroupErrorContext.join,
        ),
      );
    }
    if (g.roles.containsKey(currentUser)) {
      return JoinedGroup(g.id, alreadyMember: true);
    }
    if (g.privacy == 'restricted') {
      joinRequests.add('${g.id}:$currentUser');
      requestStatus['${g.id}:$currentUser'] = 'pending'; // upsert → pending
      return const JoinRequestFiled();
    }
    g.roles[currentUser] = 'member';
    return JoinedGroup(g.id);
  }

  @override
  Future<void> leave(String groupId) async {
    calls.add('leave:$groupId');
    _maybeFail();
    groups[groupId]?.roles.remove(currentUser);
  }

  @override
  Future<void> removeMember({
    required String groupId,
    required String userId,
  }) async {
    calls.add('remove:$groupId:$userId');
    _maybeFail();
    final g = groups[groupId];
    if (g == null) throw _notAuthorized(GroupErrorContext.removeMember);
    if (userId == currentUser) {
      throw _notAuthorized(GroupErrorContext.removeMember);
    }
    if (!await canManageMembers(groupId)) {
      throw _notAuthorized(GroupErrorContext.removeMember);
    }
    g.roles.remove(userId);
  }

  @override
  Future<bool> canManageMembers(String groupId) async =>
      hasPermission(groupId, GroupPermission.manageMembers);

  @override
  Future<bool> canEditSettings(String groupId) async =>
      hasPermission(groupId, GroupPermission.groupSettings);

  /// Extra `role_permissions` rows beyond the live seeding, as
  /// `'<groupId>:<role>:<PERMISSION>'`.
  final Set<String> roleGrants = {};

  /// Mirrors live `fn_has_permission`: owner → true; otherwise the role must
  /// hold a `role_permissions` row. Live seeding (fn_create_group) gives the
  /// leader 10 permissions — everything except GROUP_SETTINGS and
  /// MANAGE_ROLES; moderator and member hold nothing.
  bool hasPermission(String groupId, GroupPermission p) {
    final g = groups[groupId];
    if (g == null) return false;
    final role = g.roles[currentUser];
    if (role == null) return false;
    if (role == 'owner') return true;
    if (settingsGrant.contains('$groupId:$currentUser') &&
        p == GroupPermission.groupSettings) {
      return true;
    }
    if (roleGrants.contains('$groupId:$role:${p.db}')) return true;
    if (role == 'leader') {
      return p != GroupPermission.groupSettings &&
          p != GroupPermission.manageRoles &&
          p != GroupPermission.unknown;
    }
    return false;
  }

  @override
  Future<GroupPermissions> permissionsFor(
    String groupId, {
    List<GroupPermission> of = GroupPermission.live,
  }) async {
    calls.add('permissionsFor:$groupId');
    return GroupPermissions({
      for (final p in of)
        if (hasPermission(groupId, p)) p,
    });
  }

  /// Mirrors the LIVE "role changes" UPDATE policy as verified by the G3
  /// audit (docs/G3_LIVE_AUDIT_AND_CLOSURE.md):
  ///   USING  (role <> 'owner') AND fn_has_permission(group_id, uid, 'MANAGE_ROLES')
  ///   CHECK  (role <> 'owner') AND fn_has_permission(group_id, uid, 'MANAGE_ROLES')
  /// There is no self-update branch; owner rows cannot be targeted and no row
  /// may become 'owner'. Under RLS a row that fails USING simply does not
  /// match (0 rows updated); a new row failing CHECK raises.
  @override
  Future<void> setMemberRole({
    required String groupId,
    required String userId,
    required GroupRole role,
  }) async {
    calls.add('setRole:$groupId:$userId:${role.db}');
    _maybeFail();
    final g = groups[groupId];
    if (g == null || !g.roles.containsKey(userId)) {
      // No row matches → PostgREST updates 0 rows silently.
      return;
    }
    final manage = hasPermission(groupId, GroupPermission.manageRoles);
    // USING: owner rows and non-managers never match → 0 rows, no change.
    if (!manage || g.roles[userId] == 'owner') return;
    // CHECK: the new row may not be 'owner'.
    if (role.isOwner) {
      throw const DataError(
        message: 'new row violates row-level security policy for table "group_members"',
      );
    }
    g.roles[userId] = role.db;
  }

  @override
  Future<void> updateBasics({
    required String groupId,
    required String name,
    required String description,
    String? privacy,
  }) async {
    calls.add('updateBasics:$groupId');
    _maybeFail();
    final g = groups[groupId];
    if (g == null || !await canEditSettings(groupId)) {
      throw _notAuthorized(GroupErrorContext.update);
    }
    if (privacy != null &&
        !const ['public', 'private', 'restricted'].contains(privacy)) {
      throw const DataError(
        message: 'violates check constraint "groups_privacy_check"',
      );
    }
    g.name = name.trim();
    g.description = description.trim();
    if (privacy != null) g.privacy = privacy;
  }

  @override
  Future<void> clearLogo(String groupId) async {
    calls.add('clearLogo:$groupId');
    _maybeFail();
    final g = groups[groupId];
    if (g == null || !await canEditSettings(groupId)) {
      throw _notAuthorized(GroupErrorContext.update);
    }
    g.logoUrl = null;
  }

  /// Every invite-code read/rotation, so tests can prove non-settings flows
  /// never touch it.
  final List<String> inviteCodeReads = [];
  int rotations = 0;

  /// Live: `groups.invite_code` is row-readable by members (and by anyone for
  /// public groups). The client only calls this from the gated settings flow.
  @override
  Future<String> inviteCode(String groupId) async {
    inviteCodeReads.add(groupId);
    _maybeFail();
    final g = groups[groupId];
    final visible =
        g != null &&
        (g.roles.containsKey(currentUser) || g.privacy == 'public');
    if (!visible) {
      throw const DataError(message: 'Invite code is not available.');
    }
    return g.inviteCode;
  }

  /// Live `fn_reset_group_invite`: GROUP_SETTINGS or owner, else NOT_AUTHORIZED;
  /// server generates the new code.
  @override
  Future<String> rotateInviteCode(String groupId) async {
    calls.add('rotate:$groupId');
    _maybeFail();
    if (!await canEditSettings(groupId)) {
      throw _notAuthorized(GroupErrorContext.inviteCode);
    }
    rotations++;
    final g = groups[groupId]!;
    g.inviteCode = 'ROT${rotations.toString().padLeft(5, '0')}';
    return g.inviteCode;
  }

  /// Join requests as live rows: `'<groupId>:<userId>' -> status`. The
  /// `joinRequests` list (G1) keeps recording filings for older tests.
  final Map<String, String> requestStatus = {};
  int _requestSeq = 0;
  final Map<String, String> _requestIds = {};

  /// Broad reads the client must never make (tracked to prove it).
  final List<String> requestReads = [];

  GroupJoinRequest _request(String key, String status) {
    final parts = key.split(':');
    final id = _requestIds.putIfAbsent(key, () => 'r-${++_requestSeq}');
    return GroupJoinRequest(
      id: id,
      groupId: parts[0],
      userId: parts[1],
      status: status,
      createdAt: DateTime(2026, 9, 10),
    );
  }

  /// Live SELECT policy: own rows (or MANAGE_MEMBERS, not used here).
  @override
  Future<GroupJoinRequest?> myJoinRequest(String groupId) async {
    requestReads.add('mine:$groupId');
    final key = '$groupId:$currentUser';
    final status = requestStatus[key];
    return status == null ? null : _request(key, status);
  }

  @override
  Future<List<GroupJoinRequest>> myPendingJoinRequests() async {
    requestReads.add('mine:pending');
    return [
      for (final e in requestStatus.entries)
        if (e.key.endsWith(':$currentUser') && e.value == 'pending')
          _request(e.key, e.value),
    ];
  }

  /// Live SELECT policy on group_join_requests: own row OR MANAGE_MEMBERS on
  /// the row's group. Returned rows are whatever RLS lets the caller see.
  @override
  Future<List<GroupJoinRequest>> pendingJoinRequests(String groupId) async {
    requestReads.add('group:$groupId');
    final manage = hasPermission(groupId, GroupPermission.manageMembers);
    return [
      for (final e in requestStatus.entries)
        if (e.key.startsWith('$groupId:') &&
            e.value == 'pending' &&
            (manage || e.key.endsWith(':$currentUser')))
          _request(e.key, e.value),
    ];
  }

  /// Live `fn_approve_group_join_request(p_request_id, p_approve)`: loads the
  /// row, derives its group, requires MANAGE_MEMBERS **on that group** else
  /// NOT_AUTHORIZED; approve → membership ON CONFLICT DO NOTHING + approved;
  /// decline → declined. Only the request id is received.
  @override
  Future<void> decideJoinRequest(
    String requestId, {
    required bool approve,
  }) async {
    calls.add('decide:$requestId:$approve');
    _maybeFail();
    final key = _requestIds.entries
        .where((e) => e.value == requestId)
        .map((e) => e.key)
        .firstOrNull;
    final status = key == null ? null : requestStatus[key];
    if (key == null || status == null) {
      throw _notAuthorized(GroupErrorContext.joinRequest); // row not visible
    }
    final groupId = key.split(':')[0];
    final userId = key.split(':')[1];
    if (!hasPermission(groupId, GroupPermission.manageMembers)) {
      throw _notAuthorized(GroupErrorContext.joinRequest);
    }
    if (approve) {
      groups[groupId]?.roles.putIfAbsent(userId, () => 'member');
      requestStatus[key] = 'approved';
    } else {
      requestStatus[key] = 'declined';
    }
  }

  /// Seeds a pending request and returns its id (as the live row would have).
  String seedJoinRequest({required String groupId, required String userId}) {
    final key = '$groupId:$userId';
    requestStatus[key] = 'pending';
    return _request(key, 'pending').id;
  }

  /// Live `fn_withdraw_join_request(p_request_id)`: loads the row by id,
  /// verifies user_id = currentUser and status = 'pending', deletes the row.
  /// Raises JOIN_REQUEST_NOT_FOUND on any failure (not found, not owner,
  /// not pending). Only the request id is received.
  @override
  Future<void> withdrawJoinRequest(String requestId) async {
    calls.add('withdraw:$requestId');
    _maybeFail();
    final key = _requestIds.entries
        .where((e) => e.value == requestId)
        .map((e) => e.key)
        .firstOrNull;
    final status = key == null ? null : requestStatus[key];
    if (key == null || status == null) {
      throw DataError(
        message: GroupErrors.map(
          'JOIN_REQUEST_NOT_FOUND',
          context: GroupErrorContext.joinRequest,
        ),
      );
    }
    final parts = key.split(':');
    final userId = parts[1];
    if (userId != currentUser) {
      throw DataError(
        message: GroupErrors.map(
          'JOIN_REQUEST_NOT_FOUND',
          context: GroupErrorContext.joinRequest,
        ),
      );
    }
    if (status != 'pending') {
      throw DataError(
        message: GroupErrors.map(
          'JOIN_REQUEST_NOT_FOUND',
          context: GroupErrorContext.joinRequest,
        ),
      );
    }
    requestStatus.remove(key);
    _requestIds.remove(key);
  }

  /// Invitations as live rows.
  final List<GroupInvitation> invitations = [];
  final List<String> invitationReads = [];

  GroupInvitation seedInvitation({
    required String id,
    required String groupId,
    String inviterId = 'u-owner',
    String? inviteeId,
    String status = 'pending',
  }) {
    final inv = GroupInvitation(
      id: id,
      groupId: groupId,
      inviterId: inviterId,
      inviteeId: inviteeId ?? currentUser,
      status: status,
      createdAt: DateTime(2026, 9, 12, 9, 30),
    );
    invitations.add(inv);
    return inv;
  }

  /// Live SELECT policy: invitee OR inviter OR member. The client only ever
  /// asks for its own invitee rows, pending.
  @override
  Future<List<GroupInvitation>> myInvitations() async {
    invitationReads.add('mine:pending');
    return [
      for (final i in invitations)
        if (i.inviteeId == currentUser && i.isPending) i,
    ];
  }

  GroupInvitation? _pendingMine(String id) {
    for (final i in invitations) {
      if (i.id == id && i.inviteeId == currentUser && i.isPending) return i;
    }
    return null;
  }

  void _setInvitationStatus(String id, String status) {
    final idx = invitations.indexWhere((i) => i.id == id);
    final i = invitations[idx];
    invitations[idx] = GroupInvitation(
      id: i.id,
      groupId: i.groupId,
      inviterId: i.inviterId,
      inviteeId: i.inviteeId,
      status: status,
      createdAt: i.createdAt,
    );
  }

  /// Live `fn_accept_group_invitation`: invitee + pending else
  /// INVITE_NOT_FOUND; membership inserted ON CONFLICT DO NOTHING; group_id
  /// taken from the row.
  @override
  Future<void> acceptInvitation(String invitationId) async {
    calls.add('acceptInvitation:$invitationId');
    _maybeFail();
    final inv = _pendingMine(invitationId);
    if (inv == null) {
      throw DataError(
        message: GroupErrors.map(
          'INVITE_NOT_FOUND',
          context: GroupErrorContext.invitation,
        ),
      );
    }
    groups[inv.groupId]?.roles.putIfAbsent(currentUser, () => 'member');
    _setInvitationStatus(invitationId, 'accepted');
  }

  @override
  Future<void> declineInvitation(String invitationId) async {
    calls.add('declineInvitation:$invitationId');
    _maybeFail();
    if (_pendingMine(invitationId) == null) {
      throw DataError(
        message: GroupErrors.map(
          'INVITE_NOT_FOUND',
          context: GroupErrorContext.invitation,
        ),
      );
    }
    _setInvitationStatus(invitationId, 'declined');
  }

  /// Live SELECT policy: invitee OR inviter OR fn_is_member.
  @override
  Future<List<GroupInvitation>> groupInvitations(String groupId) async {
    invitationReads.add('group:$groupId');
    final member = groups[groupId]?.roles.containsKey(currentUser) ?? false;
    return [
      for (final i in invitations)
        if (i.groupId == groupId &&
            (member ||
                i.inviteeId == currentUser ||
                i.inviterId == currentUser))
          i,
    ];
  }

  /// Live DELETE policy: inviter_id = uid OR MANAGE_MEMBERS on the row's
  /// group. A non-matching row deletes 0 rows → the repository throws.
  @override
  Future<void> cancelInvitation(String invitationId) async {
    calls.add('cancelInvitation:$invitationId');
    _maybeFail();
    final idx = invitations.indexWhere((i) => i.id == invitationId);
    final i = idx < 0 ? null : invitations[idx];
    final allowed =
        i != null &&
        (i.inviterId == currentUser ||
            hasPermission(i.groupId, GroupPermission.manageMembers));
    if (!allowed) {
      throw const DataError(
        message:
            'This invitation could not be cancelled. It may already be gone, '
            'or you do not have permission for it.',
      );
    }
    invitations.removeAt(idx);
  }

  /// Thrown by the INSERT step of [reinvite] only (to exercise the explicit
  /// two-step failure).
  Object? failInsertWith;
  int _inviteSeq = 100;

  /// Live INSERT policy: inviter_id = uid AND MANAGE_MEMBERS;
  /// UNIQUE(group_id, invitee_id).
  Future<void> _insertInvitation(String groupId, String inviteeId) async {
    calls.add('insertInvitation:$groupId:$inviteeId');
    final f = failInsertWith;
    if (f != null) {
      failInsertWith = null;
      throw f;
    }
    if (!hasPermission(groupId, GroupPermission.manageMembers)) {
      throw _notAuthorized(GroupErrorContext.invitation);
    }
    if (invitations.any(
      (i) => i.groupId == groupId && i.inviteeId == inviteeId,
    )) {
      throw const DataError(
        message: 'duplicate key value violates unique constraint',
      );
    }
    invitations.add(
      GroupInvitation(
        id: 'i-${++_inviteSeq}',
        groupId: groupId,
        inviterId: currentUser,
        inviteeId: inviteeId,
        status: 'pending',
        createdAt: DateTime(2026, 9, 13),
      ),
    );
  }

  /// Registered users the resolver can find: student code -> user id.
  /// Mirrors `rpc_find_profile_by_student_code`: exact match after
  /// upper(trim()), at most one row, only id/full_name/avatar_url/student_code.
  final Map<String, String> registry = {};
  final List<String> lookups = [];

  @override
  Future<ProfileMatch?> findProfileByStudentCode(String code) async {
    final norm = code.trim().toUpperCase();
    lookups.add(norm);
    _maybeFail();
    if (norm.isEmpty) return null;
    final id = registry[norm];
    if (id == null) return null;
    return ProfileMatch(
      id: id,
      fullName: profileNames[id] ?? 'User $id',
      studentCode: norm,
      avatarUrl: null,
    );
  }

  @override
  Future<void> sendInvitation({
    required String groupId,
    required String inviteeId,
  }) async {
    _maybeFail();
    await _insertInvitation(groupId, inviteeId);
  }

  @override
  Future<void> reinvite(GroupInvitation declined) async {
    if (declined.status != 'declined') {
      throw const ValidationError(
        message: 'Only a declined invitation can be sent again.',
      );
    }
    await cancelInvitation(declined.id);
    try {
      await _insertInvitation(declined.groupId, declined.inviteeId);
    } on AppError catch (e) {
      throw DataError(
        message:
            '$reinviteIncompletePrefix (${e.message}). Nothing is pending for '
            'this person — use Re-invite again once the problem is resolved.',
      );
    }
  }

  // ── Group Rules (G6) ──
  // Mirrors the proposed group_rules RLS:
  //   SELECT              → fn_is_member(group_id, uid)
  //   INSERT/UPDATE/DELETE → fn_has_permission(group_id, uid, GROUP_SETTINGS)
  //                          OR role = owner  (= canEditSettings here)
  // A row the caller may not update/delete is simply not matched (0 rows),
  // which the real repository reports as "could not be updated/deleted".

  int _ruleSeq = 0;

  bool _isMemberOf(String groupId) =>
      groups[groupId]?.roles.containsKey(currentUser) ?? false;

  @override
  Future<List<GroupRule>> groupRules(String groupId) async {
    calls.add('groupRules:$groupId');
    if (!_isMemberOf(groupId)) return const [];
    final rules = List<GroupRule>.of(groups[groupId]!.rules)
      ..sort((a, b) {
        final byPos = a.position.compareTo(b.position);
        return byPos != 0 ? byPos : a.createdAt.compareTo(b.createdAt);
      });
    return rules;
  }

  @override
  Future<void> createRule({
    required String groupId,
    required String ruleText,
  }) async {
    calls.add('createRule:$groupId');
    _maybeFail();
    final g = groups[groupId];
    if (g == null || !await canEditSettings(groupId)) {
      throw _notAuthorized(GroupErrorContext.update);
    }
    final text = ruleText.trim();
    if (text.isEmpty || text.length > 2000) {
      // CHECK (char_length(btrim(rule_text)) BETWEEN 1 AND 2000)
      throw const DataError(message: 'check constraint');
    }
    final maxPos = g.rules.isEmpty
        ? 0
        : g.rules.map((r) => r.position).reduce((a, b) => a > b ? a : b) + 1;
    final now = DateTime(2026, 9, 15, 12, _ruleSeq);
    _ruleSeq++;
    g.rules.add(
      GroupRule(
        id: 'rule-$_ruleSeq',
        groupId: groupId,
        ruleText: text,
        position: maxPos,
        createdAt: now,
        updatedAt: now,
      ),
    );
  }

  /// Rows the caller could UPDATE/DELETE under the policy.
  Iterable<(FakeGroup, int)> _writableRuleRows(String ruleId) sync* {
    for (final g in groups.values) {
      if (!hasPermission(g.id, GroupPermission.groupSettings)) continue;
      for (var i = 0; i < g.rules.length; i++) {
        if (g.rules[i].id == ruleId) yield (g, i);
      }
    }
  }

  @override
  Future<void> updateRule({
    required String ruleId,
    required String ruleText,
  }) async {
    calls.add('updateRule:$ruleId');
    _maybeFail();
    final text = ruleText.trim();
    final hit = _writableRuleRows(ruleId).firstOrNull;
    if (hit == null) {
      throw const DataError(
        message: 'This rule could not be updated. It may have been removed.',
      );
    }
    if (text.isEmpty || text.length > 2000) {
      throw const DataError(message: 'check constraint');
    }
    final (g, i) = hit;
    g.rules[i] = g.rules[i].copyWith(
      ruleText: text,
      updatedAt: DateTime(2026, 9, 15, 13),
    );
  }

  @override
  Future<void> deleteRule(String ruleId) async {
    calls.add('deleteRule:$ruleId');
    _maybeFail();
    final hit = _writableRuleRows(ruleId).firstOrNull;
    if (hit == null) {
      throw const DataError(
        message: 'This rule could not be deleted. It may have been removed.',
      );
    }
    final (g, i) = hit;
    g.rules.removeAt(i);
  }

  // ── Group Announcements (G7) ──
  // Mirrors the legacy-defined `group_announcements` RLS (0020/0033/0040):
  //   SELECT               → fn_is_member(group_id, uid)
  //   INSERT               → SEND_ANNOUNCEMENT or owner (author_id = uid)
  //   UPDATE/DELETE (ALL)  → SEND_ANNOUNCEMENT or owner (USING + CHECK)
  // Leader holds SEND_ANNOUNCEMENT by the live seeding; moderator/member do
  // not. A row the caller may not update/delete is simply not matched.

  int _announcementSeq = 0;

  bool _canSendAnnouncement(String groupId) =>
      hasPermission(groupId, GroupPermission.sendAnnouncement);

  @override
  Future<List<GroupAnnouncement>> announcements(String groupId) async {
    calls.add('announcements:$groupId');
    if (!_isMemberOf(groupId)) return const [];
    final rows = List<GroupAnnouncement>.of(groups[groupId]!.announcements)
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return rows;
  }

  @override
  Future<void> createAnnouncement({
    required String groupId,
    required String title,
    required String body,
  }) async {
    calls.add('createAnnouncement:$groupId');
    _maybeFail();
    final g = groups[groupId];
    if (g == null || !_canSendAnnouncement(groupId)) {
      throw _notAuthorized(GroupErrorContext.announcement);
    }
    final t = title.trim();
    final b = body.trim();
    if (t.isEmpty || t.length > 120 || b.isEmpty || b.length > 2000) {
      throw const DataError(message: 'check constraint');
    }
    _announcementSeq++;
    final now = DateTime(2026, 9, 15, 12, _announcementSeq);
    g.announcements.add(
      GroupAnnouncement(
        id: 'a-$_announcementSeq',
        groupId: groupId,
        authorId: currentUser,
        title: t,
        body: b,
        createdAt: now,
        updatedAt: now,
      ),
    );
  }

  Iterable<(FakeGroup, int)> _writableAnnouncementRows(String id) sync* {
    for (final g in groups.values) {
      if (!_canSendAnnouncement(g.id)) continue;
      for (var i = 0; i < g.announcements.length; i++) {
        if (g.announcements[i].id == id) yield (g, i);
      }
    }
  }

  @override
  Future<void> updateAnnouncement({
    required String announcementId,
    required String title,
    required String body,
  }) async {
    calls.add('updateAnnouncement:$announcementId');
    _maybeFail();
    final hit = _writableAnnouncementRows(announcementId).firstOrNull;
    if (hit == null) {
      throw const DataError(
        message:
            'This announcement could not be updated. It may have been removed.',
      );
    }
    final t = title.trim();
    final b = body.trim();
    if (t.isEmpty || t.length > 120 || b.isEmpty || b.length > 2000) {
      throw const DataError(message: 'check constraint');
    }
    final (g, i) = hit;
    g.announcements[i] = g.announcements[i].copyWith(
      title: t,
      body: b,
      updatedAt: DateTime(2026, 9, 15, 13),
    );
  }

  @override
  Future<void> deleteAnnouncement(String announcementId) async {
    calls.add('deleteAnnouncement:$announcementId');
    _maybeFail();
    final hit = _writableAnnouncementRows(announcementId).firstOrNull;
    if (hit == null) {
      throw const DataError(
        message:
            'This announcement could not be deleted. It may have been removed.',
      );
    }
    final (g, i) = hit;
    g.announcements.removeAt(i);
  }

  // ── Group Chat (G8) ──
  // Mirrors the legacy-defined `group_messages` RLS (0001_init, unchanged):
  //   SELECT → fn_is_member(group_id, uid)
  //   INSERT → sender_id = auth.uid() AND fn_is_member(group_id, uid)
  //   no UPDATE / DELETE policy (deletion only via fn_delete_group_message,
  //   out of G8 scope). body CHECK 1..2000. sender_id nullable live (system
  //   notices) — [seedSystemMessage] models those server-side inserts.

  int _messageSeq = 0;

  GroupMessage seedMessage({
    required String groupId,
    required String? senderId,
    required String body,
    DateTime? at,
  }) {
    _messageSeq++;
    // Default clock: strictly after the group's newest message (the server's
    // `now()` default is monotonic in practice), so a sent message is last.
    final existing = groups[groupId]!.messages;
    final newest = existing.isEmpty
        ? DateTime(2026, 9, 10, 9, 0)
        : existing.map((m) => m.createdAt).reduce((a, b) => a.isAfter(b) ? a : b);
    final m = GroupMessage(
      id: 'm-$_messageSeq',
      groupId: groupId,
      senderId: senderId,
      body: body,
      createdAt: at ?? newest.add(const Duration(minutes: 1)),
    );
    groups[groupId]!.messages.add(m);
    return m;
  }

  @override
  Future<List<GroupMessage>> messages(
    String groupId, {
    int limit = messagePageSize,
    DateTime? before,
  }) async {
    calls.add('messages:$groupId${before == null ? '' : ':before'}');
    if (!_isMemberOf(groupId)) return const [];
    final rows = [
      for (final m in groups[groupId]!.messages)
        if (before == null || m.createdAt.isBefore(before)) m,
    ]..sort((a, b) {
      final byTime = b.createdAt.compareTo(a.createdAt);
      return byTime != 0 ? byTime : b.id.compareTo(a.id);
    });
    return rows.take(limit).toList(growable: false);
  }

  @override
  Future<void> sendMessage({required String groupId, required String body}) =>
      insertMessageAs(groupId: groupId, senderId: currentUser, body: body);

  /// The INSERT policy as the server evaluates it, with the row's
  /// `sender_id` explicit so tests can prove a forged sender is refused.
  /// The real repository always sends the signed-in uid.
  Future<void> insertMessageAs({
    required String groupId,
    required String senderId,
    required String body,
  }) async {
    calls.add('sendMessage:$groupId');
    _maybeFail();
    final g = groups[groupId];
    if (g == null || senderId != currentUser || !_isMemberOf(groupId)) {
      throw _notAuthorized(GroupErrorContext.chat);
    }
    final b = body.trim();
    if (b.isEmpty || b.length > 2000) {
      throw const DataError(message: 'check constraint');
    }
    seedMessage(groupId: groupId, senderId: senderId, body: b);
  }
}
