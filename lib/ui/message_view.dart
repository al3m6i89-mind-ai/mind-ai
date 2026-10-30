import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/models.dart';
import '../core/strings.dart';
import 'attachment_card.dart';
import 'theme.dart';

class MessageView extends StatelessWidget {
  const MessageView({
    super.key,
    required this.message,
    required this.s,
    required this.isLast,
    required this.onRetry,
    required this.onDeleteFile,
  });

  final Message message;
  final S s;
  final bool isLast;
  final VoidCallback onRetry;
  final void Function(Attachment) onDeleteFile;

  @override
  Widget build(BuildContext context) {
    final m = message;
    final user = m.role == Role.user;
    final files = [
      for (final a in m.attachments)
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: AttachmentCard(attachment: a, s: s, onRemove: () => onDeleteFile(a)),
        ),
    ];

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      builder: (context, v, child) => Opacity(
        opacity: v,
        child: Transform.translate(offset: Offset(0, (1 - v) * 10), child: child),
      ),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 20),
        child: user ? _user(context, files) : _assistant(context),
      ),
    );
  }

  Widget _user(BuildContext context, List<Widget> files) {
    return Align(
      alignment: AlignmentDirectional.centerEnd,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.85),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            ...files,
            if (message.text.isNotEmpty)
              GestureDetector(
                onLongPress: () => _copy(context),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
                  decoration: BoxDecoration(
                    color: context.userBubble,
                    borderRadius: const BorderRadiusDirectional.only(
                      topStart: Radius.circular(20),
                      topEnd: Radius.circular(20),
                      bottomStart: Radius.circular(20),
                      bottomEnd: Radius.circular(6),
                    ),
                  ),
                  child: SelectableText(message.text,
                      style: TextStyle(fontSize: 15.5, height: 1.55, color: context.onUserBubble)),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _assistant(BuildContext context) {
    final m = message;
    final theme = Theme.of(context);
    final waiting = m.status == MsgStatus.streaming && m.text.isEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.asset('assets/logo.png', width: 26, height: 26),
          ),
          const SizedBox(width: 8),
          Text(s.t('assistant'), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
        ]),
        const SizedBox(height: 6),
        if (waiting)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(children: [
              const _TypingDots(),
              if (m.note != null) ...[
                const SizedBox(width: 10),
                Flexible(child: Text(_note(m.note!), style: TextStyle(color: context.muted, fontSize: 13))),
              ],
            ]),
          )
        else if (m.text.isNotEmpty)
          MarkdownBody(
            data: m.status == MsgStatus.streaming ? '${m.text} ▍' : m.text,
            selectable: true,
            onTapLink: (_, href, _) {
              final uri = href == null ? null : Uri.tryParse(href);
              if (uri != null && (uri.scheme == 'https' || uri.scheme == 'http')) {
                launchUrl(uri, mode: LaunchMode.externalApplication);
              }
            },
            styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
              p: theme.textTheme.bodyLarge?.copyWith(height: 1.6, fontSize: 15.5),
              code: TextStyle(fontFamily: 'monospace', backgroundColor: context.surface2, fontSize: 13.5),
              codeblockDecoration: BoxDecoration(color: context.surface2, borderRadius: BorderRadius.circular(10)),
              blockquoteDecoration: BoxDecoration(
                border: BorderDirectional(start: BorderSide(color: theme.colorScheme.primary, width: 3)),
              ),
            ),
          ),
        if (m.status == MsgStatus.stopped)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(s.t('stopped'), style: TextStyle(color: context.muted, fontSize: 13)),
          ),
        if (m.status == MsgStatus.error)
          Container(
            margin: const EdgeInsets.only(top: 6),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: context.danger.withValues(alpha: 0.5)),
            ),
            child: Row(children: [
              Icon(Icons.error_outline, color: context.danger, size: 20),
              const SizedBox(width: 8),
              Expanded(child: Text(s.error(m.error), style: TextStyle(color: context.danger))),
            ]),
          ),
        if (m.status != MsgStatus.streaming)
          Row(children: [
            if (m.via != null && m.status == MsgStatus.complete)
              Padding(
                padding: const EdgeInsetsDirectional.only(end: 4),
                child: Text(s.t('via', {'name': m.via!}), style: TextStyle(color: context.muted, fontSize: 12)),
              ),
            if (m.trace.isNotEmpty)
              IconButton(
                tooltip: s.t('details'),
                visualDensity: VisualDensity.compact,
                icon: Icon(Icons.info_outline_rounded, size: 18, color: context.muted),
                onPressed: () => _showTrace(context),
              ),
            if (m.text.isNotEmpty)
              IconButton(
                tooltip: s.t('copy'),
                visualDensity: VisualDensity.compact,
                icon: Icon(Icons.copy_rounded, size: 18, color: context.muted),
                onPressed: () => _copy(context),
              ),
            if (isLast)
              IconButton(
                tooltip: s.t('retry'),
                visualDensity: VisualDensity.compact,
                icon: Icon(Icons.refresh_rounded, size: 20, color: context.muted),
                onPressed: onRetry,
              ),
          ]),
      ],
    );
  }

  void _showTrace(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(s.t('details'), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              const SizedBox(height: 6),
              Text(s.t('traceHint'), style: TextStyle(color: ctx.muted, fontSize: 13)),
              const SizedBox(height: 12),
              Flexible(
                child: SingleChildScrollView(
                  child: SelectableText(message.trace.join('\n'),
                      textDirection: TextDirection.ltr, style: const TextStyle(fontSize: 12.5, height: 1.6)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _note(String note) {
    if (note.startsWith('switching:')) return s.t('switching', {'name': note.substring(10)});
    return s.t('waitingRetry');
  }

  void _copy(BuildContext context) {
    Clipboard.setData(ClipboardData(text: message.text));
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(s.t('copied')), behavior: SnackBarBehavior.floating));
  }
}

class _TypingDots extends StatefulWidget {
  const _TypingDots();

  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = context.muted;
    return AnimatedBuilder(
      animation: _c,
      builder: (_, _) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < 3; i++)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 3),
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color.withValues(alpha: 0.3 + 0.7 * _wave((_c.value - i * 0.18) % 1)),
              ),
            ),
        ],
      ),
    );
  }

  double _wave(double t) => t < 0.5 ? t * 2 : (1 - t) * 2;
}
