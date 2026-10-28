import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/theme.dart';
import '../../services/settings_service.dart';
import '../paywall/paywall_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SettingsService>();
    final tb = s.textBackend;
    return Scaffold(
      appBar: AppBar(title: const Text('الإعدادات')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _Section('عام', [
            _Field(label: 'اسمك', value: s.userName, onSaved: s.setUserName),
            SwitchListTile(
              title: const Text('الوضع الليلي'),
              value: s.darkMode,
              onChanged: s.setDarkMode,
            ),
            ListTile(
              leading: const Icon(Icons.workspace_premium, color: MindColors.orange),
              title: const Text('الاشتراكات'),
              trailing: const Icon(Icons.arrow_back_ios_new, size: 14),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PaywallScreen())),
            ),
          ]),
          _Section('🧠 نموذج المحادثة والأكواد', [
            DropdownButtonFormField<TextBackend>(
              initialValue: tb,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'المزوّد'),
              items: [for (final b in TextBackend.values) DropdownMenuItem(value: b, child: Text(b.label))],
              onChanged: (b) => s.setTextBackend(b!),
            ),
            const SizedBox(height: 10),
            if (tb.needsKey)
              _Field(
                key: ValueKey('key_${tb.name}'),
                label: 'مفتاح API',
                value: s.textKey(tb),
                secret: true,
                onSaved: (v) => s.setTextKey(tb, v),
              ),
            _Field(
              key: ValueKey('model_${tb.name}'),
              label: 'اسم النموذج',
              value: s.textModel(tb),
              ltr: true,
              onSaved: (v) => s.setTextModel(tb, v),
            ),
            if (tb == TextBackend.custom)
              _Field(
                label: 'رابط chat/completions',
                value: s.textBaseUrl(tb),
                ltr: true,
                onSaved: (v) => s.setTextBaseUrl(tb, v),
              ),
            _Links(const [
              ('مفتاح Gemini مجاني', 'https://aistudio.google.com/apikey'),
              ('مفتاح Groq مجاني', 'https://console.groq.com/keys'),
              ('مفتاح OpenRouter', 'https://openrouter.ai/keys'),
            ]),
          ]),
          _Section('🎨 الصور والملصقات', [
            DropdownButtonFormField<ImageBackend>(
              initialValue: s.imageBackend,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'مزوّد الصور'),
              items: [for (final b in ImageBackend.values) DropdownMenuItem(value: b, child: Text(b.label))],
              onChanged: (b) => s.setImageBackend(b!),
            ),
            const SizedBox(height: 10),
            if (s.imageBackend == ImageBackend.pollinations)
              _Field(label: 'نموذج Pollinations (flux, turbo, kontext…)', value: s.imageModel, ltr: true, onSaved: s.setImageModel),
            if (s.imageBackend == ImageBackend.gemini && s.textKey(TextBackend.gemini).isEmpty)
              _Field(
                label: 'مفتاح Gemini',
                value: '',
                secret: true,
                onSaved: (v) => s.setTextKey(TextBackend.gemini, v),
              ),
            if (s.imageBackend == ImageBackend.custom)
              _Field(
                label: 'رابط مخصص ({prompt} {width} {height} {seed})',
                value: s.customImageUrl,
                ltr: true,
                onSaved: s.setCustomImageUrl,
              ),
            _Field(
              label: 'رمز Pollinations (اختياري، يرفع الحدود ويفعّل الفيديو)',
              value: s.pollinationsToken,
              secret: true,
              onSaved: s.setPollinationsToken,
            ),
            _Links(const [('احصل على رمز Pollinations', 'https://enter.pollinations.ai')]),
          ]),
          _Section('🎬 الفيديو', [
            DropdownButtonFormField<VideoBackend>(
              initialValue: s.videoBackend,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'مزوّد الفيديو'),
              items: [for (final b in VideoBackend.values) DropdownMenuItem(value: b, child: Text(b.label))],
              onChanged: (b) => s.setVideoBackend(b!),
            ),
            const SizedBox(height: 10),
            if (s.videoBackend == VideoBackend.replicate) ...[
              _Field(label: 'مفتاح Replicate', value: s.replicateKey, secret: true, onSaved: s.setReplicateKey),
              _Field(label: 'نموذج الفيديو', value: s.replicateVideoModel, ltr: true, onSaved: s.setReplicateVideoModel),
            ],
            if (s.videoBackend == VideoBackend.custom)
              _Field(label: 'رابط مخصص ({prompt} {seconds})', value: s.customVideoUrl, ltr: true, onSaved: s.setCustomVideoUrl),
          ]),
          _Section('☁️ البناء السحابي (بديل Android Studio)', [
            const Text(
              '1) أنشئ مستودعاً عاماً على GitHub.\n'
              '2) أنشئ Fine-grained token لهذا المستودع بصلاحيات: Contents, Actions, Workflows (قراءة وكتابة).\n'
              '3) الصق الرمز واسم المستودع هنا.',
              style: TextStyle(height: 1.6),
            ),
            const SizedBox(height: 10),
            _Field(label: 'المستودع (owner/repo)', value: s.githubRepo, ltr: true, onSaved: s.setGithubRepo),
            _Field(label: 'رمز GitHub', value: s.githubToken, secret: true, onSaved: s.setGithubToken),
            _Links(const [('إنشاء رمز GitHub', 'https://github.com/settings/personal-access-tokens/new')]),
          ]),
          const SizedBox(height: 20),
          const Center(child: Text('Mind Ai · v1.0.0', style: TextStyle(color: MindColors.muted))),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section(this.title, this.children);
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Card(
        margin: const EdgeInsets.only(bottom: 14),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
              const SizedBox(height: 10),
              ...children,
            ],
          ),
        ),
      );
}

/// A text field that saves when editing finishes.
class _Field extends StatefulWidget {
  const _Field({super.key, required this.label, required this.value, required this.onSaved, this.secret = false, this.ltr = false});
  final String label;
  final String value;
  final Future<void> Function(String) onSaved;
  final bool secret;
  final bool ltr;

  @override
  State<_Field> createState() => _FieldState();
}

class _FieldState extends State<_Field> {
  late final _c = TextEditingController(text: widget.value);
  bool _hidden = true;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Focus(
          onFocusChange: (f) {
            if (!f && _c.text != widget.value) widget.onSaved(_c.text);
          },
          child: TextField(
            controller: _c,
            obscureText: widget.secret && _hidden,
            textDirection: widget.ltr || widget.secret ? TextDirection.ltr : null,
            onSubmitted: widget.onSaved,
            decoration: InputDecoration(
              labelText: widget.label,
              suffixIcon: widget.secret
                  ? IconButton(
                      icon: Icon(_hidden ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                      onPressed: () => setState(() => _hidden = !_hidden),
                    )
                  : null,
            ),
          ),
        ),
      );
}

class _Links extends StatelessWidget {
  const _Links(this.links);
  final List<(String, String)> links;

  @override
  Widget build(BuildContext context) => Wrap(
        spacing: 8,
        children: [
          for (final (label, url) in links)
            ActionChip(
              avatar: const Icon(Icons.open_in_new, size: 16),
              label: Text(label),
              onPressed: () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
            ),
        ],
      );
}
