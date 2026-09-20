/// A single completion log for a routine on a specific date (maps to `routine_logs` table).
///
/// One row per `(routine_id, log_date)` enforced by UNIQUE constraint.
/// RLS ensures users can only access their own routine logs through routines ownership.
final class RoutineLog {
  const RoutineLog({
    required this.id,
    required this.routineId,
    required this.logDate,
    this.completed = false,
    this.status = 'PENDING',
    this.durationMinutes,
    this.completedAt,
    required this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String routineId;

  /// User's local calendar day as a date-only string (`YYYY-MM-DD`).
  final String logDate;

  /// Legacy boolean — use [status] for new code.
  final bool completed;

  /// `COMPLETED | SKIPPED | MISSED | PENDING`
  final String status;
  final int? durationMinutes;
  final DateTime? completedAt;
  final DateTime createdAt;
  final DateTime? updatedAt;

  bool get isCompleted => status == 'COMPLETED';
  bool get isSkipped => status == 'SKIPPED';
  bool get isMissed => status == 'MISSED';
  bool get isPending => status == 'PENDING';

  factory RoutineLog.fromJson(Map<String, dynamic> json) {
    return RoutineLog(
      id: json['id'] as String,
      routineId: json['routine_id'] as String,
      logDate: json['log_date'] as String,
      completed: json['completed'] as bool? ?? false,
      status: (json['status'] as String?) ??
          (json['completed'] == true ? 'COMPLETED' : 'PENDING'),
      durationMinutes: (json['duration_minutes'] as num?)?.toInt(),
      completedAt: json['completed_at'] != null
          ? DateTime.tryParse(json['completed_at'] as String)
          : null,
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      updatedAt: json['updated_at'] != null
          ? DateTime.tryParse(json['updated_at'] as String)
          : null,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RoutineLog &&
          runtimeType == other.runtimeType &&
          routineId == other.routineId &&
          logDate == other.logDate;

  @override
  int get hashCode => Object.hash(routineId, logDate);
}
