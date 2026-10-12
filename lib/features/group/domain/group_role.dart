/// The live `public.group_role` enum, collapsed to the app-facing role set
/// (migration 0108): owner, admin, member. The enum itself still carries
/// unused `leader`/`moderator` values server-side (Postgres cannot cheaply
/// drop an enum value) but no row is ever written with them again —
/// [fromDb] maps either legacy value to [admin] defensively, in case a
/// stale cached row or an old client is ever read.
///
/// Capability note (live): every group policy is written as
/// `fn_has_permission(group, uid, <PERM>) OR fn_get_group_role(group, uid) = 'owner'`.
/// `fn_create_group` seeds `role_permissions` rows for `leader`, and
/// `fn_has_permission` (0062) gives `admin` an automatic fallback onto that
/// same seeded set — so admin already holds every permission a leader did,
/// with no further seeding needed. The getters below mirror that and are
/// UX-only — the server decides every mutation.
enum GroupRole {
  owner,
  admin,
  member;

  static GroupRole fromDb(String? value) {
    switch (value?.trim().toLowerCase()) {
      case 'owner':
        return GroupRole.owner;
      case 'admin':
      case 'leader':
      case 'moderator':
        return GroupRole.admin;
      default:
        return GroupRole.member;
    }
  }

  String get db => name;

  String get label {
    switch (this) {
      case GroupRole.owner:
        return 'Owner';
      case GroupRole.admin:
        return 'Admin';
      case GroupRole.member:
        return 'Member';
    }
  }

  bool get isOwner => this == GroupRole.owner;
  bool get isAdmin => this == GroupRole.admin;

  /// Mirrors the live seeding: owner (role branch) and admin (seeded via
  /// the leader fallback) may remove members. Confirmed per group against
  /// `fn_has_permission` before the action is offered. Per product
  /// decision, only the owner may remove an admin — enforced server-side
  /// by `trg_owner_guard` (migration 0108), mirrored here for the UI.
  bool get mayManageMembersByDefault =>
      this == GroupRole.owner || this == GroupRole.admin;

  /// Live `groups` UPDATE policy: `GROUP_SETTINGS` or owner. `GROUP_SETTINGS`
  /// is not seeded for any role, so today only the owner passes.
  bool get mayEditGroupByDefault => this == GroupRole.owner;
}
