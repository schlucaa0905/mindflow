import 'package:flutter/material.dart';

/// Design-Tokens. Jede Farbe der Oberfläche kommt von hier, damit
/// hell und dunkel vollständig funktionieren.
@immutable
class MfPalette extends ThemeExtension<MfPalette> {
  const MfPalette({
    required this.background,
    required this.surface,
    required this.surfaceRaised,
    required this.border,
    required this.text,
    required this.textMuted,
    required this.accent,
    required this.accentSoft,
    required this.danger,
  });

  final Color background;
  final Color surface;
  final Color surfaceRaised;
  final Color border;
  final Color text;
  final Color textMuted;
  final Color accent;
  final Color accentSoft;
  final Color danger;

  static const dark = MfPalette(
    background: Color(0xFF15151A),
    surface: Color(0xFF1C1C22),
    surfaceRaised: Color(0xFF25252D),
    border: Color(0xFF2E2E38),
    text: Color(0xFFEDEDF2),
    textMuted: Color(0xFF9A9AA8),
    accent: Color(0xFF8B7CF6),
    accentSoft: Color(0x2E8B7CF6),
    danger: Color(0xFFF87171),
  );

  static const light = MfPalette(
    background: Color(0xFFF5F5F7),
    surface: Color(0xFFFFFFFF),
    surfaceRaised: Color(0xFFF0F0F4),
    border: Color(0xFFE2E2E8),
    text: Color(0xFF1C1C22),
    textMuted: Color(0xFF6B6B78),
    accent: Color(0xFF6D5DE7),
    accentSoft: Color(0x226D5DE7),
    danger: Color(0xFFDC2626),
  );

  @override
  MfPalette copyWith() => this;

  @override
  MfPalette lerp(ThemeExtension<MfPalette>? other, double t) {
    if (other is! MfPalette) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return MfPalette(
      background: l(background, other.background),
      surface: l(surface, other.surface),
      surfaceRaised: l(surfaceRaised, other.surfaceRaised),
      border: l(border, other.border),
      text: l(text, other.text),
      textMuted: l(textMuted, other.textMuted),
      accent: l(accent, other.accent),
      accentSoft: l(accentSoft, other.accentSoft),
      danger: l(danger, other.danger),
    );
  }
}

extension MfContext on BuildContext {
  MfPalette get mf => Theme.of(this).extension<MfPalette>()!;
}

ThemeData buildTheme(Brightness brightness) {
  final p = brightness == Brightness.dark ? MfPalette.dark : MfPalette.light;
  final scheme = ColorScheme.fromSeed(
    seedColor: p.accent,
    brightness: brightness,
  ).copyWith(
    primary: p.accent,
    surface: p.surface,
    onSurface: p.text,
    error: p.danger,
  );
  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: p.background,
    dividerColor: p.border,
    extensions: [p],
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: p.surfaceRaised,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: p.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: p.border),
      ),
    ),
    tooltipTheme:
        const TooltipThemeData(waitDuration: Duration(milliseconds: 600)),
  );
}

/// Papier einer Seite oder Arbeitsfläche – unabhängig vom App-Thema,
/// damit Handschrift nie unsichtbar wird, wenn man das Thema wechselt.
enum Paper { dark, light }

class PaperStyle {
  const PaperStyle({
    required this.desk,
    required this.sheet,
    required this.line,
    required this.ink,
    required this.highlighter,
  });

  /// Hintergrund um das Blatt herum.
  final Color desk;

  /// Farbe des Blattes.
  final Color sheet;

  /// Linien, Raster, Punkte.
  final Color line;

  final List<Color> ink;
  final List<Color> highlighter;

  static const dark = PaperStyle(
    desk: Color(0xFF111115),
    sheet: Color(0xFF1C1C22),
    line: Color(0xFF30303B),
    ink: [
      Color(0xFFEDEDF2),
      Color(0xFF8B7CF6),
      Color(0xFF5AA9FF),
      Color(0xFF4ADE80),
      Color(0xFFF87171),
    ],
    highlighter: [
      Color(0xFFFACC15),
      Color(0xFF4ADE80),
      Color(0xFFF472B6),
      Color(0xFF5AA9FF),
    ],
  );

  static const light = PaperStyle(
    desk: Color(0xFFE9E9ED),
    sheet: Color(0xFFFCFCFA),
    line: Color(0xFFDCDCE3),
    ink: [
      Color(0xFF1C1C22),
      Color(0xFF6D5DE7),
      Color(0xFF2563EB),
      Color(0xFF16A34A),
      Color(0xFFDC2626),
    ],
    highlighter: [
      Color(0xFFFACC15),
      Color(0xFF4ADE80),
      Color(0xFFF472B6),
      Color(0xFF60A5FA),
    ],
  );

  static PaperStyle of(Paper p) => p == Paper.dark ? dark : light;
}
