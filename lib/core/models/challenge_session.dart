/// `public.challenge_sessions` row (migration 0061). One PIN-joinable,
/// host-commenced synchronized exam session.
final class ChallengeSession {
  const ChallengeSession({
    required this.id,
    required this.pinCode,
    required this.hostUserId,
    this.testId,
    required this.title,
    required this.subject,
    required this.durationMinutes,
    required this.status,
    this.commenceAt,
    this.concludedAt,
    required this.createdAt,
  });

  final String id;
  final String pinCode;
  final String hostUserId;
  final String? testId;
  final String title;
  final String subject;
  final int durationMinutes;

  /// 'waiting_room' | 'commenced' | 'concluded' | 'abandoned'.
  final String status;
  final DateTime? commenceAt;
  final DateTime? concludedAt;
  final DateTime createdAt;

  bool get isWaitingRoom => status == 'waiting_room';
  bool get isCommenced => status == 'commenced';
  bool get isConcluded => status == 'concluded';

  bool isHost(String? userId) => userId != null && userId == hostUserId;

  factory ChallengeSession.fromJson(Map<String, dynamic> json) {
    return ChallengeSession(
      id: json['id'] as String,
      pinCode: json['pin_code'] as String,
      hostUserId: json['host_user_id'] as String,
      testId: json['test_id'] as String?,
      title: json['title'] as String? ?? 'Academic Peer Challenge',
      subject: json['subject'] as String? ?? 'General Studies',
      durationMinutes: (json['duration_minutes'] as num?)?.toInt() ?? 30,
      status: json['status'] as String? ?? 'waiting_room',
      commenceAt: json['commence_at'] != null
          ? DateTime.parse(json['commence_at'] as String)
          : null,
      concludedAt: json['concluded_at'] != null
          ? DateTime.parse(json['concluded_at'] as String)
          : null,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
    );
  }
}

/// `public.challenge_participants` row — one candidate's roll-call + result.
final class ChallengeParticipant {
  const ChallengeParticipant({
    required this.id,
    required this.sessionId,
    required this.userId,
    required this.candidateName,
    this.candidateCode,
    this.avatarUrl,
    required this.isHost,
    this.attemptId,
    this.score,
    this.accuracy,
    this.timeTakenSeconds,
    this.submittedAt,
    required this.joinedAt,
  });

  final String id;
  final String sessionId;
  final String userId;
  final String candidateName;
  final String? candidateCode;
  final String? avatarUrl;
  final bool isHost;
  final String? attemptId;
  final double? score;
  final double? accuracy;
  final int? timeTakenSeconds;
  final DateTime? submittedAt;
  final DateTime joinedAt;

  bool get hasSubmitted => submittedAt != null;

  factory ChallengeParticipant.fromJson(Map<String, dynamic> json) {
    return ChallengeParticipant(
      id: json['id'] as String,
      sessionId: json['session_id'] as String,
      userId: json['user_id'] as String,
      candidateName: json['candidate_name'] as String? ?? 'Candidate',
      candidateCode: json['candidate_code'] as String?,
      avatarUrl: json['avatar_url'] as String?,
      isHost: json['is_host'] as bool? ?? false,
      attemptId: json['attempt_id'] as String?,
      score: (json['score'] as num?)?.toDouble(),
      accuracy: (json['accuracy'] as num?)?.toDouble(),
      timeTakenSeconds: (json['time_taken_seconds'] as num?)?.toInt(),
      submittedAt: json['submitted_at'] != null
          ? DateTime.parse(json['submitted_at'] as String)
          : null,
      joinedAt: json['joined_at'] != null
          ? DateTime.parse(json['joined_at'] as String)
          : DateTime.now(),
    );
  }
}

/// One ranked row from `rpc_get_challenge_merit_list`.
final class ChallengeMeritRow {
  const ChallengeMeritRow({
    required this.rank,
    required this.candidateName,
    this.candidateCode,
    this.avatarUrl,
    required this.score,
    required this.accuracy,
    required this.timeTakenSeconds,
  });

  final int rank;
  final String candidateName;
  final String? candidateCode;
  final String? avatarUrl;
  final double score;
  final double accuracy;
  final int timeTakenSeconds;

  factory ChallengeMeritRow.fromJson(Map<String, dynamic> json) {
    return ChallengeMeritRow(
      rank: (json['rank'] as num).toInt(),
      candidateName: json['candidate_name'] as String? ?? 'Candidate',
      candidateCode: json['candidate_code'] as String?,
      avatarUrl: json['avatar_url'] as String?,
      score: (json['score'] as num?)?.toDouble() ?? 0,
      accuracy: (json['accuracy'] as num?)?.toDouble() ?? 0,
      timeTakenSeconds: (json['time_taken_seconds'] as num?)?.toInt() ?? 0,
    );
  }
}
