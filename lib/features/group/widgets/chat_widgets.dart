import 'package:flutter/material.dart';

import '../../../core/constants/theme/app_colors.dart';

/// Plays a short fade+rise exactly once (when [play] is true on first
/// build); subsequent rebuilds of the same element (e.g. the surrounding
/// list scrolling, a sibling's setState) just show the child statically —
/// an [AnimatedBuilder] here would be wrong, since it would replay on
/// every rebuild rather than once per message.
class ChatEntranceFade extends StatefulWidget {
  const ChatEntranceFade({required this.play, required this.child, super.key});

  final bool play;
  final Widget child;

  @override
  State<ChatEntranceFade> createState() => _ChatEntranceFadeState();
}

class _ChatEntranceFadeState extends State<ChatEntranceFade>
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
class ChatComposerIconButton extends StatelessWidget {
  const ChatComposerIconButton({
    required this.icon,
    required this.isDark,
    required this.onTap,
    super.key,
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

/// A small pulsing red dot for the "LIVE" test banner.
class ChatPulsingDot extends StatefulWidget {
  const ChatPulsingDot({super.key});

  @override
  State<ChatPulsingDot> createState() => _ChatPulsingDotState();
}

class _ChatPulsingDotState extends State<ChatPulsingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(begin: 0.35, end: 1).animate(_controller),
      child: Container(
        width: 8,
        height: 8,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          color: Color(0xFFDC2626),
        ),
      ),
    );
  }
}

/// Floating button shown once the viewer has scrolled away from the
/// latest message, to jump straight back down.
class ChatScrollToBottomButton extends StatelessWidget {
  const ChatScrollToBottomButton({
    required this.isDark,
    required this.onTap,
    super.key,
  });

  final bool isDark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isDark ? const Color(0xFF1E293B) : Colors.white,
      shape: const CircleBorder(),
      elevation: 3,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: isDark ? const Color(0xFF334155) : const Color(0xFFE5E9F2),
            ),
          ),
          child: Icon(
            Icons.keyboard_arrow_down_rounded,
            color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
          ),
        ),
      ),
    );
  }
}

/// The composer's circular send button: gradient-filled and highlighted
/// only once there is text to send, with a light press-scale.
class ChatSendButton extends StatefulWidget {
  const ChatSendButton({
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
  State<ChatSendButton> createState() => _ChatSendButtonState();
}

class _ChatSendButtonState extends State<ChatSendButton> {
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
