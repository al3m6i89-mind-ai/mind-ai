import 'package:flutter/material.dart';
import 'package:provider/provider.dart' hide Provider;
import 'package:url_launcher/url_launcher.dart';

import '../core/ai.dart';
import '../core/store.dart';
import '../core/strings.dart';
import 'theme.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController _key;
  bool _show = false;

  @override
  void initState() {
    super.initState();
    _key = TextEditingController(text: context.read<AppStore>().geminiKey);
  }

  @override
  void dispose() {
    _key.dispose();
    super.dispose();
  }

  Future<void> _saveKey(AppStore store, S s) async {
    await store.setGeminiKey(_key.text);
    // Saving a key means the user wants Gemini.
    if (_key.text.trim().isNotEmpty) await store.setProvider(Provider.gemini);
    if (!mounted) return;
    FocusScope.of(context).unfocus();
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(s.t('keySaved')), behavior: SnackBarBehavior.floating));
  }

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
            section(s.t('providerTitle'), [
              RadioGroup<Provider>(
                groupValue: store.provider,
                onChanged: (v) {
                  if (v != null) store.setProvider(v);
                },
                child: Column(children: [
                  RadioListTile<Provider>(value: Provider.gemini, title: Text(s.t('gemini')), contentPadding: EdgeInsets.zero),
                  RadioListTile<Provider>(
                      value: Provider.pollinations, title: Text(s.t('pollinations')), contentPadding: EdgeInsets.zero),
                ]),
              ),
            ]),
            AnimatedSize(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              child: store.provider != Provider.gemini
                  ? const SizedBox(width: double.infinity)
                  : section(s.t('geminiKey'), [
                      TextField(
                        controller: _key,
                        obscureText: !_show,
                        autocorrect: false,
                        enableSuggestions: false,
                        textDirection: TextDirection.ltr,
                        decoration: InputDecoration(
                          hintText: 'AIza...',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          suffixIcon: IconButton(
                            tooltip: s.t('showKey'),
                            icon: Icon(_show ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                            onPressed: () => setState(() => _show = !_show),
                          ),
                        ),
                        onSubmitted: (_) => _saveKey(store, s),
                      ),
                      const SizedBox(height: 8),
                      Text(s.t('keyHint'), style: TextStyle(color: context.muted, fontSize: 13)),
                      const SizedBox(height: 10),
                      Row(children: [
                        FilledButton(onPressed: () => _saveKey(store, s), child: Text(s.t('save'))),
                        const SizedBox(width: 8),
                        Flexible(
                          child: TextButton.icon(
                            icon: const Icon(Icons.open_in_new, size: 18),
                            label: Text(s.t('getKey'), overflow: TextOverflow.ellipsis),
                            onPressed: () => launchUrl(Uri.parse('https://aistudio.google.com/apikey'),
                                mode: LaunchMode.externalApplication),
                          ),
                        ),
                      ]),
                    ]),
            ),
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
