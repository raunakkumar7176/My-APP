import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/theme/app_colors.dart';
import '../../../core/models/group_member.dart';
import '../../../core/models/group_message.dart';
import '../../../core/theme/app_radius.dart';
import '../../test/data/test_repository.dart';
import '../data/chat_local_state.dart';
import '../data/notification_repository.dart';
import '../domain/group_test_management.dart';
import '../state/group_hub_controller.dart';
import '../widgets/chat_widgets.dart';
import '../widgets/group_avatar.dart';

/// A ground-up redesign of the cohort chat screen — same real-time
/// messaging, soft-delete-for-everyone, and group semantics as before, in a
/// deliberately different visual language: fully-rounded "soft" bubbles
/// with a per-sender avatar on the first message of a run (instead of a
/// WhatsApp-style tail), a frosted/blurred app bar, a pill composer with a
/// morphing send button, and a first-appearance fade+rise for new messages
/// (tracked by id, so scrolling back into view never replays it).
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
  bool _muted = false;
  final _local = const ChatLocalState();

  /// When this device last opened this chat (null the very first time) —
  /// drives the one-shot "New messages" divider. Captured before it's
  /// overwritten for next time.
  DateTime? _unreadDividerAt;

  /// Local-only "Clear chat" cutoff: messages at or before this moment are
  /// hidden on this device, nowhere else. Null means nothing is cleared.
  DateTime? _clearedBeforeAt;

  /// Shows the scroll-to-bottom button once the viewer has scrolled away
  /// from the latest message.
  bool _showScrollToBottom = false;

  /// Message ids already shown once — only a genuinely NEW id (just
  /// arrived, or just sent) gets the entrance animation; scrolling an old
  /// message back into view must never replay it.
  final Set<String> _animatedOnce = {};

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
    _loadLocalState();
    _input.addListener(_onInputChanged);
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    _loadMuted();
  }

  Future<void> _loadLocalState() async {
    final lastOpened = await _local.lastOpenedAt(widget.groupId);
    final clearedBefore = await _local.clearedBefore(widget.groupId);
    if (mounted) {
      setState(() {
        _unreadDividerAt = lastOpened;
        _clearedBeforeAt = clearedBefore;
      });
    }
    // Record this visit for next time — after reading the previous value,
    // never before.
    await _local.setLastOpenedAt(widget.groupId, DateTime.now());
  }

  Future<void> _clearChatForMe(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear chat?'),
        content: const Text(
          'This hides the chat history on this device only. Other members, '
          'and your own other devices, keep seeing it as it is.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('confirm_clear_chat'),
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Clear Chat'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final now = DateTime.now();
    await _local.clearChat(widget.groupId, now);
    if (!mounted) return;
    setState(() => _clearedBeforeAt = now);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Chat cleared on this device.')),
    );
  }

  Future<void> _loadMuted() async {
    final repo = _c.notifications;
    if (repo == null) return;
    try {
      final muted = await repo.isMuted(_c.groupId);
      if (mounted) setState(() => _muted = muted);
    } catch (_) {
      // Best-effort; the menu simply shows "Mute" until this succeeds.
    }
  }

  Future<void> _toggleMuted(BuildContext context) async {
    final repo = _c.notifications;
    if (repo == null) return;
    final next = !_muted;
    try {
      await repo.setMuted(_c.groupId, muted: next);
      if (mounted) setState(() => _muted = next);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(next ? 'Notifications muted' : 'Notifications unmuted'),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not update notification settings.'),
          backgroundColor: AppColors.error,
        ),
      );
    }
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
    _scrollController.removeListener(_onScroll);
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

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final awayFromBottom =
        _scrollController.position.maxScrollExtent - _scrollController.offset >
        240;
    if (awayFromBottom != _showScrollToBottom) {
      setState(() => _showScrollToBottom = awayFromBottom);
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
    // Optimistic: the input clears and the pending bubble appears right
    // away, regardless of how the send resolves — a failure leaves a
    // "Failed · Tap to retry" row instead of restoring the typed text.
    _input.clear();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _scrollToBottom(animate: true),
    );
    final ok = await _c.sendMessage(text);
    if (!mounted) return;

    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_c.error ?? 'Could not send the message.'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  GroupMember? _senderOf(GroupMessage m) {
    final id = m.senderId;
    if (id == null) return null;
    for (final mem in _c.members) {
      if (mem.userId == id) return mem;
    }
    return null;
  }

  Future<void> _onMessageLongPress(GroupMessage m, bool isMine) async {
    if (m.isSystem) return;
    // A still-sending or failed row has no server id yet — nothing to copy
    // or delete server-side. Tapping it (when failed) retries instead.
    if (_c.isMessageSending(m.id) || _c.isMessageFailed(m.id)) return;
    HapticFeedback.mediumImpact();

    final isDark = Theme.of(context).brightness == Brightness.dark;

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _sheetHandle(isDark),
                const SizedBox(height: 8),
                if (!m.isDeleted)
                  _sheetAction(
                    icon: Icons.copy_rounded,
                    iconColor: isDark
                        ? const Color(0xFF60A5FA)
                        : const Color(0xFF2563EB),
                    label: 'Copy message',
                    isDark: isDark,
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
                  _sheetAction(
                    key: const Key('delete_message_for_everyone'),
                    icon: Icons.delete_forever_rounded,
                    iconColor: AppColors.error,
                    label: 'Delete for everyone',
                    labelColor: AppColors.error,
                    isDark: isDark,
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

  Widget _sheetHandle(bool isDark) => Container(
    width: 36,
    height: 4,
    decoration: BoxDecoration(
      color: isDark ? const Color(0xFF475569) : const Color(0xFFCBD5E1),
      borderRadius: BorderRadius.circular(2),
    ),
  );

  Widget _sheetAction({
    Key? key,
    required IconData icon,
    required Color iconColor,
    required String label,
    required bool isDark,
    required VoidCallback onTap,
    Color? labelColor,
  }) {
    return Material(
      key: key,
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: isDark ? 0.18 : 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 19, color: iconColor),
              ),
              const SizedBox(width: 14),
              Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                  color: labelColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmDeleteMessage(GroupMessage m) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.lgBorder),
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
    final bg = isDark ? const Color(0xFF0B1220) : const Color(0xFFF4F6FB);

    return Scaffold(
      backgroundColor: bg,
      extendBodyBehindAppBar: true,
      appBar: _buildAppBar(context, isDark, group?.name, group?.logoUrl),
      body: SafeArea(
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: isDark
                  ? const [Color(0xFF0F172A), Color(0xFF0B1220)]
                  : const [Color(0xFFEFF3FB), Color(0xFFF4F6FB)],
            ),
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 960),
              child: Column(
                children: [
                  if (!_c.isRealtimeConnected) _reconnectingStrip(context, isDark),
                  _liveTestBanner(context, isDark),
                  Expanded(
                    child: Stack(
                      children: [
                        _buildMessageArea(context, isDark),
                        if (_showScrollToBottom)
                          Positioned(
                            right: 14,
                            bottom: 14,
                            child: ChatScrollToBottomButton(
                              key: const Key('discussion_scroll_to_bottom'),
                              isDark: isDark,
                              onTap: () => _scrollToBottom(animate: true),
                            ),
                          ),
                      ],
                    ),
                  ),
                  _buildComposer(context, isDark),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(
    BuildContext context,
    bool isDark,
    String? groupName,
    String? logoUrl,
  ) {
    final barColor = isDark
        ? const Color(0xCC0F172A)
        : const Color(0xE6FFFFFF);
    return PreferredSize(
      preferredSize: const Size.fromHeight(kToolbarHeight),
      child: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: AppBar(
            backgroundColor: barColor,
            elevation: 0,
            scrolledUnderElevation: 0,
            titleSpacing: 0,
            surfaceTintColor: Colors.transparent,
            shape: Border(
              bottom: BorderSide(
                color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE5E9F2),
              ),
            ),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_rounded),
              tooltip: 'Back',
              onPressed: () => Navigator.maybePop(context),
            ),
            title: InkWell(
              key: const Key('discussion_open_info'),
              onTap: _openInfo,
              borderRadius: AppRadius.mdBorder,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(2),
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: AppColors.primaryGradient,
                      ),
                      child: GroupAvatar(
                        name: groupName ?? '',
                        logoUrl: logoUrl,
                        radius: 17,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            groupName ?? 'Group Chat',
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
                              letterSpacing: -0.2,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            '${_c.memberCount} ${_c.memberCount == 1 ? 'member' : 'members'}',
                            style: TextStyle(
                              fontSize: 11.5,
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
                key: const Key('group_chat_tests_action'),
                icon: const Icon(Icons.quiz_outlined),
                tooltip: 'Group Tests',
                onPressed: () => context.push('/groups/${_c.groupId}/tests'),
              ),
              PopupMenuButton<String>(
                key: const Key('group_chat_more_menu'),
                icon: const Icon(Icons.more_vert_rounded),
                tooltip: 'More options',
                shape: const RoundedRectangleBorder(borderRadius: AppRadius.lgBorder),
                onSelected: (val) {
                  if (val == 'info') {
                    _openInfo();
                  } else if (val == 'tests') {
                    context.push('/groups/${_c.groupId}/tests');
                  } else if (val == 'mute') {
                    _toggleMuted(context);
                  } else if (val == 'clear') {
                    _clearChatForMe(context);
                  }
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(
                    value: 'info',
                    child: Row(
                      children: [
                        Icon(Icons.info_outline_rounded, size: 18),
                        SizedBox(width: 10),
                        Text('Group info'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'tests',
                    child: Row(
                      children: [
                        Icon(Icons.quiz_outlined, size: 18),
                        SizedBox(width: 10),
                        Text('Group tests'),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'mute',
                    child: Row(
                      children: [
                        Icon(
                          _muted
                              ? Icons.notifications_active_outlined
                              : Icons.notifications_off_outlined,
                          size: 18,
                        ),
                        const SizedBox(width: 10),
                        Text(_muted ? 'Unmute notifications' : 'Mute notifications'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'clear',
                    child: Row(
                      children: [
                        Icon(Icons.cleaning_services_outlined, size: 18),
                        SizedBox(width: 10),
                        Text('Clear chat (this device)'),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 4),
            ],
          ),
        ),
      ),
    );
  }

  Widget _liveTestBanner(BuildContext context, bool isDark) {
    final live = _c.testsInSection(GroupTestSection.live);
    if (live.isEmpty) return const SizedBox.shrink();
    final test = live.first;
    return Container(
      key: Key('discussion_live_test_banner_${test.id}'),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 14),
      color: const Color(0xFFDC2626).withValues(alpha: isDark ? 0.2 : 0.08),
      child: Row(
        children: [
          const ChatPulsingDot(),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'LIVE: ${test.title}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: Color(0xFFDC2626),
              ),
            ),
          ),
          TextButton(
            key: Key('discussion_start_test_${test.id}'),
            onPressed: () => context.push('/tests/${test.id}'),
            child: const Text('Start Now'),
          ),
        ],
      ),
    );
  }

  Widget _reconnectingStrip(BuildContext context, bool isDark) {
    return Container(
      key: const Key('discussion_reconnecting'),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFD97706).withValues(alpha: isDark ? 0.18 : 0.1),
        border: Border(
          bottom: BorderSide(
            color: const Color(0xFFD97706).withValues(alpha: 0.3),
          ),
        ),
      ),
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // A static icon, not a spinner: an indeterminate
          // CircularProgressIndicator animates forever and never lets
          // pumpAndSettle() (used throughout the test suite) settle.
          Icon(Icons.cloud_off_rounded, size: 14, color: Color(0xFFD97706)),
          SizedBox(width: 8),
          Text(
            'Reconnecting live chat…',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Color(0xFFD97706),
            ),
          ),
        ],
      ),
    );
  }

  /// The real window minus anything hidden by a local "Clear chat" — see
  /// [ChatLocalState]. Nothing is deleted; a later clear of the local
  /// cutoff (there is no UI for that today) would bring it all back.
  List<GroupMessage> get _visibleMessages {
    final all = _c.messages;
    final clearedBefore = _clearedBeforeAt;
    if (clearedBefore == null) return all;
    return [
      for (final m in all)
        if (m.createdAt.isAfter(clearedBefore)) m,
    ];
  }

  Widget _buildMessageArea(BuildContext context, bool isDark) {
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
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: AppColors.primaryGradientSoft(alpha: isDark ? 0.18 : 0.1),
                ),
                child: Icon(
                  Icons.forum_rounded,
                  size: 32,
                  color: isDark ? const Color(0xFF93A4F0) : const Color(0xFF5B6CDB),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'No messages yet. Say hello!',
                key: const Key('discussion_empty'),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      );
    }
    if (_visibleMessages.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            'Chat cleared on this device.',
            key: const Key('discussion_cleared_empty'),
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }

    final msgs = _visibleMessages;
    final totalCount = msgs.length + (_c.hasOlderMessages ? 1 : 0);
    final dividerAt = _unreadDividerAt;
    final unreadDividerIndex = dividerAt == null
        ? -1
        : msgs.indexWhere((m) => m.createdAt.isAfter(dividerAt));

    return RefreshIndicator(
      onRefresh: _c.refreshMessages,
      child: ListView.builder(
        key: const Key('discussion_message_list'),
        controller: _scrollController,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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

          // A role-changed notice right after another one (same day) is
          // folded into the first one's pill — nothing of its own to show.
          if (msgIndex > 0 &&
              _isRoleChangedEvent(currentMsg) &&
              _isRoleChangedEvent(msgs[msgIndex - 1]) &&
              _isSameDay(currentMsg.createdAt, msgs[msgIndex - 1].createdAt)) {
            return const SizedBox.shrink();
          }

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

          bool isConsecutive = false;
          if (msgIndex > 0 && !showDateSeparator) {
            final prevMsg = msgs[msgIndex - 1];
            final sameSender = currentMsg.senderId != null &&
                currentMsg.senderId == prevMsg.senderId;
            final closeInTime = currentMsg.createdAt
                    .difference(prevMsg.createdAt)
                    .inMinutes
                    .abs() <
                2;
            if (sameSender &&
                closeInTime &&
                !prevMsg.isSystemEvent &&
                !currentMsg.isSystemEvent) {
              isConsecutive = true;
            }
          }

          final isFirstEverSeen = _animatedOnce.add(currentMsg.id);
          final mergedLines = _isRoleChangedEvent(currentMsg)
              ? _roleChangedRun(msgs, msgIndex)
              : null;

          final bubbleWidget = ChatEntranceFade(
            play: isFirstEverSeen,
            child: _bubble(
              context,
              currentMsg,
              isDark,
              isConsecutive: isConsecutive,
              mergedLines: mergedLines,
            ),
          );

          final leadWidgets = <Widget>[
            if (showDateSeparator) _dateSeparator(context, isDark, currentMsg.createdAt),
            if (msgIndex == unreadDividerIndex) _unreadDivider(isDark),
          ];

          if (leadWidgets.isEmpty) return bubbleWidget;
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [...leadWidgets, bubbleWidget],
          );
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
    if (diff == 0) return 'TODAY';
    if (diff == 1) return 'YESTERDAY';
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${date.day.toString().padLeft(2, '0')} ${months[date.month - 1]} ${date.year}'
        .toUpperCase();
  }

  Widget _unreadDivider(bool isDark) {
    final color = isDark ? const Color(0xFF93A4F0) : const Color(0xFF5B6CDB);
    return Padding(
      key: const Key('discussion_unread_divider'),
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Expanded(child: Divider(color: color.withValues(alpha: 0.4))),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text(
              'NEW MESSAGES',
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
                color: color,
              ),
            ),
          ),
          Expanded(child: Divider(color: color.withValues(alpha: 0.4))),
        ],
      ),
    );
  }

  Widget _dateSeparator(BuildContext context, bool isDark, DateTime date) {
    final label = _formatDatePill(date);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E293B) : Colors.white,
            borderRadius: AppRadius.pillBorder,
            border: Border.all(
              color: isDark ? const Color(0xFF334155) : const Color(0xFFE5E9F2),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
              color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF8A94A6),
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

    // Migration 0108 merged leader/moderator into admin; both legacy
    // strings are still mapped here defensively (same as GroupRole.fromDb).
    switch (role.toLowerCase()) {
      case 'owner':
        label = '👑 Owner';
        bg = isDark ? const Color(0xFF3B2814) : const Color(0xFFFEF3C7);
        text = isDark ? const Color(0xFFFBBF24) : const Color(0xFFB45309);
        break;
      case 'admin':
      case 'leader':
      case 'moderator':
        label = '🛡️ Admin';
        bg = isDark ? const Color(0xFF2E1C40) : const Color(0xFFF3E8FF);
        text = isDark ? const Color(0xFFC084FC) : const Color(0xFF7E22CE);
        break;
      default:
        return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
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

  /// A test-created event ('test' message type, migration 0039), rendered
  /// as a card using the message's own `metadata` (`test_id`, `title`,
  /// `created_by`) — distinct from the small grey system-event pill used
  /// for joins/leaves/role changes.
  Widget _testAnnouncementCard(BuildContext context, GroupMessage m, bool isDark) {
    final testId = m.metadata['test_id'] as String?;
    final title = m.metadata['title'] as String? ?? m.body;
    final creatorLabel = _c.messageSenderLabel(m);
    return Padding(
      key: Key('discussion_message_${m.id}'),
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 20),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: AppColors.primaryGradientSoft(alpha: isDark ? 0.22 : 0.1),
          borderRadius: AppRadius.lgBorder,
          border: Border.all(
            color: isDark ? const Color(0xFF334155) : const Color(0xFFE5E9F2),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.quiz_rounded,
                  size: 16,
                  color: isDark ? const Color(0xFF93A4F0) : const Color(0xFF5B6CDB),
                ),
                const SizedBox(width: 6),
                Text(
                  'New test',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.4,
                    color: isDark ? const Color(0xFF93A4F0) : const Color(0xFF5B6CDB),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5),
            ),
            const SizedBox(height: 2),
            Text(
              'Created by $creatorLabel · ${_formatTime(m.createdAt)}',
              style: TextStyle(
                fontSize: 11.5,
                color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
              ),
            ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.tonal(
                key: Key('discussion_view_test_${m.id}'),
                onPressed: testId == null
                    ? null
                    : () => context.push('/tests/$testId'),
                child: const Text('View'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Role-changed system notices ("X is now admin") that land back-to-back
  /// merge into one pill — e.g. promoting three members in a row no
  /// longer prints three near-identical lines.
  static bool _isRoleChangedEvent(GroupMessage m) =>
      m.isSystemEvent && m.metadata['type'] == 'role_changed';

  /// Consecutive role-changed bodies starting at [startIndex], same day.
  List<String> _roleChangedRun(List<GroupMessage> msgs, int startIndex) {
    final bodies = [msgs[startIndex].body];
    var i = startIndex + 1;
    while (i < msgs.length &&
        _isRoleChangedEvent(msgs[i]) &&
        _isSameDay(msgs[i].createdAt, msgs[startIndex].createdAt)) {
      bodies.add(msgs[i].body);
      i++;
    }
    return bodies;
  }

  Widget _bubble(
    BuildContext context,
    GroupMessage m,
    bool isDark, {
    bool isConsecutive = false,
    List<String>? mergedLines,
  }) {
    final mine = m.senderId != null && m.senderId == _c.currentUserId;
    final label = _c.messageSenderLabel(m);

    if (m.isTestAnnouncement) {
      return _testAnnouncementCard(context, m, isDark);
    }

    if (m.isSystemEvent) {
      final lines = mergedLines ?? [m.body];
      return Padding(
        key: Key('discussion_message_${m.id}'),
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 20),
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E293B) : Colors.white,
              borderRadius: AppRadius.pillBorder,
              border: Border.all(
                color: isDark ? const Color(0xFF334155) : const Color(0xFFE5E9F2),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  size: 13,
                  color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      for (final line in lines)
                        Text(
                          line,
                          style: TextStyle(
                            color: isDark
                                ? const Color(0xFF94A3B8)
                                : const Color(0xFF64748B),
                            fontSize: 11.5,
                            fontWeight: FontWeight.w500,
                          ),
                          textAlign: TextAlign.center,
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final bodyText = m.isDeleted ? 'This message was deleted' : m.body;
    final sender = !mine && !isConsecutive ? _senderOf(m) : null;
    final isSending = mine && _c.isMessageSending(m.id);
    final isFailed = mine && _c.isMessageFailed(m.id);

    return Padding(
      key: Key('discussion_message_${m.id}'),
      padding: EdgeInsets.only(bottom: isConsecutive ? 2 : 10),
      child: Row(
        mainAxisAlignment: mine ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!mine) ...[
            SizedBox(
              width: 30,
              child: !isConsecutive
                  ? GroupAvatar(
                      name: sender?.fullName ?? label,
                      logoUrl: sender?.avatarUrl,
                      radius: 14,
                    )
                  : null,
            ),
            const SizedBox(width: 6),
          ],
          Flexible(
            child: GestureDetector(
              onLongPress: () => _onMessageLongPress(m, mine),
              onTap: isFailed ? () => _c.retryPendingMessage() : null,
              child: Container(
                constraints: const BoxConstraints(maxWidth: 320),
                padding: const EdgeInsets.fromLTRB(14, 9, 14, 7),
                decoration: BoxDecoration(
                  color: mine
                      ? (m.isDeleted
                            ? (isDark ? const Color(0xFF1E293B) : const Color(0xFFE5E9F2))
                            : null)
                      : (isDark ? const Color(0xFF1E293B) : Colors.white),
                  gradient: mine && !m.isDeleted ? AppColors.primaryGradient : null,
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(18),
                    topRight: const Radius.circular(18),
                    bottomLeft: Radius.circular(mine || isConsecutive ? 18 : 4),
                    bottomRight: Radius.circular(mine && !isConsecutive ? 4 : 18),
                  ),
                  border: mine
                      ? null
                      : Border.all(
                          color: isDark
                              ? const Color(0xFF334155)
                              : const Color(0xFFE5E9F2),
                        ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: isDark ? 0.18 : 0.05),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (!mine && !isConsecutive) ...[
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            label,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: isDark
                                  ? const Color(0xFF93A4F0)
                                  : const Color(0xFF5B6CDB),
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
                            Icons.block_rounded,
                            size: 14,
                            color: isDark
                                ? const Color(0xFF94A3B8)
                                : const Color(0xFF64748B),
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              bodyText,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontStyle: FontStyle.italic,
                                fontSize: 14,
                                color: isDark
                                    ? const Color(0xFF94A3B8)
                                    : const Color(0xFF64748B),
                              ),
                            ),
                          ),
                        ],
                      )
                    else
                      Text(
                        bodyText,
                        style: TextStyle(
                          fontSize: 14.5,
                          height: 1.4,
                          color: mine
                              ? Colors.white
                              : (isDark ? const Color(0xFFF8FAFC) : const Color(0xFF1A2233)),
                        ),
                      ),
                    const SizedBox(height: 3),
                    Align(
                      alignment: Alignment.centerRight,
                      child: isSending
                          ? Row(
                              key: Key('discussion_message_sending_${m.id}'),
                              mainAxisSize: MainAxisSize.min,
                              children: const [
                                SizedBox(
                                  width: 9,
                                  height: 9,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 1.5,
                                    color: Color(0xB3FFFFFF),
                                  ),
                                ),
                                SizedBox(width: 5),
                                Text(
                                  'Sending…',
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    color: Color(0xB3FFFFFF),
                                  ),
                                ),
                              ],
                            )
                          : isFailed
                          ? Row(
                              key: Key('discussion_message_failed_${m.id}'),
                              mainAxisSize: MainAxisSize.min,
                              children: const [
                                Icon(
                                  Icons.error_outline_rounded,
                                  size: 12,
                                  color: Color(0xFFFCA5A5),
                                ),
                                SizedBox(width: 4),
                                Text(
                                  'Failed · Tap to retry',
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFFFCA5A5),
                                  ),
                                ),
                              ],
                            )
                          : Text(
                              _formatTime(m.createdAt),
                              style: TextStyle(
                                fontSize: 10.5,
                                color: mine
                                    ? (m.isDeleted
                                          ? (isDark
                                                ? const Color(0xFF94A3B8)
                                                : const Color(0xFF64748B))
                                          : const Color(0xB3FFFFFF))
                                    : (isDark
                                          ? const Color(0xFF64748B)
                                          : const Color(0xFF9AA4B8)),
                              ),
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// A visible placeholder only — real attachments (files/images) land in
  /// Phase 3. Tapping it must never silently claim success.
  void _showAttachmentOptions(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Attachments are coming soon.')),
    );
  }

  Widget _buildComposer(BuildContext context, bool isDark) {
    final locked = (_c.group?.adminOnlyChat ?? false) &&
        !_c.myRole.isOwner &&
        !_c.myRole.isAdmin;
    if (locked) {
      return Container(
        key: const Key('discussion_admin_only_lock'),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF4F6FB),
          border: Border(
            top: BorderSide(
              color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE5E9F2),
            ),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.lock_outline_rounded,
              size: 16,
              color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
            ),
            const SizedBox(width: 8),
            Text(
              'Only admins can send messages right now',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
              ),
            ),
          ],
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF4F6FB),
        border: Border(
          top: BorderSide(
            color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE5E9F2),
          ),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          ChatComposerIconButton(
            icon: Icons.add_rounded,
            isDark: isDark,
            onTap: () => _showAttachmentOptions(context),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Container(
              constraints: const BoxConstraints(minHeight: 44),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E293B) : Colors.white,
                borderRadius: AppRadius.pillBorder,
                border: Border.all(
                  color: isDark ? const Color(0xFF334155) : const Color(0xFFE5E9F2),
                ),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 18),
              alignment: Alignment.center,
              child: TextField(
                key: const Key('discussion_message_field'),
                controller: _input,
                enabled: !_c.sending,
                minLines: 1,
                maxLines: 4,
                maxLength: GroupMessage.maxBodyLength,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _c.sending ? null : _send(),
                style: const TextStyle(fontSize: 14.5),
                decoration: const InputDecoration(
                  hintText: 'Type a message or ask a doubt…',
                  hintStyle: TextStyle(fontSize: 14.5),
                  border: InputBorder.none,
                  isDense: true,
                  counterText: '',
                  contentPadding: EdgeInsets.symmetric(vertical: 11),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          ChatSendButton(
            key: const Key('discussion_send_button'),
            enabled: !_c.sending,
            highlighted: _canSend,
            busy: _c.sending,
            onPressed: _send,
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
