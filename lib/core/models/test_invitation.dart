final class TestInvitation {
  const TestInvitation({
    required this.id,
    required this.testId,
    required this.userId,
    required this.status,
    required this.invitedAt,
    this.respondedAt,
  });

  final String id;
  final String testId;
  final String userId;
  final String status;
  final DateTime invitedAt;
  final DateTime? respondedAt;

  bool get isPending => status == 'pending';
  bool get isAccepted => status == 'accepted';
  bool get isDeclined => status == 'declined';

  factory TestInvitation.fromJson(Map<String, dynamic> json) {
    return TestInvitation(
      id: json['id'] as String,
      testId: json['test_id'] as String,
      userId: json['user_id'] as String,
      status: (json['status'] as String?) ?? 'pending',
      invitedAt: DateTime.parse(json['invited_at'] as String),
      respondedAt: json['responded_at'] != null
          ? DateTime.parse(json['responded_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'test_id': testId,
      'user_id': userId,
      'status': status,
      'invited_at': invitedAt.toIso8601String(),
      'responded_at': respondedAt?.toIso8601String(),
    };
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TestInvitation &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          testId == other.testId &&
          userId == other.userId;

  @override
  int get hashCode => Object.hash(id, testId, userId);
}
