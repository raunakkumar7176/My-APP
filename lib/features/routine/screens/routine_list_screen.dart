import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/theme/app_colors.dart';
import '../../../core/models/routine.dart';
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
    RoutineController.revision.addListener(_onRevision);
  }

  void _onRevision() {
    if (RoutineController.revision.value == _seenRevision) return;
    _seenRevision = RoutineController.revision.value;
    if (mounted) _controller.loadAll();
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
              onPressed: _controller.loadAll,
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
      onRefresh: _controller.loadAll,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (today.isNotEmpty) ...[
            header('Today · ${RoutineSchedule.weekdayShort[todayWd]}', const Key('routine_section_today')),
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

  Widget _card(Routine routine) => RoutineCard(
    key: Key('routine_card_${routine.id}'),
    routine: routine,
    onTap: () => context.push('/routine/${routine.id}'),
  );
}
