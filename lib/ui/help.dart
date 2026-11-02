import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/ai.dart';
import '../core/models.dart';
import '../core/plan.dart';
import '../core/store.dart';
import '../core/strings.dart';
import '../core/support.dart';
import 'theme.dart';
import 'version_label.dart';

/// Help: the support assistant, customer service, how to use the app, FAQ and about.
class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final s = S(store.lang);
    final scheme = Theme.of(context).colorScheme;
    final c = _HelpText(s.ar);

    Widget title(String t) => Padding(
          padding: const EdgeInsets.fromLTRB(4, 22, 4, 8),
          child: Text(t, style: TextStyle(fontWeight: FontWeight.w700, color: scheme.primary)),
        );

    Widget card(List<Widget> children) => Material(
          color: context.surface2,
          borderRadius: BorderRadius.circular(16),
          clipBehavior: Clip.antiAlias,
          child: Column(children: children),
        );

    Widget faq(String q, String a) => Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            title: Text(q, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5)),
            childrenPadding: const EdgeInsetsDirectional.fromSTEB(16, 0, 16, 14),
            expandedAlignment: AlignmentDirectional.centerStart,
            children: [Text(a, style: TextStyle(color: context.muted, height: 1.55))],
          ),
        );

    return Scaffold(
      appBar: AppBar(title: Text(s.t('help'))),
      bottomNavigationBar: VersionLabel(prefix: s.t('version')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
          children: [
            // Support assistant
            InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const HelpChatScreen())),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  gradient: LinearGradient(colors: [scheme.primary, scheme.primary.withValues(alpha: 0.75)]),
                ),
                child: Row(children: [
                  const CircleAvatar(
                    radius: 24,
                    backgroundColor: Colors.white24,
                    child: Icon(Icons.smart_toy_outlined, color: Colors.white, size: 26),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(s.t('helpBot'),
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16)),
                      const SizedBox(height: 3),
                      Text(s.t('helpBotText'), style: const TextStyle(color: Colors.white70, height: 1.4)),
                    ]),
                  ),
                  const Icon(Icons.chevron_right_rounded, color: Colors.white),
                ]),
              ),
            ),

            title(s.t('customerService')),
            card([
              if (Support.email.isNotEmpty)
                ListTile(
                  leading: Icon(Icons.mail_outline_rounded, color: scheme.primary),
                  title: Text(s.t('emailUs')),
                  subtitle: Text(Support.email, textDirection: TextDirection.ltr),
                  trailing: const Icon(Icons.open_in_new_rounded, size: 18),
                  onTap: () => launchUrl(Uri(
                    scheme: 'mailto',
                    path: Support.email,
                    query: 'subject=${Uri.encodeComponent(s.t('supportSubject'))}',
                  )),
                ),
              if (Support.whatsapp.isNotEmpty)
                ListTile(
                  leading: Icon(Icons.chat_outlined, color: scheme.primary),
                  title: Text(s.t('whatsappUs')),
                  subtitle: Text('+${Support.whatsapp}', textDirection: TextDirection.ltr),
                  trailing: const Icon(Icons.open_in_new_rounded, size: 18),
                  onTap: () => launchUrl(Uri.parse('https://wa.me/${Support.whatsapp}'),
                      mode: LaunchMode.externalApplication),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Text(s.t('supportHours'), style: TextStyle(color: context.muted, fontSize: 12.5)),
              ),
            ]),

            title(s.t('howToUse')),
            card([
              for (final (i, step) in c.steps.indexed)
                ListTile(
                  leading: CircleAvatar(
                    radius: 14,
                    backgroundColor: scheme.primary.withValues(alpha: 0.15),
                    child: Text('${i + 1}', style: TextStyle(color: scheme.primary, fontWeight: FontWeight.w700)),
                  ),
                  title: Text(step.$1, style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(step.$2, style: const TextStyle(height: 1.45)),
                ),
            ]),

            title(s.t('faq')),
            card([for (final f in c.faq) faq(f.$1, f.$2)]),

            title(s.t('aboutApp')),
            card([
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.asset('assets/logo.png', width: 44, height: 44),
                    ),
                    const SizedBox(width: 12),
                    Text(s.t('appName'), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
                  ]),
                  const SizedBox(height: 12),
                  Text(c.about, style: const TextStyle(height: 1.6)),
                  const SizedBox(height: 10),
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Icon(Icons.lock_outline, size: 18, color: context.muted),
                    const SizedBox(width: 8),
                    Expanded(child: Text(s.t('privacy'), style: TextStyle(color: context.muted, height: 1.5))),
                  ]),
                ]),
              ),
            ]),
          ],
        ),
      ),
    );
  }
}

