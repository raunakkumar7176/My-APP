import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../state/group_hub_controller.dart';

/// Settings' Danger Zone: Transfer ownership and Delete group for the
/// owner (both backed by real server functions —
/// `fn_transfer_group_ownership`/`rpc_delete_group_by_owner` — and
/// audit-logged server-side via migration 0111's trigger-fed
/// group_audit_log; nothing here is a "not available yet" placeholder),
/// or Leave group for anyone else (moved here from the Info screen, which
/// no longer carries its own Danger Zone).
class SettingsDangerZone extends StatefulWidget {
  const SettingsDangerZone({required this.controller, super.key});

  final GroupHubController controller;

  @override
  State<SettingsDangerZone> createState() => _SettingsDangerZoneState();
}

class _SettingsDangerZoneState extends State<SettingsDangerZone> {
  GroupHubController get _c => widget.controller;

  Future<void> _transfer(BuildContext context) async {
    final members = [
      for (final m in _c.members)
        if (m.userId != _c.currentUserId) m,
    ];
    if (members.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No other member to transfer ownership to.')),
      );
      return;
    }
    final target = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Transfer ownership to…'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: members.length,
            itemBuilder: (ctx, i) {
              final m = members[i];
              return ListTile(
                key: Key('transfer_pick_${m.userId}'),
                title: Text(m.displayName),
                subtitle: Text(m.role),
                onTap: () => Navigator.of(ctx).pop(m.userId),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
    if (target == null || !context.mounted) return;

    final targetMember = members.firstWhere((m) => m.userId == target);
    final nameCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('Confirm ownership transfer'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${targetMember.displayName} will become the owner. You will '
                'become an admin. This cannot be undone by anyone but the new '
                'owner.',
              ),
              const SizedBox(height: 12),
              Text('Type "${_c.group?.name ?? ''}" to confirm.'),
              const SizedBox(height: 8),
              TextField(
                key: const Key('transfer_confirm_name_field'),
                controller: nameCtrl,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(border: OutlineInputBorder()),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              key: const Key('confirm_transfer_ownership'),
              style: FilledButton.styleFrom(backgroundColor: AppColors.error),
              onPressed: nameCtrl.text.trim() == (_c.group?.name ?? '').trim()
                  ? () => Navigator.of(ctx).pop(true)
                  : null,
              child: const Text('Transfer Ownership'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final ok = await _c.transferOwnership(target);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? 'Ownership transferred to ${targetMember.displayName}.'
              : (_c.error ?? 'Could not transfer ownership.'),
        ),
        backgroundColor: ok ? null : AppColors.error,
      ),
    );
  }

  Future<void> _delete(BuildContext context) async {
    final nameCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('Delete this group?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'This permanently deletes all messages, tests, members and '
                'settings. This cannot be undone.',
              ),
              const SizedBox(height: 12),
              Text('Type "${_c.group?.name ?? ''}" to confirm.'),
              const SizedBox(height: 8),
              TextField(
                key: const Key('delete_confirm_name_field'),
                controller: nameCtrl,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(border: OutlineInputBorder()),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              key: const Key('confirm_delete_group'),
              style: FilledButton.styleFrom(backgroundColor: AppColors.error),
              onPressed: nameCtrl.text.trim() == (_c.group?.name ?? '').trim()
                  ? () => Navigator.of(ctx).pop(true)
                  : null,
              child: const Text('Delete Group'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final ok = await _c.deleteGroup();
    if (!context.mounted) return;
    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Group deleted.')),
      );
      context.go('/groups');
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_c.error ?? 'Could not delete the group.'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Future<void> _leave(BuildContext context) async {
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
    if (confirmed != true || !context.mounted) return;
    final ok = await _c.leave();
    if (!context.mounted) return;
    if (ok) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('You left the group.')));
      context.go('/groups');
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_c.error ?? 'Could not leave the group.'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isOwner = _c.isOwner;

    return Container(
      key: const Key('settings_danger_zone'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF2A1215) : const Color(0xFFFEF2F2),
        borderRadius: AppRadius.xlBorder,
        border: Border.all(
          color: isDark ? const Color(0xFF5C1D24) : const Color(0xFFFECACA),
        ),
      ),
      child: Column(
        key: const Key('settings_leave_section'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: AppColors.error, size: 20),
              SizedBox(width: 8),
              Text(
                'Danger zone',
                style: TextStyle(
                  color: AppColors.error,
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (isOwner) ...[
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                key: const Key('settings_transfer_ownership_button'),
                onPressed: _c.isBusy ? null : () => _transfer(context),
                icon: const Icon(Icons.swap_horiz, color: AppColors.error),
                label: const Text(
                  'Transfer ownership',
                  style: TextStyle(color: AppColors.error),
                ),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AppColors.error),
                ),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                key: const Key('delete_group_button'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.error,
                  foregroundColor: Colors.white,
                ),
                onPressed: _c.isBusy ? null : () => _delete(context),
                icon: const Icon(Icons.delete_forever),
                label: const Text('Delete group'),
              ),
            ),
          ] else if (_c.canLeave)
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                key: const Key('settings_leave_button'),
                onPressed: _c.isBusy ? null : () => _leave(context),
                icon: const Icon(Icons.exit_to_app, color: AppColors.error),
                label: const Text(
                  'Leave group',
                  style: TextStyle(color: AppColors.error),
                ),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AppColors.error),
                ),
              ),
            )
          else
            Text(
              _c.leaveBlockedReason,
              key: const Key('settings_leave_blocked'),
              style: TextStyle(
                fontSize: 12.5,
                color: isDark ? const Color(0xFFFCA5A5) : const Color(0xFF991B1B),
              ),
            ),
        ],
      ),
    );
  }
}
