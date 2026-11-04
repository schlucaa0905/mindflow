import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:uuid/uuid.dart';

import 'camera.dart';
import '../data/text_repository.dart';
import 'ink_history.dart';
import 'ink_scene.dart';
import 'live_stroke.dart';
import 'shape_recognizer.dart';
import 'stroke.dart';
import 'tool_settings.dart';

export 'tool_settings.dart';

/// Wie nah (in Grad) eine Linie an 0°, 45°, 90° … liegen muss, damit sie
/// einrastet. Bewusst klein: 40° bleibt 40°, erst ab 43° rastet 45° ein.
/// Ganz genaue Winkel wie 44° oder 89° gehen mit den ±1°-Knöpfen.
const double kSnapDegrees = 2.0;

/// Bündelt alles, was eine Zeichenfläche braucht.
/// Die Oberfläche spricht nur mit dem Controller, nie direkt mit den Daten.
///
/// Werkzeug-Einstellungen liegen in [settings] und werden zwischen allen
/// offenen Flächen geteilt.
class InkController extends ChangeNotifier {
  InkController({
    bool? stylusOnly,
    ToolSettings? settings,
    this.darkPaper = true,
  }) : settings = settings ?? ToolSettings() {
    if (stylusOnly != null) this.settings.stylusOnly = stylusOnly;
    this.settings.addListener(_onSettings);
  }

  final ToolSettings settings;

  /// Dunkles Papier → helle Stiftfarben (und umgekehrt).
  final bool darkPaper;

  final InkScene scene = InkScene();
  final Camera camera = Camera();
  final LiveStroke live = LiveStroke();
  final InkHistory history = InkHistory();
  static const _uuid = Uuid();

  /// Zwischenablage für Lasso-Auswahlen – gilt app-weit, damit man zwischen
  /// Seiten, Notizbüchern und Canvas kopieren kann.
  static List<Stroke> clipboard = const [];

  void _onSettings() => notifyListeners();

  String _newId() => _uuid.v4();

  // --- Einstellungen (Weiterleitung an settings) ------------------------

  ToolMode get tool => settings.tool;
  set tool(ToolMode t) => setTool(t);

  PenType get penType => settings.penType;

  Color get penColor =>
      Color(darkPaper ? settings.penColorDark : settings.penColorLight);
  set penColor(Color c) => settings.update(() {
        if (darkPaper) {
          settings.penColorDark = c.toARGB32();
        } else {
          settings.penColorLight = c.toARGB32();
        }
      });

  Color get highlighterColor => Color(settings.highlighterColor);
  set highlighterColor(Color c) =>
      settings.update(() => settings.highlighterColor = c.toARGB32());

  double get penWidth => settings.penWidth;
  double get highlighterWidth => settings.highlighterWidth;

  EraserMode get eraserMode => settings.eraserMode;
  set eraserMode(EraserMode m) => settings.update(() => settings.eraserMode = m);

  double get eraserSize => settings.eraserSize;
  ShapeKind get shapeKind => settings.shapeKind;

  List<Color> get palette => [
        for (final c in darkPaper ? settings.paletteDark : settings.paletteLight)
          Color(c)
      ];
  List<Color> get highlighterPalette =>
      [for (final c in settings.highlighterPalette) Color(c)];
  List<Color> get customColors =>
      [for (final c in settings.customColors) Color(c)];

  bool get stylusOnly =>
      settings.stylusOnly ??
      (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.android);

  /// false: niemand zeichnet, jede Eingabe verschiebt die Fläche
  /// (z. B. im Canvas-Modus "Auswählen" oder "Navigieren").
  bool drawingEnabled = true;

  void setDrawingEnabled(bool v) {
    if (drawingEnabled == v) return;
    drawingEnabled = v;
    if (!v) {
      live.cancel();
      clearSelection();
    }
    notifyListeners();
  }

  /// Zuletzt benutztes Schreibwerkzeug (Stift, Textmarker, Formen) – der
  /// „Schreiben“-Knopf in der Kopfleiste kehrt dorthin zurück.
  ToolMode lastWriteTool = ToolMode.pen;

  static bool isWriteTool(ToolMode t) =>
      t == ToolMode.pen || t == ToolMode.highlighter || t == ToolMode.shape;

  void setTool(ToolMode t) {
    if (isWriteTool(t)) lastWriteTool = t;
    picking = false;
    if (t != ToolMode.lasso) clearSelection();
    if (t != ToolMode.shape) {
      if (_shapeHidden) cancelShape();
      editShape = null;
      _toolBeforeShapeEdit = null;
    }
    settings.update(() {
      if (t == ToolMode.eraser && settings.tool != ToolMode.eraser) {
        settings.toolBeforeEraser = settings.tool;
      }
      settings.tool = t;
    });
  }

  void setPenType(PenType t) => settings.update(() {
        settings.penType = t;
        settings.tool = ToolMode.pen;
      });

  void setEraserMode(EraserMode m) => settings.update(() {
        settings.eraserMode = m;
      });

  void setEraserSize(double s) => settings.update(() => settings.eraserSize = s);

  double get textSize => settings.textSize;
  void setTextSize(double v) =>
      settings.update(() => settings.textSize = v.clamp(8, 96).toDouble());

  void setShapeKind(ShapeKind k) => settings.update(() {
        settings.shapeKind = k;
        settings.tool = ToolMode.shape;
      });

  void setColor(Color c) {
    settings.update(() => _remember(c,
        highlighter: !hasSelection && tool == ToolMode.highlighter));
    if (hasSelection) {
      recolorSelection(c);
      return;
    }
    if (tool == ToolMode.highlighter) {
      highlighterColor = c;
    } else {
      penColor = c;
      if (tool == ToolMode.eraser || tool == ToolMode.lasso ||
          tool == ToolMode.laser) {
        setTool(ToolMode.pen);
      }
    }
  }

  void addCustomColor(Color c) => setColor(c);

  /// Merkt sich eine benutzte Farbe (außer den drei festen der Leiste).
  void _remember(Color c, {required bool highlighter}) {
    final v = c.toARGB32();
    final fixed = highlighter
        ? settings.highlighterPalette
        : darkPaper
            ? settings.paletteDark
            : settings.paletteLight;
    if (fixed.take(3).contains(v)) return;
    final list =
        highlighter ? settings.recentHighlighter : settings.customColors;
    list
      ..remove(v)
      ..insert(0, v);
    if (list.length > 8) list.removeLast();
  }

  /// Zuletzt benutzte Farben des aktiven Werkzeugs (neueste zuerst).
  List<Color> get recentColors => [
        for (final v in tool == ToolMode.highlighter && !hasSelection
            ? settings.recentHighlighter
            : settings.customColors)
          Color(v)
      ];

  // --- Pipette -------------------------------------------------------------

  /// Pipette aktiv: das nächste Antippen der Fläche nimmt eine Farbe auf.
  bool picking = false;

  void setPicking(bool v) {
    if (picking == v) return;
    picking = v;
    notifyListeners();
  }

  /// Farbe an einer Stelle: Text, Handschrift, Formfüllung (oben zuerst).
  /// Bilder und PDF-Seiten liest die Oberfläche direkt vom Bildschirm.
  Color? colorAt(Offset world) {
    final h = items;
    if (h != null) {
      for (final t in h.all.reversed) {
        if (t.isText && h.rectOf(t).contains(world)) return Color(t.color);
      }
    }
    final r = 6 / camera.scale;
    final list = scene.strokes;
    // Erst Schrift, dann Textmarker (der liegt immer darunter).
    for (final hl in const [false, true]) {
      for (var i = list.length - 1; i >= 0; i--) {
        final s = list[i];
        if (s.deleted || (s.tool == InkTool.highlighter) != hl) continue;
        if (s.hits(world, r)) return Color(s.color);
      }
    }
    for (var i = list.length - 1; i >= 0; i--) {
      final s = list[i];
      final f = s.fill;
      if (s.deleted || f == null || !s.bounds.contains(world)) continue;
      final poly = [
        for (var k = 0; k < s.points.length; k += 3)
          Offset(s.points[k], s.points[k + 1])
      ];
      if (pointInPolygon(world, poly)) return Color(f).withAlpha(255);
    }
    return null;
  }