/// Help page content in both languages.
class _HelpText {
  _HelpText(this.ar);
  final bool ar;

  String get about => ar
      ? 'قارئ الملفات يجيب عن أسئلتك من ملفاتك وصورك فقط: فواتير، عقود، تقارير، جداول، عروض تقديمية ولقطات شاشة. كل إجابة تذكر مصدرها (الملف والصفحة أو الشريحة أو الخلية)، وإن لم تكن المعلومة في ملفاتك يخبرك بذلك بدلاً من التخمين.'
      : 'File Chat answers your questions from your own files and images only: invoices, contracts, reports, spreadsheets, slides and screenshots. Every answer names its source (file and page, slide or cell), and if the information is not in your files it tells you instead of guessing.';

  List<(String, String)> get steps => ar
      ? const [
          ('ابدأ محادثة', 'اضغط أيقونة القلم في الأعلى أو «محادثة جديدة» من القائمة الجانبية.'),
          ('أرفق ملفاتك', 'اضغط زر الإرفاق: «ملف» لملفات PDF وWord وExcel وPowerPoint، أو «صورة» من المعرض. يمكنك إرفاق عدة ملفات.'),
          ('اسأل', 'اكتب سؤالك وأرسله. ستصلك إجابة مختصرة من الملفات مع ذكر المصدر.'),
          ('ارجع لمحادثاتك', 'كل محادثاتك في القائمة الجانبية. ابحث فيها، أو اضغط مطولاً لتحديد عدة محادثات وحذفها.'),
        ]
      : const [
          ('Start a chat', 'Tap the pencil icon at the top or "New chat" in the side menu.'),
          ('Attach your files', 'Tap the attach button: "File" for PDF, Word, Excel and PowerPoint, or "Image" from your gallery. You can attach several.'),
          ('Ask', 'Type your question and send. You get a short answer from your files with its source.'),
          ('Find your chats', 'All chats are in the side menu. Search them, or long-press to select several and delete them.'),
        ];

  List<(String, String)> get faq => ar
      ? [
          ('ما أنواع الملفات المدعومة؟', 'PDF (حتى الممسوحة ضوئياً)، Word، Excel، PowerPoint، الملفات النصية، والصور.'),
          ('لماذا يطلب مني إيقاف مانع الإعلانات؟',
              'الخطة المجانية تعمل بشرط إيقاف مانع الإعلانات. لإيقافه: الإعدادات ← الشبكة والإنترنت ← DNS خاص ← تلقائي أو إيقاف، وأوقف تطبيقات مثل AdGuard أو Blokada. المشتركون في الخطة المميزة لا يحتاجون لذلك.'),
          ('كم سؤالاً أستطيع أن أسأل؟',
              'الخطة المجانية: ${Plan.freeDailyQuestions} سؤالاً في اليوم وتتجدد عند منتصف الليل. الخطة المميزة (4.99\$ شهرياً): أسئلة بلا حد وملفات حتى ${Plan.premiumMaxFileBytes ~/ (1024 * 1024)} ميجابايت.'),
          ('كيف ألغي الاشتراك؟', 'من Google Play ← الدفعات والاشتراكات ← الاشتراكات، أو من الإعدادات ← الاشتراك ← إدارة.'),
          ('هل ملفاتي آمنة؟', 'ملفاتك ومحادثاتك محفوظة على هاتفك فقط، وتُرسل بشكل آمن لخدمة الذكاء الاصطناعي عند السؤال فقط.'),
          ('لماذا يقول إنه لم يجد المعلومة؟', 'لأن التطبيق يجيب من ملفاتك فقط. تأكد أن المعلومة موجودة في الملف المرفق، أو أرفق الملف الصحيح.'),
          ('كيف أحدّث التطبيق؟', 'يصلك إشعار عند صدور تحديث، أو من الإعدادات ← التحديثات ← البحث عن تحديثات، ثم «تحديث الآن».'),
        ]
      : [
          ('Which files are supported?', 'PDF (including scanned), Word, Excel, PowerPoint, text files and images.'),
          ('Why must I turn off my ad blocker?',
              'The free plan works only with ad blockers off. Go to Settings → Network & internet → Private DNS → Automatic or Off, and pause apps like AdGuard or Blokada. Premium subscribers don\'t need to.'),
          ('How many questions can I ask?',
              'Free: ${Plan.freeDailyQuestions} questions a day, reset at midnight. Premium (\$4.99/month): unlimited questions and files up to ${Plan.premiumMaxFileBytes ~/ (1024 * 1024)} MB.'),
          ('How do I cancel my subscription?', 'In Google Play → Payments & subscriptions → Subscriptions, or Settings → Subscription → Manage.'),
          ('Are my files safe?', 'Your files and chats stay on your phone, and are sent securely to the AI service only when you ask.'),
          ('Why does it say it could not find the information?', 'The app answers only from your files. Check the information is in the attached file, or attach the right one.'),
          ('How do I update the app?', 'You get a notification when an update is out, or go to Settings → Updates → Check for updates, then "Update now".'),
        ];
}

