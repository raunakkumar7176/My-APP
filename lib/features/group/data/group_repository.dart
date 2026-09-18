import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/errors/app_error.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/models/group.dart';
import '../../../core/models/group_invitation.dart';
import '../../../core/models/group_join_request.dart';
import '../../../core/models/group_member.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/services/supabase_service.dart';
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

  /// `fn_accept_group_invitation(p_invite_id)` — the server checks the caller
  /// is the invitee and the row is pending, inserts the membership itself,
  /// and raises `INVITE_NOT_FOUND` otherwise. No client-side table write.
  Future<void> acceptInvitation(String invitationId);

  /// `fn_decline_group_invitation(p_invite_id)` — same guard; `INVITE_NOT_FOUND`.
  Future<void> declineInvitation(String invitationId);
}

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
          if (privacy != null) 'privacy': privacy,
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
          params: {'p_invite_id': invitationId},
        );
      });

  @override
  Future<void> declineInvitation(String invitationId) =>
      _guard(GroupErrorContext.invitation, () async {
        await _client.rpc(
          'fn_decline_group_invitation',
          params: {'p_invite_id': invitationId},
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
