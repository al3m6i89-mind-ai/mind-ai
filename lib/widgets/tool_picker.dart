import 'package:flutter/material.dart';

import '../app/theme.dart';
import '../features/settings/settings_screen.dart';

/// One choice in a [ToolPicker].
class ToolChoice {
  const ToolChoice({
    required this.id,
    required this.label,
    required this.emoji,
    required this.points,
    required this.available,
    this.note = '',
    this.needs = '',
  });
  final String id;
  final String label;
  final String emoji;
  final int points;
  final bool available;
  final String note;
  final String needs;
}

/// A horizontal row of AI tools with their price in points. Locked tools say
/// which key unlocks them and open the settings.
class ToolPicker extends StatelessWidget {
  const ToolPicker({super.key, required this.choices, required this.selected, required this.onSelected});
  final List<ToolChoice> choices;
  final String selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final card = Theme.of(context).cardTheme.color ?? Theme.of(context).colorScheme.surface;
    return SizedBox(
      height: 96,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: choices.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final c = choices[i];
          final on = c.id == selected;
          return InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () {
              if (c.available) return onSelected(c.id);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('أداة ${c.label} تحتاج ${c.needs}. أضفه من الإعدادات.'),
                  action: SnackBarAction(
                    label: 'الإعدادات',
                    onPressed: () =>
                        Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsScreen())),
                  ),
                ),
              );
            },
            child: Opacity(
              opacity: c.available ? 1 : 0.55,
              child: Container(
                width: 132,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: card,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: on ? MindColors.violet : MindColors.violet.withValues(alpha: 0.15),
                    width: on ? 2 : 1,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(c.emoji, style: const TextStyle(fontSize: 18)),
                        const Spacer(),
                        if (!c.available) const Icon(Icons.lock_outline, size: 15, color: MindColors.muted),
                        Text(
                          ' 💎${c.points}',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: MindColors.violet),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      c.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    Text(
                      c.available ? c.note : 'يحتاج ${c.needs}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11, color: MindColors.muted, height: 1.3),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
