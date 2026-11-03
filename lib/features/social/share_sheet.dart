import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../services/social/social_service.dart';
import 'widgets.dart';

String postLink(SocialPost p) => 'https://mindai.app/${p.kind.name}/${p.id}';

/// Send to people (same inbox for all three sections), copy the link, or share outside.
Future<void> sharePost(BuildContext context, SocialPost post) {
  return showModalBottomSheet(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => _ShareSheet(post: post),
  );
}

class _ShareSheet extends StatefulWidget {
  const _ShareSheet({required this.post});
  final SocialPost post;

  @override
  State<_ShareSheet> createState() => _ShareSheetState();
}

class _ShareSheetState extends State<_ShareSheet> {
  final _sent = <String>{};

  @override
  Widget build(BuildContext context) {
    final social = context.watch<SocialService>();
    final me = social.me;
    final people = <SocialUser>[
      ...social.chats.map((c) => social.user(c.other(social.meId))).whereType<SocialUser>(),
      ...?me?.following.map(social.user).whereType<SocialUser>(),
    ];
    final seen = <String>{};
    people.retainWhere((u) => u.id != social.meId && seen.add(u.id));
    final author = social.user(widget.post.authorId);
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('مشاركة', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          const SizedBox(height: 12),
          if (people.isNotEmpty)
            SizedBox(
              height: 98,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: people.length,
                itemBuilder: (_, i) {
                  final u = people[i];
                  final sent = _sent.contains(u.id);
                  return GestureDetector(
                    onTap: sent
                        ? null
                        : () async {
                            await social.sendMessage(u.id, postId: widget.post.id);
                            await social.markShared(widget.post);
                            setState(() => _sent.add(u.id));
                          },
                    child: SizedBox(
                      width: 76,
                      child: Column(
                        children: [
                          Stack(
                            children: [
                              SocialAvatar(u, size: 54),
                              if (sent)
                                const PositionedDirectional(
                                  end: 0,
                                  bottom: 0,
                                  child: CircleAvatar(radius: 10, backgroundColor: Colors.green, child: Icon(Icons.check, size: 14, color: Colors.white)),
                                ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            sent ? 'أُرسلت' : u.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.link_rounded),
            title: const Text('نسخ الرابط'),
            onTap: () {
              copyText(context, postLink(widget.post), done: 'تم نسخ الرابط');
              social.markShared(widget.post);
              Navigator.pop(context);
            },
          ),
          ListTile(
            leading: const Icon(Icons.ios_share_rounded),
            title: const Text('مشاركة خارج التطبيق'),
            onTap: () {
              Navigator.pop(context);
              social.markShared(widget.post);
              final who = author == null ? '' : '@${author.handle} (${author.id})\n';
              Share.share('$who${widget.post.text}\n${postLink(widget.post)}'.trim());
            },
          ),
        ],
      ),
    );
  }
}
