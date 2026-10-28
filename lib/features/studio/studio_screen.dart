import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../widgets/common.dart';
import 'generator_page.dart';
import 'video_page.dart';

enum StudioTool { image, sticker, animatedSticker, face, photoEdit, video }

extension StudioToolInfo on StudioTool {
  String get title => switch (this) {
        StudioTool.image => 'إنشاء صور',
        StudioTool.sticker => 'ملصقات',
        StudioTool.animatedSticker => 'ملصقات متحركة',
        StudioTool.face => 'فيسات وأفاتار',
        StudioTool.photoEdit => 'تعديل صورتك',
        StudioTool.video => 'فيديو',
      };

  String get subtitle => switch (this) {
        StudioTool.image => 'أي فكرة تتحول لصورة بأساليب متعددة',
        StudioTool.sticker => 'ملصقات بخلفية شفافة للواتساب وتيليجرام',
        StudioTool.animatedSticker => 'ملصق GIF يتحرك بحركات ممتعة',
        StudioTool.face => 'وجوه، إيموجي، شخصيات وأفاتار',
        StudioTool.photoEdit => 'غيّر خلفيتك أو أسلوب صورتك',
        StudioTool.video => 'فيديو من وصف، أو حرّك صورة مجاناً',
      };

  String get emoji => switch (this) {
        StudioTool.image => '🎨',
        StudioTool.sticker => '🦄',
        StudioTool.animatedSticker => '💃',
        StudioTool.face => '😎',
        StudioTool.photoEdit => '🪄',
        StudioTool.video => '🎬',
      };

  Gradient get gradient => switch (this) {
        StudioTool.image => MindColors.brand,
        StudioTool.sticker => MindColors.sunset,
        StudioTool.animatedSticker => const LinearGradient(colors: [MindColors.pink, MindColors.violet]),
        StudioTool.face => MindColors.cool,
        StudioTool.photoEdit => const LinearGradient(colors: [MindColors.orange, Color(0xFFFFD166)]),
        StudioTool.video => MindColors.fresh,
      };
}

class StudioScreen extends StatelessWidget {
  const StudioScreen({super.key});

  static void open(BuildContext context, StudioTool tool) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => tool == StudioTool.video ? const VideoPage() : GeneratorPage(tool: tool),
    ));
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
              badge: t == StudioTool.animatedSticker ? 'مجاني' : null,
              onTap: () => open(context, t),
            ),
        ],
      ),
    );
  }
}
