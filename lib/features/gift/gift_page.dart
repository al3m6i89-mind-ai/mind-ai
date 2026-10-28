import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../../app/theme.dart';
import '../../providers/image_gen.dart';
import '../../providers/tools.dart';
import '../../services/chat_service.dart';
import '../../services/gift_maker.dart';
import '../../services/library_service.dart';
import '../../services/media_tools.dart';
import '../../services/settings_service.dart';
import '../../services/subscription_service.dart';
import '../../widgets/common.dart';
import '../../widgets/tool_picker.dart';

/// Live-stream style animated gifts: AI artwork, cut out, animated with an
/// effect, exported as a transparent GIF and a Lottie JSON.
class GiftPage extends StatefulWidget {
  const GiftPage({super.key});

  @override
  State<GiftPage> createState() => _GiftPageState();
}

class _GiftPageState extends State<GiftPage> {
  final _prompt = TextEditingController();
  late ImageTool _ai = ImageTool.byId(context.read<SettingsService>().imageToolId);
  GiftEffect _effect = GiftEffect.spin3d;
  bool _busy = false;
  String _status = '';
  Uint8List? _art;
  Uint8List? _gif;
  String? _gifPath;

  static const _ideas = ['وردة حمراء', 'تاج ذهبي', 'سيارة رياضية', 'قلب كريستال', 'صندوق هدية', 'أسد ذهبي'];

  int get _points => _ai.points + 2;

  Future<void> _make() async {
    final text = _prompt.text.trim();
    if (text.isEmpty) return;
    final subs = context.read<SubscriptionService>();
    final images = context.read<ImageGen>();
    final chat = context.read<ChatService>();
    final library = context.read<LibraryService>();
    FocusScope.of(context).unfocus();
    try {
      subs.ensure(Usage.sticker, points: _points);
      setState(() {
        _busy = true;
        _status = 'أفهم فكرتك…';
      });
      final english = await chat.englishPrompt(text);
      setState(() => _status = 'أرسم الهدية… 🎨');
      final out = await images.generate(
        'a single $english as a luxury virtual gift icon for a live streaming app, glossy 3d render, '
        'shiny metallic and gem details, vibrant colors, soft studio lighting, centered, full object, '
        'isolated on a plain pure white background, no text, no shadow, no scenery',
        backend: _ai.backend,
        model: _ai.model,
      );
      setState(() => _status = 'أقص الخلفية… ✂️');
      _art = await MediaTools.makeSticker(out.bytes, outline: false);
      await _animate(library);
      await subs.consume(Usage.sticker, points: _points);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _animate(LibraryService library) async {
    setState(() => _status = 'أحرّك الهدية… ✨');
    final gif = await GiftMaker.gif(_art!, _effect);
    final saved = await library.save(gif, CreationKind.animatedSticker, 'هدية: ${_prompt.text}', ext: 'gif');
    setState(() {
      _gif = gif;
      _gifPath = saved.path;
    });
  }

  /// Changing the effect re-animates the same artwork for free.
  Future<void> _setEffect(GiftEffect e) async {
    setState(() => _effect = e);
    if (_art == null || _busy) return;
    setState(() => _busy = true);
    try {
      await _animate(context.read<LibraryService>());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _shareLottie() async {
    final json = await GiftMaker.lottie(_art!, _effect);
    final dir = await getTemporaryDirectory();
    final f = File('${dir.path}/mindai_gift_${DateTime.now().millisecondsSinceEpoch}.json');
    await f.writeAsString(json);
    await LibraryService.share(f.path, text: 'هدية متحركة بصيغة Lottie من Mind Ai');
  }

  @override
  void dispose() {
    _prompt.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.read<SettingsService>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('🎁 صانع الهدايا المتحركة', style: TextStyle(fontWeight: FontWeight.w900)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Align(alignment: AlignmentDirectional.centerEnd, child: QuotaPill(Usage.sticker)),
          const SizedBox(height: 8),
          TextField(
            controller: _prompt,
            minLines: 1,
            maxLines: 3,
            decoration: const InputDecoration(hintText: 'وش الهدية؟ مثال: تاج ذهبي مرصع بالألماس'),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            children: [
              for (final i in _ideas) ActionChip(label: Text(i), onPressed: () => setState(() => _prompt.text = i)),
            ],
          ),
          const SizedBox(height: 12),
          const Text('التأثير', style: TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final e in GiftEffect.values)
                ChoiceChip(
                  label: Text('${e.emoji} ${e.label}'),
                  selected: _effect == e,
                  onSelected: (_) => _setEffect(e),
                ),
            ],
          ),
          const SizedBox(height: 12),
          const Text('أداة الرسم', style: TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          ToolPicker(
            selected: _ai.id,
            onSelected: (id) => setState(() => _ai = ImageTool.byId(id)),
            choices: [
              for (final t in ImageTool.all)
                if (t.backend.name != 'custom' || t.available(settings))
                  ToolChoice(
                    id: t.id,
                    label: t.label,
                    emoji: t.emoji,
                    points: t.points + 2,
                    note: t.note,
                    needs: t.needs,
                    available: t.available(settings),
                  ),
            ],
          ),
          const SizedBox(height: 16),
          GradientButton(
            label: _busy ? _status : 'اصنع الهدية',
            icon: Icons.card_giftcard_rounded,
            gradient: MindColors.sunset,
            loading: _busy,
            onPressed: _make,
          ),
          const SizedBox(height: 18),
          if (_gif != null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    Container(
                      height: 300,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(18),
                        gradient: const LinearGradient(
                          colors: [Color(0xFF1B1035), Color(0xFF3A1D6E)],
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                        ),
                      ),
                      child: Image.memory(_gif!, gaplessPlayback: true),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.gif_box_outlined),
                            label: const Text('GIF'),
                            onPressed: () => LibraryService.share(_gifPath!),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: FilledButton.icon(
                            icon: const Icon(Icons.animation_rounded),
                            label: const Text('Lottie للتطبيقات'),
                            onPressed: _shareLottie,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'ملف Lottie (JSON) يشتغل في تطبيقات أندرويد وiOS والويب وFlutter بخلفية شفافة.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12, color: MindColors.muted),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
