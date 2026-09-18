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
import 'package:my_praperation/core/models/group_member.dart';
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
  final String inviteCode;
  String? logoUrl;
  final Map<String, String> roles = {}; // userId -> group_role
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
}
