import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';

import '../../services/social/social_service.dart';
import '../../services/social/text_utils.dart';
import 'comments_sheet.dart';
import 'post_menu.dart';
import 'share_sheet.dart';
import 'widgets.dart';

/// Full-screen vertical reels: swipe up for the next one, tap to pause,
/// double-tap to like. Used as the Reels feed and when opening a reel from a
/// profile, search or a chat.
class ReelsView extends StatefulWidget {
  const ReelsView({super.key, this.posts, this.initialIndex = 0, this.active = true});

  /// A fixed list (profile, search). Null shows the feed with its two tabs.
  final List<SocialPost>? posts;
  final int initialIndex;

  /// False pauses playback (another tab is showing).
  final bool active;

  @override
  State<ReelsView> createState() => _ReelsViewState();
}

class _ReelsViewState extends State<ReelsView> {
  late PageController _pages = PageController(initialPage: widget.initialIndex);
  bool _following = false;
  List<String> _ids = [];
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex;
    _snapshot();
  }

  /// The order is fixed until refresh, so likes and views don't reshuffle the feed mid-swipe.
  void _snapshot() {
    final social = context.read<SocialService>();
    final list = widget.posts ?? social.feed(PostKind.reel, following: _following);
    _ids = list.map((p) => p.id).toList();
  }

  void _switch(bool following) {
    if (following == _following) return;
    setState(() {
      _following = following;
      _snapshot();
      _index = 0;
      _pages.dispose();
      _pages = PageController();
    });
  }

  Future<void> _refresh() async {
    setState(() {
      _snapshot();
      _index = 0;
    });
    if (_pages.hasClients) _pages.jumpToPage(0);
  }

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final social = context.watch<SocialService>();
    final posts = _ids.map(social.post).whereType<SocialPost>().toList();
    final topPad = MediaQuery.of(context).padding.top;
    return ColoredBox(
      color: Colors.black,
      child: Stack(
        children: [
          if (posts.isEmpty)
            EmptyState(
              '🎬',
              _following ? 'لا توجد ريلز من الحسابات التي تتابعها بعد' : 'لا توجد ريلز بعد',
              action: _following ? TextButton(onPressed: () => _switch(false), child: const Text('شاهد «لك»')) : null,
            )
          else
            RefreshIndicator(
              onRefresh: _refresh,
              child: PageView.builder(
                controller: _pages,
                scrollDirection: Axis.vertical,
                itemCount: posts.length,
                onPageChanged: (i) => setState(() => _index = i),
                itemBuilder: (_, i) => ReelItem(post: posts[i], active: widget.active && i == _index),
              ),
            ),
          if (widget.posts == null)
            Positioned(
              top: topPad + 8,
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _Tab('متابَعون', selected: _following, onTap: () => _switch(true)),
                  const SizedBox(width: 18),
                  _Tab('لك', selected: !_following, onTap: () => _switch(false)),
                ],
              ),
            )
          else
            Positioned(
              top: topPad + 4,
              right: 4,
              child: const BackButton(color: Colors.white),
            ),
        ],
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab(this.label, {required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Column(
      children: [
        Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : Colors.white60,
            fontWeight: FontWeight.w800,
            fontSize: 17,
            shadows: const [Shadow(blurRadius: 6)],
          ),
        ),
        const SizedBox(height: 4),
        AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: selected ? 24 : 0,
          height: 3,
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(2)),
        ),
      ],
    ),
  );
}

/// Opens reels full screen at [index].
void openReels(BuildContext context, List<SocialPost> posts, int index) => Navigator.of(context).push(
  MaterialPageRoute(builder: (_) => Scaffold(backgroundColor: Colors.black, body: ReelsView(posts: posts, initialIndex: index))),
);

class ReelItem extends StatefulWidget {
  const ReelItem({super.key, required this.post, required this.active});
  final SocialPost post;
  final bool active;

  @override
  State<ReelItem> createState() => _ReelItemState();
}

