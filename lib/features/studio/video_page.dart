import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';

import '../../app/theme.dart';
import '../../providers/ai_models.dart';
import '../../providers/image_gen.dart';
import '../../providers/tools.dart';
import '../../widgets/tool_picker.dart';
import '../../providers/video_provider.dart';
import '../../services/chat_service.dart';
import '../../services/library_service.dart';
import '../../services/media_tools.dart';
import '../../services/settings_service.dart';
import '../../services/subscription_service.dart';
import '../../widgets/common.dart';

class VideoPage extends StatefulWidget {
  const VideoPage({super.key});

  @override
  State<VideoPage> createState() => _VideoPageState();
}

class _VideoPageState extends State<VideoPage> {
  final _prompt = TextEditingController();
  late VideoTool _tool = VideoTool.byId(context.read<SettingsService>().videoToolId);
  int _mode = 0; // 0 = text to video (AI), 1 = animate a photo (free, on device)
  int _seconds = 5;
  bool _busy = false;
  String _status = '';
  Creation? _result;
  VideoPlayerController? _player;

  Future<void> _fromText() async {
    final text = _prompt.text.trim();
    if (text.isEmpty) return;
    final subs = context.read<SubscriptionService>();
    final video = context.read<VideoProvider>();
    final images = context.read<ImageGen>();
    final chat = context.read<ChatService>();
    final library = context.read<LibraryService>();
    FocusScope.of(context).unfocus();
    try {
      final tool = _tool.available(video.settings) ? _tool : VideoTool.all.first;
      var points = tool.points;
      subs.ensure(Usage.video, points: points);
      setState(() {
        _busy = true;
        _status = 'أفهم فكرتك…';
      });
      final english = await chat.englishPrompt(text);
      Creation? saved;
      if (tool.backend != null) {
        setState(() => _status = 'أصنع الفيديو بـ ${tool.label}… قد يأخذ دقيقة أو أكثر');
        try {
          final out = await video.generate(english, seconds: _seconds, backend: tool.backend);
          final bytes = out.bytes ?? await http.readBytes(Uri.parse(out.url!));
          saved = await library.save(Uint8List.fromList(bytes), CreationKind.video, text);
        } on AiException catch (e) {
          // A busy or unpaid provider should not leave the user with nothing.
          if (mounted) showError(context, '${e.message}\nأجهز لك نسخة مجانية بدلاً منه…');
          points = VideoTool.all.first.points;
        }
      }
      if (saved == null) {
        // Free path, no key needed: an AI keyframe plus a cinematic camera move on the phone.
        setState(() => _status = 'أرسم المشهد… 🎨');
        final frame = await images.generate(
          '$english, cinematic film still, dramatic lighting, wide shot, highly detailed',
          width: 1024,
          height: 576,
        );
        setState(() => _status = 'أحرّك الكاميرا… 🎬');
        final gif = await MediaTools.kenBurns(frame.bytes, seconds: _seconds);
        saved = await library.save(gif, CreationKind.video, text, ext: 'gif');
      }
      await subs.consume(Usage.video, points: points);
      await _show(saved);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _fromPhoto() async {
    final x = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1280);
    if (x == null || !mounted) return;
    final library = context.read<LibraryService>();
    final video = context.read<VideoProvider>();
    final chat = context.read<ChatService>();
    final subs = context.read<SubscriptionService>();
    final idea = _prompt.text.trim();
    setState(() => _busy = true);
    try {
      final photo = await x.readAsBytes();
      final tool = _tool;
      if (_animatesPhotos(tool) && tool.available(video.settings)) {
        // The model animates the photo itself, following the description if one is written.
        subs.ensure(Usage.video, points: tool.points);
        setState(() => _status = 'أحرّك صورتك بـ ${tool.label}… قد يأخذ دقيقة');
        final english = idea.isEmpty ? 'natural lively motion, cinematic' : await chat.englishPrompt(idea);
        final out = await video.generate(english, seconds: _seconds, image: photo, backend: tool.backend);
        final bytes = out.bytes ?? await http.readBytes(Uri.parse(out.url!));
        await subs.consume(Usage.video, points: tool.points);
        await _show(
          await library.save(Uint8List.fromList(bytes), CreationKind.video, idea.isEmpty ? 'صورة متحركة' : idea),
        );
        return;
      }
      final gif = await MediaTools.kenBurns(photo, seconds: _seconds);
      final saved = await library.save(gif, CreationKind.animatedSticker, 'صورة متحركة', ext: 'gif');
      await _show(saved);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  static bool _animatesPhotos(VideoTool t) =>
      t.backend == VideoBackend.seedance ||
      t.backend == VideoBackend.huggingface ||
      t.backend == VideoBackend.replicate;

  Widget _picker(BuildContext context) {
    final settings = context.read<SettingsService>();
    return ToolPicker(
      selected: _tool.id,
      onSelected: (id) {
        setState(() => _tool = VideoTool.byId(id));
        settings.setVideoToolId(id);
      },
      choices: [
        for (final t in VideoTool.all)
          if ((_mode == 0 || t.backend == null || _animatesPhotos(t)) &&
              (t.backend != VideoBackend.custom || t.available(settings)))
            ToolChoice(
              id: t.id,
              label: t.label,
              emoji: t.emoji,
              points: _mode == 1 && t.backend == null ? 0 : t.points,
              note: _mode == 1 && t.backend == null ? 'مجاني: تقريب وحركة كاميرا' : t.note,
              needs: t.needs,
              available: t.available(settings),
            ),
      ],
    );
  }

  Future<void> _show(Creation c) async {
    await _player?.dispose();
    _player = null;
    if (!c.path.endsWith('.gif')) {
      _player = VideoPlayerController.file(File(c.path));
      await _player!.initialize();
      await _player!.setLooping(true);
      await _player!.play();
    }
    setState(() => _result = c);
  }

  @override
  void dispose() {
    _player?.dispose();
    _prompt.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('🎬 الفيديو')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 0, label: Text('من وصف (AI)'), icon: Icon(Icons.text_fields)),
              ButtonSegment(value: 1, label: Text('حرّك صورة (مجاني)'), icon: Icon(Icons.photo)),
            ],
            selected: {_mode},
            onSelectionChanged: (s) => setState(() => _mode = s.first),
          ),
          const SizedBox(height: 16),
          const SizedBox(height: 12),
          const Text('أداة الفيديو', style: TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          _picker(context),
          const SizedBox(height: 4),
          if (_mode == 0) ...[
            const Align(alignment: AlignmentDirectional.centerEnd, child: QuotaPill(Usage.video)),
            const SizedBox(height: 8),
            TextField(
              controller: _prompt,
              minLines: 3,
              maxLines: 6,
              decoration: const InputDecoration(
                hintText: 'مثال: سيارة رياضية حمراء تسير على طريق صحراوي وقت الغروب، تصوير سينمائي',
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Text('المدة:', style: TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(width: 8),
                for (final s in [5, 8, 10])
                  Padding(
                    padding: const EdgeInsetsDirectional.only(end: 8),
                    child: ChoiceChip(
                      label: Text('$s ث'),
                      selected: _seconds == s,
                      onSelected: (_) => setState(() => _seconds = s),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            GradientButton(
              label: _busy ? _status : 'أنشئ الفيديو',
              icon: Icons.movie_creation_outlined,
              gradient: MindColors.fresh,
              loading: _busy,
              onPressed: _fromText,
            ),
            const SizedBox(height: 10),
            _ModeNote(real: _tool.backend != null && _tool.available(context.read<SettingsService>())),
          ] else ...[
            const Text(
              'اختر صورة وسنحوّلها لمقطع متحرك بتقريب وحركة كاميرا سينمائية، على جوالك مباشرة وبدون أي تكلفة.',
            ),
            const SizedBox(height: 16),
            GradientButton(
              label: 'اختر صورة',
              icon: Icons.photo_library_outlined,
              gradient: MindColors.fresh,
              loading: _busy,
              onPressed: _fromPhoto,
            ),
          ],
          const SizedBox(height: 20),
          if (_result != null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: _player != null
                          ? AspectRatio(aspectRatio: _player!.value.aspectRatio, child: VideoPlayer(_player!))
                          : Image.file(File(_result!.path)),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.download_rounded),
                            label: const Text('حفظ'),
                            onPressed: () => LibraryService.toGallery(_result!.path, video: _player != null),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: FilledButton.icon(
                            icon: const Icon(Icons.share_rounded),
                            label: const Text('مشاركة'),
                            onPressed: () => LibraryService.share(_result!.path),
                          ),
                        ),
                      ],
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

class _ModeNote extends StatelessWidget {
  const _ModeNote({required this.real});
  final bool real;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(color: MindColors.mint.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(14)),
    child: Row(
      children: [
        Text(real ? '🎥' : '✨', style: const TextStyle(fontSize: 20)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            real
                ? 'فيديو ذكاء اصطناعي حقيقي من المزوّد اللي اخترته.'
                : 'مجاني: نرسم مشهدك بالذكاء الاصطناعي ونحرّك الكاميرا عليه بشكل سينمائي.',
            style: const TextStyle(fontSize: 13),
          ),
        ),
      ],
    ),
  );
}
