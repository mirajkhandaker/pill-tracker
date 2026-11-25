import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../../../core/utils/app_logger.dart';
import '../../../services/ad_service.dart';

/// An ad shown inside a screen's content (not full-screen): an inline
/// adaptive banner sized to the available width.
///
/// It's labelled "Advertisement" and outlined so it can never be mistaken for
/// medicine information. Takes no space until an ad has actually loaded, so a
/// failed or slow ad leaves no gap.
class InlineAdCard extends StatelessWidget {
  const InlineAdCard({super.key});

  /// Keeps the ad from dominating a screen of medicine information.
  static const int maxAdHeight = 250;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) =>
          _InlineAd(width: constraints.maxWidth.floor()),
    );
  }
}

class _InlineAd extends StatefulWidget {
  const _InlineAd({required this.width});
  final int width;

  @override
  State<_InlineAd> createState() => _InlineAdState();
}

class _InlineAdState extends State<_InlineAd>
    with AutomaticKeepAliveClientMixin {
  BannerAd? _ad;
  AdSize? _size;

  @override
  void initState() {
    super.initState();
    // The card has 1px border + 12px padding on each side.
    final adWidth = widget.width - 26;
    if (adWidth < 250) return; // too narrow for an inline ad; show nothing
    final ad = AdService.instance.createBannerAd(
      size: AdSize.getInlineAdaptiveBannerAdSize(
        adWidth,
        InlineAdCard.maxAdHeight,
      ),
      onLoaded: _onLoaded,
    );
    _ad = ad;
    ad.load();
  }

  Future<void> _onLoaded() async {
    try {
      // Inline adaptive ads pick their height at load time.
      final size = await _ad?.getPlatformAdSize();
      if (mounted && size != null) {
        setState(() => _size = size);
        updateKeepAlive();
      }
    } catch (e) {
      AppLogger.warn('Inline ad size unavailable', e);
    }
  }

  /// Keep the loaded ad when scrolled off-screen in a list, rather than
  /// disposing it and requesting a new one on the way back.
  @override
  bool get wantKeepAlive => _size != null;

  @override
  void dispose() {
    _ad?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final ad = _ad;
    final size = _size;
    if (ad == null || size == null) return const SizedBox.shrink();

    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 12),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Advertisement',
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: SizedBox(
              width: size.width.toDouble(),
              height: size.height.toDouble(),
              child: AdWidget(ad: ad),
            ),
          ),
        ],
      ),
    );
  }
}
