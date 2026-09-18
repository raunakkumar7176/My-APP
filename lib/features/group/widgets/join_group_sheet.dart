import 'package:flutter/material.dart';

import '../../../core/constants/theme/app_colors.dart';
import '../data/group_repository.dart';
import '../state/group_list_controller.dart';

/// Join a group with its invite code.
///
/// The server decides what joining means: `fn_join_group` adds the member for
/// a public/private group and, for a `restricted` one, files a join request
/// and returns NULL. Both are shown truthfully here; the client never checks
/// privacy itself.
class JoinGroupSheet extends StatefulWidget {
  const JoinGroupSheet({required this.controller, super.key});

  final GroupListController controller;

  /// Returns the group id to open, or null (cancelled, failed, or a join
  /// request was filed and there is nothing to open yet).
  static Future<String?> show(
    BuildContext context, {
    required GroupListController controller,
  }) {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (_) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: JoinGroupSheet(controller: controller),
      ),
    );
  }

  @override
  State<JoinGroupSheet> createState() => _JoinGroupSheetState();
}

class _JoinGroupSheetState extends State<JoinGroupSheet> {
  final _code = TextEditingController();
  String? _info;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChanged);
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChanged);
    _code.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _info = null);
    final outcome = await widget.controller.joinByCode(_code.text);
    if (!mounted || outcome == null) return;
    switch (outcome) {
      case JoinedGroup(:final groupId):
        Navigator.of(context).pop(groupId);
      case JoinRequestFiled():
        // NULL from fn_join_group = restricted group, request upserted. The
        // controller re-read the caller's own pending rows from the server;
        // whether or not a row came back, this is a pending state, never
        // membership, and never opens the hub.
        setState(() {
          _info = widget.controller.hasPendingRequests
              ? 'Join request pending. A group manager has to approve it '
                    'before you can open this group.'
              : 'Request sent. A group manager has to approve it before you '
                    'can open this group.';
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Join a group', style: Theme.of(context).textTheme.titleMedium),
          if (c.hasPendingRequests) ...[
            const SizedBox(height: 8),
            Text(
              c.pendingRequests.length == 1
                  ? 'You have 1 join request awaiting approval.'
                  : 'You have ${c.pendingRequests.length} join requests awaiting approval.',
              key: const Key('join_pending_banner'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          const SizedBox(height: 12),
          TextField(
            key: const Key('invite_code_field'),
            controller: _code,
            autofocus: true,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(
              labelText: 'Invite code',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (_) => _submit(),
          ),
          if (c.error != null) ...[
            const SizedBox(height: 8),
            Text(
              c.error!,
              key: const Key('join_error'),
              style: const TextStyle(color: AppColors.error),
            ),
          ],
          if (_info != null) ...[
            const SizedBox(height: 8),
            Text(_info!, key: const Key('join_request_filed')),
          ],
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              key: const Key('join_submit'),
              onPressed: c.isBusy ? null : _submit,
              child: Text(c.isBusy ? 'Joining…' : 'Join'),
            ),
          ),
        ],
      ),
    );
  }
}
