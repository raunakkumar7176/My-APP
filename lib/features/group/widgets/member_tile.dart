import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/theme/app_colors.dart';
import '../../../core/models/group_member.dart';
import '../domain/group_role.dart';
import '../state/group_hub_controller.dart';
import 'group_avatar.dart';
import 'role_badge.dart';

/// One roster row with the permission-aware action menu. Used by the Group
/// Hub roster and the Members Hub. Actions are offered only from the
/// server-reported permissions on [controller]; the live RLS remains the
/// boundary (a hidden button is never the security mechanism).
class MemberTile extends StatelessWidget {
  const MemberTile({
    required this.member,
    required this.controller,
    this.onTap,
    super.key,
  });

  final GroupMember member;
  final GroupHubController controller;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final role = GroupRole.fromDb(member.role);
    final isMe = member.userId == c.currentUserId;
    // Never yourself, never the owner — invariants, not permissions.
    final canRemove = c.canManageMembers && !isMe && !role.isOwner;
    final canChangeRole = c.canManageRoles && !isMe && !role.isOwner;
    final code = member.studentCode?.trim();

    return ListTile(
      key: Key('member_${member.userId}'),
      contentPadding: EdgeInsets.zero,
      onTap: onTap,
      leading: GroupAvatar(name: member.displayName, logoUrl: member.avatarUrl),
      title: Text(
        isMe ? '${member.displayName} (you)' : member.displayName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Row(
        children: [
          RoleBadge(role),
          if (code != null && code.isNotEmpty) ...[
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                code,
                key: Key('member_code_${member.userId}'),
                style: Theme.of(context).textTheme.bodySmall,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (canChangeRole)
            PopupMenuButton<GroupRole>(
              key: Key('role_menu_${member.userId}'),
              tooltip: 'Change role',
              enabled: !c.isBusy,
              icon: const Icon(Icons.manage_accounts_outlined),
              onSelected: (r) => _changeRole(context, r),
              itemBuilder: (_) => [
                for (final r in GroupHubController.assignableRoles)
                  PopupMenuItem(
                    key: Key('role_option_${member.userId}_${r.name}'),
                    value: r,
                    enabled: r != role,
                    child: Text(r == role ? '${r.label} (current)' : r.label),
                  ),
              ],
            ),
          if (canRemove)
            IconButton(
              key: Key('remove_${member.userId}'),
              tooltip: 'Remove member',
              icon: const Icon(Icons.person_remove_outlined),
              onPressed: c.isBusy ? null : () => _remove(context),
            ),
        ],
      ),
    );
  }

  static void _snack(
    BuildContext context,
    String message, {
    bool error = false,
  }) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? AppColors.error : null,
      ),
    );
  }

  Future<void> _changeRole(BuildContext context, GroupRole role) async {
    final from = GroupRole.fromDb(member.role);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Change role?'),
        content: Text(
          '${member.displayName}: ${from.label} → ${role.label}',
          key: const Key('role_change_summary'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('confirm_role_change'),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Change'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final ok = await controller.changeRole(member.userId, role);
    if (!context.mounted) return;
    _snack(
      context,
      ok
          ? '${member.displayName} is now ${role.label}.'
          : (controller.error ?? 'Could not change the role.'),
      error: !ok,
    );
  }

  Future<void> _remove(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove member?'),
        content: Text('${member.displayName} will lose access to this group.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('confirm_remove'),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final ok = await controller.removeMember(member.userId);
    if (!context.mounted) return;
    _snack(
      context,
      ok
          ? '${member.displayName} was removed.'
          : (controller.error ?? 'Could not remove.'),
      error: !ok,
    );
  }
}

/// Read-only member detail: only fields the roster embed already carries.
class MemberDetailSheet extends StatelessWidget {
  const MemberDetailSheet({
    required this.member,
    required this.groupName,
    required this.isMe,
    super.key,
  });

  final GroupMember member;
  final String groupName;
  final bool isMe;

  static Future<void> show(
    BuildContext context, {
    required GroupMember member,
    required String groupName,
    required bool isMe,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      builder: (_) =>
          MemberDetailSheet(member: member, groupName: groupName, isMe: isMe),
    );
  }

  @override
  Widget build(BuildContext context) {
    final role = GroupRole.fromDb(member.role);
    final code = member.studentCode?.trim();
    final bio = member.bio?.trim();
    final joined = member.joinedAt;
    String two(int n) => n.toString().padLeft(2, '0');
    return Padding(
      key: const Key('member_detail'),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              GroupAvatar(
                name: member.displayName,
                logoUrl: member.avatarUrl,
                radius: 28,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isMe ? '${member.displayName} (you)' : member.displayName,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 4),
                    RoleBadge(role),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (code != null && code.isNotEmpty)
            _row(context, 'Student code', code, key: const Key('detail_code')),
          if (bio != null && bio.isNotEmpty)
            _row(context, 'About', bio, key: const Key('detail_bio')),
          _row(context, 'Group', groupName),
          _row(
            context,
            'Member since',
            '${joined.year}-${two(joined.month)}-${two(joined.day)}',
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              key: const Key('member_view_profile'),
              onPressed: () {
                Navigator.of(context).pop();
                // Real user id in the path parameter — ProfileScreen
                // resolves it (or a student code) straight back to a row.
                context.push(isMe ? '/profile' : '/profile/${member.userId}');
              },
              icon: const Icon(Icons.account_circle_outlined, size: 18),
              label: const Text('View Profile'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(BuildContext context, String label, String value, {Key? key}) {
    return Padding(
      key: key,
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(label, style: Theme.of(context).textTheme.bodySmall),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}