  /// Aufgenommene Farbe übernehmen (auch für eine Lasso-Auswahl).
  void applyPickedColor(Color c) {
    picking = false;
    setColor(c.withAlpha(255));
    notifyListeners();
  }

  /// Ersetzt eine Farbe der Palette (langes Drücken auf eine Farbe).
  void replacePaletteColor(int index, Color c, {bool highlighter = false}) {
    settings.update(() {
      final list = highlighter
          ? settings.highlighterPalette
          : darkPaper
              ? settings.paletteDark
              : settings.paletteLight;
      if (index >= 0 && index < list.length) list[index] = c.toARGB32();
    });
    setColor(c);
  }

  /// Breite des aktiven Werkzeugs (Textmarker hat eine eigene).
  double get activeWidth =>
      tool == ToolMode.highlighter ? highlighterWidth : penWidth;

  void setWidth(double w) => settings.update(() {
        if (tool == ToolMode.highlighter) {
          settings.highlighterWidth = w;
        } else {
          settings.penWidth = w;
        }
      });

  /// Die drei Breiten-Plätze des aktiven Werkzeugs (frei einstellbar).
  List<double> get widthSlots => tool == ToolMode.highlighter
      ? settings.highlighterWidths
      : settings.penWidths;

  /// Ändert einen Breiten-Platz und benutzt ihn sofort.
  void setWidthSlot(int index, double w) => settings.update(() {
        final slots = tool == ToolMode.highlighter
            ? settings.highlighterWidths
            : settings.penWidths;
        if (index >= 0 && index < slots.length) slots[index] = w;
        if (tool == ToolMode.highlighter) {
          settings.highlighterWidth = w;
        } else {
          settings.penWidth = w;
        }
      });

  // --- Lieblingsstifte ---------------------------------------------------

  /// Speichert Stift (bzw. Textmarker) mit Farbe und Stärke als Favorit.
  /// Ein gleicher Favorit wird nicht doppelt angelegt.
  void saveCurrentAsPreset() {
    final hl = tool == ToolMode.highlighter;
    final p = PenPreset(
        type: penType,
        color: (hl ? highlighterColor : penColor).toARGB32(),
        width: hl ? highlighterWidth : penWidth,
        highlighter: hl);
    settings.update(() {
      settings.presets.removeWhere((x) => _samePreset(x, p));
      settings.presets.add(p);
      if (settings.presets.length > 8) settings.presets.removeAt(0);
    });
  }

  static bool _samePreset(PenPreset a, PenPreset b) =>
      a.highlighter == b.highlighter &&
      (a.highlighter || a.type == b.type) &&
      a.color == b.color &&
      a.width == b.width;

  void applyPreset(PenPreset p) {
    clearSelection();
    settings.update(() {
      if (p.highlighter) {
        settings.highlighterColor = p.color;
        settings.highlighterWidth = p.width;
        settings.tool = ToolMode.highlighter;
      } else {
        settings.penType = p.type;
        settings.penWidth = p.width;
        if (darkPaper) {
          settings.penColorDark = p.color;
        } else {
          settings.penColorLight = p.color;
        }
        settings.tool = ToolMode.pen;
      }
      picking = false;
    });
    lastWriteTool = p.highlighter ? ToolMode.highlighter : ToolMode.pen;
  }

  /// Favorit an alter Stelle wieder einsetzen (nach versehentlichem Löschen).
  void restorePreset(PenPreset p, int index) => settings.update(() {
        settings.presets
            .insert(index.clamp(0, settings.presets.length).toInt(), p);
      });

  void removePreset(PenPreset p) =>
      settings.update(() => settings.presets.remove(p));

  bool isActivePreset(PenPreset p) => p.highlighter
      ? tool == ToolMode.highlighter &&
          p.color == highlighterColor.toARGB32() &&
          p.width == highlighterWidth
      : tool == ToolMode.pen &&
          p.type == penType &&
          p.color == penColor.toARGB32() &&
          p.width == penWidth;

  // --- Eingabemodus -------------------------------------------------------

  void setStylusOnly(bool v) => settings.update(() {
        settings.stylusOnly = v;
        settings.stylusChosenByUser = true;
      });

  /// Wird bei jeder Stift-Berührung aufgerufen: Ist ein Stift im Spiel,
  /// sollen Finger navigieren statt zeichnen (wie bei Goodnotes).
  void onStylusDetected() {
    if (stylusOnly || settings.stylusChosenByUser) return;
    settings.update(() => settings.stylusOnly = true);
  }

  // --- Zeichenbereich ----------------------------------------------------

  /// Bereich, in dem geschrieben werden darf (z. B. das Blatt).
  /// null = überall (Canvas).
  Rect? drawBounds;

  /// Darf an dieser Stelle ein Strich beginnen?
  bool canDrawAt(Offset world) =>
      drawBounds == null || drawBounds!.contains(world);

  /// Hält einen Punkt auf dem Blatt (Striche enden am Blattrand).
  Offset clampToBounds(Offset world) {
    final b = drawBounds;
    if (b == null) return world;
    return Offset(world.dx.clamp(b.left, b.right).toDouble(),
        world.dy.clamp(b.top, b.bottom).toDouble());
  }

  // --- Schreiben ---------------------------------------------------------

  /// true, wenn die Formerkennung den aktuellen Strich ersetzt hat.
  bool shapeLocked = false;

  /// Unendliche Fläche (Canvas): Strichstärke gilt für den Bildschirm –
  /// weit herausgezoomt wird ein Strich also nicht unsichtbar dünn.
  /// Auf Seiten (Notizbuch, PDF) bleibt sie fest wie auf Papier.
  bool widthFollowsZoom = false;

  /// Stärke in Weltkoordinaten für eine Stärke in Seiten-Punkten.
  double _worldWidth(double w) =>
      widthFollowsZoom && camera.scale > 0 ? w / camera.scale : w;

  // --- Lineal (wie Goodnotes) ----------------------------------------------

  /// Lage des Lineals (Mitte und Winkel, Weltkoordinaten); null = aus.
  final ValueNotifier<({Offset center, double angle})?> ruler =
      ValueNotifier(null);
  static const rulerLength = 900.0;
  static const rulerWidth = 72.0;

  /// An welcher Kante gerade gezeichnet wird (-1 oben, 1 unten, 0 keine).
  int _rulerEdge = 0;

  void toggleRuler() {
    if (ruler.value != null) {
      ruler.value = null;
    } else {
      final v = camera.viewport;
      ruler.value = (
        center: v.isEmpty
            ? const Offset(300, 300)
            : camera.toWorld(Offset(v.width / 2, v.height / 2)),
        angle: 0.0,
      );
    }
    notifyListeners();
  }

  /// Verschiebt bzw. dreht das Lineal (zwei Finger).
  void moveRuler(Offset delta, [double rotate = 0]) {
    final r = ruler.value;
    if (r == null) return;
    ruler.value = (center: r.center + delta, angle: r.angle + rotate);
  }

  Offset _toRuler(Offset w, ({Offset center, double angle}) r) {
    final d = w - r.center;
    final c = math.cos(-r.angle), s = math.sin(-r.angle);
    return Offset(d.dx * c - d.dy * s, d.dx * s + d.dy * c);
  }

