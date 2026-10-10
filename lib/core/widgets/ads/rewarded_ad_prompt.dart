import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../../logging/app_logger.dart';
import '../../services/ads/ad_service.dart';

/// Optional "watch a short ad" offer in front of an already-free action
/// (PDF report download, Radio Revision). Never blocks the action: a VIP
/// user, a session/cooldown-capped user, a load failure, or an explicit
/// "Skip" all fall through to [onProceed] exactly as if this prompt didn't
/// exist — this is a goodwill/revenue opportunity, not a paywall gate.
abstract final class RewardedAdPrompt {
  static Future<void> maybeShow(
    BuildContext context, {
    required String title,
    required VoidCallback onProceed,
  }) async {
    if (!AdService.canShowRewardedAd()) {
      onProceed();
      return;
    }

    final choice = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: const Text(
          'Watch a short video to support My Preparation — totally optional, '
          'you can skip straight to it any time.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Skip'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(ctx).pop(true),
            icon: const Icon(Icons.play_circle_outline, size: 18),
            label: const Text('🎬 Watch Ad'),
          ),
        ],
      ),
    );

    if (choice != true) {
      onProceed();
      return;
    }

    _loadAndShow(onProceed: onProceed);
  }

  static void _loadAndShow({required VoidCallback onProceed}) {
    var proceeded = false;
    void proceedOnce() {
      if (proceeded) return;
      proceeded = true;
      onProceed();
    }

    RewardedAd.load(
      adUnitId: AdService.rewardedAdUnitId,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          ad.fullScreenContentCallback = FullScreenContentCallback(
            onAdDismissedFullScreenContent: (ad) {
              ad.dispose();
              proceedOnce();
            },
            onAdFailedToShowFullScreenContent: (ad, error) {
              AppLogger.warning('RewardedAd failed to show: $error');
              ad.dispose();
              proceedOnce();
            },
          );
          AdService.recordFullScreenImpression();
          ad.show(onUserEarnedReward: (ad, reward) {});
        },
        onAdFailedToLoad: (error) {
          AppLogger.warning('RewardedAd failed to load: $error');
          proceedOnce();
        },
      ),
    );
  }
}
