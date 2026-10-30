import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:uuid/uuid.dart';

import 'camera.dart';
import 'ink_history.dart';
import 'ink_scene.dart';
import 'live_stroke.dart';
import 'shape_recognizer.dart';
import 'stroke.dart';
import 'tool_settings.dart';

export 'tool_settings.dart';

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

  void setTool(ToolMode t) {
    if (t != ToolMode.lasso) clearSelection();
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

  void setShapeKind(ShapeKind k) => settings.update(() {
        settings.shapeKind = k;
        settings.tool = ToolMode.shape;
      });

  void setColor(Color c) {
    if (selection.isNotEmpty) {
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

  void addCustomColor(Color c) {
    final v = c.toARGB32();
    settings.update(() {
      settings.customColors.remove(v);
      settings.customColors.insert(0, v);
      if (settings.customColors.length > 6) settings.customColors.removeLast();
    });
    setColor(c);
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

  void saveCurrentAsPreset() {
    final p = PenPreset(
        type: penType, color: penColor.toARGB32(), width: penWidth);
    settings.update(() {
      settings.presets.removeWhere((x) =>
          x.type == p.type && x.color == p.color && x.width == p.width);
      settings.presets.add(p);
      if (settings.presets.length > 8) settings.presets.removeAt(0);
    });
  }

  void applyPreset(PenPreset p) {
    settings.update(() {
      settings.penType = p.type;
      settings.penWidth = p.width;
      if (darkPaper) {
        settings.penColorDark = p.color;
      } else {
        settings.penColorLight = p.color;
      }
      settings.tool = ToolMode.pen;
    });
    clearSelection();
  }

  void removePreset(PenPreset p) =>
      settings.update(() => settings.presets.remove(p));

  bool isActivePreset(PenPreset p) =>
      tool == ToolMode.pen &&
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

  void beginStroke(Offset world, double pressure) {
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
    // Breite in Weltkoordinaten: am Bildschirm wirkt der Stift immer gleich
    // dick, egal wie weit hineingezoomt ist.
    live.begin(world, pressure,
        width: (hl ? highlighterWidth : penWidth) / camera.scale,
        color: hl ? highlighterColor : penColor,
        tool: t);
  }

  /// true, wenn der Textmarker durch Halten zur geraden Linie wurde.
  bool _straightLine = false;

  void extendStroke(Offset world, double pressure) {
    if (shapeLocked) {
      if (_straightLine && live.points.length >= 6) {
        final p = live.points;
        final w = clampToBounds(world);
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
      final b = Offset(p[p.length - 3], p[p.length - 2]);
      if ((b - a).distance * camera.scale < 12) return false;
      live.setPoints([a.dx, a.dy, 0.5, b.dx, b.dy, 0.5],
          width: live.width, color: live.color, tool: InkTool.highlighter);
      shapeLocked = true;
      _straightLine = true;
      return true;
    }
    if (!settings.shapeRecognition) return false;
    final shape = recognizeShape(live.points, minSize: 12 / camera.scale);
    if (shape == null) return false;
    live.setPoints(shape,
        width: live.width, color: live.color, tool: InkTool.ballpoint);
    shapeLocked = true;
    return true;
  }

  void commitStroke() {
    final width = live.width, color = live.color, t = live.tool;
    shapeLocked = false;
    _straightLine = false;
    var pts = live.finish();
    if (pts == null || pts.isEmpty) return;
    // Textmarker gerade ziehen (Option).
    if (t == InkTool.highlighter &&
        settings.highlighterStraight &&
        pts.length >= 6) {
      final n = pts.length;
      pts = Float32List.fromList(
          [pts[0], pts[1], 0.5, pts[n - 3], pts[n - 2], 0.5]);
    }
    final s = Stroke(
      id: _newId(),
      color: color.toARGB32(),
      width: width,
      tool: t,
      points: pts,
    );
    scene.add(s);
    history.push(AddStrokes([s]));
    notifyListeners();
  }

  void cancelStroke() {
    shapeLocked = false;
    _straightLine = false;
    live.cancel();
  }

  // --- Formen-Werkzeug -----------------------------------------------------

  Offset? _shapeStart;

  void beginShape(Offset world) {
    _shapeStart = world;
    updateShape(world);
  }

  void updateShape(Offset world) {
    final a = _shapeStart;
    if (a == null) return;
    live.setPoints(shapePoints(shapeKind, a, clampToBounds(world), camera.scale),
        width: penWidth / camera.scale,
        color: penColor,
        tool: InkTool.ballpoint);
  }

  void commitShape() {
    final a = _shapeStart;
    _shapeStart = null;
    if (a == null) return;
    final pts = Float32List.fromList(live.points);
    final width = live.width, color = live.color;
    final bounds = Stroke.computeBounds(pts, 0);
    // Versehentliches Antippen erzeugt keine Form.
    if (bounds.longestSide * camera.scale < 8) {
      live.cancel();
      return;
    }
    final s = Stroke(
      id: _newId(),
      color: color.toARGB32(),
      width: width,
      tool: InkTool.ballpoint,
      points: pts,
    );
    live.cancel();
    scene.add(s);
    history.push(AddStrokes([s]));
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

  List<Stroke> selection = const [];

  /// true, solange die Auswahl verschoben oder skaliert wird.
  bool draggingSelection = false;
  bool _scaling = false;
  Offset? _dragStart;

  Rect? get selectionBounds {
    if (selection.isEmpty) return null;
    var r = selection.first.bounds;
    for (final s in selection.skip(1)) {
      r = r.expandToInclude(s.bounds);
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

  void clearSelection() {
    if (selection.isEmpty && lassoPath.value.isEmpty) return;
    selection = const [];
    lassoPath.value = const [];
    notifyListeners();
  }

  void beginLasso(Offset world) {
    selection = const [];
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
    notifyListeners();
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

  void beginMoveSelection(Offset world) => _beginTransform(world, scale: false);

  void beginScaleSelection(Offset world) => _beginTransform(world, scale: true);

  void _beginTransform(Offset world, {required bool scale}) {
    final b = selectionBounds;
    if (b == null) return;
    draggingSelection = true;
    _scaling = scale;
    _dragStart = world;
    scaleAnchor = b.topLeft;
    dragOffset.value = Offset.zero;
    dragScale.value = 1.0;
    // Originale ausblenden, solange die Vorschau mitwandert.
    scene.setDeleted(selection, true);
    notifyListeners();
  }

  /// Bewegt (bzw. skaliert) die Auswahl während des Ziehens.
  void moveSelection(Offset world) {
    final start = _dragStart;
    if (start == null) return;
    if (_scaling) {
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
    final anchor = scaleAnchor;
    draggingSelection = false;
    _scaling = false;
    _dragStart = null;
    dragOffset.value = Offset.zero;
    dragScale.value = 1.0;
    if (d.distance * camera.scale < 1 && (s - 1).abs() < 0.01) {
      scene.setDeleted(selection, false);
      notifyListeners();
      return;
    }
    _replaceSelection(
        (stroke) => _copy(stroke, offset: d, scale: s, anchor: anchor));
  }

  void recolorSelection(Color c) =>
      _replaceSelection((s) => _copy(s, color: c.toARGB32()));

  void deleteSelection() {
    if (selection.isEmpty) return;
    final list = selection;
    scene.setDeleted(list, true);
    history.push(EraseStrokes(list));
    selection = const [];
    notifyListeners();
  }

  void duplicateSelection() {
    if (selection.isEmpty) return;
    final shift = const Offset(24, 24) / camera.scale;
    final copies = [for (final s in selection) _copy(s, offset: shift)];
    scene.addAll(copies);
    history.push(AddStrokes(copies));
    selection = copies;
    notifyListeners();
  }

  void copySelection() {
    if (selection.isEmpty) return;
    clipboard = [for (final s in selection) _copy(s)];
    notifyListeners();
  }

  void cutSelection() {
    if (selection.isEmpty) return;
    copySelection();
    deleteSelection();
  }

  bool get canPaste => clipboard.isNotEmpty;

  /// Fügt die Zwischenablage in der Mitte des sichtbaren Bereichs ein.
  void paste() {
    if (clipboard.isEmpty) return;
    var bounds = clipboard.first.bounds;
    for (final s in clipboard.skip(1)) {
      bounds = bounds.expandToInclude(s.bounds);
    }
    final view = camera.viewport;
    final target = view.isEmpty
        ? bounds.center + const Offset(24, 24)
        : camera.toWorld(Offset(view.width / 2, view.height / 2));
    final shift = target - bounds.center;
    final copies = [for (final s in clipboard) _copy(s, offset: shift)];
    scene.addAll(copies);
    history.push(AddStrokes(copies));
    settings.update(() => settings.tool = ToolMode.lasso);
    selection = copies;
    notifyListeners();
  }

  void _replaceSelection(Stroke Function(Stroke) transform) {
    if (selection.isEmpty) return;
    final old = selection;
    final copies = [for (final s in old) transform(s)];
    scene.setDeleted(old, true);
    scene.addAll(copies);
    history.push(ReplaceStrokes(removed: old, added: copies));
    selection = copies;
    notifyListeners();
  }

  Stroke _copy(Stroke s,
      {Offset offset = Offset.zero,
      double scale = 1,
      Offset anchor = Offset.zero,
      int? color}) {
    final pts = Float32List.fromList(s.points);
    if (offset != Offset.zero || scale != 1) {
      for (var i = 0; i < pts.length; i += 3) {
        pts[i] = anchor.dx + (pts[i] - anchor.dx) * scale + offset.dx;
        pts[i + 1] = anchor.dy + (pts[i + 1] - anchor.dy) * scale + offset.dy;
      }
    }
    return Stroke(
      id: _newId(),
      color: color ?? s.color,
      width: s.width * scale,
      tool: s.tool,
      points: pts,
    );
  }

  // --- Verlauf ----------------------------------------------------------

  void undo() {
    clearSelection();
    if (history.undo(scene)) notifyListeners();
  }

  void redo() {
    clearSelection();
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
    super.dispose();
  }
}
