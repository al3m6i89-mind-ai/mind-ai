import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/theme.dart';
import '../../services/social/social_service.dart';
import '../../services/social/text_utils.dart';
import 'comments_sheet.dart';
import 'post_menu.dart';
import 'share_sheet.dart';
import 'stories.dart';
import 'widgets.dart';

/// Photos section: stories on top, then photo posts from people you follow
/// (newest first) followed by suggested posts.
class PhotosView extends StatefulWidget {
  const PhotosView({super.key});

  @override
  State<PhotosView> createState() => _PhotosViewState();
}

class _PhotosViewState extends State<PhotosView> {
  List<String> _ids = [];

  @override
  void initState() {
    super.initState();
    _snapshot();
  }

  void _snapshot() => _ids = context.read<SocialService>().photoHome().map((p) => p.id).toList();

  Future<void> _refresh() async => setState(_snapshot);

  bool _loading = false;

  /// Near the end: fetch older photo posts and add the new ones below.
  void _more() {
    if (_loading) return;
    _loading = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final social = context.read<SocialService>();
      final fresh = await moreFeedIds(social, PostKind.photo, social.photoHome, _ids);
      if (mounted && fresh.isNotEmpty) setState(() => _ids.addAll(fresh));
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final social = context.watch<SocialService>();
    // New posts of mine show up at the top right away.
    final fresh = social.byAuthor(social.meId, PostKind.photo).where((p) => !_ids.contains(p.id)).map((p) => p.id);
    final posts = [...fresh, ..._ids].map(social.post).whereType<SocialPost>().toList();
    final followedCount = posts.where((p) => p.authorId == social.meId || social.isFollowing(p.authorId)).length;
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView.builder(
        padding: const EdgeInsets.only(bottom: 90),
        itemCount: posts.length + 2,
        itemBuilder: (_, i) {
          if (i == 0) return const Column(children: [StoriesBar(), Divider(height: 1)]);
          if (i >= posts.length - 1) _more();
          if (i == posts.length + 1) return const LoadMoreFooter(kind: PostKind.photo);
          final p = posts[i - 1];
          return Column(
            children: [
              if (i - 1 == followedCount && followedCount < posts.length)
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 18, 16, 6),
                  child: Row(
                    children: [
                      Icon(Icons.check_circle_outline, color: MindColors.violet),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text('شاهدت كل جديد من تتابعهم · مقترحات لك', style: TextStyle(fontWeight: FontWeight.w700)),
                      ),
                    ],
                  ),
                ),
              PhotoCard(post: p),
            ],
          );
        },
      ),
    );
  }
}

/// One photo post, Instagram style.
class PhotoCard extends StatefulWidget {
  const PhotoCard({super.key, required this.post});
  final SocialPost post;

  @override
  State<PhotoCard> createState() => _PhotoCardState();
}

class _PhotoCardState extends State<PhotoCard> {
  int _page = 0;
  bool _heart = false;

