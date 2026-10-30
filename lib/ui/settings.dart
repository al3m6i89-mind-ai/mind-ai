import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

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
  late final TextEditingController _mistral;
  bool _show = false;

  @override
  void initState() {
    super.initState();
    _key = TextEditingController(text: context.read<AppStore>().geminiKey);
    _mistral = TextEditingController(text: context.read<AppStore>().mistralKey);
  }

  @override
  void dispose() {
    _key.dispose();
    _mistral.dispose();
    super.dispose();
  }

  Future<void> _saveKey(AppStore store, S s) async {
    await store.setGeminiKey(_key.text);
    await store.setMistralKey(_mistral.text);
    if (!mounted) return;
    FocusScope.of(context).unfocus();
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(s.t('keySaved')), behavior: SnackBarBehavior.floating));
  }

  Widget _keyField(TextEditingController c, String hint, AppStore store, S s) => TextField(
        controller: c,
        obscureText: !_show,
        autocorrect: false,
        enableSuggestions: false,
        textDirection: TextDirection.ltr,
        decoration: InputDecoration(
          hintText: hint,
          suffixIcon: IconButton(
            tooltip: s.t('showKey'),
            icon: Icon(_show ? Icons.visibility_off_outlined : Icons.visibility_outlined),
            onPressed: () => setState(() => _show = !_show),
          ),
        ),
        onSubmitted: (_) => _saveKey(store, s),
      );

  Widget _link(String label, String url) => Align(
        alignment: AlignmentDirectional.centerStart,
        child: TextButton.icon(
          icon: const Icon(Icons.open_in_new, size: 18),
          label: Text(label),
          onPressed: () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
        ),
      );

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
            section(s.t('geminiKey'), [
              _keyField(_key, 'AIza...', store, s),
              const SizedBox(height: 8),
              Text(s.t('keyHint'), style: TextStyle(color: context.muted, fontSize: 13)),
              _link(s.t('getKey'), 'https://aistudio.google.com/apikey'),
            ]),
            section(s.t('mistralKey'), [
              _keyField(_mistral, '', store, s),
              const SizedBox(height: 8),
              Text(s.t('mistralHint'), style: TextStyle(color: context.muted, fontSize: 13)),
              _link(s.t('getMistralKey'), 'https://console.mistral.ai/api-keys'),
            ]),
            Padding(
              padding: const EdgeInsets.only(bottom: 22),
              child: FilledButton(onPressed: () => _saveKey(store, s), child: Text(s.t('save'))),
            ),
            section(s.t('chainTitle'), [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: context.surface2, borderRadius: BorderRadius.circular(14)),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(Icons.alt_route_rounded, color: primary, size: 20),
                  const SizedBox(width: 10),
                  Expanded(child: Text(s.t('chainText'), style: const TextStyle(height: 1.55, fontSize: 13.5))),
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
