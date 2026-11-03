import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../app/theme.dart';
import '../../services/social/social_service.dart';
import '../../services/social/text_utils.dart';
import 'profile_screen.dart';
import 'search_screen.dart';

// ---------------------------------------------------------------- navigation

void openProfile(BuildContext context, String uid) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => ProfileScreen(userId: uid)));

void openHandle(BuildContext context, String handle) {
  final u = context.read<SocialService>().byHandle(handle);
  if (u == null) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('لا يوجد حساب @$handle')));
  } else {
    openProfile(context, u.id);
  }
}

void openTag(BuildContext context, String tag) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => SearchScreen(initial: '#$tag')));

void copyText(BuildContext context, String text, {String done = 'تم النسخ'}) {
  Clipboard.setData(ClipboardData(text: text));
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(done)));
}

void copyId(BuildContext context, String id) => copyText(context, id, done: 'تم نسخ الـ ID: $id');

void toast(BuildContext context, Object e) {
  final msg = e is ArgumentError ? '${e.message}' : e.toString().replaceFirst(RegExp(r'^(Exception|Bad state): '), '');
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating));
}

// ---------------------------------------------------------------- media

bool isRemote(String src) => src.startsWith('http://') || src.startsWith('https://');

/// A photo from a URL or from the phone, with a soft placeholder while loading.
class MediaImage extends StatelessWidget {
  const MediaImage(this.src, {super.key, this.fit = BoxFit.cover, this.width, this.height});
  final String src;
  final BoxFit fit;
  final double? width;
  final double? height;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final placeholder = Container(
      width: width,
      height: height,
      color: dark ? const Color(0xFF2A2540) : const Color(0xFFECE8FA),
    );
    if (src.isEmpty) return placeholder;
    Widget error(BuildContext _, Object _, StackTrace? _) => Container(
      width: width,
      height: height,
      color: dark ? const Color(0xFF2A2540) : const Color(0xFFECE8FA),
      alignment: Alignment.center,
      child: const Icon(Icons.broken_image_outlined, color: MindColors.muted),
    );
    if (isRemote(src)) {
      return Image.network(
        src,
        fit: fit,
        width: width,
        height: height,
        errorBuilder: error,
        loadingBuilder: (_, child, progress) => progress == null ? child : placeholder,
      );
    }
    return Image.file(File(src), fit: fit, width: width, height: height, errorBuilder: error);
  }
}

// ---------------------------------------------------------------- people

class VerifiedBadge extends StatelessWidget {
  const VerifiedBadge({super.key, this.size = 15});
  final double size;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsetsDirectional.only(start: 3),
    child: Icon(Icons.verified, size: size, color: const Color(0xFF1D9BF0)),
  );
}

enum StoryRing { none, unseen, seen }

/// Round profile picture; falls back to the first letter on a gradient.
class SocialAvatar extends StatelessWidget {
  const SocialAvatar(this.user, {super.key, this.size = 40, this.ring = StoryRing.none, this.onTap});
  final SocialUser? user;
  final double size;
  final StoryRing ring;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final u = user;
    final letter = (u == null || u.name.isEmpty) ? '?' : u.name.characters.first.toUpperCase();
    Widget face = ClipOval(
      child: SizedBox(
        width: size,
        height: size,
        child: u != null && u.avatar.isNotEmpty
            ? MediaImage(u.avatar)
            : DecoratedBox(
                decoration: const BoxDecoration(gradient: MindColors.brand),
                child: Center(
                  child: Text(
                    letter,
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: size * 0.42),
                  ),
                ),
              ),
      ),
    );
    if (ring != StoryRing.none) {
      final bg = Theme.of(context).scaffoldBackgroundColor;
      face = Container(
        padding: const EdgeInsets.all(2.5),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: ring == StoryRing.unseen
              ? const LinearGradient(colors: [Color(0xFFFEDA75), Color(0xFFFA7E1E), Color(0xFFD62976), Color(0xFF962FBF)])
              : null,
          color: ring == StoryRing.seen ? Colors.grey.shade400 : null,
        ),
        child: Container(
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(shape: BoxShape.circle, color: bg),
          child: face,
        ),
      );
    }
    return onTap == null ? face : GestureDetector(onTap: onTap, child: face);
  }
}

