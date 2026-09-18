import 'package:flutter/material.dart';

import '../../../core/constants/theme/app_colors.dart';
import '../domain/group_role.dart';

/// Compact role label. Colours only signal rank; nothing here grants anything.
class RoleBadge extends StatelessWidget {
  const RoleBadge(this.role, {super.key});

  final GroupRole role;

  Color _color(BuildContext context) {
    switch (role) {
      case GroupRole.owner:
        return AppColors.primaryLight;
      case GroupRole.leader:
        return AppColors.success;
      case GroupRole.moderator:
        return AppColors.warning;
      case GroupRole.member:
        return Theme.of(context).colorScheme.outline;
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = _color(context);
    return Container(
      key: Key('role_badge_${role.name}'),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        role.label,
        style: TextStyle(color: c, fontSize: 12, fontWeight: FontWeight.w600),
      ),
    );
  }
}
