import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';

import '../../app/theme.dart';
import '../../services/social/social_service.dart';
import '../../services/social/text_utils.dart';
import '../../services/video_tools.dart';
import '../../widgets/common.dart';
import 'posts_view.dart';
import 'stories.dart';
import 'widgets.dart';

/// "+" button: pick what to make. All of it goes out under the same ID.
Future<void> openCreate(BuildContext context) {
  return showModalBottomSheet(
    context: context,
    showDragHandle: true,
    builder: (ctx) {
      void go(Widget page) {
        Navigator.pop(ctx);
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
      }

      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('إنشاء', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            ListTile(
              leading: const Text('🎬', style: TextStyle(fontSize: 26)),
              title: const Text('ريل'),
              subtitle: const Text('فيديو عمودي قصير'),
              onTap: () => go(const CreateReelScreen()),
            ),
            ListTile(
              leading: const Text('📸', style: TextStyle(fontSize: 26)),
              title: const Text('منشور صور'),
              subtitle: const Text('حتى 10 صور مع وصف وموقع'),
              onTap: () => go(const CreatePhotoScreen()),
            ),
            ListTile(
              leading: const Text('💬', style: TextStyle(fontSize: 26)),
              title: const Text('منشور نصي'),
              subtitle: const Text('حتى ${SocialText.postLimit} حرفاً'),
              onTap: () => go(const ComposePostScreen()),
            ),
            ListTile(
              leading: const Text('⭕', style: TextStyle(fontSize: 26)),
              title: const Text('قصة'),
              subtitle: const Text('تختفي بعد 24 ساعة'),
              onTap: () {
                Navigator.pop(ctx);
                addStory(context);
              },
            ),
          ],
        ),
      );
    },
  );
}

void openCompose(BuildContext context, {SocialPost? replyTo, SocialPost? quote}) => Navigator.of(context).push(
  MaterialPageRoute(builder: (_) => ComposePostScreen(replyTo: replyTo, quote: quote)),
);

// ---------------------------------------------------------------- text post

class ComposePostScreen extends StatefulWidget {
  const ComposePostScreen({super.key, this.replyTo, this.quote});
  final SocialPost? replyTo;
  final SocialPost? quote;

  @override
  State<ComposePostScreen> createState() => _ComposePostScreenState();
}

