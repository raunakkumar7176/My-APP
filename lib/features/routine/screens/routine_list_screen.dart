import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/theme/app_colors.dart';
import '../../../core/theme/app_colors.dart' as premium;
import '../../../core/theme/app_radius.dart';
import '../../../core/models/routine.dart';
import '../../calendar/domain/calendar_clock.dart';
import '../data/routine_repository.dart';
import '../domain/routine_schedule.dart';
import '../state/routine_controller.dart';
import '../widgets/routine_card.dart';

/// All of the user's routines: today's first, then the rest of the week
/// (upcoming), then paused ones. Reloads whenever any routine changes.
class RoutineListScreen extends StatefulWidget {
  const RoutineListScreen({super.key, this.controller});

  final RoutineController? controller;

  @override
  State<RoutineListScreen> createState() => _RoutineListScreenState();
}

class _RoutineListScreenState extends State<RoutineListScreen> {
  late final RoutineController _controller;
  late final bool _ownsController;
  int _seenRevision = RoutineController.revision.value;

  @override
  void initState() {
    super.initState();
    _ownsController = widget.controller == null;
    _controller = widget.controller ?? RoutineController();
    _controller.loadAll();
    _controller.loadSelectedDate();
    RoutineController.revision.addListener(_onRevision);
  }

  void _onRevision() {
    if (RoutineController.revision.value == _seenRevision) return;
    _seenRevision = RoutineController.revision.value;
    if (mounted) {
      _controller.loadAll();
      _controller.loadSelectedDate();
    }
  }

