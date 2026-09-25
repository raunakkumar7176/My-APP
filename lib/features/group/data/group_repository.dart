import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/errors/app_error.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/models/group.dart';
import '../../../core/models/group_announcement.dart';
import '../../../core/models/group_invitation.dart';
import '../../../core/models/group_join_request.dart';
import '../../../core/models/group_member.dart';
import '../../../core/models/group_message.dart';
import '../../../core/models/group_rule.dart';
import '../../../core/models/profile_match.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/services/supabase_service.dart';
import '../domain/group_controls.dart';
import '../domain/group_errors.dart';
import '../domain/group_permission.dart';
import '../domain/group_role.dart';

/// Outcome of `fn_join_group`. The live function returns the group id when the
/// caller became a member and **NULL when the group is `restricted`**, where
/// it files a row in `group_join_requests` instead. Both are successes.
sealed class JoinOutcome {
  const JoinOutcome();
}

class JoinedGroup extends JoinOutcome {
  const JoinedGroup(this.groupId, {this.alreadyMember = false});
  final String groupId;

  /// `fn_join_group` returns the group id unchanged for an existing member,
  /// so a repeated join is idempotent rather than an error.
  final bool alreadyMember;
}

class JoinRequestFiled extends JoinOutcome {
  const JoinRequestFiled();
}

/// Marker text for the non-atomic re-invite failing after its first step:
/// the declined row is gone and no new invitation exists. Kept as a constant
/// so the controller and tests recognise it without a new error type
/// (`AppError` is sealed).
const reinviteIncompletePrefix =
    'The previous declined invitation was removed but the new invitation '
    'could not be sent';

/// The single group data source for the whole app (the R4 test feature reads
/// `myGroups()` through this same interface). Every method maps to a live
/// object; nothing here assumes a column or function that does not exist.
abstract interface class GroupRepository {
  /// `rpc_get_user_groups()` — owned or joined groups only, 7 columns, no
  /// `invite_code`.
  Future<List<Group>> myGroups();

  /// The group's basic profile plus the caller's own membership. Returns null
  /// when the group does not exist or the caller is not a member of it.
  Future<Group?> groupForMember(String groupId);

  /// `group_members` + embedded `profiles`, readable to fellow members.
  Future<List<GroupMember>> members(String groupId);

  /// `fn_create_group(name, description, privacy)` — creates the group, the
  /// owner membership row and the default leader permissions server-side.
  Future<String> create({
    required String name,
    String description = '',
    String privacy = 'public',
  });

  /// `fn_join_group(invite_code)`.
  Future<JoinOutcome> joinByCode(String inviteCode);

  /// Deletes the caller's own `group_members` row (live policy
  /// "self leave group").
  Future<void> leave(String groupId);

  /// Deletes another member's row. The live policy "manage members" requires
  /// `MANAGE_MEMBERS` and `user_id <> auth.uid()`; the server is the gate.
  Future<void> removeMember({required String groupId, required String userId});

  /// `fn_has_permission(group, uid, 'MANAGE_MEMBERS')` — used only to decide
  /// whether to offer the action.
  Future<bool> canManageMembers(String groupId);

  /// `fn_has_permission(group, uid, 'GROUP_SETTINGS')`. The function itself
  /// returns true for the owner, so this mirrors the live `groups` UPDATE
  /// policy (`GROUP_SETTINGS` OR owner) without a client-side role guess.
  Future<bool> canEditSettings(String groupId);

  /// One `fn_has_permission` probe per requested permission (the live,
  /// verified signature). Owner is reported true for everything by the
  /// function itself. A failed probe reads as "not granted"; the server still
  /// refuses the mutation regardless.
  Future<GroupPermissions> permissionsFor(
    String groupId, {
    List<GroupPermission> of = GroupPermission.live,
  });

  /// Changes another member's role via a direct `group_members` UPDATE.
  /// Live policy "role changes" (G3 audit, verified): USING and CHECK are
  /// both `(role <> 'owner') AND fn_has_permission(group_id, uid,
  /// 'MANAGE_ROLES')` — no self-update branch, owner rows cannot be targeted,
  /// no row may become owner; `trg_owner_guard` additionally protects the
  /// owner. No RPC is needed; the policy is the security boundary.
  Future<void> setMemberRole({
    required String groupId,
    required String userId,
    required GroupRole role,
  });

  /// Updates `groups.name` / `groups.description` and, when given, `privacy`
  /// (live CHECK: public | private | restricted). The live UPDATE policy
  /// requires `GROUP_SETTINGS` or the owner role.
  Future<void> updateBasics({
    required String groupId,
    required String name,
    required String description,
    String? privacy,
  });

  /// Sets `groups.logo_url` to NULL. Same UPDATE policy. The storage object
  /// (if any) is not touched: no group-scoped storage policy exists live.
  Future<void> clearLogo(String groupId);

  /// The group's `invite_code`, read as a single explicit column by exact id.
  /// Called only from the permission-gated settings flow; never from list,
  /// hub, members or any other screen. The value is never logged or cached.
  Future<String> inviteCode(String groupId);

