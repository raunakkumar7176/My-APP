/// Live `verification_requests.status` values (0058: `pending`, `approved`,
/// `rejected` — no other value is ever written).
enum VerificationStatus {
  pending,
  approved,
  rejected;

  static VerificationStatus fromDb(String? value) {
    switch (value) {
      case 'approved':
        return VerificationStatus.approved;
      case 'rejected':
        return VerificationStatus.rejected;
      case 'pending':
      default:
        return VerificationStatus.pending;
    }
  }

  String get db {
    switch (this) {
      case VerificationStatus.pending:
        return 'pending';
      case VerificationStatus.approved:
        return 'approved';
      case VerificationStatus.rejected:
        return 'rejected';
    }
  }
}

/// One row of `public.verification_requests` — a blue-tick application.
/// Created only via `rpc_request_verification` (requires >= 1000 points,
/// one pending request per user), resolved only by the app owner via
/// `rpc_approve_blue_tick`/`rpc_reject_blue_tick`. See
/// `0058_gamification_verification_social_v1.sql`.
final class VerificationRequest {
  const VerificationRequest({
    required this.id,
    required this.userId,
    required this.currentPoints,
    required this.status,
    this.rejectionReason,
    required this.createdAt,
  });

  final String id;
  final String userId;
  final int? currentPoints;
  final VerificationStatus status;
  final String? rejectionReason;
  final DateTime createdAt;

  bool get isPending => status == VerificationStatus.pending;
  bool get isApproved => status == VerificationStatus.approved;
  bool get isRejected => status == VerificationStatus.rejected;

  factory VerificationRequest.fromJson(Map<String, dynamic> json) {
    return VerificationRequest(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      currentPoints: (json['current_points'] as num?)?.toInt(),
      status: VerificationStatus.fromDb(json['status'] as String?),
      rejectionReason: json['rejection_reason'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'user_id': userId,
        'current_points': currentPoints,
        'status': status.db,
        'rejection_reason': rejectionReason,
        'created_at': createdAt.toIso8601String(),
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is VerificationRequest &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          userId == other.userId &&
          currentPoints == other.currentPoints &&
          status == other.status &&
          rejectionReason == other.rejectionReason &&
          createdAt == other.createdAt;

  @override
  int get hashCode => Object.hash(
        id,
        userId,
        currentPoints,
        status,
        rejectionReason,
        createdAt,
      );
}
