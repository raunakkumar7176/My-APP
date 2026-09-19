import 'group_permission.dart';
import 'group_role.dart';

/// G14 — which management controls a group screen may *offer*. Pure rules over
/// the server-reported [GroupPermissions] (one `fn_has_permission` probe per
/// value) plus the caller's own role. `fn_has_permission` already returns
/// true for the owner; the owner is accepted locally too so a failed probe
/// never hides the owner's own controls. Every rule here is UX only — the
/// live RLS / RPC decides the mutation.
final class GroupControls {
  const GroupControls({required this.permissions, required this.isOwner});

  final GroupPermissions permissions;
  final bool isOwner;

  bool _has(GroupPermission p) => isOwner || permissions.has(p);

  /// `groups` UPDATE policy: GROUP_SETTINGS or owner.
  bool get canOpenSettings => _has(GroupPermission.groupSettings);

  /// `group_members` DELETE "manage members" / invitations / join requests.
  bool get canManageMembers => _has(GroupPermission.manageMembers);

  /// `group_members` UPDATE "role changes".
  bool get canManageRoles => _has(GroupPermission.manageRoles);

  /// `role_permissions` policy "manage roles perms" (FOR ALL, MANAGE_ROLES;
  /// owner through the function's bypass).
  bool get canManageRolePermissions => _has(GroupPermission.manageRoles);

  bool get canCreateTest => _has(GroupPermission.createTest);
  bool get canEditTest => _has(GroupPermission.editTest);
  bool get canPublishTest => _has(GroupPermission.publishTest);
  bool get canScheduleTest => _has(GroupPermission.scheduleTest);
  bool get canGenerateResults => _has(GroupPermission.generateResults);
  bool get canViewAnalytics => _has(GroupPermission.viewGroupAnalytics);
  bool get canSendAnnouncement => _has(GroupPermission.sendAnnouncement);

  /// Any G10 test-management capability.
  bool get canManageTests =>
      canCreateTest || canEditTest || canPublishTest || canScheduleTest;

  /// Whether the "Manage" surface is shown at all. A plain member (no
  /// seeded permissions) never sees it.
  bool get hasAnyManagement =>
      canOpenSettings ||
      canManageMembers ||
      canManageRoles ||
      canManageTests ||
      canGenerateResults ||
      canViewAnalytics ||
      canSendAnnouncement;

  /// Short labels of the granted test capabilities, in lifecycle order.
  List<String> get testCapabilities => [
    if (canCreateTest) 'create',
    if (canEditTest) 'edit',
    if (canPublishTest) 'publish',
    if (canScheduleTest) 'schedule',
    if (canGenerateResults) 'results',
  ];
}

/// Rules for editing `role_permissions` rows. The live table keys on
/// `(group_id, role, permission)` and accepts any `group_role`; the client
/// deliberately offers fewer targets:
///   * `owner` — never a row: the owner is permitted by `fn_has_permission`'s
///     own bypass, so a row would be meaningless and misleading;
///   * `member` — never offered: every joiner lands in this role, so a grant
///     here would hand management to anyone who joins.
final class RolePermissionRules {
  const RolePermissionRules._();

  static const editableRoles = [GroupRole.leader, GroupRole.moderator];

  static bool canEditRole(GroupRole role) => editableRoles.contains(role);

  /// The permissions that may be granted or revoked (the live enum; `unknown`
  /// is never sent).
  static const editablePermissions = GroupPermission.live;

  static bool canEditPermission(GroupPermission p) =>
      p != GroupPermission.unknown && editablePermissions.contains(p);
}

/// The group's `role_permissions` rows, as the server returned them.
final class GroupRolePermissions {
  const GroupRolePermissions(this._byRole);

  static const empty = GroupRolePermissions({});

  final Map<GroupRole, Set<GroupPermission>> _byRole;

  /// Builds from raw `{role, permission}` rows; unknown labels are dropped.
  factory GroupRolePermissions.fromRows(List<Map<String, dynamic>> rows) {
    final map = <GroupRole, Set<GroupPermission>>{};
    for (final r in rows) {
      final p = GroupPermission.fromDb(r['permission'] as String?);
      if (p == GroupPermission.unknown) continue;
      map.putIfAbsent(GroupRole.fromDb(r['role'] as String?), () => {}).add(p);
    }
    return GroupRolePermissions(map);
  }

  bool has(GroupRole role, GroupPermission p) =>
      _byRole[role]?.contains(p) ?? false;

  Set<GroupPermission> of(GroupRole role) =>
      Set.unmodifiable(_byRole[role] ?? const {});

  int get rowCount => _byRole.values.fold(0, (n, s) => n + s.length);
}

/// Human labels for the live permission values (display only).
extension GroupPermissionLabel on GroupPermission {
  String get label {
    switch (this) {
      case GroupPermission.groupSettings:
        return 'Group settings';
      case GroupPermission.manageMembers:
        return 'Manage members';
      case GroupPermission.manageRoles:
        return 'Manage roles & permissions';
      case GroupPermission.createTest:
        return 'Create tests';
      case GroupPermission.editTest:
        return 'Edit tests';
      case GroupPermission.generateQuestions:
        return 'Generate questions';
      case GroupPermission.reviewQuestions:
        return 'Review questions';
      case GroupPermission.publishTest:
        return 'Publish tests';
      case GroupPermission.scheduleTest:
        return 'Schedule tests';
      case GroupPermission.generateResults:
        return 'Generate results';
      case GroupPermission.viewGroupAnalytics:
        return 'View analytics & leaderboards';
      case GroupPermission.sendAnnouncement:
        return 'Send announcements';
      case GroupPermission.unknown:
        return 'Unknown';
    }
  }
}