  /// `fn_reset_group_invite(p_group)` — the server generates and returns the
  /// new code (GROUP_SETTINGS or owner; `NOT_AUTHORIZED` otherwise). Nothing
  /// is generated client-side.
  Future<String> rotateInviteCode(String groupId);

  /// The caller's own join request for [groupId], or null. Exact group id +
  /// the caller's own user id; the live SELECT policy (`user_id = uid` OR
  /// MANAGE_MEMBERS) is the boundary — no other user's row is ever asked for.
  Future<GroupJoinRequest?> myJoinRequest(String groupId);

  /// The caller's own **pending** requests across groups (own rows only —
  /// `fn_join_group` returns NULL for a restricted group without telling the
  /// client which group it was, so this is how the pending state is found).
  Future<List<GroupJoinRequest>> myPendingJoinRequests();

  /// Pending join requests of one group (exact `group_id`, `status='pending'`).
  /// The live SELECT policy (own row OR MANAGE_MEMBERS) decides what comes
  /// back; the client calls this only for managers, and never across groups.
  /// No requester profile is embedded: a requester is not a member, so their
  /// `profiles` row is not readable under the live policy.
  Future<List<GroupJoinRequest>> pendingJoinRequests(String groupId);

  /// `fn_approve_group_join_request(p_request_id, p_approve)`. The server
  /// loads the request, derives its group, checks MANAGE_MEMBERS for **that**
  /// group, and inserts the membership itself on approval. Only the request
  /// id is sent; no group id is ever passed as authorization.
  Future<void> decideJoinRequest(String requestId, {required bool approve});

  /// The caller's own **pending incoming** invitations (`invitee_id = uid`).
  /// One query, the five live columns, nothing about the group or inviter:
  /// a non-member cannot read a private/restricted group's row, so nothing
  /// is embedded that RLS would withhold.
  Future<List<GroupInvitation>> myInvitations();

  /// `fn_accept_group_invitation(p_invitation_id)` — the server checks the caller
  /// is the invitee and the row is pending, inserts the membership itself,
  /// and raises `INVITATION_NOT_FOUND` / `INVITATION_NOT_PENDING` otherwise.
  /// No client-side table write.
  Future<void> acceptInvitation(String invitationId);

  /// `fn_decline_group_invitation(p_invitation_id)` — same guards.
  Future<void> declineInvitation(String invitationId);

  /// Outgoing / managed invitations of one group (exact `group_id`, all
  /// statuses). The live SELECT policy (invitee ∨ inviter ∨ member) decides
  /// visibility; the client calls this only for MANAGE_MEMBERS holders and
  /// never across groups. No invitee profile is embedded (not readable for a
  /// non-member; no lookup exists).
  Future<List<GroupInvitation>> groupInvitations(String groupId);

  /// Deletes exactly one invitation row by id under the live DELETE policy
  /// (`inviter_id = uid OR MANAGE_MEMBERS`). Throws when no row was deleted
  /// (not permitted, or already gone) — a 0-row delete is never a success.
  Future<void> cancelInvitation(String invitationId);

  /// Re-invites after a decline. `UNIQUE(group_id, invitee_id)` forces two
  /// steps: DELETE the declined row (DELETE policy), then INSERT a new pending
  /// row with the caller as inviter (INSERT policy `inviter_id = uid AND
  /// MANAGE_MEMBERS`). Not atomic: if the INSERT fails after the DELETE
  /// succeeded, a [DataError] starting with [reinviteIncompletePrefix] is thrown so the caller can say
  /// exactly that — the declined record is gone and no new invitation exists.
  Future<void> reinvite(GroupInvitation declined);

  /// `rpc_find_profile_by_student_code(p_code)` — exact-match lookup of one
  /// registered user (id, full_name, avatar_url, student_code). Null when no
  /// such code. Called only from the manager-gated invite flow; the result is
  /// never cached beyond that sheet.
  Future<ProfileMatch?> findProfileByStudentCode(String code);

  /// `fn_withdraw_join_request(p_request_id)` — deletes the caller's own
  /// pending join request. The server verifies: caller owns the request
  /// (`user_id = auth.uid()`), the request is `pending`, and deletes exactly
  /// that row. Touches no other table. Raises [DataError] on any failure
  /// (not found, not owner, not pending, auth).
  Future<void> withdrawJoinRequest(String requestId);

  /// Inserts one pending `group_invitations` row `{group_id, invitee_id}`;
  /// `inviter_id` is the authenticated user (the live INSERT policy requires
  /// `inviter_id = auth.uid() AND MANAGE_MEMBERS`). Touches no other table.
  /// A `UNIQUE(group_id, invitee_id)` violation surfaces as an [AppError]
  /// whose message contains "already".
  Future<void> sendInvitation({
    required String groupId,
    required String inviteeId,
  });

  // ── Role permissions (G14) — existing `public.role_permissions` ──

  /// All `{role, permission}` rows of one group (exact `group_id`). Live
  /// SELECT policy "members view perms": any member may read them.
  Future<GroupRolePermissions> rolePermissions(String groupId);

