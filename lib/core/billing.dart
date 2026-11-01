import 'dart:async';

import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';

import 'plan.dart';

/// Result of tapping "subscribe" or "restore".
enum BillingResult { started, notAvailable, notPublished, error, restored, nothingToRestore }

/// Google Play subscription. The app only unlocks the paid plan for a purchase
/// Google Play reports as active; nothing is unlocked locally.
class Billing {
  Billing(this.onPremiumChanged);

  final void Function(bool premium) onPremiumChanged;
  // Touched only inside try blocks: it talks to the Play Store as soon as it is created.
  late final _iap = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _sub;
  ProductDetails? product;

  Future<void> start() async {
    try {
      if (!await _iap.isAvailable()) return;
      _sub = _iap.purchaseStream.listen(_onPurchases, onError: (_) {});
      await refresh();
      final res = await _iap.queryProductDetails({Plan.productId});
      product = res.productDetails.firstOrNull;
    } catch (_) {
      // No Play Store on this device (or tests): the app stays on the free plan.
    }
  }

  /// Asks Google Play which subscriptions are active right now, so a cancelled
  /// or expired one turns the paid plan off again.
  Future<bool?> refresh() async {
    try {
      final android = _iap.getPlatformAddition<InAppPurchaseAndroidPlatformAddition>();
      final res = await android.queryPastPurchases();
      if (res.error != null) return null;
      final active = res.pastPurchases.any((p) => p.productID == Plan.productId && p.status != PurchaseStatus.error);
      onPremiumChanged(active);
      for (final p in res.pastPurchases) {
        if (p.pendingCompletePurchase) await _iap.completePurchase(p);
      }
      return active;
    } catch (_) {
      return null;
    }
  }

  Future<BillingResult> buy() async {
    try {
      if (!await _iap.isAvailable()) return BillingResult.notAvailable;
      if (product == null) {
        final res = await _iap.queryProductDetails({Plan.productId});
        product = res.productDetails.firstOrNull;
      }
      final p = product;
      if (p == null) return BillingResult.notPublished;
      final ok = await _iap.buyNonConsumable(purchaseParam: PurchaseParam(productDetails: p));
      return ok ? BillingResult.started : BillingResult.error;
    } catch (_) {
      return BillingResult.error;
    }
  }

  Future<BillingResult> restore() async {
    final active = await refresh();
    if (active == null) return BillingResult.notAvailable;
    return active ? BillingResult.restored : BillingResult.nothingToRestore;
  }

  Future<void> _onPurchases(List<PurchaseDetails> list) async {
    for (final p in list) {
      if (p.productID != Plan.productId) continue;
      if (p.status == PurchaseStatus.purchased || p.status == PurchaseStatus.restored) onPremiumChanged(true);
      if (p.pendingCompletePurchase) await _iap.completePurchase(p);
    }
  }

  void dispose() => _sub?.cancel();
}
