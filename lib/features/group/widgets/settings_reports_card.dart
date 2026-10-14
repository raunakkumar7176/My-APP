import 'package:flutter/material.dart';

import '../../../core/constants/theme/app_colors.dart';
import '../../../core/models/message_report_group.dart';
import '../state/group_hub_controller.dart';

/// Settings > Reported messages (Phase 3A item 6/finish-up): admin/owner
/// only. Reports are already grouped per message server-side readback
/// (`GroupHubController.messageReports`, migration 0120's RLS restricts
/// the underlying table to admin/owner, so a plain member never even
/// loads this list). Each row offers Dismiss / Delete message / Remove
/// member, each confirmed, matching the existing confirm-dialog pattern
/// used throughout Settings and the Members screen.
class SettingsReportsCard extends StatefulWidget {
  const SettingsReportsCard({required this.controller, super.key});

  final GroupHubController controller;

  @override
  State<SettingsReportsCard> createState() => _SettingsReportsCardState();
}

class _SettingsReportsCardState extends State<SettingsReportsCard> {
  GroupHubController get _c => widget.controller;
  String? _actingId;

  static const _reasonLabels = {
    'spam': 'Spam',
    'abuse': 'Abuse',
    'off_topic': 'Off-topic',
    'other': 'Other',
  };

  String _reasonSummary(MessageReportGroup r) {
    final parts = [
      for (final entry in r.reasonCounts.entries)
        '${_reasonLabels[entry.key] ?? entry.key} ×${entry.value}',
    ];
    return parts.join(', ');
  }

  String? _senderName(MessageReportGroup r) {
    final id = r.messageSenderId;
    if (id == null) return null;
    return _c.members.where((m) => m.userId == id).firstOrNull?.displayName;
  }

  void _snack(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? AppColors.error : null,
      ),
    );
  }

  Future<void> _dismiss(MessageReportGroup r) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Dismiss reports?'),
        content: const Text(
          'All reports for this message will be cleared. The message stays.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: Key('confirm_dismiss_${r.messageId}'),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Dismiss'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _actingId = r.messageId);
    final ok = await _c.dismissReports(r);
    if (!mounted) return;
    setState(() => _actingId = null);
    _snack(
      ok ? 'Reports dismissed.' : (_c.error ?? 'Could not dismiss reports.'),
      error: !ok,
    );
  }

  Future<void> _deleteMessage(MessageReportGroup r) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete message?'),
        content: const Text(
          'This message will be deleted for everyone in this group.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: Key('confirm_delete_reported_${r.messageId}'),
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete for Everyone'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _actingId = r.messageId);
    final ok = await _c.deleteReportedMessage(r);
    if (!mounted) return;
    setState(() => _actingId = null);
    _snack(
      ok ? 'Message deleted.' : (_c.error ?? 'Could not delete the message.'),
      error: !ok,
    );
  }

  Future<void> _removeMember(MessageReportGroup r) async {
    final senderId = r.messageSenderId;
    if (senderId == null) return;
    final name = _senderName(r) ?? 'this member';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove member?'),
        content: Text('$name will lose access to this group.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: Key('confirm_remove_reported_${r.messageId}'),
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _actingId = r.messageId);
    final ok = await _c.removeMember(senderId);
    if (!mounted) return;
    setState(() => _actingId = null);
    _snack(
      ok ? '$name was removed.' : (_c.error ?? 'Could not remove member.'),
      error: !ok,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_c.canModerateReports) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final reports = _c.messageReports;

    return Column(
      key: const Key('settings_reports_card'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Reported messages', style: theme.textTheme.titleMedium),
            if (reports.isNotEmpty) ...[
              const SizedBox(width: 8),
              Container(
                key: const Key('reports_pending_badge'),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.error,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${reports.length}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 8),
        if (reports.isEmpty)
          Text(
            'No pending reports.',
            key: const Key('reports_empty'),
            style: theme.textTheme.bodySmall,
          )
        else
          for (final r in reports) _reportTile(context, r),
      ],
    );
  }

  Widget _reportTile(BuildContext context, MessageReportGroup r) {
    final theme = Theme.of(context);
    final acting = _actingId == r.messageId;
    final sender = _senderName(r);
    return Card(
      key: Key('report_tile_${r.messageId}'),
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              r.messageDeleted ? 'This message was deleted' : (r.messageBody ?? ''),
              style: theme.textTheme.bodyMedium?.copyWith(
                fontStyle: r.messageDeleted ? FontStyle.italic : null,
              ),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            Text(
              [
                if (sender != null) 'From $sender',
                '${r.reporterCount} ${r.reporterCount == 1 ? "reporter" : "reporters"}',
                _reasonSummary(r),
              ].join(' · '),
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            if (acting)
              const Align(
                alignment: Alignment.centerRight,
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else
              Wrap(
                spacing: 8,
                children: [
                  OutlinedButton(
                    key: Key('dismiss_reports_${r.messageId}'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 48),
                    ),
                    onPressed: () => _dismiss(r),
                    child: const Text('Dismiss'),
                  ),
                  if (!r.messageDeleted)
                    OutlinedButton(
                      key: Key('delete_reported_message_${r.messageId}'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.error,
                        minimumSize: const Size(0, 48),
                      ),
                      onPressed: () => _deleteMessage(r),
                      child: const Text('Delete message'),
                    ),
                  if (r.messageSenderId != null)
                    OutlinedButton(
                      key: Key('remove_reported_member_${r.messageId}'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.error,
                        minimumSize: const Size(0, 48),
                      ),
                      onPressed: () => _removeMember(r),
                      child: const Text('Remove member'),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
