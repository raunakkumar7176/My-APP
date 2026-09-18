/// The live `public.group_role` enum. Values and order are the database's;
/// nothing here invents a role.
///
/// Capability note (live): every group policy is written as
/// `fn_has_permission(group, uid, <PERM>) OR fn_get_group_role(group, uid) = 'owner'`
/// and `fn_create_group` seeds `role_permissions` rows **only for `leader`**.
/// So the owner is permitted by the role branch, the leader by seeded
/// permissions, and `moderator` currently has no seeded permissions at all.
/// The getters below mirror that exactly and are UX-only — the server
/// decides every mutation.
enum GroupRole {
  owner,
  leader,
  moderator,
  member;

  static GroupRole fromDb(String? value) {
    switch (value?.trim().toLowerCase()) {
      case 'owner':
        return GroupRole.owner;
      case 'leader':
        return GroupRole.leader;
      case 'moderator':
        return GroupRole.moderator;
      default:
        return GroupRole.member;
    }
  }

  String get db => name;

  String get label {
    switch (this) {
      case GroupRole.owner:
        return 'Owner';
      case GroupRole.leader:
        return 'Leader';
      case GroupRole.moderator:
        return 'Moderator';
      case GroupRole.member:
        return 'Member';
    }
  }

  bool get isOwner => this == GroupRole.owner;

  /// Mirrors the live seeding: owner (role branch) and leader (seeded
  /// `MANAGE_MEMBERS`) may remove members. Confirmed per group against
  /// `fn_has_permission` before the action is offered.
  bool get mayManageMembersByDefault =>
      this == GroupRole.owner || this == GroupRole.leader;

  /// Live `groups` UPDATE policy: `GROUP_SETTINGS` or owner. `GROUP_SETTINGS`
  /// is not seeded for any role, so today only the owner passes.
  bool get mayEditGroupByDefault => this == GroupRole.owner;
}
