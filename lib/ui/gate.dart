import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/auth.dart';
import '../core/store.dart';
import '../core/strings.dart';
import 'home.dart';
import 'plans.dart';
import 'theme.dart';
import 'version_label.dart';

/// The first screen: sign-in when it is set up, then the chats. On the free
/// plan an ad blocker covers the app with a request to turn it off; it is
/// checked again whenever the app comes back to the front.
class StartGate extends StatefulWidget {
  const StartGate({super.key});

  @override
  State<StartGate> createState() => _StartGateState();
}

class _StartGateState extends State<StartGate> with WidgetsBindingObserver {
  bool _blocked = false;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _check();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _check();
  }

  Future<bool> _check() async {
    final store = context.read<AppStore>();
    if (store.premium) {
      if (_blocked) setState(() => _blocked = false);
      return false;
    }
    setState(() => _checking = true);
    final blocked = await store.adBlockCheck();
    if (mounted) {
      setState(() {
        _checking = false;
        _blocked = blocked && !store.premium;
      });
    }
    return blocked;
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    return ListenableBuilder(
      listenable: store.auth,
      builder: (context, _) {
        final Widget page = store.auth.needsSignIn ? const LoginScreen() : const HomeScreen();
        if (!_blocked || store.premium) return page;
        return _AdBlockScreen(checking: _checking, onRecheck: _check);
      },
    );
  }
}

class _AdBlockScreen extends StatelessWidget {
  const _AdBlockScreen({required this.checking, required this.onRecheck});
  final bool checking;
  final Future<bool> Function() onRecheck;

  @override
  Widget build(BuildContext context) {
    final s = S(context.watch<AppStore>().lang);
    final scheme = Theme.of(context).colorScheme;
    Widget step(int n, String text) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            CircleAvatar(
              radius: 12,
              backgroundColor: scheme.primary.withValues(alpha: 0.12),
              child: Text('$n', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: scheme.primary)),
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(text, style: const TextStyle(height: 1.5))),
          ]),
        );
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 48, 24, 24),
          children: [
            Center(
              child: Container(
                width: 76,
                height: 76,
                decoration: BoxDecoration(color: context.warn.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(24)),
                child: Icon(Icons.block_rounded, size: 40, color: context.warn),
              ),
            ),
            const SizedBox(height: 20),
            Text(s.t('adTitle'), textAlign: TextAlign.center, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            Text(s.t('adText'), textAlign: TextAlign.center, style: TextStyle(color: context.muted, height: 1.6)),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: context.surface2, borderRadius: BorderRadius.circular(16)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(s.t('adHow'), style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 12),
                step(1, s.t('adStep1')),
                step(2, s.t('adStep2')),
              ]),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              icon: checking
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.refresh_rounded),
              label: Text(checking ? s.t('adChecking') : s.t('adRecheck')),
              onPressed: checking
                  ? null
                  : () async {
                      final still = await onRecheck();
                      if (still && context.mounted) {
                        ScaffoldMessenger.of(context)
                          ..hideCurrentSnackBar()
                          ..showSnackBar(SnackBar(content: Text(s.t('adStill')), behavior: SnackBarBehavior.floating));
                      }
                    },
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              icon: const Icon(Icons.workspace_premium_rounded, color: Color(0xFFE0A100)),
              label: Text(s.t('subscribe')),
              onPressed: () => openPlans(context),
            ),
          ],
        ),
      ),
    );
  }
}

/// Google or phone number sign-in.
class LoginScreen extends StatefulWidget {
  /// Phone sign-in needs Firebase's paid (Blaze) plan; build with
  /// --dart-define=PHONE_LOGIN=true once billing is on.
  static const phoneLogin = bool.fromEnvironment('PHONE_LOGIN');

  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _phone = TextEditingController(text: '+');
  final _code = TextEditingController();
  bool _busy = false;
  bool _codeSent = false;

  @override
  void dispose() {
    _phone.dispose();
    _code.dispose();
    super.dispose();
  }

  Auth get _auth => context.read<AppStore>().auth;

