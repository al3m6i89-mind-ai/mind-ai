import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/store.dart';
import '../core/strings.dart';
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
            if (store.auth.available && store.auth.user != null)
              section(s.t('account'), [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const CircleAvatar(child: Icon(Icons.person_rounded)),
                  title: Text(store.auth.label ?? ''),
                  trailing: TextButton(
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
                    child: Text(s.t('signOut')),
                  ),
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
