import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/theme/app_colors.dart';
import '../../../core/models/group_message.dart';
import '../../test/data/test_repository.dart';
import '../data/notification_repository.dart';
import '../state/group_hub_controller.dart';
import '../widgets/group_avatar.dart';

/// Real-time cohort study chat screen with smart date separators,
/// soft-delete for author, responsive input composer, and seamless info navigation.
class GroupChatScreen extends StatefulWidget {
  const GroupChatScreen({required this.groupId, this.controller, super.key});

  final String groupId;
  final GroupHubController? controller;

  @override
  State<GroupChatScreen> createState() => _GroupChatScreenState();
}

class _GroupChatScreenState extends State<GroupChatScreen>
    with WidgetsBindingObserver {
  late final GroupHubController _c;
  late final bool _ownsController;
  final _input = TextEditingController();
  final _scrollController = ScrollController();
  bool _canSend = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _ownsController = widget.controller == null;
    _c =
        widget.controller ??
        GroupHubController(
          groupId: widget.groupId,
          notifications: const SupabaseNotificationRepository(),
          tests: const SupabaseTestRepository(),
        );
    _c.addListener(_onChanged);
    if (_ownsController) {
      _c.load();
    }
    _input.addListener(_onInputChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
  }

  void _onInputChanged() {
    final hasText = _input.text.trim().isNotEmpty;
    if (hasText != _canSend) {
      if (mounted) setState(() => _canSend = hasText);
    }
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _input.removeListener(_onInputChanged);
    _c.removeListener(_onChanged);
    if (_ownsController) {
      _c.dispose();
    }
    _input.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _c.refreshMessages();
    }
  }

  void _scrollToBottom({bool animate = false}) {
    if (!_scrollController.hasClients) return;
    final target = _scrollController.position.maxScrollExtent;
    if (animate) {
      _scrollController.animateTo(
        target,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    } else {
      _scrollController.jumpTo(target);
    }
  }

  bool _hasRoute(List<RouteBase> routes, String target) {
    for (final r in routes) {
      if (r is GoRoute) {
        if (r.path == target || r.name == target) return true;
        if (_hasRoute(r.routes, target)) return true;
      }
    }
    return false;
  }

  Future<void> _openInfo() async {
    final router = GoRouter.of(context);
    final hasInfo = _hasRoute(router.configuration.routes, 'info');
    if (hasInfo) {
      await context.push('/groups/${_c.groupId}/info');
    } else {
      await context.push('/groups/${_c.groupId}/settings');
    }
    if (mounted) {
      await _c.refresh();
    }
  }

  Future<void> _send() async {
    final text = _input.text;
    if (text.trim().isEmpty) return;
    HapticFeedback.lightImpact();
    final ok = await _c.sendMessage(text);
    if (!mounted) return;

    if (ok) {
      _input.clear();
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _scrollToBottom(animate: true),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_c.error ?? 'Could not send the message.'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Future<void> _onMessageLongPress(GroupMessage m, bool isMine) async {
    if (m.isSystem) return;
    HapticFeedback.mediumImpact();

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: isDark
                        ? const Color(0xFF475569)
                        : const Color(0xFFCBD5E1),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                if (!m.isDeleted)
                  ListTile(
                    leading: const Icon(Icons.copy_outlined, size: 20),
                    title: const Text('Copy message'),
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: m.body));
                      Navigator.pop(ctx);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Message copied to clipboard'),
                          duration: Duration(seconds: 2),
                        ),
                      );
                    },
                  ),
                if (isMine && !m.isDeleted)
                  ListTile(
                    key: const Key('delete_message_for_everyone'),
                    leading: const Icon(
                      Icons.delete_forever_outlined,
                      color: AppColors.error,
                      size: 22,
                    ),
                    title: const Text(
                      'Delete for everyone',
                      style: TextStyle(
                        color: AppColors.error,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    onTap: () async {
                      Navigator.pop(ctx);
                      await _confirmDeleteMessage(m);
                    },
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _confirmDeleteMessage(GroupMessage m) async {
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
            key: const Key('confirm_delete_message'),
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete for Everyone'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    final ok = await _c.deleteMessage(m);
    if (!mounted) return;

    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Message deleted for everyone.')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_c.error ?? 'Could not delete message.'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final group = _c.group;

    return Scaffold(
      backgroundColor: isDark
          ? const Color(0xFF0F172A)
          : const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
        elevation: 0.5,
        titleSpacing: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Back',
          onPressed: () => Navigator.maybePop(context),
        ),
        title: InkWell(
          key: const Key('discussion_open_info'),
          onTap: _openInfo,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: Row(
              children: [
                GroupAvatar(
                  name: group?.name ?? '',
                  logoUrl: group?.logoUrl,
                  radius: 18,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        group?.name ?? 'Group Chat',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          letterSpacing: -0.2,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${_c.memberCount} ${_c.memberCount == 1 ? 'member' : 'members'}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontSize: 12,
                          color: isDark
                              ? const Color(0xFF94A3B8)
                              : const Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            tooltip: 'Group info',
            onPressed: _openInfo,
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 960),
            child: Column(
              children: [
                if (!_c.isRealtimeConnected) _reconnectingStrip(context),
                Expanded(child: _buildMessageArea(context)),
                _buildComposer(context),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _reconnectingStrip(BuildContext context) {
    return Container(
      key: const Key('discussion_reconnecting'),
      width: double.infinity,
      color: const Color(0xFFFEF3C7),
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.sync_problem_rounded, size: 14, color: Color(0xFFD97706)),
          SizedBox(width: 8),
          Text(
            'Reconnecting live chat…',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: Color(0xFF92400E),
            ),
          ),
        ],
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
              Text(
                _c.messagesError!,
                key: const Key('discussion_error'),
                textAlign: TextAlign.center,
              ),
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
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.chat_bubble_outline_rounded,
                size: 56,
                color: Theme.of(context).colorScheme.outline
                    .withValues(alpha: 0.5),
              ),
              const SizedBox(height: 16),
              Text(
                'No messages yet. Say hello!',
                key: const Key('discussion_empty'),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w500,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final msgs = _c.messages;
    final totalCount = msgs.length + (_c.hasOlderMessages ? 1 : 0);

    return RefreshIndicator(
      onRefresh: _c.refreshMessages,
      child: ListView.builder(
        key: const Key('discussion_message_list'),
        controller: _scrollController,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        itemCount: totalCount,
        itemBuilder: (context, i) {
          if (_c.hasOlderMessages && i == 0) {
            return Center(
              child: TextButton(
                key: const Key('discussion_load_older'),
                onPressed: _c.olderMessagesLoading
                    ? null
                    : _c.loadOlderMessages,
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

          final msgIndex = i - (_c.hasOlderMessages ? 1 : 0);
          final currentMsg = msgs[msgIndex];

          // Check if date changed from previous message:
          final bool showDateSeparator;
          if (msgIndex == 0) {
            showDateSeparator = true;
          } else {
            final prevMsg = msgs[msgIndex - 1];
            showDateSeparator = !_isSameDay(
              currentMsg.createdAt,
              prevMsg.createdAt,
            );
          }

          final bubbleWidget = _bubble(context, currentMsg);

          if (showDateSeparator) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _dateSeparator(context, currentMsg.createdAt),
                bubbleWidget,
              ],
            );
          }

          return bubbleWidget;
        },
      ),
    );
  }

  static bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  static String _formatDatePill(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(date.year, date.month, date.day);
    final diff = today.difference(target).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${date.day.toString().padLeft(2, '0')} ${months[date.month - 1]} ${date.year}';
  }

  Widget _dateSeparator(BuildContext context, DateTime date) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final label = _formatDatePill(date);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0),
            borderRadius: BorderRadius.circular(12),
            boxShadow: const [
              BoxShadow(
                color: Color(0x06000000),
                blurRadius: 4,
                offset: Offset(0, 1),
              ),
            ],
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
              letterSpacing: 0.2,
            ),
          ),
        ),
      ),
    );
  }

  Widget _roleBadge(String role, bool isDark) {
    String label;
    Color bg;
    Color text;

    switch (role.toLowerCase()) {
      case 'owner':
        label = '👑 Admin';
        bg = isDark ? const Color(0xFF3B2814) : const Color(0xFFFEF3C7);
        text = isDark ? const Color(0xFFFBBF24) : const Color(0xFFB45309);
        break;
      case 'leader':
        label = '⭐ Leader';
        bg = isDark ? const Color(0xFF143026) : const Color(0xFFDCFCE7);
        text = isDark ? const Color(0xFF34D399) : const Color(0xFF15803D);
        break;
      case 'moderator':
        label = '🛡️ Mod';
        bg = isDark ? const Color(0xFF2E1C40) : const Color(0xFFF3E8FF);
        text = isDark ? const Color(0xFFC084FC) : const Color(0xFF7E22CE);
        break;
      default:
        return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 9.5,
          fontWeight: FontWeight.w700,
          color: text,
          letterSpacing: 0.1,
        ),
      ),
    );
  }

  Widget _bubble(BuildContext context, GroupMessage m) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final mine = m.senderId != null && m.senderId == _c.currentUserId;
    final label = _c.messageSenderLabel(m);

    if (m.isSystemEvent) {
      return Padding(
        key: Key('discussion_message_${m.id}'),
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 24),
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isDark
                    ? const Color(0xFF334155)
                    : const Color(0xFFE2E8F0),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  size: 13,
                  color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    m.body,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: isDark
                          ? const Color(0xFF94A3B8)
                          : const Color(0xFF64748B),
                      fontSize: 11.5,
                      fontWeight: FontWeight.w500,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final bodyText = m.isDeleted ? 'This message was deleted' : m.body;

    return Align(
      key: Key('discussion_message_${m.id}'),
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: () => _onMessageLongPress(m, mine),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 340),
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: mine
                ? (m.isDeleted
                      ? (isDark
                            ? const Color(0xFF1E293B)
                            : const Color(0xFFE2E8F0))
                      : const Color(0xFF2563EB))
                : (isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9)),
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(16),
              topRight: const Radius.circular(16),
              bottomLeft: Radius.circular(mine ? 16 : 4),
              bottomRight: Radius.circular(mine ? 4 : 16),
            ),
            border: Border.all(
              color: mine
                  ? Colors.transparent
                  : (isDark
                        ? const Color(0xFF334155)
                        : const Color(0xFFE2E8F0)),
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x08000000),
                blurRadius: 8,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!mine) ...[
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: isDark
                            ? const Color(0xFF60A5FA)
                            : const Color(0xFF2563EB),
                      ),
                    ),
                    Builder(builder: (context) {
                      final role = _c.messageSenderRole(m);
                      if (role != null && role != 'member') {
                        return Padding(
                          padding: const EdgeInsets.only(left: 6),
                          child: _roleBadge(role, isDark),
                        );
                      }
                      return const SizedBox.shrink();
                    }),
                  ],
                ),
                const SizedBox(height: 2),
              ],
              if (m.isDeleted)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.block_outlined,
                      size: 14,
                      color: isDark
                          ? const Color(0xFF94A3B8)
                          : const Color(0xFF64748B),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      bodyText,
                      style: TextStyle(
                        fontStyle: FontStyle.italic,
                        fontSize: 14,
                        color: isDark
                            ? const Color(0xFF94A3B8)
                            : const Color(0xFF64748B),
                      ),
                    ),
                  ],
                )
              else
                Text(
                  bodyText,
                  style: TextStyle(
                    fontSize: 14.5,
                    height: 1.35,
                    color: mine
                        ? Colors.white
                        : (isDark
                              ? const Color(0xFFF8FAFC)
                              : const Color(0xFF0F172A)),
                  ),
                ),
              const SizedBox(height: 4),
              Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    _formatTime(m.createdAt),
                    style: TextStyle(
                      fontSize: 11,
                      color: mine
                          ? (m.isDeleted
                                ? (isDark
                                      ? const Color(0xFF94A3B8)
                                      : const Color(0xFF64748B))
                                : const Color(0xCCFFFFFF))
                          : (isDark
                                ? const Color(0xFF94A3B8)
                                : const Color(0xFF64748B)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildComposer(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        border: Border(
          top: BorderSide(
            color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
          ),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          IconButton(
            tooltip: 'Emoji or attachment',
            icon: Icon(
              Icons.sentiment_satisfied_alt_outlined,
              color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
            ),
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Attachments and stickers coming soon!'),
                  duration: Duration(seconds: 1),
                ),
              );
            },
          ),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF0F172A)
                    : const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: isDark
                      ? const Color(0xFF334155)
                      : const Color(0xFFE2E8F0),
                ),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16),
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
                  hintText: 'Type a message...',
                  hintStyle: TextStyle(fontSize: 14),
                  border: InputBorder.none,
                  isDense: true,
                  counterText: '',
                  contentPadding: EdgeInsets.symmetric(vertical: 10),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            decoration: BoxDecoration(
              color: _canSend
                  ? const Color(0xFF2563EB)
                  : (isDark
                        ? const Color(0xFF334155)
                        : const Color(0xFFCBD5E1)),
              shape: BoxShape.circle,
            ),
            child: IconButton(
              key: const Key('discussion_send_button'),
              tooltip: 'Send',
              onPressed: _c.sending ? null : _send,
              icon: _c.sending
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.arrow_upward_rounded, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  static String _formatTime(DateTime t) {
    final hour = t.hour % 12 == 0 ? 12 : t.hour % 12;
    final minute = t.minute.toString().padLeft(2, '0');
    final ampm = t.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $ampm';
  }
}
