import 'dart:typed_data';

import '../../../core/errors/app_error.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/models/profile.dart';
import '../../../core/services/avatar_service.dart';
import '../../../core/services/profile_service.dart';
import '../../../core/services/supabase_service.dart';
import '../../test/state/disposable_notifier.dart';

enum ProfileLoadState { loading, loaded, empty, error }

enum AvatarOpState { idle, picking, uploading, deleting }

/// Field-level validators, pure and independently testable. Kept separate
/// from the controller/widget so a malformed edit can never reach the
/// network layer or crash the screen — every value shown to the user goes
/// through here first.
abstract final class ProfileValidators {
  static const nameMaxLength = 100;
  static const bioMaxLength = 500;
  static const mobileMaxLength = 20;

  /// Null = valid.
  static String? name(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return 'Please enter your name.';
    if (trimmed.length > nameMaxLength) {
      return 'Name must be $nameMaxLength characters or fewer.';
    }
    return null;
  }

  /// Mobile is optional — only validated when non-empty.
  static String? mobile(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;
    if (trimmed.length > mobileMaxLength) {
      return 'Phone number is too long.';
    }
    if (!RegExp(r'^[0-9+\-\s()]{6,20}$').hasMatch(trimmed)) {
      return 'Enter a valid phone number.';
    }
    return null;
  }

  static String? bio(String value) {
    if (value.length > bioMaxLength) {
      return 'Bio must be $bioMaxLength characters or fewer.';
    }
    return null;
  }
}

/// Orchestrates loading, editing/saving, and avatar upload/delete for the
/// Profile screen. The widget owns its own [TextEditingController]s (same
/// pattern as the rest of this app's forms); this controller owns
/// load/save/avatar *state* and talks to [ProfileService]/[AvatarService].
class ProfileController extends DisposableNotifier {
  ProfileController({
    this.targetUserId,
    this.initialProfile,
    AvatarService? avatarService,
  }) : _avatarService = avatarService ?? SupabaseAvatarService() {
    if (initialProfile != null) {
      _targetProfile = initialProfile;
      _loadState = ProfileLoadState.loaded;
    }
  }

  final String? targetUserId;
  final Profile? initialProfile;
  final AvatarService _avatarService;

  Profile? _targetProfile;
  ProfileLoadState _loadState = ProfileLoadState.loading;
  String? _loadError;
  bool _isEditing = false;
  bool _isSaving = false;
  String? _saveError;
  AvatarOpState _avatarOpState = AvatarOpState.idle;
  String? _avatarError;
  bool? _viewerFollows;

  bool get isViewingOther =>
      targetUserId != null &&
      targetUserId!.isNotEmpty &&
      targetUserId !=
          (SupabaseService.isInitialized
              ? SupabaseService.client.auth.currentUser?.id
              : null);

  ProfileLoadState get loadState => _loadState;
  String? get loadError => _loadError;
  Profile? get profile => isViewingOther
      ? (_targetProfile ?? initialProfile)
      : ProfileService.currentProfile;

  /// Whether the CALLING user already follows the student on screen.
  /// null until a peer profile has been (or is being) loaded — a peer
  /// profile seeded from [initialProfile] never asks the server, so the
  /// caller must treat null as "unknown" and show the inactive state.
  bool? get viewerFollows => _viewerFollows;
  bool get isEditing => !isViewingOther && _isEditing;
  bool get isSaving => _isSaving;
  String? get saveError => _saveError;
  AvatarOpState get avatarOpState => _avatarOpState;
  bool get isAvatarBusy => _avatarOpState != AvatarOpState.idle;
  String? get avatarError => _avatarError;

