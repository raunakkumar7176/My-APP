import 'package:flutter/material.dart';

import '../../../core/constants/theme/app_colors.dart';
import '../../../core/models/group_message.dart';
import '../state/group_hub_controller.dart';

/// Chat section in the group hub: the latest window of `group_messages`
/// (oldest → newest), "Load earlier", refresh, and a send field. Every
/// member of the group may read and send — the live RLS (`fn_is_member`
/// SELECT; `sender_id = auth.uid() AND fn_is_member` INSERT) is the boundary.
/// No realtime: the list is server-backed and refreshed on demand / after
/// every send.
class GroupChatSection extends StatefulWidget {
  const GroupChatSection({required this.controller, super.key});

  final GroupHubController controller;

  @override
  State<GroupChatSection> createState() => _GroupChatSectionState();
}

class _GroupChatSectionState extends State<GroupChatSection> {
  final _input = TextEditingController();

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  GroupHubController get c => widget.controller;

  Future<void> _send() async {
    final text = _input.text;
    final ok = await c.sendMessage(text);
    if (!mounted) return;
    if (ok) {
      _input.clear();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(c.error ?? 'Could not send the message.'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      key: const Key('group_chat_section'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Chat', style: theme.textTheme.titleMedium),
            const SizedBox(width: 8),
            if (c.messages.isNotEmpty)
              Text(
                '${c.messages.length}',
                key: const Key('messages_count'),
                style: theme.textTheme.bodySmall,
              ),
            const Spacer(),
            IconButton(
              key: const Key('messages_refresh'),
              tooltip: 'Refresh chat',
              icon: const Icon(Icons.refresh, size: 20),
              onPressed: c.messagesLoading || c.sending ? null : c.refreshMessages,
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (c.messagesLoading && c.messages.isEmpty && c.messagesError == null)
          const LinearProgressIndicator(key: Key('messages_loading'))
        else if (c.messagesError != null && c.messages.isEmpty)
          Row(
            key: const Key('messages_error'),
            children: [
              Expanded(
                child: Text(
                  c.messagesError!,
                  style: const TextStyle(color: AppColors.error),
                ),
              ),
              TextButton(
                key: const Key('messages_retry'),
                onPressed: c.messagesLoading ? null : c.refreshMessages,
                child: const Text('Retry'),
              ),
            ],
          )
        else if (c.messages.isEmpty)
          Text(
            'No messages yet. Say hello!',
            key: const Key('messages_empty'),
            style: theme.textTheme.bodySmall,
          )
        else ...[
          if (c.hasOlderMessages)
            Center(
              child: TextButton(
                key: const Key('messages_load_older'),
                onPressed: c.olderMessagesLoading ? null : c.loadOlderMessages,
                child: c.olderMessagesLoading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Load earlier messages'),
              ),
            ),
          for (final m in c.messages) _bubble(context, m),
        ],
        if (c.messagesError != null && c.messages.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              c.messagesError!,
              key: const Key('messages_action_error'),
              style: const TextStyle(color: AppColors.error),
            ),
          ),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                key: const Key('message_field'),
                controller: _input,
                enabled: !c.sending,
                minLines: 1,
                maxLines: 4,
                maxLength: GroupMessage.maxBodyLength,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => c.sending ? null : _send(),
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
              key: const Key('send_message_button'),
              tooltip: 'Send',
              onPressed: c.sending ? null : _send,
              icon: c.sending
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.send),
            ),
          ],
        ),
      ],
    );
  }

  Widget _bubble(BuildContext context, GroupMessage m) {
    final theme = Theme.of(context);
    final mine = m.senderId != null && m.senderId == c.currentUserId;
    final label = c.messageSenderLabel(m);
    if (m.isSystem) {
      return Padding(
        key: Key('message_${m.id}'),
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Center(
          child: Text(
            m.body,
            style: theme.textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return Align(
      key: Key('message_${m.id}'),
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 320),
        margin: const EdgeInsets.symmetric(vertical: 3),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: mine
              ? theme.colorScheme.primaryContainer
              : theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              key: Key('message_sender_${m.id}'),
              style: theme.textTheme.labelSmall,
            ),
            const SizedBox(height: 2),
            Text(m.body),
            const SizedBox(height: 2),
            Text(_when(m.createdAt), style: theme.textTheme.bodySmall),
          ],
        ),
      ),
    );
  }

  static String _when(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
  }
}
