import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../../logging/app_logger.dart';
import '../../services/ads/ad_service.dart';

/// Reusable banner-ad slot for the study-flow placements (Dashboard, Test
/// Instructions, Test Result, Chapter End). Renders nothing — not even an
/// empty frame — for a VIP/verified-and-current user ([AdService.
/// shouldShowPassiveAds]), and collapses to zero height on a load failure
/// instead of leaving a grey placeholder box, so a failed ad request never
/// shifts or holes the surrounding layout.
///
/// True AdMob "Native" ad units need a platform-specific native-view
/// factory registered on the Android side; this widget instead wraps a
/// standard `BannerAd` (banner or medium-rectangle size) in the same card
/// chrome the design calls a "native card" — visually consistent with the
/// rest of the screen, without the extra native-ad plumbing.
class AdBannerWidget extends StatefulWidget {
  const AdBannerWidget({
    super.key,
    this.size = AdSize.banner,
    this.margin = const EdgeInsets.only(top: 12, bottom: 12),
  });

  /// Use [AdSize.banner] for a slim strip (Dashboard, Test Instructions) or
  /// [AdSize.mediumRectangle] for a card-like block (Test Result, Chapter
  /// End) — matches the spec's "Banner" vs "Medium Rectangle / Native"
  /// distinction per placement.
  final AdSize size;
  final EdgeInsets margin;

  @override
  State<AdBannerWidget> createState() => _AdBannerWidgetState();
}

class _AdBannerWidgetState extends State<AdBannerWidget> {
  BannerAd? _bannerAd;
  bool _isLoaded = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    if (AdService.shouldShowPassiveAds()) {
      _loadAd();
    }
  }

  void _loadAd() {
    final ad = BannerAd(
      adUnitId: AdService.bannerAdUnitId,
      size: widget.size,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) {
          if (!mounted) return;
          setState(() => _isLoaded = true);
        },
        onAdFailedToLoad: (ad, error) {
          AppLogger.warning('AdBannerWidget failed to load: $error');
          ad.dispose();
          if (!mounted) return;
          setState(() => _failed = true);
        },
      ),
    );
    _bannerAd = ad;
    ad.load();
  }

  @override
  void dispose() {
    _bannerAd?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!AdService.shouldShowPassiveAds() || _failed) {
      return const SizedBox.shrink();
    }
    if (!_isLoaded || _bannerAd == null) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    return Container(
      margin: widget.margin,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 6, 10, 4),
            child: Text(
              'Sponsored',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                letterSpacing: 0.4,
              ),
            ),
          ),
          SizedBox(
            width: widget.size.width.toDouble(),
            height: widget.size.height.toDouble(),
            child: AdWidget(ad: _bannerAd!),
          ),
        ],
      ),
    );
  }
}
