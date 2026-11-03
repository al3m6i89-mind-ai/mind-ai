import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/shell.dart';
import '../../app/theme.dart';
import '../../services/social/social_service.dart';
import 'compose.dart';
import 'messages_screen.dart';
import 'moderation_screen.dart';
import 'notifications_screen.dart';
import 'onboarding.dart';
import 'photos_view.dart';
import 'posts_view.dart';
import 'reels_view.dart';
import 'search_screen.dart';
import 'widgets.dart';

/// The «مجتمع» tab: Reels, Photos and Posts under one account and one ID,
/// with shared search, notifications, messages and profile.
class SocialHome extends StatefulWidget {
  const SocialHome({super.key, required this.tabIndex});

  /// This tab's index in the app's bottom bar (to pause reels elsewhere).
  final int tabIndex;

  @override
  State<SocialHome> createState() => _SocialHomeState();
}

class _SocialHomeState extends State<SocialHome> {
  PostKind _section = PostKind.reel;
  bool _welcome = false;

  @override
  Widget build(BuildContext context) {
    final social = context.watch<SocialService>();
    if (!social.ready) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (!social.hasAccount || _welcome) {
      _welcome = true;
      return Scaffold(
        body: SafeArea(child: SocialOnboarding(onDone: () => setState(() => _welcome = false))),
      );
    }

    final reels = _section == PostKind.reel;
    final fg = reels ? Colors.white : null;
    Widget badge(Widget icon, int n) => n == 0 ? icon : Badge(label: Text(n > 99 ? '99+' : '$n'), child: icon);

    return ValueListenableBuilder<int>(
      valueListenable: Shell.current,
      builder: (context, shellTab, _) {
        final routeOnTop = ModalRoute.of(context)?.isCurrent ?? true;
        final playing = reels && shellTab == widget.tabIndex && routeOnTop;
        return Scaffold(
          backgroundColor: reels ? Colors.black : null,
          appBar: AppBar(
            backgroundColor: reels ? Colors.black : null,
            foregroundColor: fg,
            centerTitle: false,
            title: Text('مجتمع', style: TextStyle(color: fg, fontWeight: FontWeight.w900, fontSize: 22)),
            actions: [
              IconButton(
                icon: const Icon(Icons.search),
                tooltip: 'بحث بالـ ID أو المعرّف',
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SearchScreen())),
              ),
              IconButton(
                icon: badge(const Icon(Icons.notifications_none), social.unreadNotices),
                tooltip: 'الإشعارات',
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const NotificationsScreen())),
              ),
              IconButton(
                icon: badge(const Icon(Icons.mail_outline), social.unreadMessages),
                tooltip: 'الرسائل',
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const InboxScreen())),
              ),
              if (social.isAdmin && social.openReports > 0)
                IconButton(
                  icon: badge(const Icon(Icons.shield_outlined), social.openReports),
                  tooltip: 'لوحة الإشراف',
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ModerationScreen())),
                ),
              IconButton(icon: const Icon(Icons.add_box_outlined), tooltip: 'إنشاء', onPressed: () => openCreate(context)),
              Padding(
                padding: const EdgeInsetsDirectional.only(end: 10, start: 2),
                child: SocialAvatar(social.me, size: 30, onTap: () => openProfile(context, social.meId)),
              ),
            ],
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(48),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: SizedBox(
                  width: double.infinity,
                  child: SegmentedButton<PostKind>(
                    showSelectedIcon: false,
                    style: SegmentedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      foregroundColor: fg,
                      selectedForegroundColor: Colors.white,
                      selectedBackgroundColor: MindColors.violet,
                      side: BorderSide(color: reels ? Colors.white24 : MindColors.violet.withValues(alpha: 0.3)),
                    ),
                    segments: [
                      for (final k in PostKind.values)
                        ButtonSegment(value: k, label: Text('${k.emoji} ${k.label}', style: const TextStyle(fontSize: 13))),
                    ],
                    selected: {_section},
                    onSelectionChanged: (s) => setState(() => _section = s.first),
                  ),
                ),
              ),
            ),
          ),
          body: IndexedStack(
            index: _section.index,
            children: [
              ReelsView(active: playing),
              const PhotosView(),
              const PostsView(),
            ],
          ),
        );
      },
    );
  }
}