  /// Inserts or deletes exactly one `role_permissions` row
  /// `(group_id, role, permission)`. Live policy "manage roles perms"
  /// (FOR ALL, USING + CHECK `fn_has_permission(group_id, uid,
  /// 'MANAGE_ROLES')`; the owner passes through the function's bypass) is the
  /// security boundary. A revoke that deletes 0 rows is an error, never a
  /// silent success. Role / permission targets are validated by
  /// [RolePermissionRules] before anything is sent.
  Future<void> setRolePermission({
    required String groupId,
    required GroupRole role,
    required GroupPermission permission,
    required bool granted,
  });

  // ── Group Rules (G6) ──

  /// All rules for one group, ordered by position then created_at.
  /// RLS: members only.
  Future<List<GroupRule>> groupRules(String groupId);

  /// Creates a rule. RLS: GROUP_SETTINGS or owner (live groups UPDATE gate).
  Future<void> createRule({required String groupId, required String ruleText});

  /// Updates a rule's text. RLS: GROUP_SETTINGS or owner (live groups UPDATE gate).
  Future<void> updateRule({required String ruleId, required String ruleText});

  /// Deletes a rule. RLS: GROUP_SETTINGS or owner (live groups UPDATE gate).
  Future<void> deleteRule(String ruleId);

  // ── Group Announcements (G7) — existing `public.group_announcements` ──

  /// Announcements of one group, newest first. RLS "members read
  /// announcements": member only (and, where the 0040 columns exist, only
  /// published / not expired rows — the server decides, the client never
  /// filters).
  Future<List<GroupAnnouncement>> announcements(String groupId);

  /// Inserts `{group_id, author_id = auth.uid(), title, body}`. RLS
  /// "leaders create announcements": SEND_ANNOUNCEMENT or owner.
  Future<void> createAnnouncement({
    required String groupId,
    required String title,
    required String body,
  });

  /// Updates title/body by exact id. RLS "leaders manage announcements"
  /// (FOR ALL, SEND_ANNOUNCEMENT or owner, USING + CHECK). 0 rows ⇒ error.
  Future<void> updateAnnouncement({
    required String announcementId,
    required String title,
    required String body,
  });

  /// Deletes by exact id under the same policy. 0 rows ⇒ error.
  Future<void> deleteAnnouncement(String announcementId);

  // ── Group Chat (G8) — existing `public.group_messages` ──

  /// A finite window of one group's messages, **newest first**, at most
  /// [limit] rows; with [before] only rows created strictly earlier (the
  /// "load earlier" page). RLS "member reads messages": `fn_is_member`.
  Future<List<GroupMessage>> messages(
    String groupId, {
    int limit = messagePageSize,
    DateTime? before,
  });

  /// Inserts `{group_id, sender_id = auth.uid(), body}`. RLS "member sends
  /// messages": `sender_id = auth.uid() AND fn_is_member(group_id, uid)` —
  /// the server rejects any other sender and any group the caller is not in.
  Future<void> sendMessage({required String groupId, required String body});

  /// Subscribes to live INSERT/UPDATE events on `group_messages` for
  /// [groupId] via the existing Supabase Realtime publication (already
  /// carries this table — see migrations 0037/0049; this method is the
  /// first CLIENT-side use of it, not a new server capability). [onInsert]
  /// fires for a new message, [onUpdate] for a soft-delete (`deleted_at`
  /// set); [onConnectionChange] reports whether the channel is currently
  /// joined, for a "Reconnecting…" indicator. Call [GroupMessageSubscription
  /// .cancel] exactly once, when the screen using it is disposed — never
  /// leave a channel open past that.
  GroupMessageSubscription subscribeToMessages({
    required String groupId,
    required void Function(GroupMessage message) onInsert,
    required void Function(GroupMessage message) onUpdate,
    void Function(bool connected)? onConnectionChange,
  });

  /// Deletes a group that has exactly one member (its owner) — the only
  /// case a group can be deleted at all (`rpc_delete_group`, server-side
  /// authoritative: owner + solo-member check both re-verified there, not
  /// just here). Hard delete: `groups` has never had a soft-delete column
  /// (unlike `tests`), so this follows that table's own existing design
  /// rather than inventing one.
  Future<void> deleteGroup(String groupId);

  // ── Chat unread state (existing `message_reads` / RPCs from 0027) —
  // previously unused by the client; wired here so the groups list can
  // show a real per-group unread badge and preview. ──

  /// Batched unread count per group, via `fn_get_group_unread_counts`
  /// (server-side: excludes the caller's own messages and anything soft
  /// deleted, compares against the caller's `message_reads.last_read_at`).
  /// Groups with no unread rows are simply absent from the result map.
  Future<Map<String, int>> unreadCounts(List<String> groupIds);

  /// Upserts the caller's `message_reads.last_read_at = now()` for
  /// [groupId] via `fn_mark_group_read` (server re-verifies membership).
  Future<void> markGroupRead(String groupId);

  /// Batched latest-message preview per group, via
  /// `fn_latest_group_messages` (soft-delete-safe: a deleted message's
  /// `body` comes back null with `isDeleted = true`).
  Future<Map<String, GroupLatestMessage>> latestMessages(
    List<String> groupIds,
  );
}

