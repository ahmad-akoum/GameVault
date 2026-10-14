import 'package:flutter/material.dart';

ThemeData vaultTheme(Brightness brightness, int accent) {
  final dark = brightness == Brightness.dark;
  final seeded = ColorScheme.fromSeed(
    seedColor: Color(accent),
    brightness: brightness,
  );
  final primary = dark && Color(accent).computeLuminance() >= 0.2
      ? Color(accent)
      : seeded.primary;
  final scheme = seeded.copyWith(
    surface: dark ? const Color(0xff101520) : const Color(0xfff5f5f2),
    onSurface: dark ? const Color(0xffe7e8eb) : const Color(0xff22252a),
    onSurfaceVariant: dark ? const Color(0xffa0a5ae) : const Color(0xff5b626a),
    surfaceContainer: dark ? const Color(0xff182130) : const Color(0xffeaece8),
    surfaceContainerHighest: dark
        ? const Color(0xff202c3d)
        : const Color(0xffe0e3dd),
    primary: primary,
    onPrimary: primary.computeLuminance() > 0.179
        ? const Color(0xff101520)
        : Colors.white,
    outlineVariant: dark ? const Color(0xff2b384b) : const Color(0xffd4d8d1),
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
