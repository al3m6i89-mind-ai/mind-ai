import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';

import '../../app/theme.dart';
import '../../providers/image_gen.dart';
import '../../providers/tools.dart';
import '../../providers/video_provider.dart';
import '../../services/chat_service.dart';
import '../../services/gift_maker.dart';
import '../../services/gift_sound.dart';
import '../../services/library_service.dart';
import '../../services/media_tools.dart';
import '../../services/settings_service.dart';
import '../../services/subscription_service.dart';
import '../../widgets/common.dart';
import '../../widgets/tool_picker.dart';

/// Live-stream style animated gifts: AI artwork, cut out, animated, with a
/// soundtrack. Quick mode uses the on-phone effects engine; pro mode has a video
/// model animate the gift on a green screen, keys it out and adds the effects.
class GiftPage extends StatefulWidget {
  const GiftPage({super.key});

  @override
  State<GiftPage> createState() => _GiftPageState();
}

class _GiftPageState extends State<GiftPage> {
  final _prompt = TextEditingController();
  final _scene = TextEditingController();
  late ImageTool _ai = ImageTool.byId(context.read<SettingsService>().imageToolId);
  GiftEffect _effect = GiftEffect.spin3d;
  bool _pro = false;
  bool _busy = false;
  String _status = '';
  Uint8List? _art;
  Uint8List? _gif;
  String? _gifPath;
  Uint8List? _zip;
  VideoPlayerController? _sound;
  String? _soundPath;

  static const _ideas = ['صندوق هدية أحمر', 'تاج ذهبي', 'وردة حمراء', 'سيارة رياضية', 'قلب كريستال', 'أسد ذهبي'];
  static const _proTools = ['seedance', 'hf'];

  VideoTool? _proTool(SettingsService s) {
    for (final id in _proTools) {
      final t = VideoTool.byId(id);
      if (t.available(s)) return t;
    }
    return null;
  }

  /// A story with several steps needs the longer clip.
  int get _seconds => _scene.text.trim().length > 40 ? 10 : 5;

  int get _points {
    final pro = _pro ? _proTool(context.read<SettingsService>()) : null;
    return _ai.points + 2 + (pro == null ? 0 : pro.points * (_seconds > 5 ? 2 : 1));
  }

  static String _motionPrompt(GiftEffect e) => switch (e) {
    GiftEffect.spin3d =>
      'rotates 360 degrees smoothly like a premium 3d product turntable, light glinting on its surface',
    GiftEffect.royal => 'rises up, turns slowly and shines with golden sparkles and light flares',
    GiftEffect.flyIn => 'flies in from the side, spins once and lands with a burst of colorful sparkles',
    GiftEffect.hearts => 'bounces gently while pink hearts float up around it',
    GiftEffect.fireworks => 'pops in and colorful fireworks sparkles burst around it',
    GiftEffect.shine => 'glitters as a bright light sweep glides across it, rotating slightly',
  };

