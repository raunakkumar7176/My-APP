import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../errors/app_error.dart';
import '../logging/app_logger.dart';
import '../models/profile.dart';
import '../models/profile_connection.dart';
import '../models/referral_status.dart';
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
    bool? showAgeBadge,
    String? groupInvitePolicy,
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
      if (showAgeBadge != null) updates['show_age_badge'] = showAgeBadge;
      if (groupInvitePolicy != null) updates['group_invite_policy'] = groupInvitePolicy;

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
        showAgeBadge: showAgeBadge ?? _currentProfile!.showAgeBadge,
        groupInvitePolicy: groupInvitePolicy ?? _currentProfile!.groupInvitePolicy,
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

  /// Records a real account-deletion request via `rpc_request_account_deletion`
  /// (migration 0084) — an owner-reviewed table, never an unattended
  /// auto-delete. Returns true if a request now exists (freshly created or
  /// already pending); throws on failure rather than claiming success.
  static Future<bool> requestAccountDeletion() async {
    final userId = SupabaseService.client.auth.currentUser?.id;
    if (userId == null) {
      throw const AuthError(message: 'You must be signed in to request account deletion.');
    }
    try {
      final res = await SupabaseService.client.rpc('rpc_request_account_deletion');
      final data = Map<String, dynamic>.from(res as Map);
      return data['status'] == 'pending' || data['status'] == 'already_pending';
    } on PostgrestException catch (e) {
      AppLogger.error('requestAccountDeletion failed: ${e.message}');
      throw const DataError(message: 'Could not submit your deletion request. Please try again.');
    } catch (e) {
      if (e is AppError) rethrow;
      AppLogger.error('requestAccountDeletion unexpected error: $e');
      throw const DataError(message: 'Could not submit your deletion request. Please try again.');
    }
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

  /// Everyone who follows [userId], via `rpc_get_followers` (migration
  /// 0065) — a SECURITY DEFINER RPC returning only the public identity
  /// fields (never mobile/bio/date_of_birth), plus whether the CALLING
  /// user already follows each listed person. `is_following` on each row
  /// reflects the CALLING user, not [userId].
  static Future<List<ProfileConnection>> getFollowers(String userId) async {
    try {
      final rows = await SupabaseService.client.rpc(
        'rpc_get_followers',
        params: {'p_user_id': userId},
      );
      return (rows as List)
          .map((r) => ProfileConnection.fromJson(Map<String, dynamic>.from(r as Map)))
          .toList();
    } on PostgrestException catch (e) {
      AppLogger.error('getFollowers failed: ${e.message}');
      throw const DataError(message: 'Could not load followers. Please try again.');
    } catch (e) {
      if (e is AppError) rethrow;
      AppLogger.error('getFollowers unexpected error: $e');
      throw const DataError(message: 'Could not load followers. Please try again.');
    }
  }

  /// Everyone [userId] follows, via `rpc_get_following` (migration 0065).
  static Future<List<ProfileConnection>> getFollowing(String userId) async {
    try {
      final rows = await SupabaseService.client.rpc(
        'rpc_get_following',
        params: {'p_user_id': userId},
      );
      return (rows as List)
          .map((r) => ProfileConnection.fromJson(Map<String, dynamic>.from(r as Map)))
          .toList();
    } on PostgrestException catch (e) {
      AppLogger.error('getFollowing failed: ${e.message}');
      throw const DataError(message: 'Could not load following. Please try again.');
    } catch (e) {
      if (e is AppError) rethrow;
      AppLogger.error('getFollowing unexpected error: $e');
      throw const DataError(message: 'Could not load following. Please try again.');
    }
  }

  /// Follows or unfollows [targetUserId] depending on [currentlyFollowing],
  /// delegating to the existing, RLS-safe [followUser]/[unfollowUser].
  /// Named to match the Connections screen's optimistic-toggle button: the
  /// screen flips its own local state before this resolves and reverts it
  /// on failure — this method itself is a plain, non-optimistic network call.
  static Future<void> toggleFollow(
    String targetUserId, {
    required bool currentlyFollowing,
  }) {
    return currentlyFollowing ? unfollowUser(targetUserId) : followUser(targetUserId);
  }

  // ── Referral engine (0066 referral_records / rpc_apply_referral) ──

  static const _pendingReferralPrefsKey = 'pending_referral_code';

  /// Applies [code] (a referrer's `student_code`) for the CALLING user via
  /// `rpc_apply_referral`. Server-authoritative: the +50/+100 points and the
  /// self-referral/already-referred checks all happen inside the RPC — this
  /// only surfaces the result.
  static Future<ReferralApplyResult> applyReferralCode(String code) async {
    final userId = SupabaseService.client.auth.currentUser?.id;
    if (userId == null) {
      throw const AuthError(message: 'You must be signed in to use a referral code.');
    }
    try {
      final res = await SupabaseService.client.rpc(
        'rpc_claim_referral_reward',
        params: {'p_referral_code': code},
      );
      final data = Map<String, dynamic>.from(res as Map);
      return ReferralApplyResult.fromJson(data);
    } on PostgrestException catch (e) {
      AppLogger.error('applyReferralCode failed: ${e.message}');
      throw const DataError(message: 'Could not apply the referral code. Please try again.');
    } catch (e) {
      if (e is AppError) rethrow;
      AppLogger.error('applyReferralCode unexpected error: $e');
      throw const DataError(message: 'Could not apply the referral code. Please try again.');
    }
  }

  /// The caller's own referral summary via `rpc_get_my_referral_status`.
  static Future<ReferralStatus> getMyReferralStatus() async {
    try {
      final res = await SupabaseService.client.rpc('rpc_get_my_referral_status');
      return ReferralStatus.fromJson(Map<String, dynamic>.from(res as Map));
    } catch (e) {
      AppLogger.warning('getMyReferralStatus failed: $e');
      return const ReferralStatus(hasBeenReferred: false, referralCount: 0, pointsEarned: 0);
    }
  }

  /// Remembers a referral code entered at signup, before a session exists
  /// (email confirmation may still be pending). Applied automatically the
  /// next time a session becomes authenticated — see
  /// [tryApplyPendingReferral], called from `AuthService`.
  static Future<void> savePendingReferralCode(String code) async {
    final trimmed = code.trim();
    if (trimmed.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_pendingReferralPrefsKey, trimmed);
  }

  static final StreamController<ReferralApplyResult> _referralAppliedController =
      StreamController<ReferralApplyResult>.broadcast();

  /// Emits once whenever a pending referral code (entered at signup) is
  /// applied, success or failure — [AppShell] listens to this to show the
  /// celebratory dialog/snackbar, since [tryApplyPendingReferral] itself has
  /// no BuildContext.
  static Stream<ReferralApplyResult> get referralAppliedStream =>
      _referralAppliedController.stream;

  /// Best-effort, one-shot: applies a saved pending referral code (if any)
  /// now that a session exists, then clears it regardless of outcome — a
  /// bad/expired code must never retry forever on every future app launch.
  static Future<void> tryApplyPendingReferral() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final code = prefs.getString(_pendingReferralPrefsKey);
      if (code == null || code.isEmpty) return;
      await prefs.remove(_pendingReferralPrefsKey);
      final result = await applyReferralCode(code);
      _referralAppliedController.add(result);
      if (result.success) {
        AppLogger.info('Referral applied: +${result.pointsAwarded} points');
      } else {
        AppLogger.info('Referral not applied: ${result.error}');
      }
    } catch (e) {
      AppLogger.warning('tryApplyPendingReferral failed: $e');
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
    _referralAppliedController.close();
  }

  /// Offline/hermetic fallback ONLY — used when the real `profiles` row
  /// (app_role='owner') can't be read (no connection, not initialized, or
  /// no such row yet). Every stat is honest zero/empty, never a fabricated
  /// impressive number: showing "1240 Followers" for an account that may
  /// not even exist yet would be lying to whoever views it. `id` is a
  /// non-UUID sentinel by design — [ProfileScreen] uses it to hide the
  /// Follow button (there's no real row to follow yet).
  static Profile get fallbackFounderProfile => Profile(
    id: 'founder_official_uid',
    fullName: 'Founder',
    timezone: 'Asia/Kolkata',
    createdAt: DateTime(2026, 1, 1),
    studentCode: null,
    bio: 'Founder & Lead Architect of My Preparation.',
    mobile: '',
    examTargets: const [],
    totalPoints: 0,
    weeklyPoints: 0,
    appRole: AppRole.owner,
    isVip: false,
    verifiedBadge: false,
    dateOfBirth: null,
    socialLinks: const {},
    followersCount: 0,
    followingCount: 0,
  );

  /// Canonical UUID shape (8-4-4-4-12 hex groups). Anything else that is
  /// passed to [fetchProfileById] is treated as a `student_code`.
  static final RegExp _uuidPattern = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );

  /// Fetches a specific profile by EITHER of its identifiers: the user's
  /// UUID (`id`) or their shareable `student_code` (e.g. `MP-83921`).
  /// Returns [fallbackFounderProfile] if requesting the official founder
  /// and no remote record is found.
  ///
  /// Callers deep-link with a UUID (`/profile/<uuid>` from the Followers /
  /// Following lists, group rosters, search), but student codes are what
  /// users actually read out to each other — resolving both here means no
  /// screen has to guess which shape it was handed.
  ///
  /// Returns null when no row matches (unknown identifier, or RLS hid it).
  static Future<Profile?> fetchProfileById(String identifier) async {
    final value = identifier.trim();
    if (value == 'founder_official_uid' || value.toLowerCase() == 'founder') {
      return fetchFounderProfile();
    }

    if (!SupabaseService.isInitialized) {
      if (value == 'founder_official_uid') return fallbackFounderProfile;
      return null;
    }

    final isUuid = _uuidPattern.hasMatch(value);
    // `student_code` is stored uppercase (0017 permanent student codes);
    // accept whatever casing the user typed/pasted.
    final column = isUuid ? 'id' : 'student_code';
    final lookup = isUuid ? value : value.toUpperCase();

    try {
      final response = await _db.select().eq(column, lookup).maybeSingle();
      if (response != null) {
        return Profile.fromJson(response);
      }
    } catch (e) {
      AppLogger.warning('fetchProfileById failed for $column=$lookup: $e');
    }

    if (value == 'founder_official_uid') {
      return fallbackFounderProfile;
    }
    return null;
  }

  /// Live `COUNT(*)` straight off the `user_follows` edge table: how many
  /// people follow [userId], and how many [userId] follows. Used for peer
  /// profiles so the tiles show the real graph rather than a cached
  /// denormalised counter. `user_follows` is readable by any authenticated
  /// user (0058 "read follows" policy), so this works for peers too.
  ///
  /// Throws on failure — callers decide whether to fall back to
  /// `profiles.followers_count` / `following_count`.
  static Future<({int followers, int following})> fetchFollowCounts(
    String userId,
  ) async {
    if (!SupabaseService.isInitialized) {
      throw const DataError(message: 'Could not load follow counts.');
    }
    final client = SupabaseService.client;
    try {
      final followers = await client
          .from('user_follows')
          .count(CountOption.exact)
          .eq('following_id', userId);
      final following = await client
          .from('user_follows')
          .count(CountOption.exact)
          .eq('follower_id', userId);
      return (followers: followers, following: following);
    } on PostgrestException catch (e) {
      AppLogger.error('fetchFollowCounts failed for $userId: ${e.message}');
      throw const DataError(message: 'Could not load follow counts.');
    } catch (e) {
      if (e is AppError) rethrow;
      AppLogger.error('fetchFollowCounts unexpected error: $e');
      throw const DataError(message: 'Could not load follow counts.');
    }
  }

  /// Whether the CALLING user currently follows [targetUserId] — the real
  /// answer behind the peer profile's Follow / Following button (never a
  /// guess, and never "false" just because the profile was opened fresh).
  static Future<bool> isFollowingUser(String targetUserId) async {
    if (!SupabaseService.isInitialized) return false;
    final userId = SupabaseService.client.auth.currentUser?.id;
    if (userId == null || userId == targetUserId) return false;
    try {
      final rows = await SupabaseService.client
          .from('user_follows')
          .select('follower_id')
          .eq('follower_id', userId)
          .eq('following_id', targetUserId)
          .limit(1);
      return rows.isNotEmpty;
    } catch (e) {
      AppLogger.warning('isFollowingUser failed for $targetUserId: $e');
      return false;
    }
  }

  /// Fetches the official Founder / Owner profile.
  static Future<Profile?> fetchFounderProfile() async {
    if (!SupabaseService.isInitialized) {
      return fallbackFounderProfile;
    }
    try {
      final response = await _db
          .select()
          .eq('app_role', 'owner')
          .limit(1)
          .maybeSingle();
      if (response != null) {
        return Profile.fromJson(response);
      }
    } catch (e) {
      AppLogger.warning('fetchFounderProfile error: $e');
    }
    return fallbackFounderProfile;
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
