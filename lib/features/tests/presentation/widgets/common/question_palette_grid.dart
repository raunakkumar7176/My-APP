import 'package:flutter/material.dart';

/// State of an individual question in the live exam palette.
enum PaletteQuestionStatus { answered, unanswered, markedForReview, current }

/// Question status descriptor for a specific index in the test.
class QuestionPaletteItem {
  const QuestionPaletteItem({
    required this.index,
    required this.status,
    this.isMarkedForReview = false,
    this.isAnswered = false,
  });

  final int index;
  final PaletteQuestionStatus status;
  final bool isMarkedForReview;
  final bool isAnswered;
}

/// Thumb-friendly number grid distinguishing Answered (Green),
/// Unanswered (Slate), Marked for Review (Purple Star), and Current (Glowing blue ring).
class QuestionPaletteGrid extends StatelessWidget {
  const QuestionPaletteGrid({
    required this.totalQuestions,
    required this.currentIndex,
    required this.answeredIndices,
    required this.markedIndices,
    required this.onQuestionSelected,
    this.showLegend = true,
    this.crossAxisCount,
    super.key,
  });

  final int totalQuestions;
  final int currentIndex;
  final Set<int> answeredIndices;
  final Set<int> markedIndices;
  final ValueChanged<int> onQuestionSelected;
  final bool showLegend;
  final int? crossAxisCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final screenWidth = MediaQuery.of(context).size.width;

    // Adaptive column count: 5 columns on narrow mobile, 6-8 on larger screens
    final columns =
        crossAxisCount ?? (screenWidth > 720 ? 8 : (screenWidth > 480 ? 6 : 5));

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showLegend) ...[
          _buildLegend(context, isDark),
          const SizedBox(height: 16),
        ],

        // Grid of numbers
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: totalQuestions,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: 1.0,
          ),
          itemBuilder: (context, index) {
            final isCurrent = index == currentIndex;
            final isAnswered = answeredIndices.contains(index);
            final isMarked = markedIndices.contains(index);

            return _buildPaletteButton(
              context: context,
              index: index,
              isCurrent: isCurrent,
              isAnswered: isAnswered,
              isMarked: isMarked,
              isDark: isDark,
            );
          },
        ),
      ],
    );
  }

  Widget _buildPaletteButton({
    required BuildContext context,
    required int index,
    required bool isCurrent,
    required bool isAnswered,
    required bool isMarked,
    required bool isDark,
  }) {
    // Determine colors
    Color bg;
    Color border;
    Color textColor;
    List<BoxShadow> shadows = [];

    if (isCurrent) {
      bg = const Color(0xFF2563EB); // Vibrant Primary Blue
      border = const Color(0xFF60A5FA);
      textColor = Colors.white;
      shadows = [
        BoxShadow(
          color: const Color(0xFF2563EB).withValues(alpha: 0.45),
          blurRadius: 10,
          spreadRadius: 1,
          offset: const Offset(0, 2),
        ),
      ];
    } else if (isMarked) {
      bg = const Color(0xFF8B5CF6); // Purple
      border = const Color(0xFFA78BFA);
      textColor = Colors.white;
    } else if (isAnswered) {
      bg = const Color(0xFF10B981); // Emerald Green
      border = const Color(0xFF34D399);
      textColor = Colors.white;
    } else {
      bg = isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9);
      border = isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1);
      textColor = isDark ? const Color(0xFF94A3B8) : const Color(0xFF475569);
    }

    return Semantics(
      button: true,
      label:
          'Question ${index + 1}: ${isCurrent ? 'Current' : (isMarked ? 'Marked for Review' : (isAnswered ? 'Answered' : 'Unanswered'))}',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: Key('palette_btn_$index'),
          onTap: () => onQuestionSelected(index),
          borderRadius: BorderRadius.circular(12),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isCurrent ? const Color(0xFF93C5FD) : border,
                width: isCurrent ? 2.5 : 1.2,
              ),
              boxShadow: shadows,
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Text(
                  '${index + 1}',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: textColor,
                  ),
                ),
                if (isMarked)
                  const Positioned(
                    top: 3,
                    right: 3,
                    child: Icon(
                      Icons.star_rounded,
                      size: 11,
                      color: Colors.white,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLegend(BuildContext context, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
        ),
      ),
      child: Wrap(
        spacing: 12,
        runSpacing: 8,
        alignment: WrapAlignment.spaceAround,
        children: [
          _legendItem(
            color: const Color(0xFF10B981),
            label: 'Answered',
            icon: Icons.check_circle_rounded,
          ),
          _legendItem(
            color: isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8),
            label: 'Unanswered',
            icon: Icons.radio_button_unchecked_rounded,
          ),
          _legendItem(
            color: const Color(0xFF8B5CF6),
            label: 'Marked Review',
            icon: Icons.star_rounded,
          ),
          _legendItem(
            color: const Color(0xFF2563EB),
            label: 'Current',
            icon: Icons.adjust_rounded,
          ),
        ],
      ),
    );
  }

  Widget _legendItem({
    required Color color,
    required String label,
    required IconData icon,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ],
    );
  }
}
