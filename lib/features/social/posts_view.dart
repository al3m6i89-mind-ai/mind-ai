import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/theme.dart';
import '../../services/social/social_service.dart';
import '../../services/social/text_utils.dart';
import 'compose.dart';
import 'photos_view.dart';
import 'post_menu.dart';
import 'reels_view.dart';
import 'share_sheet.dart';
import 'widgets.dart';

/// Posts section: short text posts with replies, reposts and quotes.
class PostsView extends StatelessWidget {
  const PostsView({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          const TabBar(
            labelStyle: TextStyle(fontWeight: FontWeight.w800),
            tabs: [Tab(text: 'لك'), Tab(text: 'متابَعون')],
          ),
          const Expanded(
            child: TabBarView(children: [_Timeline(following: false), _Timeline(following: true)]),
          ),
        ],
      ),
    );
  }
}

class _Timeline extends StatefulWidget {
  const _Timeline({required this.following});
  final bool following;

  @override
  State<_Timeline> createState() => _TimelineState();
}

class _TimelineState extends State<_Timeline> with AutomaticKeepAliveClientMixin {
  List<String> _ids = [];

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _snapshot();
  }

  void _snapshot() => _ids = context.read<SocialService>().feed(PostKind.post, following: widget.following).map((p) => p.id).toList();

  bool _loading = false;

  void _more() {
    if (_loading) return;
    _loading = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final social = context.read<SocialService>();
      final fresh = await moreFeedIds(
        social,
        PostKind.post,
        () => social.feed(PostKind.post, following: widget.following),
        _ids,
      );
      if (mounted && fresh.isNotEmpty) setState(() => _ids.addAll(fresh));
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final social = context.watch<SocialService>();
    // What I just posted shows at the top without waiting for a refresh.
    final fresh = social.byAuthor(social.meId, PostKind.post).where((p) => !_ids.contains(p.id)).map((p) => p.id);
    final posts = [...fresh, ..._ids].map(social.post).whereType<SocialPost>().toList();
    return RefreshIndicator(
      onRefresh: () async => setState(_snapshot),
      child: posts.isEmpty
          ? ListView(
              children: [
                if (social.canLoadMore(kind: PostKind.post)) ...[
                  Builder(
                    builder: (_) {
                      _more();
                      return const LoadMoreFooter(kind: PostKind.post);
                    },
                  ),
                ],
                const SizedBox(height: 80),
                EmptyState(
                  '💬',
                  widget.following ? 'تابع أشخاصاً لتظهر منشوراتهم هنا' : 'لا توجد منشورات بعد',
                  action: FilledButton.icon(
                    onPressed: () => openCompose(context),
                    icon: const Icon(Icons.edit),
                    label: const Text('اكتب أول منشور'),
                  ),
                ),
              ],
            )
          : ListView.separated(
              padding: const EdgeInsets.only(bottom: 90),
              itemCount: posts.length + 1,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (_, i) {
                if (i >= posts.length - 3) _more();
                if (i == posts.length) return const LoadMoreFooter(kind: PostKind.post);
                return PostCard(post: posts[i]);
              },
            ),
    );
  }
}

/// One post. Reposts show the original with a "reposted" line; quotes embed
/// the quoted post; replies say who they answer.
class PostCard extends StatelessWidget {
  const PostCard({super.key, required this.post, this.focused = false, this.threadLine = false});
  final SocialPost post;

  /// The main post on its detail page: bigger text and full counts.
  final bool focused;

  /// Draws a line down from the avatar to the next post in a thread.
  final bool threadLine;