  Offset _fromRuler(Offset l, ({Offset center, double angle}) r) {
    final c = math.cos(r.angle), s = math.sin(r.angle);
    return r.center + Offset(l.dx * c - l.dy * s, l.dx * s + l.dy * c);
  }

  /// Liegt der Punkt auf dem Lineal?
  bool onRuler(Offset world) {
    final r = ruler.value;
    if (r == null) return false;
    final l = _toRuler(world, r);
    return l.dx.abs() <= rulerLength / 2 && l.dy.abs() <= rulerWidth / 2;
  }

  /// Zieht Punkte an der Linealkante entlang (gerade Linien).
  Offset _rulerSnap(Offset world, {bool start = false}) {
    final r = ruler.value;
    if (r == null) return world;
    final l = _toRuler(world, r);
    if (start) {
      _rulerEdge = 0;
      if (l.dx.abs() > rulerLength / 2 + 20) return world;
      final reach = 28 / camera.scale;
      if ((l.dy - rulerWidth / 2).abs() < reach) _rulerEdge = 1;
      if ((l.dy + rulerWidth / 2).abs() < reach) _rulerEdge = -1;
    }
    if (_rulerEdge == 0) return world;
    return _fromRuler(Offset(l.dx, _rulerEdge * rulerWidth / 2), r);
  }

  void beginStroke(Offset world, double pressure) {
    _rulerEdge = 0;
    world = _rulerSnap(world, start: true);
    shapeLocked = false;
    _straightLine = false;
    final hl = tool == ToolMode.highlighter;
    final InkTool t;
    if (hl) {
      t = InkTool.highlighter;
    } else {
      t = switch (penType) {
        PenType.fountain => InkTool.pen,
        PenType.ballpoint => InkTool.ballpoint,
        PenType.brush => InkTool.brush,
      };
    }
    // Glättung beim Schreiben (bis zur Mitte des Reglers; darüber glättet
    // zusätzlich commitStroke nach dem Abheben – ohne Verzögerung).
    final sm = settings.smoothing;
    live.smoothing = sm <= 0.5 ? 1 - 0.8 * sm : 0.6;
    // Breite in Seiten-Punkten (wie Goodnotes): ein Strich ist auf dem Blatt
    // immer gleich dick, egal bei welchem Zoom er geschrieben wurde.
    live.begin(world, pressure,
        width: _worldWidth(hl ? highlighterWidth : penWidth),
        color: hl ? highlighterColor : penColor,
        tool: t);
  }

  /// true, wenn der Textmarker durch Halten zur geraden Linie wurde.
  bool _straightLine = false;

  void extendStroke(Offset world, double pressure) {
    world = _rulerSnap(world);
    if (shapeLocked) {
      if (_straightLine && live.points.length >= 6) {
        final p = live.points;
        final w = clampToBounds(
            _snapEnd(Offset(p[0], p[1]), clampToBounds(world)));
        live.setPoints([p[0], p[1], 0.5, w.dx, w.dy, 0.5],
            width: live.width, color: live.color, tool: live.tool);
      }
      return;
    }
    live.extend(clampToBounds(world), pressure, 0.6 / camera.scale);
  }

  /// "Zeichnen und halten": versucht, den aktuellen Strich als Form zu
  /// erkennen und ersetzt ihn durch die saubere Form. Gibt true zurück,
  /// wenn eine Form erkannt wurde.
  bool recognizeHeldStroke() {
    if (!live.active || shapeLocked) return false;
    // Textmarker: Halten macht eine gerade Linie (wie bei Goodnotes).
    // Danach folgt das Linienende weiter dem Stift.
    if (tool == ToolMode.highlighter) {
      final p = live.points;
      if (p.length < 6) return false;
      final a = Offset(p[0], p[1]);
      var b = Offset(p[p.length - 3], p[p.length - 2]);
      if ((b - a).distance * camera.scale < 12) return false;
      b = clampToBounds(_snapEnd(a, b));
      live.setPoints([a.dx, a.dy, 0.5, b.dx, b.dy, 0.5],
          width: live.width, color: live.color, tool: InkTool.highlighter);
      shapeLocked = true;
      _straightLine = true;
      return true;
    }
    if (!settings.shapeRecognition) return false;
    final found = recognizeShape(live.points, minSize: 12 / camera.scale);
    if (found == null) return false;
    final shape = _snapLinePoints(found);
    live.setPoints(shape,
        width: live.width, color: live.color, tool: InkTool.shape);
    shapeLocked = true;
    return true;
  }

  void commitStroke({int? fill}) {
    final width = live.width, color = live.color, t = live.tool;
    final locked = shapeLocked;
    shapeLocked = false;
    _straightLine = false;
    var pts = live.finish();
    if (pts == null || pts.isEmpty) return;
    // Textmarker gerade ziehen (Option) – mit Winkel-Einrasten.
    if (t == InkTool.highlighter &&
        settings.highlighterStraight &&
        pts.length >= 6) {
      final n = pts.length;
      final a = Offset(pts[0], pts[1]);
      final b = clampToBounds(_snapEnd(a, Offset(pts[n - 3], pts[n - 2])));
      pts = Float32List.fromList([a.dx, a.dy, 0.5, b.dx, b.dy, 0.5]);
    } else if (!locked && t != InkTool.shape && _rulerEdge == 0) {
      // Glättungs-Regler über der Mitte: nach dem Abheben nachglätten.
      pts = smoothPoints(pts, (settings.smoothing - 0.5) * 2);
    }
    final s = Stroke(
      id: _newId(),
      color: color.toARGB32(),
      width: width,
      tool: t,
      points: pts,
      fill: fill,
    );
    scene.add(s);
    history.push(AddStrokes([s]));
    notifyListeners();
  }

  /// Glättet einen fertigen Strich: Jeder Punkt rückt ein Stück zur Mitte
  /// seiner Nachbarn. Anfang und Ende bleiben, wo der Stift war.
  /// [strength] 0 = nichts, 1 = sehr ruhig.
  static Float32List smoothPoints(Float32List pts, double strength) {
    final n = pts.length ~/ 3;
    if (strength <= 0 || n < 3) return pts;
    final w = 0.5 * math.min(1.0, strength);
    final passes = 1 + (math.min(1.0, strength) * 3).floor();
    var cur = Float32List.fromList(pts);
    for (var k = 0; k < passes; k++) {
      final next = Float32List.fromList(cur);
      for (var i = 1; i < n - 1; i++) {
        for (var j = 0; j < 3; j++) {
          final m = (cur[(i - 1) * 3 + j] + cur[(i + 1) * 3 + j]) / 2;
          next[i * 3 + j] = cur[i * 3 + j] + (m - cur[i * 3 + j]) * w;
        }
      }
      cur = next;
    }
    return cur;
  }

  // --- Winkel einrasten ---------------------------------------------------

  /// true, wenn beim letzten Schritt ein Winkel eingerastet ist – die
  /// Oberfläche gibt dann ein kleines spürbares Klicken.
  bool snapped = false;

  /// Winkel in Grad von [from] nach [to]: 0 = nach rechts, 90 = nach oben
  /// (gegen den Uhrzeigersinn, wie auf dem Geodreieck), Bereich 0–360.
  static double angleOf(Offset from, Offset to) {
    final d = to - from;
    final deg = math.atan2(-d.dy, d.dx) * 180 / math.pi;
    return (deg % 360 + 360) % 360;
  }

  /// Eingerasteter Winkel – oder null, wenn [deg] nicht nah genug
  /// (höchstens [kSnapDegrees]) an 0°/90°/180°/270° (bzw. 45°-Schritten) liegt.
  static double? snapAngle(double deg, AngleSnap mode) {
    if (mode == AngleSnap.off) return null;
    final step = mode == AngleSnap.half ? 45.0 : 90.0;
    final t = (deg / step).roundToDouble() * step;
    return (deg - t).abs() <= kSnapDegrees ? t % 360 : null;
  }

