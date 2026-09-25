import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../errors/app_error.dart';
import '../logging/app_logger.dart';
import '../models/profile.dart';
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

  static SupabaseQueryBuilder get _db => SupabaseService.client.from('profiles');

  static Future<void> loadProfile() async {
    final userId = SupabaseService.client.auth.currentUser?.id;
    if (userId == null) {
      _updateStatus(ProfileStatus.empty);
      _currentProfile = null;
      return;
    }

    _updateStatus(ProfileStatus.loading);

    try {
      final response =
          await _db.select().eq('id', userId).maybeSingle();

      if (response == null) {
        AppLogger.info('No profile found, attempting to ensure profile...');
        await _ensureProfile(userId);
        return;
      }

      _currentProfile = Profile.fromJson(response);
      _updateStatus(ProfileStatus.loaded);
      AppLogger.info('Profile loaded: ${_currentProfile!.studentCode ?? "no student code"}');
    } catch (e) {
      AppLogger.error('Failed to load profile: $e');
      _currentProfile = null;
      _updateStatus(ProfileStatus.error);
      if (e is AppError) rethrow;
      throw const DataError(message: 'Failed to load profile. Please try again.');
    }
  }

  static Future<void> _ensureProfile(String userId) async {
    try {
      await SupabaseService.client.rpc('fn_ensure_profile');
      AppLogger.info('fn_ensure_profile called, reloading...');

      final response =
          await _db.select().eq('id', userId).maybeSingle();

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
      throw const DataError(message: 'Failed to create profile. Please try again.');
    }
  }

  static Future<void> updateProfile({
    String? fullName,
    String? bio,
    String? mobile,
    String? timezone,
    List<String>? examTargets,
  }) async {
    final userId = SupabaseService.client.auth.currentUser?.id;
    if (userId == null) {
      throw const AuthError(message: 'You must be signed in to update your profile.');
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

      if (updates.isEmpty) return;

      await _db.update(updates).eq('id', userId);

      _currentProfile = _currentProfile!.copyWith(
        fullName: fullName ?? _currentProfile!.fullName,
        bio: bio ?? _currentProfile!.bio,
        mobile: mobile ?? _currentProfile!.mobile,
        timezone: timezone ?? _currentProfile!.timezone,
        examTargets: examTargets ?? _currentProfile!.examTargets,
      );

      AppLogger.info('Profile updated.');
    } on PostgrestException catch (e) {
      AppLogger.error('Profile update PostgrestException: ${e.message}');
      throw DataError(message: _mapProfileErrorMessage(e.message));
    } catch (e) {
      if (e is AppError) rethrow;
      AppLogger.error('Profile update unexpected error: $e');
      throw const DataError(message: 'Failed to update profile. Please try again.');
    }
  }

  /// Persists a new (or cleared, via null) avatar URL. Separate from
  /// [updateProfile] so the avatar upload/delete flow — which already
  /// wrote the Storage object before calling this — only ever touches the
  /// one column it needs to.
  static Future<void> setAvatarUrl(String? avatarUrl) async {
    final userId = SupabaseService.client.auth.currentUser?.id;
    if (userId == null) {
      throw const AuthError(message: 'You must be signed in to update your profile.');
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
      throw const DataError(message: 'Failed to update your photo. Please try again.');
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
    _currentStatus = profile != null ? ProfileStatus.loaded : ProfileStatus.initial;
  }
}
