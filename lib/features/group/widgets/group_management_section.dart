import 'package:flutter/material.dart';

import '../state/group_hub_controller.dart';

/// G14 — the hub's "Manage" surface. One compact card that routes to the
/// existing management screens / sheets; every row is shown only when the
/// server-reported permission (or the owner bypass) allows it. Nothing here
/// is a second control: settings, members, tests, results and announcements
/// keep their own screens, this only makes them reachable in one place.
/// Rendered as nothing at all for a plain member.
class GroupManagementSection extends StatelessWidget {
  const GroupManagementSection({
    required this.controller,
    required this.onOpenSettings,
    required this.onOpenMembers,
    required this.onOpenTests,
    required this.onOpenRolePermissions,
    super.key,
  });

  final GroupHubController controller;
  final VoidCallback onOpenSettings;
  final VoidCallback onOpenMembers;
  final VoidCallback onOpenTests;
  final VoidCallback onOpenRolePermissions;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final ctl = c.controls;
    if (!ctl.hasAnyManagement) return const SizedBox.shrink();

    final memberBits = [
      if (ctl.canManageMembers) 'invite & remove',
      if (ctl.canManageRoles) 'change roles',
    ];
    final testBits = ctl.testCapabilities;
    final busy = c.isBusy;

    return Card(
      key: const Key('group_management_section'),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Manage',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  Text(
                    c.myRole.label,
                    key: const Key('management_role_label'),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            if (ctl.canOpenSettings)
              ListTile(
                key: const Key('manage_settings'),
                dense: true,
                leading: const Icon(Icons.settings_outlined),
                title: const Text('Group settings'),
                subtitle: const Text('Name, privacy, invite code, rules'),
                trailing: const Icon(Icons.chevron_right),
                onTap: busy ? null : onOpenSettings,
              ),
            if (memberBits.isNotEmpty)
              ListTile(
                key: const Key('manage_members'),
                dense: true,
                leading: const Icon(Icons.group_outlined),
                title: const Text('Members'),
                subtitle: Text(memberBits.join(' · ')),
                trailing: const Icon(Icons.chevron_right),
                onTap: busy ? null : onOpenMembers,
              ),
            if (ctl.canManageRolePermissions)
              ListTile(
                key: const Key('manage_role_permissions'),
                dense: true,
                leading: const Icon(Icons.admin_panel_settings_outlined),
                title: const Text('Role permissions'),
                subtitle: const Text('What leaders and moderators may do'),
                trailing: const Icon(Icons.chevron_right),
                onTap: busy ? null : onOpenRolePermissions,
              ),
            if (testBits.isNotEmpty)
              ListTile(
                key: const Key('manage_tests'),
                dense: true,
                leading: const Icon(Icons.quiz_outlined),
                title: const Text('Tests'),
                subtitle: Text(testBits.join(' · ')),
                trailing: const Icon(Icons.chevron_right),
                onTap: busy ? null : onOpenTests,
              ),
            if (ctl.canViewAnalytics)
              ListTile(
                key: const Key('manage_analytics'),
                dense: true,
                leading: const Icon(Icons.leaderboard_outlined),
                title: const Text('Results & leaderboards'),
                subtitle: const Text("Every participant's result, per test"),
                trailing: const Icon(Icons.chevron_right),
                onTap: busy ? null : onOpenTests,
              ),
            if (ctl.canSendAnnouncement)
              const ListTile(
                key: Key('manage_announcements'),
                dense: true,
                leading: Icon(Icons.campaign_outlined),
                title: Text('Announcements'),
                subtitle: Text('Post from the Announcements section below'),
              ),
          ],
        ),
      ),
    );
  }
}
