import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/theme.dart';
import '../../services/library_service.dart';
import '../../widgets/common.dart';

class CreationsScreen extends StatefulWidget {
  const CreationsScreen({super.key});

  @override
  State<CreationsScreen> createState() => _CreationsScreenState();
}

class _CreationsScreenState extends State<CreationsScreen> {
  CreationKind? _filter;

  @override
  Widget build(BuildContext context) {
    final lib = context.watch<LibraryService>();
    final items = _filter == null ? lib.items : lib.items.where((c) => c.kind == _filter).toList();
    return Scaffold(
      appBar: AppBar(
        title: const GradientText('إبداعاتي', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
      ),
      body: Column(
        children: [
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: 8),
                  child: ChoiceChip(
                    label: const Text('الكل'),
                    selected: _filter == null,
                    onSelected: (_) => setState(() => _filter = null),
                  ),
                ),
                for (final k in CreationKind.values)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(end: 8),
                    child: ChoiceChip(
                      label: Text(k.label),
                      selected: _filter == k,
                      onSelected: (_) => setState(() => _filter = k),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: items.isEmpty
                ? const Center(
                    child: Text(
                      'لا توجد إبداعات بعد ✨\nابدأ من الاستوديو',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: MindColors.muted, fontSize: 16),
                    ),
                  )
                : GridView.builder(
                    padding: const EdgeInsets.all(12),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      mainAxisSpacing: 8,
                      crossAxisSpacing: 8,
                    ),
                    itemCount: items.length,
                    itemBuilder: (_, i) => _Thumb(c: items[i]),
                  ),
          ),
        ],
      ),
    );
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({required this.c});
  final Creation c;

  @override
  Widget build(BuildContext context) {
    final isVideo = c.kind == CreationKind.video && !c.path.endsWith('.gif');
    final isVoice = c.kind == CreationKind.voice;
    final noPicture = isVideo || isVoice;
    return GestureDetector(
      onTap: () => showModalBottomSheet(
        context: context,
        showDragHandle: true,
        builder: (_) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!noPicture)
                  ConstrainedBox(constraints: const BoxConstraints(maxHeight: 320), child: Image.file(File(c.path))),
                const SizedBox(height: 8),
                Text(c.prompt, textAlign: TextAlign.center),
                const SizedBox(height: 12),
                Row(
                  children: [
                    if (!isVoice)
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.download_rounded),
                          label: const Text('حفظ'),
                          onPressed: () => LibraryService.toGallery(c.path, video: isVideo),
                        ),
                      ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton.icon(
                        icon: const Icon(Icons.share_rounded),
                        label: const Text('مشاركة'),
                        onPressed: () => LibraryService.share(c.path),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                      onPressed: () {
                        context.read<LibraryService>().delete(c);
                        Navigator.pop(context);
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Container(
          color: const Color(0xFFEDEAF7),
          child: noPicture
              ? Center(
                  child: Icon(
                    isVoice ? Icons.graphic_eq_rounded : Icons.play_circle_fill,
                    size: 40,
                    color: MindColors.violet,
                  ),
                )
              : Image.file(File(c.path), fit: BoxFit.cover, cacheWidth: 300),
        ),
      ),
    );
  }
}
