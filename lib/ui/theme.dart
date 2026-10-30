import 'package:flutter/material.dart';

const accentLight = Color(0xFF0F766E);
const accentDark = Color(0xFF2DD4BF);

ThemeData buildTheme(Brightness b) {
  final dark = b == Brightness.dark;
  final scheme = ColorScheme.fromSeed(
    seedColor: accentLight,
    brightness: b,
    primary: dark ? accentDark : accentLight,
    onPrimary: dark ? const Color(0xFF062521) : Colors.white,
    surface: dark ? const Color(0xFF1F201F) : Colors.white,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: dark ? const Color(0xFF161716) : const Color(0xFFF7F7F5),
    appBarTheme: AppBarTheme(
      backgroundColor: dark ? const Color(0xFF161716) : const Color(0xFFF7F7F5),
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
    ),
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
    }),
    dividerColor: dark ? const Color(0xFF343634) : const Color(0xFFE3E3DF),
  );
}

extension Palette on BuildContext {
  bool get isDark => Theme.of(this).brightness == Brightness.dark;
  Color get border => isDark ? const Color(0xFF343634) : const Color(0xFFE3E3DF);
  Color get muted => isDark ? const Color(0xFFA2A39E) : const Color(0xFF6B6B66);
  Color get surface2 => isDark ? const Color(0xFF2A2B2A) : const Color(0xFFF0F0ED);
  Color get userBubble => isDark ? const Color(0xFF23332F) : const Color(0xFFE8F1EF);
  Color get danger => isDark ? const Color(0xFFFF8A7A) : const Color(0xFFB42318);
  Color get warn => isDark ? const Color(0xFFF5C451) : const Color(0xFF9A6700);
}
