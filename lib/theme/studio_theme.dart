import 'package:flutter/material.dart';

/// Shared typography and controls for Korean desktop and mobile screens.
ThemeData buildStudioTheme() {
  const background = Color(0xFF17191C);
  const surface = Color(0xFF202328);
  const foreground = Color(0xFFE9EBEF);
  const muted = Color(0xFFADB4BE);
  const outline = Color(0xFF41464F);
  const primary = Color(0xFFE2E8F0);
  const shape = RoundedRectangleBorder(
    borderRadius: BorderRadius.all(Radius.circular(8)),
  );
  const label = TextStyle(
    fontFamily: 'NotoSansKR',
    fontSize: 13,
    height: 1.3,
    letterSpacing: 0,
    fontWeight: FontWeight.w400,
    color: foreground,
  );
  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    fontFamily: 'NotoSansKR',
    scaffoldBackgroundColor: background,
    colorScheme: const ColorScheme.dark(
      primary: primary,
      onPrimary: Color(0xFF17191C),
      primaryContainer: Color(0xFF343A44),
      onPrimaryContainer: foreground,
      secondary: Color(0xFFFF9A57),
      onSecondary: Color(0xFF241005),
      secondaryContainer: Color(0xFF343A44),
      onSecondaryContainer: foreground,
      surface: surface,
      onSurface: foreground,
      onSurfaceVariant: muted,
      surfaceContainerHighest: Color(0xFF292D33),
      outline: outline,
      outlineVariant: Color(0xFF343941),
    ),
  );
  return base.copyWith(
    textTheme: base.textTheme
        .apply(bodyColor: foreground, displayColor: foreground)
        .copyWith(
          headlineSmall: const TextStyle(
            fontSize: 24,
            height: 1.35,
            fontWeight: FontWeight.w700,
            letterSpacing: 0,
            color: foreground,
          ),
          titleLarge: const TextStyle(
            fontSize: 20,
            height: 1.4,
            fontWeight: FontWeight.w700,
            letterSpacing: 0,
            color: foreground,
          ),
          titleMedium: const TextStyle(
            fontSize: 16,
            height: 1.4,
            fontWeight: FontWeight.w700,
            letterSpacing: 0,
            color: foreground,
          ),
          titleSmall: const TextStyle(
            fontSize: 14,
            height: 1.4,
            fontWeight: FontWeight.w700,
            letterSpacing: 0,
            color: foreground,
          ),
          bodyLarge: const TextStyle(
            fontSize: 15,
            height: 1.5,
            fontWeight: FontWeight.w400,
            letterSpacing: 0,
            color: foreground,
          ),
          bodyMedium: const TextStyle(
            fontSize: 14,
            height: 1.5,
            fontWeight: FontWeight.w400,
            letterSpacing: 0,
            color: foreground,
          ),
          bodySmall: const TextStyle(
            fontSize: 12,
            height: 1.5,
            color: muted,
            letterSpacing: 0,
          ),
          labelLarge: label,
          labelMedium: label.copyWith(fontSize: 12),
          labelSmall: label.copyWith(fontSize: 11),
        )
        .apply(fontFamily: 'NotoSansKR'),
    dividerTheme: const DividerThemeData(
      color: Color(0xFF343941),
      thickness: 1,
      space: 1,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: background,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontFamily: 'NotoSansKR',
        fontSize: 20,
        height: 1.4,
        fontWeight: FontWeight.w700,
        color: foreground,
        letterSpacing: 0,
      ),
    ),
    cardTheme: const CardThemeData(
      color: surface,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      margin: EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(10)),
        side: BorderSide(color: Color(0xFF343941)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      labelStyle: label.copyWith(color: muted),
      helperStyle: label.copyWith(fontSize: 12, color: muted),
      hintStyle: label.copyWith(color: muted),
      border: const OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(8)),
      ),
      enabledBorder: const OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(8)),
        borderSide: BorderSide(color: outline),
      ),
      focusedBorder: const OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(8)),
        borderSide: BorderSide(color: primary, width: 1.5),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(64, 42),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: shape,
        textStyle: label,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: foreground,
        minimumSize: const Size(64, 42),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        side: const BorderSide(color: outline),
        shape: shape,
        textStyle: label,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: foreground,
        minimumSize: const Size(48, 40),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        shape: shape,
        textStyle: label,
      ),
    ),
    chipTheme: ChipThemeData(
      shape: shape,
      side: const BorderSide(color: outline),
      backgroundColor: surface,
      selectedColor: const Color(0xFF343A44),
      labelStyle: label,
      secondaryLabelStyle: label.copyWith(
        color: foreground,
        fontWeight: FontWeight.w700,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      showCheckmark: false,
    ),
    tabBarTheme: TabBarThemeData(
      labelColor: foreground,
      unselectedLabelColor: muted,
      labelStyle: label.copyWith(fontSize: 14, fontWeight: FontWeight.w700),
      unselectedLabelStyle: label.copyWith(fontSize: 14),
      indicatorColor: primary,
      dividerColor: const Color(0xFF343941),
      indicatorSize: TabBarIndicatorSize.label,
    ),
    listTileTheme: const ListTileThemeData(
      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 6),
    ),
    tooltipTheme: TooltipThemeData(
      textStyle: label.copyWith(color: const Color(0xFF17191C)),
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: surface,
      indicatorColor: const Color(0xFF343A44),
      selectedIconTheme: const IconThemeData(color: foreground),
      unselectedIconTheme: const IconThemeData(color: muted),
      selectedLabelTextStyle: label.copyWith(fontWeight: FontWeight.w700),
      unselectedLabelTextStyle: label.copyWith(color: muted),
    ),
  );
}
