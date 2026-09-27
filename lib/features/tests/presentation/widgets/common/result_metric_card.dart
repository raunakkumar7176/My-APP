import 'package:flutter/material.dart';

/// Glassmorphic result metric tile for Score, Accuracy %, Study Points,
/// and Time Spent with optional celebratory badge.
class ResultMetricCard extends StatelessWidget {
  const ResultMetricCard({
    required this.label,
    required this.value,
    required this.icon,
    this.iconColor,
    this.badgeText,
    this.badgeColor,
    this.subtext,
    this.isCelebratory = false,
    this.onTap,
    super.key,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color? iconColor;
  final String? badgeText;
  final Color? badgeColor;
  final String? subtext;
  final bool isCelebratory;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final effectiveIconColor = iconColor ?? theme.colorScheme.primary;
    final effectiveBadgeColor = badgeColor ?? const Color(0xFF10B981);

    // Glassmorphic styling
    final cardBg = isDark
        ? const Color(0xFF1E293B).withValues(alpha: 0.85)
        : Colors.white.withValues(alpha: 0.92);
    final borderColor = isDark
        ? const Color(0xFF334155).withValues(alpha: 0.8)
        : const Color(0xFFE2E8F0);

    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isCelebratory
              ? effectiveBadgeColor.withValues(alpha: 0.5)
              : borderColor,
          width: isCelebratory ? 1.5 : 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: (isCelebratory ? effectiveBadgeColor : Colors.black)
                .withValues(
                  alpha: isCelebratory ? 0.12 : (isDark ? 0.2 : 0.04),
                ),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Top row: Icon + optional badge
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: effectiveIconColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(icon, size: 20, color: effectiveIconColor),
                    ),
                    if (badgeText != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3.5,
                        ),
                        decoration: BoxDecoration(
                          color: effectiveBadgeColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: effectiveBadgeColor.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Text(
                          badgeText!,
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            color: effectiveBadgeColor,
                          ),
                        ),
                      ),
                  ],
                ),

                const SizedBox(height: 12),

                // Main Metric Value
                Text(
                  value,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                    fontSize: 22,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),

                const SizedBox(height: 4),

                // Label
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: isDark
                        ? const Color(0xFF94A3B8)
                        : const Color(0xFF64748B),
                  ),
                ),

                if (subtext != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    subtext!,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: isDark
                          ? const Color(0xFF64748B)
                          : const Color(0xFF94A3B8),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