class _ComposePostScreenState extends State<ComposePostScreen> {
  final _text = TextEditingController();
  final _images = <String>[];
  bool _busy = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    final list = await ImagePicker().pickMultiImage(maxWidth: 1600, imageQuality: 88, limit: 4);
    setState(() {
      for (final x in list) {
        if (_images.length < 4) _images.add(x.path);
      }
    });
  }

  Future<void> _send() async {
    setState(() => _busy = true);
    try {
      await context.read<SocialService>().createPost(
        text: _text.text,
        imagePaths: _images,
        replyTo: widget.replyTo?.id,
        quoteOf: widget.quote?.id,
      );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) toast(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final social = context.watch<SocialService>();
    final replyAuthor = widget.replyTo == null ? null : social.user(widget.replyTo!.authorId);
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
        title: Text(widget.replyTo != null ? 'رد' : (widget.quote != null ? 'اقتباس' : 'منشور جديد')),
        actions: [
          ListenableBuilder(
            listenable: _text,
            builder: (_, _) {
              final len = _text.text.trim().runes.length;
              final ok = !_busy && len <= SocialText.postLimit && (len > 0 || _images.isNotEmpty || widget.quote != null);
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: FilledButton(onPressed: ok ? _send : null, child: Text(widget.replyTo != null ? 'رد' : 'نشر')),
              );
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          if (widget.replyTo != null) ...[
            PostCard(post: widget.replyTo!, threadLine: true),
            Padding(
              padding: const EdgeInsetsDirectional.only(start: 64, bottom: 6),
              child: Text('ردًا على @${replyAuthor?.handle ?? ''}', style: const TextStyle(color: MindColors.muted)),
            ),
          ],
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SocialAvatar(social.me, size: 42),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _text,
                  autofocus: true,
                  maxLines: null,
                  minLines: 4,
                  style: const TextStyle(fontSize: 18),
                  decoration: InputDecoration(
                    hintText: widget.replyTo != null ? 'اكتب ردّك' : 'ماذا يحدث؟',
                    filled: false,
                    border: InputBorder.none,
                  ),
                ),
              ),
            ],
          ),
          if (_images.isNotEmpty)
            SizedBox(
              height: 120,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _images.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (_, i) => Stack(
                  children: [
                    ClipRRect(borderRadius: BorderRadius.circular(12), child: MediaImage(_images[i], width: 120, height: 120)),
                    PositionedDirectional(
                      top: 4,
                      end: 4,
                      child: GestureDetector(
                        onTap: () => setState(() => _images.removeAt(i)),
                        child: const CircleAvatar(radius: 12, backgroundColor: Colors.black54, child: Icon(Icons.close, size: 15, color: Colors.white)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (widget.quote != null) Padding(padding: const EdgeInsets.only(top: 10), child: QuotedPost(id: widget.quote!.id)),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.image_outlined, color: MindColors.violet),
                onPressed: _images.length >= 4 ? null : _pick,
              ),
              const Spacer(),
              ListenableBuilder(
                listenable: _text,
                builder: (_, _) {
                  final len = _text.text.trim().runes.length;
                  final left = SocialText.postLimit - len;
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        if (left <= 20)
                          Text('$left', style: TextStyle(color: left < 0 ? Colors.red : MindColors.orange, fontWeight: FontWeight.w700)),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            value: (len / SocialText.postLimit).clamp(0, 1).toDouble(),
                            strokeWidth: 2.5,
                            backgroundColor: Colors.grey.withValues(alpha: 0.25),
                            color: left < 0 ? Colors.red : (left <= 20 ? MindColors.orange : MindColors.violet),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- photos

class CreatePhotoScreen extends StatefulWidget {
  const CreatePhotoScreen({super.key});

  @override
  State<CreatePhotoScreen> createState() => _CreatePhotoScreenState();
}

class _CreatePhotoScreenState extends State<CreatePhotoScreen> {
  final _caption = TextEditingController();
  final _location = TextEditingController();
  final _images = <String>[];
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _pick());
  }

  @override
  void dispose() {
    _caption.dispose();
    _location.dispose();
    super.dispose();
  }

  Future<void> _pick({bool camera = false}) async {
    final picker = ImagePicker();
    if (camera) {
      final x = await picker.pickImage(source: ImageSource.camera, maxWidth: 1600, imageQuality: 88);
      if (x != null && _images.length < 10) setState(() => _images.add(x.path));
      return;
    }
    final list = await picker.pickMultiImage(maxWidth: 1600, imageQuality: 88, limit: 10);
    setState(() {
      for (final x in list) {
        if (_images.length < 10) _images.add(x.path);
      }
    });
  }

  Future<void> _share() async {
    setState(() => _busy = true);
    try {
      await context.read<SocialService>().createPhoto(paths: _images, caption: _caption.text, location: _location.text);
      if (mounted) {
        Navigator.pop(context);
        toast(context, 'نُشر منشورك 📸');
      }
    } catch (e) {
      if (mounted) toast(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('منشور صور جديد')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_images.isEmpty)
            AspectRatio(
              aspectRatio: 1,
              child: InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: _pick,
                child: Ink(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: MindColors.violet.withValues(alpha: 0.4), width: 2),
                  ),
                  child: const Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.add_photo_alternate_outlined, size: 56, color: MindColors.violet),
                      SizedBox(height: 8),
                      Text('اختر حتى 10 صور', style: TextStyle(fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
              ),
            )
          else
            SizedBox(
              height: 220,
              child: ReorderableListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: _images.length,
                onReorder: (a, b) => setState(() {
                  if (b > a) b--;
                  _images.insert(b, _images.removeAt(a));
                }),
                itemBuilder: (_, i) => Padding(
                  key: ValueKey(_images[i]),
                  padding: const EdgeInsetsDirectional.only(end: 8),
                  child: Stack(
                    children: [
                      ClipRRect(borderRadius: BorderRadius.circular(14), child: MediaImage(_images[i], width: 200, height: 220)),
                      PositionedDirectional(
                        top: 6,
                        end: 6,
                        child: GestureDetector(
                          onTap: () => setState(() => _images.removeAt(i)),
                          child: const CircleAvatar(radius: 13, backgroundColor: Colors.black54, child: Icon(Icons.close, size: 16, color: Colors.white)),
                        ),
                      ),
                      if (i == 0)
                        PositionedDirectional(
                          bottom: 6,
                          start: 6,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(8)),
                            child: const Text('الغلاف', style: TextStyle(color: Colors.white, fontSize: 12)),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          const SizedBox(height: 8),
          Row(
            children: [
              TextButton.icon(
                onPressed: _images.length >= 10 ? null : _pick,
                icon: const Icon(Icons.photo_library_outlined),
                label: const Text('المعرض'),
              ),
              TextButton.icon(
                onPressed: _images.length >= 10 ? null : () => _pick(camera: true),
                icon: const Icon(Icons.photo_camera_outlined),
                label: const Text('الكاميرا'),
              ),
              const Spacer(),
              Text('${_images.length}/10', style: const TextStyle(color: MindColors.muted)),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _caption,
            maxLines: 5,
            minLines: 2,
            maxLength: SocialText.captionLimit,
            decoration: const InputDecoration(hintText: 'اكتب وصفاً… استخدم #هاشتاق و @إشارة'),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _location,
            decoration: const InputDecoration(hintText: 'إضافة موقع', prefixIcon: Icon(Icons.place_outlined)),
          ),
          const SizedBox(height: 20),
          GradientButton(label: 'مشاركة', icon: Icons.send_rounded, loading: _busy, onPressed: _images.isEmpty ? null : _share),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- reel

class CreateReelScreen extends StatefulWidget {
  const CreateReelScreen({super.key});

  @override
  State<CreateReelScreen> createState() => _CreateReelScreenState();
}

class _CreateReelScreenState extends State<CreateReelScreen> {
  final _caption = TextEditingController();
  final _sound = TextEditingController();
  String? _path;

  /// Cover the person picked; when empty, [_autoCover] (a frame from the video) is used.
  String _cover = '';
  String _autoCover = '';
  VideoPlayerController? _video;
  bool _busy = false;

  String get _effectiveCover => _cover.isNotEmpty ? _cover : _autoCover;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _pick());
  }

  @override
  void dispose() {
    _caption.dispose();
    _sound.dispose();
    _video?.dispose();
    super.dispose();
  }

  Future<void> _pick({bool camera = false}) async {
    final x = await ImagePicker().pickVideo(
      source: camera ? ImageSource.camera : ImageSource.gallery,
      maxDuration: const Duration(minutes: 3),
    );
    if (x == null) return;
    final old = _video;
    final c = VideoPlayerController.file(File(x.path));
    try {
      await c.initialize();
    } catch (_) {
      await c.dispose();
      if (mounted) toast(context, 'تعذّر فتح هذا الفيديو');
      return;
    }
    if (c.value.duration > const Duration(minutes: 3, seconds: 1)) {
      await c.dispose();
      if (mounted) toast(context, 'الحد الأقصى للريل 3 دقائق');
      return;
    }
    await c.setLooping(true);
    await c.play();
    await old?.dispose();
    if (!mounted) return c.dispose();
    setState(() {
      _video = c;
      _path = x.path;
      _autoCover = '';
    });
    // A cover from the video itself, so the reel never shows as a blank tile.
    final thumb = await VideoTools.thumbnail(x.path);
    if (mounted && _path == x.path && thumb != null) setState(() => _autoCover = thumb);
  }

  Future<void> _pickCover() async {
    final x = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 720, imageQuality: 85);
    if (x != null) setState(() => _cover = x.path);
  }

  Future<void> _share() async {
    final path = _path;
    if (path == null) return;
    setState(() => _busy = true);
    _video?.pause();
    final social = context.read<SocialService>();
    String? light;
    try {
      // Smaller upload: 720p, ~2.5 Mbps, on the phone's video chip.
      light = await VideoTools.compress(path);
      await social.createReel(videoPath: light, caption: _caption.text, sound: _sound.text, thumbPath: _effectiveCover);
      if (mounted) {
        Navigator.pop(context);
        toast(context, 'نُشر الريل 🎬');
      }
    } catch (e) {
      if (mounted) toast(context, e);
    } finally {
      // The compressed copy was copied or uploaded; the temporary file can go.
      if (light != null && light != path) {
        try {
          File(light).deleteSync();
        } catch (_) {}
      }
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = _video;
    return Scaffold(
      appBar: AppBar(title: const Text('ريل جديد')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Center(
            child: SizedBox(
              height: 360,
              child: AspectRatio(
                aspectRatio: 9 / 16,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: c == null
                      ? InkWell(
                          onTap: _pick,
                          child: Container(
                            color: Colors.black,
                            alignment: Alignment.center,
                            child: const Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.video_library_outlined, color: Colors.white, size: 48),
                                SizedBox(height: 8),
                                Text('اختر فيديو (حتى 3 دقائق)', style: TextStyle(color: Colors.white)),
                              ],
                            ),
                          ),
                        )
                      : GestureDetector(
                          onTap: () {
                            c.value.isPlaying ? c.pause() : c.play();
                            setState(() {});
                          },
                          child: ColoredBox(
                            color: Colors.black,
                            child: FittedBox(
                              fit: BoxFit.cover,
                              clipBehavior: Clip.hardEdge,
                              child: SizedBox(width: c.value.size.width, height: c.value.size.height, child: VideoPlayer(c)),
                            ),
                          ),
                        ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            alignment: WrapAlignment.center,
            children: [
              TextButton.icon(onPressed: _pick, icon: const Icon(Icons.video_library_outlined), label: const Text('المعرض')),
              TextButton.icon(onPressed: () => _pick(camera: true), icon: const Icon(Icons.videocam_outlined), label: const Text('تصوير')),
              TextButton.icon(
                onPressed: _pickCover,
                icon: _effectiveCover.isEmpty
                    ? const Icon(Icons.image_outlined)
                    : ClipRRect(borderRadius: BorderRadius.circular(4), child: MediaImage(_effectiveCover, width: 22, height: 22)),
                label: Text(_cover.isEmpty ? 'تغيير الغلاف' : 'غلافك'),
              ),
            ],
          ),
          if (_path != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'الحجم ${VideoTools.size(_path!)} · سيُضغط قبل الرفع إلى 720p ليصل أسرع ويوفّر باقتك',
                textAlign: TextAlign.center,
                style: const TextStyle(color: MindColors.muted, fontSize: 12),
              ),
            ),
          const SizedBox(height: 8),
          TextField(
            controller: _caption,
            maxLines: 4,
            minLines: 2,
            maxLength: SocialText.captionLimit,
            decoration: const InputDecoration(hintText: 'وصف الريل… #هاشتاق @إشارة'),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _sound,
            decoration: const InputDecoration(
              hintText: 'اسم الصوت (اتركه فارغاً لـ«الصوت الأصلي»)',
              prefixIcon: Icon(Icons.music_note_rounded),
            ),
          ),
          const SizedBox(height: 20),
          ValueListenableBuilder<double?>(
            valueListenable: VideoTools.progress,
            builder: (_, p, _) => GradientButton(
              label: p != null ? 'جارٍ ضغط الفيديو ${(p * 100).round()}%' : (_busy ? 'جارٍ النشر…' : 'نشر الريل'),
              icon: Icons.send_rounded,
              loading: _busy,
              onPressed: _path == null ? null : _share,
            ),
          ),
        ],
      ),
    );
  }
}
