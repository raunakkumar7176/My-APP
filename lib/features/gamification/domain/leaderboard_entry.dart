/// One row of `rpc_get_following_weekly_leaderboard()` — the caller plus
/// everyone they follow, ranked by this week's `point_transactions` sum.
final class LeaderboardEntry {
  const LeaderboardEntry({
    required this.userId,
    required this.fullName,
    required this.weeklyXp,
    required this.rank,
    required this.isCurrentUser,
    this.studentCode,
    this.avatarUrl,
  });

  final String userId;
  final String fullName;
  final String? studentCode;
  final String? avatarUrl;
  final int weeklyXp;
  final int rank;
  final bool isCurrentUser;

  factory LeaderboardEntry.fromJson(Map<String, dynamic> json) => LeaderboardEntry(
        userId: json['user_id'] as String,
        fullName: (json['full_name'] as String?) ?? 'Student',
        studentCode: json['student_code'] as String?,
        avatarUrl: json['avatar_url'] as String?,
        weeklyXp: (json['weekly_xp'] as num?)?.toInt() ?? 0,
        rank: (json['rank'] as num?)?.toInt() ?? 0,
        isCurrentUser: json['is_current_user'] as bool? ?? false,
      );
}
