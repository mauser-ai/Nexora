import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Palette e tema condivisi per Nexora.
abstract class GussoniBrand {
  // ─────────────────────────────────────────────
  // Core brand (personalizzabile dalle impostazioni)
  // ─────────────────────────────────────────────
  static const Color defaultPrimary = Color(0xFF00332A);

  static Color primary = defaultPrimary;
  static Color primaryHover = const Color(0xFF0A4D40);
  static Color primaryDark = const Color(0xFF02231D);
  static Color primaryBg = const Color(0xFFF2F7F5);
  static Color primaryBorder = const Color(0xFF8DB9AF);
  static const Color accent = Color(0xFFACCF78);
  static const Color light = Color(0xFFF7F7F7);

  /// Notifica i listener (es. MaterialApp) quando cambia il colore brand.
  static final ValueNotifier<int> themeRevision = ValueNotifier<int>(0);
  static Color? _appliedAccent;

  /// Applica un nuovo colore primario e ricalcola le tonalità derivate.
  static void applyAccent(Color? accent) {
    final seed = accent ?? defaultPrimary;
    if (_appliedAccent == seed) return;
    _appliedAccent = seed;
    if (seed == defaultPrimary) {
      primary = defaultPrimary;
      primaryHover = const Color(0xFF0A4D40);
      primaryDark = const Color(0xFF02231D);
      primaryBg = const Color(0xFFF2F7F5);
      primaryBorder = const Color(0xFF8DB9AF);
    } else {
      final hsl = HSLColor.fromColor(seed);
      primary = seed;
      primaryHover = hsl
          .withLightness((hsl.lightness + .10).clamp(0.0, 1.0))
          .toColor();
      primaryDark = hsl
          .withLightness((hsl.lightness - .14).clamp(0.0, 1.0))
          .toColor();
      primaryBg = hsl.withLightness(.95).toColor();
      primaryBorder = hsl.withLightness(.76).toColor();
    }
    themeRevision.value += 1;
  }

  // ─────────────────────────────────────────────
  // Palette app Nexora
  // ─────────────────────────────────────────────
  static const Color scaffoldBg = Color(0xFFF7F7F7);
  static const Color surface = Color(0xFFFDFDFD);
  static const Color surfaceSubtle = Color(0xFFF4F7F5);
  static const Color surfaceMuted = Color(0xFFE8EFEC);
  static const Color glassSurface = Color(0xD9F7F7F7);
  static const Color glassSurfaceStrong = Color(0xEEF7F7F7);
  static const Color glassSurfaceMuted = Color(0xCCEDF3F0);
  static const Color glassDark = Color(0xCC02332A);

  static const Color border = Color(0xFFD4E1DC);
  static const Color borderSubtle = Color(0xFFE4ECE8);
  static const Color divider = Color(0xFFDCE7E2);

  // ─────────────────────────────────────────────
  // Testi
  // ─────────────────────────────────────────────
  static const Color textPrimary = Color(0xFF02332A);
  static const Color textSecondary = Color(0xFF31564F);
  static const Color textMuted = Color(0xFF6B847E);
  static const Color textDisabled = Color(0xFFA9BBB6);

  // ─────────────────────────────────────────────
  // Sidebar
  // ─────────────────────────────────────────────
  static const Color sidebarBg = Color(0xFF02332A);
  static const Color sidebarColor = sidebarBg; // alias compat
  static const Color sidebarActive = Color(0xFF0A4D40);
  static const Color sidebarText = Color(0xFFF7F7F7);
  static const Color sidebarMuted = Color(0xFFB6CAC5);
  static const Color sidebarBorder = Color(0xFF1E5A50);

  // ─────────────────────────────────────────────
  // Accenti
  // ─────────────────────────────────────────────
  static const Color gold = accent;
  static const Color goldBg = Color(0xFFF1F8E7);
  static const Color tan = accent;

  // ─────────────────────────────────────────────
  // Status
  // ─────────────────────────────────────────────
  static const Color success = Color(0xFF1F7A55);
  static const Color successBg = Color(0xFFE8F5EE);
  static const Color successBorder = Color(0xFFA8D5BC);

  static const Color error = Color(0xFFB43D34);
  static const Color errorBg = Color(0xFFFCEDEB);
  static const Color errorBorder = Color(0xFFE7B3AD);

  static const Color warning = Color(0xFF9B7A17);
  static const Color warningBg = Color(0xFFF9F4DE);
  static const Color warningBorder = Color(0xFFE1D08D);

  static const Color info = Color(0xFF2E6F7E);
  static const Color infoBg = Color(0xFFEAF5F7);
  static const Color infoBorder = Color(0xFFB8D6DC);

