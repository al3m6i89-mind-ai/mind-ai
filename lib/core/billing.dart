import 'dart:async';

import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';

import 'plan.dart';

/// Result of tapping "subscribe" or "restore".
enum BillingResult { started, notAvailable, notPublished, error, restored, nothingToRestore }

/// Google Play subscription. The app only unlocks the paid plan for a purchase
/// Google Play reports as active, and the proxy checks that purchase with
/// Google again (by its token) before it allows the paid limits.
class Billing {
  Billing(this.onPremiumChanged);

  /// [token] is the Play purchase token of the active subscription, if any.
  final Future<void> Function(bool premium, String? token) onPremiumChanged;
  // Touched only inside try blocks: it talks to the Play Store as soon as it is created.
  late final _iap = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _sub;

  /// The monthly and yearly subscriptions as Google Play lists them (prices in the user's currency).
  final Map<String, ProductDetails> products = {};
  ProductDetails? get product => products[Plan.monthlyId];

  Future<void> _load() async {
    final res = await _iap.queryProductDetails(Plan.productIds);
    for (final p in res.productDetails) {
      products[p.id] = p;
    }
  }

  Future<void> start() async {
    try {
      if (!await _iap.isAvailable()) return;
      _sub = _iap.purchaseStream.listen(_onPurchases, onError: (_) {});
      await refresh();
      await _load();
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
      final mine = res.pastPurchases.where((p) => Plan.productIds.contains(p.productID) && p.status != PurchaseStatus.error);
      final active = mine.isNotEmpty;
      await onPremiumChanged(active, active ? mine.first.verificationData.serverVerificationData : null);
      for (final p in res.pastPurchases) {
        if (p.pendingCompletePurchase) await _iap.completePurchase(p);
      }
      return active;
    } catch (_) {
      return null;
    }
  }

  /// Starts buying [id] (monthly by default).
  Future<BillingResult> buy([String id = Plan.monthlyId]) async {
    try {
      if (!await _iap.isAvailable()) return BillingResult.notAvailable;
      if (products[id] == null) await _load();
      final p = products[id];
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
      if (!Plan.productIds.contains(p.productID)) continue;
      if (p.status == PurchaseStatus.purchased || p.status == PurchaseStatus.restored) {
        await onPremiumChanged(true, p.verificationData.serverVerificationData);
      }
      if (p.pendingCompletePurchase) await _iap.completePurchase(p);
    }
  }

  void dispose() => _sub?.cancel();
}
