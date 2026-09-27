import 'package:flutter/material.dart';

/// Test difficulty levels for visual badge styling.
enum TestCardDifficulty {
  easy,
  medium,
  hard;

  String get label {
    switch (this) {
      case TestCardDifficulty.easy:
        return 'Easy';
      case TestCardDifficulty.medium:
        return 'Medium';
      case TestCardDifficulty.hard:
        return 'Hard';
    }
  }

  Color get color {
    switch (this) {
      case TestCardDifficulty.easy:
        return const Color(0xFF10B981); // Emerald
      case TestCardDifficulty.medium:
        return const Color(0xFFF59E0B); // Amber
      case TestCardDifficulty.hard:
        return const Color(0xFFEF4444); // Rose
    }
  }
}

/// Operational state of the test.
enum TestCardStatus {
  live,
  upcoming,
  completed;

  String get label {
    switch (this) {
      case TestCardStatus.live:
        return 'Live & Active';
      case TestCardStatus.upcoming:
        return 'Upcoming';
      case TestCardStatus.completed:
        return 'Completed';
    }
  }
}

/// Model encapsulating test presentation data.
class TestCardData {
  const TestCardData({
    required this.id,
    required this.title,
    required this.subject,
    required this.difficulty,
    required this.mode,
    required this.questionCount,
    required this.totalMarks,
    required this.durationMinutes,
    required this.status,
    this.scheduledDate,
    this.scoreObtained,
    this.accuracyPercentage,
    this.rank,
    this.totalParticipants,
    this.isBookmarked = false,
    this.correctCount,
    this.incorrectCount,
    this.unansweredCount,
    this.marksPerQuestion,
    this.negativeMarks,
    this.startedAt,
    this.submittedAt,
  });

  final String id;
  final String title;
  final String subject;
  final TestCardDifficulty difficulty;
  final String mode;
  final int questionCount;
  final double totalMarks;
  final int durationMinutes;
  final TestCardStatus status;
  final String? scheduledDate;
  final double? scoreObtained;
  final double? accuracyPercentage;
  final int? rank;
  final int? totalParticipants;
  final bool isBookmarked;

  /// The following are only ever populated from the server's own
  /// `rpc_submit_and_score_test` scorecard / attempt row — never estimated
  /// client-side. All nullable: a caller with no real value simply omits it,
  /// and PDF export / UI must render "--" rather than fabricate one.
  final int? correctCount;
  final int? incorrectCount;
  final int? unansweredCount;
  final double? marksPerQuestion;
  final double? negativeMarks;
  final DateTime? startedAt;
  final DateTime? submittedAt;
}

/// Unified TestCard component: displays subject pill, difficulty badge,
/// mode tag, and status-driven primary CTAs with responsive padding.
class TestCard extends StatelessWidget {
  const TestCard({
    required this.data,
    this.onTap,
    this.onAction,
    this.onSecondaryAction,
    super.key,
  });