  // ─────────────────────────────────────────────
  // Logo
  // ─────────────────────────────────────────────
  static const String logoWhitePath =
      'assets/branding/nexora_wordmark_default.png';

  /// Il nome resta "glass" per compatibilità con i molti call-site.
  static BoxDecoration glassPanel({
    double radius = 14,
    Color? accent,
    double opacity = 1,
  }) {
    return BoxDecoration(
      borderRadius: BorderRadius.circular(radius),
      color: (accent ?? glassSurfaceStrong).withOpacity(opacity.clamp(0, 1)),
      border: Border.all(color: border.withOpacity(.9)),
      boxShadow: const [
        BoxShadow(
          color: Color(0x1402332A),
          blurRadius: 24,
          offset: Offset(0, 10),
        ),
      ],
    );
  }

  static BoxDecoration glassField({double radius = 10}) {
    return BoxDecoration(
      borderRadius: BorderRadius.circular(radius),
      color: surface,
      border: Border.all(color: border),
    );
  }

  // ─────────────────────────────────────────────
  // Tipografia
  // ─────────────────────────────────────────────
  static TextTheme buildTextTheme() => TextTheme(
    displayLarge: GoogleFonts.montserrat(
      fontSize: 57,
      fontWeight: FontWeight.w600,
      color: textPrimary,
    ),
    displayMedium: GoogleFonts.montserrat(
      fontSize: 45,
      fontWeight: FontWeight.w600,
      color: textPrimary,
    ),
    displaySmall: GoogleFonts.montserrat(
      fontSize: 36,
      fontWeight: FontWeight.w600,
      color: textPrimary,
    ),
    headlineLarge: GoogleFonts.montserrat(
      fontSize: 32,
      fontWeight: FontWeight.w600,
      color: textPrimary,
    ),
    headlineMedium: GoogleFonts.montserrat(
      fontSize: 26,
      fontWeight: FontWeight.w600,
      color: textPrimary,
    ),
    headlineSmall: GoogleFonts.montserrat(
      fontSize: 22,
      fontWeight: FontWeight.w600,
      color: textPrimary,
    ),
    titleLarge: GoogleFonts.montserrat(
      fontSize: 18,
      fontWeight: FontWeight.w600,
      color: textPrimary,
    ),
    titleMedium: GoogleFonts.montserrat(
      fontSize: 15,
      fontWeight: FontWeight.w600,
      color: textPrimary,
    ),
    titleSmall: GoogleFonts.montserrat(
      fontSize: 13,
      fontWeight: FontWeight.w600,
      color: textPrimary,
    ),
    bodyLarge: GoogleFonts.montserrat(
      fontSize: 15,
      fontWeight: FontWeight.w400,
      color: textPrimary,
    ),
    bodyMedium: GoogleFonts.montserrat(
      fontSize: 13,
      fontWeight: FontWeight.w400,
      color: textPrimary,
    ),
    bodySmall: GoogleFonts.montserrat(
      fontSize: 12,
      fontWeight: FontWeight.w400,
      color: textSecondary,
    ),
    labelLarge: GoogleFonts.montserrat(
      fontSize: 13,
      fontWeight: FontWeight.w600,
      color: textPrimary,
    ),
    labelMedium: GoogleFonts.montserrat(
      fontSize: 12,
      fontWeight: FontWeight.w500,
      color: textSecondary,
    ),
    labelSmall: GoogleFonts.montserrat(
      fontSize: 11,
      fontWeight: FontWeight.w500,
      color: textMuted,
    ),
  );

