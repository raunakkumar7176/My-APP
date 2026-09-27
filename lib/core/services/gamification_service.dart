import 'dart:async';

import 'package:flutter/foundation.dart';

import '../logging/app_logger.dart';
import 'profile_service.dart';
import 'supabase_service.dart';

/// Models an entry on the weekly cohort leaderboard.
class CohortLeaderboardEntry {
  const CohortLeaderboardEntry({
    required this.userId,
    required this.fullName,
    required this.studentCode,
    required this.avatarUrl,
    required this.weeklyPoints,
    required this.totalPoints,
    required this.rank,
    this.targetExams = const [],
  });

  final String userId;
  final String fullName;
  final String studentCode;
  final String? avatarUrl;
  final int weeklyPoints;
  final int totalPoints;
  final int rank;
  final List<String> targetExams;

  factory CohortLeaderboardEntry.fromJson(Map<String, dynamic> json, int rank) {
    final rawTargets = json['exam_targets'];
    List<String> targets = [];
    if (rawTargets is List) {
      targets = rawTargets.map((e) => e.toString()).toList();
    }

    return CohortLeaderboardEntry(
      userId: (json['user_id'] ?? json['id'] ?? '') as String,
      fullName: (json['full_name'] as String?)?.trim().isNotEmpty == true
          ? (json['full_name'] as String)
          : 'Anonymous Student',
      studentCode: (json['student_code'] as String?) ?? 'MP-STUDENT',
      avatarUrl: json['avatar_url'] as String?,
      weeklyPoints: (json['weekly_points'] as num?)?.toInt() ?? 0,
      totalPoints: (json['total_points'] as num?)?.toInt() ?? 0,
      rank: rank,
      targetExams: targets,
    );
  }
}

/// Models a student found by searching their unique Student Code (e.g., MP-84920).
class StudentSearchResult {
  const StudentSearchResult({
    required this.id,
    required this.fullName,
    required this.studentCode,
    required this.avatarUrl,
    required this.bio,
    required this.totalPoints,
    required this.weeklyPoints,
    required this.examTargets,
    this.verifiedBadge = false,
    this.appRole = 'aspirant',
  });

  final String id;
  final String fullName;
  final String studentCode;
  final String? avatarUrl;
  final String? bio;
  final int totalPoints;
  final int weeklyPoints;
  final List<String> examTargets;
  final bool verifiedBadge;
  final String appRole;

  String get initials {
    final parts = fullName.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }

  factory StudentSearchResult.fromJson(Map<String, dynamic> json) {
    final rawTargets = json['exam_targets'];
    List<String> targets = [];
    if (rawTargets is List) {
      targets = rawTargets.map((e) => e.toString()).toList();
    }

    return StudentSearchResult(
      id: (json['id'] ?? '') as String,
      fullName: (json['full_name'] as String?)?.trim().isNotEmpty == true
          ? (json['full_name'] as String)
          : 'Anonymous Student',
      studentCode: (json['student_code'] as String?) ?? '',
      avatarUrl: json['avatar_url'] as String?,
      bio: json['bio'] as String?,
      totalPoints: (json['total_points'] as num?)?.toInt() ?? 0,
      weeklyPoints: (json['weekly_points'] as num?)?.toInt() ?? 0,
      examTargets: targets,
      verifiedBadge: (json['verified_badge'] as bool?) ?? false,
      appRole: (json['app_role'] as String?) ?? 'aspirant',
    );
  }
}

/// Global Gamification Service orchestrating points awarding, real-time reflection,
/// weekly cohort leaderboard fetching, and student lookup by Unique Student Code.
final class GamificationService {
  GamificationService._();

  // Cache to prevent duplicate points within the current session
  static final Set<String> _awardedItems = <String>{};

  /// Award +10 points for completing theory/topic.
  static Future<int?> awardTopicCompleted(String topicId) async {
    final cacheKey = 'topic_$topicId';
    if (_awardedItems.contains(cacheKey)) return null;
    _awardedItems.add(cacheKey);

    return _awardPoints(10, 'topic_completed');
  }

  /// Award +1 point for attempting a practice question.
  static Future<int?> awardPracticeQuestionAttempted(String questionId) async {
    final cacheKey = 'practice_$questionId';
    if (_awardedItems.contains(cacheKey)) return null;
    _awardedItems.add(cacheKey);

    return _awardPoints(1, 'practice_attempt');
  }

  /// Award +1 point for a CORRECT answer in Chapter Practice (interactive
  /// quiz mode) — distinct from [awardPracticeQuestionAttempted], which
  /// awards on any attempt regardless of correctness. Deduped per question
  /// per session, same as the other award methods.
  static Future<int?> awardPracticeCorrectAnswer(String questionId) async {
    final cacheKey = 'practice_correct_$questionId';
    if (_awardedItems.contains(cacheKey)) return null;
    _awardedItems.add(cacheKey);

    return awardStudyPoints(1, 'practice_correct');
  }

  /// Generic public entry point to award points for any reason, wrapping
  /// the RPC call. Callers that need their own dedup key (or none) can use
  /// this directly instead of one of the named convenience methods above.
  static Future<int?> awardStudyPoints(int points, String reason) =>
      _awardPoints(points, reason);

