import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../errors/app_error.dart';
import '../logging/app_logger.dart';
import 'supabase_service.dart';

/// Decode/resize/encode off the UI thread — full-resolution JPEG work
/// otherwise drops frames while the user waits on the upload sheet.
/// Returns null when the bytes cannot be decoded.
Uint8List? _normalizeAvatarBytes((Uint8List, int, int) input) {
  final (bytes, maxDimension, quality) = input;
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return null;
  final resized =
      (decoded.width > maxDimension || decoded.height > maxDimension)
          ? img.copyResize(
              decoded,
              width: decoded.width >= decoded.height ? maxDimension : null,
              height: decoded.height > decoded.width ? maxDimension : null,
            )
          : decoded;
  return Uint8List.fromList(img.encodeJpg(resized, quality: quality));
}

/// Handles profile photo selection, validation, compression, and
/// Supabase Storage upload/delete.
///
/// SECURITY: the storage path is always `{user_id}/profile.jpg` — derived
/// from the authenticated session, never a caller-supplied id — and the
/// `avatars` bucket's storage policies only allow a user to write/delete
/// objects inside their own folder (see
/// `migrations/AVATAR_STORAGE_bucket_and_policies.sql`).
///
/// DESIGN NOTE (why the path is fixed, not timestamped): every upload is
/// re-encoded to JPEG and written with `upsert: true` to the SAME path.
/// That means "replace the photo" is a single atomic Storage call — the
/// old bytes are overwritten in place, so there is no separate old object
/// to clean up afterward and no way to ever leak an orphan (unlike the
/// timestamped-path documents feature, a fixed path can't accumulate
/// history). The tradeoff: once the new bytes are written, the old ones
/// are gone — so if the follow-up `profiles.avatar_url` DB write then
/// fails, there is nothing safe to "roll back" (deleting the just-written
/// file would leave the user with zero avatar, strictly worse). The
/// caller should surface a retry instead; retrying is harmless (same
/// idempotent upsert).
abstract interface class AvatarService {
  /// Opens the gallery/photo picker. Returns null if the user cancelled.
  Future<Uint8List?> pickFromGallery();

  /// Opens the camera. Returns null if the user cancelled.
  Future<Uint8List?> pickFromCamera();

  /// Validates raw picked bytes (size + real file signature — never trusts
  /// a filename/extension alone). Throws [ValidationError] on failure.
  void validateImageBytes(Uint8List bytes);

  /// Compresses/normalizes [bytes] to JPEG and uploads it as the current
  /// user's avatar, replacing any existing one. Returns the new public URL
  /// (with a cache-busting query parameter so `Image.network` widgets
  /// showing the old bytes actually refresh).
  Future<String> uploadAvatar(Uint8List bytes);

  /// Removes the current user's avatar object from Storage, if any.
  /// Idempotent — a missing object is not an error.
  Future<void> deleteAvatar();
}

class SupabaseAvatarService implements AvatarService {
  SupabaseAvatarService({SupabaseClient? client}) : _injectedClient = client;

  final SupabaseClient? _injectedClient;

  SupabaseClient get _client => _injectedClient ?? SupabaseService.client;

  static const _bucket = 'avatars';
  static const _maxRawBytes = 10 * 1024 * 1024; // 10 MB, pre-compression
  static const _maxDimension = 1024;
  static const _jpegQuality = 88;

  String get _userId {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) throw const AuthError(message: 'You must be logged in.');
    return uid;
  }

  String get _storagePath => '$_userId/profile.jpg';

  @override
  Future<Uint8List?> pickFromGallery() async {
    final file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 95, // real compression happens in uploadAvatar
    );
    if (file == null) return null;
    return file.readAsBytes();
  }

  @override
  Future<Uint8List?> pickFromCamera() async {
    try {
      final file = await ImagePicker().pickImage(
        source: ImageSource.camera,
        maxWidth: 2000,
        maxHeight: 2000,
        imageQuality: 90,
      );
      if (file == null) return null;
      return await file.readAsBytes();
    } on Exception catch (e) {
      final msg = e.toString().toLowerCase();
      if (msg.contains('permission') || msg.contains('denied')) {
        throw const AuthError(
          message: 'Camera permission is needed to take a photo. '
              'Enable it in your device settings and try again.',
        );
      }
      throw const DataError(message: 'Could not open the camera. Please try again.');
    }
  }

  @override
  void validateImageBytes(Uint8List bytes) {
    if (bytes.isEmpty) {
      throw const ValidationError(message: 'Image is empty or unreadable.');
    }
    if (bytes.length > _maxRawBytes) {
      throw const ValidationError(message: 'Image is too large. Maximum size is 10 MB.');
    }
    if (!_looksLikeSupportedImage(bytes)) {
      throw const ValidationError(
        message: 'Unsupported image format. Please choose a JPG, PNG, or WebP image.',
      );
    }
  }

  /// Never trusts a filename/extension — sniffs the real file signature.
  bool _looksLikeSupportedImage(Uint8List b) {
    if (b.length < 4) return false;
    final isJpeg = b[0] == 0xFF && b[1] == 0xD8 && b[2] == 0xFF;
    final isPng = b.length >= 8 && b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E && b[3] == 0x47;
    final isWebp = b.length >= 12 &&
        b[0] == 0x52 && b[1] == 0x49 && b[2] == 0x46 && b[3] == 0x46 && // "RIFF"
        b[8] == 0x57 && b[9] == 0x45 && b[10] == 0x42 && b[11] == 0x50; // "WEBP"
    return isJpeg || isPng || isWebp;
  }

  @override
  Future<String> uploadAvatar(Uint8List bytes) async {
    validateImageBytes(bytes);

    final normalized = await compute(
      _normalizeAvatarBytes,
      (bytes, _maxDimension, _jpegQuality),
    );
    if (normalized == null) {
      throw const ValidationError(
        message: 'Could not read that image. Please try a different photo.',
      );
    }

    try {
      await _client.storage.from(_bucket).uploadBinary(
            _storagePath,
            normalized,
            fileOptions: const FileOptions(contentType: 'image/jpeg', upsert: true),
          );
    } on StorageException catch (e) {
      AppLogger.error('Avatar upload failed: ${e.message}');
      throw DataError(message: 'Upload failed: ${e.message}');
    } catch (e, st) {
      AppLogger.error('Avatar upload unexpected error: $e', stackTrace: st);
      throw const DataError(message: 'Upload failed. Please try again.');
    }

    final publicUrl = _client.storage.from(_bucket).getPublicUrl(_storagePath);
    // Cache-bust: the path never changes on replace, so without this every
    // Image.network showing the old avatar would keep the stale bytes.
    return '$publicUrl?v=${DateTime.now().millisecondsSinceEpoch}';
  }

  @override
  Future<void> deleteAvatar() async {
    try {
      await _client.storage.from(_bucket).remove([_storagePath]);
    } on StorageException catch (e) {
      // "not found" is a success for an idempotent delete; anything else
      // is a real failure the caller should surface.
      final msg = e.message.toLowerCase();
      if (msg.contains('not found') || msg.contains('does not exist')) return;
      AppLogger.error('Avatar delete failed: ${e.message}');
      throw DataError(message: 'Could not remove the photo: ${e.message}');
    } catch (e, st) {
      AppLogger.error('Avatar delete unexpected error: $e', stackTrace: st);
      throw const DataError(message: 'Could not remove the photo. Please try again.');
    }
  }
}