/// One group's most recent message, for a list-screen preview. Mirrors
/// `fn_latest_group_messages`'s row shape exactly — not a general chat
/// model (see [GroupMessage] for that).
class GroupLatestMessage {
  const GroupLatestMessage({
    required this.groupId,
    required this.id,
    required this.body,
    required this.createdAt,
    required this.senderId,
    required this.senderName,
    required this.isDeleted,
  });

  factory GroupLatestMessage.fromJson(Map<String, dynamic> json) =>
      GroupLatestMessage(
        groupId: json['group_id'] as String,
        id: json['id'] as String,
        body: json['body'] as String?,
        createdAt: DateTime.parse(json['created_at'] as String),
        senderId: json['sender_id'] as String?,
        senderName: json['sender_name'] as String? ?? 'Member',
        isDeleted: json['is_deleted'] as bool? ?? false,
      );

  final String groupId;
  final String id;

  /// Null when [isDeleted] — the server never sends a deleted body.
  final String? body;
  final DateTime createdAt;
  final String? senderId;
  final String senderName;
  final bool isDeleted;

  String get preview => isDeleted ? 'Message deleted' : (body ?? '');
}

/// A live subscription handle. Exactly one [cancel] call releases the
/// underlying Realtime channel.
abstract interface class GroupMessageSubscription {
  Future<void> cancel();
}

/// Default chat window; one page per hub open, older pages on demand.
const messagePageSize = 50;

class SupabaseGroupRepository implements GroupRepository {
  const SupabaseGroupRepository();

  SupabaseClient get _client => SupabaseService.client;

  static String? get _uid => AuthService.currentUser?.id;

  @override
  Future<List<Group>> myGroups() => _guard(GroupErrorContext.load, () async {
    final response = await _client.rpc('rpc_get_user_groups');
    AppLogger.rpcShape('rpc_get_user_groups', response);
    if (response == null) return const <Group>[];
    final list = response is List ? response : [response];
    return [for (final r in list) Group.fromJson(r as Map<String, dynamic>)];
  });

  @override
  Future<Group?> groupForMember(String groupId) => _guard(
    GroupErrorContext.load,
    () async {
      final uid = _uid;
      if (uid == null) throw const AuthError(message: 'Please sign in again.');

      // Membership decides access, not readability: the live
      // "public groups are discoverable" policy lets any signed-in user
      // read a public group's row without belonging to it.
      final membership = await _client
          .from('group_members')
          .select('role')
          .eq('group_id', groupId)
          .eq('user_id', uid)
          .maybeSingle();
      if (membership == null) return null;

      // Explicit columns: `invite_code` is never selected here.
      final row = await _client
          .from('groups')
          .select(
            'id, name, description, logo_url, owner_id, privacy, created_at',
          )
          .eq('id', groupId)
          .maybeSingle();
      if (row == null) return null;

      final count = await _client
          .from('group_members')
          .count(CountOption.exact)
          .eq('group_id', groupId);

      return Group.fromJson({
        ...row,
        'member_count': count,
        'user_role': membership['role'],
      });
    },
  );

  @override
  Future<List<GroupMember>> members(String groupId) =>
      _guard(GroupErrorContext.load, () async {
        final rows = await _client
            .from('group_members')
            .select(
              'group_id, user_id, role, joined_at, profiles(full_name, avatar_url, student_code, bio)',
            )
            .eq('group_id', groupId)
            .order('joined_at');
        return [
          for (final r in rows as List)
            GroupMember.fromJson(r as Map<String, dynamic>),
        ];
      });

  @override
  Future<String> create({
    required String name,
    String description = '',
    String privacy = 'public',
  }) => _guard(GroupErrorContext.create, () async {
    final response = await _client.rpc(
      'fn_create_group',
      params: {
        'p_name': name.trim(),
        'p_description': description.trim(),
        'p_privacy': privacy,
      },
    );
    AppLogger.rpcShape('fn_create_group', response);
    final id = response is Map
        ? response['id'] ?? response['fn_create_group']
        : response;
    if (id is! String || id.isEmpty) {
      throw const DataError(
        message: 'The group was not created. Please try again.',
      );
    }
    return id;
  });

  @override
  Future<JoinOutcome> joinByCode(String inviteCode) => _guard(
    GroupErrorContext.join,
    () async {
      final response = await _client.rpc(
        'fn_join_group',
        params: {'p_invite_code': GroupErrors.normalizeInviteCode(inviteCode)},
      );
      AppLogger.rpcShape('fn_join_group', response);
      // NULL is the documented "restricted → join request filed" answer.
      if (response == null) return const JoinRequestFiled();
      final id = response is Map
          ? (response['id'] ?? response['fn_join_group'])
          : response;
      if (id is! String || id.isEmpty) return const JoinRequestFiled();
      return JoinedGroup(id);
    },
  );

  @override
  Future<void> leave(String groupId) => _guard(
    GroupErrorContext.leave,
    () async {
      final uid = _uid;
      if (uid == null) throw const AuthError(message: 'Please sign in again.');
      await _client
          .from('group_members')
          .delete()
          .eq('group_id', groupId)
          .eq('user_id', uid);
    },
  );

