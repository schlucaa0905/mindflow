import 'dart:math' as math;

import 'package:flutter/foundation.dart';

/// Werkzeuge der Schreibfläche.
///
/// Neue Werkzeuge immer hinten anfügen (gespeichert wird der Name).
enum ToolMode { pen, highlighter, eraser, lasso, shape, laser, text }

/// Stiftart.
enum PenType {
  fountain('Füller', 'Wird dicker, je fester du drückst.'),
  ballpoint('Kugelschreiber', 'Immer gleich dick.'),
  brush('Pinselstift', 'Starker Druckeffekt, spitze Enden.');

  const PenType(this.label, this.hint);
  final String label;
  final String hint;
}

enum EraserMode {
  stroke('Ganzer Strich', 'Löscht jeden berührten Strich komplett.'),
  area('Bereich', 'Löscht nur die berührten Stellen.');

  const EraserMode(this.label, this.hint);
  final String label;
  final String hint;
}

enum ShapeKind {
  line('Linie'),
  arrow('Pfeil'),
  rectangle('Rechteck'),
  ellipse('Ellipse'),
  triangle('Dreieck');

  const ShapeKind(this.label);
  final String label;
}

/// Wo die Werkzeugleiste sitzt.
enum ToolbarDock { top, bottom, left, right, floating }

/// Ein gespeicherter Lieblingsstift (oder Lieblings-Textmarker).
class PenPreset {
  const PenPreset(
      {required this.type,
      required this.color,
      required this.width,
      this.highlighter = false});

  final PenType type;
  final int color;
  final double width;
  final bool highlighter;

  Map<String, dynamic> toJson() => {
        'type': type.name,
        'color': color,
        'width': width,
        if (highlighter) 'hl': true,
      };

  static PenPreset? fromJson(Object? j) {
    if (j is! Map) return null;
    final type = PenType.values.where((t) => t.name == j['type']).firstOrNull;
    final color = j['color'], width = j['width'];
    if (type == null || color is! int || width is! num) return null;
    return PenPreset(
        type: type,
        color: color,
        width: width.toDouble(),
        highlighter: j['hl'] == true);
  }
}

/// Winkel-Einrasten für Linien und das Drehen mit dem Lasso.
enum AngleSnap {
  off('Aus'),
  right('90°'),
  half('45° und 90°');

  const AngleSnap(this.label);
  final String label;
}

/// Standard-Paletten (je eine für dunkles und helles Papier).
const kDefaultPaletteDark = <int>[
  0xFFEDEDF2, 0xFF8B7CF6, 0xFF5AA9FF, 0xFF4ADE80, 0xFFF87171,
];
const kDefaultPaletteLight = <int>[
  0xFF1C1C22, 0xFF6D5DE7, 0xFF2563EB, 0xFF16A34A, 0xFFDC2626,
];
const kDefaultHighlighters = <int>[
  0xFFFACC15, 0xFF4ADE80, 0xFFF472B6, 0xFF60A5FA,
];

/// Alle Werkzeug-Einstellungen. Gelten app-weit (wie bei Goodnotes:
/// der Stift bleibt derselbe, egal welches Notizbuch offen ist) und
/// werden dauerhaft gespeichert.
class ToolSettings extends ChangeNotifier {
  ToolMode tool = ToolMode.pen;

  /// Werkzeug vor dem Radierer (für "automatisch zurück").
  ToolMode toolBeforeEraser = ToolMode.pen;

  PenType penType = PenType.fountain;
  int penColorDark = kDefaultPaletteDark.first;
  int penColorLight = kDefaultPaletteLight.first;
  double penWidth = 2.5;
  bool shapeRecognition = true;

  /// Die drei Breiten-Plätze in der Leiste (frei einstellbar).
  List<double> penWidths = [1.2, 2.6, 5.0];
  List<double> highlighterWidths = [8, 14, 24];

  int highlighterColor = kDefaultHighlighters.first;
  double highlighterWidth = 14;
  bool highlighterStraight = false;

  EraserMode eraserMode = EraserMode.stroke;
  double eraserSize = 12;
  bool eraseHighlighterOnly = false;

