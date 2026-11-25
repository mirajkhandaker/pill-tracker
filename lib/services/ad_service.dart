import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../core/constants/ad_ids.dart';
import '../core/utils/app_logger.dart';

/// Thin wrapper around google_mobile_ads.
///
/// PillTrack only shows ads *inside* its screens (a banner on Home and inline
/// ad cards in content) — never full-screen interstitial or rewarded ads that
/// take the user out of what they were doing. Ad failures never surface to the
/// UI: a failed ad simply doesn't appear.
class AdService {
  AdService._();
  static final AdService instance = AdService._();

  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;
    await MobileAds.instance.initialize();
    _initialized = true;
  }

  /// A fresh banner ad of [size]. The caller owns loading/disposing;
  /// [onLoaded] fires once the ad is ready to render.
  BannerAd createBannerAd({
    AdSize size = AdSize.banner,
    required VoidCallback onLoaded,
  }) {
    return BannerAd(
      adUnitId: AdIds.banner,
      size: size,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) => onLoaded(),
        onAdFailedToLoad: (ad, error) {
          AppLogger.warn('Banner ad failed to load', error);
          ad.dispose();
        },
      ),
    );
  }
}
