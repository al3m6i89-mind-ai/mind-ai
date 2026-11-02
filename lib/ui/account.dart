import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/plan.dart';
import '../core/store.dart';
import '../core/strings.dart';
import 'plans.dart';
import 'theme.dart';

/// Who is signed in and what their plan allows.
class AccountScreen extends StatelessWidget {
  const AccountScreen({super.key});

  static String _date(DateTime? d) {
    if (d == null) return '—';
    d = d.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year}/${two(d.month)}/${two(d.day)}  ${two(d.hour)}:${two(d.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final s = S(store.lang);
    final scheme = Theme.of(context).colorScheme;
    final u = store.auth.user;
    final premium = store.premium;
    const gold = Color(0xFFE0A100);

    final google = u?.providerData.any((p) => p.providerId == 'google.com') ?? false;
    final phone = u?.phoneNumber;
    final email = u?.email;
    final name = u?.displayName;

    Widget card(String title, List<Widget> rows) => Container(
          margin: const EdgeInsets.only(bottom: 18),
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
          decoration: BoxDecoration(color: context.surface2, borderRadius: BorderRadius.circular(18)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(title, style: TextStyle(fontWeight: FontWeight.w700, color: scheme.primary)),
            const SizedBox(height: 6),
            ...rows,
          ]),
        );

    Widget row(IconData icon, String label, String value, {Color? color}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 9),
          child: Row(children: [
            Icon(icon, size: 19, color: context.muted),
            const SizedBox(width: 10),
            Text(label, style: TextStyle(color: context.muted, fontSize: 13.5)),
            const SizedBox(width: 12),
            Expanded(
              child: Text(value,
                  textAlign: TextAlign.end,
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: color)),
            ),
          ]),
        );

    final now = DateTime.now();
    final left = DateTime(now.year, now.month, now.day + 1).difference(now);
    final price = store.billing.product?.price;

    final initial = (name ?? email ?? phone ?? '?').trim();
    return Scaffold(
      appBar: AppBar(title: Text(s.t('account'))),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            Center(
              child: Column(children: [
                CircleAvatar(
                  radius: 38,
                  backgroundColor: scheme.primary.withValues(alpha: 0.18),
                  backgroundImage: u?.photoURL == null ? null : NetworkImage(u!.photoURL!),
                  child: u?.photoURL != null
                      ? null
                      : Text(initial.isEmpty ? '?' : initial.characters.first.toUpperCase(),
                          style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700, color: scheme.primary)),
                ),
                const SizedBox(height: 10),
                Text(store.auth.label ?? s.t('notSignedIn'),
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: (premium ? gold : scheme.primary).withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(premium ? Icons.workspace_premium_rounded : Icons.person_outline_rounded,
                        size: 16, color: premium ? gold : scheme.primary),
                    const SizedBox(width: 5),
                    Text(s.t(premium ? 'planPremium' : 'planFree'),
                        style: TextStyle(fontWeight: FontWeight.w600, color: premium ? gold : scheme.primary)),
                  ]),
                ),
                const SizedBox(height: 18),
              ]),
            ),
            if (u != null)
              card(s.t('accountDetails'), [
                if (name != null && name.isNotEmpty) row(Icons.badge_outlined, s.t('fName'), name),
                if (email != null && email.isNotEmpty) row(Icons.alternate_email_rounded, s.t('fEmail'), email),
                if (phone != null && phone.isNotEmpty)
                  row(Icons.phone_iphone_rounded, s.t('fPhone'), phone),
                row(Icons.login_rounded, s.t('fMethod'), google ? 'Google' : (phone != null && phone.isNotEmpty) ? s.t('methodPhone') : s.t('methodEmail')),
                row(Icons.event_outlined, s.t('fCreated'), _date(u.metadata.creationTime)),
                row(Icons.schedule_rounded, s.t('fLastIn'), _date(u.metadata.lastSignInTime)),
              ]),
            card(s.t('yourPlan'), [
              row(Icons.workspace_premium_outlined, s.t('plans'), s.t(premium ? 'planPremium' : 'planFree'),
                  color: premium ? gold : null),
              row(Icons.payments_outlined, s.t('fPrice'),
                  premium ? (price == null ? s.t('monthly') : '$price / ${s.t('month')}') : s.t('free')),
              if (premium) row(Icons.autorenew_rounded, s.t('fRenew'), s.t('renewPlay')),
              row(Icons.chat_bubble_outline_rounded, s.t('fUsedToday'),
                  premium ? '${store.questionsToday}' : '${store.questionsToday} / ${Plan.freeDailyQuestions}'),
              row(Icons.hourglass_bottom_rounded, s.t('fLeftToday'),
                  premium ? s.t('unlimitedL') : '${store.questionsLeft}'),
              if (!premium)
                row(Icons.restart_alt_rounded, s.t('fResets'),
                    s.t('resetsMidnight', {'h': '${left.inHours}', 'm': '${left.inMinutes % 60}'})),
              row(Icons.insert_drive_file_outlined, s.t('fMaxFile'),
                  s.t('mbN', {'n': '${(premium ? Plan.premiumMaxFileBytes : Plan.freeMaxFileBytes) ~/ (1024 * 1024)}'})),
              row(Icons.shield_outlined, s.t('fAdblock'), s.t(premium ? 'adNotNeeded' : 'adMustOff')),
              Padding(
                padding: const EdgeInsets.only(top: 8, bottom: 10),
                child: premium
                    ? OutlinedButton.icon(
                        icon: const Icon(Icons.open_in_new_rounded, size: 18),
                        label: Text(s.t('manage')),
                        onPressed: () => launchUrl(
                            Uri.parse('https://play.google.com/store/account/subscriptions'
                                '?sku=${Plan.productId}&package=com.zuhair.file_chat'),
                            mode: LaunchMode.externalApplication),
                      )
                    : FilledButton.icon(
                        icon: const Icon(Icons.workspace_premium_rounded, size: 18),
                        label: Text(s.t('upgrade')),
                        onPressed: () => openPlans(context),
                      ),
              ),
            ]),
            if (u != null)
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: context.danger,
                  side: BorderSide(color: context.danger.withValues(alpha: 0.5)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                icon: const Icon(Icons.logout_rounded),
                label: Text(s.t('signOut')),
                onPressed: () async {
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: Text(s.t('signOutQ')),
                      content: Text(s.t('signOutText')),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(s.t('cancel'))),
                        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(s.t('signOut'))),
                      ],
                    ),
                  );
                  if (ok == true) {
                    await store.auth.signOut();
                    if (context.mounted) Navigator.popUntil(context, (r) => r.isFirst);
                  }
                },
              ),
          ],
        ),
      ),
    );
  }
}