  @override
  Widget build(BuildContext context) {
    final social = context.watch<SocialService>();
    final reposter = post.repostOf == null ? null : social.user(post.authorId);
    final p = post.repostOf == null ? post : social.post(post.repostOf!);
    if (p == null) {
      return const Padding(padding: EdgeInsets.all(16), child: Text('هذا المنشور لم يعد متاحاً', style: TextStyle(color: MindColors.muted)));
    }
    final author = social.user(p.authorId);
    final parent = p.replyTo == null ? null : social.post(p.replyTo!);
    final parentAuthor = parent == null ? null : social.user(parent.authorId);
    final liked = social.liked(p);
    final reposted = social.reposted(p);
    final saved = social.isSaved(p);

    final actions = Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        CountAction(
          icon: Icons.chat_bubble_outline_rounded,
          count: social.commentCount(p),
          onTap: () => openCompose(context, replyTo: p),
        ),
        CountAction(
          icon: Icons.repeat_rounded,
          count: social.repostCount(p),
          color: reposted ? const Color(0xFF00BA7C) : null,
          onTap: () => _repostMenu(context, p, reposted),
        ),
        CountAction(
          icon: liked ? Icons.favorite : Icons.favorite_border,
          count: p.likes.length,
          color: liked ? const Color(0xFFF91880) : null,
          onTap: () => social.toggleLike(p),
        ),
        CountAction(icon: Icons.bar_chart_rounded, count: p.views),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CountAction(
              icon: saved ? Icons.bookmark : Icons.bookmark_border,
              color: saved ? const Color(0xFF1D9BF0) : null,
              onTap: () => social.toggleSave(p),
            ),
            CountAction(icon: Icons.ios_share_rounded, onTap: () => sharePost(context, p)),
          ],
        ),
      ],
    );

    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: NameLine(author, time: focused ? null : p.createdAt)),
            InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => showPostMenu(context, p),
              child: const Padding(padding: EdgeInsets.all(4), child: Icon(Icons.more_horiz, size: 18, color: MindColors.muted)),
            ),
          ],
        ),
        if (p.hidden) const HiddenNote(),
        if (parentAuthor != null && !focused)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text.rich(
              TextSpan(
                text: 'ردًا على ',
                children: [
                  TextSpan(text: '@${parentAuthor.handle}', style: const TextStyle(color: Color(0xFF1D9BF0))),
                ],
              ),
              style: const TextStyle(color: MindColors.muted, fontSize: 13),
            ),
          ),
        if (p.text.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: RichPostText(p.text, style: TextStyle(fontSize: focused ? 19 : 15, height: 1.45)),
          ),
        if (p.media.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: _ImageGrid(media: p.media),
          ),
        if (p.quoteOf != null) Padding(padding: const EdgeInsets.only(top: 10), child: QuotedPost(id: p.quoteOf!)),
        if (focused) ...[
          const SizedBox(height: 12),
          Text(
            '${_clock(p.createdAt)} · ${SocialText.count(p.views)} مشاهدة',
            style: const TextStyle(color: MindColors.muted),
          ),
          const Divider(height: 24),
          Wrap(
            spacing: 16,
            children: [
              _Stat(social.repostCount(p), 'إعادة نشر', () => showPeople(context, 'أعادوا النشر', social.reposters(p.id))),
              _Stat(p.likes.length, 'إعجاب', () => showPeople(context, 'الإعجابات', p.likes.toList())),
              _Stat(p.saves.length, 'حفظ', null),
            ],
          ),
          const Divider(height: 24),
        ] else
          const SizedBox(height: 4),
        actions,
      ],
    );

    return InkWell(
      onTap: focused ? null : () => openPost(context, p),
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(12, 10, 12, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (reposter != null)
              Padding(
                padding: const EdgeInsetsDirectional.only(start: 28, bottom: 4),
                child: Row(
                  children: [
                    const Icon(Icons.repeat_rounded, size: 15, color: MindColors.muted),
                    const SizedBox(width: 6),
                    Text(
                      reposter.id == social.meId ? 'أعدت النشر' : 'أعاد نشره ${reposter.name}',
                      style: const TextStyle(color: MindColors.muted, fontSize: 13, fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Column(
                    children: [
                      SocialAvatar(author, size: 42, onTap: () => openProfile(context, p.authorId)),
                      if (threadLine)
                        Expanded(
                          child: Container(width: 2, margin: const EdgeInsets.only(top: 4), color: Colors.grey.withValues(alpha: 0.4)),
                        ),
                    ],
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: body),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _clock(DateTime t) {
    final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
    final m = t.minute.toString().padLeft(2, '0');
    return '$h:$m ${t.hour < 12 ? 'ص' : 'م'} · ${t.day}/${t.month}/${t.year}';
  }

  static void _repostMenu(BuildContext context, SocialPost p, bool reposted) {
    final social = context.read<SocialService>();
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.repeat_rounded),
              title: Text(reposted ? 'التراجع عن إعادة النشر' : 'إعادة نشر'),
              onTap: () {
                Navigator.pop(ctx);
                social.toggleRepost(p);
              },
            ),
            ListTile(
              leading: const Icon(Icons.edit_note_rounded),
              title: const Text('اقتباس'),
              onTap: () {
                Navigator.pop(ctx);
                openCompose(context, quote: p);
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.n, this.label, this.onTap);
  final int n;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Text.rich(
      TextSpan(
        children: [
          TextSpan(text: SocialText.count(n), style: const TextStyle(fontWeight: FontWeight.w800)),
          TextSpan(text: ' $label', style: const TextStyle(color: MindColors.muted)),
        ],
      ),
    ),
  );
}

class _ImageGrid extends StatelessWidget {
  const _ImageGrid({required this.media});
  final List<Media> media;

  @override
  Widget build(BuildContext context) {
    Widget img(int i) => GestureDetector(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => Scaffold(
            backgroundColor: Colors.black,
            appBar: AppBar(foregroundColor: Colors.white),
            body: PageView(
              controller: PageController(initialPage: i),
              children: [for (final m in media) InteractiveViewer(child: MediaImage(m.src, fit: BoxFit.contain))],
            ),
          ),
        ),
      ),
      child: MediaImage(media[i].src),
    );
    const gap = SizedBox(width: 2, height: 2);
    final Widget grid = switch (media.length) {
      1 => AspectRatio(aspectRatio: 16 / 10, child: img(0)),
      2 => AspectRatio(
        aspectRatio: 16 / 9,
        child: Row(children: [Expanded(child: img(0)), gap, Expanded(child: img(1))]),
      ),
      3 => AspectRatio(
        aspectRatio: 16 / 9,
        child: Row(
          children: [
            Expanded(child: img(0)),
            gap,
            Expanded(child: Column(children: [Expanded(child: img(1)), gap, Expanded(child: img(2))])),
          ],
        ),
      ),
      _ => AspectRatio(
        aspectRatio: 16 / 9,
        child: Column(
          children: [
            Expanded(child: Row(children: [Expanded(child: img(0)), gap, Expanded(child: img(1))])),
            gap,
            Expanded(child: Row(children: [Expanded(child: img(2)), gap, Expanded(child: img(3))])),
          ],
        ),
      ),
    };
    return ClipRRect(borderRadius: BorderRadius.circular(16), child: grid);
  }
}

/// A quoted post inside another one. Quotes may point at any section.
class QuotedPost extends StatelessWidget {
  const QuotedPost({super.key, required this.id});
  final String id;

  @override
  Widget build(BuildContext context) {
    final social = context.watch<SocialService>();
    final q = social.post(id);
    final border = BoxDecoration(
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: Colors.grey.withValues(alpha: 0.35)),
    );
    if (q == null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: border,
        child: const Text('هذا المنشور لم يعد متاحاً', style: TextStyle(color: MindColors.muted)),
      );
    }
    final author = social.user(q.authorId);
    final thumb = q.media.isEmpty ? null : (q.media.first.video ? q.media.first.thumb : q.media.first.src);
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => openAnyPost(context, q),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(10),
        decoration: border,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      SocialAvatar(author, size: 20),
                      const SizedBox(width: 6),
                      Expanded(child: NameLine(author, time: q.createdAt)),
                    ],
                  ),
                  if (q.kind != PostKind.post)
                    Text('${q.kind.emoji} ${q.kind.single}', style: const TextStyle(color: MindColors.muted, fontSize: 12)),
                  if (q.text.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(q.text, maxLines: 4, overflow: TextOverflow.ellipsis),
                    ),
                ],
              ),
            ),
            if (thumb != null && thumb.isNotEmpty) ...[
              const SizedBox(width: 8),
              ClipRRect(borderRadius: BorderRadius.circular(10), child: MediaImage(thumb, width: 64, height: 64)),
            ],
          ],
        ),
      ),
    );
  }
}

