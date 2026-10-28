import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/theme.dart';
import '../../services/settings_service.dart';
import '../auth/sign_in_screen.dart';
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
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const CircleAvatar(child: Icon(Icons.person)),
              title: Text(s.userName.isEmpty ? 'حسابي' : s.userName),
              subtitle: Text(s.accountEmail),
              trailing: TextButton(
                onPressed: () async {
                  await s.signOut();
                  if (context.mounted) {
                    Navigator.of(context)
                        .pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const SignInScreen()), (_) => false);
                  }
                },
                child: const Text('تسجيل خروج'),
              ),
            ),
            _Field(label: 'اسمك', value: s.userName, onSaved: s.setUserName),
            SwitchListTile(title: const Text('الوضع الليلي'), value: s.darkMode, onChanged: s.setDarkMode),
            ListTile(
              leading: const Icon(Icons.workspace_premium, color: MindColors.orange),
              title: const Text('الاشتراكات'),
              trailing: const Icon(Icons.arrow_back_ios_new, size: 14),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PaywallScreen())),
            ),
          ]),
          _Section('🆓 مفاتيح مجانية (ننصح فيها)', [
            const Text(
              'كلها مجانية وبدون بطاقة. اضغط 🔗 جنب الخانة، سجّل دخول، انسخ المفتاح والصقه هنا. '
              'التطبيق يستخدم أقوى مفتاح عندك تلقائياً.',
              style: TextStyle(height: 1.5, color: MindColors.muted),
            ),
            const SizedBox(height: 10),
            _Field(
              label: 'Gemini: محادثة، رؤية، تعديل صور، صوت',
              value: s.textKey(TextBackend.gemini),
              secret: true,
              link: 'https://aistudio.google.com/apikey',
              onSaved: (v) => s.setTextKey(TextBackend.gemini, v),
            ),
            _Field(
              label: 'Hugging Face: صور FLUX وفيديو',
              value: s.hfToken,
              secret: true,
              link: 'https://huggingface.co/settings/tokens',
              onSaved: s.setHfToken,
            ),
            _Field(
              label: 'Cloudflare: رقم الحساب (Account ID)',
              value: s.cfAccountId,
              ltr: true,
              link: 'https://dash.cloudflare.com/?to=/:account/ai/workers-ai',
              onSaved: s.setCfAccountId,
            ),
            _Field(
              label: 'Cloudflare: رمز Workers AI',
              value: s.cfToken,
              secret: true,
              link: 'https://dash.cloudflare.com/profile/api-tokens',
              onSaved: s.setCfToken,
            ),
            _Field(
              label: 'Groq: محادثة سريعة جداً',
              value: s.textKey(TextBackend.groq),
              secret: true,
              link: 'https://console.groq.com/keys',
              onSaved: (v) => s.setTextKey(TextBackend.groq, v),
            ),
            _Field(
              label: 'OpenRouter: موديلات مجانية متعددة',
              value: s.textKey(TextBackend.openrouter),
              secret: true,
              link: 'https://openrouter.ai/keys',
              onSaved: (v) => s.setTextKey(TextBackend.openrouter, v),
            ),
          ]),
          _Section('💎 مفاتيح مدفوعة (الأقوى)', [
            const Text(
              'تدفع حسب استخدامك من حسابك عند كل شركة. Claude هو الأقوى في بناء التطبيقات.',
              style: TextStyle(height: 1.5, color: MindColors.muted),
            ),
            const SizedBox(height: 10),
            _Field(
              label: 'Claude (Anthropic)',
              value: s.textKey(TextBackend.anthropic),
              secret: true,
              link: 'https://platform.claude.com/settings/keys',
              onSaved: (v) => s.setTextKey(TextBackend.anthropic, v),
            ),
            _Field(
              label: 'ChatGPT (OpenAI)',
              value: s.textKey(TextBackend.openai),
              secret: true,
              link: 'https://platform.openai.com/api-keys',
              onSaved: (v) => s.setTextKey(TextBackend.openai, v),
            ),
            _Field(
              label: 'BytePlus ModelArk: Seedream للصور وSeedance للفيديو',
              value: s.arkKey,
              secret: true,
              link: 'https://console.byteplus.com/ark/region:ark+ap-southeast-1/apiKey',
              onSaved: s.setArkKey,
            ),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text('أسماء الموديلات (متقدم)', style: TextStyle(fontWeight: FontWeight.w700)),
              children: [
                _Field(
                  label: 'موديل Seedream (Model ID أو ep-…)',
                  value: s.seedreamModel,
                  ltr: true,
                  onSaved: s.setSeedreamModel,
                ),
                _Field(
                  label: 'موديل Seedance (Model ID أو ep-…)',
                  value: s.seedanceModel,
                  ltr: true,
                  onSaved: s.setSeedanceModel,
                ),
                _Field(label: 'موديل صور Hugging Face', value: s.hfImageModel, ltr: true, onSaved: s.setHfImageModel),
                _Field(label: 'موديل فيديو Hugging Face', value: s.hfVideoModel, ltr: true, onSaved: s.setHfVideoModel),
              ],
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
                link: tb.keyUrl,
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
              _Field(
                label: 'نموذج Pollinations (flux, turbo, kontext…)',
                value: s.imageModel,
                ltr: true,
                onSaved: s.setImageModel,
              ),
            if (s.imageBackend == ImageBackend.gemini && s.textKey(TextBackend.gemini).isEmpty)
              _Field(
                label: 'مفتاح Gemini',
                value: '',
                secret: true,
                link: 'https://aistudio.google.com/apikey',
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
              link: 'https://enter.pollinations.ai',
              onSaved: s.setPollinationsToken,
            ),
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
              _Field(
                label: 'مفتاح Replicate',
                value: s.replicateKey,
                secret: true,
                link: 'https://replicate.com/account/api-tokens',
                onSaved: s.setReplicateKey,
              ),
              _Field(
                label: 'نموذج الفيديو',
                value: s.replicateVideoModel,
                ltr: true,
                onSaved: s.setReplicateVideoModel,
              ),
            ],
            if (s.videoBackend == VideoBackend.custom)
              _Field(
                label: 'رابط مخصص ({prompt} {seconds})',
                value: s.customVideoUrl,
                ltr: true,
                onSaved: s.setCustomVideoUrl,
              ),
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
            _Field(
              label: 'رمز GitHub',
              value: s.githubToken,
              secret: true,
              link: 'https://github.com/settings/personal-access-tokens/new',
              onSaved: s.setGithubToken,
            ),
          ]),
          const SizedBox(height: 20),
          const Center(
            child: Text('Mind Ai · v1.0.0', style: TextStyle(color: MindColors.muted)),
          ),
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
  const _Field({
    super.key,
    required this.label,
    required this.value,
    required this.onSaved,
    this.secret = false,
    this.ltr = false,
    this.link,
  });
  final String label;
  final String value;
  final Future<void> Function(String) onSaved;
  final bool secret;
  final bool ltr;

  /// Page where the user gets this key; shown as a 🔗 button.
  final String? link;

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
  Widget build(BuildContext context) {
    final link = widget.link;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Focus(
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
          if (link != null)
            InkWell(
              onTap: () => launchUrl(Uri.parse(link), mode: LaunchMode.externalApplication),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(6, 4, 6, 0),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.link_rounded, size: 14, color: MindColors.violet),
                    const SizedBox(width: 4),
                    Text(
                      'المفتاح من: ${_short(link)}',
                      style: const TextStyle(fontSize: 12, color: MindColors.violet, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// "https://aistudio.google.com/apikey" -> "aistudio.google.com/apikey".
  static String _short(String url) {
    final u = Uri.parse(url);
    final path = u.path.length > 1 && u.path.length < 22 ? u.path : '';
    return '${u.host.replaceFirst('www.', '')}$path';
  }
}
