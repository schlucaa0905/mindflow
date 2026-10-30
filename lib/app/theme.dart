import 'package:flutter/material.dart';

/// Design-Tokens: alle Farben zentral, damit der helle Modus und spätere
/// Anpassungen an einer Stelle passieren.
abstract final class MfColors {
  static const background = Color(0xFF15151A);
  static const surface = Color(0xFF1E1E25);
  static const surfaceRaised = Color(0xFF26262F);
  static const border = Color(0xFF30303B);
  static const text = Color(0xFFEDEDF2);
  static const textMuted = Color(0xFF9A9AA8);
  static const accent = Color(0xFF8B7CF6);

  static const inkPalette = <Color>[
    Color(0xFFEDEDF2),
    Color(0xFF8B7CF6),
    Color(0xFF5AA9FF),
    Color(0xFF4ADE80),
    Color(0xFFF87171),
  ];

  static const highlighterPalette = <Color>[
    Color(0xFFFACC15),
    Color(0xFF4ADE80),
    Color(0xFFF472B6),
    Color(0xFF5AA9FF),
  ];
}

ThemeData buildDarkTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: MfColors.accent,
    brightness: Brightness.dark,
  ).copyWith(
    primary: MfColors.accent,
    surface: MfColors.surface,
    onSurface: MfColors.text,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: MfColors.background,
    dividerColor: MfColors.border,
    tooltipTheme: const TooltipThemeData(waitDuration: Duration(milliseconds: 600)),
  );
}
