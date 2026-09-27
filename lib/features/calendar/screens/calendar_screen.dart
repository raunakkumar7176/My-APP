import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/theme/app_colors.dart';
import '../../../core/models/academic_special_day.dart';
import '../domain/calendar_clock.dart';
import '../domain/calendar_event.dart';
import '../state/calendar_controller.dart';
import '../widgets/special_day_bottom_sheet.dart';

/// Calendar V1 — month grid (Monday first) with event markers, previous /
/// next / today, and the selected day's agenda built from routines and tests.
/// Read-only; every mutation lives in its own feature (routine, test).
class CalendarScreen extends StatefulWidget {
  const CalendarScreen({this.controller, super.key});

  final CalendarController? controller;

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  late final CalendarController _c;
  late final bool _owns;

  @override
  void initState() {
    super.initState();
    _owns = widget.controller == null;
    _c = widget.controller ?? CalendarController();
    _c.addListener(_onChanged);
    _c.load();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _c.removeListener(_onChanged);
    if (_owns) _c.dispose();
    super.dispose();
  }

  void _openEvent(CalendarEvent e) {
    if (GoRouter.maybeOf(context) == null) return;
    if (e.kind == CalendarEventKind.test && e.testId != null) {
      context.push('/tests/${e.testId}');
    }
    // Routine entries are informational in V1 (the Routine feature owns editing).
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Calendar'),
        actions: [
          TextButton(
            key: const Key('calendar_today'),
            onPressed: _c.goToToday,
            child: const Text('Today'),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _c.refresh,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
          children: [
            _monthHeader(theme),
            const SizedBox(height: 8),
            _weekdayRow(theme),
            _grid(theme),
            if (_c.clock.usesDeviceFallback)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Times shown in device time (zone "${_c.clock.timezoneName}" is not supported offline).',
                  key: const Key('calendar_tz_note'),
                  style: theme.textTheme.bodySmall,
                ),
              ),
            const SizedBox(height: 16),
            _filterChips(theme),
            const SizedBox(height: 12),
            _agendaHeader(theme),
            const SizedBox(height: 8),
            if (_c.selectedDaySpecialDay != null) ...[
              _specialDayBanner(theme, _c.selectedDaySpecialDay!),
              const SizedBox(height: 8),
            ],
            ..._agenda(theme),
          ],
        ),
      ),
    );
  }

  Widget _monthHeader(ThemeData theme) => Row(
    children: [
      IconButton(
        key: const Key('calendar_prev'),
        tooltip: 'Previous month',
        icon: const Icon(Icons.chevron_left),
        onPressed: _c.previousMonth,
      ),
      Expanded(
        child: Text(
          _c.monthTitle,
          key: const Key('calendar_month_title'),
          textAlign: TextAlign.center,
          style: theme.textTheme.titleLarge,
        ),
      ),
      IconButton(
        key: const Key('calendar_next'),
        tooltip: 'Next month',
        icon: const Icon(Icons.chevron_right),
        onPressed: _c.nextMonth,
      ),
    ],
  );

  Widget _weekdayRow(ThemeData theme) => Row(
    children: [
      for (final d in const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'])
        Expanded(
          child: Center(
            child: Text(d, style: theme.textTheme.labelSmall),
          ),
        ),
    ],
  );

  Widget _grid(ThemeData theme) {
    final days = _c.grid;
    final today = _c.today;
    return Column(
      children: [
        for (var row = 0; row < 6; row++)
          Row(
            children: [
              for (var col = 0; col < 7; col++) Expanded(child: _dayCell(theme, days[row * 7 + col], today)),
            ],
          ),
      ],
    );
  }

  Widget _dayCell(ThemeData theme, DateTime day, DateTime today) {
    final inMonth = _c.isInVisibleMonth(day);
    final selected = CalendarDates.sameDay(day, _c.selectedDay);
    final isToday = CalendarDates.sameDay(day, today);
    final events = _c.eventsOn(day);
    final hasRoutine = events.any((e) => e.kind == CalendarEventKind.routine);
    final hasTest = events.any((e) => e.kind == CalendarEventKind.test);
    final hasSpecialDay = events.any((e) => e.kind == CalendarEventKind.specialDay);
    final allDone = events.isNotEmpty && events.every((e) => e.isDone);
    return InkWell(
      key: Key('calendar_day_${CalendarDates.iso(day)}'),
      onTap: () => _c.selectDay(day),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        height: 46,
        margin: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: selected ? theme.colorScheme.primaryContainer : null,
          border: isToday ? Border.all(color: theme.colorScheme.primary, width: 1.5) : null,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '${day.day}',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: inMonth ? null : theme.colorScheme.outline,
                fontWeight: isToday ? FontWeight.w700 : null,
              ),
            ),
            const SizedBox(height: 2),
            SizedBox(
              height: 8,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (hasRoutine)
                    _dot(allDone ? AppColors.success : theme.colorScheme.primary, key: 'routine_dot_${CalendarDates.iso(day)}'),
                  if (hasTest) _dot(theme.colorScheme.tertiary, key: 'test_dot_${CalendarDates.iso(day)}'),
                  if (hasSpecialDay)
                    Icon(
                      Icons.star_rounded,
                      key: Key('special_day_dot_${CalendarDates.iso(day)}'),
                      size: 8,
                      color: const Color(0xFFD97706),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dot(Color color, {required String key}) => Container(
    key: Key(key),
    width: 6,
    height: 6,
    margin: const EdgeInsets.symmetric(horizontal: 1),
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );

  Widget _filterChips(ThemeData theme) {
    final options = <(String, CalendarEventKind?)>[
      ('All', null),
      ('Study', CalendarEventKind.routine),
      ('Tests', CalendarEventKind.test),
      ('GK Days & Events', CalendarEventKind.specialDay),
    ];
    return SizedBox(
      height: 34,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (final (label, kind) in options)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                key: Key('calendar_filter_${kind?.name ?? 'all'}'),
                label: Text(label),
                selected: _c.kindFilter == kind,
                onSelected: (_) => _c.setKindFilter(kind),
              ),
            ),
        ],
      ),
    );
  }

  Widget _specialDayBanner(ThemeData theme, AcademicSpecialDay specialDay) {
    return InkWell(
      key: const Key('calendar_special_day_banner'),
      onTap: () => SpecialDayBottomSheet.show(context, specialDay),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFD97706).withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFD97706).withValues(alpha: 0.4)),
        ),
        child: Row(
          children: [
            const Text('🎗️', style: TextStyle(fontSize: 18)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '${_c.selectedDay.day} ${CalendarDates.monthNames[_c.selectedDay.month - 1]} — ${specialDay.title}',
                style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
            const Icon(Icons.chevron_right, size: 18),
          ],
        ),
      ),
    );
  }

  Widget _agendaHeader(ThemeData theme) {
    final d = _c.selectedDay;
    final label = CalendarDates.sameDay(d, _c.today)
        ? 'Today · ${d.day} ${CalendarDates.monthNames[d.month - 1]}'
        : '${d.day} ${CalendarDates.monthNames[d.month - 1]} ${d.year}';
    return Text(label, key: const Key('calendar_agenda_title'), style: theme.textTheme.titleMedium);
  }

  List<Widget> _agenda(ThemeData theme) {
    if (_c.error != null) {
      return [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Column(
            key: const Key('calendar_error'),
            children: [
              Text(_c.error!, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.error)),
              const SizedBox(height: 8),
              FilledButton(key: const Key('calendar_retry'), onPressed: _c.load, child: const Text('Retry')),
            ],
          ),
        ),
      ];
    }
    if (_c.isLoading && !_c.hasLoaded) {
      return const [
        Padding(
          padding: EdgeInsets.symmetric(vertical: 32),
          child: Center(child: CircularProgressIndicator(key: Key('calendar_loading'))),
        ),
      ];
    }
    // Special days are shown via the sticky banner above, not duplicated as
    // a list tile — unless the user explicitly filtered to "GK Days & Events".
    final items = _c.kindFilter == CalendarEventKind.specialDay
        ? _c.selectedDayEvents
        : _c.selectedDayEvents.where((e) => e.kind != CalendarEventKind.specialDay).toList();
    if (items.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 32),
          child: Column(
            key: const Key('calendar_empty_day'),
            children: [
              Icon(Icons.event_available_outlined, size: 40, color: theme.colorScheme.outline),
              const SizedBox(height: 8),
              const Text('Nothing planned for this day.'),
            ],
          ),
        ),
      ];
    }
    return [for (final e in items) _eventTile(theme, e)];
  }

  Widget _eventTile(ThemeData theme, CalendarEvent e) {
    final (icon, chip, chipColor) = switch (e.state) {
      CalendarEventState.completed => (Icons.check_circle, 'Completed', AppColors.success),
      CalendarEventState.skipped => (Icons.remove_circle_outline, 'Skipped', theme.colorScheme.outline),
      CalendarEventState.missed => (Icons.cancel_outlined, 'Missed', AppColors.error),
      CalendarEventState.live => (Icons.play_circle_outline, 'Live', theme.colorScheme.tertiary),
      CalendarEventState.ended => (Icons.flag_outlined, 'Ended', theme.colorScheme.outline),
      CalendarEventState.cancelled => (Icons.block_outlined, 'Cancelled', theme.colorScheme.outline),
      CalendarEventState.scheduled => switch (e.kind) {
          CalendarEventKind.test => (Icons.quiz_outlined, 'Test', theme.colorScheme.primary),
          CalendarEventKind.specialDay => (Icons.star_rounded, 'Special Day', const Color(0xFFD97706)),
          CalendarEventKind.routine => (Icons.menu_book_outlined, 'Routine', theme.colorScheme.primary),
        },
    };
    return Card(
      key: Key('calendar_event_${e.id}'),
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        leading: Icon(icon, color: chipColor),
        title: Text(
          e.title,
          style: e.isDone ? const TextStyle(decoration: TextDecoration.lineThrough) : null,
        ),
        subtitle: Text([if (e.timeLabel != null) e.timeLabel!, if (e.subtitle != null) e.subtitle!].join(' · ')),
        trailing: Text(chip, key: Key('calendar_state_${e.id}'), style: theme.textTheme.labelMedium?.copyWith(color: chipColor)),
        onTap: e.kind == CalendarEventKind.specialDay && e.specialDay != null
            ? () => SpecialDayBottomSheet.show(context, e.specialDay!)
            : e.kind == CalendarEventKind.test
                ? () => _openEvent(e)
                : null,
      ),
    );
  }
}
