// In-memory GroupRepository that mirrors the live server rules, so the
// controller tests exercise the same outcomes the database produces:
//   * rpc_get_user_groups  → owned or joined groups only, never invite_code
//   * fn_create_group      → group + owner membership + leader permissions
//   * fn_join_group        → member for public/private, NULL (join request)
//                            for restricted, idempotent for an existing member
//   * group_members RLS    → self-delete (leave) always; deleting someone else
//                            needs MANAGE_MEMBERS
//   * groups UPDATE RLS    → GROUP_SETTINGS or owner (only owner in practice)

import 'package:my_praperation/core/errors/app_error.dart';
import 'package:my_praperation/core/models/group.dart';
import 'package:my_praperation/core/models/group_member.dart';
import 'package:my_praperation/features/group/data/group_repository.dart';
import 'package:my_praperation/features/group/domain/group_errors.dart';

class FakeGroup {
  FakeGroup({
    required this.id,
    required this.name,
    required this.ownerId,
    this.description = '',
    this.privacy = 'public',
    this.inviteCode = 'CODE1234',
  });

  final String id;
  String name;
  String description;
  final String ownerId;
  final String privacy;
  final String inviteCode;
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

  /// Thrown by the next mutating call, to exercise the error paths.
  Object? failNextWith;

  FakeGroup seed({
    String? id,
    String name = 'Physics Group',
    String ownerId = 'u-owner',
    String privacy = 'public',
    String inviteCode = 'CODE1234',
    Map<String, String> members = const {},
  }) {
    final g = FakeGroup(
      id: id ?? 'g-${nextId++}',
      name: name,
      ownerId: ownerId,
      privacy: privacy,
      inviteCode: inviteCode,
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

  Group _toGroup(FakeGroup g, {bool withProfile = false}) => Group(
    id: g.id,
    name: g.name,
    ownerId: g.ownerId,
    createdAt: g.createdAt,
    memberCount: g.roles.length,
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
          fullName: 'User ${e.key}',
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
    if (g == null)
      throw DataError(
        message: GroupErrors.map(
          'INVALID_INVITE_CODE',
          context: GroupErrorContext.join,
        ),
      );
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
    if (g == null)
      throw DataError(
        message: GroupErrors.map(
          'NOT_AUTHORIZED',
          context: GroupErrorContext.removeMember,
        ),
      );
    if (userId == currentUser)
      throw DataError(
        message: GroupErrors.map(
          'NOT_AUTHORIZED',
          context: GroupErrorContext.removeMember,
        ),
      );
    if (!await canManageMembers(groupId)) {
      throw DataError(
        message: GroupErrors.map(
          'NOT_AUTHORIZED',
          context: GroupErrorContext.removeMember,
        ),
      );
    }
    g.roles.remove(userId);
  }

  @override
  Future<bool> canManageMembers(String groupId) async {
    final g = groups[groupId];
    if (g == null) return false;
    // Live seeding: owner passes by role, leader by seeded MANAGE_MEMBERS.
    final role = g.roles[currentUser];
    return role == 'owner' || role == 'leader';
  }

  @override
  Future<void> updateBasics({
    required String groupId,
    required String name,
    required String description,
  }) async {
    calls.add('updateBasics:$groupId');
    _maybeFail();
    final g = groups[groupId];
    if (g == null || g.roles[currentUser] != 'owner') {
      throw DataError(
        message: GroupErrors.map(
          'NOT_AUTHORIZED',
          context: GroupErrorContext.removeMember,
        ),
      );
    }
    g.name = name.trim();
    g.description = description.trim();
  }
}
