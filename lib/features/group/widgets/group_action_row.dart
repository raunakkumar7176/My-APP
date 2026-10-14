import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/constants/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../state/group_hub_controller.dart';

/// The Info screen's quick-action row: Mute/Unmute (real, backed by
/// `group_mutes`), Share invite and Settings (both owner/admin only, same
/// gate as the existing Settings icon) — nothing here invents a feature
/// that isn't already live.
class GroupActionRow extends StatefulWidget {
  const GroupActionRow({
    required this.controller,
    required this.onShareInvite,
    required this.onOpenSettings,
    super.key,
  });

  final GroupHubController controller;
  final VoidCallback onShareInvite;
  final VoidCallback onOpenSettings;

  @override
  State<GroupActionRow> createState() => _GroupActionRowState();
}

class _GroupActionRowState extends State<GroupActionRow> {
  bool _muted = false;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _loadMuted();
  }

  Future<void> _loadMuted() async {
    final repo = widget.controller.notifications;
    if (repo == null) return;
    try {
      final muted = await repo.isMuted(widget.controller.groupId);
      if (mounted) {
        setState(() {
          _muted = muted;
          _loaded = true;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loaded = true);
    }
  }

  Future<void> _toggleMuted() async {
    final repo = widget.controller.notifications;
    if (repo == null) return;
    final next = !_muted;
    HapticFeedback.selectionClick();
    try {
      await repo.setMuted(widget.controller.groupId, muted: next);
      if (mounted) setState(() => _muted = next);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(next ? 'Notifications muted' : 'Notifications unmuted'),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not update notification settings.'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final canManage = widget.controller.canEditBasics;
    final hasMute = widget.controller.notifications != null;

    final actions = <_ActionRowItem>[
      if (hasMute)
        _ActionRowItem(
          key: const Key('group_info_mute_action'),
          icon: _muted ? Icons.notifications_active_outlined : Icons.notifications_off_outlined,
          label: _muted ? 'Unmute' : 'Mute',
          onTap: _loaded ? _toggleMuted : null,
        ),
      if (canManage)
        _ActionRowItem(
          key: const Key('group_info_share_invite_action'),
          icon: Icons.ios_share_rounded,
          label: 'Share invite',
          onTap: widget.onShareInvite,
        ),
      if (canManage)
        _ActionRowItem(
          key: const Key('group_info_settings_action_row'),
          icon: Icons.settings_outlined,
          label: 'Settings',
          onTap: widget.onOpenSettings,
          badgeCount: widget.controller.canModerateReports
              ? widget.controller.pendingReportCount
              : 0,
        ),
    ];

    if (actions.isEmpty) return const SizedBox.shrink();

    return Row(
      key: const Key('group_action_row'),
      children: [
        for (var i = 0; i < actions.length; i++) ...[
          if (i > 0) const SizedBox(width: 10),
          Expanded(child: actions[i]._build(isDark)),
        ],
      ],
    );
  }
}

class _ActionRowItem {
  const _ActionRowItem({
    required this.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.badgeCount = 0,
  });

  final Key key;
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  /// Pending-reports count shown as a small badge on the icon (0 hides it).
  final int badgeCount;

  Widget _build(bool isDark) {
    return Container(
      key: key,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: AppRadius.xlBorder,
        border: Border.all(
          color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Badge(
                  isLabelVisible: badgeCount > 0,
                  label: Text('$badgeCount'),
                  backgroundColor: AppColors.error,
                  child: Icon(
                    icon,
                    size: 20,
                    color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF475569),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF334155),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
