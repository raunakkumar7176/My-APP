import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../routine/data/routine_repository.dart';
import '../../routine/state/routine_controller.dart';

/// Compact "Today's Target" summary: planned vs. completed study minutes,
/// derived from the same [RoutineController] data [TodayRoutineCard] shows
/// as a list — this is a second, denser view of the identical routine data,
/// not a new data source.
class TodayProgressCard extends StatefulWidget {
  const TodayProgressCard({super.key, this.controller});

  final RoutineController? controller;

  @override
  State<TodayProgressCard> createState() => _TodayProgressCardState();
}

class _TodayProgressCardState extends State<TodayProgressCard> {
  late final RoutineController _controller;
  late final bool _ownsController;
  int _seenRevision = RoutineController.revision.value;

  @override
  void initState() {
    super.initState();
    _ownsController = widget.controller == null;
    _controller = widget.controller ?? RoutineController();
    _controller.addListener(_onChanged);
    _controller.loadToday();
    RoutineController.revision.addListener(_onRevision);
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  void _onRevision() {
    if (RoutineController.revision.value == _seenRevision) return;
    _seenRevision = RoutineController.revision.value;
    if (mounted) _controller.loadToday();
  }

  @override
  void dispose() {
    RoutineController.revision.removeListener(_onRevision);
    _controller.removeListener(_onChanged);
    if (_ownsController) _controller.dispose();
    super.dispose();
  }

  static int _plannedMinutes(RoutineWithLog item) =>
      item.routine.targetDurationMinutes ?? item.routine.computedDurationMinutes ?? 0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final items = _controller.todayItems;

    if (_controller.isLoading && items.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    if (_controller.error != null && items.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(Icons.error_outline, color: theme.colorScheme.error),
              const SizedBox(width: 12),
              Expanded(child: Text(_controller.error!)),
              TextButton(onPressed: _controller.loadToday, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }

    if (items.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Icon(
                Icons.wb_sunny_outlined,
                size: 32,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
              ),
              const SizedBox(height: 8),
              Text('Start your study plan', style: theme.textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(
                'Build a daily routine to track today\'s target.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () => context.push('/routine/create'),
                child: const Text('Build Routine'),
              ),
            ],
          ),
        ),
      );
    }

    final planned = items.fold<int>(0, (sum, i) => sum + _plannedMinutes(i));
    final completed = items
        .where((i) => i.isCompleted)
        .fold<int>(0, (sum, i) => sum + (i.log?.durationMinutes ?? _plannedMinutes(i)));
    final remaining = (planned - completed).clamp(0, planned);
    final pct = planned > 0 ? (completed / planned).clamp(0.0, 1.0) : 0.0;
    final doneCount = items.where((i) => i.isCompleted).length;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(Icons.timer_outlined, color: theme.colorScheme.primary, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      "Today's Target",
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
                if (planned > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '${(pct * 100).round()}% Done',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  _fmt(completed),
                  style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
                Text(
                  ' / ${_fmt(planned)} planned',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
                const Spacer(),
                Text(
                  remaining > 0 ? '${_fmt(remaining)} left' : 'All done',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.tertiary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: pct,
                minHeight: 8,
                backgroundColor: theme.colorScheme.surfaceContainerHighest,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Focus: $doneCount of ${items.length} sessions completed',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _fmt(int minutes) {
    if (minutes <= 0) return '0m';
    final h = minutes ~/ 60;
    final m = minutes % 60;
    if (h == 0) return '${m}m';
    if (m == 0) return '${h}h';
    return '${h}h ${m}m';
  }
}