  Future<void> _do(Future<String?> Function() f, {void Function()? onOk}) async {
    setState(() => _busy = true);
    final err = await f();
    if (!mounted) return;
    setState(() => _busy = false);
    if (err == null) {
      onOk?.call();
      return;
    }
    final s = S(context.read<AppStore>().lang);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(s.authError(err)), behavior: SnackBarBehavior.floating));
  }

  void _send() {
    final phone = _phone.text.replaceAll(RegExp(r'[\s\-()]'), '');
    if (!RegExp(r'^\+\d{8,15}$').hasMatch(phone)) {
      _do(() async => 'invalid-phone-number');
      return;
    }
    _do(() => _auth.sendCode(phone), onOk: () => setState(() => _codeSent = true));
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final s = S(store.lang);
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      bottomNavigationBar: VersionLabel(prefix: s.t('version')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
          children: [
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: SegmentedButton<String>(
                showSelectedIcon: false,
                style: const ButtonStyle(visualDensity: VisualDensity.compact),
                segments: const [
                  ButtonSegment(value: 'ar', label: Text('العربية')),
                  ButtonSegment(value: 'en', label: Text('English')),
                ],
                selected: {store.lang},
                onSelectionChanged: (v) => store.setLang(v.first),
              ),
            ),
            const SizedBox(height: 28),
            Center(
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(26),
                  boxShadow: [BoxShadow(color: scheme.primary.withValues(alpha: 0.28), blurRadius: 28, offset: const Offset(0, 10))],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(26),
                  child: Image.asset('assets/logo.png', width: 84, height: 84),
                ),
              ),
            ),
            const SizedBox(height: 22),
            Text(s.t('welcome'), textAlign: TextAlign.center, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text(s.t('welcomeText'), textAlign: TextAlign.center, style: TextStyle(color: context.muted, height: 1.6)),
            const SizedBox(height: 32),
            SizedBox(
              height: 52,
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  side: BorderSide(color: context.muted.withValues(alpha: 0.35)),
                ),
                onPressed: _busy ? null : () => _do(_auth.google),
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  const _GoogleMark(),
                  const SizedBox(width: 12),
                  Text(s.t('withGoogle'), style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600)),
                ]),
              ),
            ),
            if (LoginScreen.phoneLogin) ...[
              const SizedBox(height: 22),
              Row(children: [
                const Expanded(child: Divider()),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text(s.t('or'), style: TextStyle(color: context.muted)),
                ),
                const Expanded(child: Divider()),
              ]),
              const SizedBox(height: 22),
              if (!_codeSent) ...[
                TextField(
                  controller: _phone,
                  keyboardType: TextInputType.phone,
                  textDirection: TextDirection.ltr,
                  autofillHints: const [AutofillHints.telephoneNumber],
                  decoration: InputDecoration(
                    labelText: s.t('phone'),
                    hintText: s.t('phoneHint'),
                    helperText: s.t('phoneHelp'),
                    prefixIcon: const Icon(Icons.phone_iphone_rounded),
                  ),
                  onSubmitted: (_) => _send(),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  height: 50,
                  child: FilledButton(
                    onPressed: _busy ? null : _send,
                    child: _busy
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : Text(s.t('sendCode')),
                  ),
                ),
              ] else ...[
                Text(s.t('codeSent', {'phone': _phone.text}), textAlign: TextAlign.center, style: TextStyle(color: context.muted)),
                const SizedBox(height: 12),
                TextField(
                  controller: _code,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  maxLength: 6,
                  autofillHints: const [AutofillHints.oneTimeCode],
                  style: const TextStyle(fontSize: 22, letterSpacing: 8, fontWeight: FontWeight.w600),
                  decoration: InputDecoration(labelText: s.t('code'), counterText: ''),
                  onSubmitted: (_) => _do(() => _auth.verifyCode(_code.text)),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  height: 50,
                  child: FilledButton(
                    onPressed: _busy ? null : () => _do(() => _auth.verifyCode(_code.text)),
                    child: _busy
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : Text(s.t('verify')),
                  ),
                ),
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  TextButton(
                    onPressed: _busy ? null : () => setState(() => _codeSent = false),
                    child: Text(s.t('changeNumber')),
                  ),
                  TextButton(onPressed: _busy ? null : _send, child: Text(s.t('resend'))),
                ]),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

/// Google's four-colour "G", drawn so no image asset is needed.
class _GoogleMark extends StatelessWidget {
  const _GoogleMark();

  @override
  Widget build(BuildContext context) => SizedBox(width: 22, height: 22, child: CustomPaint(painter: _GPainter()));
}

class _GPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width * 0.2;
    final rect = Rect.fromLTWH(w / 2, w / 2, size.width - w, size.height - w);
    Paint p(int c) => Paint()
      ..color = Color(c)
      ..style = PaintingStyle.stroke
      ..strokeWidth = w;
    const d = 3.14159265 / 180;
    canvas.drawArc(rect, -40 * d, -95 * d, false, p(0xFFEA4335)); // red, top
    canvas.drawArc(rect, -135 * d, -90 * d, false, p(0xFFFBBC05)); // yellow, left
    canvas.drawArc(rect, 135 * d, -95 * d, false, p(0xFF34A853)); // green, bottom
    canvas.drawArc(rect, 40 * d, -40 * d, false, p(0xFF4285F4)); // blue, right
    final bar = Paint()..color = const Color(0xFF4285F4);
    canvas.drawRect(Rect.fromLTWH(size.width / 2, size.height / 2 - w / 2, size.width / 2 - w / 4, w), bar);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
