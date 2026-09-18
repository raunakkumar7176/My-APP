import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/errors/app_error.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/models/group.dart';
import '../../../core/models/group_member.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/services/supabase_service.dart';
import '../domain/group_errors.dart';

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

  /// Updates `groups.name` / `groups.description`. The live UPDATE policy
  /// requires `GROUP_SETTINGS` or the owner role.
  Future<void> updateBasics({
    required String groupId,
    required String name,
    required String description,
  });
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
  Future<List<GroupMember>> members(
    String groupId,
  ) => _guard(GroupErrorContext.load, () async {
    final rows = await _client
        .from('group_members')
        .select(
          'group_id, user_id, role, joined_at, profiles(full_name, avatar_url)',
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
  Future<bool> canManageMembers(String groupId) async {
    final uid = _uid;
    if (uid == null) return false;
    try {
      final response = await _client.rpc(
        'fn_has_permission',
        params: {'p_group': groupId, 'p_user': uid, 'p_perm': 'MANAGE_MEMBERS'},
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
  }) => _guard(GroupErrorContext.update, () async {
    await _client
        .from('groups')
        .update({'name': name.trim(), 'description': description.trim()})
        .eq('id', groupId);
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