  /// Endpunkt [moving] einer Linie ab [fixed] – rastet nah an geraden
  /// Winkeln ein, die Länge bleibt gleich.
  Offset _snapEnd(Offset fixed, Offset moving) {
    snapped = false;
    final len = (moving - fixed).distance;
    if (len * camera.scale < 8) return moving;
    final t = snapAngle(angleOf(fixed, moving), settings.angleSnap);
    if (t == null) return moving;
    snapped = true;
    final r = t * math.pi / 180;
    return fixed + Offset(math.cos(r), -math.sin(r)) * len;
  }

  /// Verteilt die Punkte einer Linie gleichmäßig zwischen [a] und [b].
  static List<double> _lerpPoints(List<double> pts, Offset a, Offset b) {
    final n = pts.length ~/ 3;
    final out = List<double>.of(pts);
    for (var i = 0; i < n; i++) {
      final p = Offset.lerp(a, b, n == 1 ? 0 : i / (n - 1))!;
      out[i * 3] = p.dx;
      out[i * 3 + 1] = p.dy;
    }
    return out;
  }

  /// Erkannte Form: Ist es eine offene gerade Linie, rastet sie ein.
  List<double> _snapLinePoints(List<double> pts) {
    snapped = false;
    if (pts.length < 6) return pts;
    final a = Offset(pts[0], pts[1]);
    final b = Offset(pts[pts.length - 3], pts[pts.length - 2]);
    if ((b - a).distance < 1) return pts; // geschlossene Form
    final b2 = _snapEnd(a, b);
    return snapped ? _lerpPoints(pts, a, b2) : pts;
  }

  void cancelStroke() {
    shapeLocked = false;
    _straightLine = false;
    live.cancel();
  }

  // --- Formen-Werkzeug (wie Goodnotes) -----------------------------------
  //
  // Zeichnen: frei Hand – beim Abheben wird daraus die perfekte Form.
  // Vorhandene Form oder Linie antippen: Griffe erscheinen; Ecken/Kanten
  // ziehen ändert die Größe, Linienenden lassen sich einzeln versetzen,
  // in die Form tippen und ziehen verschiebt sie.

  Offset? _shapeStart;

  /// Die gerade bearbeitete Form (mit Griffen).
  Stroke? editShape;

  /// Vorschau während des Ziehens an einem Griff.
  final ValueNotifier<Stroke?> shapePreview = ValueNotifier(null);

  /// -2 nichts, -1 verschieben, 0–7 Rahmen-Griffe, 8/9 Linienenden.
  int _shapeDrag = -2;
  Offset _shapeDragFrom = Offset.zero;
  bool _shapeHidden = false;

  /// true, solange ein Griff der Form gezogen wird.
  bool get draggingShape => _shapeDrag != -2;

  /// Die bearbeitete Linie (bzw. ihre Vorschau) – null bei anderen Formen.
  Stroke? get editLine {
    final s = shapePreview.value ?? editShape;
    return s != null && isLine(s) ? s : null;
  }

  /// Winkel einer Linie in Grad (Anfang → Ende), siehe [angleOf].
  static double lineAngle(Stroke s) {
    final p = s.points;
    return angleOf(
        Offset(p[0], p[1]), Offset(p[p.length - 3], p[p.length - 2]));
  }

  /// Länge einer Linie in Seiten-Punkten (28,35 Punkte = 1 cm).
  static double lineLength(Stroke s) {
    final p = s.points;
    return (Offset(p[p.length - 3], p[p.length - 2]) - Offset(p[0], p[1]))
        .distance;
  }

  /// Dreht die bearbeitete Linie um ihre Mitte auf genau [deg] Grad
  /// (ohne Einrasten – so gehen auch 44° oder 89°).
  /// [preview]: nur anzeigen, z. B. solange ein Knopf gehalten wird;
  /// sonst wird es als ein Rückgängig-Schritt übernommen.
  void setLineAngle(double deg, {bool preview = false}) {
    final e = editShape;
    if (e == null || draggingShape || !isLine(e)) return;
    final p = (shapePreview.value ?? e).points;
    final a = Offset(p[0], p[1]), b = Offset(p[p.length - 3], p[p.length - 2]);
    final mid = (a + b) / 2;
    final r = deg * math.pi / 180;
    final half = Offset(math.cos(r), -math.sin(r)) * ((b - a).distance / 2);
    if (!_shapeHidden) {
      scene.setDeleted([e], true);
      _shapeHidden = true;
    }
    shapePreview.value = Stroke(
        id: _newId(),
        color: e.color,
        width: e.width,
        tool: e.tool,
        points: Float32List.fromList(_lerpPoints(p, mid - half, mid + half)),
        fill: e.fill);
    if (!preview) {
      _commitPreview();
      notifyListeners();
    }
  }

  /// Übernimmt die Vorschau der bearbeiteten Form als einen Schritt.
  void _commitPreview() {
    final e = editShape;
    final p = shapePreview.value;
    shapePreview.value = null;
    if (!_shapeHidden || e == null) return;
    _shapeHidden = false;
    if (p == null) {
      scene.setDeleted([e], false);
    } else {
      scene.add(p);
      history.push(ReplaceStrokes(removed: [e], added: [p]));
      editShape = p;
    }
  }

  static Rect pointsRect(Stroke s) {
    final p = s.points;
    var r = Rect.fromLTWH(p[0], p[1], 0, 0);
    for (var i = 3; i < p.length; i += 3) {
      r = r.expandToInclude(Rect.fromLTWH(p[i], p[i + 1], 0, 0));
    }
    return r;
  }

  /// Ist der Strich eine gerade Linie?
  static bool isLine(Stroke s) {
    final p = s.points;
    if (p.length < 6) return false;
    final a = Offset(p[0], p[1]), b = Offset(p[p.length - 3], p[p.length - 2]);
    if ((b - a).distance < 1) return false;
    final tol = math.max(0.8, s.width);
    for (var i = 0; i < p.length; i += 3) {
      if (math.sqrt(distanceToSegmentSquared(Offset(p[i], p[i + 1]), a, b)) >
          tol) {
        return false;
      }
    }
    return true;
  }

  /// Griffe der Form: Linienenden oder 8 Rahmen-Griffe
  /// (oben links, oben, oben rechts, rechts, unten rechts, unten,
  /// unten links, links).
  static List<Offset> shapeHandles(Stroke s) {
    if (isLine(s)) {
      final p = s.points;
      return [Offset(p[0], p[1]), Offset(p[p.length - 3], p[p.length - 2])];
    }
    final r = pointsRect(s);
    return [
      r.topLeft, r.topCenter, r.topRight, r.centerRight,
      r.bottomRight, r.bottomCenter, r.bottomLeft, r.centerLeft,
    ];
  }

  int? _handleAt(Stroke s, Offset world) {
    final hs = shapeHandles(s);
    for (var i = 0; i < hs.length; i++) {
      if ((hs[i] - world).distance * camera.scale <= 22) {
        return hs.length == 2 ? 8 + i : i;
      }
    }
    return null;
  }

  List<Stroke> _shapesAt(Offset world) => [
        for (final s in scene.hitTest(world, 10 / camera.scale))
          if (s.tool == InkTool.shape) s
      ];

  /// Werkzeug vor dem Antippen einer Form – danach geht es dorthin zurück.
  ToolMode? _toolBeforeShapeEdit;

  /// Antippen mit beliebigem Werkzeug: Liegt dort eine Form, wird sie zum
  /// Bearbeiten ausgewählt (wie bei Goodnotes). Gibt true zurück, wenn ja.
  bool tryEditShapeAt(Offset world) {
    final hits = _shapesAt(world);
    if (hits.isEmpty) return false;
    if (tool != ToolMode.shape) {
      _toolBeforeShapeEdit = tool;
      setTool(ToolMode.shape);
    }
    editShape = hits.last;
    notifyListeners();
    return true;
  }

