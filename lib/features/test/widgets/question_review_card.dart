import 'package:flutter/material.dart';

import '../../../core/constants/theme/app_colors.dart';
import '../../../core/models/answer.dart';
import '../../../core/models/question.dart';
import '../../radio/domain/radio_track.dart';
import '../../radio/state/radio_player_controller.dart';

enum ReviewStatus { correct, wrong, answered, unanswered }

class QuestionReviewCard extends StatelessWidget {
  const QuestionReviewCard({
    required this.question,
    required this.answer,
    required this.questionNumber,
    required this.totalQuestions,
    this.correctOption,
    super.key,
  });

  final Question question;
  final Answer? answer;
  final int questionNumber;
  final int totalQuestions;

  /// The real correct option index, from `rpc_get_my_answer_key` (migration
  /// 0079) — only ever populated for the caller's own already-submitted
  /// attempt. Null means the key wasn't available (e.g. offline, or the
  /// migration isn't deployed yet); the card then falls back to the plain
  /// "Answered"/"Unanswered" status rather than guessing a verdict.
  final int? correctOption;

  ReviewStatus get _status {
    if (answer == null || !answer!.isAnswered) {
      return ReviewStatus.unanswered;
    }
    if (correctOption == null) {
      return ReviewStatus.answered;
    }
    return answer!.selectedOption == correctOption
        ? ReviewStatus.correct
        : ReviewStatus.wrong;
  }

  @override
  Widget build(BuildContext context) {
    final selectedIndex = answer?.selectedOption;
    final status = _status;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(context, status),
            const SizedBox(height: 12),
            Text(
              question.question,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 12),
            if (question.hasOptions)
              ...question.options!.map(
                (opt) => _buildOption(
                  context,
                  option: opt,
                  isSelected: selectedIndex == opt.index,
                  isCorrect: correctOption != null && correctOption == opt.index,
                  // The answer key wasn't available for this attempt — don't
                  // paint the selection red, which claims a verdict ("you
                  // got this wrong") the app doesn't actually have.
                  verdictKnown: correctOption != null,
                ),
              ),
            // Typed-answer questions have no storage on the live backend.
            if (!question.hasOptions) _buildUnanswered(context),
            if (question.explanation != null &&
                question.explanation!.isNotEmpty) ...[
              const SizedBox(height: 12),
              _buildExplanation(context),
            ],
            if (question.explanation == null ||
                question.explanation!.isEmpty) ...[
              const SizedBox(height: 12),
              _buildNoExplanation(context),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, ReviewStatus status) {
    Color statusColor;
    IconData statusIcon;
    String statusText;

    switch (status) {
      case ReviewStatus.correct:
        statusColor = AppColors.success;
        statusIcon = Icons.check_circle;
        statusText = 'Correct';
      case ReviewStatus.wrong:
        statusColor = AppColors.error;
        statusIcon = Icons.cancel;
        statusText = 'Wrong';
      case ReviewStatus.answered:
        statusColor = AppColors.primaryLight;
        statusIcon = Icons.check_circle_outline;
        statusText = 'Answered';
      case ReviewStatus.unanswered:
        statusColor = AppColors.textSecondaryLight;
        statusIcon = Icons.help_outline;
        statusText = 'Unanswered';
    }

    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: AppColors.primaryLight.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            'Q $questionNumber / $totalQuestions',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: AppColors.primaryLight,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: AppColors.success.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            '${question.marks} mark${question.marks != 1 ? 's' : ''}',
            style: Theme.of(context).textTheme.labelSmall
                ?.copyWith(color: AppColors.success),
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: statusColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(statusIcon, size: 14, color: statusColor),
              const SizedBox(width: 4),
              Text(
                statusText,
                style: Theme.of(context).textTheme.labelSmall
                    ?.copyWith(color: statusColor, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
        const Spacer(),
        IconButton(
          key: const Key('question_review_speak_button'),
          tooltip: 'Suniye',
          icon: const Icon(Icons.volume_up_rounded, size: 20),
          onPressed: () => RadioPlayerController.instance.speakOnce(
            RadioTrack(question: question, correctOption: correctOption),
          ),
        ),
        _buildDifficultyBadge(context),
      ],
    );
  }

  Widget _buildDifficultyBadge(BuildContext context) {
    Color color;
    String label;

    switch (question.difficulty) {
      case DifficultyLevel.easy:
        color = AppColors.success;
        label = 'Easy';
      case DifficultyLevel.medium:
        color = AppColors.warning;
        label = 'Medium';
      case DifficultyLevel.hard:
        color = AppColors.error;
        label = 'Hard';
      case DifficultyLevel.unknown:
        color = AppColors.textSecondaryLight;
        label = '--';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color),
      ),
    );
  }

  Widget _buildOption(
    BuildContext context, {
    required QuestionOption option,
    required bool isSelected,
    required bool isCorrect,
    required bool verdictKnown,
  }) {
    // isCorrect always wins the styling (even if the student didn't pick
    // it, so they can see what the right answer was); a selected-but-wrong
    // option is called out in red — but only once a verdict is actually
    // known (the answer key loaded). Without it, red would claim "this was
    // wrong" when the truth is just "unknown"; the selection is shown in
    // the neutral primary colour instead, matching the header's own
    // "Answered" (not "Wrong") status in that case.
    final theme = Theme.of(context);
    final Color? accent = isCorrect
        ? AppColors.success
        : (isSelected
              ? (verdictKnown ? AppColors.error : theme.colorScheme.primary)
              : null);
    final bool highlighted = isCorrect || isSelected;

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: highlighted
              ? (accent ?? theme.colorScheme.primary).withValues(alpha: 0.08)
              : Colors.transparent,
          border: Border.all(
            color: highlighted
                ? (accent ?? theme.colorScheme.primary)
                : theme.colorScheme.outlineVariant,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(
              isCorrect
                  ? Icons.check_circle
                  : (isSelected ? Icons.cancel : Icons.radio_button_off),
              size: 18,
              color: highlighted
                  ? (accent ?? theme.colorScheme.primary)
                  : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                option.text,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: highlighted
                      ? (accent ?? theme.colorScheme.primary)
                      : theme.colorScheme.onSurface,
                  fontWeight: isCorrect ? FontWeight.w600 : null,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUnanswered(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        'Not answered',
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          fontStyle: FontStyle.italic,
        ),
      ),
    );
  }

  Widget _buildExplanation(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.success.withValues(alpha: 0.05),
        border: Border.all(color: AppColors.success.withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.lightbulb_outline,
                size: 16,
                color: AppColors.success,
              ),
              const SizedBox(width: 6),
              Text(
                'Explanation',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: AppColors.success,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            question.explanation!,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }

  Widget _buildNoExplanation(BuildContext context) {
    return Row(
      children: [
        const Icon(
          Icons.info_outline,
          size: 14,
          color: AppColors.textSecondaryLight,
        ),
        const SizedBox(width: 6),
        Text(
          'Explanation not available',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: AppColors.textSecondaryLight,
            fontStyle: FontStyle.italic,
          ),
        ),
      ],
    );
  }
}
