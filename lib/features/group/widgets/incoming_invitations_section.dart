import 'package:flutter/material.dart';

import '../../../core/constants/theme/app_colors.dart';
import '../../../core/models/group_invitation.dart';
import '../state/group_list_controller.dart';

/// Incoming invitations for the signed-in user (invitee rows only).
///
/// Only the five live columns are known: the group's name and the inviter's
/// name are deliberately not shown, because a non-member cannot read a
/// private or restricted group's row and no verified path exists to resolve
/// them without a new RPC. Accept/Decline call the live functions; the
/// invitation id is never treated as authorization — the server is.
class IncomingInvitationsSection extends StatelessWidget {
  const IncomingInvitationsSection({
    required this.controller,
    required this.onAccepted,
    super.key,
  });

  final GroupListController controller;

  /// Called with the group id **only when the server confirmed membership**
  /// after accepting (the group appeared in `rpc_get_user_groups`).
  final void Function(String groupId) onAccepted;

  static String _when(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final c = controller;
    if (c.invitationsLoading &&
        c.invitations.isEmpty &&
        c.invitationsError == null) {
      return const Padding(
        key: Key('invitations_loading'),
        padding: EdgeInsets.only(bottom: 12),
        child: LinearProgressIndicator(),
      );
    }
    if (c.invitationsError != null && c.invitations.isEmpty) {
      return Card(
        key: const Key('invitations_error'),
        margin: const EdgeInsets.only(bottom: 12),
        child: ListTile(
          leading: const Icon(Icons.error_outline, color: AppColors.error),
          title: const Text('Could not load invitations'),
          subtitle: Text(c.invitationsError!),
          trailing: TextButton(
            key: const Key('invitations_retry'),
            onPressed: c.retryInvitations,
            child: const Text('Retry'),
          ),
        ),
      );
    }
    if (!c.hasInvitations)
      return const SizedBox.shrink(key: Key('invitations_empty'));

    return Column(
      key: const Key('invitations_section'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            c.invitations.length == 1
                ? '1 invitation'
                : '${c.invitations.length} invitations',
            key: const Key('invitations_heading'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        for (final inv in c.invitations) _tile(context, inv),
        if (c.error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              c.error!,
              key: const Key('invitation_action_error'),
              style: const TextStyle(color: AppColors.error),
            ),
          ),
        const SizedBox(height: 4),
      ],
    );
  }

  Widget _tile(BuildContext context, GroupInvitation inv) {
    final c = controller;
    final acting = c.actingInvitationId == inv.id;
    final anyActing = c.actingInvitationId != null || c.isBusy;
    return Card(
      key: Key('invitation_${inv.id}'),
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: const Icon(Icons.mail_outline),
        title: const Text('Group invitation'),
        subtitle: Text(
          inv.isPending
              ? 'Received ${_when(inv.createdAt)}'
              : 'Received ${_when(inv.createdAt)} · ${inv.status}',
          key: Key('invitation_meta_${inv.id}'),
        ),
        trailing: !inv.isPending
            ? null
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextButton(
                    key: Key('decline_${inv.id}'),
                    onPressed: anyActing ? null : () => _decline(context, inv),
                    child: const Text('Decline'),
                  ),
                  FilledButton(
                    key: Key('accept_${inv.id}'),
                    onPressed: anyActing ? null : () => _accept(context, inv),
                    child: Text(acting ? '…' : 'Accept'),
                  ),
                ],
              ),
      ),
    );
  }

  Future<void> _accept(BuildContext context, GroupInvitation inv) async {
    final groupId = await controller.acceptInvitation(inv);
    if (!context.mounted) return;
    if (groupId != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Invitation accepted. You joined the group.'),
        ),
      );
      onAccepted(groupId);
    } else if (controller.error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(controller.error!),
          backgroundColor: AppColors.error,
        ),
      );
    } else {
      // Accepted, but membership was not visible in the refreshed list yet:
      // do not guess — the user opens it from the list once it appears.
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Invitation accepted. Pull to refresh your groups.'),
        ),
      );
    }
  }

  Future<void> _decline(BuildContext context, GroupInvitation inv) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Decline invitation?'),
        content: const Text('You can be invited again later.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('confirm_decline'),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Decline'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final ok = await controller.declineInvitation(inv);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? 'Invitation declined.'
              : (controller.error ?? 'Could not decline.'),
        ),
        backgroundColor: ok ? null : AppColors.error,
      ),
    );
  }
}