  /// Nach dem Radieren automatisch zurück zum vorigen Stift.
  bool eraserAutoReturn = true;

  /// Einrasten bei geraden Winkeln (nur ganz nah dran, siehe kSnapDegrees).
  AngleSnap angleSnap = AngleSnap.half;

  /// Glättung der Handschrift: 0 = roh, 0,5 = Standard, 1 = sehr ruhig.
  double smoothing = 0.5;

  /// Druckempfindlichkeit des Stifts: 0 = hart (wenig Wirkung),
  /// 0,5 = Standard, 1 = sehr empfindlich.
  double pressure = 0.5;

  /// Rechnet den gemessenen Druck (0–1) mit der Empfindlichkeit um.
  double applyPressure(double p) {
    if (pressure == 0.5) return p;
    return math.pow(p.clamp(0.0, 1.0), math.pow(2, (0.5 - pressure) * 2.4))
        .toDouble();
  }

  ShapeKind shapeKind = ShapeKind.line;

  /// Schriftgröße neuer Textfelder (in Seiten-Punkten).
  double textSize = 18;

  /// Füllfarbe neuer Formen (null = ohne).
  int? shapeFill;

  List<int> paletteDark = List.of(kDefaultPaletteDark);
  List<int> paletteLight = List.of(kDefaultPaletteLight);
  List<int> highlighterPalette = List.of(kDefaultHighlighters);
  /// Zuletzt benutzte eigene Farben (Stift bzw. Textmarker).
  List<int> customColors = [];
  List<int> recentHighlighter = [];
  List<PenPreset> presets = [];

  /// null = noch nicht festgelegt (dann Plattform-Standard).
  bool? stylusOnly;
  bool stylusChosenByUser = false;

  ToolbarDock dock = ToolbarDock.top;

  /// Position der schwebenden Leiste als Anteil der Fläche (0..1).
  double floatX = 0.5;
  double floatY = 0.2;
  bool collapsed = false;

  /// Ändert etwas und benachrichtigt alle offenen Flächen.
  void update(VoidCallback change) {
    change();
    notifyListeners();
  }

  Map<String, dynamic> toJson() => {
        'tool': tool.name,
        'penType': penType.name,
        'penColorDark': penColorDark,
        'penColorLight': penColorLight,
        'penWidth': penWidth,
        'penWidths': penWidths,
        'highlighterWidths': highlighterWidths,
        'shapeRecognition': shapeRecognition,
        'highlighterColor': highlighterColor,
        'highlighterWidth': highlighterWidth,
        'highlighterStraight': highlighterStraight,
        'eraserMode': eraserMode.name,
        'eraserSize': eraserSize,
        'eraseHighlighterOnly': eraseHighlighterOnly,
        'eraserReturn': eraserAutoReturn,
        'angleSnap': angleSnap.name,
        'smoothing': smoothing,
        'pressure': pressure,
        'shapeKind': shapeKind.name,
        'textSize': textSize,
        'shapeFill': shapeFill,
        'paletteDark': paletteDark,
        'paletteLight': paletteLight,
        'highlighterPalette': highlighterPalette,
        'customColors': customColors,
        'recentHighlighter': recentHighlighter,
        'presets': [for (final p in presets) p.toJson()],
        'stylusOnly': stylusOnly,
        'stylusChosenByUser': stylusChosenByUser,
        'dock': dock.name,
        'floatX': floatX,
        'floatY': floatY,
        'collapsed': collapsed,
      };

