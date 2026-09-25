// Supabase email verification redirect: the production bug was that
// AuthService.signUp() passed no emailRedirectTo, so Supabase fell back to
// the project's Site URL (a localhost dev URL, unreachable from a device).
// These tests guard the two halves of the fix from silently drifting apart:
// the constant AuthService actually sends to Supabase, and the Android
// intent-filter that must match it exactly for the deep link to reopen the
// app. They do not exercise GoTrue itself — AuthService is a static wrapper
// with no injectable client, so a live signUp() call is out of scope here;
// see the integration report for the manual device-verification steps.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_praperation/core/services/auth_service.dart';

void main() {
  group('AuthService.emailVerificationRedirectUrl', () {
    test('is a custom scheme, never localhost or an http(s) URL', () {
      final uri = Uri.parse(AuthService.emailVerificationRedirectUrl);
      expect(uri.scheme, isNot('http'));
      expect(uri.scheme, isNot('https'));
      expect(AuthService.emailVerificationRedirectUrl, isNot(contains('localhost')));
      expect(AuthService.emailVerificationRedirectUrl, isNot(contains('127.0.0.1')));
      expect(uri.scheme, 'my-preparation');
      expect(uri.host, 'auth-callback');
    });
  });

  group('AndroidManifest.xml deep-link intent-filter', () {
    late String manifest;

    setUpAll(() {
      manifest = File(
        'android/app/src/main/AndroidManifest.xml',
      ).readAsStringSync();
    });

    test('declares a VIEW/BROWSABLE intent-filter for the auth callback scheme', () {
      expect(manifest, contains('android.intent.action.VIEW'));
      expect(manifest, contains('android.intent.category.BROWSABLE'));
    });

    test('scheme/host match AuthService.emailVerificationRedirectUrl exactly', () {
      final uri = Uri.parse(AuthService.emailVerificationRedirectUrl);
      expect(
        manifest,
        contains('android:scheme="${uri.scheme}"'),
        reason:
            'A drift here means Android will not reopen the app for the '
            'link Supabase actually sends.',
      );
      expect(manifest, contains('android:host="${uri.host}"'));
    });

    test('MainActivity is exported (required for any deep link to reach it)', () {
      expect(manifest, contains('android:exported="true"'));
    });
  });
}
