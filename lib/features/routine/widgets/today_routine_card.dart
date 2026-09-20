import 'package:flutter/material.dart';

import '../../../core/constants/theme/app_colors.dart';
import '../../../core/errors/app_error.dart';
import '../data/routine_repository.dart';
import '../domain/routine_schedule.dart';
import '../state/routine_controller.dart';

/// Home-screen card: today's routine tasks (user-zone day) with a done/total
/// progress bar, one-tap complete / undo, and an "Up next" banner.
/// Reloads itself whenever any routine or log changes elsewhere in the app.
class TodayRoutineCard extends StatefulWidget {
  const TodayRoutineCard({super.key, this.onViewAll, this.controller});

  final VoidCallback? onViewAll;
  final RoutineController? controller;

  @override
  State<TodayRoutineCard> createState() => _TodayRoutineCardState();
}

class _TodayRoutineCardState extends State<TodayRoutineCard> {
  late final RoutineController _controller;
  late final bool _ownsController;
  int _seenRevision = RoutineController.revision.value;
  String? _busyId;

  @override
  void initState() {
    super.initState();
    _ownsController = widget.controller == null;
    _controller = widget.controller ?? RoutineController();
    _controller.loadToday();
    RoutineController.revision.addListener(_onRevision);
  }

  void _onRevision() {
    if (RoutineController.revision.value == _seenRevision) return;
    _seenRevision = RoutineController.revision.value;
    if (mounted) _controller.loadToday();
  }

  @override
  void dispose() {
    RoutineController.revision.removeListener(_onRevision);
    if (_ownsController) _controller.dispose();
    super.dispose();
  }

  Future<void> _toggle(RoutineWithLog item) async {
    if (_busyId != null) return;
    setState(() => _busyId = item.routine.id);
    try {
      if (item.isCompleted) {
        await _controller.markIncomplete(item.routine.id);
      } else {
        await _controller.markComplete(
          item.routine.id,
          durationMinutes: item.routine.targetDurationMinutes,
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e is AppError ? e.message : 'Could not save. Please try again.'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        final items = _controller.todayItems;
        return Card(
          key: const Key('today_routine_card'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(),
              if (_controller.isLoading && items.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(
                    child: CircularProgressIndicator(key: Key('today_routine_loading')),
                  ),
                )
              else if (_controller.error != null && items.isEmpty)
                _buildError()
              else if (items.isEmpty)
                _buildEmpty()
              else ...[
                _buildProgressBar(),
                _buildRoutineList(),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 8, 0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            "Today's Routine",
            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
          TextButton(
            key: const Key('today_routine_view_all'),
            onPressed: widget.onViewAll,
            child: Text(_controller.todayItems.isEmpty ? 'Plan' : 'View All'),
          ),
        ],
      ),
    );
  }

  Widget _buildError() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        key: const Key('today_routine_error'),
        children: [
          Text(_controller.error!, style: const TextStyle(color: AppColors.error)),
          const SizedBox(height: 8),
          TextButton(
            key: const Key('today_routine_retry'),
            onPressed: _controller.loadToday,
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressBar() {
    final completed = _controller.completedCount;
    final total = _controller.totalCount;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Row(
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: _controller.completionPercentage,
                backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                color: AppColors.success,
                minHeight: 6,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            '$completed/$total',
            key: const Key('today_routine_progress'),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }

  Widget _buildRoutineList() {
    final items = _controller.todayItems;
    final pending = items.where((i) => !i.isCompleted).toList()
      ..sort((a, b) => a.routine.startTime.compareTo(b.routine.startTime));
    final completed = items.where((i) => i.isCompleted).toList();
    final upNext = _controller.upNext;

    return Column(
      children: [
        if (upNext != null && pending.length > 1) _buildUpcomingBanner(upNext),
        ...pending.map(_buildRoutineTile),
        if (completed.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              children: [
                Text(
                  'Completed (${completed.length})',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          ...completed.map(_buildRoutineTile),
        ],
      ],
    );
  }

  Widget _buildUpcomingBanner(RoutineWithLog item) {
    return Container(
      key: const Key('today_routine_up_next'),
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.primaryLight.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const Icon(Icons.play_arrow, size: 18, color: AppColors.primaryLight),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Up next: ${item.routine.title} at ${RoutineSchedule.format12h(item.routine.startTime)}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppColors.primaryLight,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRoutineTile(RoutineWithLog item) {
    final theme = Theme.of(context);
    final routine = item.routine;
    final isCompleted = item.isCompleted;
    final isSkipped = item.isSkipped;
    final busy = _busyId == routine.id;

    return ListTile(
      key: Key('today_routine_${routine.id}'),
      onTap: busy ? null : () => _toggle(item),
      leading: SizedBox(
        width: 32,
        height: 32,
        child: busy
            ? const Padding(padding: EdgeInsets.all(6), child: CircularProgressIndicator(strokeWidth: 2))
            : Container(
                key: Key('today_routine_toggle_${routine.id}'),
                decoration: BoxDecoration(
                  color: isCompleted
                      ? AppColors.success.withValues(alpha: 0.1)
                      : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isCompleted
                        ? AppColors.success
                        : theme.colorScheme.onSurface.withValues(alpha: 0.3),
                    width: 2,
                  ),
                ),
                child: isCompleted
                    ? const Icon(Icons.check, size: 18, color: AppColors.success)
                    : null,
              ),
      ),
      title: Text(
        routine.title,
        style: TextStyle(
          decoration: isCompleted ? TextDecoration.lineThrough : null,
          color: isCompleted ? theme.colorScheme.onSurface.withValues(alpha: 0.5) : null,
        ),
      ),
      subtitle: Text(
        [
          '${RoutineSchedule.format12h(routine.startTime)} – ${RoutineSchedule.format12h(routine.endTime)}',
          if (routine.targetDurationMinutes != null) '${routine.targetDurationMinutes} min',
          if (isSkipped) 'Skipped',
        ].join(' · '),
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
        ),
      ),
      trailing: isCompleted
          ? const Icon(Icons.check_circle, color: AppColors.success, size: 20)
          : Icon(
              isSkipped ? Icons.skip_next : Icons.radio_button_unchecked,
              size: 20,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
            ),
    );
  }

  Widget _buildEmpty() {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: Column(
          key: const Key('today_routine_empty'),
          children: [
            Icon(
              Icons.wb_sunny_outlined,
              size: 32,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 8),
            Text(
              'No routines scheduled for today',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
