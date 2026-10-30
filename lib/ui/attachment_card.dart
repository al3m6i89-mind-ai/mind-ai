import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:provider/provider.dart';

import '../core/models.dart';
import '../core/store.dart';
import '../core/strings.dart';
import 'theme.dart';

String formatSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

IconData iconFor(Attachment a) => switch (a.ext) {
      'pdf' => Icons.picture_as_pdf_outlined,
      'docx' => Icons.description_outlined,
      'pptx' => Icons.slideshow_outlined,
      'xlsx' || 'csv' => Icons.table_chart_outlined,
      _ when a.isImage => Icons.image_outlined,
      _ => Icons.article_outlined,
    };

/// One attached file: icon, name, size and whether the assistant can read it.
/// Tapping opens the original in another app.
class AttachmentCard extends StatelessWidget {
  const AttachmentCard({super.key, required this.attachment, required this.s, this.onRemove, this.compact = false});

  final Attachment attachment;
  final S s;
  final VoidCallback? onRemove;
  final bool compact;

  (String, Color) _status(BuildContext context) {
    final a = attachment;
    final store = context.watch<AppStore>();
    final noVisionKey = store.geminiKey.isEmpty && store.mistralKey.isEmpty;
    // A scanned PDF has no text layer: only Gemini can read it.
    if (a.isPdf && (a.extractedText ?? '').isEmpty && store.geminiKey.isEmpty) return (s.t('needsKey'), context.warn);
    if (a.isImage && noVisionKey) return (s.t('readyFree'), context.warn);
    if (a.note == 'truncated') return (s.t('truncated'), context.warn);
    if (!a.readable) return (s.t('notReadable'), context.danger);
    return (a.sentAsBinary ? s.t('ready') : s.t('readyText'), Theme.of(context).colorScheme.primary);
  }

  Future<void> _open(BuildContext context) async {
    final res = await OpenFilex.open(attachment.path);
    if (res.type != ResultType.done && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(res.message),
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final a = attachment;
    final (label, color) = _status(context);
    return Material(
      color: context.surface2,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _open(context),
        child: Container(
          width: compact ? 220 : null,
          padding: const EdgeInsetsDirectional.fromSTEB(10, 8, 4, 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: context.border),
          ),
          child: Row(
            mainAxisSize: compact ? MainAxisSize.max : MainAxisSize.min,
            children: [
              Icon(iconFor(a), color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 10),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(a.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(
                      '${a.typeLabel} · ${formatSize(a.size)} · $label',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: color),
                    ),
                  ],
                ),
              ),
              if (onRemove != null)
                IconButton(
                  tooltip: s.t('delete'),
                  visualDensity: VisualDensity.compact,
                  icon: Icon(Icons.close, size: 18, color: context.muted),
                  onPressed: onRemove,
                )
              else
                const SizedBox(width: 6),
            ],
          ),
        ),
      ),
    );
  }
}