/// "Name ✓ @handle · 3س" line used by posts and comments.
class NameLine extends StatelessWidget {
  const NameLine(this.user, {super.key, this.time, this.color, this.showHandle = true});
  final SocialUser? user;
  final DateTime? time;
  final Color? color;
  final bool showHandle;

  @override
  Widget build(BuildContext context) {
    final u = user;
    final muted = color?.withValues(alpha: 0.7) ?? MindColors.muted;
    return Row(
      children: [
        Flexible(
          child: Text(
            u?.name ?? 'حساب محذوف',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontWeight: FontWeight.w800, color: color),
          ),
        ),
        if (u?.verified ?? false) const VerifiedBadge(),
        if (showHandle && u != null)
          Flexible(
            child: Padding(
              padding: const EdgeInsetsDirectional.only(start: 4),
              child: Text(
                '@${u.handle}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textDirection: TextDirection.ltr,
                style: TextStyle(color: muted, fontSize: 13),
              ),
            ),
          ),
        if (time != null) Text(' · ${SocialText.ago(time!)}', style: TextStyle(color: muted, fontSize: 13)),
      ],
    );
  }
}

/// Follow / Following button that works the same in every section.
class FollowButton extends StatelessWidget {
  const FollowButton(this.uid, {super.key, this.compact = false});
  final String uid;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final social = context.watch<SocialService>();
    if (uid == social.meId || !social.hasAccount) return const SizedBox.shrink();
    final on = social.isFollowing(uid);
    final back = social.follows(uid, social.meId);
    final label = on ? 'تتابعه' : (back ? 'تابِع بالمثل' : 'متابعة');
    final pad = compact ? const EdgeInsets.symmetric(horizontal: 12, vertical: 6) : null;
    return on
        ? OutlinedButton(
            style: OutlinedButton.styleFrom(padding: pad, visualDensity: VisualDensity.compact),
            onPressed: () => social.toggleFollow(uid),
            child: Text(label),
          )
        : FilledButton(
            style: FilledButton.styleFrom(padding: pad, visualDensity: VisualDensity.compact),
            onPressed: () => social.toggleFollow(uid),
            child: Text(label),
          );
  }
}

// ---------------------------------------------------------------- text

/// Text with tappable #hashtags and @mentions, and "more" for long captions.
class RichPostText extends StatefulWidget {
  const RichPostText(this.text, {super.key, this.style, this.maxLines, this.linkColor});
  final String text;
  final TextStyle? style;
  final int? maxLines;
  final Color? linkColor;

  @override
  State<RichPostText> createState() => _RichPostTextState();
}

class _RichPostTextState extends State<RichPostText> {
  final _recognizers = <TapGestureRecognizer>[];
  bool _open = false;

  void _clear() {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();
  }