  @override
  void dispose() {
    RoutineController.revision.removeListener(_onRevision);
    if (_ownsController) _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Routines'),
        actions: [
          IconButton(
            key: const Key('routine_list_history'),
            onPressed: () => context.push('/routine/history'),
            icon: const Icon(Icons.history),
            tooltip: 'History',
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: _controller,
        builder: (context, _) {
          if (_controller.isLoading && _controller.allRoutines.isEmpty) {
            return const Center(
              child: CircularProgressIndicator(key: Key('routine_list_loading')),
            );
          }
          if (_controller.error != null && _controller.allRoutines.isEmpty) {
            return _buildError();
          }
          if (_controller.allRoutines.isEmpty) return _buildEmpty();
          return _buildList();
        },
      ),
      floatingActionButton: FloatingActionButton(
        key: const Key('routine_list_add'),
        onPressed: () => context.push('/routine/create'),
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          key: const Key('routine_list_error'),
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48, color: AppColors.error),
            const SizedBox(height: 12),
            Text(
              _controller.error!,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: AppColors.error),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              key: const Key('routine_list_retry'),
              onPressed: () {
                _controller.loadAll();
                _controller.loadSelectedDate();
              },
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmpty() {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          key: const Key('routine_list_empty'),
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.schedule_outlined,
              size: 64,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 16),
            Text('No routines yet', style: theme.textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text(
              'Plan a study task — subject, chapter, activity and time — and follow it every day.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => context.push('/routine/create'),
              icon: const Icon(Icons.add),
              label: const Text('Create Routine'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildList() {
    final todayWd = _controller.todayWeekday;
    final active = _controller.activeRoutines;
    final today = active.where((r) => r.isScheduledOn(todayWd)).toList();
    final otherDays = active.where((r) => !r.isScheduledOn(todayWd)).toList();
    final paused = _controller.pausedRoutines;
    // The day-view section renders the selected date's items (with
    // completion state) once loaded; while that load is still in flight it
    // falls back to the plain today-only list so nothing appears to vanish.
    final dayItems = _controller.selectedItems;
    final showDayView = dayItems.isNotEmpty || !_controller.isLoadingSelected;

    Widget header(String text, Key key) => Padding(
      padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
      child: Text(
        text,
        key: key,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
          fontWeight: FontWeight.w600,
        ),
      ),
    );

    return RefreshIndicator(
      onRefresh: () => Future.wait([
        _controller.loadAll(),
        _controller.loadSelectedDate(),
      ]),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _weekStrip(),
          const SizedBox(height: 12),
          _dayProgressCard(),
          if (dayItems.isNotEmpty || today.isNotEmpty) ...[
            header(_dayHeaderText(todayWd), const Key('routine_section_today')),
            if (showDayView)
              for (final item in dayItems) _timelineTile(item)
            else
              for (final r in today) _card(r),
          ],
          if (otherDays.isNotEmpty) ...[
            header('Other days', const Key('routine_section_upcoming')),
            for (final r in otherDays) _card(r),
          ],
          if (paused.isNotEmpty) ...[
            header('Paused', const Key('routine_section_paused')),
            for (final r in paused) _card(r),
          ],
        ],
      ),
    );
  }

  String _dayHeaderText(int todayWd) {
    if (_controller.isSelectedToday) {
      return 'Today · ${RoutineSchedule.weekdayShort[todayWd]}';
    }
    final d = _controller.selectedDate;
    final wd = RoutineSchedule.weekdayShort[CalendarDates.liveWeekday(d)];
    return '$wd · ${d.day} ${CalendarDates.monthNames[d.month - 1].substring(0, 3)}';
  }

  /// Monday-first strip of the current live week; tapping a day loads that
  /// date's routine items (real data via [RoutineController.loadSelectedDate],
  /// backed by the existing `getToday(date, weekday)` repository call).
  Widget _weekStrip() {
    final theme = Theme.of(context);
    final today = _controller.clock.today();
    final mondayIndex = (CalendarDates.liveWeekday(today) + 6) % 7;
    final weekStart = CalendarDates.addDays(today, -mondayIndex);
    final selected = _controller.selectedDate;

    return Row(
      key: const Key('routine_week_strip'),
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        for (var i = 0; i < 7; i++)
          Builder(
            builder: (context) {
              final day = CalendarDates.addDays(weekStart, i);
              final isSelected = CalendarDates.sameDay(day, selected);
              final isToday = CalendarDates.sameDay(day, today);
              return InkWell(
                key: Key('routine_week_day_${CalendarDates.iso(day)}'),
                borderRadius: BorderRadius.circular(20),
                onTap: () => _controller.loadSelectedDate(day),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? theme.colorScheme.primary
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Column(
                    children: [
                      Text(
                        RoutineSchedule.weekdayShort[CalendarDates.liveWeekday(day)]
                            .substring(0, 1),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: isSelected
                              ? theme.colorScheme.onPrimary
                              : theme.colorScheme.onSurface.withValues(alpha: 0.6),
                          fontWeight: isToday ? FontWeight.w700 : null,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${day.day}',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: isSelected
                              ? theme.colorScheme.onPrimary
                              : theme.colorScheme.onSurface,
                          fontWeight: isToday || isSelected ? FontWeight.w700 : null,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
      ],
    );
  }

  Widget _dayProgressCard() {
    final theme = Theme.of(context);
    final completed = _controller.selectedCompletedCount;
    final total = _controller.selectedTotalCount;
    final minutes = _controller.selectedLoggedMinutes;
    final current = _controller.currentItem;
    if (total == 0) return const SizedBox.shrink();

    return Container(
      key: const Key('routine_day_progress'),
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: premium.AppColors.primaryGradientSoft(),
        borderRadius: AppRadius.xlBorder,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: _controller.selectedCompletionPercentage,
                    backgroundColor: theme.colorScheme.surfaceContainerHighest,
                    color: AppColors.success,
                    minHeight: 6,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '$completed/$total done',
                style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w500),
              ),
            ],
          ),
          if (minutes > 0) ...[
            const SizedBox(height: 6),
            Text(
              '$minutes min logged today',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
          ],
          if (current != null) ...[
            const SizedBox(height: 10),
            Row(
              key: const Key('routine_current_activity'),
              children: [
                const Icon(Icons.play_circle_fill, size: 18, color: AppColors.primaryLight),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Now: ${current.routine.title}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.primaryLight,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ] else if (_controller.selectedUpNext != null) ...[
            const SizedBox(height: 10),
            Row(
              key: const Key('routine_up_next'),
              children: [
                Icon(Icons.schedule, size: 18, color: theme.colorScheme.onSurface.withValues(alpha: 0.5)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Up next: ${_controller.selectedUpNext!.routine.title} at '
                    '${RoutineSchedule.format12h(_controller.selectedUpNext!.routine.startTime)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _toggleCompletion(RoutineWithLog item) async {
    final routine = item.routine;
    if (item.isCompleted) {
      await _controller.markIncomplete(routine.id);
    } else {
      HapticFeedback.mediumImpact();
      SystemSound.play(SystemSoundType.click);
      await _controller.markComplete(routine.id);
      if (mounted) {
        final pts = _controller.lastRoutinePointsAwarded;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: AppColors.success, size: 18),
                const SizedBox(width: 8),
                Text(
                  pts > 0
                      ? 'Routine completed! +$pts XP'
                      : 'Routine marked as completed!',
                ),
              ],
            ),
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Widget _timelineTile(RoutineWithLog item) {
    final theme = Theme.of(context);
    final routine = item.routine;
    final isCurrent = _controller.currentItem?.routine.id == routine.id;
    final isDone = item.isCompleted;
    final hasActiveAlarm = routine.hasAlarm || routine.reminderEnabled;

    return Card(
      key: Key('routine_card_${routine.id}'),
      margin: const EdgeInsets.only(bottom: 10),
      elevation: isCurrent ? 2 : 0.5,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.xlBorder,
        side: BorderSide(
          color: isCurrent
              ? theme.colorScheme.primary.withValues(alpha: 0.5)
              : theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
          width: isCurrent ? 1.5 : 1,
        ),
      ),
      child: InkWell(
        borderRadius: AppRadius.xlBorder,
        onTap: () => context.push('/routine/${routine.id}'),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Google Tasks Style Circular Checkbox
              InkWell(
                key: Key('routine_checkbox_${routine.id}'),
                onTap: () => _toggleCompletion(item),
                borderRadius: BorderRadius.circular(20),
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isDone ? AppColors.success : Colors.transparent,
                      border: Border.all(
                        color: isDone
                            ? AppColors.success
                            : theme.colorScheme.outline.withValues(alpha: 0.7),
                        width: 2,
                      ),
                    ),
                    child: isDone
                        ? const Icon(
                            Icons.check,
                            size: 14,
                            color: Colors.white,
                          )
                        : null,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Center: Title, Subject/Session tag, Time
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      routine.title.isNotEmpty ? routine.title : 'Study Routine',
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                        decoration: isDone ? TextDecoration.lineThrough : null,
                        color: isDone
                            ? theme.colorScheme.onSurface.withValues(alpha: 0.45)
                            : isCurrent
                                ? theme.colorScheme.primary
                                : null,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Text(
                          '${RoutineSchedule.format12h(routine.startTime)} – ${RoutineSchedule.format12h(routine.endTime)}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontSize: 12,
                            color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                          ),
                        ),
                        if (routine.sessionType != 'study') ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primaryContainer.withValues(alpha: 0.6),
                              borderRadius: AppRadius.smBorder,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  routine.sessionTypeIcon,
                                  size: 11,
                                  color: theme.colorScheme.onPrimaryContainer,
                                ),
                                const SizedBox(width: 3),
                                Text(
                                  routine.sessionTypeLabel,
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    color: theme.colorScheme.onPrimaryContainer,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // Right: Bell indicator and status chip
              if (hasActiveAlarm)
                Tooltip(
                  message: 'Exact Alarm Active',
                  child: Icon(
                    Icons.notifications_active_outlined,
                    size: 16,
                    color: isCurrent
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurface.withValues(alpha: 0.45),
                  ),
                ),
              if (item.isSkipped) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.warning.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'Skipped',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: AppColors.warning,
                      fontWeight: FontWeight.w600,
                      fontSize: 10,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _card(Routine routine) => RoutineCard(
    key: Key('routine_card_${routine.id}'),
    routine: routine,
    onTap: () => context.push('/routine/${routine.id}'),
  );
}
