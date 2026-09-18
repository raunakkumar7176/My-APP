/// Maps the raw errors the live group functions raise into user-facing text.
///
/// The codes come from the deployed function bodies: `fn_create_group`
/// raises `AUTH_REQUIRED`, `INVALID_NAME`, `INVALID_PRIVACY`,
/// `FN_ENSURE_PROFILE_FAILED`, `FK_PROFILE_MISSING`, `GROUPS_INSERT_FAILED`,
/// `GROUP_MEMBERS_INSERT_FAILED`, `ROLE_PERMISSIONS_INSERT_FAILED`;
/// `fn_join_group` raises `AUTH_REQUIRED` / `INVALID_INVITE_CODE`;
/// `fn_approve_group_join_request` and `fn_reset_group_invite` raise
/// `NOT_AUTHORIZED`. Nothing is invented here: unknown text falls back to a
/// neutral message and the raw error stays in the log.
enum GroupErrorContext {
  load,
  create,
  join,
  leave,
  removeMember,
  update,
  changeRole,
  inviteCode,
}

class GroupErrors {
  const GroupErrors._();

  /// The live CHECK on `groups.name`: 1..80 characters.
  static const nameMinLength = 1;
  static const nameMaxLength = 80;

  static String map(String raw, {required GroupErrorContext context}) {
    final lower = raw.toLowerCase();

    if (lower.contains('auth_required') ||
        lower.contains('jwt') ||
        lower.contains('not authenticated')) {
      return 'Please sign in again to continue.';
    }
    if (lower.contains('invalid_invite_code')) {
      return 'That invite code does not match any group. Check it and try again.';
    }
    if (lower.contains('invalid_name')) {
      return 'Group name must be between $nameMinLength and $nameMaxLength characters.';
    }
    if (lower.contains('invalid_privacy')) {
      return 'That privacy setting is not allowed.';
    }
    // trg_owner_guard (fn_prevent_owner_removal) on group_members.
    if (lower.contains('cannot_demote_owner')) {
      return 'The group owner cannot be demoted.';
    }
    if (lower.contains('cannot_remove_owner')) {
      return 'The group owner cannot be removed from the group.';
    }
    if (lower.contains('invalid input value for enum')) {
      return 'That role is not valid.';
    }
    if (lower.contains('not_authorized') ||
        lower.contains('row-level security') ||
        lower.contains('violates row-level') ||
        lower.contains('permission denied')) {
      switch (context) {
        case GroupErrorContext.removeMember:
          return 'You do not have permission to remove members from this group.';
        case GroupErrorContext.update:
          return 'You do not have permission to change this group.';
        case GroupErrorContext.changeRole:
          return 'You do not have permission to change roles in this group.';
        case GroupErrorContext.inviteCode:
          return 'Only the group owner or a member with the settings permission can manage the invite code.';
        default:
          return 'You do not have permission to do that.';
      }
    }
    if (lower.contains('duplicate key') || lower.contains('already exists')) {
      return 'You are already a member of this group.';
    }
    if (lower.contains('fk_profile_missing') ||
        lower.contains('fn_ensure_profile_failed')) {
      return 'Your profile could not be prepared. Please reopen the app and try again.';
    }
    if (lower.contains('socketexception') ||
        lower.contains('failed host lookup') ||
        lower.contains('network') ||
        lower.contains('clientexception') ||
        lower.contains('timeout')) {
      return 'Network error. Please check your connection and try again.';
    }

    switch (context) {
      case GroupErrorContext.load:
        return 'Could not load groups. Please try again.';
      case GroupErrorContext.create:
        return 'Could not create the group. Please try again.';
      case GroupErrorContext.join:
        return 'Could not join the group. Please try again.';
      case GroupErrorContext.leave:
        return 'Could not leave the group. Please try again.';
      case GroupErrorContext.removeMember:
        return 'Could not remove that member. Please try again.';
      case GroupErrorContext.update:
        return 'Could not save the group. Please try again.';
      case GroupErrorContext.changeRole:
        return 'Could not change that role. Please try again.';
      case GroupErrorContext.inviteCode:
        return 'Could not load the invite code. Please try again.';
    }
  }

  /// Client-side mirror of the live `groups.name` CHECK. Returns null when
  /// the trimmed name is acceptable; the server re-validates regardless.
  static String? validateName(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return 'Group name is required.';
    if (trimmed.length > nameMaxLength) {
      return 'Group name must be $nameMaxLength characters or fewer.';
    }
    return null;
  }

  /// Invite codes are 8 characters, stored upper-case and compared after
  /// `upper(trim(...))` by `fn_join_group`.
  static String? validateInviteCode(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return 'Invite code is required.';
    return null;
  }

  static String normalizeInviteCode(String value) => value.trim().toUpperCase();
}
