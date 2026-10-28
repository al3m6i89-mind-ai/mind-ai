import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';

import '../../app/theme.dart';
import '../../providers/voice_gen.dart';
import '../../services/library_service.dart';
import '../../services/subscription_service.dart';
import '../../widgets/common.dart';

/// Text to speech: a natural AI voice file with Gemini, or the phone's free voice.
class VoicePage extends StatefulWidget {
  const VoicePage({super.key});

  @override
  State<VoicePage> createState() => _VoicePageState();
}

class _VoicePageState extends State<VoicePage> {
  final _text = TextEditingController();
  VoiceOption _voice = VoiceOption.all.first;
  int _style = 0;
  bool _busy = false;
  Creation? _result;
  VideoPlayerController? _player;
  late final VoiceGen _gen = context.read<VoiceGen>();

  static const _styles = [
    ('عادي', ''),
    ('حماسي', 'excitedly and energetically'),
    ('هادئ', 'calmly and warmly'),
    ('راوي قصص', 'like a captivating storyteller'),
    ('إعلان', 'like a professional TV advertisement voice-over'),
    ('حزين', 'sadly and softly'),
  ];

  Future<void> _make() async {
    final text = _text.text.trim();
    if (text.isEmpty) return;
    final voice = _gen;
    FocusScope.of(context).unfocus();
    if (!voice.hasAiVoice) {
      await voice.speakOnDevice(text);
      return;
    }
    final subs = context.read<SubscriptionService>();
    final library = context.read<LibraryService>();
    try {
      subs.ensure(Usage.image, points: 2);
      setState(() => _busy = true);
      final wav = await voice.synthesize(text, _voice, style: _styles[_style].$2);
      final saved = await library.save(wav, CreationKind.voice, text, ext: 'wav');
      await subs.consume(Usage.image, points: 2);
      await _player?.dispose();
      _player = VideoPlayerController.file(File(saved.path));
      await _player!.initialize();
      await _player!.play();
      setState(() => _result = saved);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _player?.dispose();
    _gen.stop();
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ai = _gen.hasAiVoice;
    return Scaffold(
      appBar: AppBar(
        title: const Text('إنشاء صوت 🎙️', style: TextStyle(fontWeight: FontWeight.w900)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _text,
            minLines: 4,
            maxLines: 10,
            decoration: const InputDecoration(
              hintText: 'اكتب النص اللي تبيه يتحول لصوت…\nمثال: أهلاً بكم في متجرنا، خصومات حتى ٥٠٪ اليوم فقط!',
            ),
          ),
          const SizedBox(height: 14),
          if (ai) ...[
            const Text('الصوت', style: TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final v in VoiceOption.all)
                  ChoiceChip(
                    label: Text(v.label),
                    selected: _voice == v,
                    onSelected: (_) => setState(() => _voice = v),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            const Text('الأسلوب', style: TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final (i, s) in _styles.indexed)
                  ChoiceChip(label: Text(s.$1), selected: _style == i, onSelected: (_) => setState(() => _style = i)),
              ],
            ),
            const SizedBox(height: 18),
          ],
          GradientButton(
            label: _busy ? 'أجهز الصوت…' : (ai ? 'أنشئ الصوت' : 'استمع (صوت الجوال المجاني)'),
            icon: Icons.graphic_eq_rounded,
            gradient: MindColors.sunset,
            loading: _busy,
            onPressed: _make,
          ),
          const SizedBox(height: 10),
          if (!ai)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: MindColors.violet.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Text(
                'تسمع الآن صوت جوالك المجاني. لصوت ذكي طبيعي بأصوات وأساليب متعددة وملف تقدر تشاركه، أضف مفتاح Gemini المجاني من الإعدادات.',
                style: TextStyle(height: 1.5),
              ),
            ),
          if (_result != null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    IconButton.filled(
                      icon: const Icon(Icons.play_arrow_rounded),
                      onPressed: () async {
                        await _player?.seekTo(Duration.zero);
                        await _player?.play();
                      },
                    ),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text('صوتك جاهز ✅', style: TextStyle(fontWeight: FontWeight.w800)),
                    ),
                    FilledButton.icon(
                      icon: const Icon(Icons.share_rounded),
                      label: const Text('مشاركة'),
                      onPressed: () => LibraryService.share(_result!.path),
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