  void _endShapeEdit() {
    if (editShape == null) return;
    editShape = null;
    final back = _toolBeforeShapeEdit;
    _toolBeforeShapeEdit = null;
    if (back != null) {
      setTool(back);
    } else {
      notifyListeners();
    }
  }

  void beginShape(Offset world) {
    final e = editShape;
    if (e != null) {
      final h = _handleAt(e, world);
      final inside = pointsRect(e).inflate(10 / camera.scale).contains(world);
      if (h != null || inside) {
        _shapeDrag = h ?? -1;
        _shapeDragFrom = world;
        return;
      }
      final temporary = _toolBeforeShapeEdit != null;
      _endShapeEdit();
      if (temporary) return;
    }
    final hits = _shapesAt(world);
    if (hits.isNotEmpty) {
      editShape = hits.last;
      _shapeDrag = -1;
      _shapeDragFrom = world;
      notifyListeners();
      return;
    }
    _shapeStart = world;
    live.begin(world, 0.5,
        width: _worldWidth(penWidth), color: penColor, tool: InkTool.ballpoint);
  }

  void updateShape(Offset world) {
    final e = editShape;
    if (_shapeDrag != -2 && e != null) {
      if (!_shapeHidden) {
        scene.setDeleted([e], true);
        _shapeHidden = true;
      }
      shapePreview.value = transformShape(e, _shapeDrag, _shapeDragFrom, world);
      return;
    }
    if (_shapeStart != null) {
      live.extend(clampToBounds(world), 0.5, 0.6 / camera.scale);
    }
  }

  void commitShape() {
    final e = editShape;
    if (_shapeDrag != -2 && e != null) {
      _shapeDrag = -2;
      _commitPreview();
      notifyListeners();
      return;
    }
    if (_shapeStart == null) return;
    _shapeStart = null;
    final pts = live.points;
    if (pts.length < 6 ||
        Stroke.computeBounds(Float32List.fromList(pts), 0).longestSide *
                camera.scale <
            4) {
      live.cancel();
      return;
    }
    final found = settings.shapeRecognition
        ? recognizeShape(pts, minSize: 12 / camera.scale)
        : null;
    final shape = found == null ? null : _snapLinePoints(found);
    if (shape != null) {
      live.setPoints(shape,
          width: live.width, color: live.color, tool: InkTool.shape);
    }
    // Füllung nur für geschlossene Formen (nicht für Linien).
    final closed = shape != null &&
        shape.length >= 9 &&
        (Offset(shape[0], shape[1]) -
                    Offset(shape[shape.length - 3], shape[shape.length - 2]))
                .distance <
            1;
    commitStroke(fill: closed ? settings.shapeFill : null);
  }

  /// Abbrechen (z. B. zweiter Finger zum Zoomen): alles wie vorher.
  void cancelShape() {
    final e = editShape;
    if (_shapeHidden && e != null) scene.setDeleted([e], false);
    _shapeHidden = false;
    _shapeDrag = -2;
    shapePreview.value = null;
    _shapeStart = null;
    live.cancel();
  }

  /// Form nach Ziehen an Griff [handle] von [from] nach [to].
  Stroke transformShape(Stroke s, int handle, Offset from, Offset to) {
    final pts = Float32List.fromList(s.points);
    final n = pts.length ~/ 3;
    final d = to - from;
    snapped = false;
    if (handle == -1) {
      for (var i = 0; i < pts.length; i += 3) {
        pts[i] += d.dx;
        pts[i + 1] += d.dy;
      }
    } else if (handle >= 8) {
      var a = Offset(pts[0], pts[1]);
      var b = Offset(pts[(n - 1) * 3], pts[(n - 1) * 3 + 1]);
      // Das gezogene Ende rastet nah an 0°/45°/90° … ein.
      if (handle == 8) {
        a = _snapEnd(b, to);
      } else {
        b = _snapEnd(a, to);
      }
      for (var i = 0; i < n; i++) {
        final p = Offset.lerp(a, b, n == 1 ? 0 : i / (n - 1))!;
        pts[i * 3] = p.dx;
        pts[i * 3 + 1] = p.dy;
      }
    } else {
      final r = pointsRect(s);
      var l = r.left, t = r.top, rt = r.right, b = r.bottom;
      if (const [0, 6, 7].contains(handle)) l = math.min(l + d.dx, rt - 4);
      if (const [2, 3, 4].contains(handle)) rt = math.max(rt + d.dx, l + 4);
      if (const [0, 1, 2].contains(handle)) t = math.min(t + d.dy, b - 4);
      if (const [4, 5, 6].contains(handle)) b = math.max(b + d.dy, t + 4);
      final sx = r.width < 1e-6 ? 1.0 : (rt - l) / r.width;
      final sy = r.height < 1e-6 ? 1.0 : (b - t) / r.height;
      for (var i = 0; i < pts.length; i += 3) {
        pts[i] = l + (pts[i] - r.left) * sx;
        pts[i + 1] = t + (pts[i + 1] - r.top) * sy;
      }
    }
    return Stroke(
        id: _newId(),
        color: s.color,
        width: s.width,
        tool: s.tool,
        points: pts,
        fill: s.fill);
  }

  /// Füllfarbe für neue Formen – und für die gerade bearbeitete.
  void setShapeFill(int? fill) {
    settings.update(() => settings.shapeFill = fill);
    final e = editShape;
    if (e == null || isLine(e)) return;
    final f = Stroke(
        id: _newId(),
        color: e.color,
        width: e.width,
        tool: e.tool,
        points: Float32List.fromList(e.points),
        fill: fill);
    scene.setDeleted([e], true);
    scene.add(f);
    history.push(ReplaceStrokes(removed: [e], added: [f]));
    editShape = f;
    notifyListeners();
  }

  /// Bearbeitete Form löschen.
  void deleteEditShape() {
    if (_shapeHidden) cancelShape();
    final e = editShape;
    if (e == null) return;
    scene.setDeleted([e], true);
    history.push(EraseStrokes([e]));
    editShape = null;
    notifyListeners();
  }

  /// Punkte einer Form, aufgespannt zwischen [a] und [b].
  static List<double> shapePoints(
      ShapeKind kind, Offset a, Offset b, double scale) {
    switch (kind) {
      case ShapeKind.line:
        return polyPoints([a, b]);
      case ShapeKind.arrow:
        final d = b - a;
        final len = d.distance;
        if (len < 1e-3) return polyPoints([a, b]);
        final u = d / len;
        final head = math.min(len * 0.4, 18 / scale);
        const angle = 0.5; // ca. 28°
        Offset rot(Offset v, double t) => Offset(
            v.dx * math.cos(t) - v.dy * math.sin(t),
            v.dx * math.sin(t) + v.dy * math.cos(t));
        final h1 = b - rot(u, angle) * head;
        final h2 = b - rot(u, -angle) * head;
        return polyPoints([a, b, h1, b, h2]);
      case ShapeKind.rectangle:
        return polyPoints([a, Offset(b.dx, a.dy), b, Offset(a.dx, b.dy), a]);
      case ShapeKind.triangle:
        final top = Offset((a.dx + b.dx) / 2, a.dy);
        return polyPoints([top, b, Offset(a.dx, b.dy), top]);
      case ShapeKind.ellipse:
        return ellipsePoints(Rect.fromPoints(a, b));
    }
  }

  // --- Radieren ---------------------------------------------------------

  final List<Stroke> _eraseRemoved = [];
  final List<Stroke> _eraseAdded = [];