/// Chat with the support assistant. Not saved and not counted against the daily questions.
class HelpChatScreen extends StatefulWidget {
  const HelpChatScreen({super.key, this.client});
  final AiClient? client;

  @override
  State<HelpChatScreen> createState() => _HelpChatScreenState();
}

class _HelpChatScreenState extends State<HelpChatScreen> {
  final _conv = Conversation(id: 'help', title: 'help');
  final _input = TextEditingController();
  final _scroll = ScrollController();
  late final AiClient _client = widget.client ?? AiClient(system: helpBotPrompt);
  StreamSubscription<AiEvent>? _sub;
  bool get _busy => _sub != null;

  @override
  void dispose() {
    _sub?.cancel();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _send(String text, S s) {
    text = text.trim();
    if (text.isEmpty || _busy) return;
    _input.clear();
    final reply = Message(id: 'a${_conv.messages.length}', role: Role.assistant, text: '', status: MsgStatus.streaming);
    setState(() {
      _conv.messages.add(Message(id: 'u${_conv.messages.length}', role: Role.user, text: text));
    });
    final stream = _client.reply(_conv);
    setState(() => _conv.messages.add(reply));
    _toBottom();
    _sub = stream.listen(
      (e) {
        if (e is AiText) reply.text += e.text;
        if (e is AiReset) reply.text = '';
        setState(() {});
        _toBottom();
      },
      onError: (Object e) => setState(() {
        reply
          ..status = MsgStatus.error
          ..text = s.t('helpBotError');
        _sub = null;
      }),
      onDone: () => setState(() {
        if (reply.status == MsgStatus.streaming) reply.status = MsgStatus.complete;
        _sub = null;
      }),
    );
  }

  void _toBottom() => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) {
          _scroll.animateTo(_scroll.position.maxScrollExtent,
              duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
        }
      });

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final s = S(store.lang);
    final scheme = Theme.of(context).colorScheme;
    final msgs = _conv.messages;
    final suggestions = [s.t('hq1'), s.t('hq2'), s.t('hq3'), s.t('hq4')];

    return Scaffold(
      appBar: AppBar(title: Text(s.t('helpBot'))),
      body: SafeArea(
        child: Column(children: [
          Expanded(
            child: ListView(
              controller: _scroll,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              children: [
                _Bubble(text: s.t('helpBotHello'), mine: false),
                if (msgs.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Wrap(spacing: 8, runSpacing: 8, children: [
                      for (final q in suggestions)
                        ActionChip(label: Text(q), onPressed: () => _send(q, s)),
                    ]),
                  ),
                for (final m in msgs)
                  m.role == Role.assistant && m.text.isEmpty
                      ? const Padding(
                          padding: EdgeInsets.symmetric(vertical: 10),
                          child: Align(
                            alignment: AlignmentDirectional.centerStart,
                            child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)),
                          ),
                        )
                      : _Bubble(text: m.text, mine: m.role == Role.user, error: m.status == MsgStatus.error),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
            child: Row(children: [
              Expanded(
                child: TextField(
                  controller: _input,
                  minLines: 1,
                  maxLines: 4,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (v) => _send(v, s),
                  decoration: InputDecoration(hintText: s.t('helpBotHint')),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                tooltip: s.t('send'),
                onPressed: _busy ? null : () => _send(_input.text, s),
                icon: const Icon(Icons.arrow_upward_rounded),
                style: IconButton.styleFrom(backgroundColor: scheme.primary),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.text, required this.mine, this.error = false});
  final String text;
  final bool mine;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Align(
      alignment: mine ? AlignmentDirectional.centerEnd : AlignmentDirectional.centerStart,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 5),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.82),
        decoration: BoxDecoration(
          color: mine ? scheme.primary.withValues(alpha: 0.16) : context.surface2,
          borderRadius: BorderRadius.circular(16),
        ),
        child: mine
            ? Text(text, style: const TextStyle(height: 1.45))
            : MarkdownBody(
                data: text,
                styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
                  p: TextStyle(height: 1.5, color: error ? context.danger : null),
                ),
              ),
      ),
    );
  }
}
