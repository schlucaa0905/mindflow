import 'package:flutter/material.dart';

/// Design-Tokens. Jede Farbe der Oberfläche kommt von hier, damit
/// hell und dunkel vollständig funktionieren.
///
/// Stil: „Deep Space“ – fast schwarzes Blau, violett-cyanfarbene Verläufe,
/// gläserne Flächen mit feinen hellen Kanten.
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
    required this.accent2,
    required this.accentSoft,
    required this.danger,
    required this.success,
    required this.glass,
    required this.glassEdge,
    required this.glow,
    required this.isDark,
  });

  final Color background;
  final Color surface;
  final Color surfaceRaised;
  final Color border;
  final Color text;
  final Color textMuted;

  /// Hauptakzent (Violett).
  final Color accent;

  /// Zweiter Akzent (Cyan) – für Verläufe und Highlights.
  final Color accent2;
  final Color accentSoft;
  final Color danger;
  final Color success;

  /// Halbtransparente Glasfläche (Seitenleiste, Leisten, Karten).
  final Color glass;

  /// Feine helle Kante an Glasflächen.
  final Color glassEdge;

  /// Farbe des Leuchtens hinter Hauptknöpfen.
  final Color glow;
  final bool isDark;

  /// Der Markenverlauf Violett → Cyan.
  LinearGradient get gradient => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [accent, accent2],
      );

  /// Dezenter Verlauf für Glasflächen.
  LinearGradient get glassGradient => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          glass,
          Color.lerp(glass, background, 0.5)!,
        ],
      );

  static const dark = MfPalette(
    background: Color(0xFF0A0A0F),
    surface: Color(0xFF13131B),
    surfaceRaised: Color(0xFF1C1C27),
    border: Color(0xFF262634),
    text: Color(0xFFF2F2F7),
    textMuted: Color(0xFF8E8EA3),
    accent: Color(0xFF8B5CF6),
    accent2: Color(0xFF22D3EE),
    accentSoft: Color(0x338B5CF6),
    danger: Color(0xFFF87171),
    success: Color(0xFF34D399),
    glass: Color(0xB3161620),
    glassEdge: Color(0x1FFFFFFF),
    glow: Color(0x668B5CF6),
    isDark: true,
  );

  static const light = MfPalette(
    background: Color(0xFFF4F5FA),
    surface: Color(0xFFFFFFFF),
    surfaceRaised: Color(0xFFEEEFF6),
    border: Color(0xFFE1E2EC),
    text: Color(0xFF14141C),
    textMuted: Color(0xFF6A6B7C),
    accent: Color(0xFF7C3AED),
    accent2: Color(0xFF0891B2),
    accentSoft: Color(0x1F7C3AED),
    danger: Color(0xFFDC2626),
    success: Color(0xFF059669),
    glass: Color(0xCCFFFFFF),
    glassEdge: Color(0x14000000),
    glow: Color(0x407C3AED),
    isDark: false,
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
      accent2: l(accent2, other.accent2),
      accentSoft: l(accentSoft, other.accentSoft),
      danger: l(danger, other.danger),
      success: l(success, other.success),
      glass: l(glass, other.glass),
      glassEdge: l(glassEdge, other.glassEdge),
      glow: l(glow, other.glow),
      isDark: t < 0.5 ? isDark : other.isDark,
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
    onPrimary: Colors.white,
    secondary: p.accent2,
    surface: p.surface,
    onSurface: p.text,
    surfaceContainerLowest: p.background,
    surfaceContainerLow: p.surface,
    surfaceContainer: p.surface,
    surfaceContainerHigh: p.isDark ? const Color(0xFF181822) : p.surface,
    surfaceContainerHighest: p.surfaceRaised,
    surfaceTint: Colors.transparent,
    outline: p.border,
    outlineVariant: p.border,
    error: p.danger,
  );
  final radius14 = BorderRadius.circular(14);
  OutlineInputBorder ob(Color c, [double w = 1]) => OutlineInputBorder(
        borderRadius: radius14,
        borderSide: BorderSide(color: c, width: w),
      );
  final base = ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
  );
  return base.copyWith(
    scaffoldBackgroundColor: p.background,
    canvasColor: p.background,
    dividerColor: p.border,
    extensions: [p],
    textTheme: base.textTheme.apply(
      bodyColor: p.text,
      displayColor: p.text,
    ),
    iconTheme: IconThemeData(color: p.text),
    dividerTheme: DividerThemeData(color: p.border, thickness: 1, space: 1),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: p.surfaceRaised,
      hintStyle: TextStyle(color: p.textMuted),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: ob(p.border),
      enabledBorder: ob(p.border),
      focusedBorder: ob(p.accent, 1.6),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: p.accent,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: radius14),
        textStyle: const TextStyle(fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: p.text,
        side: BorderSide(color: p.border),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: radius14),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: p.accent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: p.surfaceRaised,
      selectedColor: p.accentSoft,
      side: BorderSide(color: p.border),
      labelStyle: TextStyle(color: p.text, fontSize: 13),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: p.isDark ? const Color(0xFF22222F) : const Color(0xFF1C1C27),
      contentTextStyle: const TextStyle(color: Colors.white),
      actionTextColor: p.accent2,
      shape: RoundedRectangleBorder(borderRadius: radius14),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: p.accent),
    sliderTheme: SliderThemeData(
      activeTrackColor: p.accent,
      thumbColor: p.accent,
      inactiveTrackColor: p.border,
    ),
    tooltipTheme: TooltipThemeData(
      waitDuration: const Duration(milliseconds: 600),
      decoration: BoxDecoration(
        color: p.isDark ? const Color(0xFF26263A) : const Color(0xFF1C1C27),
        borderRadius: BorderRadius.circular(8),
      ),
      textStyle: const TextStyle(color: Colors.white, fontSize: 12),
    ),
  );
}

