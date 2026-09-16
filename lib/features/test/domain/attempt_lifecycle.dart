import '../../../core/models/attempt.dart' show AttemptStatus;

/// Centralized attempt-state rules (mirrors the server enum
/// in_progress → submitted | auto_submitted → scored).
abstract final class AttemptLifecycle {
  /// The user may still answer / autosave / submit.
  static bool isInteractive(AttemptStatus status) =>
      status == AttemptStatus.inProgress;

  /// A result row may exist (submitted attempts are scored server-side).
  static bool mayHaveResult(AttemptStatus status) =>
      status == AttemptStatus.submitted ||
      status == AttemptStatus.autoSubmitted ||
      status == AttemptStatus.scored;

  static String label(AttemptStatus status) {
    switch (status) {
      case AttemptStatus.inProgress:
        return 'In progress';
      case AttemptStatus.submitted:
        return 'Submitted';
      case AttemptStatus.autoSubmitted:
        return 'Auto-submitted';
      case AttemptStatus.scored:
        return 'Scored';
      case AttemptStatus.unknown:
        return 'Unknown';
    }
  }
}