  List<Stroke> _eraserHits(Offset world, double r) {
    final hits = scene.hitTest(world, r);
    if (!settings.eraseHighlighterOnly) return hits;
    return [for (final s in hits) if (s.tool == InkTool.highlighter) s];
  }

  void eraseAt(Offset world, double screenRadius) {
    final r = screenRadius / camera.scale;
    if (eraserMode == EraserMode.stroke) {
      final hits = _eraserHits(world, r);
      if (hits.isEmpty) return;
      scene.setDeleted(hits, true);
      _eraseRemoved.addAll(hits);
    } else {
      _eraseArea(world, r);
    }
  }

  /// Entfernt nur die Punkte im Radierer-Kreis und teilt Striche dabei auf.
  void _eraseArea(Offset world, double r) {
    final hits = _eraserHits(world, r);
    if (hits.isEmpty) return;
    final removed = <Stroke>[];
    final added = <Stroke>[];
    for (final s in hits) {
      final reach = r + s.width / 2;
      final reach2 = reach * reach;
      final pts = s.points;
      final pieces = <List<double>>[];
      var current = <double>[];
      var anyInside = false;
      for (var i = 0; i < pts.length; i += 3) {
        final dx = pts[i] - world.dx, dy = pts[i + 1] - world.dy;
        if (dx * dx + dy * dy <= reach2) {
          anyInside = true;
          if (current.length >= 6) pieces.add(current);
          current = <double>[];
        } else {
          current.addAll([pts[i], pts[i + 1], pts[i + 2]]);
        }
      }
      if (!anyInside) continue;
      if (current.length >= 6) pieces.add(current);
      removed.add(s);
      for (final piece in pieces) {
        added.add(Stroke(
          id: _newId(),
          color: s.color,
          width: s.width,
          tool: s.tool,
          points: Float32List.fromList(piece),
        ));
      }
    }
    if (removed.isEmpty) return;
    scene.setDeleted(removed, true);
    scene.addAll(added);
    _eraseRemoved.addAll(removed);
    _eraseAdded.addAll(added);
  }

  void endErase() {
    if (_eraseRemoved.isNotEmpty) {
      if (_eraseAdded.isEmpty) {
        history.push(EraseStrokes(List.of(_eraseRemoved)));
      } else {
        // Zwischenstücke, die in derselben Bewegung wieder radiert wurden,
        // gehören weder zu "vorher" noch zu "nachher".
        final addedIds = {for (final s in _eraseAdded) s.id};
        final removedIds = {for (final s in _eraseRemoved) s.id};
        history.push(ReplaceStrokes(
          removed: [
            for (final s in _eraseRemoved)
              if (!addedIds.contains(s.id)) s
          ],
          added: [
            for (final s in _eraseAdded)
              if (!removedIds.contains(s.id)) s
          ],
        ));
      }
    }
    _eraseRemoved.clear();
    _eraseAdded.clear();
    if (settings.eraserAutoReturn && tool == ToolMode.eraser) {
      setTool(settings.toolBeforeEraser == ToolMode.eraser
          ? ToolMode.pen
          : settings.toolBeforeEraser);
    } else {
      notifyListeners();
    }
  }

  // --- Laserpointer -------------------------------------------------------

  /// Laser-Linie in Weltkoordinaten. Wird nie gespeichert.
  final ValueNotifier<List<Offset>> laserPath = ValueNotifier(const []);

  void beginLaser(Offset world) => laserPath.value = [world];

  void extendLaser(Offset world) {
    final p = laserPath.value;
    final recent = p.length > 400 ? p.sublist(p.length - 400) : p;
    laserPath.value = [...recent, world];
  }

  void clearLaser() => laserPath.value = const [];

  // --- Lasso / Auswahl ----------------------------------------------------

  /// Die Linie, die gerade mit dem Lasso gezogen wird (Weltkoordinaten).
  final ValueNotifier<List<Offset>> lassoPath = ValueNotifier(const []);

  /// Verschiebung der Auswahl während des Ziehens.
  final ValueNotifier<Offset> dragOffset = ValueNotifier(Offset.zero);

  /// Vergrößerung der Auswahl während des Skalierens (um [scaleAnchor]).
  final ValueNotifier<double> dragScale = ValueNotifier(1.0);
  Offset scaleAnchor = Offset.zero;

  /// Drehung der Auswahl während des Drehens (Bogenmaß, um [rotatePivot]).
  final ValueNotifier<double> dragRotate = ValueNotifier(0.0);
  Offset rotatePivot = Offset.zero;

  /// Ein Punkt nach Verschieben [d], Skalieren [s] um [anchor] und
  /// Drehen [rot] (Bogenmaß, im Uhrzeigersinn auf dem Bildschirm) um [pivot].
  static Offset transformPoint(Offset p, Offset d, double s, Offset anchor,
      double rot, Offset pivot) {
    final q = anchor + (p - anchor) * s + d;
    if (rot == 0) return q;
    final v = q - pivot;
    final c = math.cos(rot), sn = math.sin(rot);
    return pivot + Offset(v.dx * c - v.dy * sn, v.dx * sn + v.dy * c);
  }

  /// Ein Element der Auswahl, wie es gerade (beim Ziehen) aussieht.
  TextItem previewItem(TextItem t) => moveItem(
      t, dragOffset.value, dragScale.value, scaleAnchor,
      rotate: dragRotate.value, pivot: rotatePivot);

  /// Ein Punkt der Auswahl, wie er gerade (beim Ziehen) liegt.
  Offset previewPoint(Offset w) => transformPoint(w, dragOffset.value,
      dragScale.value, scaleAnchor, dragRotate.value, rotatePivot);

  List<Stroke> selection = const [];

  /// Textfelder und Bilder der Seite (von der Textebene gesetzt).
  PageItems? items;

  /// Bilder der Seite (werden unter der Handschrift gezeichnet).
  final ValueNotifier<List<TextItem>> pageImages = ValueNotifier(const []);

  /// Links der Seite (Flächen, die zu einer Seite oder einem Inhalt führen).
  final ValueNotifier<List<TextItem>> pageLinks = ValueNotifier(const []);

  /// Link an dieser Stelle (oberster zuerst) oder null.
  TextItem? linkAt(Offset world) {
    for (final t in pageLinks.value.reversed) {
      if (t.file != null &&
          Rect.fromLTWH(t.x, t.y, t.w, t.h).inflate(2 / camera.scale)
              .contains(world)) {
        return t;
      }
    }
    return null;
  }

  /// Neue Elemente (z. B. ein Bild) einfügen – rückgängig machbar und
  /// gleich mit dem Lasso ausgewählt.
  void insertItems(List<TextItem> list) {
    if (items == null || list.isEmpty) return;
    setTool(ToolMode.lasso);
    _apply(after: list);
  }

  /// Ausgewählte Textfelder/Bilder.
  Set<String> selectedItems = const {};

  /// Kopierte Textfelder/Bilder (app-weit).
  static List<TextItem> itemClipboard = const [];

  bool get hasSelection => selection.isNotEmpty || selectedItems.isNotEmpty;

  List<TextItem> get _selItems {
    final h = items;
    if (h == null || selectedItems.isEmpty) return const [];
    return [for (final t in h.all) if (selectedItems.contains(t.id)) t.copy()];
  }

