enum AttemptStatus { inProgress, submitted, autoSubmitted, scored, unknown }

AttemptStatus _parseAttemptStatus(String? value) {
  switch (value) {
    case 'in_progress':
      return AttemptStatus.inProgress;
    case 'submitted':
      return AttemptStatus.submitted;
    case 'auto_submitted':
      return AttemptStatus.autoSubmitted;
    case 'scored':
      return AttemptStatus.scored;
    default:
      return AttemptStatus.unknown;
  }
}

final class Attempt {
  const Attempt({
    required this.id,
    required this.testId,
    required this.userId,
    required this.status,
    required this.startedAt,
    this.attemptNumber = 1,
    this.deadlineAt,
    this.submittedAt,
    this.integrityEventCount,
    this.autoSubmitThreshold,
  });

  final String id;
  final String testId;
  final String userId;
  final AttemptStatus status;
  final DateTime startedAt;
  final int attemptNumber;
  final DateTime? deadlineAt;
  final DateTime? submittedAt;
  final int? integrityEventCount;
  final int? autoSubmitThreshold;

  bool get isInProgress => status == AttemptStatus.inProgress;
  bool get isSubmitted =>
      status == AttemptStatus.submitted ||
      status == AttemptStatus.autoSubmitted ||
      status == AttemptStatus.scored;

  Duration? get timeRemaining {
    if (deadlineAt == null) return null;
    final remaining = deadlineAt!.difference(DateTime.now());
    return remaining.isNegative ? Duration.zero : remaining;
  }

  factory Attempt.fromJson(Map<String, dynamic> json) {
    return Attempt(
      id: json['id'] as String,
      testId: json['test_id'] as String,
      userId: json['user_id'] as String,
      status: _parseAttemptStatus(json['status'] as String?),
      startedAt: DateTime.parse(json['started_at'] as String),
      attemptNumber: (json['attempt_number'] as num?)?.toInt() ?? 1,
      deadlineAt: json['deadline_at'] != null
          ? DateTime.parse(json['deadline_at'] as String)
          : null,
      submittedAt: json['submitted_at'] != null
          ? DateTime.parse(json['submitted_at'] as String)
          : null,
      integrityEventCount: (json['integrity_event_count'] as num?)?.toInt(),
      autoSubmitThreshold: (json['auto_submit_threshold'] as num?)?.toInt(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'test_id': testId,
      'user_id': userId,
      'status': status.name,
      'started_at': startedAt.toIso8601String(),
      'attempt_number': attemptNumber,
      'deadline_at': deadlineAt?.toIso8601String(),
      'submitted_at': submittedAt?.toIso8601String(),
      'integrity_event_count': integrityEventCount,
      'auto_submit_threshold': autoSubmitThreshold,
    };
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Attempt &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          testId == other.testId &&
          userId == other.userId &&
          status == other.status;

  @override
  int get hashCode => Object.hash(id, testId, userId, status);
}
