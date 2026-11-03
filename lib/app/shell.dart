import 'package:flutter/material.dart';

import '../features/code/projects_screen.dart';
import '../features/home/home_screen.dart';
import '../features/social/social_home.dart';
import '../features/studio/creations_screen.dart';
import '../features/studio/studio_screen.dart';

/// Bottom navigation: Home (chat), Community (reels, photos, posts), Studio (media),
/// Code (app builder), My creations.
class Shell extends StatefulWidget {
  const Shell({super.key});

  /// The tab showing now, so screens (like reels) can pause when hidden.
  static final current = ValueNotifier<int>(0);

  static void goTo(BuildContext context, int tab) => context.findAncestorStateOfType<_ShellState>()?.setTab(tab);

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    Shell.current.value = 0;
  }

  void setTab(int i) {
    Shell.current.value = i;
    setState(() => _tab = i);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _tab,
        children: const [HomeScreen(), SocialHome(tabIndex: 1), StudioScreen(), ProjectsScreen(), CreationsScreen()],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: setTab,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.chat_bubble_outline),
            selectedIcon: Icon(Icons.chat_bubble),
            label: 'الرئيسية',
          ),
          NavigationDestination(
            icon: Icon(Icons.people_alt_outlined),
            selectedIcon: Icon(Icons.people_alt),
            label: 'مجتمع',
          ),
          NavigationDestination(
            icon: Icon(Icons.auto_awesome_outlined),
            selectedIcon: Icon(Icons.auto_awesome),
            label: 'الاستوديو',
          ),
          NavigationDestination(
            icon: Icon(Icons.code_rounded),
            selectedIcon: Icon(Icons.terminal_rounded),
            label: 'الأكواد',
          ),
          NavigationDestination(
            icon: Icon(Icons.photo_library_outlined),
            selectedIcon: Icon(Icons.photo_library),
            label: 'إبداعاتي',
          ),
        ],
      ),
    );
  }
}