  @override
  void dispose() {
    _clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _clear();
    final link = widget.linkColor ?? const Color(0xFF1D9BF0);
    final spans = <InlineSpan>[];
    for (final p in SocialText.pieces(widget.text)) {
      if (p.tag == null && p.mention == null) {
        spans.add(TextSpan(text: p.text));
        continue;
      }
      final r = TapGestureRecognizer()
        ..onTap = () => p.tag != null ? openTag(context, p.tag!) : openHandle(context, p.mention!);
      _recognizers.add(r);
      spans.add(TextSpan(text: p.text, style: TextStyle(color: link, fontWeight: FontWeight.w600), recognizer: r));
    }
    final text = Text.rich(
      TextSpan(children: spans),
      style: widget.style,
      maxLines: _open ? null : widget.maxLines,
      overflow: _open || widget.maxLines == null ? null : TextOverflow.ellipsis,
    );
    if (widget.maxLines == null || _open) return text;
    return LayoutBuilder(
      builder: (context, box) {
        final tp = TextPainter(
          text: TextSpan(text: widget.text, style: widget.style ?? DefaultTextStyle.of(context).style),
          maxLines: widget.maxLines,
          textDirection: Directionality.of(context),
        )..layout(maxWidth: box.maxWidth);
        if (!tp.didExceedMaxLines) return text;
        return GestureDetector(
          onTap: () => setState(() => _open = true),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              text,
              Text('المزيد', style: TextStyle(color: (widget.style?.color ?? MindColors.muted).withValues(alpha: 0.7), fontWeight: FontWeight.w700)),
            ],
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------- misc

/// Icon + count used in action rows.
class CountAction extends StatelessWidget {
  const CountAction({super.key, required this.icon, this.count, this.color, this.onTap, this.size = 20});
  final IconData icon;
  final int? count;
  final Color? color;
  final VoidCallback? onTap;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = color ?? MindColors.muted;
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: size, color: c),
            if (count != null && count! > 0) ...[
              const SizedBox(width: 4),
              Text(SocialText.count(count!), style: TextStyle(color: c, fontSize: 13)),
            ],
          ],
        ),
      ),
    );
  }
}

/// Centered message for empty lists.
class EmptyState extends StatelessWidget {
  const EmptyState(this.emoji, this.text, {super.key, this.action});
  final String emoji;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 48)),
          const SizedBox(height: 10),
          Text(text, textAlign: TextAlign.center, style: const TextStyle(color: MindColors.muted, height: 1.5)),
          if (action != null) ...[const SizedBox(height: 14), action!],
        ],
      ),
    ),
  );
}

/// The unified ID shown as a tappable chip (copies on tap).
class IdChip extends StatelessWidget {
  const IdChip(this.id, {super.key});
  final String id;

  @override
  Widget build(BuildContext context) => InkWell(
    borderRadius: BorderRadius.circular(12),
    onTap: () => copyId(context, id),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: MindColors.violet.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.badge_outlined, size: 15, color: MindColors.violet),
          const SizedBox(width: 6),
          Text(
            id,
            textDirection: TextDirection.ltr,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontWeight: FontWeight.w800,
              color: MindColors.violet,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(width: 6),
          const Icon(Icons.copy_rounded, size: 14, color: MindColors.violet),
        ],
      ),
    ),
  );
}

/// Grid of post thumbnails (reels and photos on a profile, explore, search).
class PostGrid extends StatelessWidget {
  const PostGrid({super.key, required this.posts, required this.onOpen, this.shrinkWrap = false, this.tall = false});
  final List<SocialPost> posts;
  final void Function(int index) onOpen;
  final bool shrinkWrap;

  /// 9:16 tiles for reels.
  final bool tall;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: shrinkWrap,
      physics: shrinkWrap ? const NeverScrollableScrollPhysics() : null,
      padding: EdgeInsets.zero,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 2,
        crossAxisSpacing: 2,
        childAspectRatio: tall ? 9 / 16 : 1,
      ),
      itemCount: posts.length,
      itemBuilder: (_, i) => GestureDetector(onTap: () => onOpen(i), child: PostTile(posts[i])),
    );
  }
}

class PostTile extends StatelessWidget {
  const PostTile(this.post, {super.key});
  final SocialPost post;

