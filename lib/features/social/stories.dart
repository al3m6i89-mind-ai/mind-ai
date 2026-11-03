import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../services/social/social_service.dart';
import '../../services/social/text_utils.dart';
import 'photos_view.dart';
import 'widgets.dart';

/// Row of story circles: you first (tap + to add), then people with stories.
class StoriesBar extends StatelessWidget {
  const StoriesBar({super.key});

  @override
  Widget build(BuildContext context) {
    final social = context.watch<SocialService>();
    final ring = social.storyRing();
    if (ring.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 108,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        itemCount: ring.length,
        itemBuilder: (_, i) {
          final u = ring[i];
          final mine = u.id == social.meId;
          final has = social.storiesOf(u.id).isNotEmpty;
          return GestureDetector(
            onTap: () => mine && !has ? addStory(context) : openStories(context, u.id),
            onLongPress: mine ? () => addStory(context) : null,
            child: SizedBox(
              width: 78,
              child: Column(
                children: [
                  Stack(
                    children: [
                      SocialAvatar(
                        u,
                        size: 62,
                        ring: !has ? StoryRing.none : (social.hasUnseenStory(u.id) ? StoryRing.unseen : StoryRing.seen),
                      ),
                      if (mine)
                        PositionedDirectional(
                          end: 0,
                          bottom: 0,
                          child: GestureDetector(
                            onTap: () => addStory(context),
                            child: Container(
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: const Color(0xFF1D9BF0),
                                border: Border.all(color: Theme.of(context).scaffoldBackgroundColor, width: 2),
                              ),
                              child: const Icon(Icons.add, color: Colors.white, size: 18),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    mine ? 'قصتك' : u.handle,
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
    );
  }
}

/// Picks a photo and adds it as a 24-hour story, with an optional caption.
Future<void> addStory(BuildContext context, {ImageSource source = ImageSource.gallery}) async {
  final social = context.read<SocialService>();
  if (!social.hasAccount) return;
  final x = await ImagePicker().pickImage(source: source, maxWidth: 1440, imageQuality: 88);
  if (x == null || !context.mounted) return;
  final caption = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('قصة جديدة'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipRRect(borderRadius: BorderRadius.circular(12), child: MediaImage(x.path, height: 220)),
          const SizedBox(height: 12),
          TextField(controller: caption, maxLength: 120, decoration: const InputDecoration(hintText: 'نص على القصة (اختياري)')),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('نشر لمدة 24 ساعة')),
      ],
    ),
  );
  if (ok != true) return;
  try {
    await social.addStory(x.path, caption: caption.text);
    if (context.mounted) toast(context, 'نُشرت قصتك ✨');
  } catch (e) {
    if (context.mounted) toast(context, e);
  }
}

/// Opens the story viewer at [uid], continuing through the others in the row.
void openStories(BuildContext context, String uid) {
  final social = context.read<SocialService>();
  final ring = social.storyRing().where((u) => social.storiesOf(u.id).isNotEmpty).map((u) => u.id).toList();
  if (!ring.contains(uid)) {
    if (social.storiesOf(uid).isEmpty) return;
    ring.insert(0, uid);
  }
  Navigator.of(context).push(
    PageRouteBuilder(
      opaque: true,
      pageBuilder: (_, _, _) => StoryViewer(users: ring, start: ring.indexOf(uid)),
      transitionsBuilder: (_, a, _, child) => FadeTransition(opacity: a, child: child),
    ),
  );
}

class StoryViewer extends StatefulWidget {
  const StoryViewer({super.key, required this.users, required this.start});
  final List<String> users;
  final int start;

  @override
  State<StoryViewer> createState() => _StoryViewerState();
}

class _StoryViewerState extends State<StoryViewer> with SingleTickerProviderStateMixin {
  static const _each = Duration(seconds: 5);
  late final AnimationController _timer = AnimationController(vsync: this, duration: _each)
    ..addStatusListener((s) {
      if (s == AnimationStatus.completed) _next();
    });
  late int _user = widget.start;
  int _story = 0;
  final _reply = TextEditingController();
  final _replyFocus = FocusNode();

  List<Story> get _stories => context.read<SocialService>().storiesOf(widget.users[_user]);

  @override
  void initState() {
    super.initState();
    // Start at the first story not seen yet.
    final social = context.read<SocialService>();
    final list = _stories;
    final firstNew = list.indexWhere((s) => !s.seenBy.contains(social.meId));
    _story = firstNew < 0 ? 0 : firstNew;
    _replyFocus.addListener(() => _replyFocus.hasFocus ? _timer.stop() : _timer.forward());
    _show();
  }

  void _show() {
    final list = _stories;
    if (list.isEmpty) return _next();
    _timer.forward(from: 0);
    final s = list[_story.clamp(0, list.length - 1)];
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<SocialService>().markStorySeen(s);
    });
  }

  void _next() {
    if (_story < _stories.length - 1) {
      setState(() => _story++);
    } else if (_user < widget.users.length - 1) {
      setState(() {
        _user++;
        _story = 0;
      });
    } else {
      Navigator.of(context).maybePop();
      return;
    }
    _show();
  }

  void _prev() {
    if (_story > 0) {
      setState(() => _story--);
    } else if (_user > 0) {
      setState(() {
        _user--;
        _story = _stories.length - 1;
      });
    }
    _show();
  }

  Future<void> _sendReply(String to) async {
    final text = _reply.text.trim();
    if (text.isEmpty) return;
    try {
      await context.read<SocialService>().sendMessage(to, text: 'ردّ على قصتك: $text');
      _reply.clear();
      _replyFocus.unfocus();
      if (mounted) toast(context, 'أُرسل الرد');
    } catch (e) {
      if (mounted) toast(context, e);
    }
  }

  @override
  void dispose() {
    _timer.dispose();
    _reply.dispose();
    _replyFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final social = context.watch<SocialService>();
    final uid = widget.users[_user];
    final author = social.user(uid);
    final list = social.storiesOf(uid);
    if (list.isEmpty) return const Scaffold(backgroundColor: Colors.black);
    final i = _story.clamp(0, list.length - 1);
    final s = list[i];
    final mine = uid == social.meId;
    final liked = s.likes.contains(social.meId);

    return Scaffold(
      backgroundColor: Colors.black,
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: GestureDetector(
                onTapUp: (d) {
                  final w = MediaQuery.of(context).size.width;
                  d.globalPosition.dx < w / 3 ? _prev() : _next();
                },
                onLongPressStart: (_) => _timer.stop(),
                onLongPressEnd: (_) => _timer.forward(),
                onVerticalDragEnd: (d) {
                  if ((d.primaryVelocity ?? 0) > 300) Navigator.of(context).maybePop();
                },
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ClipRRect(borderRadius: BorderRadius.circular(12), child: MediaImage(s.media.src)),
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.black54, Colors.transparent],
                          stops: [0, 0.2],
                        ),
                      ),
                    ),
                    Positioned(
                      top: 8,
                      left: 8,
                      right: 8,
                      child: Directionality(
                        textDirection: TextDirection.ltr,
                        child: Row(
                          children: [
                            for (var k = 0; k < list.length; k++)
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 2),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(2),
                                    child: AnimatedBuilder(
                                      animation: _timer,
                                      builder: (_, _) => LinearProgressIndicator(
                                        minHeight: 2.5,
                                        value: k < i ? 1 : (k == i ? _timer.value : 0),
                                        backgroundColor: Colors.white30,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    Positioned(
                      top: 20,
                      left: 8,
                      right: 8,
                      child: Row(
                        children: [
                          SocialAvatar(author, size: 34, onTap: () => openProfile(context, uid)),
                          const SizedBox(width: 8),
                          Expanded(child: NameLine(author, time: s.createdAt, color: Colors.white, showHandle: false)),
                          if (mine)
                            IconButton(
                              icon: const Icon(Icons.delete_outline, color: Colors.white),
                              onPressed: () async {
                                _timer.stop();
                                await social.deleteStory(s);
                                if (!context.mounted) return;
                                if (social.storiesOf(uid).isEmpty) {
                                  Navigator.of(context).maybePop();
                                } else {
                                  setState(() => _story = 0);
                                  _show();
                                }
                              },
                            ),
                          IconButton(
                            icon: const Icon(Icons.close, color: Colors.white),
                            onPressed: () => Navigator.of(context).maybePop(),
                          ),
                        ],
                      ),
                    ),
                    if (s.caption.isNotEmpty)
                      Positioned(
                        left: 24,
                        right: 24,
                        bottom: 40,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(12)),
                          child: Text(
                            s.caption,
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
              child: mine
                  ? InkWell(
                      onTap: () {
                        _timer.stop();
                        showPeople(context, 'شاهدها', s.seenBy.where((id) => id != social.meId).toList());
                      },
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: Row(
                          children: [
                            const Icon(Icons.visibility_outlined, color: Colors.white),
                            const SizedBox(width: 6),
                            Text(
                              'شاهدها ${SocialText.count(s.seenBy.where((id) => id != social.meId).length)}',
                              style: const TextStyle(color: Colors.white),
                            ),
                            const SizedBox(width: 16),
                            const Icon(Icons.favorite, color: Colors.redAccent, size: 18),
                            const SizedBox(width: 4),
                            Text(SocialText.count(s.likes.length), style: const TextStyle(color: Colors.white)),
                          ],
                        ),
                      ),
                    )
                  : Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _reply,
                            focusNode: _replyFocus,
                            style: const TextStyle(color: Colors.white),
                            textInputAction: TextInputAction.send,
                            onSubmitted: (_) => _sendReply(uid),
                            decoration: InputDecoration(
                              hintText: 'رد على ${author?.name ?? ''}…',
                              hintStyle: const TextStyle(color: Colors.white60),
                              filled: true,
                              fillColor: Colors.white12,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(24),
                                borderSide: const BorderSide(color: Colors.white38),
                              ),
                            ),
                          ),
                        ),
                        IconButton(
                          icon: Icon(liked ? Icons.favorite : Icons.favorite_border, color: liked ? Colors.redAccent : Colors.white),
                          onPressed: () => social.toggleStoryLike(s),
                        ),
                        IconButton(icon: const Icon(Icons.send_rounded, color: Colors.white), onPressed: () => _sendReply(uid)),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
