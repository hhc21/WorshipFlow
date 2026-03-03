import 'package:flutter/material.dart';

ThemeData buildAppTheme() {
  const baseSeed = Color(0xFF0E4E87);
  final colorScheme = ColorScheme.fromSeed(
    seedColor: baseSeed,
    brightness: Brightness.light,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: const Color(0xFFEFF3F8),
    fontFamilyFallback: const [
      'Apple SD Gothic Neo',
      'Noto Sans CJK KR',
      'Noto Sans KR',
      'Roboto',
    ],
    textTheme: const TextTheme(
      headlineSmall: TextStyle(fontWeight: FontWeight.w900),
      titleLarge: TextStyle(fontWeight: FontWeight.w800),
      titleMedium: TextStyle(fontWeight: FontWeight.w700, height: 1.25),
      titleSmall: TextStyle(fontWeight: FontWeight.w700, height: 1.2),
      bodyLarge: TextStyle(height: 1.45),
      bodyMedium: TextStyle(height: 1.45),
    ),
    appBarTheme: AppBarTheme(
      elevation: 0,
      shadowColor: colorScheme.shadow.withValues(alpha: 0.06),
      backgroundColor: const Color(0xFFF7FAFF),
      foregroundColor: colorScheme.onSurface,
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      shadowColor: colorScheme.shadow.withValues(alpha: 0.08),
      color: const Color(0xFFFFFFFF),
      surfaceTintColor: Colors.transparent,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: colorScheme.outlineVariant.withValues(alpha: 0.3),
        ),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: const Color(0xFFF7FAFF),
      isDense: true,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(
          color: colorScheme.outline.withValues(alpha: 0.3),
        ),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(
          color: colorScheme.outline.withValues(alpha: 0.3),
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: colorScheme.primary, width: 1.6),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: colorScheme.surfaceContainerHigh,
      side: BorderSide(
        color: colorScheme.outlineVariant.withValues(alpha: 0.32),
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      labelStyle: const TextStyle(fontWeight: FontWeight.w600),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        minimumSize: const Size(0, 46),
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 46),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        side: BorderSide(
          color: colorScheme.outlineVariant.withValues(alpha: 0.6),
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: const Size(0, 40),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 46),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
      ),
    ),
    snackBarTheme: const SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      showCloseIcon: true,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: const Color(0xFFFFFFFF),
      indicatorColor: colorScheme.primaryContainer.withValues(alpha: 0.85),
      height: 72,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          fontWeight: states.contains(WidgetState.selected)
              ? FontWeight.w800
              : FontWeight.w600,
        ),
      ),
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: const Color(0xFFF6F8FC),
      indicatorColor: colorScheme.primaryContainer.withValues(alpha: 0.88),
      selectedIconTheme: IconThemeData(color: colorScheme.primary),
      selectedLabelTextStyle: const TextStyle(fontWeight: FontWeight.w800),
      unselectedLabelTextStyle: const TextStyle(fontWeight: FontWeight.w600),
    ),
    dividerTheme: DividerThemeData(
      color: colorScheme.outlineVariant.withValues(alpha: 0.35),
      thickness: 1,
      space: 1,
    ),
  );
}