class _ReelItemState extends State<ReelItem> with SingleTickerProviderStateMixin {
  VideoPlayerController? _video;
  bool _failed = false;
  bool _userPaused = false;
  bool _counted = false;
  Offset? _heartAt;
  Offset _tapAt = Offset.zero;
  late final AnimationController _disc = AnimationController(vsync: this, duration: const Duration(seconds: 5));

  SocialPost get _shown {
    final p = widget.post;
    return p.repostOf == null ? p : (context.read<SocialService>().post(p.repostOf!) ?? p);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    if (!mounted) return;
    final m = _shown.media.isEmpty ? null : _shown.media.first;
    if (m == null) return setState(() => _failed = true);
    final c = isRemote(m.src) ? VideoPlayerController.networkUrl(Uri.parse(m.src)) : VideoPlayerController.file(File(m.src));
    _video = c;
    try {
      await c.initialize();
      await c.setLooping(true);
      if (!mounted) return;
      setState(() {});
      _sync();
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  void didUpdateWidget(ReelItem old) {
    super.didUpdateWidget(old);
    if (old.active != widget.active) {
      if (widget.active) _userPaused = false;
      _sync();
    }
  }

  void _sync() {
    final c = _video;
    if (c == null || !c.value.isInitialized) return;
    if (widget.active && !_userPaused) {
      c.play();
      _disc.repeat();
      if (!_counted) {
        _counted = true;
        // After the frame: counting a view notifies listeners, which can't happen mid-build.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) context.read<SocialService>().view(_shown);
        });
      }
    } else {
      c.pause();
      _disc.stop();
    }
  }

  void _togglePause() {
    setState(() => _userPaused = !_userPaused);
    _sync();
  }

  void _doubleTap() {
    context.read<SocialService>().like(_shown);
    setState(() => _heartAt = _tapAt);
    Future.delayed(const Duration(milliseconds: 800), () {
      if (mounted) setState(() => _heartAt = null);
    });
  }

