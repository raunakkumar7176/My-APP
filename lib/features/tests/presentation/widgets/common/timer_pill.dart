import 'package:flutter/material.dart';

/// Non-distracting top-centered examination timer with amber pulsing
/// animation when < 5 mins remaining.
class TimerPill extends StatefulWidget {
  const TimerPill({
    required this.remainingSeconds,
    this.totalSeconds,
    this.onTimeExpired,
    this.isPaused = false,
    super.key,
  });

  final int remainingSeconds;
  final int? totalSeconds;
  final VoidCallback? onTimeExpired;
  final bool isPaused;

  @override
  State<TimerPill> createState() => _TimerPillState();
}

class _TimerPillState extends State<TimerPill>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    _pulseAnimation = Tween<double>(begin: 1.0, end: 0.65).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _updatePulsingState();
  }

  @override
  void didUpdateWidget(covariant TimerPill oldWidget) {
    super.didUpdateWidget(oldWidget);
    _updatePulsingState();
    if (widget.remainingSeconds <= 0 && oldWidget.remainingSeconds > 0) {
      widget.onTimeExpired?.call();
    }
  }

  void _updatePulsingState() {
    final isCritical =
        widget.remainingSeconds <= 300 && widget.remainingSeconds > 0;
    if (isCritical && !widget.isPaused) {
      if (!_pulseController.isAnimating) {
        _pulseController.repeat(reverse: true);
      }
    } else {
      if (_pulseController.isAnimating) {
        _pulseController.stop();
        _pulseController.reset();
      }
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  String _formatTime(int totalSecs) {
    if (totalSecs <= 0) return '00:00';
    final hours = totalSecs ~/ 3600;
    final mins = (totalSecs % 3600) ~/ 60;
    final secs = totalSecs % 60;

    final minsStr = mins.toString().padLeft(2, '0');
    final secsStr = secs.toString().padLeft(2, '0');

    if (hours > 0) {
      final hoursStr = hours.toString().padLeft(2, '0');
      return '$hoursStr:$minsStr:$secsStr';
    }
    return '$minsStr:$secsStr';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final isUrgent = widget.remainingSeconds <= 60; // < 1 min: Red
    final isWarning = widget.remainingSeconds <= 300; // < 5 mins: Amber

    final Color accentColor;
    final Color bgColor;
    final Color borderColor;

    if (isUrgent) {
      accentColor = const Color(0xFFEF4444); // Red
      bgColor = isDark
          ? const Color(0xFF450A0A).withValues(alpha: 0.6)
          : const Color(0xFFFEF2F2);
      borderColor = const Color(0xFFFCA5A5);
    } else if (isWarning) {
      accentColor = const Color(0xFFD97706); // Amber
      bgColor = isDark
          ? const Color(0xFF451A03).withValues(alpha: 0.6)
          : const Color(0xFFFFFBEB);
      borderColor = const Color(0xFFFCD34D);
    } else {
      accentColor = isDark ? const Color(0xFFE2E8F0) : const Color(0xFF0F172A);
      bgColor = isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9);
      borderColor = isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1);
    }

    final formattedTime = _formatTime(widget.remainingSeconds);

    return AnimatedBuilder(
      animation: _pulseAnimation,
      builder: (context, child) {
        final opacity = isWarning ? _pulseAnimation.value : 1.0;
        return Opacity(
          opacity: opacity,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: borderColor, width: 1.2),
              boxShadow: isWarning
                  ? [
                      BoxShadow(
                        color: accentColor.withValues(alpha: 0.25),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ]
                  : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isWarning ? Icons.alarm_rounded : Icons.timer_outlined,
                  size: 16,
                  color: accentColor,
                ),
                const SizedBox(width: 6),
                Text(
                  formattedTime,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                    color: accentColor,
                  ),
                ),
                if (widget.isPaused) ...[
                  const SizedBox(width: 4),
                  Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                      color: Color(0xFFF59E0B),
                      shape: BoxShape.circle,
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}
