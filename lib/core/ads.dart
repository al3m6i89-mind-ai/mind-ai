import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// Full-screen ads for the free plan (AdMob). The ad unit comes from the build
/// (secret ADMOB_INTERSTITIAL); without it no ad is ever requested.
class Ads {
  static const unit = String.fromEnvironment('ADMOB_INTERSTITIAL');
  static bool get configured => unit.isNotEmpty;

  static Future<void>? _init;

  /// Loads and shows one ad. Returns true when it was shown. Gives up quietly
  /// (no network, no ad to show, ad blocked) after [wait].
  static Future<bool> showInterstitial({Duration wait = const Duration(seconds: 8)}) async {
    if (!configured) return false;
    try {
      await (_init ??= MobileAds.instance.initialize().then((_) {}));
      final loaded = Completer<InterstitialAd?>();
      await InterstitialAd.load(
        adUnitId: unit,
        request: const AdRequest(),
        adLoadCallback: InterstitialAdLoadCallback(
          onAdLoaded: (ad) => loaded.complete(ad),
          onAdFailedToLoad: (e) {
            debugPrint('ad: $e');
            loaded.complete(null);
          },
        ),
      );
      final ad = await loaded.future.timeout(wait, onTimeout: () => null);
      if (ad == null) return false;
      final closed = Completer<void>();
      ad.fullScreenContentCallback = FullScreenContentCallback(
        onAdDismissedFullScreenContent: (a) {
          a.dispose();
          closed.complete();
        },
        onAdFailedToShowFullScreenContent: (a, e) {
          a.dispose();
          closed.complete();
        },
      );
      await ad.show();
      await closed.future;
      return true;
    } catch (e) {
      debugPrint('ad: $e');
      return false;
    }
  }
}
