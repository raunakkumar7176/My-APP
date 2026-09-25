import 'package:flutter/material.dart';

/// A clean section card for grouping related form fields.
///
/// Provides consistent padding, optional title/subtitle, and a subtle
/// card treatment that works in both light and dark mode.
class SectionCard extends StatelessWidget {
  const SectionCard({
    required this.children,
    this.title,
    this.subtitle,
    this.trailing,
    this.padding = const EdgeInsets.all(16),
    this.margin = const EdgeInsets.only(bottom: 12),
    this.showDivider = false,
    super.key,
  });

  /// Section heading text. Omit for unlabelled sections.
  final String? title;

  /// Optional description below the title.
  final String? subtitle;

  /// Widget to show at the end of the header row (e.g. a chip or icon).
  final Widget? trailing;

  /// Content padding inside the card.
  final EdgeInsetsGeometry padding;

  /// Margin around the card.
  final EdgeInsetsGeometry margin;

  /// Whether to show a divider between header and body.
  final bool showDivider;

  /// The card's child content.
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      margin: margin,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Padding(
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (title != null || subtitle != null || trailing != null) ...[
              Row(
                children: [
                  if (title != null)
                    Expanded(
                      child: Text(
                        title!,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ?trailing,
                ],
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              if (showDivider) ...[
                const SizedBox(height: 12),
                Divider(height: 1, color: theme.colorScheme.outlineVariant),
                const SizedBox(height: 12),
              ] else
                const SizedBox(height: 12),
            ],
            ...children,
          ],
        ),
      ),
    );
  }
}
