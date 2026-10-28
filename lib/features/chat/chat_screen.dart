import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:provider/provider.dart';

import '../../app/theme.dart';
import '../../providers/ai_models.dart';
import '../../services/chat_service.dart';
import '../../services/library_service.dart';
import 'chat_input.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key, required this.conversation});
  final Conversation conversation;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _scroll = ScrollController();

  void _toBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final chat = context.watch<ChatService>();
    final c = widget.conversation;
    final persona = Persona.byId(c.personaId);
    _toBottom();

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(persona.emoji, style: const TextStyle(fontSize: 22)),
            const SizedBox(width: 8),
            Text(persona.name),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: c.messages.isEmpty
                ? _Welcome(persona: persona)
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.all(12),
                    itemCount: c.messages.length,
                    itemBuilder: (_, i) => _Bubble(message: c.messages[i]),
                  ),
          ),
          ChatInput(
            busy: chat.busy,
            onSend: (text, image) => chat.send(c, text, image: image),
          ),
        ],
      ),
    );
  }
}

class _Welcome extends StatelessWidget {
  const _Welcome({required this.persona});
  final Persona persona;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(persona.emoji, style: const TextStyle(fontSize: 64)),
        const SizedBox(height: 8),
        Text(persona.name, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
        Text(persona.tagline, style: const TextStyle(color: MindColors.muted)),
        const SizedBox(height: 12),
        const Text(
          '💡 اكتب "ارسم" قبل وصفك لإنشاء صورة مباشرة',
          style: TextStyle(fontSize: 13, color: MindColors.muted),
        ),
      ],
    ),
  );
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message});
  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final me = message.role == Role.user;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final bubble = Container(
      constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.82),
      margin: const EdgeInsets.symmetric(vertical: 5),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        gradient: me ? MindColors.brand : null,
        color: me ? null : Theme.of(context).cardTheme.color,
        borderRadius: BorderRadiusDirectional.only(
          topStart: const Radius.circular(20),
          topEnd: const Radius.circular(20),
          bottomStart: Radius.circular(me ? 20 : 6),
          bottomEnd: Radius.circular(me ? 6 : 20),
        ).resolve(Directionality.of(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (message.imageBytes != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Image.memory(message.imageBytes!, height: 180, fit: BoxFit.cover),
              ),
            ),
          if (message.imageUrl != null && File(message.imageUrl!).existsSync())
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: GestureDetector(
                onTap: () => LibraryService.share(message.imageUrl!),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: Image.file(File(message.imageUrl!), fit: BoxFit.cover),
                ),
              ),
            ),
          if (me)
            Text(message.text, style: const TextStyle(color: Colors.white, fontSize: 15))
          else if (message.text.isEmpty)
            const _Typing()
          else
            MarkdownBody(
              data: message.text,
              selectable: true,
              styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
                // Intrinsic widths make wide tables scroll sideways instead of
                // squeezing every column into one letter per line.
                tableColumnWidth: const IntrinsicColumnWidth(),
                tableCellsPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                tableBorder: TableBorder.all(color: MindColors.violet.withValues(alpha: 0.25)),
                code: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 13,
                  backgroundColor: dark ? Colors.black26 : const Color(0xFFF1EEFF),
                ),
                codeblockDecoration: BoxDecoration(
                  color: dark ? Colors.black38 : const Color(0xFFF1EEFF),
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
        ],
      ),
    );

    return Align(
      alignment: me ? AlignmentDirectional.centerEnd : AlignmentDirectional.centerStart,
      child: GestureDetector(
        onLongPress: () {
          Clipboard.setData(ClipboardData(text: message.text));
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم النسخ')));
        },
        child: bubble,
      ),
    );
  }
}

class _Typing extends StatefulWidget {
  const _Typing();

  @override
  State<_Typing> createState() => _TypingState();
}

class _TypingState extends State<_Typing> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _c,
    builder: (_, _) => Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(3, (i) {
        final t = ((_c.value * 3) - i).clamp(0.0, 1.0);
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 3),
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Color.lerp(MindColors.violet, MindColors.pink, t)!.withValues(alpha: 0.4 + 0.6 * t),
          ),
        );
      }),
    ),
  );
}
