import 'attempt_policy.dart';
import 'creation_settings.dart';
import 'test_kind.dart';

/// One readiness item shown in the Review step and enforced client-side
/// before calling `rpc_publish_test` (which re-validates everything).
class ReadinessItem {
  const ReadinessItem({
    required this.label,
    required this.isValid,
    this.reason,
  });

  final String label;
  final bool isValid;

  /// Actionable reason when [isValid] is false.
  final String? reason;
}

/// Inputs are plain values so the same function serves the creation
/// controller and the review widget.
class PublishReadinessInput {
  const PublishReadinessInput({
    required this.title,
    required this.kind,
    required this.groupId,
    required this.durationSec,
    required this.marksPerQuestion,
    required this.startsAt,
    required this.endsAt,
    required this.serverQuestionStatuses,
    required this.localDraftValidity,
    this.serverQuestionOptionCounts = const [],
    this.syllabusNodeCount,
    this.questionConfig,
    this.actualDifficultyCounts,
    this.attemptSettings,
    this.lateJoin,
    this.allowLateJoin,
    this.joinCode,
  });

  // ── creation-completion inputs (all optional; absent = not evaluated) ──
  final int? syllabusNodeCount;
  final QuestionConfig? questionConfig;
  final Map<String, int>? actualDifficultyCounts;
  final AttemptSettings? attemptSettings;
  final LateJoinSettings? lateJoin;
  final bool? allowLateJoin;
  final String? joinCode;

  /// V1 rule mirrored from rpc_create_question / rpc_update_question.
  static const minOptions = 4;

  /// Option count of every server question (legacy rows may carry < 4).
  final List<int> serverQuestionOptionCounts;

  final String title;
  final TestKind kind;
  final String? groupId;
  final int? durationSec;
  final double? marksPerQuestion;
  final DateTime? startsAt;
  final DateTime? endsAt;

  /// `status` of every question already on the server.
  final List<String> serverQuestionStatuses;

  /// `isValid` of every not-yet-persisted local draft.
  final List<bool> localDraftValidity;
}

abstract final class PublishReadiness {
  static const approvedStatus = 'approved';

