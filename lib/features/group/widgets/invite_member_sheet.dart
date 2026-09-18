import 'package:flutter/material.dart';

import '../../../core/constants/theme/app_colors.dart';
import '../state/group_hub_controller.dart';
import '../state/invite_member_controller.dart';
import 'group_avatar.dart';

/// Invite an existing registered user by student code. Opened from the Group
/// Hub only when the server-reported MANAGE_MEMBERS is true; the lookup runs
/// on an explicit Search, the invitation is sent as `{group_id, invitee_id}`
/// with the session user as inviter, and the live INSERT policy + UNIQUE
/// remain the boundary.
class InviteMemberSheet extends StatefulWidget {
  const InviteMemberSheet({required this.hub, this.controller, super.key});

  final GroupHubController hub;

  /// Injectable for tests; otherwise created from the hub's current context.
  final InviteMemberController? controller;

  /// Returns true when an invitation was sent (caller refreshes the hub).
  static Future<bool?> show(
    BuildContext context, {
    required GroupHubController hub,
  }) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: InviteMemberSheet(hub: hub),
      ),
    );
  }

  @override
  State<InviteMemberSheet> createState() => _InviteMemberSheetState();
}

class _InviteMemberSheetState extends State<InviteMemberSheet> {
  late final InviteMemberController _c;
  late final bool _owns;
  final _code = TextEditingController();

  @override
  void initState() {
    super.initState();
    _owns = widget.controller == null;
    _c =
        widget.controller ??
        InviteMemberController(
          groupId: widget.hub.groupId,
          currentUserId: widget.hub.currentUserId,
          members: widget.hub.members,
          invitations: widget.hub.outgoingInvitations,
          repository: widget.hub.repository,
        );
    _c.addListener(_onChanged);
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _c.removeListener(_onChanged);
    if (_owns) _c.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final m = _c.match;
    if (m == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Send invitation?'),
        content: Text(
          '${m.displayName} (${m.studentCode}) will be invited to this group.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('confirm_send_invitation'),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Send'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final ok = await _c.send();
    if (!mounted) return;
    if (ok) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Invitation sent.')));
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;
    final theme = Theme.of(context);
    final m = c.match;
    final state = m == null ? null : c.stateFor(m);
    final canSend = state == InviteeState.canInvite && !c.isBusy;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Invite a member', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'Enter the student code shown on their profile (for example MP-1A2B3).',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  key: const Key('invite_code_input'),
                  controller: _code,
                  autofocus: true,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(
                    labelText: 'Student code',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  onSubmitted: (_) => c.search(_code.text),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.tonal(
                key: const Key('invite_search'),
                onPressed: c.isBusy ? null : () => c.search(_code.text),
                child: Text(c.isSearching ? '…' : 'Search'),
              ),
            ],
          ),
          if (c.isSearching) ...[
            const SizedBox(height: 8),
            const LinearProgressIndicator(key: Key('invite_searching')),
          ],
          if (m != null) ...[
            const SizedBox(height: 12),
            ListTile(
              key: const Key('invite_match'),
              contentPadding: EdgeInsets.zero,
              leading: GroupAvatar(name: m.displayName, logoUrl: m.avatarUrl),
              title: Text(m.displayName),
              subtitle: Text(
                m.studentCode,
                key: const Key('invite_match_code'),
              ),
              trailing: state == InviteeState.canInvite
                  ? null
                  : Text(_stateLabel(state!), key: const Key('invite_state')),
            ),
          ],
          if (c.error != null) ...[
            const SizedBox(height: 8),
            Text(
              c.error!,
              key: const Key('invite_error'),
              style: const TextStyle(color: AppColors.error),
            ),
          ],
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              key: const Key('invite_send'),
              onPressed: canSend ? _send : null,
              child: Text(c.isSending ? 'Sending…' : 'Send invitation'),
            ),
          ),
        ],
      ),
    );
  }

  static String _stateLabel(InviteeState s) {
    switch (s) {
      case InviteeState.self:
        return 'That is you';
      case InviteeState.alreadyMember:
        return 'Already a member';
      case InviteeState.alreadyPending:
        return 'Invitation pending';
      case InviteeState.accepted:
        return 'Already accepted';
      case InviteeState.declined:
        return 'Declined earlier';
      case InviteeState.expired:
        return 'Marked expired';
      case InviteeState.canInvite:
        return '';
    }
  }
}
