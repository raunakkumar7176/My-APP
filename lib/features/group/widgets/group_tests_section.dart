import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/models/test.dart';
import '../../../core/theme/app_radius.dart';
import '../../test/domain/test_lifecycle.dart';
import '../../test/widgets/test_formatters.dart';
import '../domain/group_test_management.dart';
import '../state/group_hub_controller.dart';

/// "Tests" section on the Info screen: Active (live + upcoming) and Past,
/// each a real server-backed list — no counts are invented, and an empty
/// section says so honestly instead of showing 0 silently.
class GroupTestsSection extends StatefulWidget {
  const GroupTestsSection({
    required this.controller,
    required this.onOpenAllTests,
    super.key,
  });

  final GroupHubController controller;
  final VoidCallback onOpenAllTests;

  @override
  State<GroupTestsSection> createState() => _GroupTestsSectionState();
}

class _GroupTestsSectionState extends State<GroupTestsSection> {
  bool _showPast = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = widget.controller;
    final active = [
      ...c.testsInSection(GroupTestSection.live),
      ...c.testsInSection(GroupTestSection.upcoming),
    ];
    final past = c.testsInSection(GroupTestSection.previous);
    final rows = _showPast ? past : active;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Tests', style: theme.textTheme.titleMedium),
            TextButton(
              key: const Key('group_info_view_all_tests'),
              onPressed: widget.onOpenAllTests,
              child: const Text('View all'),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            _toggleChip(
              key: const Key('group_tests_tab_active'),
              label: 'Active (${active.length})',
              selected: !_showPast,
              onTap: () => setState(() => _showPast = false),
            ),
            const SizedBox(width: 8),
            _toggleChip(
              key: const Key('group_tests_tab_past'),
              label: 'Past (${past.length})',
              selected: _showPast,
              onTap: () => setState(() => _showPast = true),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (rows.isEmpty)
          Card(
            key: Key(
              _showPast ? 'group_tests_past_empty' : 'group_tests_active_empty',
            ),
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                _showPast
                    ? 'No past tests yet.'
                    : "No tests yet\nYour group hasn't scheduled an upcoming test.",
                style: theme.textTheme.bodySmall,
              ),
            ),
          )
        else
          for (final t in rows.take(3))
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _testRow(context, t),
            ),
      ],
    );
  }

  Widget _toggleChip({
    required Key key,
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      key: key,
      onTap: onTap,
      borderRadius: AppRadius.pillBorder,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF2563EB) : Colors.transparent,
          borderRadius: AppRadius.pillBorder,
          border: Border.all(
            color: selected ? const Color(0xFF2563EB) : const Color(0xFFCBD5E1),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: selected ? Colors.white : const Color(0xFF64748B),
          ),
        ),
      ),
    );
  }

  Widget _testRow(BuildContext context, Test test) {
    final theme = Theme.of(context);
    return Card(
      key: Key('group_test_row_${test.id}'),
      margin: EdgeInsets.zero,
      child: InkWell(
        borderRadius: AppRadius.lgBorder,
        onTap: () => context.push('/tests/${test.id}'),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                test.title,
                style: theme.textTheme.titleSmall,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Text(
                '${TestLifecycle.statusLabel(test.status)} · '
                '${TestFormatters.duration(test.durationSec)}'
                '${test.startsAt != null ? ' · ${TestFormatters.dateTime(test.startsAt)}' : ''}',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
