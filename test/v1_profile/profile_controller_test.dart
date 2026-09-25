// Profile — controller-level tests using a fake AvatarService. Avatar
// pick/validate is fully fake-isolated from Supabase; the profile-row
// write side (ProfileService.setAvatarUrl/updateProfile) still goes
// through the real static ProfileService, which touches the live
// SupabaseClient for its actual network calls. Since this test environment
// never calls SupabaseService.initialize(), those specific calls fail
// with a "not initialized" error — which the controller is required to
// turn into a graceful, non-crashing failure (exercised explicitly below)
// rather than let escape. Genuine success-path coverage of the DB write
// itself is not possible without a fake Supabase client, which no test in
// this project's suite currently has (same limitation noted for the AI
// repository's Supabase-session-dependent path in an earlier session).

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_praperation/core/errors/app_error.dart';
import 'package:my_praperation/core/services/avatar_service.dart';
import 'package:my_praperation/features/profile/state/profile_controller.dart';

class FakeAvatarService implements AvatarService {
  Uint8List? nextGalleryBytes;
  Uint8List? nextCameraBytes;
  Object? pickError;
  String? nextUploadUrl;
  Object? uploadError;
  Object? deleteError;
  bool deleteCalled = false;
  Uint8List? lastUploadedBytes;

  final List<String> calls = [];

  @override
  Future<Uint8List?> pickFromGallery() async {
    calls.add('pickFromGallery');
    if (pickError != null) throw pickError!;
    return nextGalleryBytes ?? Uint8List.fromList([0xFF, 0xD8, 0xFF]);
  }

  @override
  Future<Uint8List?> pickFromCamera() async {
    calls.add('pickFromCamera');
    if (pickError != null) throw pickError!;
    return nextCameraBytes ?? Uint8List.fromList([0xFF, 0xD8, 0xFF]);
  }

  @override
  void validateImageBytes(Uint8List bytes) {
    calls.add('validateImageBytes');
  }

  @override
  Future<String> uploadAvatar(Uint8List bytes) async {
    calls.add('uploadAvatar');
    lastUploadedBytes = bytes;
    if (uploadError != null) throw uploadError!;
    return nextUploadUrl ?? 'https://example.com/avatars/u1/profile.jpg?v=1';
  }

  @override
  Future<void> deleteAvatar() async {
    calls.add('deleteAvatar');
    deleteCalled = true;
    if (deleteError != null) throw deleteError!;
  }
}

