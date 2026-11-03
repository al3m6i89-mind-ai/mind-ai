import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/theme.dart';
import '../../services/social/social_id.dart';
import '../../services/social/social_service.dart';
import 'photos_view.dart';
import 'posts_view.dart';
import 'reels_view.dart';
import 'widgets.dart';

/// One search for all three sections: by unified ID, @handle, name, #hashtag or words.
/// With no query it shows trends and an explore grid.
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key, this.initial = ''});
  final String initial;

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  late final _q = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  void _set(String v) {
    _q.text = v;
    _q.selection = TextSelection.collapsed(offset: v.length);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final social = context.watch<SocialService>();
    final q = _q.text.trim();
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: TextField(
          controller: _q,
          autofocus: widget.initial.isEmpty,
          onChanged: (_) => setState(() {}),
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: 'ابحث بالـ ID أو @المعرّف أو #هاشتاق',
            prefixIcon: const Icon(Icons.search),
            isDense: true,
            suffixIcon: q.isEmpty ? null : IconButton(icon: const Icon(Icons.close), onPressed: () => _set('')),
          ),
        ),
        actions: const [SizedBox(width: 12)],
      ),
      body: q.isEmpty ? _Explore(onTag: (t) => _set('#$t')) : _Results(query: q, social: social),
    );
  }
}

class _Explore extends StatelessWidget {
  const _Explore({required this.onTag});
  final void Function(String) onTag;

  @override
  Widget build(BuildContext context) {
    final social = context.watch<SocialService>();
    final trends = social.trends();
    final people = social.suggestions(max: 8);
    final grid = [...social.feed(PostKind.photo), ...social.feed(PostKind.reel)]
      ..sort((a, b) => b.likes.length.compareTo(a.likes.length));
    return ListView(
      children: [
        if (trends.isNotEmpty) ...[
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text('🔥 الأكثر تداولاً', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17)),
          ),
          for (var i = 0; i < trends.length; i++)
            ListTile(
              dense: true,
              onTap: () => onTag(trends[i].$1),
              leading: Text('${i + 1}', style: const TextStyle(color: MindColors.muted, fontWeight: FontWeight.w800)),
              title: Text('#${trends[i].$1}', style: const TextStyle(fontWeight: FontWeight.w800)),
              subtitle: Text('${trends[i].$2} منشور هذا الأسبوع'),
            ),
        ],
        if (people.isNotEmpty) ...[
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Text('حسابات مقترحة', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17)),
          ),
          SizedBox(
            height: 190,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: people.length,
              itemBuilder: (_, i) {
                final u = people[i];
                return Card(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(22),
                    onTap: () => openProfile(context, u.id),
                    child: SizedBox(
                      width: 140,
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Column(
                          children: [
                            SocialAvatar(u, size: 60),
                            const SizedBox(height: 6),
                            NameLine(u, showHandle: false),
                            Text('@${u.handle}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: MindColors.muted, fontSize: 12)),
                            const Spacer(),
                            FollowButton(u.id, compact: true),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text('استكشف', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17)),
        ),
        PostGrid(posts: grid, shrinkWrap: true, onOpen: (i) => openAnyPost(context, grid[i])),
      ],
    );
  }
}

class _Results extends StatelessWidget {
  const _Results({required this.query, required this.social});
  final String query;
  final SocialService social;

  @override
  Widget build(BuildContext context) {
    final r = social.search(query);
    final reels = r.posts[PostKind.reel] ?? const [];
    final photos = r.posts[PostKind.photo] ?? const [];
    final posts = r.posts[PostKind.post] ?? const [];
    final idTyped = SocialId.looksLikeId(query);
    return DefaultTabController(
      length: 4,
      child: Column(
        children: [
          if (r.exactId != null)
            Card(
              margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              child: Column(
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 10),
                    child: Text('✅ تطابق الـ ID', style: TextStyle(fontWeight: FontWeight.w800, color: Colors.green)),
                  ),
                  UserTile(r.exactId!),
                ],
              ),
            )
          else if (idTyped)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: Text(
                'لا يوجد حساب بهذا الـ ID. تأكد من كتابته كاملاً بالشكل MA-XXXX-XXXX-X (رمز التحقق الأخير يكشف أي خطأ في الكتابة).',
                style: TextStyle(color: MindColors.muted),
              ),
            ),
          TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              Tab(text: 'حسابات (${r.users.length})'),
              Tab(text: 'ريلز (${reels.length})'),
              Tab(text: 'صور (${photos.length})'),
              Tab(text: 'منشورات (${posts.length})'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                r.users.isEmpty
                    ? const EmptyState('🔎', 'لا توجد حسابات')
                    : ListView(children: [for (final u in r.users) UserTile(u)]),
                reels.isEmpty
                    ? const EmptyState('🎬', 'لا توجد ريلز')
                    : PostGrid(posts: reels, tall: true, onOpen: (i) => openReels(context, reels, i)),
                photos.isEmpty
                    ? const EmptyState('📸', 'لا توجد صور')
                    : PostGrid(
                        posts: photos,
                        onOpen: (i) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => PhotoPostScreen(posts: photos, index: i))),
                      ),
                posts.isEmpty
                    ? const EmptyState('💬', 'لا توجد منشورات')
                    : ListView.separated(
                        itemCount: posts.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (_, i) => PostCard(post: posts[i]),
                      ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