  @override
  void dispose() {
    _video?.dispose();
    _disc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final social = context.watch<SocialService>();
    final p = _shown;
    final author = social.user(p.authorId);
    final reposter = widget.post.repostOf == null ? null : social.user(widget.post.authorId);
    final c = _video;
    final ready = c != null && c.value.isInitialized;
    final m = p.media.isEmpty ? null : p.media.first;
    final bottomPad = MediaQuery.of(context).padding.bottom;

    return Stack(
      fit: StackFit.expand,
      children: [
        if (ready)
          FittedBox(
            fit: BoxFit.cover,
            clipBehavior: Clip.hardEdge,
            child: SizedBox(width: c.value.size.width, height: c.value.size.height, child: VideoPlayer(c)),
          )
        else if (m != null && m.thumb.isNotEmpty)
          MediaImage(m.thumb)
        else
          const ColoredBox(color: Colors.black),
        if (!ready && !_failed) const Center(child: CircularProgressIndicator(color: Colors.white70)),
        if (_failed)
          const Center(
            child: Text('تعذّر تشغيل الفيديو', style: TextStyle(color: Colors.white70)),
          ),
        // Gestures: tap pauses, double tap likes where you tapped.
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _togglePause,
          onDoubleTapDown: (d) => _tapAt = d.localPosition,
          onDoubleTap: _doubleTap,
        ),
        if (_userPaused && ready)
          const IgnorePointer(
            child: Center(child: Icon(Icons.play_arrow_rounded, size: 90, color: Colors.white70)),
          ),
        if (_heartAt != null)
          Positioned(
            left: _heartAt!.dx - 50,
            top: _heartAt!.dy - 50,
            child: IgnorePointer(
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.4, end: 1.2),
                duration: const Duration(milliseconds: 350),
                curve: Curves.elasticOut,
                builder: (_, s, child) => Transform.scale(scale: s, child: child),
                child: const Icon(Icons.favorite, color: Colors.redAccent, size: 100),
              ),
            ),
          ),
        // Shade so white text stays readable.
        const IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.black26, Colors.transparent, Colors.transparent, Colors.black54],
                stops: [0, 0.18, 0.6, 1],
              ),
            ),
          ),
        ),
        // Right rail (left in RTL: it follows the reading direction's end side).
        PositionedDirectional(
          end: 8,
          bottom: 24 + bottomPad,
          child: Column(
            children: [
              Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.bottomCenter,
                children: [
                  Container(
                    decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 1.5)),
                    child: SocialAvatar(author, size: 46, onTap: () => openProfile(context, p.authorId)),
                  ),
                  if (social.hasAccount && p.authorId != social.meId && !social.isFollowing(p.authorId))
                    Positioned(
                      bottom: -9,
                      child: GestureDetector(
                        onTap: () => social.toggleFollow(p.authorId),
                        child: const CircleAvatar(
                          radius: 10,
                          backgroundColor: Color(0xFFFE2C55),
                          child: Icon(Icons.add, size: 15, color: Colors.white),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 20),
              _RailButton(
                icon: Icons.favorite,
                color: social.liked(p) ? const Color(0xFFFE2C55) : Colors.white,
                label: SocialText.count(p.likes.length),
                onTap: () => social.toggleLike(p),
              ),
              _RailButton(
                icon: Icons.chat_bubble_rounded,
                label: SocialText.count(social.commentCount(p)),
                onTap: () => showComments(context, p),
              ),
              _RailButton(
                icon: Icons.bookmark_rounded,
                color: social.isSaved(p) ? const Color(0xFFFACE15) : Colors.white,
                label: SocialText.count(p.saves.length),
                onTap: () => social.toggleSave(p),
              ),
              _RailButton(
                icon: Icons.reply_rounded,
                flip: true,
                label: SocialText.count(p.shares),
                onTap: () => sharePost(context, p),
              ),
              _RailButton(icon: Icons.more_horiz, label: '', onTap: () => showPostMenu(context, p)),
              const SizedBox(height: 6),
              RotationTransition(
                turns: _disc,
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(colors: [Color(0xFF444444), Color(0xFF111111)]),
                  ),
                  child: SocialAvatar(author, size: 22),
                ),
              ),
            ],
          ),
        ),
        // Caption, author, sound.
        PositionedDirectional(
          start: 12,
          end: 80,
          bottom: 18 + bottomPad,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (reposter != null)
                Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(6)),
                  child: Text('🔁 أعاد نشره ${reposter.name}', style: const TextStyle(color: Colors.white, fontSize: 12)),
                ),
              GestureDetector(
                onTap: () => openProfile(context, p.authorId),
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        '@${author?.handle ?? ''}',
                        textDirection: TextDirection.ltr,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16),
                      ),
                    ),
                    if (author?.verified ?? false) const VerifiedBadge(),
                    Text(' · ${SocialText.ago(p.createdAt)}', style: const TextStyle(color: Colors.white70, fontSize: 13)),
                  ],
                ),
              ),
              if (p.text.isNotEmpty) ...[
                const SizedBox(height: 6),
                RichPostText(
                  p.text,
                  maxLines: 2,
                  linkColor: Colors.white,
                  style: const TextStyle(color: Colors.white, height: 1.4),
                ),
              ],
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.music_note_rounded, color: Colors.white, size: 16),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      p.sound.isNotEmpty ? p.sound : 'الصوت الأصلي - @${author?.handle ?? ''}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (ready)
          Positioned(
            left: 0,
            right: 0,
            bottom: bottomPad,
            height: 3,
            child: VideoProgressIndicator(
              c,
              allowScrubbing: true,
              padding: EdgeInsets.zero,
              colors: const VideoProgressColors(playedColor: Colors.white, bufferedColor: Colors.white24, backgroundColor: Colors.white10),
            ),
          ),
      ],
    );
  }
}

class _RailButton extends StatelessWidget {
  const _RailButton({required this.icon, required this.label, required this.onTap, this.color = Colors.white, this.flip = false});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color color;
  final bool flip;

  @override
  Widget build(BuildContext context) {
    Widget i = Icon(icon, color: color, size: 34, shadows: const [Shadow(blurRadius: 8)]);
    if (flip) i = Transform.flip(flipX: true, child: i);
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Column(
          children: [
            i,
            if (label.isNotEmpty)
              Text(
                label,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12, shadows: [Shadow(blurRadius: 6)]),
              ),
          ],
        ),
      ),
    );
  }
}
