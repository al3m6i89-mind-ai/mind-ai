import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/theme.dart';
import '../../services/social/social_id.dart';
import '../../services/social/social_service.dart';
import '../../services/social/text_utils.dart';
import 'messages_screen.dart';
import 'onboarding.dart';
import 'photos_view.dart';
import 'posts_view.dart';
import 'reels_view.dart';
import 'stories.dart';
import 'widgets.dart';

/// One profile for all three sections: the same ID, followers and bio, with a
/// tab for each section's content.
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key, required this.userId, this.embedded = false});
  final String userId;

  /// Shown inside the social home (no back button).
  final bool embedded;

  @override
  Widget build(BuildContext context) {
    final social = context.watch<SocialService>();
    final u = social.user(userId);
    if (u == null) {
      return Scaffold(appBar: AppBar(), body: const EmptyState('🤷', 'هذا الحساب غير موجود'));
    }
    final mine = u.id == social.meId;
    final blockedByMe = social.isBlocked(u.id);
    final locked = u.private && !mine && !social.isFollowing(u.id);
    final tabs = <(String, IconData)>[
      ('ريلز', Icons.movie_outlined),
      ('صور', Icons.grid_on_rounded),
      ('منشورات', Icons.notes_rounded),
      ('ردود', Icons.forum_outlined),
      if (mine) ('محفوظات', Icons.bookmark_border),
    ];

    return DefaultTabController(
      length: tabs.length,
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: !embedded,
          title: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (u.private) const Padding(padding: EdgeInsets.only(left: 4), child: Icon(Icons.lock_outline, size: 18)),
              Text('@${u.handle}', textDirection: TextDirection.ltr),
              if (u.verified) const VerifiedBadge(size: 18),
            ],
          ),
          actions: [
            if (mine)
              IconButton(icon: const Icon(Icons.menu_rounded), onPressed: () => _myMenu(context))
            else
              IconButton(icon: const Icon(Icons.more_vert), onPressed: () => _theirMenu(context, u)),
          ],
        ),
        body: NestedScrollView(
          headerSliverBuilder: (_, _) => [
            SliverToBoxAdapter(child: _Header(user: u, mine: mine)),
            if (!blockedByMe && !locked)
              SliverPersistentHeader(
                pinned: true,
                delegate: _TabsHeader(
                  TabBar(
                    isScrollable: tabs.length > 4,
                    tabs: [for (final t in tabs) Tab(icon: Icon(t.$2, size: 20), text: t.$1)],
                  ),
                  Theme.of(context).scaffoldBackgroundColor,
                ),
              ),
          ],
          body: blockedByMe
              ? EmptyState(
                  '🚫',
                  'لقد حظرت هذا الحساب',
                  action: OutlinedButton(onPressed: () => social.toggleBlock(u.id), child: const Text('إلغاء الحظر')),
                )
              : locked
              ? const EmptyState('🔒', 'هذا الحساب خاص\nتابعه لترى ريلزه وصوره ومنشوراته')
              : TabBarView(
                  children: [
                    _Grid(posts: social.byAuthor(u.id, PostKind.reel).where((p) => p.repostOf == null).toList(), reels: true, mine: mine),
                    _Grid(posts: social.byAuthor(u.id, PostKind.photo).where((p) => p.repostOf == null).toList(), mine: mine),
                    _List(posts: social.byAuthor(u.id, PostKind.post), empty: 'لا توجد منشورات بعد'),
                    _List(posts: social.byAuthor(u.id, PostKind.post, replies: true), empty: 'لا توجد ردود بعد'),
                    if (mine) const _Saved(),
                  ],
                ),
        ),
      ),
    );
  }

  void _myMenu(BuildContext context) {
    final social = context.read<SocialService>();
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('تعديل الملف الشخصي'),
              onTap: () {
                Navigator.pop(ctx);
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => const EditProfileScreen()));
              },
            ),
            ListTile(
              leading: const Icon(Icons.favorite_border),
              title: const Text('ما أعجبني'),
              onTap: () {
                Navigator.pop(ctx);
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => const _LikedScreen()));
              },
            ),
            const Divider(),
            for (final a in social.localAccounts.where((a) => a.id != social.meId))
              ListTile(
                leading: SocialAvatar(a, size: 32),
                title: Text('التبديل إلى @${a.handle}'),
                subtitle: Text(a.id, textDirection: TextDirection.ltr, textAlign: TextAlign.end),
                onTap: () {
                  Navigator.pop(ctx);
                  social.switchAccount(a.id);
                },
              ),
            ListTile(
              leading: const Icon(Icons.person_add_alt),
              title: const Text('إضافة حساب'),
              onTap: () {
                Navigator.pop(ctx);
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SocialOnboarding(addAnother: true)));
              },
            ),
          ],
        ),
      ),
    );
  }

  void _theirMenu(BuildContext context, SocialUser u) {
    final social = context.read<SocialService>();
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.badge_outlined),
              title: const Text('نسخ الـ ID'),
              subtitle: Text(u.id, textDirection: TextDirection.ltr, textAlign: TextAlign.end),
              onTap: () {
                Navigator.pop(ctx);
                copyId(context, u.id);
              },
            ),
            ListTile(
              leading: const Icon(Icons.block, color: Colors.redAccent),
              title: Text(social.isBlocked(u.id) ? 'إلغاء الحظر' : 'حظر', style: const TextStyle(color: Colors.redAccent)),
              onTap: () {
                Navigator.pop(ctx);
                social.toggleBlock(u.id);
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.user, required this.mine});
  final SocialUser user;
  final bool mine;

  @override
  Widget build(BuildContext context) {
    final social = context.watch<SocialService>();
    final u = user;
    final hasStory = social.storiesOf(u.id).isNotEmpty;
    Widget stat(int n, String label, VoidCallback? onTap) => Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            children: [
              Text(SocialText.count(n), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17)),
              Text(label, style: const TextStyle(color: MindColors.muted, fontSize: 12)),
            ],
          ),
        ),
      ),
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SocialAvatar(
                u,
                size: 84,
                ring: hasStory ? (social.hasUnseenStory(u.id) ? StoryRing.unseen : StoryRing.seen) : StoryRing.none,
                onTap: hasStory ? () => openStories(context, u.id) : (mine ? () => addStory(context) : null),
              ),
              const SizedBox(width: 8),
              stat(social.postCount(u.id), 'منشور', null),
              stat(u.followers.length, 'متابِع', () => showPeople(context, 'المتابِعون', u.followers.toList())),
              stat(u.following.length, 'يتابع', () => showPeople(context, 'يتابع', u.following.toList())),
              stat(social.likesReceived(u.id), 'إعجاب', null),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Flexible(child: Text(u.name, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17))),
              if (u.verified) const VerifiedBadge(size: 17),
            ],
          ),
          const SizedBox(height: 6),
          IdChip(u.id),
          if (u.bio.isNotEmpty) ...[const SizedBox(height: 8), RichPostText(u.bio)],
          if (u.link.isNotEmpty)
            GestureDetector(
              onTap: () {
                final uri = Uri.tryParse(u.link.startsWith('http') ? u.link : 'https://${u.link}');
                if (uri != null) launchUrl(uri, mode: LaunchMode.externalApplication);
              },
              child: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  children: [
                    const Icon(Icons.link_rounded, size: 16, color: Color(0xFF1D9BF0)),
                    const SizedBox(width: 4),
                    Flexible(child: Text(u.link, textDirection: TextDirection.ltr, style: const TextStyle(color: Color(0xFF1D9BF0)))),
                  ],
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'انضم ${u.joined.month}/${u.joined.year}${!mine && social.follows(u.id, social.meId) ? ' · يتابعك' : ''}',
              style: const TextStyle(color: MindColors.muted, fontSize: 12),
            ),
          ),
          const SizedBox(height: 12),
          if (mine)
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const EditProfileScreen())),
                    child: const Text('تعديل الملف'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => copyText(
                      context,
                      'تابعني على Mind Ai: @${u.handle}\nالـ ID: ${u.id}',
                      done: 'تم نسخ بطاقة حسابك',
                    ),
                    child: const Text('مشاركة الملف'),
                  ),
                ),
              ],
            )
          else if (!social.isBlocked(u.id))
            Row(
              children: [
                Expanded(child: FollowButton(u.id)),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(onPressed: () => openChat(context, u.id), child: const Text('مراسلة')),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _TabsHeader extends SliverPersistentHeaderDelegate {
  _TabsHeader(this.bar, this.bg);
  final TabBar bar;
  final Color bg;

  @override
  double get minExtent => bar.preferredSize.height;
  @override
  double get maxExtent => bar.preferredSize.height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) => ColoredBox(color: bg, child: bar);

  @override
  bool shouldRebuild(_TabsHeader old) => old.bar != bar || old.bg != bg;
}

class _Grid extends StatelessWidget {
  const _Grid({required this.posts, this.reels = false, this.mine = false});
  final List<SocialPost> posts;
  final bool reels;
  final bool mine;

  @override
  Widget build(BuildContext context) {
    if (posts.isEmpty) {
      return EmptyState(
        reels ? '🎬' : '📸',
        reels ? 'لا توجد ريلز بعد' : 'لا توجد صور بعد',
      );
    }
    return PostGrid(
      posts: posts,
      tall: reels,
      onOpen: (i) => reels
          ? openReels(context, posts, i)
          : Navigator.of(context).push(MaterialPageRoute(builder: (_) => PhotoPostScreen(posts: posts, index: i))),
    );
  }
}

class _List extends StatelessWidget {
  const _List({required this.posts, required this.empty});
  final List<SocialPost> posts;
  final String empty;

  @override
  Widget build(BuildContext context) {
    if (posts.isEmpty) return EmptyState('💬', empty);
    return ListView.separated(
      padding: EdgeInsets.zero,
      itemCount: posts.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (_, i) => PostCard(post: posts[i]),
    );
  }
}

/// Saved items from all three sections, private to you.
class _Saved extends StatelessWidget {
  const _Saved();

  @override
  Widget build(BuildContext context) {
    final social = context.watch<SocialService>();
    final reels = social.saved(PostKind.reel);
    final photos = social.saved(PostKind.photo);
    final posts = social.saved(PostKind.post);
    if (reels.isEmpty && photos.isEmpty && posts.isEmpty) {
      return const EmptyState('🔖', 'احفظ ريلز وصوراً ومنشورات لتجدها هنا\nلا يراها أحد غيرك');
    }
    Widget title(String t) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      child: Text(t, style: const TextStyle(fontWeight: FontWeight.w800)),
    );
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        if (reels.isNotEmpty) ...[
          title('🎬 ريلز (${reels.length})'),
          PostGrid(posts: reels, tall: true, shrinkWrap: true, onOpen: (i) => openReels(context, reels, i)),
        ],
        if (photos.isNotEmpty) ...[
          title('📸 صور (${photos.length})'),
          PostGrid(
            posts: photos,
            shrinkWrap: true,
            onOpen: (i) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => PhotoPostScreen(posts: photos, index: i))),
          ),
        ],
        if (posts.isNotEmpty) ...[
          title('💬 منشورات (${posts.length})'),
          for (final p in posts) ...[PostCard(post: p), const Divider(height: 1)],
        ],
      ],
    );
  }
}

