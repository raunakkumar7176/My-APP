import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/constants/theme/app_colors.dart';
import '../../../core/errors/app_error.dart';
import '../../../core/widgets/xp_celebration_overlay.dart';
import '../../../l10n/app_localizations.dart';
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
  Timer? _tickerTimer;

  @override
  void initState() {
    super.initState();
    _ownsController = widget.controller == null;
    _controller = widget.controller ?? RoutineController();
    _controller.loadToday();
    RoutineController.revision.addListener(_onRevision);
    // Dynamic periodic ticker to keep time-of-day progress bars and countdowns live.
    _tickerTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted) setState(() {});
    });
  }

  void _onRevision() {
    if (RoutineController.revision.value == _seenRevision) return;
    _seenRevision = RoutineController.revision.value;
    if (mounted) _controller.loadToday();
  }

  @override
  void dispose() {
    _tickerTimer?.cancel();
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
        if (mounted) {
          XpCelebrationOverlay.show(
            context,
            points: _controller.lastRoutinePointsAwarded,
            label: 'Routine complete!',
          );
        }
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
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 8, 0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            l10n?.dashboardTodayRoutine ?? "Today's Routine",
            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
          TextButton(
            key: const Key('today_routine_view_all'),
            onPressed: widget.onViewAll,
            child: Text(_controller.todayItems.isEmpty ? 'Plan' : (l10n?.dashboardViewAll ?? 'View all')),
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
    final pct = _controller.completionPercentage;
    final ongoing = _controller.currentTodayItem;
    final now = _controller.nowInUserZone;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: pct,
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
                style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
              ),
            ],
          ),
          if (ongoing != null) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: const BoxDecoration(
                    color: AppColors.success,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Active now: ${ongoing.routine.title} · ${ongoing.routine.remainingMinutesAt(now)}m left',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
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
    final now = _controller.nowInUserZone;

    return Column(
      children: [
        if (upNext != null && pending.length > 1) _buildUpcomingBanner(upNext),
        ...pending.map((i) => _buildRoutineTile(i, now)),
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
          ...completed.map((i) => _buildRoutineTile(i, now)),
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

  Widget _buildRoutineTile(RoutineWithLog item, DateTime nowInUserZone) {
    final theme = Theme.of(context);
    final routine = item.routine;
    final isCompleted = item.isCompleted;
    final isSkipped = item.isSkipped;
    final isOngoing = item.isOngoingAt(nowInUserZone);
    final isMissed = item.isMissedAt(nowInUserZone);
    final progress = item.progressAt(nowInUserZone);
    final remainingMins = routine.remainingMinutesAt(nowInUserZone);
    final startMins = routine.minutesUntilStart(nowInUserZone);
    final endedMins = routine.minutesSinceEnded(nowInUserZone);
    final busy = _busyId == routine.id;

    // Accent colors based on live academic state
    final Color accentColor = isCompleted
        ? AppColors.success
        : isOngoing
            ? theme.colorScheme.primary
            : isMissed
                ? const Color(0xFFE59A2F) // Amber / Warning
                : theme.colorScheme.onSurface.withValues(alpha: 0.35);

    final Color cardBorderColor = isOngoing
        ? theme.colorScheme.primary.withValues(alpha: 0.4)
        : isMissed
            ? const Color(0xFFE59A2F).withValues(alpha: 0.35)
            : theme.colorScheme.outlineVariant.withValues(alpha: 0.35);

    final Color cardBgColor = isOngoing
        ? theme.colorScheme.primary.withValues(alpha: 0.04)
        : isMissed
            ? const Color(0xFFE59A2F).withValues(alpha: 0.03)
            : Colors.transparent;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Material(
        key: Key('today_routine_${routine.id}'),
        color: cardBgColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: cardBorderColor, width: isOngoing ? 1.5 : 1.0),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: busy ? null : () => _toggle(item),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Action toggle circle
                    SizedBox(
                      width: 28,
                      height: 28,
                      child: busy
                          ? const Padding(
                              padding: EdgeInsets.all(4),
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Container(
                              key: Key('today_routine_toggle_${routine.id}'),
                              decoration: BoxDecoration(
                                color: isCompleted
                                    ? AppColors.success.withValues(alpha: 0.12)
                                    : isOngoing
                                        ? theme.colorScheme.primary.withValues(alpha: 0.1)
                                        : isMissed
                                            ? const Color(0xFFE59A2F).withValues(alpha: 0.12)
                                            : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: accentColor,
                                  width: 2,
                                ),
                              ),
                              child: isCompleted
                                  ? const Icon(Icons.check, size: 16, color: AppColors.success)
                                  : isOngoing
                                      ? Icon(Icons.play_arrow_rounded, size: 16, color: theme.colorScheme.primary)
                                      : isMissed
                                          ? const Icon(Icons.priority_high_rounded, size: 14, color: Color(0xFFE59A2F))
                                          : null,
                            ),
                    ),
                    const SizedBox(width: 10),
                    // Title and time window
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  routine.title,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                    decoration: isCompleted ? TextDecoration.lineThrough : null,
                                    color: isCompleted
                                        ? theme.colorScheme.onSurface.withValues(alpha: 0.5)
                                        : isMissed
                                            ? const Color(0xFFB45309)
                                            : null,
                                  ),
                                ),
                              ),
                              // Live state badge
                              if (isCompleted)
                                _statusBadge(
                                  label: 'Completed',
                                  bgColor: AppColors.success.withValues(alpha: 0.12),
                                  textColor: AppColors.success,
                                )
                              else if (isOngoing)
                                _statusBadge(
                                  label: remainingMins > 0 ? '$remainingMins min left' : 'Ending now',
                                  bgColor: theme.colorScheme.primary.withValues(alpha: 0.12),
                                  textColor: theme.colorScheme.primary,
                                  isLive: true,
                                )
                              else if (isMissed)
                                _statusBadge(
                                  label: endedMins > 0 ? 'Ended ${_formatDuration(endedMins)} ago' : 'Slot Ended',
                                  bgColor: const Color(0xFFE59A2F).withValues(alpha: 0.12),
                                  textColor: const Color(0xFFB45309),
                                )
                              else
                                _statusBadge(
                                  label: startMins > 0 ? 'Starts in ${_formatDuration(startMins)}' : 'Upcoming',
                                  bgColor: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                                  textColor: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                                ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            [
                              '${RoutineSchedule.format12h(routine.startTime)} – ${RoutineSchedule.format12h(routine.endTime)}',
                              if (routine.targetDurationMinutes != null) '${routine.targetDurationMinutes} min',
                              if (isSkipped) 'Skipped',
                              if (isMissed) 'Missed',
                            ].join(' · '),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: isMissed
                                  ? const Color(0xFFB45309)
                                  : theme.colorScheme.onSurface.withValues(alpha: 0.55),
                              fontWeight: isMissed ? FontWeight.w500 : null,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // ── Timely Progress Bar ──
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: isCompleted
                        ? 1.0
                        : (isMissed
                            ? 1.0
                            : (isOngoing ? progress : 0.0)),
                    minHeight: 5,
                    backgroundColor: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                    valueColor: AlwaysStoppedAnimation<Color>(
                      isCompleted
                          ? AppColors.success
                          : (isOngoing
                              ? theme.colorScheme.primary
                              : (isMissed
                                  ? const Color(0xFFE59A2F)
                                  : theme.colorScheme.outlineVariant)),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                // Timely progress label row
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      isCompleted
                          ? '100% completed'
                          : isOngoing
                              ? '${(progress * 100).round()}% time elapsed'
                              : isMissed
                                  ? '100% time elapsed · Concluded'
                                  : '0% elapsed',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: isCompleted
                            ? AppColors.success
                            : isOngoing
                                ? theme.colorScheme.primary
                                : isMissed
                                    ? const Color(0xFFB45309)
                                    : theme.colorScheme.onSurface.withValues(alpha: 0.45),
                        fontWeight: isOngoing || isMissed ? FontWeight.w600 : FontWeight.w400,
                        fontSize: 10.5,
                      ),
                    ),
                    Text(
                      isCompleted
                          ? 'Earned XP'
                          : isOngoing
                              ? '${remainingMins}m remaining'
                              : isMissed
                                  ? 'Tap to mark done & earn XP'
                                  : 'Starts at ${RoutineSchedule.format12h(routine.startTime)}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: isOngoing
                            ? theme.colorScheme.primary
                            : isMissed
                                ? const Color(0xFFB45309)
                                : theme.colorScheme.onSurface.withValues(alpha: 0.5),
                        fontWeight: isOngoing || isMissed ? FontWeight.w600 : FontWeight.w400,
                        fontSize: 10.5,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _statusBadge({
    required String label,
    required Color bgColor,
    required Color textColor,
    bool isLive = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isLive) ...[
            Container(
              width: 5,
              height: 5,
              margin: const EdgeInsets.only(right: 5),
              decoration: BoxDecoration(
                color: textColor,
                shape: BoxShape.circle,
              ),
            ),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              color: textColor,
            ),
          ),
        ],
      ),
    );
  }

  String _formatDuration(int minutes) {
    if (minutes < 60) return '${minutes}m';
    final h = minutes ~/ 60;
    final m = minutes % 60;
    return m == 0 ? '${h}h' : '${h}h ${m}m';
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