/// Opens any post on the right screen for its section.
void openAnyPost(BuildContext context, SocialPost p) {
  switch (p.kind) {
    case PostKind.reel:
      openReels(context, [p], 0);
    case PostKind.photo:
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => PhotoPostScreen(posts: [p])));
    case PostKind.post:
      openPost(context, p);
  }
}

void openPost(BuildContext context, SocialPost p) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => PostDetailScreen(postId: p.id)));

/// A post with the conversation above it and the replies below.
class PostDetailScreen extends StatefulWidget {
  const PostDetailScreen({super.key, required this.postId});
  final String postId;

  @override
  State<PostDetailScreen> createState() => _PostDetailScreenState();
}

class _PostDetailScreenState extends State<PostDetailScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final social = context.read<SocialService>();
      final p = social.post(widget.postId);
      if (p != null) social.view(p);
    });
  }

  @override
  Widget build(BuildContext context) {
    final social = context.watch<SocialService>();
    final p = social.post(widget.postId);
    return Scaffold(
      appBar: AppBar(title: const Text('منشور')),
      body: p == null
          ? const EmptyState('🗑️', 'هذا المنشور لم يعد متاحاً')
          : ListView(
              padding: const EdgeInsets.only(bottom: 90),
              children: [
                for (final a in social.ancestors(p)) PostCard(post: a, threadLine: true),
                PostCard(post: p, focused: true),
                const Divider(height: 1),
                if (social.hasAccount)
                  ListTile(
                    leading: SocialAvatar(social.me, size: 36),
                    title: const Text('اكتب ردّك', style: TextStyle(color: MindColors.muted)),
                    onTap: () => openCompose(context, replyTo: p),
                  ),
                const Divider(height: 1),
                for (final r in social.replies(p.id)) ...[PostCard(post: r), const Divider(height: 1)],
              ],
            ),
    );
  }
}