  @override
  Future<void> removeMember({
    required String groupId,
    required String userId,
  }) => _guard(GroupErrorContext.removeMember, () async {
    await _client
        .from('group_members')
        .delete()
        .eq('group_id', groupId)
        .eq('user_id', userId);
  });

  @override
  Future<bool> canManageMembers(String groupId) =>
      _hasPermission(groupId, 'MANAGE_MEMBERS');

  @override
  Future<bool> canEditSettings(String groupId) =>
      _hasPermission(groupId, 'GROUP_SETTINGS');

  @override
  Future<GroupPermissions> permissionsFor(
    String groupId, {
    List<GroupPermission> of = GroupPermission.live,
  }) async {
    final results = await Future.wait([
      for (final p in of) _hasPermission(groupId, p.db),
    ]);
    return GroupPermissions({
      for (var i = 0; i < of.length; i++)
        if (results[i]) of[i],
    });
  }

  @override
  Future<void> setMemberRole({
    required String groupId,
    required String userId,
    required GroupRole role,
  }) => _guard(GroupErrorContext.changeRole, () async {
    await _client
        .from('group_members')
        .update({'role': role.db})
        .eq('group_id', groupId)
        .eq('user_id', userId);
  });

  /// `fn_has_permission(p_group, p_user, p_perm)` — live-verified signature.
  Future<bool> _hasPermission(String groupId, String permission) async {
    final uid = _uid;
    if (uid == null) return false;
    try {
      final response = await _client.rpc(
        'fn_has_permission',
        params: {'p_group': groupId, 'p_user': uid, 'p_perm': permission},
      );
      return response == true;
    } catch (e) {
      // A permission probe must never break the screen; the server still
      // refuses the mutation itself.
      AppLogger.warning('fn_has_permission unavailable: $e');
      return false;
    }
  }

  @override
  Future<void> updateBasics({
    required String groupId,
    required String name,
    required String description,
    String? privacy,
  }) => _guard(GroupErrorContext.update, () async {
    await _client
        .from('groups')
        .update({
          'name': name.trim(),
          'description': description.trim(),
          'privacy': ?privacy,
        })
        .eq('id', groupId);
  });

  @override
  Future<void> clearLogo(String groupId) => _guard(
    GroupErrorContext.update,
    () async {
      await _client.from('groups').update({'logo_url': null}).eq('id', groupId);
    },
  );

  @override
  Future<String> inviteCode(String groupId) =>
      _guard(GroupErrorContext.inviteCode, () async {
        final row = await _client
            .from('groups')
            .select('invite_code')
            .eq('id', groupId)
            .maybeSingle();
        final code = row?['invite_code'];
        if (code is! String || code.isEmpty) {
          throw const DataError(message: 'Invite code is not available.');
        }
        return code; // never logged
      });

  @override
  Future<String> rotateInviteCode(String groupId) =>
      _guard(GroupErrorContext.inviteCode, () async {
        final response = await _client.rpc(
          'fn_reset_group_invite',
          params: {'p_group': groupId},
        );
        // Deliberately no rpcShape() here: the response IS the secret.
        final code = response is Map
            ? (response['fn_reset_group_invite'] ?? response['invite_code'])
            : response;
        if (code is! String || code.isEmpty) {
          throw const DataError(message: 'The invite code was not rotated.');
        }
        return code;
      });

  static const _joinRequestColumns =
      'id, group_id, user_id, status, created_at';

  @override
  Future<GroupJoinRequest?> myJoinRequest(String groupId) => _guard(
    GroupErrorContext.join,
    () async {
      final uid = _uid;
      if (uid == null) throw const AuthError(message: 'Please sign in again.');
      final row = await _client
          .from('group_join_requests')
          .select(_joinRequestColumns)
          .eq('group_id', groupId)
          .eq('user_id', uid)
          .maybeSingle(); // UNIQUE(group_id, user_id)
      return row == null ? null : GroupJoinRequest.fromJson(row);
    },
  );

  @override
  Future<List<GroupJoinRequest>> myPendingJoinRequests() => _guard(
    GroupErrorContext.join,
    () async {
      final uid = _uid;
      if (uid == null) throw const AuthError(message: 'Please sign in again.');
      final rows = await _client
          .from('group_join_requests')
          .select(_joinRequestColumns)
          .eq('user_id', uid)
          .eq('status', GroupJoinRequest.statusPending)
          .order('created_at', ascending: false);
      return [
        for (final r in rows as List)
          GroupJoinRequest.fromJson(r as Map<String, dynamic>),
      ];
    },
  );

  static const _invitationColumns =
      'id, group_id, inviter_id, invitee_id, status, created_at';

  @override
  Future<List<GroupInvitation>> myInvitations() => _guard(
    GroupErrorContext.invitation,
    () async {
      final uid = _uid;
      if (uid == null) throw const AuthError(message: 'Please sign in again.');
      final rows = await _client
          .from('group_invitations')
          .select(_invitationColumns)
          .eq('invitee_id', uid)
          .eq('status', GroupInvitation.statusPending)
          .order('created_at', ascending: false);
      return [
        for (final r in rows as List)
          GroupInvitation.fromJson(r as Map<String, dynamic>),
      ];
    },
  );

