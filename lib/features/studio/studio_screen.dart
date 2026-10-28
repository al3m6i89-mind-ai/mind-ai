import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../widgets/common.dart';
import '../code/projects_screen.dart';
import '../voice/voice_page.dart';
import 'generator_page.dart';
import 'video_page.dart';

enum StudioTool { image, sticker, animatedSticker, removeBg, face, photoEdit, video, voice, slides, website, game }

extension StudioToolInfo on StudioTool {
  String get title => switch (this) {
    StudioTool.image => 'إنشاء صور',
    StudioTool.sticker => 'ملصقات',
    StudioTool.animatedSticker => 'ملصقات متحركة',
    StudioTool.removeBg => 'حذف الخلفية',
    StudioTool.face => 'فيسات وأفاتار',
    StudioTool.photoEdit => 'تعديل صورتك',
    StudioTool.video => 'فيديو',
    StudioTool.voice => 'إنشاء صوت',
    StudioTool.slides => 'عرض شرائح',
    StudioTool.website => 'موقع إلكتروني',
    StudioTool.game => 'تصميم لعبة',
  };

  String get subtitle => switch (this) {
    StudioTool.image => 'أي فكرة تتحول لصورة بأساليب متعددة',
    StudioTool.sticker => 'ملصقات بخلفية شفافة للواتساب وتيليجرام',
    StudioTool.animatedSticker => 'ملصق GIF يتحرك بحركات ممتعة',
    StudioTool.removeBg => 'قص العنصر من صورتك بخلفية شفافة',
    StudioTool.face => 'وجوه، إيموجي، شخصيات وأفاتار',
    StudioTool.photoEdit => 'غيّر خلفيتك أو أسلوب صورتك',
    StudioTool.video => 'فيديو من وصف، أو حرّك صورة مجاناً',
    StudioTool.voice => 'حوّل النص لصوت طبيعي بأساليب متعددة',
    StudioTool.slides => 'عرض تقديمي جاهز من فكرة واحدة',
    StudioTool.website => 'موقع كامل بتصميم احترافي',
    StudioTool.game => 'لعبة تلعبها على جوالك فوراً',
  };

  String get emoji => switch (this) {
    StudioTool.image => '🎨',
    StudioTool.sticker => '🦄',
    StudioTool.animatedSticker => '💃',
    StudioTool.removeBg => '✂️',
    StudioTool.face => '😎',
    StudioTool.photoEdit => '🪄',
    StudioTool.video => '🎬',
    StudioTool.voice => '🎙️',
    StudioTool.slides => '📊',
    StudioTool.website => '🌐',
    StudioTool.game => '🎮',
  };

  Gradient get gradient => switch (this) {
    StudioTool.image => MindColors.brand,
    StudioTool.sticker => MindColors.sunset,
    StudioTool.animatedSticker => const LinearGradient(colors: [MindColors.pink, MindColors.violet]),
    StudioTool.removeBg => const LinearGradient(colors: [MindColors.cyan, MindColors.mint]),
    StudioTool.face => MindColors.cool,
    StudioTool.photoEdit => const LinearGradient(colors: [MindColors.orange, Color(0xFFFFD166)]),
    StudioTool.video => MindColors.fresh,
    StudioTool.voice => const LinearGradient(colors: [MindColors.orange, MindColors.pink]),
    StudioTool.slides => const LinearGradient(colors: [MindColors.violet, MindColors.cyan]),
    StudioTool.website => MindColors.cool,
    StudioTool.game => const LinearGradient(colors: [MindColors.mint, MindColors.violet]),
  };

  /// Slides, websites and games are built by the code agent.
  BuildKind? get buildKind => switch (this) {
    StudioTool.slides => BuildKind.slides,
    StudioTool.website => BuildKind.website,
    StudioTool.game => BuildKind.game,
    _ => null,
  };
}

class StudioScreen extends StatelessWidget {
  const StudioScreen({super.key});

  static void open(BuildContext context, StudioTool tool) {
    final kind = tool.buildKind;
    if (kind != null) {
      ProjectsScreen.newProject(context, kind: kind);
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => switch (tool) {
          StudioTool.video => const VideoPage(),
          StudioTool.voice => const VoicePage(),
          _ => GeneratorPage(tool: tool),
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const GradientText('استوديو الإبداع', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
      ),
      body: GridView.count(
        padding: const EdgeInsets.all(16),
        crossAxisCount: 2,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 0.95,
        children: [
          for (final t in StudioTool.values)
            ToolTile(
              title: t.title,
              subtitle: t.subtitle,
              emoji: t.emoji,
              gradient: t.gradient,
              badge: t.buildKind != null || t == StudioTool.voice
                  ? 'جديد'
                  : (t == StudioTool.animatedSticker || t == StudioTool.removeBg ? 'مجاني' : null),
              onTap: () => open(context, t),
            ),
        ],
      ),
    );
  }
}
