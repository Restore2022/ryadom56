import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

ThemeData buildRyadomTheme(Brightness brightness) {
  final isDark = brightness == Brightness.dark;
  final seed = const Color(0xFF1B6B3A);
  final scheme = ColorScheme.fromSeed(
    seedColor: seed,
    brightness: brightness,
    primary: isDark ? const Color(0xFF6BCB8B) : seed,
    surface: isDark ? const Color(0xFF152018) : const Color(0xFFF4F7F2),
  );

  final chipBg = isDark ? const Color(0xFF2A3B30) : Colors.white;
  final chipSelectedBg = isDark ? const Color(0xFF3D8A58) : const Color(0xFF1B6B3A);
  final chipBorder = isDark ? const Color(0xFF5C7A66) : const Color(0xFFB7C9B8);
  final chipLabel = isDark ? const Color(0xFFEEF6EF) : const Color(0xFF1C2B1F);
  final chipSelectedLabel = isDark ? const Color(0xFFFFFFFF) : Colors.white;

  final textTheme = GoogleFonts.manropeTextTheme(
    isDark ? ThemeData.dark().textTheme : ThemeData.light().textTheme,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    textTheme: textTheme,
    scaffoldBackgroundColor: isDark ? const Color(0xFF0B100D) : const Color(0xFFEEF3EA),
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
      color: isDark ? const Color(0xFF1E2C22) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: isDark ? const Color(0xFF4A6354) : const Color(0xFFD5E0D0)),
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
      backgroundColor: isDark ? const Color(0xFF152018) : const Color(0xFFF4F7F2),
      indicatorColor: scheme.primary.withValues(alpha: isDark ? 0.28 : 0.18),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return IconThemeData(
          color: selected ? scheme.primary : (isDark ? const Color(0xFFC5D6C8) : scheme.onSurfaceVariant),
        );
      }),
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return GoogleFonts.manrope(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: selected ? scheme.primary : (isDark ? const Color(0xFFC5D6C8) : scheme.onSurfaceVariant),
        );
      }),
    ),
    chipTheme: ChipThemeData(
      showCheckmark: false,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      side: BorderSide(color: chipBorder),
      backgroundColor: chipBg,
      selectedColor: chipSelectedBg,
      disabledColor: chipBg,
      secondarySelectedColor: chipSelectedBg,
      labelStyle: GoogleFonts.manrope(fontWeight: FontWeight.w700, fontSize: 13, color: chipLabel),
      secondaryLabelStyle: GoogleFonts.manrope(fontWeight: FontWeight.w700, fontSize: 13, color: chipSelectedLabel),
      color: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return chipSelectedBg;
        return chipBg;
      }),
    ),
  );
}
