import 'package:flutter/material.dart';

/// "Leaderboard" — the only live leaderboard is per-test
/// (`/groups/:id/tests/:testId/results/leaderboard`); there is no
/// group-wide leaderboard table or RPC. Rather than fabricate one, this
/// routes to the group's test list, where a real leaderboard is one tap
/// away from any test's results.
class GroupLeaderboardSection extends StatelessWidget {
  const GroupLeaderboardSection({required this.onOpenTests, super.key});

  final VoidCallback onOpenTests;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Leaderboard', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        Card(
          key: const Key('group_leaderboard_stub'),
          margin: EdgeInsets.zero,
          child: InkWell(
            onTap: onOpenTests,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(Icons.leaderboard_outlined, color: theme.colorScheme.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Pick a test to see its leaderboard.',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                  const Icon(Icons.chevron_right),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
