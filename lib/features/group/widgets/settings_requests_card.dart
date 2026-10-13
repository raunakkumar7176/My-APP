import 'package:flutter/material.dart';

import '../state/group_hub_controller.dart';
import 'join_request_queue.dart';
import 'outgoing_invitations_section.dart';

/// Join requests (with Accept/Reject) plus a collapsible outgoing-
/// invitations history, also shown in Settings as a convenience for
/// whoever is already here with GROUP_SETTINGS. NOT a replacement for the
/// dedicated Requests screen (`/groups/:id/requests`): that one is gated
/// on MANAGE_MEMBERS alone, which an admin can hold without also holding
/// GROUP_SETTINGS (the live default leader/admin seeding grants
/// everything except GROUP_SETTINGS and MANAGE_ROLES) — folding this
/// exclusively into Settings would lock such an admin out of reviewing
/// join requests entirely. Both widgets self-gate on MANAGE_MEMBERS, so
/// nothing here widens who can act.
class SettingsRequestsCard extends StatefulWidget {
  const SettingsRequestsCard({required this.controller, super.key});

  final GroupHubController controller;

  @override
  State<SettingsRequestsCard> createState() => _SettingsRequestsCardState();
}

class _SettingsRequestsCardState extends State<SettingsRequestsCard> {
  bool _showInvitationsHistory = false;

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    if (!c.canManageMembers) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Column(
      key: const Key('settings_requests_card'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        JoinRequestQueue(controller: c),
        const SizedBox(height: 16),
        InkWell(
          key: const Key('toggle_invitations_history'),
          onTap: () => setState(() => _showInvitationsHistory = !_showInvitationsHistory),
          child: Row(
            children: [
              Text('Invitations history', style: theme.textTheme.titleMedium),
              const SizedBox(width: 4),
              Icon(
                _showInvitationsHistory
                    ? Icons.expand_less_rounded
                    : Icons.expand_more_rounded,
              ),
            ],
          ),
        ),
        if (_showInvitationsHistory) ...[
          const SizedBox(height: 8),
          OutgoingInvitationsSection(controller: c),
        ],
      ],
    );
  }
}
