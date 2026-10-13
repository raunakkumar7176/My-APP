import 'package:flutter/material.dart';

import '../../test/data/test_repository.dart';
import '../data/notification_repository.dart';
import '../state/group_hub_controller.dart';
import '../widgets/join_request_queue.dart';
import '../widgets/outgoing_invitations_section.dart';

/// Join requests + outgoing invitations, moved off the Info screen (which
/// used to render both inline, long enough to dominate the page) into their
/// own manager-only screen. Both widgets still self-gate on MANAGE_MEMBERS,
/// so nothing changes about who can see what — only where it lives.
class GroupRequestsScreen extends StatefulWidget {
  const GroupRequestsScreen({required this.groupId, this.controller, super.key});

  final String groupId;
  final GroupHubController? controller;

  @override
  State<GroupRequestsScreen> createState() => _GroupRequestsScreenState();
}

class _GroupRequestsScreenState extends State<GroupRequestsScreen> {
  late final GroupHubController _c;
  late final bool _owns;

  @override
  void initState() {
    super.initState();
    _owns = widget.controller == null;
    _c =
        widget.controller ??
        GroupHubController(
          groupId: widget.groupId,
          notifications: const SupabaseNotificationRepository(),
          tests: const SupabaseTestRepository(),
        );
    _c.addListener(_onChanged);
    _c.load();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _c.removeListener(_onChanged);
    if (_owns) _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Requests & Invitations')),
      body: RefreshIndicator(
        onRefresh: _c.refresh,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            JoinRequestQueue(controller: _c),
            const SizedBox(height: 20),
            OutgoingInvitationsSection(controller: _c),
          ],
        ),
      ),
    );
  }
}
