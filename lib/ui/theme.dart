import 'package:flutter/material.dart';

// Custom hues adapt to the selected mode so every surface remains readable.
Color appearanceSurface(int value, Brightness brightness) {
  final color = HSLColor.fromColor(Color(value));
  final lightness = brightness == Brightness.dark
      ? color.lightness.clamp(0.03, 0.20)
      : color.lightness.clamp(0.85, 0.98);
  return color.withLightness(lightness).toColor();
}

ThemeData vaultTheme(
  Brightness brightness,
  int accent, {
  int? background,
  int? surface,
}) {
  final dark = brightness == Brightness.dark;
  final seeded = ColorScheme.fromSeed(
    seedColor: Color(accent),
    brightness: brightness,
  );
  final bg = background == null
      ? (dark ? const Color(0xff101520) : const Color(0xfff5f5f2))
      : appearanceSurface(background, brightness);
  final panel = surface == null
      ? (dark ? const Color(0xff182130) : const Color(0xffeaece8))
      : appearanceSurface(surface, brightness);
  var primary = dark && Color(accent).computeLuminance() >= 0.2
      ? Color(accent)
      : seeded.primary;
  double contrast(Color a, Color b) {
    final x = a.computeLuminance(), y = b.computeLuminance();
    return (x > y ? (x + .05) / (y + .05) : (y + .05) / (x + .05));
  }

  for (
    var i = 0;
    i < 20 && (contrast(primary, bg) < 4.5 || contrast(primary, panel) < 4.5);
    i++
  ) {
    primary = Color.lerp(primary, dark ? Colors.white : Colors.black, .15)!;
  }
  final ink = dark ? Colors.white : const Color(0xff17191d);
  final scheme = seeded.copyWith(
    surface: bg,
    onSurface: ink,
    onSurfaceVariant: Color.lerp(ink, panel, .20),
    surfaceContainer: panel,
    surfaceContainerLow: panel,
    surfaceContainerHigh: panel,
    surfaceContainerHighest: Color.lerp(panel, ink, .04),
    primary: primary,
    onPrimary: primary.computeLuminance() > 0.179
        ? const Color(0xff101520)
        : Colors.white,
    outlineVariant: Color.lerp(panel, ink, .22),
  );
  final radius = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(10),
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    brightness: brightness,
    fontFamily: 'Segoe UI',
    scaffoldBackgroundColor: scheme.surface,
    visualDensity: VisualDensity.compact,
    textTheme: TextTheme(
      headlineLarge: TextStyle(
        fontSize: 32,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.8,
        color: scheme.onSurface,
      ),
      headlineMedium: TextStyle(
        fontSize: 25,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.5,
        color: scheme.onSurface,
      ),
      titleLarge: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        color: scheme.onSurface,
      ),
      titleMedium: TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        color: scheme.onSurface,
      ),
      bodyMedium: TextStyle(fontSize: 14, height: 1.5, color: scheme.onSurface),
      bodySmall: TextStyle(
        fontSize: 12,
        height: 1.4,
        color: scheme.onSurfaceVariant,
      ),
    ),
    dividerTheme: DividerThemeData(color: scheme.outlineVariant, space: 1),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: radius,
        minimumSize: const Size(0, 38),
        padding: const EdgeInsets.symmetric(horizontal: 18),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        shape: radius,
        minimumSize: const Size(0, 38),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        side: BorderSide(color: scheme.outlineVariant),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(shape: radius),
    ),
    inputDecorationTheme: InputDecorationTheme(
      isDense: true,
      filled: true,
      fillColor: scheme.surfaceContainer,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: scheme.primary, width: 1.5),
      ),
    ),
    dialogTheme: DialogThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      backgroundColor: scheme.surface,
    ),
    tooltipTheme: const TooltipThemeData(
      waitDuration: Duration(milliseconds: 450),
    ),
  );
}
