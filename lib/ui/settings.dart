import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:url_launcher/url_launcher.dart';

import '../core/plan.dart';
import '../core/store.dart';
import '../core/strings.dart';
import 'account.dart';
import 'plans.dart';
import 'theme.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final s = S(store.lang);
    final primary = Theme.of(context).colorScheme.primary;

    Widget section(String title, List<Widget> children) => Padding(
          padding: const EdgeInsets.only(bottom: 22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(title, style: TextStyle(fontWeight: FontWeight.w700, color: primary)),
              ),
              ...children,
            ],
          ),
        );

    return Scaffold(
      appBar: AppBar(title: Text(s.t('settings'))),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            if (store.auth.available && store.auth.user != null)
              section(s.t('account'), [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const CircleAvatar(child: Icon(Icons.person_rounded)),
                  title: Text(store.auth.label ?? ''),
                  subtitle: Text(s.t('accountDetails'), style: TextStyle(color: context.muted, fontSize: 12.5)),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AccountScreen())),
                ),
              ]),
            section(s.t('subscription'), [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  color: store.premium ? const Color(0xFFF5B300).withValues(alpha: 0.12) : context.surface2,
                ),
                child: Row(children: [
                  Icon(store.premium ? Icons.workspace_premium_rounded : Icons.person_outline_rounded,
                      color: store.premium ? const Color(0xFFE0A100) : primary, size: 30),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(s.t(store.premium ? 'planPremium' : 'planFree'),
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                      const SizedBox(height: 3),
                      Text(
                        store.premium
                            ? s.t('premiumUsage')
                            : s.t('freeUsage', {'used': '${store.questionsToday}', 'total': '${Plan.freeDailyQuestions}'}),
                        style: TextStyle(color: context.muted, fontSize: 13, height: 1.4),
                      ),
                    ]),
                  ),
                  const SizedBox(width: 8),
                  store.premium
                      ? OutlinedButton(
                          onPressed: () => launchUrl(
                              Uri.parse('https://play.google.com/store/account/subscriptions'
                                  '?sku=${Plan.productId}&package=com.zuhair.file_chat'),
                              mode: LaunchMode.externalApplication),
                          child: Text(s.t('manage')),
                        )
                      : FilledButton(onPressed: () => openPlans(context), child: Text(s.t('upgrade'))),
                ]),
              ),
            ]),
            section(s.t('theme'), [
              SegmentedButton<ThemeMode>(
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(value: ThemeMode.system, label: Text(s.t('themeSystem'))),
                  ButtonSegment(value: ThemeMode.light, label: Text(s.t('themeLight'))),
                  ButtonSegment(value: ThemeMode.dark, label: Text(s.t('themeDark'))),
                ],
                selected: {store.themeMode},
                onSelectionChanged: (v) => store.setThemeMode(v.first),
              ),
            ]),
            section(s.t('language'), [
              SegmentedButton<String>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: 'ar', label: Text('العربية')),
                  ButtonSegment(value: 'en', label: Text('English')),
                ],
                selected: {store.lang},
                onSelectionChanged: (v) => store.setLang(v.first),
              ),
            ]),
            section(s.t('about'), [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(Icons.lock_outline, size: 20, color: context.muted),
                const SizedBox(width: 8),
                Expanded(child: Text(s.t('privacy'), style: TextStyle(color: context.muted, height: 1.5))),
              ]),
            ]),
          ],
        ),
      ),
    );
  }
}
