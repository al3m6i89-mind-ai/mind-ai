import 'dart:async';
import 'dart:math';

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

  /// Price in points when the screen does not pick a specific tool.
  int get defaultPoints => switch (this) {
    Usage.chat => 0,
    Usage.image => 1,
    Usage.sticker => 2,
    Usage.video => 5,
    Usage.codeAgent => 3,
    Usage.apkBuild => 5,
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
    required this.points,
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

  /// Points granted every month. Each tool costs points (see providers/tools.dart).
  final int points;
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
    points: 0,
    perks: [
      '${SubscriptionService.welcomePoints} نقطة هدية عند التسجيل',
      'محادثة ذكية',
      'حتى 15 صورة وملصق يومياً',
      'فيديوهين يومياً',
      'بناء APK مرتين يومياً',
    ],
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
    points: 3000,
    perks: [
      '3000 نقطة شهرياً',
      '200 صورة وملصق يومياً',
      '20 فيديو يومياً',
      'وكيل أكواد متقدم',
      '20 بناء APK يومياً',
      'بدون إعلانات',
    ],
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
    points: 10000,
    perks: ['10000 نقطة شهرياً', 'كل شيء بلا حدود تقريباً', '100 فيديو يومياً', 'أولوية في السرعة', 'دعم مباشر'],
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

/// A one-time Google Play purchase that adds points to the wallet.
class PointsPack {
  const PointsPack(this.productId, this.points, this.price, {this.bonus = ''});
  final String productId;
  final int points;

  /// Shown when the store price is not loaded yet.
  final String price;
  final String bonus;

  static const all = [
    PointsPack('mindai_points_300', 300, '\$0.99'),
    PointsPack('mindai_points_1000', 1000, '\$2.99', bonus: '+10%'),
    PointsPack('mindai_points_3500', 3500, '\$7.99', bonus: '+30%'),
    PointsPack('mindai_points_10000', 10000, '\$19.99', bonus: 'الأوفر'),
  ];
}

class NotEnoughPoints implements Exception {
  NotEnoughPoints(this.need, this.left);
  final int need;
  final int left;
  @override
  String toString() => 'هذي الأداة تحتاج $need نقطة وباقي عندك $left. اشترِ نقاط أو اختر أداة أرخص.';
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

  String get _month {
    final d = DateTime.now();
    return '${d.year}-${d.month}';
  }

  /// Points given once when a user signs in for the first time.
  static const welcomePoints = 200;

  int get pointsUsed => _prefs.getInt('pts_$_month') ?? 0;

  /// Plan points left this month; they reset on the 1st.
  int get monthlyLeft => max(0, plan.points - pointsUsed);

  /// Points that never expire: the welcome gift and purchased packs.
  int get wallet => _prefs.getInt('wallet') ?? 0;

  int get pointsLeft => monthlyLeft + wallet;

  bool get welcomed => _prefs.getBool('welcomed') ?? false;

  /// Gives the welcome gift once. Returns true when it was given now.
  Future<bool> grantWelcome() async {
    if (welcomed) return false;
    await _prefs.setBool('welcomed', true);
    await _addToWallet(welcomePoints);
    return true;
  }

  Future<void> _addToWallet(int n) async {
    await _prefs.setInt('wallet', wallet + n);
    notifyListeners();
  }

  /// Call before an action. Throws [QuotaExceeded] when the daily limit is hit,
  /// or [NotEnoughPoints] when the month's points can't pay for it.
  void ensure(Usage u, {int? points}) {
    final l = limit(u);
    if (l >= 0 && used(u) >= l) throw QuotaExceeded(u, l);
    final cost = points ?? u.defaultPoints;
    if (cost > pointsLeft) throw NotEnoughPoints(cost, pointsLeft);
  }

  Future<void> consume(Usage u, {int? points}) async {
    await _prefs.setInt('use_${_today}_${u.name}', used(u) + 1);
    // Monthly plan points are spent first, then the wallet.
    final cost = points ?? u.defaultPoints;
    final fromMonth = min(cost, monthlyLeft);
    await _prefs.setInt('pts_$_month', pointsUsed + fromMonth);
    await _prefs.setInt('wallet', max(0, wallet - (cost - fromMonth)));
    notifyListeners();
  }

  Future<void> init() async {
    try {
      storeAvailable = await _iap.isAvailable();
      if (!storeAvailable) return;
      _sub = _iap.purchaseStream.listen(_onPurchases);
      final ids = {
        ...Plan.all.map((p) => p.productId).where((id) => id.isNotEmpty),
        ...PointsPack.all.map((p) => p.productId),
      };
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

  String priceOfPack(PointsPack p) => products[p.productId]?.price ?? p.price;

  Future<void> buyPack(PointsPack p) async {
    final product = products[p.productId];
    if (product == null) {
      throw Exception(
        'المتجر غير متاح الآن. أضف باقة النقاط ${p.productId} كمنتج داخل التطبيق في Google Play Console.',
      );
    }
    await _iap.buyConsumable(purchaseParam: PurchaseParam(productDetails: product));
  }

  Future<void> restore() => _iap.restorePurchases();

  Future<void> _onPurchases(List<PurchaseDetails> list) async {
    for (final pd in list) {
      final pack = PointsPack.all.where((p) => p.productId == pd.productID).firstOrNull;
      if (pack != null) {
        // Consumables are never "restored", so each purchase is credited once.
        if (pd.status == PurchaseStatus.purchased) await _addToWallet(pack.points);
      } else if (pd.status == PurchaseStatus.purchased || pd.status == PurchaseStatus.restored) {
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
