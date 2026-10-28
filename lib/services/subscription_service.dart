import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// What a user spends when using Mind Ai. Each feature has its own daily limit.
enum Usage { chat, image, sticker, video, codeAgent, apkBuild }

extension UsageInfo on Usage {
  String get label => switch (this) {
        Usage.chat => 'رسائل المحادثة',
        Usage.image => 'الصور',
        Usage.sticker => 'الملصقات',
        Usage.video => 'الفيديوهات',
        Usage.codeAgent => 'طلبات وكيل الأكواد',
        Usage.apkBuild => 'بناء APK',
      };
}

/// A subscription tier. Edit [Plan.all] to change prices, names or limits;
/// the paywall and the quota checks read from here.
class Plan {
  const Plan({
    required this.id,
    required this.name,
    required this.price,
    required this.productId,
    required this.limits,
    required this.perks,
    this.highlight = false,
  });

  final String id;
  final String name;

  /// Shown when the store price is not loaded yet.
  final String price;

  /// Google Play subscription product id ('' for the free plan).
  final String productId;

  /// Daily limits. -1 means unlimited.
  final Map<Usage, int> limits;
  final List<String> perks;
  final bool highlight;

  static const free = Plan(
    id: 'free',
    name: 'مجاني',
    price: '0',
    productId: '',
    limits: {
      Usage.chat: 60,
      Usage.image: 15,
      Usage.sticker: 15,
      Usage.video: 2,
      Usage.codeAgent: 15,
      Usage.apkBuild: 2,
    },
    perks: ['محادثة ذكية', '15 صورة وملصق يومياً', 'ملصقات متحركة', 'بناء APK مرتين يومياً'],
  );

  static const pro = Plan(
    id: 'pro',
    name: 'Pro',
    price: '\$4.99 / شهر',
    productId: 'mindai_pro_monthly',
    limits: {
      Usage.chat: 1000,
      Usage.image: 200,
      Usage.sticker: 200,
      Usage.video: 20,
      Usage.codeAgent: 300,
      Usage.apkBuild: 20,
    },
    perks: ['200 صورة وملصق يومياً', '20 فيديو يومياً', 'وكيل أكواد متقدم', '20 بناء APK يومياً', 'بدون إعلانات'],
    highlight: true,
  );

  static const max = Plan(
    id: 'max',
    name: 'Max',
    price: '\$12.99 / شهر',
    productId: 'mindai_max_monthly',
    limits: {
      Usage.chat: -1,
      Usage.image: -1,
      Usage.sticker: -1,
      Usage.video: 100,
      Usage.codeAgent: -1,
      Usage.apkBuild: -1,
    },
    perks: ['كل شيء بلا حدود تقريباً', '100 فيديو يومياً', 'أولوية في السرعة', 'دعم مباشر'],
  );

  static const all = [free, pro, max];

  static Plan byId(String id) => all.firstWhere((p) => p.id == id, orElse: () => free);
}

class QuotaExceeded implements Exception {
  QuotaExceeded(this.usage, this.limit);
  final Usage usage;
  final int limit;
  @override
  String toString() => 'وصلت للحد اليومي من ${usage.label} ($limit). رقِّ اشتراكك للمزيد.';
}

class SubscriptionService extends ChangeNotifier {
  SubscriptionService(this._prefs);

  final SharedPreferences _prefs;
  InAppPurchase get _iap => InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _sub;
  Map<String, ProductDetails> products = {};
  bool storeAvailable = false;

  Plan get plan => Plan.byId(_prefs.getString('plan') ?? 'free');

  String get _today {
    final d = DateTime.now();
    return '${d.year}-${d.month}-${d.day}';
  }

  int used(Usage u) => _prefs.getInt('use_${_today}_${u.name}') ?? 0;

  int limit(Usage u) => plan.limits[u] ?? 0;

  int remaining(Usage u) => limit(u) < 0 ? 1 << 30 : (limit(u) - used(u)).clamp(0, 1 << 30);

  /// Call before an action. Throws [QuotaExceeded] when the daily limit is hit.
  void ensure(Usage u) {
    final l = limit(u);
    if (l >= 0 && used(u) >= l) throw QuotaExceeded(u, l);
  }

  Future<void> consume(Usage u, [int n = 1]) async {
    await _prefs.setInt('use_${_today}_${u.name}', used(u) + n);
    notifyListeners();
  }

  Future<void> init() async {
    try {
      storeAvailable = await _iap.isAvailable();
      if (!storeAvailable) return;
      _sub = _iap.purchaseStream.listen(_onPurchases);
      final ids = Plan.all.map((p) => p.productId).where((id) => id.isNotEmpty).toSet();
      final resp = await _iap.queryProductDetails(ids);
      products = {for (final p in resp.productDetails) p.id: p};
      await _iap.restorePurchases();
      notifyListeners();
    } catch (e) {
      debugPrint('IAP unavailable: $e');
    }
  }

  String priceOf(Plan p) => products[p.productId]?.price ?? p.price;

  Future<void> buy(Plan p) async {
    final product = products[p.productId];
    if (product == null) {
      throw Exception('المتجر غير متاح الآن. تأكد من نشر الاشتراك في Google Play Console.');
    }
    await _iap.buyNonConsumable(purchaseParam: PurchaseParam(productDetails: product));
  }

  Future<void> restore() => _iap.restorePurchases();

  Future<void> _onPurchases(List<PurchaseDetails> list) async {
    for (final pd in list) {
      if (pd.status == PurchaseStatus.purchased || pd.status == PurchaseStatus.restored) {
        // NOTE: for production, verify pd.verificationData on your server before granting.
        final plan = Plan.all.firstWhere((p) => p.productId == pd.productID, orElse: () => Plan.free);
        await _setPlan(plan);
      }
      if (pd.pendingCompletePurchase) await _iap.completePurchase(pd);
    }
  }

  Future<void> _setPlan(Plan p) async {
    await _prefs.setString('plan', p.id);
    notifyListeners();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
