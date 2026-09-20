import 'package:flutter/material.dart';

import '../../../core/constants/theme/app_colors.dart';
import '../../../core/errors/app_error.dart';
import '../../../core/models/routine.dart';
import '../../../core/models/routine_log.dart';
import '../domain/routine_schedule.dart';
import '../state/routine_controller.dart';

/// Completion history from `routine_logs`, newest day first, grouped by
/// user-zone date with a per-day done/total badge. Paged (30 logs a page);
/// filtered server-side when opened for one routine.
class RoutineHistoryScreen extends StatefulWidget {
  const RoutineHistoryScreen({super.key, this.routineId, this.controller});

  /// If provided, shows history for a specific routine only.
  final String? routineId;
  final RoutineController? controller;

  @override
  State<RoutineHistoryScreen> createState() => _RoutineHistoryScreenState();
}

class _RoutineHistoryScreenState extends State<RoutineHistoryScreen> {
  static const _pageSize = 30;

  late final RoutineController _controller;
  late final bool _ownsController;
  final List<RoutineLog> _logs = [];
  Map<String, Routine> _routinesById = {};
  bool _isLoading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
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
      _logs.clear();
      _hasMore = true;
    });
    try {
      final logs = await _controller.getHistory(
        limit: _pageSize,
        routineId: widget.routineId,
      );
      // Titles come from the routine list (all own routines, paused included,
      // so historical logs of a paused routine still get their name).
      await _controller.loadAll();
      if (!mounted) return;
      setState(() {
        _logs.addAll(logs);
        _hasMore = logs.length == _pageSize;
        _routinesById = {for (final r in _controller.allRoutines) r.id: r};
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e is AppError ? e.message : 'Failed to load history';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    try {
      final logs = await _controller.getHistory(
        limit: _pageSize,
        offset: _logs.length,
        routineId: widget.routineId,
      );
      if (!mounted) return;
      setState(() {
        _logs.addAll(logs);
        _hasMore = logs.length == _pageSize;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e is AppError ? e.message : 'Could not load more')),
        );
      }
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  String _routineTitle(String routineId) =>
      _routinesById[routineId]?.title ?? 'Routine';

  /// Relative label using the user-zone today, not the device day.
  String _formatDate(String iso) {
    final parts = iso.split('-');
    if (parts.length != 3) return iso;
    final d = DateTime.utc(int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]));
    final today = _controller.clock.today();
    final diff = today.difference(d).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    if (diff > 1 && diff < 7) return '$diff days ago';
    return '${d.day}/${d.month}/${d.year}';
  }

  Color _statusColor(String status) => switch (status) {
    'COMPLETED' => AppColors.success,
    'SKIPPED' => AppColors.warning,
    'MISSED' => AppColors.error,
    _ => Colors.grey,
  };

  IconData _statusIcon(String status) => switch (status) {
    'COMPLETED' => Icons.check_circle,
    'SKIPPED' => Icons.skip_next,
    'MISSED' => Icons.cancel,
    _ => Icons.radio_button_unchecked,
  };

  @override
  Widget build(BuildContext context) {
    final title = widget.routineId == null
        ? 'Routine History'
        : _routinesById[widget.routineId]?.title ?? 'Routine History';
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(key: Key('routine_history_loading')));
    }
    if (_error != null) {
      return Center(
        child: Column(
          key: const Key('routine_history_error'),
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48, color: AppColors.error),
            const SizedBox(height: 12),
            Text(_error!, style: const TextStyle(color: AppColors.error)),
            const SizedBox(height: 16),
            ElevatedButton(
              key: const Key('routine_history_retry'),
              onPressed: _load,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }
    if (_logs.isEmpty) return _buildEmpty();
    return RefreshIndicator(onRefresh: _load, child: _buildLogList());
  }

  Widget _buildEmpty() {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          key: const Key('routine_history_empty'),
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.history, size: 64, color: theme.colorScheme.onSurface.withValues(alpha: 0.3)),
            const SizedBox(height: 16),
            Text('No history yet', style: theme.textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text(
              'Complete routines to see your progress here.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLogList() {
    final theme = Theme.of(context);
    final grouped = <String, List<RoutineLog>>{};
    for (final log in _logs) {
      grouped.putIfAbsent(log.logDate, () => []).add(log);
    }
    final dates = grouped.keys.toList()..sort((a, b) => b.compareTo(a));

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: dates.length + (_hasMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == dates.length) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: _loadingMore
                  ? const CircularProgressIndicator()
                  : TextButton(
                      key: const Key('routine_history_more'),
                      onPressed: _loadMore,
                      child: const Text('Load more'),
                    ),
            ),
          );
        }

        final date = dates[index];
        final logs = grouped[date]!;
        final completed = logs.where((l) => l.isCompleted).length;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Text(
                    _formatDate(date),
                    style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.success.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '$completed/${logs.length}',
                      key: Key('routine_history_badge_$date'),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.success,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            ...logs.map(_buildLogTile),
            const SizedBox(height: 8),
          ],
        );
      },
    );
  }

  Widget _buildLogTile(RoutineLog log) {
    final theme = Theme.of(context);
    final status = log.status[0] + log.status.substring(1).toLowerCase();
    final routine = _routinesById[log.routineId];
    return Card(
      key: Key('routine_history_${log.routineId}_${log.logDate}'),
      margin: const EdgeInsets.only(bottom: 4),
      child: ListTile(
        leading: Icon(_statusIcon(log.status), color: _statusColor(log.status), size: 24),
        title: Text(
          _routineTitle(log.routineId),
          style: TextStyle(decoration: log.isCompleted ? TextDecoration.lineThrough : null),
        ),
        subtitle: Text(
          [
            status,
            if (routine != null)
              '${RoutineSchedule.format12h(routine.startTime)} – ${RoutineSchedule.format12h(routine.endTime)}',
          ].join(' · '),
          style: TextStyle(color: _statusColor(log.status)),
        ),
        trailing: log.durationMinutes != null
            ? Text(
                '${log.durationMinutes} min',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                ),
              )
            : null,
      ),
    );
  }
}
