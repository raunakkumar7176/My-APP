import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Grid of shortcuts to the app's primary personal actions.
/// Designed with academic clarity, soft-tinted icon containers,
/// descriptive subtitle tags, and tactile touch feedback.
class DashboardQuickActions extends StatelessWidget {
  const DashboardQuickActions({super.key, required this.draftsCount});

  final int draftsCount;

  @override
  Widget build(BuildContext context) {
    final actions = <_QuickActionData>[
      const _QuickActionData(
        title: 'My Study',
        subtitle: 'Learn & revise',
        icon: Icons.menu_book_rounded,
        accentColor: Color(0xFF2563EB), // Blue
        route: '/study',
      ),
      const _QuickActionData(
        title: 'Build Test',
        subtitle: 'Custom practice',
        icon: Icons.add_task_rounded,
        accentColor: Color(0xFF059669), // Emerald
        route: '/tests/create',
      ),
      const _QuickActionData(
        title: 'Question Bank',
        subtitle: 'Explore questions',
        icon: Icons.auto_stories_rounded,
        accentColor: Color(0xFFD97706), // Amber
        route: '/question-bank',
      ),
      const _QuickActionData(
        title: 'Routine',
        subtitle: 'Study schedule',
        icon: Icons.event_note_rounded,
        accentColor: Color(0xFF7C3AED), // Violet
        route: '/routine',
      ),
      const _QuickActionData(
        title: 'Groups',
        subtitle: 'Community study',
        icon: Icons.group_work_rounded,
        accentColor: Color(0xFFDB2777), // Pink
        route: '/groups',
      ),
      _QuickActionData(
        title: 'My Tests',
        subtitle: draftsCount > 0
            ? '$draftsCount drafts pending'
            : 'Papers & history',
        icon: Icons.assignment_outlined,
        accentColor: const Color(0xFF0284C7), // Sky
        route: '/tests',
        badge: draftsCount > 0 ? draftsCount : null,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = constraints.maxWidth >= 600 ? 3 : 2;
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: crossAxisCount == 3 ? 2.3 : 1.75,
          ),
          itemCount: actions.length,
          itemBuilder: (context, i) => _ActionCard(data: actions[i]),
        );
      },
    );
  }
}

class _QuickActionData {
  const _QuickActionData({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.accentColor,
    required this.route,
    this.badge,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color accentColor;
  final String route;
  final int? badge;
}

class _ActionCard extends StatefulWidget {
  const _ActionCard({required this.data});

  final _QuickActionData data;

  @override
  State<_ActionCard> createState() => _ActionCardState();
}

class _ActionCardState extends State<_ActionCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final cardBg = isDark ? const Color(0xFF1E293B) : Colors.white;
    final borderColor = isDark
        ? const Color(0xFF334155)
        : const Color(0xFFE2E8F0);

    return AnimatedScale(
      scale: _pressed ? 0.975 : 1.0,
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOutCubic,
      child: Material(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTapDown: (_) => setState(() => _pressed = true),
          onTapUp: (_) => setState(() => _pressed = false),
          onTapCancel: () => setState(() => _pressed = false),
          onTap: () => context.push(widget.data.route),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: borderColor),
              boxShadow: isDark
                  ? null
                  : [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.025),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ],
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: widget.data.accentColor.withValues(
                          alpha: isDark ? 0.2 : 0.1,
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        widget.data.icon,
                        color: widget.data.accentColor,
                        size: 22,
                      ),
                    ),
                    if (widget.data.badge != null)
                      Positioned(
                        top: -4,
                        right: -4,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 1.5,
                          ),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.error,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: cardBg, width: 1.5),
                          ),
                          child: Text(
                            '${widget.data.badge}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.data.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        widget.data.subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.6,
                          ),
                          fontSize: 11.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
