import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/theme.dart';
import '../../services/social/social_service.dart';
import '../../services/social/text_utils.dart';
import 'messages_screen.dart';
import 'posts_view.dart';
import 'widgets.dart';

/// One notification list for all three sections, filterable by section.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  PostKind? _filter;
  bool _mentionsOnly = false;

  late final SocialService _social;

  @override
  void initState() {
    super.initState();
    _social = context.read<SocialService>();
  }

  @override
  void dispose() {
    // Leaving the screen marks everything as read.
    final social = _social;
    WidgetsBinding.instance.addPostFrameCallback((_) => social.markNoticesRead());
    super.dispose();
  }

  static String _what(Notice n, SocialPost? p) {
    final k = p?.kind.single ?? '';
    return switch (n.type) {
      NoticeType.like => 'أعجبه $k الخاص بك',
      NoticeType.comment => 'علّق: ${n.text}',
      NoticeType.reply => 'ردّ عليك: ${n.text}',
      NoticeType.follow => 'بدأ بمتابعتك',
      NoticeType.repost => 'أعاد نشر $k الخاص بك',
      NoticeType.quote => 'اقتبس منشورك: ${n.text}',
      NoticeType.mention => 'أشار إليك: ${n.text}',
      NoticeType.save => 'حفظ $k الخاص بك',
      NoticeType.storyLike => 'أعجبته قصتك',
      NoticeType.message => 'أرسل لك رسالة: ${n.text}',
    };
  }

  static (IconData, Color) _icon(NoticeType t) => switch (t) {
    NoticeType.like || NoticeType.storyLike => (Icons.favorite, const Color(0xFFF91880)),
    NoticeType.comment || NoticeType.reply => (Icons.chat_bubble, MindColors.violet),
    NoticeType.follow => (Icons.person_add_alt_1, const Color(0xFF1D9BF0)),
    NoticeType.repost || NoticeType.quote => (Icons.repeat_rounded, const Color(0xFF00BA7C)),
    NoticeType.mention => (Icons.alternate_email, MindColors.orange),
    NoticeType.save => (Icons.bookmark, const Color(0xFFFACE15)),
    NoticeType.message => (Icons.mail, MindColors.pink),
  };

  @override
  Widget build(BuildContext context) {
    final social = context.watch<SocialService>();
    var list = social.notices;
    if (_mentionsOnly) {
      list = list.where((n) => n.type == NoticeType.mention || n.type == NoticeType.reply).toList();
    }
    if (_filter != null) list = list.where((n) => n.postId != null && social.post(n.postId!)?.kind == _filter).toList();

    Widget chip(String label, bool on, VoidCallback tap) => Padding(
      padding: const EdgeInsetsDirectional.only(end: 6),
      child: ChoiceChip(label: Text(label), selected: on, onSelected: (_) => tap()),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('الإشعارات')),
      body: Column(
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Row(
              children: [
                chip('الكل', _filter == null && !_mentionsOnly, () => setState(() {
                  _filter = null;
                  _mentionsOnly = false;
                })),
                chip('الإشارات والردود', _mentionsOnly, () => setState(() => _mentionsOnly = !_mentionsOnly)),
                for (final k in PostKind.values)
                  chip('${k.emoji} ${k.label}', _filter == k, () => setState(() => _filter = _filter == k ? null : k)),
              ],
            ),
          ),
          Expanded(
            child: list.isEmpty
                ? const EmptyState('🔔', 'لا توجد إشعارات بعد\nعندما يتفاعل أحد مع ريلزك أو صورك أو منشوراتك ستظهر هنا')
                : ListView.builder(
                    itemCount: list.length,
                    itemBuilder: (_, i) {
                      final n = list[i];
                      final from = social.user(n.fromId);
                      final p = n.postId == null ? null : social.post(n.postId!);
                      final (icon, color) = _icon(n.type);
                      final thumb = p == null || p.media.isEmpty ? null : (p.media.first.video ? p.media.first.thumb : p.media.first.src);
                      return Container(
                        color: n.read ? null : MindColors.violet.withValues(alpha: 0.06),
                        child: ListTile(
                          onTap: () {
                            if (n.type == NoticeType.message) {
                              openChat(context, n.fromId);
                            } else if (p != null) {
                              openAnyPost(context, p);
                            } else {
                              openProfile(context, n.fromId);
                            }
                          },
                          leading: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              SocialAvatar(from, size: 44, onTap: () => openProfile(context, n.fromId)),
                              PositionedDirectional(
                                end: -4,
                                bottom: -4,
                                child: CircleAvatar(radius: 10, backgroundColor: color, child: Icon(icon, size: 12, color: Colors.white)),
                              ),
                            ],
                          ),
                          title: Text.rich(
                            TextSpan(
                              children: [
                                TextSpan(text: from?.handle ?? 'حساب', style: const TextStyle(fontWeight: FontWeight.w800)),
                                TextSpan(text: ' ${_what(n, p)}'),
                              ],
                            ),
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            '${p != null ? '${p.kind.emoji} ' : ''}${SocialText.ago(n.createdAt)}',
                            style: const TextStyle(fontSize: 12),
                          ),
                          trailing: n.type == NoticeType.follow
                              ? FollowButton(n.fromId, compact: true)
                              : (thumb != null && thumb.isNotEmpty)
                              ? ClipRRect(borderRadius: BorderRadius.circular(6), child: MediaImage(thumb, width: 44, height: 44))
                              : null,
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
