import 'package:flutter/material.dart';

import '../../../core/constants/theme/app_colors.dart';
import '../../../core/models/group_join_request.dart';
import '../state/group_hub_controller.dart';

/// Manager-side pending join requests for one group. Rendered only when the
/// controller's server-reported MANAGE_MEMBERS is true (UX gate); the live
/// SELECT policy and `fn_approve_group_join_request` remain the boundary.
///
/// A requester is not a member, so their profile is not readable under the
/// live policy: each item is a generic "Join request" with its date/time.
class JoinRequestQueue extends StatelessWidget {
  const JoinRequestQueue({required this.controller, super.key});

  final GroupHubController controller;

  static String _when(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final c = controller;
    if (!c.canManageMembers) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Column(
      key: const Key('join_request_queue'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Join requests', style: theme.textTheme.titleMedium),
            const SizedBox(width: 8),
            if (c.pendingRequestCount > 0)
              Container(
                key: const Key('join_request_badge'),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.warning.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${c.pendingRequestCount}',
                  style: const TextStyle(
                    color: AppColors.warning,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        if (c.joinRequestsLoading &&
            c.joinRequests.isEmpty &&
            c.joinRequestsError == null)
          const LinearProgressIndicator(key: Key('join_requests_loading'))
        else if (c.joinRequestsError != null && c.joinRequests.isEmpty)
          Row(
            key: const Key('join_requests_error'),
            children: [
              Expanded(
                child: Text(
                  c.joinRequestsError!,
                  style: const TextStyle(color: AppColors.error),
                ),
              ),
              TextButton(
                key: const Key('join_requests_retry'),
                onPressed: c.retryJoinRequests,
                child: const Text('Retry'),
              ),
            ],
          )
        else if (c.joinRequests.isEmpty)
          Text(
            'No pending requests.',
            key: const Key('join_requests_empty'),
            style: theme.textTheme.bodySmall,
          )
        else
          for (final r in c.joinRequests) _tile(context, r),
        if (c.error != null && c.joinRequests.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              c.error!,
              key: const Key('join_request_action_error'),
              style: const TextStyle(color: AppColors.error),
            ),
          ),
      ],
    );
  }

  Widget _tile(BuildContext context, GroupJoinRequest r) {
    final c = controller;
    final acting = c.actingRequestId == r.id;
    final disabled = acting || c.isBusy;
    return ListTile(
      key: Key('join_request_${r.id}'),
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.person_add_alt_outlined),
      title: const Text('Join request'),
      subtitle: Text('Requested ${_when(r.createdAt)}'),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextButton(
            key: Key('decline_request_${r.id}'),
            onPressed: disabled
                ? null
                : () => _decide(context, r, approve: false),
            child: const Text('Decline'),
          ),
          FilledButton(
            key: Key('approve_request_${r.id}'),
            onPressed: disabled
                ? null
                : () => _decide(context, r, approve: true),
            child: Text(acting ? '…' : 'Approve'),
          ),
        ],
      ),
    );
  }

  Future<void> _decide(
    BuildContext context,
    GroupJoinRequest r, {
    required bool approve,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          approve ? 'Approve join request?' : 'Decline join request?',
        ),
        content: Text(
          approve
              ? 'The requester will become a member of this group.'
              : 'The requester will not join. They can request again later.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: Key(
              approve ? 'confirm_approve_request' : 'confirm_decline_request',
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(approve ? 'Approve' : 'Decline'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final ok = await controller.decideJoinRequest(r, approve: approve);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? (approve
                    ? 'Request approved. They are now a member.'
                    : 'Request declined.')
              : (controller.error ?? 'Could not update the request.'),
        ),
        backgroundColor: ok ? null : AppColors.error,
      ),
    );
  }
}
