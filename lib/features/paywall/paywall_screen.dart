import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/theme.dart';
import '../../services/subscription_service.dart';
import '../../widgets/common.dart';

class PaywallScreen extends StatelessWidget {
  const PaywallScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final subs = context.watch<SubscriptionService>();
    return Scaffold(
      appBar: AppBar(title: const Text('الاشتراكات')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Center(child: Text('👑', style: TextStyle(fontSize: 56))),
          const Center(
            child: GradientText('أطلق قوة Mind Ai كاملة', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
          ),
          const SizedBox(height: 6),
          const Center(
            child: Text('ابدأ مجاناً، ورقِّ متى ما احتجت أكثر', style: TextStyle(color: MindColors.muted)),
          ),
          const SizedBox(height: 18),
          for (final p in Plan.all) _PlanCard(plan: p, current: subs.plan.id == p.id),
          const SizedBox(height: 8),
          TextButton(onPressed: subs.restore, child: const Text('استعادة المشتريات')),
          const SizedBox(height: 12),
          const Text('استخدامك اليوم', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
          const SizedBox(height: 8),
          for (final u in Usage.values)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  SizedBox(width: 130, child: Text(u.label)),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: LinearProgressIndicator(
                        minHeight: 8,
                        value: subs.limit(u) <= 0 ? 0 : (subs.used(u) / subs.limit(u)).clamp(0, 1),
                        color: MindColors.pink,
                        backgroundColor: MindColors.violet.withValues(alpha: 0.1),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(subs.limit(u) < 0 ? '${subs.used(u)} / ∞' : '${subs.used(u)} / ${subs.limit(u)}'),
                ],
              ),
            ),
          const SizedBox(height: 12),
          const Text(
            'يتجدد الاشتراك شهرياً عبر Google Play ويمكنك إلغاؤه في أي وقت من إعدادات المتجر.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: MindColors.muted),
          ),
        ],
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({required this.plan, required this.current});
  final Plan plan;
  final bool current;

  @override
  Widget build(BuildContext context) {
    final subs = context.read<SubscriptionService>();
    final card = Theme.of(context).cardTheme.color!;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(2.5),
      decoration: BoxDecoration(
        gradient: plan.highlight ? MindColors.brand : null,
        color: plan.highlight ? null : MindColors.violet.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: card, borderRadius: BorderRadius.circular(22)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(plan.name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
                const SizedBox(width: 8),
                if (plan.highlight)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(gradient: MindColors.sunset, borderRadius: BorderRadius.circular(10)),
                    child: const Text('الأكثر طلباً',
                        style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800)),
                  ),
                const Spacer(),
                Text(plan.id == 'free' ? 'مجاناً' : subs.priceOf(plan),
                    style: const TextStyle(fontWeight: FontWeight.w900, color: MindColors.violet)),
              ],
            ),
            const SizedBox(height: 10),
            for (final perk in plan.perks)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(children: [
                  const Icon(Icons.check_circle, size: 18, color: MindColors.mint),
                  const SizedBox(width: 6),
                  Expanded(child: Text(perk)),
                ]),
              ),
            const SizedBox(height: 10),
            if (current)
              const Center(child: Text('✅ باقتك الحالية', style: TextStyle(fontWeight: FontWeight.w800)))
            else if (plan.id != 'free')
              SizedBox(
                width: double.infinity,
                child: GradientButton(
                  label: 'اشترك في ${plan.name}',
                  gradient: plan.highlight ? MindColors.brand : MindColors.cool,
                  onPressed: () async {
                    try {
                      await subs.buy(plan);
                    } catch (e) {
                      if (context.mounted) showError(context, e);
                    }
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}
