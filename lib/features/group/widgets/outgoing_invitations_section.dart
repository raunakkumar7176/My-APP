import 'package:flutter/material.dart';

import '../../../core/constants/theme/app_colors.dart';
import '../../../core/models/group_invitation.dart';
import '../state/group_hub_controller.dart';

/// Manager-side invitations of one group (all statuses). Rendered only when
/// the controller's server-reported MANAGE_MEMBERS is true; the live RLS
/// (DELETE: inviter OR MANAGE_MEMBERS; INSERT: inviter = uid AND
/// MANAGE_MEMBERS) remains the boundary.
///
/// The invitee cannot be named: a non-member's profile is not readable and no
/// lookup exists (G5.6). Status is shown exactly as the server stores it —
/// nothing computes or dates expiry.
class OutgoingInvitationsSection extends StatelessWidget {
  const OutgoingInvitationsSection({required this.controller, super.key});

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
    final pending = c.outgoingInvitations.where((i) => i.isPending).length;
    return Column(
      key: const Key('outgoing_invitations'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Sent invitations', style: theme.textTheme.titleMedium),
            const SizedBox(width: 8),
            if (pending > 0)
              Text(
                '$pending pending',
                key: const Key('outgoing_pending_count'),
                style: theme.textTheme.bodySmall,
              ),
          ],
        ),
        const SizedBox(height: 8),
        if (c.outgoingLoading &&
            c.outgoingInvitations.isEmpty &&
            c.outgoingError == null)
          const LinearProgressIndicator(key: Key('outgoing_loading'))
        else if (c.outgoingError != null && c.outgoingInvitations.isEmpty)
          Row(
            key: const Key('outgoing_error'),
            children: [
              Expanded(
                child: Text(
                  c.outgoingError!,
                  style: const TextStyle(color: AppColors.error),
                ),
              ),
              TextButton(
                key: const Key('outgoing_retry'),
                onPressed: c.retryOutgoingInvitations,
                child: const Text('Retry'),
              ),
            ],
          )
        else if (c.outgoingInvitations.isEmpty)
          Text(
            'No invitations sent yet.',
            key: const Key('outgoing_empty'),
            style: theme.textTheme.bodySmall,
          )
        else
          for (final inv in c.outgoingInvitations) _tile(context, inv),
        if (c.error != null && c.outgoingInvitations.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              c.error!,
              key: const Key('outgoing_action_error'),
              style: const TextStyle(color: AppColors.error),
            ),
          ),
      ],
    );
  }

  Widget _tile(BuildContext context, GroupInvitation inv) {
    final c = controller;
    final acting = c.actingInvitationId == inv.id;
    final disabled = acting || c.isBusy;
    Widget? action;
    if (inv.isPending) {
      action = TextButton(
        key: Key('cancel_invitation_${inv.id}'),
        onPressed: disabled ? null : () => _cancel(context, inv),
        child: Text(acting ? '…' : 'Cancel'),
      );
    } else if (c.canReinvite(inv)) {
      action = TextButton(
        key: Key('reinvite_${inv.id}'),
        onPressed: disabled ? null : () => _reinvite(context, inv),
        child: Text(acting ? '…' : 'Re-invite'),
      );
    }
    return ListTile(
      key: Key('outgoing_${inv.id}'),
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.outgoing_mail),
      title: Text('Invitation · Sent ${_when(inv.createdAt)}'),
      subtitle: Text(
        inv.status, // server status verbatim; never computed
        key: Key('outgoing_status_${inv.id}'),
      ),
      trailing: action,
    );
  }

  Future<bool?> _confirm(
    BuildContext context, {
    required String title,
    required String body,
    required String action,
    required Key key,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Keep'),
          ),
          FilledButton(
            key: key,
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(action),
          ),
        ],
      ),
    );
  }

  Future<void> _cancel(BuildContext context, GroupInvitation inv) async {
    final ok = await _confirm(
      context,
      title: 'Cancel invitation?',
      body: 'The invitation will be withdrawn. It can be sent again later.',
      action: 'Cancel invitation',
      key: const Key('confirm_cancel_invitation'),
    );
    if (ok != true || !context.mounted) return;
    final done = await controller.cancelInvitation(inv);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          done
              ? 'Invitation cancelled.'
              : (controller.error ?? 'Could not cancel.'),
        ),
        backgroundColor: done ? null : AppColors.error,
      ),
    );
  }

  Future<void> _reinvite(BuildContext context, GroupInvitation inv) async {
    final ok = await _confirm(
      context,
      title: 'Send the invitation again?',
      body:
          'The declined invitation will be replaced by a new pending one. '
          'This happens in two steps; if the second step fails you will be '
          'told exactly that.',
      action: 'Re-invite',
      key: const Key('confirm_reinvite'),
    );
    if (ok != true || !context.mounted) return;
    final done = await controller.reinvite(inv);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          done
              ? 'Invitation sent again.'
              : (controller.error ?? 'Could not re-invite.'),
        ),
        backgroundColor: done ? null : AppColors.error,
      ),
    );
  }
}
