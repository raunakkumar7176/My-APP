import 'package:flutter/material.dart';

import '../../../core/constants/theme/app_colors.dart';
import '../domain/group_controls.dart';
import '../domain/group_permission.dart';
import '../domain/group_role.dart';
import '../state/group_hub_controller.dart';

/// G14 — per-role permission matrix over the existing `role_permissions`
/// table. Opened only for a caller the server reports as MANAGE_ROLES (or
/// the owner); each switch sends exactly one insert / delete and the matrix
/// is re-read from the server afterwards. Owner is never a row (bypass) and
/// `member` is never offered ([RolePermissionRules]).
class RolePermissionsSheet extends StatefulWidget {
  const RolePermissionsSheet({required this.hub, super.key});

  final GroupHubController hub;

  static Future<void> show(BuildContext context, {required GroupHubController hub}) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => RolePermissionsSheet(hub: hub),
    );
  }

  @override
  State<RolePermissionsSheet> createState() => _RolePermissionsSheetState();
}

class _RolePermissionsSheetState extends State<RolePermissionsSheet> {
  GroupRole _role = RolePermissionRules.editableRoles.first;

  @override
  void initState() {
    super.initState();
    widget.hub.addListener(_onChanged);
    // The load notifies the hub synchronously; defer it past the sheet's
    // first build so the hub screen is not marked dirty mid-build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.hub.loadRolePermissions();
    });
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.hub.removeListener(_onChanged);
    super.dispose();
  }

  Future<void> _toggle(GroupPermission p, bool granted) async {
    final ok = await widget.hub.setRolePermission(_role, p, granted: granted);
    if (!mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(widget.hub.error ?? 'Could not update that permission.'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final hub = widget.hub;
    final matrix = hub.rolePermissions;
    final busy = hub.isBusy || hub.rolePermissionsLoading;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Role permissions',
              key: const Key('role_permissions_title'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 4),
            Text(
              'The owner always holds every permission. Members hold none; '
              'grant a role below and every member with that role gets it.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            SegmentedButton<GroupRole>(
              key: const Key('role_permissions_role'),
              segments: [
                for (final r in RolePermissionRules.editableRoles)
                  ButtonSegment(value: r, label: Text(r.label)),
              ],
              selected: {_role},
              onSelectionChanged: (s) => setState(() => _role = s.first),
            ),
            const SizedBox(height: 8),
            if (hub.rolePermissionsError != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        hub.rolePermissionsError!,
                        key: const Key('role_permissions_error'),
                        style: const TextStyle(color: AppColors.error),
                      ),
                    ),
                    TextButton(
                      key: const Key('role_permissions_retry'),
                      onPressed: busy ? null : hub.loadRolePermissions,
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            if (hub.rolePermissionsLoading && matrix.rowCount == 0)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final p in RolePermissionRules.editablePermissions)
                    SwitchListTile(
                      key: Key('perm_${_role.name}_${p.name}'),
                      dense: true,
                      title: Text(p.label),
                      subtitle: Text(p.db),
                      value: matrix.has(_role, p),
                      onChanged: busy ? null : (v) => _toggle(p, v),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
