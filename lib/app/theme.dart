import 'package:flutter/material.dart';

/// Bright, Dola-style palette: violet → pink → orange gradients on a clean white canvas.
class MindColors {
  static const violet = Color(0xFF7B5CFF);
  static const pink = Color(0xFFFF4FA3);
  static const orange = Color(0xFFFF9F43);
  static const cyan = Color(0xFF2BD9FE);
  static const mint = Color(0xFF2EE6A6);
  static const ink = Color(0xFF1B1530);
  static const muted = Color(0xFF8A84A3);
  static const canvas = Color(0xFFF7F5FF);
  static const card = Colors.white;

  static const brand = LinearGradient(
    colors: [violet, pink, orange],
    begin: Alignment.topRight,
    end: Alignment.bottomLeft,
  );

  static const cool = LinearGradient(
    colors: [cyan, violet],
    begin: Alignment.topRight,
    end: Alignment.bottomLeft,
  );

  static const fresh = LinearGradient(
    colors: [mint, cyan],
    begin: Alignment.topRight,
    end: Alignment.bottomLeft,
  );

  static const sunset = LinearGradient(
    colors: [orange, pink],
    begin: Alignment.topRight,
    end: Alignment.bottomLeft,
  );
}

ThemeData buildTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final scheme = ColorScheme.fromSeed(
    seedColor: MindColors.violet,
    brightness: brightness,
    primary: MindColors.violet,
    secondary: MindColors.pink,
    tertiary: MindColors.orange,
    surface: dark ? const Color(0xFF14111F) : MindColors.canvas,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: true,
      foregroundColor: dark ? Colors.white : MindColors.ink,
      titleTextStyle: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w800,
        color: dark ? Colors.white : MindColors.ink,
      ),
    ),
    cardTheme: CardThemeData(
      color: dark ? const Color(0xFF1E1A2E) : MindColors.card,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: dark ? const Color(0xFF1E1A2E) : Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide.none,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        textStyle: TextStyle(fontWeight: FontWeight.w700),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: dark ? const Color(0xFF1E1A2E) : Colors.white,
      indicatorColor: MindColors.violet.withValues(alpha: 0.14),
      labelTextStyle: WidgetStateProperty.all(
        TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
      ),
    ),
  );
}
