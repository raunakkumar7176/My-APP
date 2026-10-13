import 'package:flutter/material.dart';

import '../../../core/constants/theme/app_colors.dart';
import '../domain/group_permission.dart';
import '../domain/group_role.dart';
import '../state/group_hub_controller.dart';

/// Settings > Permissions: who can chat (reuses `admin_only_chat`,
/// migration 0110) and who can create tests (grants/revokes CREATE_TEST
/// for the `member` role, migration-free — the live `tests` INSERT policy
/// already checks `fn_has_permission(..., 'CREATE_TEST')`, which already
/// honours a `role_permissions` row for `member`; only the client-side
/// "member is never editable" guard needed a narrow carve-out).
///
/// Deliberately NOT here: a "share files/links" toggle. No file-sharing
/// feature exists anywhere in this app yet (the Info screen's Media &
/// Files section is an honest "coming soon" stub) — a toggle would govern
/// nothing real.
class SettingsPermissionsCard extends StatefulWidget {
  const SettingsPermissionsCard({required this.controller, super.key});

  final GroupHubController controller;

  @override
  State<SettingsPermissionsCard> createState() => _SettingsPermissionsCardState();
}

class _SettingsPermissionsCardState extends State<SettingsPermissionsCard> {
  GroupHubController get _c => widget.controller;
  bool _busyChat = false;
  bool _busyTests = false;

  @override
  void initState() {
    super.initState();
    // Deferred to after the first frame: loadRolePermissions() notifies
    // synchronously before its first await, which would otherwise call
    // setState on an ancestor still in the middle of its own first build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _c.loadRolePermissions(); // no-op unless canManageRolePermissions
    });
  }

  Future<void> _setChatEveryone(bool everyone) async {
    setState(() => _busyChat = true);
    final ok = await _c.updateAdminOnlyChat(!everyone);
    if (mounted) setState(() => _busyChat = false);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_c.error ?? 'Could not update chat permissions.'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Future<void> _setCreateTestsEveryone(bool everyone) async {
    setState(() => _busyTests = true);
    final ok = await _c.setRolePermission(
      GroupRole.member,
      GroupPermission.createTest,
      granted: everyone,
    );
    if (mounted) setState(() => _busyTests = false);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_c.error ?? 'Could not update test-creation permissions.'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final chatEveryone = !(_c.group?.adminOnlyChat ?? false);
    final testsEveryone = _c.rolePermissions.has(
      GroupRole.member,
      GroupPermission.createTest,
    );
    return Column(
      key: const Key('settings_permissions_card'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Permissions', style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        _toggleRow(
          key: 'settings_chat_permission',
          label: 'Who can chat',
          everyone: chatEveryone,
          busy: _busyChat,
          onChanged: _setChatEveryone,
        ),
        const Divider(height: 24),
        _toggleRow(
          key: 'settings_create_test_permission',
          label: 'Who can create tests',
          everyone: testsEveryone,
          busy: _busyTests || _c.rolePermissionsLoading,
          onChanged: _setCreateTestsEveryone,
        ),
      ],
    );
  }

  Widget _toggleRow({
    required String key,
    required String label,
    required bool everyone,
    required bool busy,
    required ValueChanged<bool> onChanged,
  }) {
    return Row(
      key: Key(key),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: Text(label)),
        if (busy)
          const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        else
          _EveryoneAdminsToggle(everyone: everyone, onChanged: onChanged),
      ],
    );
  }
}

class _EveryoneAdminsToggle extends StatelessWidget {
  const _EveryoneAdminsToggle({required this.everyone, required this.onChanged});

  final bool everyone;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<bool>(
      segments: const [
        ButtonSegment(value: true, label: Text('Everyone')),
        ButtonSegment(value: false, label: Text('Admins only')),
      ],
      selected: {everyone},
      onSelectionChanged: (s) => onChanged(s.first),
      showSelectedIcon: false,
    );
  }
}
