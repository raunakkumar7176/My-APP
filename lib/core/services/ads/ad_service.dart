import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../../logging/app_logger.dart';
import '../../models/profile.dart';
import '../entitlement_service.dart';
import '../profile_service.dart';

/// Central gate + ad-unit registry for the whole app's Google Mobile Ads
/// integration. Every placement (banner/native widget, rewarded video
/// trigger) must go through [shouldShowPassiveAds]/[canShowRewardedAd]
/// rather than deciding independently — this is the one place that knows
/// about VIP exemption, session caps, and the full-screen-ad cooldown.
///
/// IDs below are Google's own official TEST ad unit IDs (see
/// https://developers.google.com/admob/android/test-ads) — safe to ship
/// during development, but MUST be swapped for this app's real AdMob ad
/// unit IDs (created after the AdMob account + payment profile are set up)
/// before a production/Play Store release. Requesting real traffic against
/// test IDs is a no-op; shipping test IDs to production just means no real
/// ads (and no real revenue) ever serve — it is not itself a policy
/// violation, but it must still be swapped before launch.
abstract final class AdService {
  static const String bannerAdUnitId = 'ca-app-pub-3940256099942544/6300978111';
  static const String interstitialAdUnitId = 'ca-app-pub-3940256099942544/1033173712';
  static const String rewardedAdUnitId = 'ca-app-pub-3940256099942544/5224354917';

  /// Minimum gap enforced between two full-screen (rewarded/interstitial)
  /// ad impressions, regardless of how many separate trigger points ask for
  /// one — prevents stacking two "watch a video" prompts back to back if a
  /// student bounces between the PDF download and Radio Revision buttons.
  static const Duration _fullScreenCooldown = Duration(minutes: 10);

  /// Hard ceiling on full-screen ad impressions for one app session (resets
  /// on cold start) — a deliberate ethical cap, not an AdMob requirement.
  static const int _maxFullScreenImpressionsPerSession = 4;

  static bool _initialized = false;

  static final _instance = _AdServiceState();

  /// Call once at app startup. Safe to call multiple times (no-ops after
  /// the first success) and never throws — an ad SDK failing to initialize
  /// must never block the rest of the app.
  static Future<void> initialize() async {
    if (_initialized) return;
    try {
      await MobileAds.instance.initialize();
      _initialized = true;
    } catch (e, st) {
      AppLogger.error('AdService.initialize failed: $e', stackTrace: st);
    }
  }

  /// Banner/native placements (Dashboard, Test Instructions, Test Result,
  /// Chapter End): on for everyone except a VIP/verified-and-current user.
  /// No cooldown or session cap — these are static, non-intrusive slots,
  /// never more than one per screen.
  static bool shouldShowPassiveAds() {
    final profile = ProfileService.currentProfile;
    if (profile == null) return true; // not signed in yet: no VIP to exempt
    return !EntitlementService.isVipUser(profile);
  }

  /// Rewarded-video trigger points (PDF download, Radio Revision unlock):
  /// additionally respects the cooldown and session cap above.
  static bool canShowRewardedAd({Profile? profileOverride}) {
    final profile = profileOverride ?? ProfileService.currentProfile;
    if (profile != null && EntitlementService.isVipUser(profile)) return false;
    if (_instance._fullScreenImpressionsThisSession >=
        _maxFullScreenImpressionsPerSession) {
      return false;
    }
    final lastShown = _instance._lastFullScreenImpressionAt;
    if (lastShown != null &&
        DateTime.now().difference(lastShown) < _fullScreenCooldown) {
      return false;
    }
    return true;
  }

  /// Record a shown full-screen ad impression — call right after the
  /// rewarded ad actually displays (not merely loads), so the cooldown and
  /// session cap reflect real impressions, not load attempts.
  static void recordFullScreenImpression() {
    _instance._lastFullScreenImpressionAt = DateTime.now();
    _instance._fullScreenImpressionsThisSession++;
  }
}

/// Holds the mutable cooldown/session-cap state behind [AdService]'s static
/// interface — a plain instance field set, not a singleton meant to be used
/// directly.
class _AdServiceState {
  DateTime? _lastFullScreenImpressionAt;
  int _fullScreenImpressionsThisSession = 0;
}