  // ─────────────────────────────────────────────
  // ThemeData completo
  // ─────────────────────────────────────────────
  static ThemeData buildTheme() {
    final tt = buildTextTheme();
    final cs = ColorScheme(
      brightness: Brightness.light,
      primary: primary,
      onPrimary: Colors.white,
      primaryContainer: primaryBg,
      onPrimaryContainer: primaryDark,
      secondary: gold,
      onSecondary: Colors.white,
      secondaryContainer: goldBg,
      onSecondaryContainer: Color(0xFF5C4413),
      tertiary: success,
      onTertiary: Colors.white,
      tertiaryContainer: successBg,
      onTertiaryContainer: Color(0xFF1E4A30),
      error: error,
      onError: Colors.white,
      errorContainer: errorBg,
      onErrorContainer: Color(0xFF7F1D1D),
      surface: surface,
      onSurface: textPrimary,
      onSurfaceVariant: textSecondary,
      outline: border,
      outlineVariant: borderSubtle,
      shadow: Colors.black,
      scrim: Colors.black,
      inverseSurface: sidebarBg,
      onInverseSurface: sidebarText,
      inversePrimary: primaryHover,
      surfaceContainerHighest: surfaceMuted,
      surfaceContainerHigh: surfaceSubtle,
      surfaceContainer: surface,
      surfaceContainerLow: scaffoldBg,
      surfaceContainerLowest: scaffoldBg,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: cs,
      scaffoldBackgroundColor: Colors.transparent,
      textTheme: tt,

      appBarTheme: AppBarTheme(
        backgroundColor: glassSurfaceStrong,
        foregroundColor: textPrimary,
        elevation: 0,
        scrolledUnderElevation: 1,
        shadowColor: border,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: GoogleFonts.montserrat(
          fontSize: 17,
          fontWeight: FontWeight.w700,
          color: textPrimary,
        ),
        iconTheme: const IconThemeData(color: textSecondary),
      ),

      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: border, width: 1),
        ),
        margin: EdgeInsets.zero,
      ),

      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          disabledBackgroundColor: border,
          textStyle: GoogleFonts.montserrat(
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          elevation: 0,
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: textPrimary,
          textStyle: GoogleFonts.montserrat(
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
          side: const BorderSide(color: border, width: 1),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primary,
          textStyle: GoogleFonts.montserrat(
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: primary, width: 1.4),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: error),
        ),
        labelStyle: GoogleFonts.montserrat(color: textMuted, fontSize: 13),
        hintStyle: GoogleFonts.montserrat(color: textDisabled, fontSize: 13),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
        isDense: true,
      ),

      dividerTheme: const DividerThemeData(
        color: divider,
        thickness: 1,
        space: 1,
      ),

      chipTheme: ChipThemeData(
        backgroundColor: surface,
        selectedColor: primaryBg,
        labelStyle: GoogleFonts.montserrat(fontSize: 12, color: textPrimary),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        side: const BorderSide(color: border),
      ),

      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? primary : null,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(3)),
      ),

      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? primary : null,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? primaryBorder : null,
        ),
      ),

      progressIndicatorTheme: ProgressIndicatorThemeData(color: primary),

      listTileTheme: ListTileThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        tileColor: Colors.transparent,
      ),

      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: border),
        ),
        titleTextStyle: GoogleFonts.montserrat(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: textPrimary,
        ),
        contentTextStyle: GoogleFonts.montserrat(
          fontSize: 14,
          color: textSecondary,
        ),
        elevation: 0,
      ),

      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: sidebarBg,
        contentTextStyle: GoogleFonts.montserrat(
          color: sidebarText,
          fontSize: 13,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),

      tabBarTheme: TabBarThemeData(
        labelColor: primary,
        unselectedLabelColor: textMuted,
        indicatorColor: primary,
        dividerColor: divider,
        labelStyle: GoogleFonts.montserrat(
          fontWeight: FontWeight.w700,
          fontSize: 13,
        ),
        unselectedLabelStyle: GoogleFonts.montserrat(
          fontWeight: FontWeight.w500,
          fontSize: 13,
        ),
      ),

      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: sidebarBg,
          borderRadius: BorderRadius.circular(6),
        ),
        textStyle: GoogleFonts.montserrat(color: sidebarText, fontSize: 12),
      ),

      popupMenuTheme: PopupMenuThemeData(
        color: surface,
        surfaceTintColor: Colors.transparent,
        elevation: 3,
        shadowColor: Colors.black.withValues(alpha: .35),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: border),
        ),
        textStyle: GoogleFonts.montserrat(color: textPrimary, fontSize: 13),
      ),

      dropdownMenuTheme: DropdownMenuThemeData(
        menuStyle: MenuStyle(
          backgroundColor: const WidgetStatePropertyAll(surface),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          elevation: const WidgetStatePropertyAll(3),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: const BorderSide(color: border),
            ),
          ),
        ),
      ),

      dataTableTheme: DataTableThemeData(
        headingRowColor: const WidgetStatePropertyAll(surface),
        dataRowColor: WidgetStateProperty.resolveWith((s) {
          if (s.contains(WidgetState.selected)) return primaryBg;
          return surface;
        }),
        headingTextStyle: GoogleFonts.montserrat(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: textMuted,
          letterSpacing: 0.8,
        ),
        dataTextStyle: GoogleFonts.montserrat(fontSize: 13, color: textPrimary),
        dividerThickness: 1,
        columnSpacing: 24,
        horizontalMargin: 16,
        headingRowHeight: 44,
        dataRowMinHeight: 48,
        dataRowMaxHeight: 58,
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Utility functions
// ─────────────────────────────────────────────

Color? hexToColor(String? hex) {
  if (hex == null || hex.isEmpty) return null;
  try {
    final h = hex.replaceAll('#', '');
    if (h.length == 6) return Color(int.parse('FF$h', radix: 16));
  } catch (_) {}
  return null;
}

String colorToHex(Color c) {
  final v = c.toARGB32();
  return '#${(v & 0x00FFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';
}
