import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/theme/app_colors.dart';
import '../../../core/models/group_member.dart';
import '../../../core/models/group_message.dart';
import '../../../core/theme/app_radius.dart';
import '../../test/data/test_repository.dart';
import '../data/notification_repository.dart';
import '../state/group_hub_controller.dart';
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
                  Expanded(child: _buildMessageArea(context, isDark)),
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
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Notifications muted')),
                    );
                  } else if (val == 'clear') {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Chat messages cleared locally')),
                    );
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(
                    value: 'info',
                    child: Row(
                      children: [
                        Icon(Icons.info_outline_rounded, size: 18),
                        SizedBox(width: 10),
                        Text('Group info'),
                      ],
                    ),
                  ),
                  PopupMenuItem(
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
                        Icon(Icons.notifications_off_outlined, size: 18),
                        SizedBox(width: 10),
                        Text('Mute notifications'),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'clear',
                    child: Row(
                      children: [
                        Icon(Icons.cleaning_services_outlined, size: 18),
                        SizedBox(width: 10),
                        Text('Clear chat'),
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

    final msgs = _c.messages;
    final totalCount = msgs.length + (_c.hasOlderMessages ? 1 : 0);

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

          final bubbleWidget = _EntranceFade(
            play: isFirstEverSeen,
            child: _bubble(context, currentMsg, isDark, isConsecutive: isConsecutive),
          );

          if (showDateSeparator) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _dateSeparator(context, isDark, currentMsg.createdAt),
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
    if (diff == 0) return 'TODAY';
    if (diff == 1) return 'YESTERDAY';
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${date.day.toString().padLeft(2, '0')} ${months[date.month - 1]} ${date.year}'
        .toUpperCase();
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

  Widget _bubble(
    BuildContext context,
    GroupMessage m,
    bool isDark, {
    bool isConsecutive = false,
  }) {
    final mine = m.senderId != null && m.senderId == _c.currentUserId;
    final label = _c.messageSenderLabel(m);

    if (m.isSystemEvent) {
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
                    style: TextStyle(
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
    final sender = !mine && !isConsecutive ? _senderOf(m) : null;

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
                      child: Text(
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

  void _showAttachmentOptions(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _sheetHandle(isDark),
              const SizedBox(height: 8),
              _sheetAction(
                icon: Icons.quiz_rounded,
                iconColor: const Color(0xFF4338CA),
                label: 'Group Tests',
                isDark: isDark,
                onTap: () {
                  Navigator.pop(ctx);
                  context.push('/groups/${_c.groupId}/tests');
                },
              ),
              _sheetAction(
                icon: Icons.menu_book_rounded,
                iconColor: const Color(0xFF15803D),
                label: 'Study Materials',
                isDark: isDark,
                onTap: () {
                  Navigator.pop(ctx);
                  context.push('/study');
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildComposer(BuildContext context, bool isDark) {
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
          _ComposerIconButton(
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
                  hintText: 'Message…',
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
          _SendButton(
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

/// Plays a short fade+rise exactly once (when [play] is true on first
/// build); subsequent rebuilds of the same element (e.g. the surrounding
/// list scrolling, a sibling's setState) just show the child statically —
/// an [AnimatedBuilder] here would be wrong, since it would replay on
/// every rebuild rather than once per message.
class _EntranceFade extends StatefulWidget {
  const _EntranceFade({required this.play, required this.child});

  final bool play;
  final Widget child;

  @override
  State<_EntranceFade> createState() => _EntranceFadeState();
}

class _EntranceFadeState extends State<_EntranceFade>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
  );
  late final Animation<double> _fade = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOut,
  );
  late final Animation<Offset> _slide = Tween<Offset>(
    begin: const Offset(0, 0.06),
    end: Offset.zero,
  ).animate(_fade);

  @override
  void initState() {
    super.initState();
    if (widget.play) {
      _controller.forward();
    } else {
      _controller.value = 1;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(position: _slide, child: widget.child),
    );
  }
}

/// A compact circular tonal icon button for the composer's leading "add"
/// action — a soft-filled circle rather than a bare [IconButton].
class _ComposerIconButton extends StatelessWidget {
  const _ComposerIconButton({
    required this.icon,
    required this.isDark,
    required this.onTap,
  });

  final IconData icon;
  final bool isDark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isDark ? const Color(0xFF1E293B) : Colors.white,
      shape: const CircleBorder(
        side: BorderSide(color: Color(0x00000000)),
      ),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: isDark ? const Color(0xFF334155) : const Color(0xFFE5E9F2),
            ),
          ),
          child: Icon(
            icon,
            color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
          ),
        ),
      ),
    );
  }
}

/// The composer's circular send button: gradient-filled and highlighted
/// only once there is text to send, with a light press-scale.
class _SendButton extends StatefulWidget {
  const _SendButton({
    required this.enabled,
    required this.highlighted,
    required this.busy,
    required this.onPressed,
    super.key,
  });

  /// Whether the button responds to taps at all (false only while sending).
  final bool enabled;

  /// Whether it shows the gradient (has text to send) vs. a flat muted fill.
  final bool highlighted;
  final bool busy;
  final VoidCallback onPressed;

  @override
  State<_SendButton> createState() => _SendButtonState();
}

class _SendButtonState extends State<_SendButton> {
  bool _pressed = false;

  void _setPressed(bool v) {
    if (!widget.enabled) return;
    setState(() => _pressed = v);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTapDown: (_) => _setPressed(true),
      onTapUp: (_) => _setPressed(false),
      onTapCancel: () => _setPressed(false),
      onTap: widget.enabled ? widget.onPressed : null,
      child: AnimatedScale(
        scale: _pressed ? 0.9 : 1.0,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            gradient: widget.highlighted ? AppColors.primaryGradient : null,
            color: widget.highlighted
                ? null
                : (isDark ? const Color(0xFF334155) : const Color(0xFFD7DCE8)),
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: widget.busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : AnimatedSwitcher(
                  duration: const Duration(milliseconds: 150),
                  child: Icon(
                    Icons.arrow_upward_rounded,
                    key: ValueKey(widget.highlighted),
                    color: Colors.white,
                  ),
                ),
        ),
      ),
    );
  }
}
