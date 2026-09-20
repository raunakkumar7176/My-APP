import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/theme/app_colors.dart';
import '../../../core/errors/app_error.dart';
import '../../../core/models/routine.dart';
import '../../../core/models/routine_log.dart';
import '../../../core/models/subject.dart';
import '../../../core/services/subject_service.dart';
import '../domain/routine_schedule.dart';
import '../state/routine_controller.dart';


/// One routine: slot, repeat, study context, today's completion actions,
/// 30-day completion rate, and edit / pause / resume / delete.
class RoutineDetailScreen extends StatefulWidget {
  const RoutineDetailScreen({
    super.key,
    required this.routineId,
    this.controller,
    this.subjectLoader,
  });

  final String routineId;
  final RoutineController? controller;
  final Future<List<Subject>> Function()? subjectLoader;

  @override
  State<RoutineDetailScreen> createState() => _RoutineDetailScreenState();
}

class _RoutineDetailScreenState extends State<RoutineDetailScreen> {
  late final RoutineController _controller;
  late final bool _ownsController;
  Routine? _routine;
  Subject? _subject;
  RoutineLog? _todayLog;
  RoutineStats? _stats;
  bool _isLoading = true;
  bool _notFound = false;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _ownsController = widget.controller == null;
    _controller = widget.controller ?? RoutineController();
    _load();
  }

  @override
  void dispose() {
    if (_ownsController) _controller.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
      _notFound = false;
    });
    try {
      final routine = await _controller.getById(widget.routineId);
      if (!mounted) return;
      if (routine == null) {
        setState(() {
          _notFound = true;
          _isLoading = false;
        });
        return;
      }

      Subject? subject;
      if (routine.subjectId != null) {
        try {
          final loader = widget.subjectLoader ?? SubjectService.loadSubjects;
          final subjects = await loader();
          subject = subjects.where((s) => s.id == routine.subjectId).firstOrNull;
        } catch (_) {
          // Subject name is decorative; the routine still renders.
        }
      }

      RoutineStats? stats;
      RoutineLog? todayLog;
      try {
        stats = await _controller.statsFor(routine);
        final today = await _controller.getHistory(limit: 1, routineId: routine.id);
        todayLog = today.where((l) => l.logDate == _controller.todayDate).firstOrNull;
      } catch (_) {
        // Stats are secondary; keep the routine visible.
      }

      if (mounted) {
        setState(() {
          _routine = routine;
          _subject = subject;
          _stats = stats;
          _todayLog = todayLog;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e is AppError ? e.message : 'Failed to load routine';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _run(Future<void> Function() action, {String? success}) async {
    setState(() => _busy = true);
    try {
      await action();
      if (mounted && success != null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(success)));
      }
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e is AppError ? e.message : 'Something went wrong. Please try again.'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Routine'),
        content: const Text(
          'This removes the routine and its completion history. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            key: const Key('routine_delete_confirm'),
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await _controller.deleteRoutine(widget.routineId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Routine deleted')),
        );
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e is AppError ? e.message : 'Could not delete routine'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  bool get _scheduledToday =>
      _routine != null && _routine!.isActive && _routine!.isScheduledOn(_controller.todayWeekday);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_routine?.title ?? 'Routine'),
        actions: [
          if (_routine != null)
            PopupMenuButton<String>(
              key: const Key('routine_menu'),
              enabled: !_busy,
              onSelected: (value) async {
                switch (value) {
                  case 'edit':
                    final changed = await context.push<bool>('/routine/${widget.routineId}/edit');
                    if (changed == true && mounted) await _load();
                  case 'toggle':
                    final active = _routine!.isActive;
                    await _run(
                      () => active
                          ? _controller.deactivateRoutine(widget.routineId)
                          : _controller.activateRoutine(widget.routineId),
                      success: active ? 'Routine paused' : 'Routine resumed',
                    );
                  case 'delete':
                    await _confirmDelete();
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'edit',
                  child: ListTile(
                    leading: Icon(Icons.edit),
                    title: Text('Edit'),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                PopupMenuItem(
                  key: const Key('routine_menu_toggle'),
                  value: 'toggle',
                  child: ListTile(
                    leading: Icon(_routine!.isActive ? Icons.pause : Icons.play_arrow),
                    title: Text(_routine!.isActive ? 'Pause' : 'Resume'),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                const PopupMenuItem(
                  key: Key('routine_menu_delete'),
                  value: 'delete',
                  child: ListTile(
                    leading: Icon(Icons.delete, color: AppColors.error),
                    title: Text('Delete', style: TextStyle(color: AppColors.error)),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ],
            ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(key: Key('routine_detail_loading')));
    }
    if (_error != null) {
      return Center(
        child: Column(
          key: const Key('routine_detail_error'),
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48, color: AppColors.error),
            const SizedBox(height: 12),
            Text(_error!, style: const TextStyle(color: AppColors.error)),
            const SizedBox(height: 16),
            ElevatedButton(
              key: const Key('routine_detail_retry'),
              onPressed: _load,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }
    if (_notFound || _routine == null) {
      return const Center(
        child: Text('Routine not found', key: Key('routine_detail_not_found')),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildTimeCard(),
          const SizedBox(height: 16),
          if (_scheduledToday) ...[_buildTodayCard(), const SizedBox(height: 16)],
          _buildScheduleCard(),
          const SizedBox(height: 16),
          _buildDetailsCard(),
          const SizedBox(height: 16),
          _buildProgressCard(),
        ],
      ),
    );
  }

  Widget _buildTimeCard() {
    final theme = Theme.of(context);
    Widget col(String time, String label) => Column(
      children: [
        Text(
          RoutineSchedule.format12h(time),
          style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
          ),
        ),
      ],
    );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            col(_routine!.startTime, 'Start'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Icon(
                Icons.arrow_forward,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
              ),
            ),
            col(_routine!.endTime, 'End'),
          ],
        ),
      ),
    );
  }

  Widget _buildTodayCard() {
    final theme = Theme.of(context);
    final done = _todayLog?.isCompleted ?? false;
    final skipped = _todayLog?.isSkipped ?? false;
    final status = done ? 'Completed today' : skipped ? 'Skipped today' : 'Not done yet today';
    final color = done ? AppColors.success : skipped ? AppColors.warning : theme.colorScheme.primary;
    return Card(
      key: const Key('routine_today_card'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  done ? Icons.check_circle : skipped ? Icons.skip_next : Icons.radio_button_unchecked,
                  color: color,
                ),
                const SizedBox(width: 8),
                Text(status, key: const Key('routine_today_status'), style: theme.textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                if (!done)
                  FilledButton.icon(
                    key: const Key('routine_mark_complete'),
                    onPressed: _busy
                        ? null
                        : () => _run(
                            () => _controller.markComplete(
                              _routine!.id,
                              durationMinutes: _routine!.targetDurationMinutes,
                            ),
                            success: 'Marked complete',
                          ),
                    icon: const Icon(Icons.check),
                    label: const Text('Mark complete'),
                  )
                else
                  OutlinedButton.icon(
                    key: const Key('routine_mark_incomplete'),
                    onPressed: _busy
                        ? null
                        : () => _run(
                            () => _controller.markIncomplete(_routine!.id),
                            success: 'Marked not done',
                          ),
                    icon: const Icon(Icons.undo),
                    label: const Text('Undo'),
                  ),
                const SizedBox(width: 8),
                if (!done && !skipped)
                  TextButton(
                    key: const Key('routine_skip_today'),
                    onPressed: _busy ? null : () => _run(() => _controller.skipRoutine(_routine!.id)),
                    child: const Text('Skip today'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildScheduleCard() {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Schedule', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(Icons.calendar_today, size: 20),
                const SizedBox(width: 12),
                Text(RoutineSchedule.weekdaysLabel(_routine!.weekdays)),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.access_time, size: 20),
                const SizedBox(width: 12),
                Text('${_routine!.computedDurationMinutes ?? 0} min slot'),
              ],
            ),
            if (_routine!.targetDurationMinutes != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.timer_outlined, size: 20),
                  const SizedBox(width: 12),
                  Text('${_routine!.targetDurationMinutes} min target'),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDetailsCard() {
    final theme = Theme.of(context);
    final parsed = RoutineSchedule.parseTitle(_routine!.title);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Study', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            if (_subject != null) _row(Icons.book_outlined, 'Subject', _subject!.name),
            if (parsed.activity != null) _row(Icons.school_outlined, 'Activity', parsed.activity!),
            _row(
              Icons.notifications_outlined,
              'Reminder',
              _routine!.reminderEnabled ? 'Enabled' : 'Disabled',
            ),
            _row(
              Icons.circle,
              'Status',
              _routine!.isActive ? 'Active' : 'Paused',
              valueColor: _routine!.isActive ? AppColors.success : AppColors.warning,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProgressCard() {
    final theme = Theme.of(context);
    final s = _stats;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Last 30 days',
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
                TextButton(
                  key: const Key('routine_view_history'),
                  onPressed: () => context.push('/routine/history?routine=${widget.routineId}'),
                  child: const Text('History'),
                ),
              ],
            ),
            if (s == null)
              Text(
                'Progress unavailable right now.',
                style: theme.textTheme.bodySmall,
              )
            else ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: s.completionRate,
                  minHeight: 8,
                  color: AppColors.success,
                  backgroundColor: theme.colorScheme.surfaceContainerHighest,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '${(s.completionRate * 100).round()}% · ${s.completedDays} of ${s.scheduledDays} '
                'scheduled days completed'
                '${s.loggedMinutes > 0 ? ' · ${s.loggedMinutes} min logged' : ''}',
                key: const Key('routine_stats_text'),
                style: theme.textTheme.bodyMedium,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _row(IconData icon, String label, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon, size: 20),
          const SizedBox(width: 12),
          Text(label),
          const Spacer(),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: TextStyle(fontWeight: FontWeight.w500, color: valueColor),
            ),
          ),
        ],
      ),
    );
  }
}
