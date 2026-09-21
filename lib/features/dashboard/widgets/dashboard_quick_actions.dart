import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Grid of shortcuts to the app's main personal actions. Every action here
/// is available to any signed-in user — nothing here is group-scoped, so
/// there is no admin/member gate to apply (that gating happens inside the
/// Group feature itself for group-specific actions).
class DashboardQuickActions extends StatelessWidget {
  const DashboardQuickActions({super.key, required this.draftsCount});

  final int draftsCount;

  @override
  Widget build(BuildContext context) {
    final actions = <_QuickAction>[
      _QuickAction('Start Study', Icons.menu_book_outlined, () => context.push('/subjects')),
      _QuickAction('My Routine', Icons.calendar_today_outlined, () => context.push('/routine')),
      _QuickAction('My Tests', Icons.quiz_outlined, () => context.push('/tests')),
      _QuickAction('Create Test', Icons.add_box_outlined, () => context.push('/tests/create')),
      _QuickAction(
        'My Drafts',
        Icons.drafts_outlined,
        () => context.push('/tests/drafts'),
        badge: draftsCount > 0 ? draftsCount : null,
      ),
      _QuickAction('Question Bank', Icons.library_books_outlined, () => context.push('/question-bank')),
      _QuickAction('Groups', Icons.groups_outlined, () => context.push('/groups')),
      _QuickAction('Leaderboard', Icons.leaderboard_outlined, () => context.push('/leaderboard')),
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 1.0,
      ),
      itemCount: actions.length,
      itemBuilder: (context, i) => _ActionTile(action: actions[i]),
    );
  }
}

class _QuickAction {
  const _QuickAction(this.label, this.icon, this.onTap, {this.badge});

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final int? badge;
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({required this.action});

  final _QuickAction action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerLowest,
      borderRadius: BorderRadius.circular(14),
      elevation: 0.5,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: action.onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Badge(
                isLabelVisible: action.badge != null,
                label: Text('${action.badge}'),
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Icon(action.icon, color: theme.colorScheme.primary, size: 20),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                action.label,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