/// Papier einer Seite oder Arbeitsfläche – unabhängig vom App-Thema,
/// damit Handschrift nie unsichtbar wird, wenn man das Thema wechselt.
enum Paper {
  dark('Dunkel'),
  light('Weiß'),
  cream('Creme');

  const Paper(this.label);
  final String label;
}

class PaperStyle {
  const PaperStyle({
    required this.desk,
    required this.sheet,
    required this.line,
    required this.ink,
    required this.highlighter,
    this.gap = 1.0,
  });

  /// Abstand der Linien/Kästchen (1 = normal, kleiner = enger).
  final double gap;

  /// Gleiches Papier mit eigener Blattfarbe, Linienfarbe oder Abstand.
  PaperStyle copyWith({Color? sheet, Color? line, double? gap}) => PaperStyle(
        desk: desk,
        sheet: sheet ?? this.sheet,
        line: line ?? this.line,
        ink: ink,
        highlighter: highlighter,
        gap: gap ?? this.gap,
      );

  /// Hintergrund um das Blatt herum.
  final Color desk;

  /// Farbe des Blattes.
  final Color sheet;

  /// Linien, Raster, Punkte.
  final Color line;

  final List<Color> ink;
  final List<Color> highlighter;

  static const dark = PaperStyle(
    desk: Color(0xFF0B0B10),
    sheet: Color(0xFF17171F),
    line: Color(0xFF2C2C3A),
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
    desk: Color(0xFFE6E7EE),
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

  static const cream = PaperStyle(
    desk: Color(0xFFE4DFD3),
    sheet: Color(0xFFF8F3E6),
    line: Color(0xFFE0D8C5),
    ink: [
      Color(0xFF2B2A28),
      Color(0xFF6D5DE7),
      Color(0xFF1D4ED8),
      Color(0xFF15803D),
      Color(0xFFB91C1C),
    ],
    highlighter: [
      Color(0xFFFACC15),
      Color(0xFF4ADE80),
      Color(0xFFF472B6),
      Color(0xFF60A5FA),
    ],
  );

  static PaperStyle of(Paper p) => switch (p) {
        Paper.dark => dark,
        Paper.light => light,
        Paper.cream => cream,
      };
}