  Future<void> _make() async {
    final text = _prompt.text.trim();
    if (text.isEmpty) return;
    final subs = context.read<SubscriptionService>();
    final images = context.read<ImageGen>();
    final chat = context.read<ChatService>();
    final library = context.read<LibraryService>();
    final pro = _pro ? _proTool(context.read<SettingsService>()) : null;
    final points = _points;
    FocusScope.of(context).unfocus();
    try {
      subs.ensure(Usage.sticker, points: points);
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
      _zip = null;
      if (pro != null) {
        final scene = _scene.text.trim();
        final story = scene.isEmpty ? null : await chat.englishPrompt(scene);
        await _animatePro(english, story, pro, library);
        await _music(_seconds.toDouble());
      } else {
        await _animate(library);
        await _music(GiftMaker.seconds);
      }
      await subs.consume(Usage.sticker, points: points);
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

  /// The video model animates the gift on a green screen; the frames are then
  /// keyed to transparency on the phone and the effects are layered on top.
  Future<void> _animatePro(String english, String? story, VideoTool tool, LibraryService library) async {
    final video = context.read<VideoProvider>();
    final motion = story == null
        ? 'The $english ${_motionPrompt(_effect)}.'
        : '$story. Show each step clearly and in this order.';
    setState(() => _status = 'أحرّك الهدية بـ ${tool.label}… قد يأخذ دقيقة أو أكثر 🎬');
    final out = await video.generate(
      '$motion Static camera, the object stays centered and fully in frame. '
      'Keep the solid pure green background (#00FF00) completely flat and unchanged, no shadows on it, no other objects.',
      seconds: _seconds,
      image: GiftMaker.onGreen(_art!),
      backend: tool.backend,
    );
    final bytes = out.bytes ?? await http.readBytes(Uri.parse(out.url!));
    final mp4 = await library.save(Uint8List.fromList(bytes), CreationKind.video, 'هدية (شاشة خضراء): ${_prompt.text}');
    setState(() => _status = 'أشيل الخلفية من كل لقطة… ✂️');
    final frames = await GiftMaker.extractFrames(mp4.path, count: _seconds > 5 ? 60 : 36);
    final (gif, zip) = await GiftMaker.keyFrames(frames, effect: _effect);
    final saved = await library.save(gif, CreationKind.animatedSticker, 'هدية: ${_prompt.text}', ext: 'gif');
    setState(() {
      _gif = gif;
      _gifPath = saved.path;
      _zip = zip;
    });
  }

  /// Makes the matching soundtrack and plays it with the preview.
  Future<void> _music(double seconds) async {
    setState(() => _status = 'أألّف الموسيقى… 🎵');
    final wav = await GiftSound.make(_effect, seconds: seconds);
    final dir = await getTemporaryDirectory();
    final f = File('${dir.path}/mindai_gift_${DateTime.now().millisecondsSinceEpoch}.wav');
    await f.writeAsBytes(wav);
    await _sound?.dispose();
    _sound = VideoPlayerController.file(f);
    await _sound!.initialize();
    await _sound!.setLooping(true);
    await _sound!.play();
    setState(() => _soundPath = f.path);
  }

  /// In quick mode, changing the effect re-animates the same artwork for free.
  Future<void> _setEffect(GiftEffect e) async {
    setState(() => _effect = e);
    if (_art == null || _busy || _zip != null) return;
    setState(() => _busy = true);
    try {
      await _animate(context.read<LibraryService>());
      await _music(GiftMaker.seconds);
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

  Future<void> _shareZip() async {
    final dir = await getTemporaryDirectory();
    final f = File('${dir.path}/mindai_gift_frames_${DateTime.now().millisecondsSinceEpoch}.zip');
    await f.writeAsBytes(_zip!);
    await LibraryService.share(f.path, text: 'لقطات الهدية PNG شفافة (لـ SVGA / VAP / After Effects)');
  }

  @override
  void dispose() {
    _sound?.dispose();
    _scene.dispose();
    _prompt.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.read<SettingsService>();
    final proTool = _proTool(settings);
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
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, label: Text('⚡ سريع مجاني')),
              ButtonSegment(value: true, label: Text('🎬 احترافي 3D')),
            ],
            selected: {_pro},
            onSelectionChanged: (v) {
              if (v.first && proTool == null) {
                showError(context, 'الوضع الاحترافي يحتاج مفتاح BytePlus (Seedance) أو رمز Hugging Face من الإعدادات.');
                return;
              }
              setState(() => _pro = v.first);
            },
          ),
          const SizedBox(height: 6),
          Text(
            _pro
                ? 'فيديو ذكاء اصطناعي يحرّك الهدية حركة حقيقية (${proTool?.label ?? ''})، ثم نشيل الخلفية ونضيف المؤثرات والموسيقى.'
                : 'مؤثرات جاهزة على جوالك مع موسيقى: سريعة ومجانية، وتصدّر GIF وLottie.',
            style: const TextStyle(fontSize: 12, color: MindColors.muted),
          ),
          if (_pro) ...[
            const SizedBox(height: 10),
            TextField(
              controller: _scene,
              minLines: 2,
              maxLines: 4,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'وصف المشهد (اختياري)',
                hintText: 'مثال: البوكس يدور ببطء، ثم يفتح غطاه، ويطلع منه خاتم ذهبي يلمع',
              ),
            ),
          ],
          const SizedBox(height: 12),
          const Text('التأثير والموسيقى', style: TextStyle(fontWeight: FontWeight.w800)),
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
            label: _busy ? _status : 'اصنع الهدية · 💎$_points',
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
                      width: double.infinity,
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
                    if (_soundPath != null)
                      Row(
                        children: [
                          IconButton(
                            icon: Icon(_sound?.value.isPlaying == true ? Icons.volume_up : Icons.volume_off),
                            onPressed: () async {
                              final p = _sound;
                              if (p == null) return;
                              p.value.isPlaying ? await p.pause() : await p.play();
                              setState(() {});
                            },
                          ),
                          const Expanded(
                            child: Text('🎵 موسيقى الهدية', style: TextStyle(fontWeight: FontWeight.w700)),
                          ),
                          TextButton.icon(
                            icon: const Icon(Icons.share_rounded, size: 18),
                            label: const Text('الصوت'),
                            onPressed: () => LibraryService.share(_soundPath!),
                          ),
                        ],
                      ),
                    const SizedBox(height: 4),
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
                          child: _zip != null
                              ? FilledButton.icon(
                                  icon: const Icon(Icons.folder_zip_outlined),
                                  label: const Text('لقطات PNG'),
                                  onPressed: _shareZip,
                                )
                              : FilledButton.icon(
                                  icon: const Icon(Icons.animation_rounded),
                                  label: const Text('Lottie للتطبيقات'),
                                  onPressed: _shareLottie,
                                ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _zip != null
                          ? 'لقطات PNG شفافة تحوّلها لـ SVGA أو VAP لتطبيقات الدردشة. فيديو الشاشة الخضراء محفوظ في إبداعاتك.'
                          : 'ملف Lottie (JSON) يشتغل في تطبيقات أندرويد وiOS والويب وFlutter بخلفية شفافة.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 12, color: MindColors.muted),
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
