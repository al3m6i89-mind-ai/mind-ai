import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';

import '../../app/theme.dart';
import '../../providers/video_provider.dart';
import '../../services/chat_service.dart';
import '../../services/library_service.dart';
import '../../services/media_tools.dart';
import '../../services/subscription_service.dart';
import '../../widgets/common.dart';

class VideoPage extends StatefulWidget {
  const VideoPage({super.key});

  @override
  State<VideoPage> createState() => _VideoPageState();
}

class _VideoPageState extends State<VideoPage> {
  final _prompt = TextEditingController();
  int _mode = 0; // 0 = text to video (AI), 1 = animate a photo (free, on device)
  int _seconds = 5;
  bool _busy = false;
  Creation? _result;
  VideoPlayerController? _player;

  Future<void> _fromText() async {
    final text = _prompt.text.trim();
    if (text.isEmpty) return;
    final subs = context.read<SubscriptionService>();
    final video = context.read<VideoProvider>();
    final chat = context.read<ChatService>();
    final library = context.read<LibraryService>();
    try {
      subs.ensure(Usage.video);
      setState(() => _busy = true);
      final english = await chat.englishPrompt(text);
      final out = await video.generate(english, seconds: _seconds);
      final bytes = out.bytes ?? await http.readBytes(Uri.parse(out.url!));
      final saved = await library.save(Uint8List.fromList(bytes), CreationKind.video, text);
      await subs.consume(Usage.video);
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
    setState(() => _busy = true);
    try {
      final gif = await MediaTools.kenBurns(await x.readAsBytes());
      final saved = await library.save(gif, CreationKind.animatedSticker, 'صورة متحركة', ext: 'gif');
      await _show(saved);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _show(Creation c) async {
    await _player?.dispose();
    _player = null;
    if (c.path.endsWith('.mp4')) {
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
          if (_mode == 0) ...[
            const Align(alignment: AlignmentDirectional.centerEnd, child: QuotaPill(Usage.video)),
            const SizedBox(height: 8),
            TextField(
              controller: _prompt,
              minLines: 3,
              maxLines: 6,
              decoration: const InputDecoration(hintText: 'مثال: سيارة رياضية حمراء تسير على طريق صحراوي وقت الغروب، تصوير سينمائي'),
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
              label: _busy ? 'جاري إنشاء الفيديو… قد يستغرق دقيقة أو أكثر' : 'أنشئ الفيديو',
              icon: Icons.movie_creation_outlined,
              gradient: MindColors.fresh,
              loading: _busy,
              onPressed: _fromText,
            ),
            const SizedBox(height: 8),
            const Text(
              'مزوّد الفيديو تقدر تغيّره من الإعدادات. للاستخدام المجاني بدون حدود جرّب "حرّك صورة".',
              style: TextStyle(fontSize: 12, color: MindColors.muted),
            ),
          ] else ...[
            const Text('اختر صورة وسنحوّلها لمقطع متحرك بتقريب وحركة كاميرا سينمائية، على جوالك مباشرة وبدون أي تكلفة.'),
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