class _LikedScreen extends StatelessWidget {
  const _LikedScreen();

  @override
  Widget build(BuildContext context) {
    final social = context.watch<SocialService>();
    final reels = social.likedBy(social.meId, PostKind.reel);
    final photos = social.likedBy(social.meId, PostKind.photo);
    final posts = social.likedBy(social.meId, PostKind.post);
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('ما أعجبني'),
          bottom: const TabBar(tabs: [Tab(text: 'ريلز'), Tab(text: 'صور'), Tab(text: 'منشورات')]),
        ),
        body: TabBarView(
          children: [
            _Grid(posts: reels, reels: true),
            _Grid(posts: photos),
            _List(posts: posts, empty: 'لم تعجبك منشورات بعد'),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- edit

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  late final SocialUser _me = context.read<SocialService>().me!;
  late final _name = TextEditingController(text: _me.name);
  late final _handle = TextEditingController(text: _me.handle);
  late final _bio = TextEditingController(text: _me.bio);
  late final _link = TextEditingController(text: _me.link);
  late bool _private = _me.private;
  String? _avatar;
  String? _handleError;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _handle.dispose();
    _bio.dispose();
    _link.dispose();
    super.dispose();
  }

  void _checkHandle(String v) {
    final social = context.read<SocialService>();
    setState(() {
      _handleError = Handle.problem(v) ?? (social.handleFree(v, exceptId: _me.id) ? null : 'هذا المعرّف مستخدم');
    });
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      await context.read<SocialService>().updateProfile(
        name: _name.text,
        handle: _handle.text,
        bio: _bio.text,
        link: _link.text,
        private: _private,
        avatarPath: _avatar,
      );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) toast(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final preview = SocialUser(id: _me.id, handle: _me.handle, name: _name.text, avatar: _avatar ?? _me.avatar);
    return Scaffold(
      appBar: AppBar(
        title: const Text('تعديل الملف الشخصي'),
        actions: [
          TextButton(onPressed: _busy || _handleError != null ? null : _save, child: const Text('حفظ')),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Center(child: SocialAvatar(preview, size: 96)),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TextButton(
                onPressed: () async {
                  final x = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 600, imageQuality: 88);
                  if (x != null) setState(() => _avatar = x.path);
                },
                child: const Text('تغيير الصورة'),
              ),
              if ((_avatar ?? _me.avatar).isNotEmpty)
                TextButton(onPressed: () => setState(() => _avatar = ''), child: const Text('إزالة', style: TextStyle(color: Colors.redAccent))),
            ],
          ),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: const Icon(Icons.badge_outlined, color: MindColors.violet),
              title: const Text('الـ ID الموحّد'),
              subtitle: const Text('ثابت ولا يتغير، يعرّفك في الريلز والصور والمنشورات'),
              trailing: IdChip(_me.id),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _name,
            maxLength: 50,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(labelText: 'الاسم'),
          ),
          TextField(
            controller: _handle,
            maxLength: 20,
            textDirection: TextDirection.ltr,
            onChanged: _checkHandle,
            decoration: InputDecoration(labelText: 'المعرّف', prefixText: '@', errorText: _handleError),
          ),
          TextField(controller: _bio, maxLength: 150, maxLines: 3, minLines: 1, decoration: const InputDecoration(labelText: 'النبذة')),
          TextField(
            controller: _link,
            textDirection: TextDirection.ltr,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(labelText: 'رابط'),
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            value: _private,
            onChanged: (v) => setState(() => _private = v),
            title: const Text('حساب خاص'),
            subtitle: const Text('يرى محتواك في الأقسام الثلاثة من يتابعك فقط'),
          ),
        ],
      ),
    );
  }
}
