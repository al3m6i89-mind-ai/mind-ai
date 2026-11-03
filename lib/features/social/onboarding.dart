import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/theme.dart';
import '../../services/settings_service.dart';
import '../../services/social/social_id.dart';
import '../../services/social/social_service.dart';
import '../../widgets/common.dart';
import 'widgets.dart';

/// Creates the one account (and its unified ID) used in Reels, Photos and Posts.
class SocialOnboarding extends StatefulWidget {
  const SocialOnboarding({super.key, this.addAnother = false, this.onDone});

  /// Adding a second account on this phone (pushed as a page).
  final bool addAnother;

  /// Called by «ابدأ» after the account is made (when embedded).
  final VoidCallback? onDone;

  @override
  State<SocialOnboarding> createState() => _SocialOnboardingState();
}

class _SocialOnboardingState extends State<SocialOnboarding> {
  late final TextEditingController _name;
  late final TextEditingController _handle;
  String? _handleError;
  bool _busy = false;
  SocialUser? _created;

  @override
  void initState() {
    super.initState();
    final settings = context.read<SettingsService>();
    _name = TextEditingController(text: widget.addAnother ? '' : settings.userName);
    var h = widget.addAnother ? '' : Handle.suggest(settings.accountEmail.isEmpty ? settings.userName : settings.accountEmail);
    final social = context.read<SocialService>();
    if (h.isNotEmpty && !social.handleFree(h)) h = '${h.length > 16 ? h.substring(0, 16) : h}_${DateTime.now().millisecond % 1000}';
    _handle = TextEditingController(text: h);
    if (h.isNotEmpty) _check(h);
  }

  @override
  void dispose() {
    _name.dispose();
    _handle.dispose();
    super.dispose();
  }

  void _check(String v) {
    final social = context.read<SocialService>();
    final p = Handle.problem(v);
    _handleError = p ?? (social.handleFree(v) ? null : 'المعرّف @${v.toLowerCase()} مستخدم');
    if (mounted) setState(() {});
  }

  Future<void> _create() async {
    setState(() => _busy = true);
    try {
      final u = await context.read<SocialService>().createAccount(name: _name.text, handle: _handle.text);
      if (mounted) setState(() => _created = u);
    } catch (e) {
      if (mounted) toast(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final body = _created != null ? _done(_created!) : _form();
    return widget.addAnother ? Scaffold(appBar: AppBar(title: const Text('حساب جديد')), body: body) : body;
  }

  Widget _form() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
      children: [
        const Center(child: Text('🎬 📸 💬', style: TextStyle(fontSize: 40))),
        const SizedBox(height: 12),
        const Center(
          child: GradientText('مجتمع Mind Ai', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900)),
        ),
        const SizedBox(height: 8),
        const Text(
          'حساب واحد بـ ID واحد لثلاثة أقسام:\nريلز قصيرة، صور وقصص، ومنشورات وتغريدات.\nمن يتابعك يتابعك في الثلاثة.',
          textAlign: TextAlign.center,
          style: TextStyle(color: MindColors.muted, height: 1.6),
        ),
        const SizedBox(height: 24),
        TextField(
          controller: _name,
          maxLength: 50,
          decoration: const InputDecoration(labelText: 'الاسم الظاهر', prefixIcon: Icon(Icons.person_outline)),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _handle,
          maxLength: 20,
          textDirection: TextDirection.ltr,
          onChanged: _check,
          decoration: InputDecoration(
            labelText: 'المعرّف (اسم المستخدم)',
            prefixText: '@',
            errorText: _handleError,
            helperText: _handleError == null && _handle.text.isNotEmpty ? '✓ متاح' : null,
            helperStyle: const TextStyle(color: Colors.green),
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: MindColors.violet.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Row(
            children: [
              Icon(Icons.badge_outlined, color: MindColors.violet),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'ستحصل على ID ثابت بالشكل MA-XXXX-XXXX-X. يمكنك تغيير اسمك ومعرّفك لاحقاً، أما الـ ID فلا يتغير أبداً.',
                  style: TextStyle(height: 1.5, fontSize: 13),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 22),
        GradientButton(
          label: 'أنشئ حسابي',
          icon: Icons.rocket_launch_rounded,
          loading: _busy,
          onPressed: _handleError != null || _handle.text.isEmpty ? null : _create,
        ),
      ],
    );
  }

  Widget _done(SocialUser u) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const SizedBox(height: 20),
        Center(child: SocialAvatar(u, size: 96)),
        const SizedBox(height: 12),
        Center(child: Text(u.name, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900))),
        Center(child: Text('@${u.handle}', textDirection: TextDirection.ltr, style: const TextStyle(color: MindColors.muted))),
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(gradient: MindColors.brand, borderRadius: BorderRadius.circular(22)),
          child: Column(
            children: [
              const Text('الـ ID الخاص بك', style: TextStyle(color: Colors.white70)),
              const SizedBox(height: 6),
              Text(
                u.id,
                textDirection: TextDirection.ltr,
                style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w900, letterSpacing: 1.5, fontFamily: 'monospace'),
              ),
              const SizedBox(height: 10),
              const Text('🎬 ريلز  ·  📸 صور  ·  💬 منشورات', style: TextStyle(color: Colors.white)),
            ],
          ),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(onPressed: () => copyId(context, u.id), icon: const Icon(Icons.copy), label: const Text('نسخ الـ ID')),
        const SizedBox(height: 12),
        GradientButton(
          label: 'ابدأ',
          onPressed: () {
            if (widget.addAnother) {
              Navigator.pop(context);
            } else {
              widget.onDone?.call();
            }
          },
        ),
      ],
    );
  }
}
