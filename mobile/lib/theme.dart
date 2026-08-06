import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

ThemeData buildRyadomTheme(Brightness brightness) {
  final isDark = brightness == Brightness.dark;
  final seed = const Color(0xFF1B6B3A);
  final scheme = ColorScheme.fromSeed(
    seedColor: seed,
    brightness: brightness,
    primary: isDark ? const Color(0xFF6BCB8B) : seed,
    surface: isDark ? const Color(0xFF121A14) : const Color(0xFFF4F7F2),
  );

  final textTheme = GoogleFonts.manropeTextTheme(
    isDark ? ThemeData.dark().textTheme : ThemeData.light().textTheme,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    textTheme: textTheme,
    scaffoldBackgroundColor: isDark ? const Color(0xFF0D1410) : const Color(0xFFEEF3EA),
    appBarTheme: AppBarTheme(
      centerTitle: false,
      elevation: 0,
      backgroundColor: Colors.transparent,
      foregroundColor: scheme.onSurface,
      titleTextStyle: GoogleFonts.unbounded(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        color: scheme.onSurface,
      ),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: isDark ? const Color(0xFF182118) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: isDark ? const Color(0xFF2A3A2E) : const Color(0xFFD5E0D0)),
      ),
      margin: EdgeInsets.zero,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: isDark ? const Color(0xFF182118) : Colors.white,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: isDark ? const Color(0xFF2A3A2E) : const Color(0xFFCDD8C8)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: scheme.primary, width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: GoogleFonts.manrope(fontWeight: FontWeight.w700),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: 68,
      indicatorColor: scheme.primary.withValues(alpha: 0.18),
      labelTextStyle: WidgetStatePropertyAll(GoogleFonts.manrope(fontSize: 12, fontWeight: FontWeight.w600)),
    ),
    chipTheme: ChipThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      side: BorderSide.none,
      selectedColor: scheme.primary.withValues(alpha: 0.2),
      backgroundColor: isDark ? const Color(0xFF223028) : const Color(0xFFE5F0E7),
      labelStyle: GoogleFonts.manrope(fontWeight: FontWeight.w600, fontSize: 13),
    ),
  );
}