void main() {
  group('ProfileController — avatar pick', () {
    late FakeAvatarService fake;
    late ProfileController controller;

    setUp(() {
      fake = FakeAvatarService();
      controller = ProfileController(avatarService: fake);
    });

    tearDown(() => controller.dispose());

    test('pickAvatarFromGallery returns the picked bytes', () async {
      fake.nextGalleryBytes = Uint8List.fromList([1, 2, 3]);
      final bytes = await controller.pickAvatarFromGallery();
      expect(bytes, [1, 2, 3]);
      expect(fake.calls, contains('pickFromGallery'));
      expect(controller.avatarError, isNull);
    });

    test('pickAvatarFromCamera returns the picked bytes', () async {
      fake.nextCameraBytes = Uint8List.fromList([4, 5, 6]);
      final bytes = await controller.pickAvatarFromCamera();
      expect(bytes, [4, 5, 6]);
      expect(fake.calls, contains('pickFromCamera'));
    });

    test('a pick failure (e.g. permission denied) surfaces a friendly error, not a crash', () async {
      fake.pickError = const AuthError(message: 'Camera permission is needed.');
      final bytes = await controller.pickAvatarFromGallery();
      expect(bytes, isNull);
      expect(controller.avatarError, contains('permission'));
    });

    test('a second pick call while one is in flight is ignored (no concurrent picks)', () async {
      final first = controller.pickAvatarFromGallery();
      final second = await controller.pickAvatarFromGallery();
      expect(second, isNull); // busy-guard, not a real pick
      await first;
    });
  });

  group('ProfileController — avatar upload', () {
    late FakeAvatarService fake;
    late ProfileController controller;

    setUp(() {
      fake = FakeAvatarService();
      controller = ProfileController(avatarService: fake);
    });

    tearDown(() => controller.dispose());

    test('upload failure at the storage layer surfaces a friendly error, not a crash', () async {
      fake.uploadError = const DataError(message: 'Upload failed: network error');
      final ok = await controller.uploadAvatar(Uint8List.fromList([1, 2, 3]));
      expect(ok, isFalse);
      expect(controller.avatarError, contains('Upload failed'));
      expect(controller.avatarOpState, AvatarOpState.idle); // never gets stuck "uploading"
    });

    test('upload succeeding at the storage layer but the DB write having no Supabase session fails gracefully', () async {
      fake.nextUploadUrl = 'https://example.com/avatars/u1/profile.jpg?v=2';
      final ok = await controller.uploadAvatar(Uint8List.fromList([1, 2, 3]));
      // ProfileService.setAvatarUrl needs a real Supabase session, which
      // this test environment never provides — the controller must not
      // crash or hang; it must report failure and stay interactive.
      expect(ok, isFalse);
      expect(controller.avatarError, isNotNull);
      expect(controller.avatarOpState, AvatarOpState.idle);
      expect(fake.calls, contains('uploadAvatar'));
    });

    test('a second upload call while one is in flight is ignored', () async {
      fake.nextUploadUrl = 'https://example.com/u.jpg';
      final first = controller.uploadAvatar(Uint8List.fromList([1]));
      final second = await controller.uploadAvatar(Uint8List.fromList([2]));
      expect(second, isFalse);
      await first;
    });
  });

  group('ProfileController — avatar delete', () {
    test('deleting when there is no current avatar is a safe no-op success', () async {
      final fake = FakeAvatarService();
      final controller = ProfileController(avatarService: fake);
      final ok = await controller.deleteAvatar();
      expect(ok, isTrue);
      expect(fake.deleteCalled, isFalse); // nothing to delete, service never called
      controller.dispose();
    });
  });

  group('ProfileController — save validation (no network needed to fail fast)', () {
    late ProfileController controller;

    setUp(() {
      controller = ProfileController(avatarService: FakeAvatarService());
    });

    tearDown(() => controller.dispose());

    test('an empty name is rejected before any save attempt', () async {
      final ok = await controller.save(fullName: '   ', bio: '', mobile: '');
      expect(ok, isFalse);
      expect(controller.saveError, isNotNull);
    });

    test('a bio over the character limit is rejected', () async {
      final ok = await controller.save(
        fullName: 'Valid Name',
        bio: 'x' * (ProfileValidators.bioMaxLength + 1),
        mobile: '',
      );
      expect(ok, isFalse);
      expect(controller.saveError, contains('Bio'));
    });

    test('an invalid phone number is rejected', () async {
      final ok = await controller.save(fullName: 'Valid Name', bio: '', mobile: 'not-a-number');
      expect(ok, isFalse);
      expect(controller.saveError, contains('phone number'));
    });

    test('a second save call while one is in flight is ignored (prevents duplicate saves)', () async {
      final first = controller.save(fullName: 'Name One', bio: '', mobile: '');
      final second = await controller.save(fullName: 'Name Two', bio: '', mobile: '');
      expect(second, isFalse);
      await first;
    });
  });

  group('ProfileController — edit mode', () {
    test('starting and cancelling editing toggles isEditing without throwing', () {
      final controller = ProfileController(avatarService: FakeAvatarService());
      expect(controller.isEditing, isFalse);
      controller.startEditing();
      expect(controller.isEditing, isTrue);
      controller.cancelEditing();
      expect(controller.isEditing, isFalse);
      controller.dispose();
    });
  });
}
