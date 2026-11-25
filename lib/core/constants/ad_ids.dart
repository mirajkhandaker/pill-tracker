import 'package:flutter/foundation.dart';

/// AdMob unit ids. Google's public test id is used in debug/profile builds;
/// the production id is used in release builds (`kReleaseMode`).
///
/// PillTrack only uses banner ads (the Home banner and inline ad cards), so a
/// single banner ad unit serves both — no interstitial or rewarded units.
///
/// TODO(launch): replace the production id with the real AdMob banner unit id
/// from the AdMob console before shipping (see Phase 9.2 in the build plan).
abstract final class AdIds {
  // Google test id (safe to click during development).
  static const _testBanner = 'ca-app-pub-3940256099942544/6300978111';

  // Production id (placeholder until the real unit exists).
  static const _prodBanner = 'ca-app-pub-0000000000000000/0000000000';

  static String get banner => kReleaseMode ? _prodBanner : _testBanner;
}
