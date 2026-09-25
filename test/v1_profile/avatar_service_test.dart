// Profile photo — pure validation/signature-sniffing tests for
// SupabaseAvatarService.validateImageBytes. Doesn't touch Supabase (the
// method never reads _client), so no initialization is needed.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_praperation/core/errors/app_error.dart';
import 'package:my_praperation/core/services/avatar_service.dart';

void main() {
  final service = SupabaseAvatarService();

  group('validateImageBytes — real file signatures, never trust the caller', () {
    test('accepts a real JPEG (FF D8 FF magic)', () {
      final bytes = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 0, 0, 0, 0]);
      expect(() => service.validateImageBytes(bytes), returnsNormally);
    });

    test('accepts a real PNG (89 50 4E 47 magic)', () {
      final bytes = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
      expect(() => service.validateImageBytes(bytes), returnsNormally);
    });

    test('accepts a real WebP (RIFF....WEBP magic)', () {
      final bytes = Uint8List.fromList([
        0x52, 0x49, 0x46, 0x46, // RIFF
        0, 0, 0, 0, // size (unused by the check)
        0x57, 0x45, 0x42, 0x50, // WEBP
      ]);
      expect(() => service.validateImageBytes(bytes), returnsNormally);
    });

    test('rejects an empty file', () {
      expect(
        () => service.validateImageBytes(Uint8List(0)),
        throwsA(isA<ValidationError>()),
      );
    });

    test('rejects a file over the 10 MB ceiling', () {
      final huge = Uint8List(10 * 1024 * 1024 + 1);
      huge[0] = 0xFF;
      huge[1] = 0xD8;
      huge[2] = 0xFF;
      expect(
        () => service.validateImageBytes(huge),
        throwsA(
          isA<ValidationError>().having((e) => e.message, 'message', contains('too large')),
        ),
      );
    });

    test('rejects a renamed non-image (e.g. an .exe disguised as a photo)', () {
      final bytes = Uint8List.fromList([0x4D, 0x5A, 0x90, 0x00, 0x03, 0x00, 0x00, 0x00]); // MZ
      expect(
        () => service.validateImageBytes(bytes),
        throwsA(
          isA<ValidationError>().having((e) => e.message, 'message', contains('Unsupported')),
        ),
      );
    });

    test('rejects plain text pretending to be an image', () {
      final bytes = Uint8List.fromList('just some plain text'.codeUnits);
      expect(() => service.validateImageBytes(bytes), throwsA(isA<ValidationError>()));
    });

    test('rejects a truncated file too short to carry any real signature', () {
      final bytes = Uint8List.fromList([0xFF]);
      expect(() => service.validateImageBytes(bytes), throwsA(isA<ValidationError>()));
    });
  });

  // NOTE on "unauthorized user cannot manipulate another user's avatar":
  // AvatarService.uploadAvatar/deleteAvatar take no path/user-id parameter
  // at all — the storage path is always derived from the authenticated
  // session inside the implementation, so a caller structurally cannot
  // target another user's object client-side. The server-side enforcement
  // (Storage RLS policies scoping writes to the uid-prefixed folder) is in
  // migrations/AVATAR_STORAGE_bucket_and_policies.sql and — like all RLS
  // in this project — isn't verifiable from this offline test environment;
  // see the final report's security section.
}
