import 'package:flutter/material.dart';

const accentLight = Color(0xFF0F766E);
const accentDark = Color(0xFF2DD4BF);

ThemeData buildTheme(Brightness b) {
  final dark = b == Brightness.dark;
  final bg = dark ? const Color(0xFF111312) : const Color(0xFFF6F7F6);
  final surface = dark ? const Color(0xFF1B1E1D) : Colors.white;
  final border = dark ? const Color(0xFF2C302F) : const Color(0xFFE4E7E5);
  final scheme = ColorScheme.fromSeed(
    seedColor: accentLight,
    brightness: b,
    primary: dark ? accentDark : accentLight,
    onPrimary: dark ? const Color(0xFF042420) : Colors.white,
    surface: surface,
  );
  final base = ThemeData(useMaterial3: true, colorScheme: scheme, fontFamily: 'Plex');
  final rounded = RoundedRectangleBorder(borderRadius: BorderRadius.circular(14));
  return base.copyWith(
    scaffoldBackgroundColor: bg,
    textTheme: base.textTheme.apply(
      bodyColor: dark ? const Color(0xFFE8EBE9) : const Color(0xFF17201D),
      displayColor: dark ? const Color(0xFFE8EBE9) : const Color(0xFF17201D),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: bg,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: true,
      titleTextStyle: TextStyle(
        fontFamily: 'Plex',
        fontSize: 17,
        fontWeight: FontWeight.w600,
        color: dark ? const Color(0xFFE8EBE9) : const Color(0xFF17201D),
      ),
    ),
    drawerTheme: DrawerThemeData(backgroundColor: surface, surfaceTintColor: Colors.transparent),
    dialogTheme: DialogThemeData(
      backgroundColor: surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: surface,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: border)),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: rounded,
      contentTextStyle: const TextStyle(fontFamily: 'Plex', fontSize: 14),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: rounded,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        textStyle: const TextStyle(fontFamily: 'Plex', fontWeight: FontWeight.w600, fontSize: 15),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(shape: rounded, textStyle: const TextStyle(fontFamily: 'Plex', fontWeight: FontWeight.w600)),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        side: BorderSide(color: border),
        textStyle: const TextStyle(fontFamily: 'Plex', fontWeight: FontWeight.w500),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: dark ? const Color(0xFF232726) : const Color(0xFFF1F3F2),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: scheme.primary, width: 1.4),
      ),
    ),
    listTileTheme: ListTileThemeData(shape: rounded),
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
    }),
    dividerColor: border,
    dividerTheme: DividerThemeData(color: border, space: 1, thickness: 1),
  );
}

extension Palette on BuildContext {
  bool get isDark => Theme.of(this).brightness == Brightness.dark;
  Color get border => isDark ? const Color(0xFF2C302F) : const Color(0xFFE4E7E5);
  Color get muted => isDark ? const Color(0xFF9AA19E) : const Color(0xFF66706C);
  Color get surface2 => isDark ? const Color(0xFF232726) : const Color(0xFFF1F3F2);
  Color get userBubble => isDark ? const Color(0xFF15403A) : const Color(0xFF0F766E);
  Color get onUserBubble => isDark ? const Color(0xFFE6FFFA) : Colors.white;
  Color get danger => isDark ? const Color(0xFFFF8A7A) : const Color(0xFFB42318);
  Color get warn => isDark ? const Color(0xFFF5C451) : const Color(0xFF9A6700);
}