  void _doubleTap() {
    context.read<SocialService>().like(widget.post);
    setState(() => _heart = true);
    Future.delayed(const Duration(milliseconds: 750), () {
      if (mounted) setState(() => _heart = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final social = context.watch<SocialService>();
    final p = widget.post;
    final author = social.user(p.authorId);
    final liked = social.liked(p);
    final comments = social.commentCount(p);
    final hasStory = social.storiesOf(p.authorId).isNotEmpty;
    final firstLiker = p.likes
        .where((id) => social.isFollowing(id) || id == social.meId)
        .map(social.user)
        .whereType<SocialUser>()
        .firstOrNull;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(12, 10, 4, 8),
          child: Row(
            children: [
              SocialAvatar(
                author,
                size: 36,
                ring: hasStory ? (social.hasUnseenStory(p.authorId) ? StoryRing.unseen : StoryRing.seen) : StoryRing.none,
                onTap: () => hasStory ? openStories(context, p.authorId) : openProfile(context, p.authorId),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: GestureDetector(
                  onTap: () => openProfile(context, p.authorId),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      NameLine(author, showHandle: false),
                      if (p.location.isNotEmpty) Text(p.location, style: const TextStyle(fontSize: 12, color: MindColors.muted)),
                    ],
                  ),
                ),
              ),
              if (social.hasAccount && p.authorId != social.meId && !social.isFollowing(p.authorId))
                TextButton(onPressed: () => social.toggleFollow(p.authorId), child: const Text('متابعة')),
              IconButton(icon: const Icon(Icons.more_vert), onPressed: () => showPostMenu(context, p)),
            ],
          ),
        ),
        GestureDetector(
          onDoubleTap: _doubleTap,
          child: AspectRatio(
            aspectRatio: 1,
            child: Stack(
              fit: StackFit.expand,
              children: [
                PageView.builder(
                  itemCount: p.media.length,
                  onPageChanged: (i) => setState(() => _page = i),
                  itemBuilder: (_, i) => MediaImage(p.media[i].src),
                ),
                if (p.media.length > 1)
                  PositionedDirectional(
                    top: 10,
                    end: 10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                      decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(12)),
                      child: Text('${_page + 1}/${p.media.length}', style: const TextStyle(color: Colors.white, fontSize: 12)),
                    ),
                  ),
                IgnorePointer(
                  child: AnimatedOpacity(
                    opacity: _heart ? 1 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: AnimatedScale(
                      scale: _heart ? 1 : 0.5,
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeOutBack,
                      child: const Center(
                        child: Icon(Icons.favorite, color: Colors.white, size: 110, shadows: [Shadow(blurRadius: 20)]),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        Row(
          children: [
            IconButton(
              icon: Icon(liked ? Icons.favorite : Icons.favorite_border, color: liked ? Colors.red : null),
              onPressed: () => social.toggleLike(p),
            ),
            IconButton(icon: const Icon(Icons.mode_comment_outlined), onPressed: () => showComments(context, p)),
            IconButton(icon: const Icon(Icons.send_outlined), onPressed: () => sharePost(context, p)),
            const Spacer(),
            if (p.media.length > 1)
              Row(
                children: List.generate(
                  p.media.length,
                  (i) => AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: i == _page ? MindColors.violet : Colors.grey.shade400,
                    ),
                  ),
                ),
              ),
            const Spacer(),
            IconButton(
              icon: Icon(social.isSaved(p) ? Icons.bookmark : Icons.bookmark_border),
              onPressed: () => social.toggleSave(p),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (p.likes.isNotEmpty)
                GestureDetector(
                  onTap: () => showPeople(context, 'الإعجابات', p.likes.toList()),
                  child: Text(
                    firstLiker != null && p.likes.length > 1
                        ? 'أعجب بها ${firstLiker.id == social.meId ? 'أنت' : firstLiker.handle} و${SocialText.count(p.likes.length - 1)} آخرين'
                        : '${SocialText.count(p.likes.length)} إعجاب',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              if (p.text.isNotEmpty) ...[
                const SizedBox(height: 4),
                RichPostText('${author?.handle ?? ''}  ${p.text}', maxLines: 2),
              ],
              if (comments > 0)
                GestureDetector(
                  onTap: () => showComments(context, p),
                  child: Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text('عرض التعليقات ($comments)', style: const TextStyle(color: MindColors.muted)),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.only(top: 4, bottom: 12),
                child: Text(SocialText.ago(p.createdAt), style: const TextStyle(color: MindColors.muted, fontSize: 12)),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// A single photo post on its own page (from a profile, search or a chat).
class PhotoPostScreen extends StatelessWidget {
  const PhotoPostScreen({super.key, required this.posts, this.index = 0});
  final List<SocialPost> posts;
  final int index;

  @override
  Widget build(BuildContext context) {
    final social = context.watch<SocialService>();
    final list = posts.map((p) => social.post(p.id)).whereType<SocialPost>().toList();
    final start = index.clamp(0, list.isEmpty ? 0 : list.length - 1);
    return Scaffold(
      appBar: AppBar(title: const Text('صور')),
      body: list.isEmpty
          ? const EmptyState('📸', 'لم يعد هذا المنشور متاحاً')
          // Starts at the tapped post and keeps the rest below it.
          : ListView(children: [for (final p in list.skip(start)) PhotoCard(post: p)]),
    );
  }
}

/// A list of people (likes, followers, following).
void showPeople(BuildContext context, String title, List<String> ids) => Navigator.of(context).push(
  MaterialPageRoute(builder: (_) => PeopleScreen(title: title, ids: ids)),
);

class PeopleScreen extends StatelessWidget {
  const PeopleScreen({super.key, required this.title, required this.ids});
  final String title;
  final List<String> ids;

  @override
  Widget build(BuildContext context) {
    final social = context.watch<SocialService>();
    final people = ids.map(social.user).whereType<SocialUser>().where((u) => !social.isBlocked(u.id)).toList();
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: people.isEmpty
          ? const EmptyState('👥', 'لا يوجد أحد هنا بعد')
          : ListView.builder(
              itemCount: people.length,
              itemBuilder: (_, i) => UserTile(people[i]),
            ),
    );
  }
}

class UserTile extends StatelessWidget {
  const UserTile(this.user, {super.key, this.trailing});
  final SocialUser user;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => ListTile(
    onTap: () => openProfile(context, user.id),
    leading: SocialAvatar(user, size: 44),
    title: NameLine(user, showHandle: false),
    subtitle: Text('@${user.handle}', textDirection: TextDirection.ltr, textAlign: TextAlign.end),
    trailing: trailing ?? FollowButton(user.id, compact: true),
  );
}
