import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/constants/theme/app_colors.dart';

class CountdownTimer extends StatefulWidget {
  const CountdownTimer({
    required this.deadlineAt,
    required this.onTimeUp,
    super.key,
  });

  final DateTime deadlineAt;
  final VoidCallback onTimeUp;

  @override
  State<CountdownTimer> createState() => _CountdownTimerState();

  @visibleForTesting
  static Duration remainingAt(DateTime deadline) {
    final remaining = deadline.difference(DateTime.now());
    return remaining.isNegative ? Duration.zero : remaining;
  }
}

class _CountdownTimerState extends State<CountdownTimer> {
  Timer? _timer;
  Duration _remaining = Duration.zero;

  @override
  void initState() {
    super.initState();
    _remaining = CountdownTimer.remainingAt(widget.deadlineAt);
    _startTimer();
  }

  @override
  void didUpdateWidget(CountdownTimer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.deadlineAt != widget.deadlineAt) {
      _timer?.cancel();
      _remaining = CountdownTimer.remainingAt(widget.deadlineAt);
      _startTimer();
    }
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final remaining = CountdownTimer.remainingAt(widget.deadlineAt);
      setState(() => _remaining = remaining);
      if (remaining <= Duration.zero) {
        _timer?.cancel();
        widget.onTimeUp();
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String _format(Duration d) {
    final hours = d.inHours;
    final minutes = d.inMinutes.remainder(60);
    final seconds = d.inSeconds.remainder(60);
    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:'
          '${minutes.toString().padLeft(2, '0')}:'
          '${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:'
        '${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Urgent tint when time remaining is less than 2 minutes (120 seconds)
    final isUrgent = _remaining.inSeconds <= 120 && _remaining > Duration.zero;
    final fgColor = isUrgent ? AppColors.error : theme.colorScheme.onSurface;
    final bgColor = isUrgent
        ? AppColors.error.withValues(alpha: 0.12)
        : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.65);
    final borderColor = isUrgent
        ? AppColors.error.withValues(alpha: 0.35)
        : theme.colorScheme.outlineVariant.withValues(alpha: 0.5);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isUrgent ? Icons.timer_outlined : Icons.access_time_rounded,
            size: 16,
            color: fgColor,
          ),
          const SizedBox(width: 6),
          Text(
            _format(_remaining),
            style: theme.textTheme.titleSmall?.copyWith(
              color: fgColor,
              fontWeight: FontWeight.w700,
              fontFeatures: const [FontFeature.tabularFigures()],
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}
