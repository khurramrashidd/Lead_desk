import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// The design system for the whole product: colours, type, spacing, elevation.
///
/// Two families live together on purpose:
///  * **Institute** (navy + amber) — the SechTummit Trainers public website.
///  * **Product** (indigo + violet) — AI Lead Desk: chat, counsellor desk, admin.
class AppTheme {
  AppTheme._();

  // ----------------------------------------------------------------- palette
  /// Product brand (matches the app icon gradient).
  static const indigo = Color(0xFF4F46E5);
  static const indigoDeep = Color(0xFF4338CA);
  static const violet = Color(0xFF7C3AED);
  static const seed = indigo; // kept for older call sites

  /// Institute brand (public website).
  static const navy = Color(0xFF0B1F3A);
  static const navySoft = Color(0xFF14315A);
  static const amber = Color(0xFFF59E0B);
  static const amberDeep = Color(0xFFD97706);

  /// Status + meaning.
  static const hot = Color(0xFFE11D48);
  static const warm = Color(0xFFF59E0B);
  static const cold = Color(0xFF64748B);
  static const ai = Color(0xFF7C3AED);
  static const human = Color(0xFF059669);
  static const guard = Color(0xFFDC2626);
  static const success = Color(0xFF059669);
  static const info = Color(0xFF0284C7);

  static const brandGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [indigoDeep, violet],
  );
  static const heroGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF0B1F3A), Color(0xFF14315A), Color(0xFF2B2A7A)],
  );

  // ----------------------------------------------------------------- metrics
  static const r8 = 8.0, r12 = 12.0, r16 = 16.0, r20 = 20.0, r28 = 28.0;
  static const gapXs = 4.0, gapS = 8.0, gapM = 16.0, gapL = 24.0, gapXl = 40.0;

  /// Soft, wide shadow used for cards that need to lift off the page.
  static List<BoxShadow> lift(BuildContext context, {double y = 10, double blur = 30, double opacity = 0.08}) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return [
      BoxShadow(
        color: Colors.black.withValues(alpha: dark ? opacity * 2.4 : opacity),
        blurRadius: blur,
        offset: Offset(0, y),
      ),
    ];
  }

  /// Hairline border that replaces heavy elevation on flat surfaces.
  static Border hairline(BuildContext context, {Color? color}) =>
      Border.all(color: color ?? Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.7));

  static Color temperature(String? t) => switch (t) {
        'hot' => hot,
        'warm' => warm,
        _ => cold,
      };

  // ------------------------------------------------------------------ themes
  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final scheme = ColorScheme.fromSeed(
      seedColor: indigo,
      brightness: brightness,
    ).copyWith(
      primary: isDark ? const Color(0xFF9D96FF) : indigo,
      secondary: isDark ? const Color(0xFFFBBF24) : amberDeep,
      surface: isDark ? const Color(0xFF12131C) : Colors.white,
      surfaceContainerLowest: isDark ? const Color(0xFF0C0D14) : Colors.white,
      surfaceContainerLow: isDark ? const Color(0xFF14151F) : const Color(0xFFFAFAFD),
      surfaceContainer: isDark ? const Color(0xFF181925) : const Color(0xFFF4F4F9),
      surfaceContainerHigh: isDark ? const Color(0xFF1E1F2D) : const Color(0xFFEFEFF6),
      surfaceContainerHighest: isDark ? const Color(0xFF252637) : const Color(0xFFE9E9F2),
      outlineVariant: isDark ? const Color(0xFF2E3042) : const Color(0xFFE2E3EC),
      error: const Color(0xFFDC2626),
    );

    final base = ThemeData(colorScheme: scheme, useMaterial3: true);
    final text = _typography(base.textTheme, scheme);

    return base.copyWith(
      scaffoldBackgroundColor: isDark ? const Color(0xFF0C0D14) : const Color(0xFFF7F7FB),
      textTheme: text,
      splashFactory: InkSparkle.splashFactory,
      visualDensity: VisualDensity.standard,
      appBarTheme: AppBarThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        systemOverlayStyle: isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.surface,
        surfaceTintColor: Colors.transparent,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(r16),
          side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.8)),
        ),
      ),
      dividerTheme: DividerThemeData(color: scheme.outlineVariant, thickness: 1, space: 1),
      inputDecorationTheme: InputDecorationThemeData(
        filled: true,
        fillColor: isDark ? const Color(0xFF181925) : const Color(0xFFF4F4F9),
        hintStyle: TextStyle(color: scheme.onSurfaceVariant.withValues(alpha: 0.8)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(r12),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(r12),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(r12),
          borderSide: BorderSide(color: scheme.primary, width: 1.6),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(r12),
          borderSide: BorderSide(color: scheme.error),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(r12)),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15, letterSpacing: 0.1),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(r12)),
          side: BorderSide(color: scheme.outlineVariant),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(r8)),
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      chipTheme: ChipThemeData(
        side: BorderSide(color: scheme.outlineVariant),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
        labelStyle: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: scheme.onSurface),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(r12)),
      ),
      dialogTheme: DialogThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(r20)),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(r28))),
        showDragHandle: true,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surface,
        elevation: 0,
        height: 68,
        surfaceTintColor: Colors.transparent,
        indicatorColor: scheme.primary.withValues(alpha: 0.14),
        labelTextStyle: WidgetStatePropertyAll(
          TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: scheme.onSurface),
        ),
      ),
      tabBarTheme: TabBarThemeData(
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: scheme.outlineVariant,
        labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
        unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF2A2C3D) : const Color(0xFF1E1F2D),
          borderRadius: BorderRadius.circular(r8),
        ),
        textStyle: const TextStyle(color: Colors.white, fontSize: 12.5),
      ),
    );
  }

  static TextTheme _typography(TextTheme t, ColorScheme c) => t.copyWith(
        displayLarge: t.displayLarge?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -1.6, height: 1.05),
        displayMedium: t.displayMedium?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -1.2, height: 1.08),
        displaySmall: t.displaySmall?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.9, height: 1.12),
        headlineLarge: t.headlineLarge?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.8, height: 1.15),
        headlineMedium: t.headlineMedium?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.6, height: 1.2),
        headlineSmall: t.headlineSmall?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.4, height: 1.25),
        titleLarge: t.titleLarge?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.2),
        titleMedium: t.titleMedium?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.1),
        titleSmall: t.titleSmall?.copyWith(fontWeight: FontWeight.w600),
        bodyLarge: t.bodyLarge?.copyWith(height: 1.55, color: c.onSurface),
        bodyMedium: t.bodyMedium?.copyWith(height: 1.55, color: c.onSurfaceVariant),
        bodySmall: t.bodySmall?.copyWith(height: 1.45, color: c.onSurfaceVariant),
        labelLarge: t.labelLarge?.copyWith(fontWeight: FontWeight.w600, letterSpacing: 0.1),
      );
}

/// Small helpers used all over the UI.
extension ThemeX on BuildContext {
  ColorScheme get scheme => Theme.of(this).colorScheme;
  TextTheme get texts => Theme.of(this).textTheme;
  bool get isDark => Theme.of(this).brightness == Brightness.dark;
}