  Future<void> load() async {
    if (isViewingOther) {
      if (_targetProfile != null) {
        _loadState = ProfileLoadState.loaded;
        notifyListeners();
        return;
      }

      _loadState = ProfileLoadState.loading;
      _loadError = null;
      notifyListeners();

      try {
        final fetched = await ProfileService.fetchProfileById(targetUserId!);
        if (fetched != null) {
          _targetProfile = fetched;
          _loadState = ProfileLoadState.loaded;
          // Paint the student immediately, then refine the counts and the
          // Follow button's real state once those two queries land.
          notifyListeners();
          await _loadPeerSocialState(fetched.id);
        } else {
          _loadState = ProfileLoadState.empty;
        }
      } catch (e, st) {
        AppLogger.error(
          'Failed to load target user profile: $e',
          stackTrace: st,
        );
        _loadError = 'Could not load student profile.';
        _loadState = ProfileLoadState.error;
      }
      notifyListeners();
      return;
    }

    final existing = ProfileService.currentProfile;
    if (existing != null) {
      _loadState = ProfileLoadState.loaded;
      notifyListeners();
      return;
    }

    _loadState = ProfileLoadState.loading;
    _loadError = null;
    notifyListeners();

    try {
      await ProfileService.loadProfile();
      _loadState = ProfileService.currentProfile != null
          ? ProfileLoadState.loaded
          : ProfileLoadState.empty;
    } on AppError catch (e) {
      _loadError = e.message;
      _loadState = ProfileLoadState.error;
    } catch (e, st) {
      AppLogger.error('Profile load failed: $e', stackTrace: st);
      _loadError = 'Failed to load your profile. Please try again.';
      _loadState = ProfileLoadState.error;
    }
    notifyListeners();
  }

  /// Loads the social layer of an already-fetched peer profile: live
  /// `user_follows` counts for the Followers / Following tiles, plus
  /// whether the caller already follows this student (the Follow button's
  /// real initial state).
  ///
  /// Deliberately never throws: the profile row itself is already on
  /// screen, so a hiccup on either query degrades to what the database
  /// already gave us (`profiles.followers_count` / `following_count` and
  /// an inactive Follow button) instead of failing the whole screen.
  Future<void> _loadPeerSocialState(String peerId) async {
    try {
      final counts = await ProfileService.fetchFollowCounts(peerId);
      _targetProfile = _targetProfile?.copyWith(
        followersCount: counts.followers,
        followingCount: counts.following,
      );
    } catch (e) {
      AppLogger.warning('Peer follow counts unavailable for $peerId: $e');
    }

    try {
      _viewerFollows = await ProfileService.isFollowingUser(peerId);
    } catch (e) {
      AppLogger.warning('Peer follow state unavailable for $peerId: $e');
    }
  }

  /// Applies a follow/unfollow the screen just performed successfully:
  /// keeps [viewerFollows] and the peer's follower count in step with the
  /// edge the server actually recorded.
  void applyViewerFollowChange({required bool following}) {
    _viewerFollows = following;
    final peer = _targetProfile;
    if (peer != null) {
      final next = peer.followersCount + (following ? 1 : -1);
      _targetProfile = peer.copyWith(followersCount: next < 0 ? 0 : next);
    }
    notifyListeners();
  }

  void startEditing() {
    _isEditing = true;
    _saveError = null;
    notifyListeners();
  }

  void cancelEditing() {
    _isEditing = false;
    _saveError = null;
    notifyListeners();
  }

  /// Validates and saves. Returns true on success. Prevents a duplicate
  /// save from a fast double-tap by no-oping while already saving.
  Future<bool> save({
    required String fullName,
    required String bio,
    required String mobile,
    DateTime? dateOfBirth,
    Map<String, String>? socialLinks,
  }) async {
    if (_isSaving) return false;

    final nameError = ProfileValidators.name(fullName);
    final bioError = ProfileValidators.bio(bio);
    final mobileError = ProfileValidators.mobile(mobile);
    if (nameError != null || bioError != null || mobileError != null) {
      _saveError = nameError ?? bioError ?? mobileError;
      notifyListeners();
      return false;
    }

    _isSaving = true;
    _saveError = null;
    notifyListeners();

    try {
      await ProfileService.updateProfile(
        fullName: fullName.trim(),
        bio: bio.trim(),
        mobile: mobile.trim(),
        dateOfBirth: dateOfBirth,
        socialLinks: socialLinks,
      );
      _isSaving = false;
      _isEditing = false;
      notifyListeners();
      return true;
    } on AppError catch (e) {
      _saveError = e.message;
    } catch (e, st) {
      AppLogger.error('Profile save failed: $e', stackTrace: st);
      _saveError = 'Failed to save your profile. Please try again.';
    }
    _isSaving = false;
    notifyListeners();
    return false;
  }

