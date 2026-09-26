import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../errors/app_error.dart';
import '../logging/app_logger.dart';
import '../models/profile.dart';
import '../models/verification_request.dart';
import 'supabase_service.dart';

enum ProfileStatus { initial, loading, loaded, error, empty }

final class ProfileService {
  ProfileService._();

  static final StreamController<ProfileStatus> _statusController =
      StreamController<ProfileStatus>.broadcast();

  static Stream<ProfileStatus> get statusStream => _statusController.stream;

  static ProfileStatus _currentStatus = ProfileStatus.initial;
  static ProfileStatus get currentStatus => _currentStatus;

  static Profile? _currentProfile;
  static Profile? get currentProfile => _currentProfile;

  static SupabaseQueryBuilder get _db =>
      SupabaseService.client.from('profiles');

  static Future<void> loadProfile() async {
    final userId = SupabaseService.client.auth.currentUser?.id;
    if (userId == null) {
      _updateStatus(ProfileStatus.empty);
      _currentProfile = null;
      return;
    }

    _updateStatus(ProfileStatus.loading);

    try {
      final response = await _db.select().eq('id', userId).maybeSingle();

      if (response == null) {
        AppLogger.info('No profile found, attempting to ensure profile...');
        await _ensureProfile(userId);
        return;
      }

      _currentProfile = Profile.fromJson(response);
      _updateStatus(ProfileStatus.loaded);
      AppLogger.info(
        'Profile loaded: ${_currentProfile!.studentCode ?? "no student code"}',
      );
    } catch (e) {
      AppLogger.error('Failed to load profile: $e');
      _currentProfile = null;
      _updateStatus(ProfileStatus.error);
      if (e is AppError) rethrow;
      throw const DataError(
        message: 'Failed to load profile. Please try again.',
      );
    }
  }

  static Future<void> _ensureProfile(String userId) async {
    try {
      await SupabaseService.client.rpc('fn_ensure_profile');
      AppLogger.info('fn_ensure_profile called, reloading...');

      final response = await _db.select().eq('id', userId).maybeSingle();

      if (response != null) {
        _currentProfile = Profile.fromJson(response);
        _updateStatus(ProfileStatus.loaded);
        AppLogger.info('Profile ensured and loaded.');
      } else {
        _currentProfile = null;
        _updateStatus(ProfileStatus.empty);
        AppLogger.warning('Profile still not found after ensure.');
      }
    } catch (e) {
      AppLogger.error('Failed to ensure profile: $e');
      _currentProfile = null;
      _updateStatus(ProfileStatus.error);
      throw const DataError(
        message: 'Failed to create profile. Please try again.',
      );
    }
  }

  static Future<void> updateProfile({
    String? fullName,
    String? bio,
    String? mobile,
    String? timezone,
    List<String>? examTargets,
    DateTime? dateOfBirth,
    Map<String, String>? socialLinks,
  }) async {
    final userId = SupabaseService.client.auth.currentUser?.id;
    if (userId == null) {
      throw const AuthError(
        message: 'You must be signed in to update your profile.',
      );
    }

    if (_currentProfile == null) {
      throw const DataError(message: 'No profile loaded. Please reload.');
    }

    try {
      final updates = <String, dynamic>{};
      if (fullName != null) updates['full_name'] = fullName;
      if (bio != null) updates['bio'] = bio;
      if (mobile != null) updates['mobile'] = mobile;
      if (timezone != null) updates['timezone'] = timezone;
      if (examTargets != null) updates['exam_targets'] = examTargets;
      if (dateOfBirth != null) {
        updates['date_of_birth'] = dateOfBirth.toIso8601String().substring(
          0,
          10,
        );
      }
      if (socialLinks != null) updates['social_links'] = socialLinks;

      if (updates.isEmpty) return;

      await _db.update(updates).eq('id', userId);

      _currentProfile = _currentProfile!.copyWith(
        fullName: fullName ?? _currentProfile!.fullName,
        bio: bio ?? _currentProfile!.bio,
        mobile: mobile ?? _currentProfile!.mobile,
        timezone: timezone ?? _currentProfile!.timezone,
        examTargets: examTargets ?? _currentProfile!.examTargets,
        dateOfBirth: dateOfBirth ?? _currentProfile!.dateOfBirth,
        socialLinks: socialLinks ?? _currentProfile!.socialLinks,
      );

      AppLogger.info('Profile updated.');
    } on PostgrestException catch (e) {
      AppLogger.error('Profile update PostgrestException: ${e.message}');
      throw DataError(message: _mapProfileErrorMessage(e.message));
    } catch (e) {
      if (e is AppError) rethrow;
      AppLogger.error('Profile update unexpected error: $e');
      throw const DataError(
        message: 'Failed to update profile. Please try again.',
      );
    }
  }