  /// Core helper to invoke the atomic database RPC and update local state
  /// immediately. [activityType] becomes the RPC's `p_reason` — it also
  /// drives the server's daily cap category (any reason matching
  /// `fn_point_reason_is_practice` gets the 30/day practice cap; everything
  /// else gets the 25/day theory cap; see `rpc_award_study_points` in
  /// `0058_gamification_verification_social_v1.sql`).
  static Future<int?> _awardPoints(int points, String activityType) async {
    if (!SupabaseService.isInitialized) return null;
    final userId = SupabaseService.client.auth.currentUser?.id;
    if (userId == null || points <= 0) return null;

    // Immediately update local profile optimistically
    final currentProfile = ProfileService.currentProfile;
    if (currentProfile != null) {
      ProfileService.updatePointsLocally(
        totalPoints: currentProfile.totalPoints + points,
        weeklyPoints: currentProfile.weeklyPoints + points,
      );
    }

    try {
      // The live RPC signature is `rpc_award_study_points(p_points int,
      // p_reason text)` — it takes no user id (it awards to auth.uid()
      // server-side) and does not return `weekly_points` (that column was
      // dropped in 0059; weekly points are now RPC-computed only, via
      // rpc_get_weekly_cohort_leaderboard / rpc_search_student_by_code).
      final res = await SupabaseService.client.rpc(
        'rpc_award_study_points',
        params: {'p_points': points, 'p_reason': activityType},
      );

      AppLogger.info(
        'Awarded $points study points for $activityType. Response: $res',
      );

      // If RPC returned an updated total, sync with precision.
      if (res is Map<String, dynamic>) {
        final total = (res['total_points'] as num?)?.toInt();
        final weekly = (res['weekly_points'] as num?)?.toInt();
        if (total != null || weekly != null) {
          ProfileService.updatePointsLocally(
            totalPoints: total,
            weeklyPoints: weekly,
          );
        }
      }
      return points;
    } catch (e) {
      AppLogger.warning(
        'rpc_award_study_points failed (offline or pending migration): $e',
      );
      // Return points since local optimistic update is active
      return points;
    }
  }

  /// Searches for a student profile by their unique Student ID (e.g. "MP-84920").
  static Future<StudentSearchResult?> searchStudentByCode(String code) async {
    final trimmed = code.trim().toUpperCase();
    if (trimmed.isEmpty) return null;
    if (trimmed.isEmpty || !SupabaseService.isInitialized) return null;

    try {
      final res = await SupabaseService.client.rpc(
        'rpc_search_student_by_code',
        params: {'p_student_code': trimmed},
      );

      if (res is List && res.isNotEmpty) {
        return StudentSearchResult.fromJson(res.first as Map<String, dynamic>);
      } else if (res is Map<String, dynamic>) {
        return StudentSearchResult.fromJson(res);
      }
      return null;
    } catch (e) {
      AppLogger.warning(
        'rpc_search_student_by_code failed, falling back to direct query: $e',
      );
      try {
        final queryRes = await SupabaseService.client
            .from('profiles')
            .select(
              'id, full_name, student_code, avatar_url, bio, total_points, weekly_points, exam_targets',
            )
            .eq('student_code', trimmed)
            .maybeSingle();

        if (queryRes != null) {
          return StudentSearchResult.fromJson(queryRes);
        }
      } catch (fallbackError) {
        AppLogger.error('Fallback student search failed: $fallbackError');
      }
      return null;
    }
  }

  /// Fetches weekly leaderboard for a cohort (or global cohort if [groupId] is null).
  static Future<List<CohortLeaderboardEntry>> fetchWeeklyCohortLeaderboard({
    String? groupId,
    int limit = 50,
  }) async {
    if (!SupabaseService.isInitialized) return const [];
    try {
      final res = await SupabaseService.client.rpc(
        'rpc_get_weekly_cohort_leaderboard',
        params: {'p_group_id': groupId, 'p_limit': limit},
      );

      if (res is List) {
        final list = <CohortLeaderboardEntry>[];
        for (var i = 0; i < res.length; i++) {
          final item = res[i] as Map<String, dynamic>;
          list.add(CohortLeaderboardEntry.fromJson(item, i + 1));
        }
        return list;
      }
      return const [];
    } catch (e) {
      AppLogger.warning(
        'rpc_get_weekly_cohort_leaderboard failed, falling back: $e',
      );
      try {
        // Fallback to direct profiles table order by weekly_points DESC
        final queryRes = await SupabaseService.client
            .from('profiles')
            .select(
              'id, full_name, student_code, avatar_url, weekly_points, total_points, exam_targets',
            )
            .order('weekly_points', ascending: false)
            .limit(limit);

        final list = <CohortLeaderboardEntry>[];
        for (var i = 0; i < queryRes.length; i++) {
          list.add(CohortLeaderboardEntry.fromJson(queryRes[i], i + 1));
        }
        return list;
      } catch (fallbackError) {
        AppLogger.error('Fallback leaderboard failed: $fallbackError');
      }
      return const [];
    }
  }

  @visibleForTesting
  static void clearAwardedCacheForTesting() {
    _awardedItems.clear();
  }
}
