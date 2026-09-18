import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/theme/app_colors.dart';
import '../../../core/models/group_member.dart';
import '../domain/group_role.dart';
import '../state/group_hub_controller.dart';

/// One group's hub: profile header, roster, and the G1 membership actions.
/// Later phases (announcements, chat, group tests, leaderboard) attach here;
/// nothing is stubbed for them yet.
class GroupHubScreen extends StatefulWidget {
  const GroupHubScreen({required this.groupId, this.controller, super.key});

  final String groupId;
  final GroupHubController? controller;

  @override
  State<GroupHubScreen> createState() => _GroupHubScreenState();
}

class _GroupHubScreenState extends State<GroupHubScreen> {
  late final GroupHubController _c;
  late final bool _owns;

  @override
  void initState() {
    super.initState();
    _owns = widget.controller == null;
    _c = widget.controller ?? GroupHubController(groupId: widget.groupId);
    _c.addListener(_onChanged);
    _c.load();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _c.removeListener(_onChanged);
    if (_owns) _c.dispose();
    super.dispose();
  }

  void _snack(String message, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? AppColors.error : null,
      ),
    );
  }

  Future<void> _leave() async {
    if (!_c.canLeave) {
      _snack(_c.leaveBlockedReason, error: true);
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Leave group?'),
        content: Text(
          'You will lose access to ${_c.group?.name ?? 'this group'}, its '
          'tests and its members. You can rejoin later with the invite code '
          'if the group allows it.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('confirm_leave'),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Leave'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final ok = await _c.leave();
    if (!mounted) return;
    if (ok) {
      _snack('You left the group.');
      context.go('/groups');
    } else {
      _snack(_c.error ?? 'Could not leave the group.', error: true);
    }
  }

  Future<void> _removeMember(GroupMember member) async {
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
    if (confirmed != true) return;
    final ok = await _c.removeMember(member.userId);
    if (!mounted) return;
    _snack(
      ok
          ? '${member.displayName} was removed.'
          : (_c.error ?? 'Could not remove.'),
      error: !ok,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_c.hasLoaded && _c.isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Loading…')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (_c.accessDenied) {
      return _message(
        icon: Icons.lock_outline,
        title: _c.hasLeft ? 'You left this group' : 'Group not available',
        // One honest message: the server does not distinguish "deleted" from
        // "you are not a member", and guessing would leak that a group exists.
        body: _c.hasLeft
            ? 'You no longer have access to this group.'
            : 'This group does not exist, or you are not a member of it.',
      );
    }
    if (_c.group == null) {
      return _message(
        icon: Icons.error_outline,
        title: 'Could not open this group',
        body: _c.error ?? 'Please try again.',
        action: FilledButton(onPressed: _c.load, child: const Text('Retry')),
      );
    }

    final group = _c.group!;
    return Scaffold(
      appBar: AppBar(
        title: Text(group.name),
        actions: [
          PopupMenuButton<String>(
            key: const Key('group_menu'),
            onSelected: (value) {
              if (value == 'leave') _leave();
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'leave',
                enabled: _c.canLeave,
                child: const Text('Leave group'),
              ),
            ],
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _c.refresh,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 28,
                  child: Text(
                    group.name.trim().isEmpty
                        ? '?'
                        : group.name.trim()[0].toUpperCase(),
                    style: const TextStyle(fontSize: 22),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        group.name,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${_c.memberCount} ${_c.memberCount == 1 ? 'member' : 'members'} · '
                        '${_c.myRole.label} · ${_c.privacy.label}',
                        key: const Key('group_header_meta'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if ((group.description ?? '').trim().isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(group.description!.trim()),
            ],
            const SizedBox(height: 24),
            Text('Members', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            for (final m in _c.members) _memberTile(m),
            const SizedBox(height: 24),
            if (_c.canLeave)
              OutlinedButton.icon(
                key: const Key('leave_group_button'),
                onPressed: _c.isBusy ? null : _leave,
                icon: const Icon(Icons.logout),
                label: const Text('Leave group'),
              )
            else
              Text(
                _c.leaveBlockedReason,
                key: const Key('leave_blocked_note'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
          ],
        ),
      ),
    );
  }

  Widget _memberTile(GroupMember m) {
    final role = GroupRole.fromDb(m.role);
    final isMe = m.userId == _c.currentUserId;
    // Offered only when the server confirmed MANAGE_MEMBERS, never for the
    // owner and never for yourself — the server refuses those too.
    final canRemove = _c.canManageMembers && !isMe && !role.isOwner;
    return ListTile(
      key: Key('member_${m.userId}'),
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(child: Text(m.displayName[0].toUpperCase())),
      title: Text(isMe ? '${m.displayName} (you)' : m.displayName),
      subtitle: Text(role.label),
      trailing: canRemove
          ? IconButton(
              key: Key('remove_${m.userId}'),
              tooltip: 'Remove member',
              icon: const Icon(Icons.person_remove_outlined),
              onPressed: _c.isBusy ? null : () => _removeMember(m),
            )
          : null,
    );
  }

  Widget _message({
    required IconData icon,
    required String title,
    required String body,
    Widget? action,
  }) {
    return Scaffold(
      appBar: AppBar(title: const Text('Group')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 48,
                color: Theme.of(context).colorScheme.outline,
              ),
              const SizedBox(height: 12),
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(body, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              action ??
                  FilledButton(
                    onPressed: () => context.go('/groups'),
                    child: const Text('Back to Groups'),
                  ),
            ],
          ),
        ),
      ),
    );
  }
}