  /// Persists a new (or cleared, via null) avatar URL. Separate from
  /// [updateProfile] so the avatar upload/delete flow — which already
  /// wrote the Storage object before calling this — only ever touches the
  /// one column it needs to.
  static Future<void> setAvatarUrl(String? avatarUrl) async {
    final userId = SupabaseService.client.auth.currentUser?.id;
    if (userId == null) {
      throw const AuthError(
        message: 'You must be signed in to update your profile.',
      );
    }
    if (_currentProfile == null) {
      throw const DataError(message: 'No profile loaded. Please reload.');
    }

    try {
      await _db.update({'avatar_url': avatarUrl}).eq('id', userId);
      _currentProfile = _currentProfile!.copyWith(
        avatarUrl: avatarUrl,
        clearAvatar: avatarUrl == null,
      );
      AppLogger.info('Profile avatar_url updated.');
    } on PostgrestException catch (e) {
      AppLogger.error('Avatar URL update PostgrestException: ${e.message}');
      throw DataError(message: _mapProfileErrorMessage(e.message));
    } catch (e) {
      if (e is AppError) rethrow;
      AppLogger.error('Avatar URL update unexpected error: $e');
      throw const DataError(
        message: 'Failed to update your photo. Please try again.',
      );
    }
  }

  static void updatePointsLocally({int? totalPoints, int? weeklyPoints}) {
    if (_currentProfile != null) {
      _currentProfile = _currentProfile!.copyWith(
        totalPoints: totalPoints ?? _currentProfile!.totalPoints,
        weeklyPoints: weeklyPoints ?? _currentProfile!.weeklyPoints,
      );
      _updateStatus(ProfileStatus.loaded);
    }
  }

  // ── Blue-tick verification (0058) ──

  /// Applies for blue-tick verification via `rpc_request_verification`.
  /// The RPC itself re-checks the >= 1000-point threshold and the
  /// one-pending-request rule server-side (`INSUFFICIENT_POINTS` /
  /// `REQUEST_ALREADY_PENDING`) — this call never assumes eligibility.
  static Future<VerificationRequest> applyForBlueTick() async {
    final userId = SupabaseService.client.auth.currentUser?.id;
    if (userId == null) {
      throw const AuthError(
        message: 'You must be signed in to apply for verification.',
      );
    }
    try {
      await SupabaseService.client.rpc('rpc_request_verification');
      final status = await fetchVerificationStatus();
      if (status == null) {
        throw const DataError(
          message: 'Verification request was not recorded. Please try again.',
        );
      }
      return status;
    } on PostgrestException catch (e) {
      AppLogger.error('rpc_request_verification failed: ${e.message}');
      throw DataError(message: _mapVerificationErrorMessage(e.message));
    } catch (e) {
      if (e is AppError) rethrow;
      AppLogger.error('rpc_request_verification unexpected error: $e');
      throw const DataError(
        message:
            'Could not submit your verification request. Please try again.',
      );
    }
  }

  /// The caller's own most recent verification request, or null if they've
  /// never applied. RLS on `verification_requests` returns only the
  /// caller's own rows (or every row, for the app owner) — never guessed.
  static Future<VerificationRequest?> fetchVerificationStatus() async {
    final userId = SupabaseService.client.auth.currentUser?.id;
    if (userId == null) return null;
    try {
      final row = await SupabaseService.client
          .from('verification_requests')
          .select()
          .eq('user_id', userId)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();
      return row == null ? null : VerificationRequest.fromJson(row);
    } catch (e) {
      AppLogger.warning('fetchVerificationStatus failed: $e');
      return null;
    }
  }

