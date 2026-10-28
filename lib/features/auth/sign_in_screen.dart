import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/shell.dart';
import '../../app/theme.dart';
import '../../services/settings_service.dart';
import '../../services/subscription_service.dart';
import '../../widgets/common.dart';

/// First screen for a new user: a short sign-in, then a welcome gift of points
/// to try every tool.
class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  String? _error;

  Future<void> _go() async {
    final name = _name.text.trim();
    final email = _email.text.trim();
    if (name.isEmpty) return setState(() => _error = 'اكتب اسمك');
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      return setState(() => _error = 'اكتب بريد إلكتروني صحيح');
    }
    final settings = context.read<SettingsService>();
    final subs = context.read<SubscriptionService>();
    await settings.signIn(name, email);
    final gift = await subs.grantWelcome();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const Shell()));
    if (gift) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('🎁 هديتك ${SubscriptionService.welcomePoints} نقطة! جرّب كل الأدوات.')),
      );
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 40, 24, 24),
          children: [
            Center(
              child: Container(
                width: 96,
                height: 96,
                decoration: const BoxDecoration(shape: BoxShape.circle, gradient: MindColors.brand),
                alignment: Alignment.center,
                child: const Text('🧠', style: TextStyle(fontSize: 52)),
              ),
            ),
            const SizedBox(height: 18),
            const Center(
              child: GradientText('أهلاً بك في Mind Ai', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900)),
            ),
            const SizedBox(height: 8),
            const Text(
              'سجّل دخولك وخذ ${SubscriptionService.welcomePoints} نقطة هدية تجرّب فيها الصور والفيديو والملصقات وبناء التطبيقات.',
              textAlign: TextAlign.center,
              style: TextStyle(color: MindColors.muted, height: 1.6),
            ),
            const SizedBox(height: 28),
            TextField(
              controller: _name,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(labelText: 'اسمك', prefixIcon: Icon(Icons.person_outline)),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              textDirection: TextDirection.ltr,
              onSubmitted: (_) => _go(),
              decoration: const InputDecoration(labelText: 'بريدك الإلكتروني', prefixIcon: Icon(Icons.mail_outline)),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: const TextStyle(color: Colors.redAccent)),
            ],
            const SizedBox(height: 22),
            GradientButton(label: 'ابدأ وخذ هديتك 🎁', onPressed: _go),
            const SizedBox(height: 16),
            const Text(
              'بعد ما تخلص نقاط الهدية تقدر تشتري نقاط أو تشترك شهرياً.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: MindColors.muted),
            ),
          ],
        ),
      ),
    );
  }
}
