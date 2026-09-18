import 'package:flutter/material.dart';

import '../../../core/constants/theme/app_colors.dart';
import '../state/attempt_controller.dart';

/// Thin autosave indicator under the app bar of the taking screen.
/// Informational only — never blocks answering. On failure it becomes a
/// warning strip with a manual retry (the timer keeps retrying regardless).
class SaveStatusBar extends StatelessWidget {
  const SaveStatusBar({
    required this.status,
    required this.lastSavedAt,
    required this.error,
    required this.failures,
    required this.onRetry,
    super.key,
  });

  final SaveStatus status;
  final DateTime? lastSavedAt;
  final String? error;
  final int failures;
  final VoidCallback onRetry;

  static String _time(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    switch (status) {
      case SaveStatus.idle:
        return const SizedBox.shrink();
      case SaveStatus.saving:
        return _line(
          context,
          key: const Key('save_status_saving'),
          leading: const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          text: 'Saving…',
          color: theme.colorScheme.outline,
        );
      case SaveStatus.saved:
        return _line(
          context,
          key: const Key('save_status_saved'),
          leading: const Icon(
            Icons.cloud_done_outlined,
            size: 14,
            color: AppColors.success,
          ),
          text: lastSavedAt == null ? 'Saved' : 'Saved ${_time(lastSavedAt!)}',
          color: theme.colorScheme.outline,
        );
      case SaveStatus.failed:
        return Material(
          key: const Key('save_status_failed'),
          color: AppColors.warning.withValues(alpha: 0.15),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
            child: Row(
              children: [
                const Icon(
                  Icons.cloud_off_outlined,
                  size: 18,
                  color: AppColors.warning,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    failures > 1
                        ? 'Answers not saved yet ($failures tries). ${error ?? ''}'
                              .trim()
                        : 'Answers not saved yet. ${error ?? ''}'.trim(),
                    style: theme.textTheme.bodySmall,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                TextButton(
                  key: const Key('save_retry_now'),
                  onPressed: onRetry,
                  child: const Text('Retry now'),
                ),
              ],
            ),
          ),
        );
    }
  }

  Widget _line(
    BuildContext context, {
    required Key key,
    required Widget leading,
    required String text,
    required Color color,
  }) {
    return Padding(
      key: key,
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      child: Row(
        children: [
          leading,
          const SizedBox(width: 6),
          Text(
            text,
            style: Theme.of(context).textTheme.labelSmall
                ?.copyWith(color: color),
          ),
        ],
      ),
    );
  }
}