  /// Fetches pending verification requests with joined profile details.
  /// Only returns records when called by an owner due to Supabase RLS.
  static Future<List<Map<String, dynamic>>>
  fetchPendingVerificationRequests() async {
    try {
      final res = await SupabaseService.client
          .from('verification_requests')
          .select(
            '*, profiles:user_id(id, full_name, avatar_url, student_code, total_points, app_role)',
          )
          .eq('status', 'pending')
          .order('created_at', ascending: false);
      return (res as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    } catch (e) {
      AppLogger.warning('fetchPendingVerificationRequests failed: $e');
      return [];
    }
  }

  /// Approves a pending blue tick verification request via `rpc_approve_blue_tick`.
  static Future<void> approveVerificationRequest(String requestId) async {
    try {
      await SupabaseService.client.rpc(
        'rpc_approve_blue_tick',
        params: {'p_request_id': requestId},
      );
    } catch (e) {
      AppLogger.error('approveVerificationRequest failed: $e');
      throw const DataError(
        message:
            'Failed to approve request. Ensure you have founder permissions.',
      );
    }
  }

  /// Rejects a pending blue tick verification request via `rpc_reject_blue_tick`.
  static Future<void> rejectVerificationRequest(
    String requestId,
    String reason,
  ) async {
    try {
      await SupabaseService.client.rpc(
        'rpc_reject_blue_tick',
        params: {'p_request_id': requestId, 'p_reason': reason},
      );
    } catch (e) {
      AppLogger.error('rejectVerificationRequest failed: $e');
      throw const DataError(
        message:
            'Failed to decline request. Ensure you have founder permissions.',
      );
    }
  }

  /// Runs the badge expiry sweep via `rpc_check_and_revoke_badges`.
  static Future<int> checkAndRevokeBadges() async {
    try {
      final res = await SupabaseService.client.rpc(
        'rpc_check_and_revoke_badges',
      );
      return (res as num?)?.toInt() ?? 0;
    } catch (e) {
      AppLogger.warning('checkAndRevokeBadges error: $e');
      return 0;
    }
  }

  static SupabaseClient get _supabase => SupabaseService.client;

  /// Promotes a user to a new role via `rpc_promote_user`.
  static Future<Map<String, dynamic>> promoteUser({
    required String studentCode,
    required String newRole, // 'core_team', 'scholar', 'aspirant'
    String? roleTitle,
    bool grantVip = true,
    bool grantBlueTick = true,
  }) async {
    final res = await _supabase.rpc(
      'rpc_promote_user',
      params: {
        'p_target_student_code': studentCode.trim().toUpperCase(),
        'p_new_role': newRole,
        'p_role_title': roleTitle,
        'p_grant_vip': grantVip,
        'p_grant_blue_tick': grantBlueTick,
      },
    );
    return Map<String, dynamic>.from(res as Map);
  }

  static String _mapVerificationErrorMessage(String message) {
    final lower = message.toLowerCase();
    if (lower.contains('insufficient_points')) {
      return 'You need at least 1000 points to apply for verification.';
    }
    if (lower.contains('request_already_pending')) {
      return 'You already have a pending verification request.';
    }
    return 'Could not submit your verification request. Please try again.';
  }

  // ── Follow graph (0058 user_follows) ──

  /// Inserts `{follower_id: auth.uid(), following_id: targetUserId}`. RLS
  /// "follow others" enforces `follower_id = auth.uid()`; the unique pair
  /// constraint makes a repeat follow a no-op rather than an error.
  static Future<void> followUser(String targetUserId) async {
    final userId = SupabaseService.client.auth.currentUser?.id;
    if (userId == null) {
      throw const AuthError(
        message: 'You must be signed in to follow other students.',
      );
    }
    if (userId == targetUserId) {
      throw const DataError(message: 'You cannot follow yourself.');
    }
    try {
      await SupabaseService.client
          .from('user_follows')
          .upsert(
            {'follower_id': userId, 'following_id': targetUserId},
            onConflict: 'follower_id,following_id',
            ignoreDuplicates: true,
          );
    } on PostgrestException catch (e) {
      AppLogger.error('followUser failed: ${e.message}');
      throw const DataError(
        message: 'Could not follow this student. Please try again.',
      );
    } catch (e) {
      if (e is AppError) rethrow;
      AppLogger.error('followUser unexpected error: $e');
      throw const DataError(
        message: 'Could not follow this student. Please try again.',
      );
    }
  }

  /// Deletes the caller's own follow edge to [targetUserId]. RLS "unfollow
  /// others" enforces `follower_id = auth.uid()` — 0 rows deleted is not an
  /// error (idempotent: unfollowing someone you don't follow is a no-op).
  static Future<void> unfollowUser(String targetUserId) async {
    final userId = SupabaseService.client.auth.currentUser?.id;
    if (userId == null) {
      throw const AuthError(
        message: 'You must be signed in to unfollow other students.',
      );
    }
    try {
      await SupabaseService.client
          .from('user_follows')
          .delete()
          .eq('follower_id', userId)
          .eq('following_id', targetUserId);
    } on PostgrestException catch (e) {
      AppLogger.error('unfollowUser failed: ${e.message}');
      throw const DataError(
        message: 'Could not unfollow this student. Please try again.',
      );
    } catch (e) {
      if (e is AppError) rethrow;
      AppLogger.error('unfollowUser unexpected error: $e');
      throw const DataError(
        message: 'Could not unfollow this student. Please try again.',
      );
    }
  }

  static void _updateStatus(ProfileStatus status) {
    _currentStatus = status;
    _statusController.add(status);
  }

  static void reset() {
    _currentProfile = null;
    _currentStatus = ProfileStatus.initial;
    _statusController.add(ProfileStatus.initial);
  }

  static String _mapProfileErrorMessage(String message) {
    final lower = message.toLowerCase();
    if (lower.contains('permission') || lower.contains('denied')) {
      return 'You do not have permission to update this profile.';
    }
    if (lower.contains('not found')) {
      return 'Profile not found. Please restart the app.';
    }
    if (lower.contains('network') || lower.contains('timeout')) {
      return 'Network error. Please check your connection and try again.';
    }
    return 'Failed to update profile. Please try again.';
  }

  static void dispose() {
    _statusController.close();
  }

  /// Seeds [currentProfile] directly, bypassing Supabase — for widget/unit
  /// tests that need a loaded profile without a real backend. Matches the
  /// existing [SupabaseService.setClientForTesting] convention.
  @visibleForTesting
  static void setProfileForTesting(Profile? profile) {
    _currentProfile = profile;
    _currentStatus = profile != null
        ? ProfileStatus.loaded
        : ProfileStatus.initial;
  }
}
