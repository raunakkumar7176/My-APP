/// One row of `public.point_transactions` — an immutable audit-trail entry
/// written only by `rpc_award_study_points` (never inserted directly by the
/// client; the table's RLS grants `select` only, no `insert`, to
/// `authenticated`). See `0058_gamification_verification_social_v1.sql`.
final class PointTransaction {
  const PointTransaction({
    required this.id,
    required this.userId,
    required this.points,
    required this.reason,
    required this.createdAt,
  });

  final String id;
  final String userId;
  final int points;
  final String reason;
  final DateTime createdAt;

  factory PointTransaction.fromJson(Map<String, dynamic> json) {
    return PointTransaction(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      points: (json['points'] as num).toInt(),
      reason: json['reason'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'user_id': userId,
        'points': points,
        'reason': reason,
        'created_at': createdAt.toIso8601String(),
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PointTransaction &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          userId == other.userId &&
          points == other.points &&
          reason == other.reason &&
          createdAt == other.createdAt;

  @override
  int get hashCode => Object.hash(id, userId, points, reason, createdAt);
}