  @override
  Future<void> acceptInvitation(String invitationId) =>
      _guard(GroupErrorContext.invitation, () async {
        await _client.rpc(
          'fn_accept_group_invitation',
          params: {'p_invitation_id': invitationId},
        );
      });

  @override
  Future<void> declineInvitation(String invitationId) =>
      _guard(GroupErrorContext.invitation, () async {
        await _client.rpc(
          'fn_decline_group_invitation',
          params: {'p_invitation_id': invitationId},
        );
      });

  @override
  Future<List<GroupJoinRequest>> pendingJoinRequests(String groupId) =>
      _guard(GroupErrorContext.joinRequest, () async {
        final rows = await _client
            .from('group_join_requests')
            .select(_joinRequestColumns)
            .eq('group_id', groupId)
            .eq('status', GroupJoinRequest.statusPending)
            .order('created_at');
        return [
          for (final r in rows as List)
            GroupJoinRequest.fromJson(r as Map<String, dynamic>),
        ];
      });

  @override
  Future<void> decideJoinRequest(String requestId, {required bool approve}) =>
      _guard(GroupErrorContext.joinRequest, () async {
        await _client.rpc(
          'fn_approve_group_join_request',
          params: {'p_request_id': requestId, 'p_approve': approve},
        );
      });

  @override
  Future<List<GroupInvitation>> groupInvitations(String groupId) =>
      _guard(GroupErrorContext.invitation, () async {
        final rows = await _client
            .from('group_invitations')
            .select(_invitationColumns)
            .eq('group_id', groupId)
            .order('created_at', ascending: false);
        return [
          for (final r in rows as List)
            GroupInvitation.fromJson(r as Map<String, dynamic>),
        ];
      });

  @override
  Future<void> cancelInvitation(String invitationId) =>
      _guard(GroupErrorContext.invitation, () async {
        final deleted = await _client
            .from('group_invitations')
            .delete()
            .eq('id', invitationId)
            .select('id');
        if ((deleted as List).isEmpty) {
          throw const DataError(
            message:
                'This invitation could not be cancelled. It may already be '
                'gone, or you do not have permission for it.',
          );
        }
      });

  @override
  Future<void> reinvite(GroupInvitation declined) async {
    final uid = _uid;
    if (uid == null) throw const AuthError(message: 'Please sign in again.');
    if (declined.status != GroupInvitation.statusDeclined) {
      throw const ValidationError(
        message: 'Only a declined invitation can be sent again.',
      );
    }
    // Step 1 — remove the declined row (UNIQUE would block the new one).
    await cancelInvitation(declined.id);
    // Step 2 — new pending row; the caller is the inviter.
    try {
      await sendInvitation(
        groupId: declined.groupId,
        inviteeId: declined.inviteeId,
      );
    } on AppError catch (e) {
      throw DataError(
        message:
            '$reinviteIncompletePrefix (${e.message}). Nothing is pending for '
            'this person — use Re-invite again once the problem is resolved.',
      );
    }
  }

  @override
  Future<ProfileMatch?> findProfileByStudentCode(String code) =>
      _guard(GroupErrorContext.invitation, () async {
        final trimmed = code.trim();
        if (trimmed.isEmpty) return null;
        final response = await _client.rpc(
          'rpc_find_profile_by_student_code',
          params: {'p_code': trimmed},
        );
        // Identity of a third party: log the shape only, never the values.
        AppLogger.rpcShape('rpc_find_profile_by_student_code', response);
        final rows = response is List ? response : [?response];
        if (rows.isEmpty) return null;
        return ProfileMatch.fromJson(rows.first as Map<String, dynamic>);
      });

  @override
  Future<void> sendInvitation({
    required String groupId,
    required String inviteeId,
  }) => _guard(GroupErrorContext.invitation, () async {
    final uid = _uid;
    if (uid == null) throw const AuthError(message: 'Please sign in again.');
    await _client.from('group_invitations').insert({
      'group_id': groupId,
      'inviter_id': uid, // must equal auth.uid() or the policy rejects it
      'invitee_id': inviteeId,
    });
  });

  @override
  Future<void> withdrawJoinRequest(String requestId) =>
      _guard(GroupErrorContext.joinRequest, () async {
        await _client.rpc(
          'fn_withdraw_join_request',
          params: {'p_request_id': requestId},
        );
      });

  // ── Role permissions (G14) ──

  @override
  Future<GroupRolePermissions> rolePermissions(String groupId) =>
      _guard(GroupErrorContext.rolePermission, () async {
        final rows = await _client
            .from('role_permissions')
            .select('role, permission')
            .eq('group_id', groupId);
        return GroupRolePermissions.fromRows(
          (rows as List).cast<Map<String, dynamic>>(),
        );
      });

