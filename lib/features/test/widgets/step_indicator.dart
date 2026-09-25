import 'package:flutter/material.dart';

/// A compact, numbered step indicator for the test creation wizard.
///
/// Shows circular step numbers with active/completed/pending states,
/// connected by a track line. Labels are shown below the active step.
class StepIndicator extends StatelessWidget {
  const StepIndicator({
    required this.steps,
    required this.currentStep,
    super.key,
  });

  /// Step labels (e.g. ['Details', 'Config', 'Syllabus', ...]).
  final List<String> steps;

  /// Zero-based index of the currently active step.
  final int currentStep;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildTrackRow(context, colorScheme),
          const SizedBox(height: 6),
          _buildLabelsRow(context, colorScheme),
        ],
      ),
    );
  }

  Widget _buildTrackRow(BuildContext context, ColorScheme colorScheme) {
    return Row(
      children: List.generate(steps.length, (i) {
        final isCompleted = i < currentStep;
        final isActive = i == currentStep;
        final isLast = i == steps.length - 1;

        return Expanded(
          child: Row(
            children: [
              _buildCircle(context, i, isCompleted, isActive, colorScheme),
              if (!isLast)
                Expanded(
                  child: Container(
                    height: 2,
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    color: i < currentStep
                        ? colorScheme.primary
                        : colorScheme.outlineVariant,
                  ),
                ),
            ],
          ),
        );
      }),
    );
  }

  Widget _buildCircle(
    BuildContext context,
    int index,
    bool isCompleted,
    bool isActive,
    ColorScheme colorScheme,
  ) {
    final size = isActive ? 28.0 : 24.0;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isCompleted || isActive
            ? colorScheme.primary
            : colorScheme.surfaceContainerHighest,
        border: isActive
            ? Border.all(color: colorScheme.primary, width: 2)
            : isCompleted
                ? null
                : Border.all(color: colorScheme.outlineVariant),
        boxShadow: isActive
            ? [
                BoxShadow(
                  color: colorScheme.primary.withValues(alpha: 0.3),
                  blurRadius: 8,
                  spreadRadius: 1,
                ),
              ]
            : null,
      ),
      child: Center(
        child: isCompleted
            ? Icon(Icons.check, size: 14, color: colorScheme.onPrimary)
            : Text(
                '${index + 1}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: isActive
                      ? colorScheme.onPrimary
                      : colorScheme.onSurfaceVariant,
                ),
              ),
      ),
    );
  }

  Widget _buildLabelsRow(BuildContext context, ColorScheme colorScheme) {
    return Row(
      children: List.generate(steps.length, (i) {
        final isActive = i == currentStep;
        final isCompleted = i < currentStep;

        return Expanded(
          child: Center(
            child: Text(
              steps[i],
              style: TextStyle(
                fontSize: 10,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                color: isActive
                    ? colorScheme.primary
                    : isCompleted
                        ? colorScheme.onSurface
                        : colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        );
      }),
    );
  }
}