  /// Element verschoben/skaliert/gedreht (für Vorschau und Übernahme).
  /// Beim Drehen wandern Textfelder und Bilder mit, bleiben aber aufrecht.
  static TextItem moveItem(TextItem t, Offset d, double s, Offset anchor,
      {String? id, double rotate = 0, Offset pivot = Offset.zero}) {
    final c = t.copy(id: id);
    c.x = anchor.dx + (t.x - anchor.dx) * s + d.dx;
    c.y = anchor.dy + (t.y - anchor.dy) * s + d.dy;
    c.w = t.w * s;
    c.h = t.h * s;
    if (!t.isImage && s != 1) {
      c.size = (t.size * s).clamp(6.0, 120.0).toDouble();
      if (t.lineHeight != null) c.lineHeight = t.lineHeight! * s;
    }
    if (rotate != 0) {
      final mid = Offset(c.x + c.w / 2, c.y + c.h / 2);
      final to =
          transformPoint(mid, Offset.zero, 1, Offset.zero, rotate, pivot);
      c.x += to.dx - mid.dx;
      c.y += to.dy - mid.dy;
    }
    return c;
  }

  /// Übernimmt eine Auswahl-Änderung (Striche und Elemente) als einen
  /// Rückgängig-Schritt.
  void _apply({
    List<Stroke> removed = const [],
    List<Stroke> added = const [],
    List<TextItem> before = const [],
    List<TextItem> after = const [],
  }) {
    final acts = <InkAction>[];
    if (removed.isNotEmpty || added.isNotEmpty) {
      scene.setDeleted(removed, true);
      scene.addAll(added);
      acts.add(ReplaceStrokes(removed: removed, added: added));
    }
    final h = items;
    if (h != null && (before.isNotEmpty || after.isNotEmpty)) {
      acts.add(ItemsChange(h, before, after)..apply(scene));
    }
    selection = added;
    selectedItems = {for (final t in after) t.id};
    if (acts.isNotEmpty) {
      history.push(acts.length == 1 ? acts.first : Combined(acts));
    }
    notifyListeners();
  }

  /// true, solange die Auswahl verschoben, skaliert oder gedreht wird.
  bool draggingSelection = false;
  bool _scaling = false;
  bool _rotating = false;
  bool get rotatingSelection => draggingSelection && _rotating;
  Offset? _dragStart;

  Rect? get selectionBounds {
    Rect? r;
    for (final s in selection) {
      r = r == null ? s.bounds : r.expandToInclude(s.bounds);
    }
    final h = items;
    if (h != null) {
      for (final t in h.all) {
        if (!selectedItems.contains(t.id)) continue;
        final b = h.rectOf(t);
        r = r == null ? b : r.expandToInclude(b);
      }
    }
    return r;
  }

  bool isInsideSelection(Offset world) {
    final b = selectionBounds;
    return b != null && b.inflate(8 / camera.scale).contains(world);
  }

  /// Liegt [world] auf dem Skalier-Griff (Ecke unten rechts)?
  bool isOnScaleHandle(Offset world) {
    final b = selectionBounds;
    if (b == null) return false;
    final handle = b.inflate(6 / camera.scale).bottomRight;
    return (handle - world).distance * camera.scale <= 22;
  }

  /// Mitte des Dreh-Griffs auf dem Bildschirm (unter der Auswahl).
  Offset? rotateHandleScreen() {
    final b = selectionBounds;
    if (b == null) return null;
    return camera.toScreen(b.bottomCenter) + const Offset(0, 6 + 30);
  }

  /// Liegt [world] auf dem Dreh-Griff?
  bool isOnRotateHandle(Offset world) {
    final h = rotateHandleScreen();
    return h != null && (camera.toScreen(world) - h).distance <= 22;
  }

  void clearSelection() {
    if (!hasSelection && lassoPath.value.isEmpty) return;
    selection = const [];
    selectedItems = const {};
    lassoPath.value = const [];
    notifyListeners();
  }

  void beginLasso(Offset world) {
    selection = const [];
    selectedItems = const {};
    lassoPath.value = [world];
    notifyListeners();
  }

  void extendLasso(Offset world) {
    final path = lassoPath.value;
    if (path.isNotEmpty && (path.last - world).distance * camera.scale < 3) {
      return;
    }
    lassoPath.value = [...path, world];
  }

  void endLasso() {
    final path = lassoPath.value;
    lassoPath.value = const [];
    selection = path.length < 3 ? const [] : strokesInPolygon(scene, path);
    final h = items;
    selectedItems = h == null || path.length < 3
        ? const {}
        : {
            for (final t in h.all)
              if (_rectTouchesPolygon(h.rectOf(t), path)) t.id
          };
    notifyListeners();
  }

  static bool _rectTouchesPolygon(Rect r, List<Offset> poly) {
    if (poly.any(r.contains)) return true;
    final corners = [r.topLeft, r.topRight, r.bottomRight, r.bottomLeft];
    if (corners.any((c) => pointInPolygon(c, poly))) return true;
    for (var i = 0; i < 4; i++) {
      for (var j = 0; j < poly.length; j++) {
        if (segmentsIntersect(corners[i], corners[(i + 1) % 4], poly[j],
            poly[(j + 1) % poly.length])) {
          return true;
        }
      }
    }
    return false;
  }

  /// Striche, die das Lasso berühren – wie bei Goodnotes 6 reicht schon
  /// ein kleiner Teil des Strichs innerhalb oder auf der Lasso-Linie.
  static List<Stroke> strokesInPolygon(InkScene scene, List<Offset> poly) {
    var box = Rect.fromPoints(poly.first, poly.first);
    for (final p in poly) {
      box = box.expandToInclude(Rect.fromPoints(p, p));
    }
    final result = <Stroke>[];
    for (final s in scene.strokes) {
      if (s.deleted || !s.bounds.overlaps(box)) continue;
      if (_strokeTouchesPolygon(s, poly)) result.add(s);
    }
    return result;
  }

  static bool _strokeTouchesPolygon(Stroke s, List<Offset> poly) {
    final n = s.pointCount;
    Offset pt(int i) => Offset(s.points[i * 3], s.points[i * 3 + 1]);
    // 1. Liegt irgendein Punkt innerhalb?
    for (var i = 0; i < n; i++) {
      if (pointInPolygon(pt(i), poly)) return true;
    }
    // 2. Schneidet der Strich die Lasso-Linie (z. B. sehr dünnes Lasso)?
    final step = math.max(1, n ~/ 80);
    for (var i = 0; i + step < n; i += step) {
      final a = pt(i), b = pt(i + step);
      for (var j = 0; j < poly.length; j++) {
        final c = poly[j], d = poly[(j + 1) % poly.length];
        if (segmentsIntersect(a, b, c, d)) return true;
      }
    }
    return false;
  }

  /// Schneiden sich die Strecken a–b und c–d?
  static bool segmentsIntersect(Offset a, Offset b, Offset c, Offset d) {
    double cross(Offset o, Offset p, Offset q) =>
        (p.dx - o.dx) * (q.dy - o.dy) - (p.dy - o.dy) * (q.dx - o.dx);
    final d1 = cross(c, d, a), d2 = cross(c, d, b);
    final d3 = cross(a, b, c), d4 = cross(a, b, d);
    return ((d1 > 0) != (d2 > 0)) && ((d3 > 0) != (d4 > 0));
  }

  void beginMoveSelection(Offset world) => _beginTransform(world);

  void beginScaleSelection(Offset world) =>
      _beginTransform(world, scale: true);

  /// Drehen um die Mitte der Auswahl (rastet nah an 0°/45°/90° … ein).
  void beginRotateSelection(Offset world) =>
      _beginTransform(world, rotate: true);

  void _beginTransform(Offset world,
      {bool scale = false, bool rotate = false}) {
    final b = selectionBounds;
    if (b == null) return;
    draggingSelection = true;
    _scaling = scale;
    _rotating = rotate;
    _dragStart = world;
    scaleAnchor = b.topLeft;
    rotatePivot = b.center;
    dragOffset.value = Offset.zero;
    dragScale.value = 1.0;
    dragRotate.value = 0.0;
    // Originale ausblenden, solange die Vorschau mitwandert.
    scene.setDeleted(selection, true);
    notifyListeners();
  }

