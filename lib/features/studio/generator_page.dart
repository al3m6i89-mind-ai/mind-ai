import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../app/theme.dart';
import '../../providers/image_gen.dart';
import '../../services/chat_service.dart';
import '../../services/library_service.dart';
import '../../services/media_tools.dart';
import '../../services/subscription_service.dart';
import '../../widgets/common.dart';
import 'studio_screen.dart';

/// One screen for images, stickers, animated stickers, faces and photo edits.
/// The tool decides the prompt recipe and the post-processing.
class GeneratorPage extends StatefulWidget {
  const GeneratorPage({super.key, required this.tool});
  final StudioTool tool;

  @override
  State<GeneratorPage> createState() => _GeneratorPageState();
}

class _Ratio {
  const _Ratio(this.label, this.w, this.h);
  final String label;
  final int w, h;
}

const _ratios = [
  _Ratio('1:1', 1024, 1024),
  _Ratio('9:16', 768, 1344),
  _Ratio('16:9', 1344, 768),
  _Ratio('3:4', 896, 1152),
];

const _faceKinds = [
  ('واقعي', 'portrait photo of a person, studio lighting, detailed face'),
  ('أنمي', 'anime character face portrait, big expressive eyes'),
  ('كرتون 3D', '3d pixar style character face, cute, soft lighting'),
  ('إيموجي', 'glossy 3d emoji face icon, centered, white background'),
  ('بكسل', 'pixel art face avatar, 32-bit, centered'),
  ('كاريكاتير', 'funny caricature face, exaggerated features, colorful'),
];

class _GeneratorPageState extends State<GeneratorPage> {
  final _prompt = TextEditingController();
  ImageStyle _style = ImageStyle.all.first;
  _Ratio _ratio = _ratios.first;
  int _face = 0;
  StickerMotion _motion = StickerMotion.bounce;
  Uint8List? _photo;
  bool _busy = false;
  String _status = '';
  Uint8List? _result;
  Uint8List? _stillSticker;
  String _resultExt = 'jpg';

  StudioTool get tool => widget.tool;

  Usage get _usage => switch (tool) {
        StudioTool.sticker || StudioTool.animatedSticker => Usage.sticker,
        _ => Usage.image,
      };

  CreationKind get _kind => switch (tool) {
        StudioTool.sticker => CreationKind.sticker,
        StudioTool.animatedSticker => CreationKind.animatedSticker,
        StudioTool.face => CreationKind.face,
        _ => CreationKind.image,
      };

  String _recipe(String english) {
    final style = _style.suffix.isEmpty ? '' : ', ${_style.suffix}';
    return switch (tool) {
      StudioTool.sticker || StudioTool.animatedSticker =>
        'cute sticker of $english$style, die-cut sticker, bold clean outline, centered, full body, plain pure white background, no text',
      StudioTool.face => '${_faceKinds[_face].$2}, $english$style',
      StudioTool.photoEdit => 'Edit this photo: $english. Keep the person\'s identity and face unchanged$style',
      _ => '$english$style',
    };
  }