  @override
  Widget build(BuildContext context) {
    final p = post;
    final first = p.media.isEmpty ? null : p.media.first;
    final Widget bg;
    if (first == null) {
      bg = Container(
        decoration: const BoxDecoration(gradient: MindColors.cool),
        padding: const EdgeInsets.all(8),
        alignment: Alignment.center,
        child: Text(
          p.text,
          maxLines: 5,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12),
        ),
      );
    } else if (first.video && first.thumb.isEmpty) {
      bg = Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(colors: [Color(0xFF241B3B), Color(0xFF0E0B16)], begin: Alignment.topCenter, end: Alignment.bottomCenter),
        ),
        padding: const EdgeInsets.all(8),
        alignment: Alignment.center,
        child: Text(
          p.text.isEmpty ? '🎬' : p.text,
          maxLines: 4,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
      );
    } else {
      bg = MediaImage(first.video ? first.thumb : first.src);
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        bg,
        if (first?.video ?? false)
          PositionedDirectional(
            start: 6,
            bottom: 6,
            child: Row(
              children: [
                const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 18, shadows: [Shadow(blurRadius: 4)]),
                Text(
                  SocialText.count(p.views),
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12, shadows: [Shadow(blurRadius: 4)]),
                ),
              ],
            ),
          ),
        if (p.media.length > 1)
          const PositionedDirectional(
            top: 6,
            end: 6,
            child: Icon(Icons.collections_rounded, color: Colors.white, size: 18, shadows: [Shadow(blurRadius: 4)]),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------- infinite scroll

/// Loads older pages of [kind] until [feed] shows posts not in [have] (or the
/// server has nothing older). Returns the new IDs in feed order.
Future<List<String>> moreFeedIds(
  SocialService social,
  PostKind kind,
  Iterable<SocialPost> Function() feed,
  List<String> have,
) async {
  for (var tries = 0; tries < 4 && social.canLoadMore(kind: kind); tries++) {
    final added = await social.loadMore(kind: kind);
    final known = have.toSet();
    final fresh = [for (final p in feed()) if (!known.contains(p.id)) p.id];
    if (fresh.isNotEmpty) return fresh;
    if (added == 0) break;
  }
  return const [];
}

/// Bottom of a list: a spinner while older posts load, a quiet end mark
/// when there is nothing older.
class LoadMoreFooter extends StatelessWidget {
  const LoadMoreFooter({super.key, this.kind, this.authorId, this.dark = false});
  final PostKind? kind;
  final String? authorId;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final social = context.watch<SocialService>();
    if (!social.online) return const SizedBox(height: 24);
    if (social.isLoadingMore(kind: kind, authorId: authorId)) {
      return Padding(
        padding: const EdgeInsets.all(20),
        child: Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2.5, color: dark ? Colors.white70 : null),
          ),
        ),
      );
    }
    if (!social.canLoadMore(kind: kind, authorId: authorId)) {
      return Padding(
        padding: const EdgeInsets.all(20),
        child: Center(
          child: Text('✓ وصلت للنهاية', style: TextStyle(color: dark ? Colors.white54 : MindColors.muted, fontSize: 12)),
        ),
      );
    }
    return const SizedBox(height: 60);
  }
}

/// Asks for older posts of a person (profile tabs) when the list is short or
/// scrolled near its end.
class AuthorPager extends StatefulWidget {
  const AuthorPager({super.key, required this.kind, required this.authorId, required this.count, required this.child});
  final PostKind kind;
  final String authorId;

  /// How many items the list shows now.
  final int count;
  final Widget child;

  @override
  State<AuthorPager> createState() => _AuthorPagerState();
}

class _AuthorPagerState extends State<AuthorPager> {
  bool _asked = false;

  void _more() {
    if (_asked) return;
    final social = context.read<SocialService>();
    if (!social.canLoadMore(kind: widget.kind, authorId: widget.authorId)) return;
    _asked = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await social.loadMore(kind: widget.kind, authorId: widget.authorId);
      _asked = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    // A short list fills itself (older posts may be outside the live window).
    if (widget.count < SocialService.pageSize) _more();
    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        if (n.metrics.extentAfter < 600) _more();
        return false;
      },
      child: widget.child,
    );
  }
}

/// Shown to the writer (and moderators) on content hidden for review.
class HiddenNote extends StatelessWidget {
  const HiddenNote({super.key});

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.symmetric(vertical: 4),
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(color: Colors.orange.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
    child: const Text(
      '🚩 مخفي عن الآخرين بانتظار مراجعة الإشراف',
      style: TextStyle(color: Colors.orange, fontSize: 12, fontWeight: FontWeight.w700),
    ),
  );
}
