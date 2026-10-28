import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/shell.dart';
import '../../app/theme.dart';
import '../../services/chat_service.dart';
import '../../services/settings_service.dart';
import '../../services/subscription_service.dart';
import '../../widgets/common.dart';
import '../chat/chat_input.dart';
import '../chat/chat_screen.dart';
import '../paywall/paywall_screen.dart';
import '../settings/settings_screen.dart';
import '../studio/studio_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  static const _suggestions = [
    ('🎨', 'ارسم قطة رائد فضاء بأسلوب ثلاثي الأبعاد'),
    ('📱', 'ابنِ لي تطبيق قائمة مهام بألوان زاهية'),
    ('✍️', 'اكتب لي منشور إنستغرام لمطعم جديد'),
    ('💡', 'اقترح 5 أفكار تطبيقات مربحة في 2026'),
  ];

  void _openChat(BuildContext context, {String personaId = 'mind', String? text}) {
    final chat = context.read<ChatService>();
    final c = chat.start(personaId);
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => ChatScreen(conversation: c)));
    if (text != null) chat.send(c, text);
  }

  @override
  Widget build(BuildContext context) {
    final name = context.select<SettingsService, String>((s) => s.userName);
    final plan = context.select<SubscriptionService, String>((s) => s.plan.name);

    return Scaffold(
      drawer: const _HistoryDrawer(),
      appBar: AppBar(
        title: const GradientText('Mind Ai', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: ActionChip(
              avatar: const Icon(Icons.workspace_premium, size: 18, color: MindColors.orange),
              label: Text(plan, style: const TextStyle(fontWeight: FontWeight.w800)),
              shape: const StadiumBorder(),
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PaywallScreen())),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsScreen())),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              children: [
                const SizedBox(height: 8),
                const Center(child: _Orb()),
                const SizedBox(height: 14),
                Center(
                  child: Text(
                    name.isEmpty ? 'أهلاً بك 👋' : 'أهلاً $name 👋',
                    style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
                  ),
                ),
                const Center(
                  child: Text(
                    'بماذا أساعدك اليوم؟',
                    style: TextStyle(fontSize: 16, color: MindColors.muted, fontWeight: FontWeight.w600),
                  ),
                ),
                const SizedBox(height: 20),
                GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 1.25,
                  children: [
                    ToolTile(
                      title: 'إنشاء صور',
                      subtitle: 'حوّل كلامك لصورة',
                      emoji: '🎨',
                      gradient: MindColors.brand,
                      onTap: () => StudioScreen.open(context, StudioTool.image),
                    ),
                    ToolTile(
                      title: 'بناء تطبيق',
                      subtitle: 'كود كامل + APK',
                      emoji: '📱',
                      gradient: MindColors.cool,
                      onTap: () => Shell.goTo(context, 2),
                    ),
                    ToolTile(
                      title: 'ملصقات',
                      subtitle: 'ثابتة ومتحركة',
                      emoji: '🦄',
                      gradient: MindColors.sunset,
                      onTap: () => StudioScreen.open(context, StudioTool.sticker),
                    ),
                    ToolTile(
                      title: 'فيديو',
                      subtitle: 'من نص أو صورة',
                      emoji: '🎬',
                      gradient: MindColors.fresh,
                      onTap: () => StudioScreen.open(context, StudioTool.video),
                    ),
                    for (final t in const [
                      StudioTool.gift,
                      StudioTool.slides,
                      StudioTool.website,
                      StudioTool.game,
                      StudioTool.voice,
                    ])
                      ToolTile(
                        title: t.title,
                        subtitle: t.subtitle,
                        emoji: t.emoji,
                        gradient: t.gradient,
                        badge: 'جديد',
                        onTap: () => StudioScreen.open(context, t),
                      ),
                  ],
                ),
                const SizedBox(height: 22),
                const Text('مساعدون أذكياء', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                const SizedBox(height: 10),
                SizedBox(
                  height: 118,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: Persona.all.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 10),
                    itemBuilder: (context, i) {
                      final p = Persona.all[i];
                      return InkWell(
                        borderRadius: BorderRadius.circular(20),
                        onTap: () => _openChat(context, personaId: p.id),
                        child: Ink(
                          width: 112,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Theme.of(context).cardTheme.color,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Column(
                            children: [
                              Text(p.emoji, style: const TextStyle(fontSize: 30)),
                              const SizedBox(height: 4),
                              Text(p.name, style: const TextStyle(fontWeight: FontWeight.w800)),
                              Text(
                                p.tagline,
                                maxLines: 2,
                                textAlign: TextAlign.center,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 11, color: MindColors.muted),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 22),
                const Text('جرّب مثلاً', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                const SizedBox(height: 8),
                for (final (emoji, text) in _suggestions)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      tileColor: Theme.of(context).cardTheme.color,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      leading: Text(emoji, style: const TextStyle(fontSize: 22)),
                      title: Text(text, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                      trailing: const Icon(Icons.arrow_back_ios_new, size: 14),
                      onTap: () {
                        if (text.startsWith('ابنِ')) {
                          Shell.goTo(context, 2);
                        } else {
                          _openChat(context, text: text);
                        }
                      },
                    ),
                  ),
              ],
            ),
          ),
          ChatInput(
            onSend: (text, image) {
              final chat = context.read<ChatService>();
              final c = chat.start('mind');
              Navigator.of(context).push(MaterialPageRoute(builder: (_) => ChatScreen(conversation: c)));
              chat.send(c, text, image: image);
            },
          ),
        ],
      ),
    );
  }
}

/// The glowing gradient "mind" avatar at the top of the home screen.
class _Orb extends StatefulWidget {
  const _Orb();

  @override
  State<_Orb> createState() => _OrbState();
}

class _OrbState extends State<_Orb> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(seconds: 3))..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, _) => Container(
        width: 96,
        height: 96,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: SweepGradient(
            colors: const [MindColors.violet, MindColors.pink, MindColors.orange, MindColors.cyan, MindColors.violet],
            transform: GradientRotation(_c.value * 6.28),
          ),
          boxShadow: [
            BoxShadow(
              color: MindColors.pink.withValues(alpha: 0.25 + 0.2 * _c.value),
              blurRadius: 30 + 10 * _c.value,
              spreadRadius: 2,
            ),
          ],
        ),
        alignment: Alignment.center,
        child: const Text('🧠', style: TextStyle(fontSize: 44)),
      ),
    );
  }
}

class _HistoryDrawer extends StatelessWidget {
  const _HistoryDrawer();

  @override
  Widget build(BuildContext context) {
    final chat = context.watch<ChatService>();
    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Row(
                children: [GradientText('سجل المحادثات', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900))],
              ),
            ),
            Expanded(
              child: chat.conversations.isEmpty
                  ? const Center(
                      child: Text('لا توجد محادثات بعد', style: TextStyle(color: MindColors.muted)),
                    )
                  : ListView.builder(
                      itemCount: chat.conversations.length,
                      itemBuilder: (context, i) {
                        final c = chat.conversations[i];
                        final p = Persona.byId(c.personaId);
                        return ListTile(
                          leading: Text(p.emoji, style: const TextStyle(fontSize: 22)),
                          title: Text(c.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Text(p.name),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline, size: 20),
                            onPressed: () => chat.remove(c),
                          ),
                          onTap: () {
                            Navigator.pop(context);
                            Navigator.of(context).push(MaterialPageRoute(builder: (_) => ChatScreen(conversation: c)));
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