  static List<ReadinessItem> evaluate(PublishReadinessInput i) {
    final items = <ReadinessItem>[];

    final hasTitle = i.title.trim().isNotEmpty;
    items.add(
      ReadinessItem(
        label: 'Test title',
        isValid: hasTitle,
        reason: hasTitle ? null : 'Enter a test title',
      ),
    );

    final hasDuration = i.durationSec != null && i.durationSec! > 0;
    items.add(
      ReadinessItem(
        label: 'Duration set',
        isValid: hasDuration,
        reason: hasDuration ? null : 'Set a valid duration',
      ),
    );

    final hasMarks = i.marksPerQuestion != null && i.marksPerQuestion! > 0;
    items.add(
      ReadinessItem(
        label: 'Scoring configured',
        isValid: hasMarks,
        reason: hasMarks ? null : 'Set marks per question',
      ),
    );

    if (i.kind.requiresGroup) {
      final hasGroup = i.groupId != null && i.groupId!.isNotEmpty;
      items.add(
        ReadinessItem(
          label: 'Group selected',
          isValid: hasGroup,
          reason: hasGroup ? null : 'Select a group for Group Test',
        ),
      );
    }

    final total = i.serverQuestionStatuses.length + i.localDraftValidity.length;
    items.add(
      ReadinessItem(
        label: 'Questions added',
        isValid: total > 0,
        reason: total > 0 ? null : 'Add at least one question',
      ),
    );

    if (total > 0) {
      final pending = i.serverQuestionStatuses
          .where((s) => s != approvedStatus)
          .length;
      items.add(
        ReadinessItem(
          label: 'All questions approved',
          isValid: pending == 0,
          reason: pending == 0
              ? null
              : '$pending question(s) need approval before publishing',
        ),
      );
    }

    if (i.serverQuestionOptionCounts.isNotEmpty) {
      final short = i.serverQuestionOptionCounts
          .where((n) => n < PublishReadinessInput.minOptions)
          .length;
      items.add(
        ReadinessItem(
          label:
              'Every question has ${PublishReadinessInput.minOptions} options',
          isValid: short == 0,
          reason: short == 0
              ? null
              : '$short question(s) have fewer than ${PublishReadinessInput.minOptions} options',
        ),
      );
    }

    if (i.localDraftValidity.isNotEmpty) {
      final invalid = i.localDraftValidity.where((v) => !v).length;
      items.add(
        ReadinessItem(
          label: 'All questions valid',
          isValid: invalid == 0,
          reason: invalid == 0 ? null : '$invalid question(s) need fixing',
        ),
      );
    }

    final scheduleOk =
        i.startsAt == null ||
        i.endsAt == null ||
        !i.endsAt!.isBefore(i.startsAt!);
    items.add(
      ReadinessItem(
        label: 'Schedule valid',
        isValid: scheduleOk,
        reason: scheduleOk ? null : 'End time must be after start time',
      ),
    );

    if (i.kind.requiresStartTime) {
      final ok = i.startsAt != null;
      items.add(
        ReadinessItem(
          label: 'Start time set',
          isValid: ok,
          reason: ok ? null : '${i.kind.label} needs a start time',
        ),
      );
    }

    if (i.kind.requiresScope && i.syllabusNodeCount != null) {
      final ok = i.syllabusNodeCount! > 0;
      items.add(
        ReadinessItem(
          label: 'Syllabus scope selected',
          isValid: ok,
          reason: ok
              ? null
              : 'Select at least one syllabus topic for ${i.kind.label}',
        ),
      );
    }

    final qc = i.questionConfig;
    if (qc != null && qc.isSet) {
      items.add(
        ReadinessItem(
          label: 'Difficulty distribution valid',
          isValid: qc.isValid,
          reason: qc.isValid
              ? null
              : 'Easy + Medium + Hard must equal ${qc.total}',
        ),
      );
      if (qc.isValid && i.actualDifficultyCounts != null) {
        final check = qc.check(i.actualDifficultyCounts!);
        items.add(
          ReadinessItem(
            label: 'Questions match the difficulty target',
            isValid: check.satisfied,
            reason: check.satisfied ? null : 'Target not met: ${check.summary}',
          ),
        );
      }
    }

    final a = i.attemptSettings;
    if (a != null) {
      final ok =
          !a.allowReattempt ||
          AttemptSettings.allowedMaxValues.contains(a.maxAttempts);
      items.add(
        ReadinessItem(
          label: 'Attempt settings valid',
          isValid: ok,
          reason: ok
              ? null
              : 'Maximum attempts must be one of ${AttemptSettings.allowedMaxValues}',
        ),
      );
    }

    if (i.kind.supportsLateJoin &&
        i.lateJoin != null &&
        i.allowLateJoin == true) {
      final ok = i.lateJoin!.minutes >= 0;
      items.add(
        ReadinessItem(
          label: 'Late-join window valid',
          isValid: ok,
          reason: ok ? null : 'Late-join window cannot be negative',
        ),
      );
    }

    if (i.kind.requiresJoinCode && i.joinCode != null) {
      final ok = i.joinCode!.trim().isNotEmpty;
      items.add(
        ReadinessItem(
          label: 'Join code set',
          isValid: ok,
          reason: ok ? null : 'Challenge with Friends needs a join code',
        ),
      );
    }

    return items;
  }

  static bool isReady(PublishReadinessInput i) =>
      evaluate(i).every((item) => item.isValid);

  /// Actionable reasons only (what the publish error dialog shows).
  static List<String> blockingReasons(PublishReadinessInput i) => [
    for (final item in evaluate(i))
      if (!item.isValid && item.reason != null) item.reason!,
  ];
}
