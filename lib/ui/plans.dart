import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart' show ProductDetails;
import 'package:provider/provider.dart';

import '../core/billing.dart';
import '../core/plan.dart';
import '../core/store.dart';
import '../core/strings.dart';
import 'theme.dart';

void openPlans(BuildContext context) =>
    Navigator.push(context, MaterialPageRoute(builder: (_) => const PlansScreen()));

/// Shown when the free plan's limit stops something: says why and offers the paid plan.
Future<void> showPaywall(BuildContext context, String reason) {
  final s = S(context.read<AppStore>().lang);
  return showModalBottomSheet<void>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 0, 22, 22),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: const Color(0xFFF5B300).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Icon(Icons.workspace_premium_rounded, color: Color(0xFFE0A100), size: 30),
          ),
          const SizedBox(height: 14),
          Text(reason, textAlign: TextAlign.center, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, height: 1.4)),
          const SizedBox(height: 8),
          Text(s.t('paywallText'), textAlign: TextAlign.center, style: TextStyle(color: ctx.muted, height: 1.5)),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              icon: const Icon(Icons.workspace_premium_rounded),
              label: Text(s.t('seePlans')),
              onPressed: () {
                Navigator.pop(ctx);
                openPlans(context);
              },
            ),
          ),
        ]),
      ),
    ),
  );
}

/// Prices as Google Play reports them, or the list prices until it does.
class Prices {
  Prices(AppStore store)
      : monthly = store.billing.products[Plan.monthlyId],
        yearly = store.billing.products[Plan.yearlyId];
  final ProductDetails? monthly, yearly;

  String get monthlyText => monthly?.price ?? '\$${Plan.monthlyUsd}';
  String get yearlyText => yearly?.price ?? '\$${Plan.yearlyUsd}';

  /// The yearly plan's price per month, in the same currency.
  String get yearlyPerMonth {
    final y = yearly;
    if (y == null) return '\$${(Plan.yearlyUsd / 12).toStringAsFixed(2)}';
    return '${y.currencySymbol}${(y.rawPrice / 12).toStringAsFixed(2)}';
  }

  int get saving {
    final m = monthly, y = yearly;
    if (m == null || y == null || m.rawPrice <= 0) return Plan.yearlySaving;
    return (100 - y.rawPrice / (m.rawPrice * 12) * 100).round();
  }
}

/// The subscription offer in the middle of the screen, for the free plan.
Future<void> showPromo(BuildContext context) {
  final store = context.read<AppStore>();
  final s = S(store.lang);
  final prices = Prices(store);
  const gold = Color(0xFFE0A100);
  Widget point(IconData icon, String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(children: [
          Icon(icon, size: 20, color: gold),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: const TextStyle(fontWeight: FontWeight.w600, height: 1.3))),
        ]),
      );
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.6),
    builder: (ctx) => Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 22, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 26, 20, 20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [gold.withValues(alpha: 0.22), gold.withValues(alpha: 0.0)],
                ),
              ),
              child: Column(children: [
                Container(
                  width: 68,
                  height: 68,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [Color(0xFFF5C451), gold]),
                    borderRadius: BorderRadius.circular(22),
                    boxShadow: [BoxShadow(color: gold.withValues(alpha: 0.4), blurRadius: 22, offset: const Offset(0, 8))],
                  ),
                  child: const Icon(Icons.workspace_premium_rounded, color: Colors.white, size: 38),
                ),
                const SizedBox(height: 14),
                Text(s.t('promoTitle'), textAlign: TextAlign.center, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                Text(s.t('promoText'), textAlign: TextAlign.center, style: TextStyle(color: ctx.muted, height: 1.5)),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 0, 22, 8),
              child: Column(children: [
                point(Icons.all_inclusive_rounded, s.t('fUnlimitedQ')),
                point(Icons.block_rounded, s.t('fNoAds')),
                point(Icons.draw_rounded, s.t('fHandwriting')),
                point(Icons.bolt_rounded, s.t('fFast')),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: gold.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: gold.withValues(alpha: 0.5)),
                  ),
                  child: Column(children: [
                    Text(s.t('promoYearly', {'p': prices.yearlyText, 'n': '${prices.saving}'}),
                        textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 2),
                    Text(s.t('perMonthOnly', {'p': prices.yearlyPerMonth}),
                        textAlign: TextAlign.center, style: TextStyle(color: ctx.muted, fontSize: 13)),
                  ]),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                        backgroundColor: gold, foregroundColor: Colors.black, padding: const EdgeInsets.symmetric(vertical: 15)),
                    icon: const Icon(Icons.workspace_premium_rounded),
                    label: Text(s.t('promoCta'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                    onPressed: () {
                      Navigator.pop(ctx);
                      openPlans(context);
                    },
                  ),
                ),
                TextButton(onPressed: () => Navigator.pop(ctx), child: Text(s.t('promoLater'))),
              ]),
            ),
          ]),
        ),
      ),
    ),
  );
}

