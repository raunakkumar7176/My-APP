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

  Color _color() {
    if (_remaining.inSeconds <= 60) return AppColors.error;
    if (_remaining.inSeconds <= 300) return AppColors.warning;
    return AppColors.textPrimaryLight;
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.timer_outlined, size: 18, color: _color()),
        const SizedBox(width: 4),
        Text(
          _format(_remaining),
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: _color(),
            fontWeight: FontWeight.w600,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}