  /// Bewegt (bzw. skaliert) die Auswahl während des Ziehens.
  void moveSelection(Offset world) {
    final start = _dragStart;
    if (start == null) return;
    if (_rotating) {
      final from = start - rotatePivot, to = world - rotatePivot;
      if (from.distance < 1e-6 || to.distance < 1e-6) return;
      var d = to.direction - from.direction;
      if (d > math.pi) d -= 2 * math.pi;
      if (d < -math.pi) d += 2 * math.pi;
      // Gradzahl wie beim Geodreieck (gegen den Uhrzeigersinn positiv).
      final deg = ((-d * 180 / math.pi) % 360 + 360) % 360;
      final t = snapAngle(deg, settings.angleSnap);
      snapped = t != null;
      if (t != null) d = -(t > 180 ? t - 360 : t) * math.pi / 180;
      dragRotate.value = d;
    } else if (_scaling) {
      final from = (start - scaleAnchor).distance;
      if (from < 1e-6) return;
      final to = (world - scaleAnchor).distance;
      dragScale.value = (to / from).clamp(0.1, 10.0).toDouble();
    } else {
      dragOffset.value = world - start;
    }
  }

  void endMoveSelection() {
    if (!draggingSelection) return;
    final d = dragOffset.value;
    final s = dragScale.value;
    final r = dragRotate.value;
    final anchor = scaleAnchor, pivot = rotatePivot;
    draggingSelection = false;
    _scaling = false;
    _rotating = false;
    snapped = false;
    _dragStart = null;
    dragOffset.value = Offset.zero;
    dragScale.value = 1.0;
    dragRotate.value = 0.0;
    if (d.distance * camera.scale < 1 &&
        (s - 1).abs() < 0.01 &&
        r.abs() < 1e-4) {
      scene.setDeleted(selection, false);
      notifyListeners();
      return;
    }
    final before = _selItems;
    _apply(
      removed: selection,
      added: [
        for (final st in selection)
          _copy(st,
              offset: d, scale: s, anchor: anchor, rotate: r, pivot: pivot)
      ],
      before: before,
      after: [
        for (final t in before)
          moveItem(t, d, s, anchor, rotate: r, pivot: pivot)
      ],
    );
  }

  void recolorSelection(Color c) {
    final before = _selItems;
    _apply(
      removed: selection,
      added: [for (final s in selection) _copy(s, color: c.toARGB32())],
      before: before,
      after: [
        for (final t in before) t.isImage ? t : (t.copy()..color = c.toARGB32())
      ],
    );
  }

  void deleteSelection() {
    if (!hasSelection) return;
    _apply(removed: selection, before: _selItems);
  }

  void duplicateSelection() {
    if (!hasSelection) return;
    final shift = const Offset(24, 24) / camera.scale;
    _apply(
      added: [for (final s in selection) _copy(s, offset: shift)],
      after: [
        for (final t in _selItems)
          moveItem(t, shift, 1, Offset.zero, id: _newId())
      ],
    );
  }

  void copySelection() {
    if (!hasSelection) return;
    clipboard = [for (final s in selection) _copy(s)];
    itemClipboard = _selItems;
    notifyListeners();
  }

  void cutSelection() {
    if (!hasSelection) return;
    copySelection();
    deleteSelection();
  }

  bool get canPaste => clipboard.isNotEmpty || itemClipboard.isNotEmpty;

  /// Fügt die Zwischenablage ein – an der Stelle [at] (Weltkoordinate,
  /// z. B. langes Drücken mit dem Lasso) oder sonst in der Mitte des
  /// sichtbaren Bereichs. Auf einem Blatt bleibt alles auf dem Blatt.
  void paste({Offset? at}) {
    if (!canPaste) return;
    insertClip(clipboard, itemClipboard, at: at);
  }

  /// Fügt Striche und Elemente ein (z. B. aus der Elemente-Bibliothek) –
  /// mit neuen IDs, an [at] oder in der Mitte, als Lasso-Auswahl.
  void insertClip(List<Stroke> strokes, List<TextItem> clipItems,
      {Offset? at}) {
    final h = items;
    final its = h == null ? const <TextItem>[] : clipItems;
    final clipboard = strokes;
    Rect? b;
    for (final s in clipboard) {
      b = b == null ? s.bounds : b.expandToInclude(s.bounds);
    }
    for (final t in its) {
      final r = h!.rectOf(t);
      b = b == null ? r : b.expandToInclude(r);
    }
    if (b == null) return;
    final bounds = b;
    final view = camera.viewport;
    var target = at ??
        (view.isEmpty
            ? bounds.center + const Offset(24, 24)
            : camera.toWorld(Offset(view.width / 2, view.height / 2)));
    target = _keepOnSheet(target, bounds.size);
    final shift = target - bounds.center;
    settings.update(() => settings.tool = ToolMode.lasso);
    _apply(
      added: [for (final s in clipboard) _copy(s, offset: shift)],
      after: [for (final t in its) moveItem(t, shift, 1, Offset.zero, id: _newId())],
    );
  }

  /// Verschiebt einen Mittelpunkt so, dass ein Inhalt der Größe [size]
  /// möglichst ganz auf dem Blatt liegt.
  Offset _keepOnSheet(Offset center, Size size) {
    final b = drawBounds;
    if (b == null) return center;
    double fit(double v, double lo, double hi, double half) {
      if (hi - lo <= half * 2) return (lo + hi) / 2;
      return v.clamp(lo + half, hi - half).toDouble();
    }

    return Offset(fit(center.dx, b.left, b.right, size.width / 2),
        fit(center.dy, b.top, b.bottom, size.height / 2));
  }

  Stroke _copy(Stroke s,
      {Offset offset = Offset.zero,
      double scale = 1,
      Offset anchor = Offset.zero,
      double rotate = 0,
      Offset pivot = Offset.zero,
      int? color}) {
    final pts = Float32List.fromList(s.points);
    if (offset != Offset.zero || scale != 1 || rotate != 0) {
      for (var i = 0; i < pts.length; i += 3) {
        final q = transformPoint(Offset(pts[i], pts[i + 1]), offset, scale,
            anchor, rotate, pivot);
        pts[i] = q.dx;
        pts[i + 1] = q.dy;
      }
    }
    return Stroke(
      id: _newId(),
      color: color ?? s.color,
      width: s.width * scale,
      tool: s.tool,
      points: pts,
      fill: s.fill,
    );
  }

  // --- Verlauf ----------------------------------------------------------

  void undo() {
    clearSelection();
    if (_shapeHidden) cancelShape();
    editShape = null;
    if (history.undo(scene)) notifyListeners();
  }

  void redo() {
    clearSelection();
    if (_shapeHidden) cancelShape();
    editShape = null;
    if (history.redo(scene)) notifyListeners();
  }

  void clearAll() {
    final alive = scene.strokes.where((s) => !s.deleted).toList();
    if (alive.isEmpty) return;
    scene.setDeleted(alive, true);
    history.push(EraseStrokes(alive));
    selection = const [];
    notifyListeners();
  }

  /// Zeigt alle Inhalte im Fenster.
  void fitContent(Size view) {
    final r = scene.contentBounds();
    if (r == null || r.isEmpty) {
      camera.reset();
      return;
    }
    final sx = view.width / r.width, sy = view.height / r.height;
    camera.lookAt(r.center, (sx < sy ? sx : sy) * 0.9, view);
  }

  @override
  void dispose() {
    settings.removeListener(_onSettings);
    scene.dispose();
    camera.dispose();
    live.dispose();
    lassoPath.dispose();
    laserPath.dispose();
    dragOffset.dispose();
    dragScale.dispose();
    dragRotate.dispose();
    shapePreview.dispose();
    ruler.dispose();
    pageImages.dispose();
    pageLinks.dispose();
    super.dispose();
  }
}
