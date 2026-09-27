import 'package:share_plus/share_plus.dart';

import 'profile_service.dart';

/// Builds and triggers the app's viral-share message. The referral code is
/// always the caller's own real `student_code` — never a placeholder — so a
/// share triggered before the profile has loaded is refused rather than
/// sharing a blank/fake code.
abstract final class AppShareService {
  static const _joinUrl = 'https://mypreparation.app/join';

  /// The caller's own referral code, or null if the profile hasn't loaded.
  static String? get myReferralCode => ProfileService.currentProfile?.studentCode;

  static String buildShareMessage(String code) {
    return '📚 Join me on My Preparation — The serious test & study app for '
        'NCERT & competitive aspirants!\n\n'
        '🎁 Use my Invite Code: $code to get 100 Study Points immediately '
        'upon joining!\n\n'
        '👉 Download App & Start Learning:\n'
        '$_joinUrl?ref=$code';
  }

  /// Opens the native share sheet with the dynamic invite message. Returns
  /// false (and shares nothing) when the profile/student code isn't loaded
  /// yet, so the caller can show a real error instead of a broken message.
  static Future<bool> shareApp() async {
    final code = myReferralCode;
    if (code == null || code.isEmpty) return false;
    await SharePlus.instance.share(
      ShareParams(text: buildShareMessage(code), subject: 'Invite to My Preparation'),
    );
    return true;
  }
}