  @override
  Future<void> setRolePermission({
    required String groupId,
    required GroupRole role,
    required GroupPermission permission,
    required bool granted,
  }) => _guard(GroupErrorContext.rolePermission, () async {
    if (!RolePermissionRules.canEditRole(role) ||
        !RolePermissionRules.canEditPermission(permission)) {
      throw const ValidationError(
        message: 'That role or permission cannot be changed here.',
      );
    }
    if (granted) {
      // PK (group_id, role, permission): an existing row is left untouched.
      await _client
          .from('role_permissions')
          .upsert(
            {'group_id': groupId, 'role': role.db, 'permission': permission.db},
            onConflict: 'group_id,role,permission',
            ignoreDuplicates: true,
          );
      return;
    }
    final deleted = await _client
        .from('role_permissions')
        .delete()
        .eq('group_id', groupId)
        .eq('role', role.db)
        .eq('permission', permission.db)
        .select('permission');
    if ((deleted as List).isEmpty) {
      throw const DataError(
        message:
            'That permission could not be revoked. It may already be '
            'revoked, or you do not have permission to manage roles here.',
      );
    }
  });

  // ── Group Rules (G6) ──

  static const _ruleColumns =
      'id, group_id, rule_text, position, created_at, updated_at';

  @override
  Future<List<GroupRule>> groupRules(String groupId) =>
      _guard(GroupErrorContext.load, () async {
        final rows = await _client
            .from('group_rules')
            .select(_ruleColumns)
            .eq('group_id', groupId)
            .order('position')
            .order('created_at');
        return [
          for (final r in rows as List)
            GroupRule.fromJson(r as Map<String, dynamic>),
        ];
      });

  @override
  Future<void> createRule({
    required String groupId,
    required String ruleText,
  }) => _guard(GroupErrorContext.update, () async {
    // Position = max existing + 1 for this group.
    final existing = await _client
        .from('group_rules')
        .select('position')
        .eq('group_id', groupId)
        .order('position', ascending: false)
        .limit(1);
    final maxPos = existing.isEmpty
        ? 0
        : (existing.first['position'] as num).toInt() + 1;
    await _client.from('group_rules').insert({
      'group_id': groupId,
      'rule_text': ruleText.trim(),
      'position': maxPos,
    });
  });

  @override
  Future<void> updateRule({required String ruleId, required String ruleText}) =>
      _guard(GroupErrorContext.update, () async {
        final updated = await _client
            .from('group_rules')
            .update({'rule_text': ruleText.trim()})
            .eq('id', ruleId)
            .select('id');
        if ((updated as List).isEmpty) {
          throw const DataError(
            message:
                'This rule could not be updated. It may have been removed.',
          );
        }
      });

  @override
  Future<void> deleteRule(String ruleId) => _guard(
    GroupErrorContext.update,
    () async {
      final deleted = await _client
          .from('group_rules')
          .delete()
          .eq('id', ruleId)
          .select('id');
      if ((deleted as List).isEmpty) {
        throw const DataError(
          message: 'This rule could not be deleted. It may have been removed.',
        );
      }
    },
  );

  // ── Group Announcements (G7) ──

  /// Base columns only (present since migration 0020; 0040's optional
  /// columns are never requested so a partially-migrated live table still
  /// reads).
  static const _announcementColumns =
      'id, group_id, author_id, title, body, created_at, updated_at';

  @override
  Future<List<GroupAnnouncement>> announcements(String groupId) =>
      _guard(GroupErrorContext.load, () async {
        final rows = await _client
            .from('group_announcements')
            .select(_announcementColumns)
            .eq('group_id', groupId)
            .order('created_at', ascending: false);
        AppLogger.rpcShape('group_announcements.select', rows);
        return [
          for (final r in rows as List)
            GroupAnnouncement.fromJson(r as Map<String, dynamic>),
        ];
      });

  @override
  Future<void> createAnnouncement({
    required String groupId,
    required String title,
    required String body,
  }) => _guard(GroupErrorContext.announcement, () async {
    final uid = _uid;
    if (uid == null) throw const AuthError(message: 'Please sign in again.');
    await _client.from('group_announcements').insert({
      'group_id': groupId,
      'author_id': uid, // NOT NULL, no default; FK → profiles(id)
      'title': title.trim(),
      'body': body.trim(),
    });
  });

  @override
  Future<void> updateAnnouncement({
    required String announcementId,
    required String title,
    required String body,
  }) => _guard(GroupErrorContext.announcement, () async {
    final updated = await _client
        .from('group_announcements')
        .update({'title': title.trim(), 'body': body.trim()})
        .eq('id', announcementId)
        .select('id');
    if ((updated as List).isEmpty) {
      throw const DataError(
        message:
            'This announcement could not be updated. It may have been removed.',
      );
    }
  });

  @override
  Future<void> deleteAnnouncement(
    String announcementId,
  ) => _guard(GroupErrorContext.announcement, () async {
    final deleted = await _client
        .from('group_announcements')
        .delete()
        .eq('id', announcementId)
        .select('id');
    if ((deleted as List).isEmpty) {
      throw const DataError(
        message:
            'This announcement could not be deleted. It may have been removed.',
      );
    }
  });

  // ── Group Chat (G8) ──