class PlansScreen extends StatefulWidget {
  const PlansScreen({super.key});

  @override
  State<PlansScreen> createState() => _PlansScreenState();
}

class _PlansScreenState extends State<PlansScreen> {
  bool _busy = false;
  bool _yearly = true;

  Future<void> _run(Future<BillingResult> Function() action) async {
    final s = S(context.read<AppStore>().lang);
    setState(() => _busy = true);
    final r = await action();
    if (!mounted) return;
    setState(() => _busy = false);
    final msg = switch (r) {
      BillingResult.started => null,
      BillingResult.restored => s.t('billRestored'),
      BillingResult.nothingToRestore => s.t('billNothing'),
      BillingResult.notAvailable => s.t('billNoStore'),
      BillingResult.notPublished => s.t('billNotPublished'),
      BillingResult.error => s.t('billError'),
    };
    if (msg != null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 6)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final s = S(store.lang);
    final scheme = Theme.of(context).colorScheme;
    final prices = Prices(store);
    const gold = Color(0xFFE0A100);

    return Scaffold(
      appBar: AppBar(title: Text(s.t('plans'))),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          children: [
            Center(
              child: Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [Color(0xFFF5C451), Color(0xFFE0A100)]),
                  borderRadius: BorderRadius.circular(22),
                  boxShadow: [BoxShadow(color: gold.withValues(alpha: 0.35), blurRadius: 24, offset: const Offset(0, 8))],
                ),
                child: const Icon(Icons.workspace_premium_rounded, color: Colors.white, size: 40),
              ),
            ),
            const SizedBox(height: 16),
            Text(s.t('plansTitle'), textAlign: TextAlign.center, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text(s.t('plansSubtitle'), textAlign: TextAlign.center, style: TextStyle(color: context.muted, height: 1.5)),
            const SizedBox(height: 22),
            _PlanCard(
              title: s.t('planPremium'),
              price: _yearly ? '${prices.yearlyText} / ${s.t('year')}' : '${prices.monthlyText} / ${s.t('month')}',
              highlight: true,
              current: store.premium,
              s: s,
              features: [
                s.t('fUnlimitedQ'),
                s.t('fNoAds'),
                s.t('fHandwriting'),
                s.t('fUnlimitedFiles'),
                s.t('fPro'),
                s.t('fChain'),
                s.t('fAllTypes'),
              ],
            ),
            const SizedBox(height: 12),
            _PlanCard(
              title: s.t('planFree'),
              price: s.t('free'),
              highlight: false,
              current: !store.premium,
              s: s,
              features: [
                s.t('fFreeQ', {'n': '${Plan.freeDailyQuestions}'}),
                s.t('fWithAds'),
                s.t('fFreeFiles'),
                s.t('fChain'),
                s.t('fAllTypes'),
              ],
            ),
            const SizedBox(height: 20),
            if (!store.premium) ...[
              Row(children: [
                Expanded(
                  child: _Period(
                    title: s.t('yearly'),
                    price: prices.yearlyText,
                    sub: s.t('perMonthOnly', {'p': prices.yearlyPerMonth}),
                    badge: s.t('savePct', {'n': '${prices.saving}'}),
                    selected: _yearly,
                    onTap: () => setState(() => _yearly = true),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _Period(
                    title: s.t('monthlyShort'),
                    price: prices.monthlyText,
                    sub: '/ ${s.t('month')}',
                    selected: !_yearly,
                    onTap: () => setState(() => _yearly = false),
                  ),
                ),
              ]),
              const SizedBox(height: 14),
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: gold, foregroundColor: Colors.black, padding: const EdgeInsets.symmetric(vertical: 16)),
                icon: _busy
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                    : const Icon(Icons.workspace_premium_rounded),
                label: Text(s.t('subscribe'), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                onPressed: _busy ? null : () => _run(() => store.billing.buy(_yearly ? Plan.yearlyId : Plan.monthlyId)),
              ),
              const SizedBox(height: 10),
              Text(s.t('freeLeft', {'n': '${store.questionsLeft}'}),
                  textAlign: TextAlign.center, style: TextStyle(color: context.muted, fontSize: 13)),
            ] else
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: scheme.primary.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(14)),
                child: Row(children: [
                  Icon(Icons.verified_rounded, color: scheme.primary),
                  const SizedBox(width: 10),
                  Expanded(child: Text(s.t('youArePremium'), style: const TextStyle(fontWeight: FontWeight.w600))),
                ]),
              ),
            const SizedBox(height: 6),
            TextButton(onPressed: _busy ? null : () => _run(store.billing.restore), child: Text(s.t('restore'))),
            const SizedBox(height: 6),
            Text(s.t('billNoteBoth'), textAlign: TextAlign.center, style: TextStyle(color: context.muted, fontSize: 12, height: 1.5)),
          ],
        ),
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.title,
    required this.price,
    required this.highlight,
    required this.current,
    required this.features,
    required this.s,
  });
  final String title;
  final String price;
  final bool highlight;
  final bool current;
  final List<String> features;
  final S s;

  @override
  Widget build(BuildContext context) {
    const gold = Color(0xFFE0A100);
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: highlight ? gold : context.border, width: highlight ? 1.6 : 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            if (highlight) const Padding(padding: EdgeInsetsDirectional.only(end: 8), child: Icon(Icons.workspace_premium_rounded, color: gold)),
            Expanded(child: Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700))),
            if (current)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: scheme.primary.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
                child: Text(s.t('currentPlan'), style: TextStyle(color: scheme.primary, fontSize: 12, fontWeight: FontWeight.w600)),
              ),
          ]),
          const SizedBox(height: 4),
          Text(price, style: TextStyle(color: highlight ? gold : context.muted, fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          for (final f in features)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(Icons.check_circle_rounded, size: 18, color: highlight ? gold : scheme.primary),
                const SizedBox(width: 10),
                Expanded(child: Text(f, style: const TextStyle(height: 1.45))),
              ]),
            ),
        ],
      ),
    );
  }
}


/// One billing period to pick: yearly (with its saving) or monthly.
class _Period extends StatelessWidget {
  const _Period({required this.title, required this.price, required this.sub, required this.selected, required this.onTap, this.badge});
  final String title, price, sub;
  final String? badge;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const gold = Color(0xFFE0A100);
    return Semantics(
      selected: selected,
      button: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
          decoration: BoxDecoration(
            color: selected ? gold.withValues(alpha: 0.12) : null,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: selected ? gold : context.border, width: selected ? 2 : 1),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w700))),
              if (badge != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(color: gold, borderRadius: BorderRadius.circular(20)),
                  child: Text(badge!, style: const TextStyle(color: Colors.black, fontSize: 11, fontWeight: FontWeight.w800)),
                ),
            ]),
            const SizedBox(height: 6),
            Text(price, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            Text(sub, style: TextStyle(color: context.muted, fontSize: 12)),
          ]),
        ),
      ),
    );
  }
}
