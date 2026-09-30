import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/errors/app_error.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/services/supabase_service.dart';
import '../domain/leaderboard_entry.dart';

/// Data access for migration 0074 (`xp_gamification_and_leaderboard`).
/// Deliberately does NOT wrap `rpc_award_study_points`,
/// `rpc_submit_and_score_test` or the referral RPCs — those already exist
/// and are already called from their own features; duplicating them here
/// would risk a second, uncapped award path for the same activity.
class GamificationRepository {
  const GamificationRepository();

  SupabaseClient get _client => SupabaseService.client;

  /// Weekly XP leaderboard among the caller + everyone they follow.
  Future<List<LeaderboardEntry>> fetchFollowingWeeklyLeaderboard() async {
    try {
      final rows = await _client.rpc('rpc_get_following_weekly_leaderboard');
      return (rows as List)
          .map((r) => LeaderboardEntry.fromJson(Map<String, dynamic>.from(r as Map)))
          .toList();
    } on PostgrestException catch (e) {
      AppLogger.error('fetchFollowingWeeklyLeaderboard failed: ${e.message}');
      throw const DataError(message: 'Could not load the leaderboard. Please try again.');
    }
  }

  /// Pays the one-time +20 XP for a specific completed routine session.
  /// Returns the real points awarded (0 if already paid, capped, or the
  /// log isn't actually COMPLETED yet) — never assumed by the caller.
  Future<int> awardRoutineSessionPoints({
    required String routineId,
    required String logDate,
  }) async {
    try {
      final res = await _client.rpc('rpc_award_routine_session_points', params: {
        'p_routine_id': routineId,
        'p_log_date': logDate,
      });
      final data = Map<String, dynamic>.from(res as Map);
      return (data['points_awarded'] as num?)?.toInt() ?? 0;
    } catch (e) {
      AppLogger.warning('awardRoutineSessionPoints failed: $e');
      return 0;
    }
  }

  /// Claims today's streak bonus (+10 XP) if not already claimed. Returns
  /// (pointsAwarded, streakLength); (0, 0) on any failure or no activity yet.
  Future<({int pointsAwarded, int streak})> claimDailyStreak() async {
    try {
      final res = await _client.rpc('rpc_claim_daily_streak');
      final data = Map<String, dynamic>.from(res as Map);
      return (
        pointsAwarded: (data['points_awarded'] as num?)?.toInt() ?? 0,
        streak: (data['streak'] as num?)?.toInt() ?? 0,
      );
    } catch (e) {
      AppLogger.warning('claimDailyStreak failed: $e');
      return (pointsAwarded: 0, streak: 0);
    }
  }

  /// Read-only current streak length (no claim/payment) for badge progress.
  Future<int> fetchCurrentStreak() async {
    try {
      final res = await _client.rpc('rpc_get_current_streak');
      return (res as num?)?.toInt() ?? 0;
    } catch (e) {
      AppLogger.warning('fetchCurrentStreak failed: $e');
      return 0;
    }
  }

  /// Whether the caller has ever posted a result with >= [pct]% accuracy.
  Future<bool> hasHighAccuracyResult({num pct = 80}) async {
    try {
      final res = await _client.rpc('rpc_has_high_accuracy_result', params: {'p_pct': pct});
      return res as bool? ?? false;
    } catch (e) {
      AppLogger.warning('hasHighAccuracyResult failed: $e');
      return false;
    }
  }

  /// Whether the caller has ever completed a test attempt at all (First
  /// Test Attempted badge) — a plain, RLS-scoped count off `results`.
  Future<bool> hasAnyResult() async {
    try {
      final userId = _client.auth.currentUser?.id;
      if (userId == null) return false;
      final count = await _client.from('results').count(CountOption.exact).eq('user_id', userId);
      return count > 0;
    } catch (e) {
      AppLogger.warning('hasAnyResult failed: $e');
      return false;
    }
  }
}