  final TestCardData data;
  final VoidCallback? onTap;
  final VoidCallback? onAction;
  final VoidCallback? onSecondaryAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final cardBg = isDark ? const Color(0xFF1E293B) : Colors.white;
    final borderColor = isDark
        ? const Color(0xFF334155).withValues(alpha: 0.8)
        : const Color(0xFFE2E8F0);

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top Tags Row: Subject Pill + Difficulty Badge + Mode Tag
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    // Subject Pill
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 3.5,
                      ),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        data.subject,
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ),

                    // Difficulty Badge
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3.5,
                      ),
                      decoration: BoxDecoration(
                        color: data.difficulty.color.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: data.difficulty.color.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: data.difficulty.color,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 5),
                          Text(
                            data.difficulty.label,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: data.difficulty.color,
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Mode Tag
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3.5,
                      ),
                      decoration: BoxDecoration(
                        color: isDark
                            ? const Color(0xFF334155)
                            : const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        data.mode,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: isDark
                              ? const Color(0xFF94A3B8)
                              : const Color(0xFF64748B),
                        ),
                      ),
                    ),

                    // Live pulsing indicator
                    if (data.status == TestCardStatus.live)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3.5,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF10B981)
                              .withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '🟢 LIVE NOW',
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF059669),
                                letterSpacing: 0.4,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),

                const SizedBox(height: 12),

                // Test Title
                Text(
                  data.title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),

                const SizedBox(height: 8),

                // Metadata Metrics Row: Questions • Marks • Duration (responsive Wrap)
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.help_outline_rounded,
                          size: 15,
                          color: isDark
                              ? const Color(0xFF94A3B8)
                              : const Color(0xFF64748B),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${data.questionCount} Questions',
                          style: TextStyle(
                            fontSize: 12.5,
                            color: isDark
                                ? const Color(0xFF94A3B8)
                                : const Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ),
                    const Text('•', style: TextStyle(color: Color(0xFF94A3B8))),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.stars_rounded,
                          size: 15,
                          color: Color(0xFFD97706),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${data.totalMarks.toInt()} Marks',
                          style: TextStyle(
                            fontSize: 12.5,
                            color: isDark
                                ? const Color(0xFF94A3B8)
                                : const Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ),
                    const Text('•', style: TextStyle(color: Color(0xFF94A3B8))),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.schedule_rounded,
                          size: 15,
                          color: isDark
                              ? const Color(0xFF94A3B8)
                              : const Color(0xFF64748B),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${data.durationMinutes}m',
                          style: TextStyle(
                            fontSize: 12.5,
                            color: isDark
                                ? const Color(0xFF94A3B8)
                                : const Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),

                // If completed, show performance snippet
                if (data.status == TestCardStatus.completed &&
                    data.scoreObtained != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: isDark
                          ? const Color(0xFF0F172A).withValues(alpha: 0.5)
                          : const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isDark
                            ? const Color(0xFF334155)
                            : const Color(0xFFE2E8F0),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            const Text(
                              'Score: ',
                              style: TextStyle(
                                fontSize: 12.5,
                                color: Color(0xFF64748B),
                              ),
                            ),
                            Text(
                              '${data.scoreObtained?.toStringAsFixed(1)} / ${data.totalMarks.toInt()}',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                        if (data.accuracyPercentage != null)
                          Text(
                            'Accuracy: ${data.accuracyPercentage?.toStringAsFixed(1)}%',
                            style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF10B981),
                            ),
                          ),
                        if (data.rank != null)
                          Text(
                            'Rank: #${data.rank}',
                            style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF2563EB),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],

                // Upcoming schedule date line
                if (data.status == TestCardStatus.upcoming &&
                    data.scheduledDate != null) ...[
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      const Icon(
                        Icons.event_rounded,
                        size: 14,
                        color: Color(0xFF2563EB),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Scheduled: ${data.scheduledDate}',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF2563EB),
                        ),
                      ),
                    ],
                  ),
                ],

                const SizedBox(height: 14),
                const Divider(height: 1),
                const SizedBox(height: 12),

                // Status-Driven CTA Actions
                _buildActionButtons(context),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActionButtons(BuildContext context) {
    switch (data.status) {
      case TestCardStatus.live:
        return Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                key: Key('test_card_start_btn_${data.id}'),
                onPressed: onAction ?? onTap,
                icon: const Icon(Icons.play_arrow_rounded, size: 18),
                label: const Text('Start Examination ➔'),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF2563EB),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ),
          ],
        );

      case TestCardStatus.upcoming:
        return Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                key: Key('test_card_instructions_btn_${data.id}'),
                onPressed: onAction ?? onTap,
                icon: const Icon(Icons.menu_book_rounded, size: 16),
                label: const Text('View Instructions'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filledTonal(
              tooltip: 'Set Reminder',
              onPressed: onSecondaryAction ?? () {},
              icon: const Icon(Icons.notifications_active_outlined, size: 18),
            ),
          ],
        );

      case TestCardStatus.completed:
        return Row(
          children: [
            Expanded(
              child: FilledButton.tonalIcon(
                key: Key('test_card_analysis_btn_${data.id}'),
                onPressed: onAction ?? onTap,
                icon: const Icon(Icons.analytics_outlined, size: 16),
                label: const Text('View Scorecard & Solutions'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 11),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              key: Key('test_card_leaderboard_btn_${data.id}'),
              onPressed: onSecondaryAction,
              icon: const Icon(Icons.emoji_events_outlined, size: 16),
              label: const Text('Leaderboard'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 11,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ],
        );
    }
  }
}