  /// Base columns including `deleted_at` (present since the initial migration;
  /// selected so the client can show a truthful "Message deleted" placeholder
  /// for soft-deleted rows). `message_type` / `metadata` / `deleted_by` are
  /// never requested so a partially-migrated live table still reads.
  static const _messageColumns =
      'id, group_id, sender_id, body, created_at, deleted_at';

  @override
  Future<List<GroupMessage>> messages(
    String groupId, {
    int limit = messagePageSize,
    DateTime? before,
  }) => _guard(GroupErrorContext.load, () async {
    var query = _client
        .from('group_messages')
        .select(_messageColumns)
        .eq('group_id', groupId);
    if (before != null) {
      query = query.lt('created_at', before.toUtc().toIso8601String());
    }
    final rows = await query
        .order('created_at', ascending: false)
        .order('id', ascending: false)
        .limit(limit);
    AppLogger.rpcShape('group_messages.select', rows);
    return [
      for (final r in rows as List)
        GroupMessage.fromJson(r as Map<String, dynamic>),
    ];
  });

  @override
  Future<void> sendMessage({required String groupId, required String body}) =>
      _guard(GroupErrorContext.chat, () async {
        final uid = _uid;
        if (uid == null) {
          throw const AuthError(message: 'Please sign in again.');
        }
        await _client.from('group_messages').insert({
          'group_id': groupId,
          'sender_id': uid, // must equal auth.uid() or the policy rejects it
          'body': body.trim(),
        });
      });

  @override
  GroupMessageSubscription subscribeToMessages({
    required String groupId,
    required void Function(GroupMessage message) onInsert,
    required void Function(GroupMessage message) onUpdate,
    void Function(bool connected)? onConnectionChange,
  }) {
    // Channel name only needs to be unique per subscription on this client;
    // it carries no server meaning.
    final channel = _client.channel('group_messages:$groupId');
    channel
      ..onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'group_messages',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'group_id',
          value: groupId,
        ),
        callback: (payload) {
          try {
            onInsert(GroupMessage.fromJson(payload.newRecord));
          } catch (e, st) {
            AppLogger.error('Realtime group_messages INSERT decode failed: $e', stackTrace: st);
          }
        },
      )
      ..onPostgresChanges(
        event: PostgresChangeEvent.update,
        schema: 'public',
        table: 'group_messages',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'group_id',
          value: groupId,
        ),
        callback: (payload) {
          try {
            onUpdate(GroupMessage.fromJson(payload.newRecord));
          } catch (e, st) {
            AppLogger.error('Realtime group_messages UPDATE decode failed: $e', stackTrace: st);
          }
        },
      )
      ..subscribe((status, error) {
        if (error != null) {
          AppLogger.warning('group_messages realtime channel error: $error');
        }
        onConnectionChange?.call(status == RealtimeSubscribeStatus.subscribed);
      });

    return _SupabaseGroupMessageSubscription(_client, channel);
  }

  @override
  Future<void> deleteGroup(String groupId) => _guard(GroupErrorContext.update, () async {
        await _client.rpc('rpc_delete_group', params: {'p_group': groupId});
      });

  @override
  Future<Map<String, int>> unreadCounts(List<String> groupIds) =>
      _guard(GroupErrorContext.load, () async {
        if (groupIds.isEmpty) return const {};
        final rows = await _client.rpc(
          'fn_get_group_unread_counts',
          params: {'p_group_ids': groupIds},
        ) as List<dynamic>;
        return {
          for (final r in rows.cast<Map<String, dynamic>>())
            r['group_id'] as String: (r['unread_count'] as num).toInt(),
        };
      });

  @override
  Future<void> markGroupRead(String groupId) =>
      _guard(GroupErrorContext.load, () async {
        await _client.rpc('fn_mark_group_read', params: {'p_group': groupId});
      });

  @override
  Future<Map<String, GroupLatestMessage>> latestMessages(
    List<String> groupIds,
  ) => _guard(GroupErrorContext.load, () async {
        if (groupIds.isEmpty) return const {};
        final rows = await _client.rpc(
          'fn_latest_group_messages',
          params: {'p_group_ids': groupIds},
        ) as List<dynamic>;
        return {
          for (final r in rows.cast<Map<String, dynamic>>())
            r['group_id'] as String: GroupLatestMessage.fromJson(r),
        };
      });

  static Future<T> _guard<T>(
    GroupErrorContext context,
    Future<T> Function() body,
  ) async {
    try {
      return await body();
    } on PostgrestException catch (e) {
      AppLogger.error(
        'GroupRepository PostgrestException: ${e.code} ${e.message}',
      );
      throw DataError(message: GroupErrors.map(e.message, context: context));
    } on AppError {
      rethrow;
    } catch (e, st) {
      AppLogger.error('GroupRepository unexpected: $e', stackTrace: st);
      throw DataError(message: GroupErrors.map(e.toString(), context: context));
    }
  }
}

class _SupabaseGroupMessageSubscription implements GroupMessageSubscription {
  _SupabaseGroupMessageSubscription(this._client, this._channel);

  final SupabaseClient _client;
  final RealtimeChannel _channel;

  @override
  Future<void> cancel() async {
    await _client.removeChannel(_channel);
  }
}
