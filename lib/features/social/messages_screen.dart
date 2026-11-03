import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/theme.dart';
import '../../services/social/social_service.dart';
import '../../services/social/text_utils.dart';
import 'posts_view.dart';
import 'search_screen.dart';
import 'widgets.dart';

void openChat(BuildContext context, String uid) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => ChatScreen(userId: uid)));

/// One inbox for the whole account, whatever section a conversation started from.
class InboxScreen extends StatelessWidget {
  const InboxScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final social = context.watch<SocialService>();
    final chats = social.chats;
    return Scaffold(
      appBar: AppBar(
        title: Text('@${social.me?.handle ?? ''}', textDirection: TextDirection.ltr),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_square),
            tooltip: 'رسالة جديدة',
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SearchScreen())),
          ),
        ],
      ),
      body: chats.isEmpty
          ? const EmptyState('✉️', 'لا توجد رسائل بعد\nافتح ملف أي شخص واضغط «مراسلة»، أو ابحث عنه بالـ ID')
          : ListView.builder(
              itemCount: chats.length,
              itemBuilder: (_, i) {
                final c = chats[i];
                final other = social.user(c.other(social.meId));
                final last = c.messages.last;
                final unread = c.unread(social.meId);
                final preview = last.postId != null ? '📎 شارك منشوراً' : last.text;
                return ListTile(
                  onTap: () => openChat(context, c.other(social.meId)),
                  leading: SocialAvatar(other, size: 50),
                  title: NameLine(other, showHandle: false),
                  subtitle: Text(
                    '${last.fromId == social.meId ? 'أنت: ' : ''}$preview · ${SocialText.ago(last.createdAt)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontWeight: unread > 0 ? FontWeight.w800 : null),
                  ),
                  trailing: unread > 0
                      ? CircleAvatar(
                          radius: 11,
                          backgroundColor: MindColors.pink,
                          child: Text('$unread', style: const TextStyle(color: Colors.white, fontSize: 11)),
                        )
                      : null,
                );
              },
            ),
    );
  }
}

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key, required this.userId});
  final String userId;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _text = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => context.read<SocialService>().markChatRead(widget.userId));
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final t = _text.text;
    if (t.trim().isEmpty) return;
    _text.clear();
    try {
      await context.read<SocialService>().sendMessage(widget.userId, text: t);
    } catch (e) {
      if (mounted) toast(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final social = context.watch<SocialService>();
    final other = social.user(widget.userId);
    final msgs = social.chatWith(widget.userId).messages.reversed.toList();
    return Scaffold(
      appBar: AppBar(
        centerTitle: false,
        title: InkWell(
          onTap: () => openProfile(context, widget.userId),
          child: Row(
            children: [
              SocialAvatar(other, size: 34),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    NameLine(other, showHandle: false),
                    Text(other?.id ?? '', textDirection: TextDirection.ltr, style: const TextStyle(fontSize: 11, color: MindColors.muted)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: msgs.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SocialAvatar(other, size: 80),
                        const SizedBox(height: 8),
                        Text(other?.name ?? '', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
                        Text('@${other?.handle ?? ''}', style: const TextStyle(color: MindColors.muted)),
                        const SizedBox(height: 8),
                        if (other != null) IdChip(other.id),
                      ],
                    ),
                  )
                : ListView.builder(
                    reverse: true,
                    padding: const EdgeInsets.all(12),
                    itemCount: msgs.length,
                    itemBuilder: (_, i) {
                      final m = msgs[i];
                      final mine = m.fromId == social.meId;
                      final shared = m.postId == null ? null : social.post(m.postId!);
                      return Align(
                        alignment: mine ? AlignmentDirectional.centerEnd : AlignmentDirectional.centerStart,
                        child: Container(
                          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
                          margin: const EdgeInsets.symmetric(vertical: 3),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            gradient: mine ? MindColors.brand : null,
                            color: mine ? null : Theme.of(context).cardTheme.color,
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (m.postId != null)
                                shared == null
                                    ? const Text('منشور لم يعد متاحاً', style: TextStyle(fontStyle: FontStyle.italic))
                                    : SizedBox(width: 240, child: QuotedPost(id: shared.id)),
                              if (m.text.isNotEmpty) Text(m.text, style: TextStyle(color: mine ? Colors.white : null)),
                              Text(
                                SocialText.ago(m.createdAt),
                                style: TextStyle(fontSize: 10, color: mine ? Colors.white70 : MindColors.muted),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 4, 10, 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _text,
                      minLines: 1,
                      maxLines: 4,
                      maxLength: 1000,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      decoration: const InputDecoration(hintText: 'اكتب رسالة…', counterText: '', isDense: true),
                    ),
                  ),
                  IconButton(icon: const Icon(Icons.send_rounded, color: MindColors.violet), onPressed: _send),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