  /// Liest gespeicherte Einstellungen. Unbekannte oder kaputte Werte werden
  /// einfach übersprungen – die App startet dann mit Standardwerten.
  static ToolSettings fromJson(Map<String, dynamic>? j) {
    final s = ToolSettings();
    if (j == null) return s;
    T? pick<T extends Enum>(List<T> values, Object? v) =>
        values.where((e) => e.name == v).firstOrNull;
    double? num_(Object? v) => v is num ? v.toDouble() : null;
    List<int>? ints(Object? v, {int min = 0}) {
      if (v is! List) return null;
      final out = [for (final x in v) if (x is int) x];
      return out.length >= min ? out : null;
    }

    s.tool = pick(ToolMode.values, j['tool']) ?? s.tool;
    if (s.tool == ToolMode.laser) s.tool = ToolMode.pen;
    s.penType = pick(PenType.values, j['penType']) ?? s.penType;
    s.penColorDark = j['penColorDark'] is int ? j['penColorDark'] as int : s.penColorDark;
    s.penColorLight = j['penColorLight'] is int ? j['penColorLight'] as int : s.penColorLight;
    s.penWidth = (num_(j['penWidth']) ?? s.penWidth).clamp(0.5, 20).toDouble();
    List<double>? widths(Object? v, double min, double max) {
      if (v is! List || v.length != 3) return null;
      final out = <double>[];
      for (final x in v) {
        if (x is! num) return null;
        out.add(x.toDouble().clamp(min, max).toDouble());
      }
      return out;
    }

    s.penWidths = widths(j['penWidths'], 0.3, 20) ?? s.penWidths;
    s.highlighterWidths =
        widths(j['highlighterWidths'], 2, 40) ?? s.highlighterWidths;
    s.shapeRecognition = j['shapeRecognition'] is bool ? j['shapeRecognition'] as bool : true;
    s.highlighterColor = j['highlighterColor'] is int ? j['highlighterColor'] as int : s.highlighterColor;
    s.highlighterWidth = (num_(j['highlighterWidth']) ?? s.highlighterWidth).clamp(2, 40).toDouble();
    s.highlighterStraight = j['highlighterStraight'] == true;
    s.eraserMode = pick(EraserMode.values, j['eraserMode']) ?? s.eraserMode;
    s.eraserSize = (num_(j['eraserSize']) ?? s.eraserSize).clamp(2, 60).toDouble();
    s.eraseHighlighterOnly = j['eraseHighlighterOnly'] == true;
    // Neuer Schlüssel: früher war es versteckt und aus – jetzt Standard an.
    s.eraserAutoReturn =
        j['eraserReturn'] is bool ? j['eraserReturn'] as bool : true;
    s.angleSnap = pick(AngleSnap.values, j['angleSnap']) ?? s.angleSnap;
    s.smoothing = (num_(j['smoothing']) ?? s.smoothing).clamp(0, 1).toDouble();
    s.pressure = (num_(j['pressure']) ?? s.pressure).clamp(0, 1).toDouble();
    s.shapeKind = pick(ShapeKind.values, j['shapeKind']) ?? s.shapeKind;
    s.textSize = (num_(j['textSize']) ?? s.textSize).clamp(8, 96).toDouble();
    s.shapeFill = j['shapeFill'] is int ? j['shapeFill'] as int : null;
    s.paletteDark = ints(j['paletteDark'], min: 1) ?? s.paletteDark;
    s.paletteLight = ints(j['paletteLight'], min: 1) ?? s.paletteLight;
    s.highlighterPalette = ints(j['highlighterPalette'], min: 1) ?? s.highlighterPalette;
    s.customColors = ints(j['customColors']) ?? s.customColors;
    s.recentHighlighter = ints(j['recentHighlighter']) ?? s.recentHighlighter;
    final presets = j['presets'];
    if (presets is List) {
      final list = <PenPreset>[];
      for (final p in presets) {
        final preset = PenPreset.fromJson(p);
        if (preset != null) list.add(preset);
      }
      s.presets = list;
    }
    s.stylusOnly = j['stylusOnly'] is bool ? j['stylusOnly'] as bool : null;
    s.stylusChosenByUser = j['stylusChosenByUser'] == true;
    s.dock = pick(ToolbarDock.values, j['dock']) ?? s.dock;
    s.floatX = (num_(j['floatX']) ?? s.floatX).clamp(0, 1).toDouble();
    s.floatY = (num_(j['floatY']) ?? s.floatY).clamp(0, 1).toDouble();
    s.collapsed = j['collapsed'] == true;
    return s;
  }
}