  Future<void> _pickPhoto() async {
    final x = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1280, imageQuality: 88);
    if (x != null) {
      final b = await x.readAsBytes();
      setState(() => _photo = b);
    }
  }

  Future<void> _generate() async {
    final text = _prompt.text.trim();
    if (text.isEmpty) return;
    if (tool == StudioTool.photoEdit && _photo == null) {
      showError(context, 'اختر صورة أولاً');
      return;
    }
    final subs = context.read<SubscriptionService>();
    final images = context.read<ImageGen>();
    final chat = context.read<ChatService>();
    final library = context.read<LibraryService>();
    FocusScope.of(context).unfocus();
    try {
      subs.ensure(_usage);
      setState(() {
        _busy = true;
        _status = 'أفهم فكرتك…';
        _result = null;
      });
      final english = await chat.englishPrompt(text);
      setState(() => _status = 'أرسم لك الآن… 🎨');
      final square = tool != StudioTool.image;
      final out = await images.generate(
        _recipe(english),
        width: square ? 1024 : _ratio.w,
        height: square ? 1024 : _ratio.h,
        reference: tool == StudioTool.photoEdit || (tool == StudioTool.face && _photo != null) ? _photo : null,
      );

      var bytes = out.bytes;
      var ext = 'jpg';
      if (tool == StudioTool.sticker || tool == StudioTool.animatedSticker) {
        setState(() => _status = 'أقص الخلفية وأجهز الملصق…');
        bytes = await MediaTools.makeSticker(bytes);
        ext = 'png';
        _stillSticker = bytes;
        if (tool == StudioTool.animatedSticker) {
          setState(() => _status = 'أحرّك الملصق… 💃');
          bytes = await MediaTools.animateSticker(bytes, _motion);
          ext = 'gif';
        }
      }
      await library.save(bytes, _kind, text, ext: ext);
      await subs.consume(_usage);
      setState(() {
        _result = bytes;
        _resultExt = ext;
      });
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Re-animates the same sticker with another motion without a new AI call.
  Future<void> _remotion(StickerMotion m) async {
    setState(() => _motion = m);
    if (_stillSticker == null || _busy) return;
    setState(() {
      _busy = true;
      _status = 'أحرّك الملصق… 💃';
    });
    try {
      final gif = await MediaTools.animateSticker(_stillSticker!, m);
      if (!mounted) return;
      await context.read<LibraryService>().save(gif, CreationKind.animatedSticker, _prompt.text, ext: 'gif');
      setState(() => _result = gif);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _prompt.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryService>();
    return Scaffold(
      appBar: AppBar(title: Text('${tool.emoji} ${tool.title}')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(children: [Expanded(child: Text(tool.subtitle, style: const TextStyle(color: MindColors.muted))), QuotaPill(_usage)]),
          const SizedBox(height: 12),
          if (tool == StudioTool.photoEdit || tool == StudioTool.face) _photoPicker(),
          TextField(
            controller: _prompt,
            minLines: 2,
            maxLines: 5,
            decoration: InputDecoration(hintText: _hint),
          ),
          const SizedBox(height: 14),
          if (tool == StudioTool.face) ...[
            const _Label('نوع الفيس'),
            _chips(_faceKinds.map((f) => f.$1).toList(), _face, (i) => setState(() => _face = i)),
          ],
          if (tool == StudioTool.animatedSticker) ...[
            const _Label('الحركة'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final m in StickerMotion.values)
                  ChoiceChip(
                    label: Text('${m.emoji} ${m.label}'),
                    selected: _motion == m,
                    onSelected: (_) => _remotion(m),
                  ),
              ],
            ),
            const SizedBox(height: 10),
          ],
          const _Label('الأسلوب'),
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final s in ImageStyle.all)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(end: 8),
                    child: ChoiceChip(
                      label: Text('${s.emoji} ${s.label}'),
                      selected: _style == s,
                      onSelected: (_) => setState(() => _style = s),
                    ),
                  ),
              ],
            ),
          ),
          if (tool == StudioTool.image) ...[
            const SizedBox(height: 10),
            const _Label('المقاس'),
            _chips(_ratios.map((r) => r.label).toList(), _ratios.indexOf(_ratio), (i) => setState(() => _ratio = _ratios[i])),
          ],
          const SizedBox(height: 18),
          GradientButton(
            label: _busy ? _status : 'أنشئ الآن',
            icon: Icons.auto_awesome,
            loading: _busy,
            gradient: tool.gradient,
            onPressed: _generate,
          ),
          const SizedBox(height: 18),
          if (_result != null) _resultCard(library),
        ],
      ),
    );
  }

  String get _hint => switch (tool) {
        StudioTool.sticker => 'مثال: قطة تلبس نظارة شمسية وتضحك',
        StudioTool.animatedSticker => 'مثال: بطريق يلوّح بيده',
        StudioTool.face => 'مثال: شاب عربي بلحية خفيفة وابتسامة',
        StudioTool.photoEdit => 'مثال: غيّر الخلفية لشاطئ وقت الغروب',
        _ => 'صف الصورة التي تتخيلها بالتفصيل…',
      };

  Widget _photoPicker() => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: InkWell(
          onTap: _pickPhoto,
          borderRadius: BorderRadius.circular(18),
          child: Ink(
            height: 120,
            decoration: BoxDecoration(
              color: Theme.of(context).cardTheme.color,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: MindColors.violet.withValues(alpha: 0.3)),
            ),
            child: _photo == null
                ? Center(
                    child: Text(
                      tool == StudioTool.face ? '📸 أضف صورتك (اختياري) لتحويلها لفيس' : '📸 اختر الصورة التي تريد تعديلها',
                      style: const TextStyle(fontWeight: FontWeight.w700, color: MindColors.violet),
                    ),
                  )
                : ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: Image.memory(_photo!, fit: BoxFit.cover, width: double.infinity),
                  ),
          ),
        ),
      );

  Widget _chips(List<String> labels, int selected, ValueChanged<int> onTap) => Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (var i = 0; i < labels.length; i++)
            ChoiceChip(label: Text(labels[i]), selected: selected == i, onSelected: (_) => onTap(i)),
        ],
      );

  Widget _resultCard(LibraryService library) {
    final sticker = _resultExt != 'jpg';
    final latest = library.items.isEmpty ? null : library.items.first;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Container(
              decoration: sticker
                  ? BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      color: const Color(0xFFEDEAF7),
                    )
                  : null,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Image.memory(_result!, gaplessPlayback: true),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.download_rounded),
                    label: const Text('حفظ'),
                    onPressed: latest == null
                        ? null
                        : () async {
                            await LibraryService.toGallery(latest.path);
                            if (mounted) {
                              ScaffoldMessenger.of(context)
                                  .showSnackBar(const SnackBar(content: Text('تم الحفظ في المعرض ✅')));
                            }
                          },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.icon(
                    icon: const Icon(Icons.share_rounded),
                    label: const Text('مشاركة'),
                    onPressed: latest == null ? null : () => LibraryService.share(latest.path),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  icon: const Icon(Icons.refresh_rounded),
                  onPressed: _busy ? null : _generate,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(text, style: const TextStyle(fontWeight: FontWeight.w800)),
      );
}
