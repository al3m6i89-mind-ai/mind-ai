import 'package:flutter/material.dart';

import '../features/code/projects_screen.dart';
import '../features/home/home_screen.dart';
import '../features/studio/creations_screen.dart';
import '../features/studio/studio_screen.dart';

/// Bottom navigation: Home (chat), Studio (media), Code (app builder), My creations.
class Shell extends StatefulWidget {
  const Shell({super.key});

  static void goTo(BuildContext context, int tab) =>
      context.findAncestorStateOfType<_ShellState>()?.setTab(tab);

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int _tab = 0;

  void setTab(int i) => setState(() => _tab = i);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _tab,
        children: const [HomeScreen(), StudioScreen(), ProjectsScreen(), CreationsScreen()],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: setTab,
        destinations: const [
          NavigationDestination(icon: Icon(Icons.chat_bubble_outline), selectedIcon: Icon(Icons.chat_bubble), label: 'الرئيسية'),
          NavigationDestination(icon: Icon(Icons.auto_awesome_outlined), selectedIcon: Icon(Icons.auto_awesome), label: 'الاستوديو'),
          NavigationDestination(icon: Icon(Icons.code_rounded), selectedIcon: Icon(Icons.terminal_rounded), label: 'الأكواد'),
          NavigationDestination(icon: Icon(Icons.photo_library_outlined), selectedIcon: Icon(Icons.photo_library), label: 'إبداعاتي'),
        ],
      ),
    );
  }
}