  Future<bool> saveSocialLinks(Map<String, String> links) async {
    try {
      await ProfileService.updateProfile(socialLinks: links);
      notifyListeners();
      return true;
    } catch (e) {
      AppLogger.error('Failed to update social links: $e');
      return false;
    }
  }

  Future<Uint8List?> pickAvatarFromGallery() =>
      _pickAvatar(_avatarService.pickFromGallery);

  Future<Uint8List?> pickAvatarFromCamera() =>
      _pickAvatar(_avatarService.pickFromCamera);

  Future<Uint8List?> _pickAvatar(Future<Uint8List?> Function() picker) async {
    if (isAvatarBusy) return null;
    _avatarOpState = AvatarOpState.picking;
    _avatarError = null;
    notifyListeners();

    try {
      final bytes = await picker();
      _avatarOpState = AvatarOpState.idle;
      notifyListeners();
      return bytes;
    } on AppError catch (e) {
      _avatarError = e.message;
      _avatarOpState = AvatarOpState.idle;
      notifyListeners();
      return null;
    } catch (e, st) {
      AppLogger.error('Avatar pick failed: $e', stackTrace: st);
      _avatarError = 'Failed to pick a photo. Please try again.';
      _avatarOpState = AvatarOpState.idle;
      notifyListeners();
      return null;
    }
  }

  /// Validates, compresses, and uploads [bytes] as the new avatar, then
  /// persists the resulting URL on the profile row. Returns true on
  /// success.
  Future<bool> uploadAvatar(Uint8List bytes) async {
    if (isAvatarBusy) return false;
    _avatarOpState = AvatarOpState.uploading;
    _avatarError = null;
    notifyListeners();

    try {
      final url = await _avatarService.uploadAvatar(bytes);
      await ProfileService.setAvatarUrl(url);
      _avatarOpState = AvatarOpState.idle;
      notifyListeners();
      return true;
    } on AppError catch (e) {
      _avatarError = e.message;
    } catch (e, st) {
      AppLogger.error('Avatar upload failed: $e', stackTrace: st);
      _avatarError = 'Failed to upload your photo. Please try again.';
    }
    _avatarOpState = AvatarOpState.idle;
    notifyListeners();
    return false;
  }

  /// Removes the current avatar (Storage object, then the profile's
  /// `avatar_url`), returning to the default initials avatar.
  Future<bool> deleteAvatar() async {
    if (isAvatarBusy) return false;
    if (profile?.avatarUrl == null) return true; // nothing to do

    _avatarOpState = AvatarOpState.deleting;
    _avatarError = null;
    notifyListeners();

    try {
      await _avatarService.deleteAvatar();
      await ProfileService.setAvatarUrl(null);
      _avatarOpState = AvatarOpState.idle;
      notifyListeners();
      return true;
    } on AppError catch (e) {
      _avatarError = e.message;
    } catch (e, st) {
      AppLogger.error('Avatar delete failed: $e', stackTrace: st);
      _avatarError = 'Failed to remove your photo. Please try again.';
    }
    _avatarOpState = AvatarOpState.idle;
    notifyListeners();
    return false;
  }

  void clearAvatarError() {
    _avatarError = null;
    notifyListeners();
  }
}
