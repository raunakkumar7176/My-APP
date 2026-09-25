import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/theme/app_colors.dart';
import '../../../core/models/group_message.dart';
import '../state/group_hub_controller.dart';
import '../widgets/group_avatar.dart';

/// Dedicated full-screen group discussion — the professional-workspace
/// equivalent of a familiar chat layout (header, message bubbles,
/// composer), backed by the SAME [GroupHubController] instance the Group
/// Hub already loaded (shares its realtime subscription and message
/// window rather than opening a second one for the same group).
///
/// Not a second chat implementation: message rendering/validation/sending
/// logic here mirrors `GroupChatSection` (kept separately there because
/// that widget is also embedded directly in the Hub and is independently
/// tested) — both read and write through the one controller.
class GroupDiscussionScreen extends StatefulWidget {
  const GroupDiscussionScreen({required this.controller, super.key});

  final GroupHubController controller;

  @override
  State<GroupDiscussionScreen> createState() => _GroupDiscussionScreenState();
}

class _GroupDiscussionScreenState extends State<GroupDiscussionScreen>
    with WidgetsBindingObserver {
  final _input = TextEditingController();
  final _scrollController = ScrollController();

  GroupHubController get _c => widget.controller;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _c.addListener(_onChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _c.removeListener(_onChanged);
    _input.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Phase 13: catch anything missed while backgrounded — belt-and-suspenders
    // alongside Realtime's own auto-reconnect, never the only mechanism.
    if (state == AppLifecycleState.resumed) {
      _c.refreshMessages();
    }
  }

  void _scrollToBottom() {
    if (!_scrollController.hasClients) return;
    _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
  }

  Future<void> _send() async {
    final text = _input.text;
    final ok = await _c.sendMessage(text);
    if (!mounted) return;
    if (ok) {
      _input.clear();
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_c.error ?? 'Could not send the message.'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final group = _c.group;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: InkWell(
          key: const Key('discussion_open_info'),
          onTap: () => context.push('/groups/${_c.groupId}/settings'),
          child: Row(
            children: [
              GroupAvatar(
                name: group?.name ?? '',
                logoUrl: group?.logoUrl,
                radius: 16,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      group?.name ?? 'Discussion',
                      style: Theme.of(context).textTheme.titleMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      '${_c.memberCount} ${_c.memberCount == 1 ? 'member' : 'members'}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      body: Column(
        children: [
          if (!_c.isRealtimeConnected) _reconnectingStrip(context),
          Expanded(child: _buildMessageArea(context)),
          _buildComposer(context),
        ],
      ),
    );
  }

  Widget _reconnectingStrip(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      key: const Key('discussion_reconnecting'),
      width: double.infinity,
      color: theme.colorScheme.surfaceContainerHigh,
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Text(
        'Reconnecting…',
        textAlign: TextAlign.center,
        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
      ),
    );
  }

  Widget _buildMessageArea(BuildContext context) {
    if (_c.messagesLoading && _c.messages.isEmpty && _c.messagesError == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_c.messagesError != null && _c.messages.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_c.messagesError!, key: const Key('discussion_error'), textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton(
                key: const Key('discussion_retry'),
                onPressed: _c.messagesLoading ? null : _c.refreshMessages,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }
    if (_c.messages.isEmpty) {
      return Center(
        child: Text(
          'No messages yet. Say hello!',
          key: const Key('discussion_empty'),
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _c.refreshMessages,
      child: ListView.builder(
        key: const Key('discussion_message_list'),
        controller: _scrollController,
        padding: const EdgeInsets.all(12),
        itemCount: _c.messages.length + (_c.hasOlderMessages ? 1 : 0),
        itemBuilder: (context, i) {
          if (_c.hasOlderMessages && i == 0) {
            return Center(
              child: TextButton(
                key: const Key('discussion_load_older'),
                onPressed: _c.olderMessagesLoading ? null : _c.loadOlderMessages,
                child: _c.olderMessagesLoading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Load earlier messages'),
              ),
            );
          }
          final m = _c.messages[i - (_c.hasOlderMessages ? 1 : 0)];
          return _bubble(context, m);
        },
      ),
    );
  }

  Widget _bubble(BuildContext context, GroupMessage m) {
    final theme = Theme.of(context);
    final mine = m.senderId != null && m.senderId == _c.currentUserId;
    final label = _c.messageSenderLabel(m);

    if (m.isSystem) {
      return Padding(
        key: Key('discussion_message_${m.id}'),
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(m.body, style: theme.textTheme.bodySmall, textAlign: TextAlign.center),
          ),
        ),
      );
    }

    final bodyText = m.isDeleted ? 'Message deleted' : m.body;
    return Align(
      key: Key('discussion_message_${m.id}'),
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 320),
        margin: const EdgeInsets.symmetric(vertical: 3),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: mine ? theme.colorScheme.primaryContainer : theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!mine)
              Text(label, style: theme.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w600)),
            Text(
              bodyText,
              style: m.isDeleted
                  ? theme.textTheme.bodyMedium?.copyWith(
                      fontStyle: FontStyle.italic,
                      color: theme.colorScheme.outline,
                    )
                  : theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 2),
            Text(_when(m.createdAt), style: theme.textTheme.bodySmall),
          ],
        ),
      ),
    );
  }

  Widget _buildComposer(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                key: const Key('discussion_message_field'),
                controller: _input,
                enabled: !_c.sending,
                minLines: 1,
                maxLines: 4,
                maxLength: GroupMessage.maxBodyLength,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _c.sending ? null : _send(),
                decoration: const InputDecoration(
                  hintText: 'Message the group',
                  border: OutlineInputBorder(),
                  isDense: true,
                  counterText: '',
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              key: const Key('discussion_send_button'),
              tooltip: 'Send',
              onPressed: _c.sending ? null : _send,
              icon: _c.sending
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.send),
            ),
          ],
        ),
      ),
    );
  }

  static String _when(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(t.hour)}:${two(t.minute)}';
  }
}
