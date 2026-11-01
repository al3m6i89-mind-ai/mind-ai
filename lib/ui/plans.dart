import 'package:flutter/material.dart';
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

class PlansScreen extends StatefulWidget {
  const PlansScreen({super.key});

  @override
  State<PlansScreen> createState() => _PlansScreenState();
}

class _PlansScreenState extends State<PlansScreen> {
  bool _busy = false;

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
    final price = store.billing.product?.price;
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
              price: price == null ? s.t('monthly') : '$price / ${s.t('month')}',
              highlight: true,
              current: store.premium,
              s: s,
              features: [
                s.t('fUnlimitedQ'),
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
                s.t('fFreeFiles'),
                s.t('fChain'),
                s.t('fAllTypes'),
              ],
            ),
            const SizedBox(height: 20),
            if (!store.premium) ...[
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: gold, foregroundColor: Colors.black, padding: const EdgeInsets.symmetric(vertical: 16)),
                icon: _busy
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                    : const Icon(Icons.workspace_premium_rounded),
                label: Text(s.t('subscribe'), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                onPressed: _busy ? null : () => _run(store.billing.buy),
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
            Text(s.t('billNote'), textAlign: TextAlign.center, style: TextStyle(color: context.muted, fontSize: 12, height: 1.5)),
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
