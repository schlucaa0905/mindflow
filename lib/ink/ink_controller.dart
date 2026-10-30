import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:uuid/uuid.dart';

import 'camera.dart';
import 'ink_history.dart';
import 'ink_scene.dart';
import 'live_stroke.dart';
import 'stroke.dart';

enum ToolMode { pen, highlighter, eraser, lasso, shape }

/// Stiftart: Füller reagiert auf Druck, Kugelschreiber bleibt gleich dick.
enum PenType {
  fountain('Füller'),
  ballpoint('Kugelschreiber');

  const PenType(this.label);
  final String label;
}

enum EraserMode {
  stroke('Ganze Striche'),
  area('Nur berührte Stellen');

  const EraserMode(this.label);
  final String label;
}

enum ShapeKind {
  line('Linie'),
  arrow('Pfeil'),
  rectangle('Rechteck'),
  ellipse('Ellipse');

  const ShapeKind(this.label);
  final String label;
}

/// Bündelt alles, was eine Zeichenfläche braucht.
/// Die Oberfläche spricht nur mit dem Controller, nie direkt mit den Daten.
class InkController extends ChangeNotifier {
  InkController({bool? stylusOnly})
      : stylusOnly = stylusOnly ??
            (defaultTargetPlatform == TargetPlatform.iOS ||
                defaultTargetPlatform == TargetPlatform.android);

  final InkScene scene = InkScene();
  final Camera camera = Camera();
  final LiveStroke live = LiveStroke();
  final InkHistory history = InkHistory();
  static const _uuid = Uuid();

  // --- Werkzeug-Einstellungen --------------------------------------------

  ToolMode tool = ToolMode.pen;
  PenType penType = PenType.fountain;
  Color penColor = const Color(0xFFEDEDF2);
  Color highlighterColor = const Color(0xFFFACC15);
  double penWidth = 2.5;
  double highlighterWidth = 14;
  EraserMode eraserMode = EraserMode.stroke;
  double eraserSize = 12;
  ShapeKind shapeKind = ShapeKind.line;

  /// Selbst gewählte Farben (zusätzlich zur Palette).
  final List<Color> customColors = [];

  /// true: nur der Stift zeichnet, Finger verschieben und zoomen.
  bool stylusOnly;

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
    tool = t;
    notifyListeners();
  }

  void setPenType(PenType t) {
    penType = t;
    tool = ToolMode.pen;
    notifyListeners();
  }

  void setEraserMode(EraserMode m) {
    eraserMode = m;
    tool = ToolMode.eraser;
    notifyListeners();
  }

  void setEraserSize(double s) {
    eraserSize = s;
    notifyListeners();
  }

  void setShapeKind(ShapeKind k) {
    shapeKind = k;
    tool = ToolMode.shape;
    notifyListeners();
  }

  void setColor(Color c) {
    if (selection.isNotEmpty) {
      recolorSelection(c);
      return;
    }
    if (tool == ToolMode.highlighter) {
      highlighterColor = c;
    } else {
      penColor = c;
      if (tool == ToolMode.eraser || tool == ToolMode.lasso) {
        tool = ToolMode.pen;
      }
    }
    notifyListeners();
  }

  void addCustomColor(Color c) {
    customColors.removeWhere((x) => x.toARGB32() == c.toARGB32());
    customColors.insert(0, c);
    if (customColors.length > 6) customColors.removeLast();
    setColor(c);
  }

  /// Breite des aktiven Werkzeugs (Textmarker hat eine eigene).
  double get activeWidth =>
      tool == ToolMode.highlighter ? highlighterWidth : penWidth;

  void setWidth(double w) {
    if (tool == ToolMode.highlighter) {
      highlighterWidth = w;
    } else {
      penWidth = w;
    }
    notifyListeners();
  }

  /// true, sobald der Nutzer selbst umgeschaltet hat – dann greift die
  /// Automatik nicht mehr.
  bool _inputModeChosenByUser = false;

  void setStylusOnly(bool v) {
    stylusOnly = v;
    _inputModeChosenByUser = true;
    notifyListeners();
  }

  /// Wird bei jeder Stift-Berührung aufgerufen: Ist ein Stift im Spiel,
  /// sollen Finger navigieren statt zeichnen (wie bei Goodnotes).
  void onStylusDetected() {
    if (stylusOnly || _inputModeChosenByUser) return;
    stylusOnly = true;
    notifyListeners();
  }

  String _newId() => _uuid.v4();

  // --- Schreiben ---------------------------------------------------------

  void beginStroke(Offset world, double pressure) {
    final hl = tool == ToolMode.highlighter;
    // Breite in Weltkoordinaten: am Bildschirm wirkt der Stift immer gleich
    // dick, egal wie weit hineingezoomt ist.
    live.begin(world, pressure,
        width: (hl ? highlighterWidth : penWidth) / camera.scale,
        color: hl ? highlighterColor : penColor,
        tool: hl
            ? InkTool.highlighter
            : penType == PenType.ballpoint
                ? InkTool.ballpoint
                : InkTool.pen);
  }

  void extendStroke(Offset world, double pressure) =>
      live.extend(world, pressure, 0.6 / camera.scale);

  void commitStroke() {
    final width = live.width, color = live.color, t = live.tool;
    final pts = live.finish();
    if (pts == null || pts.isEmpty) return;
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

  void cancelStroke() => live.cancel();

  // --- Formen ------------------------------------------------------------

  Offset? _shapeStart;

  void beginShape(Offset world) {
    _shapeStart = world;
    updateShape(world);
  }

  void updateShape(Offset world) {
    final a = _shapeStart;
    if (a == null) return;
    live.setPoints(shapePoints(shapeKind, a, world, camera.scale),
        width: penWidth / camera.scale, color: penColor, tool: InkTool.ballpoint);
  }

  void commitShape() {
    final a = _shapeStart;
    _shapeStart = null;
    if (a == null) return;
    final pts = live.points;
    final width = live.width, color = live.color;
    final bounds = Stroke.computeBounds(Float32List.fromList(pts), 0);
    // Versehentliches Antippen erzeugt keine Form.
    if (bounds.longestSide * camera.scale < 6) {
      live.cancel();
      return;
    }
    final s = Stroke(
      id: _newId(),
      color: color.toARGB32(),
      width: width,
      tool: InkTool.ballpoint,
      points: Float32List.fromList(pts),
    );
    live.cancel();
    scene.add(s);
    history.push(AddStrokes([s]));
    notifyListeners();
  }

  /// Punkte einer Form. Wird als Kugelschreiber-Strich gezeichnet
  /// (gleichmäßige Breite, saubere Ecken).
  static List<double> shapePoints(
      ShapeKind kind, Offset a, Offset b, double scale) {
    const p = 0.6;
    List<double> poly(List<Offset> pts) =>
        [for (final o in pts) ...[o.dx, o.dy, p]];
    switch (kind) {
      case ShapeKind.line:
        return poly([a, b]);
      case ShapeKind.arrow:
        final d = b - a;
        final len = d.distance;
        if (len < 1e-3) return poly([a, b]);
        final u = d / len;
        final head = math.min(len * 0.4, 18 / scale);
        const angle = 0.5; // ca. 28°
        Offset rot(Offset v, double t) => Offset(
            v.dx * math.cos(t) - v.dy * math.sin(t),
            v.dx * math.sin(t) + v.dy * math.cos(t));
        final h1 = b - rot(u, angle) * head;
        final h2 = b - rot(u, -angle) * head;
        return poly([a, b, h1, b, h2]);
      case ShapeKind.rectangle:
        return poly([a, Offset(b.dx, a.dy), b, Offset(a.dx, b.dy), a]);
      case ShapeKind.ellipse:
        final c = Offset((a.dx + b.dx) / 2, (a.dy + b.dy) / 2);
        final rx = (b.dx - a.dx).abs() / 2, ry = (b.dy - a.dy).abs() / 2;
        const steps = 72;
        return poly([
          for (var i = 0; i <= steps; i++)
            Offset(c.dx + rx * math.cos(i / steps * math.pi * 2),
                c.dy + ry * math.sin(i / steps * math.pi * 2)),
        ]);
    }
  }

  // --- Radieren ---------------------------------------------------------

  final List<Stroke> _eraseRemoved = [];
  final List<Stroke> _eraseAdded = [];

  void eraseAt(Offset world, double screenRadius) {
    final r = screenRadius / camera.scale;
    if (eraserMode == EraserMode.stroke) {
      final hits = scene.hitTest(world, r);
      if (hits.isEmpty) return;
      scene.setDeleted(hits, true);
      _eraseRemoved.addAll(hits);
    } else {
      _eraseArea(world, r);
    }
  }

  /// Entfernt nur die Punkte im Radierer-Kreis und teilt Striche dabei auf.
  void _eraseArea(Offset world, double r) {
    final hits = scene.hitTest(world, r);
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
    if (_eraseRemoved.isEmpty) return;
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
    _eraseRemoved.clear();
    _eraseAdded.clear();
    notifyListeners();
  }

  // --- Lasso / Auswahl ----------------------------------------------------

  /// Die Linie, die gerade mit dem Lasso gezogen wird (Weltkoordinaten).
  final ValueNotifier<List<Offset>> lassoPath = ValueNotifier(const []);

  /// Verschiebung der Auswahl während des Ziehens.
  final ValueNotifier<Offset> dragOffset = ValueNotifier(Offset.zero);

  List<Stroke> selection = const [];
  bool draggingSelection = false;
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

  /// Striche, die überwiegend innerhalb des Polygons liegen.
  static List<Stroke> strokesInPolygon(InkScene scene, List<Offset> poly) {
    var box = Rect.fromPoints(poly.first, poly.first);
    for (final p in poly) {
      box = box.expandToInclude(Rect.fromPoints(p, p));
    }
    final result = <Stroke>[];
    for (final s in scene.strokes) {
      if (s.deleted || !s.bounds.overlaps(box)) continue;
      final n = s.pointCount;
      final step = math.max(1, n ~/ 24);
      var inside = 0, total = 0;
      for (var i = 0; i < n; i += step) {
        total++;
        if (_pointInPolygon(Offset(s.points[i * 3], s.points[i * 3 + 1]), poly)) {
          inside++;
        }
      }
      if (total > 0 && inside / total >= 0.5) result.add(s);
    }
    return result;
  }

  static bool _pointInPolygon(Offset p, List<Offset> poly) {
    var inside = false;
    for (var i = 0, j = poly.length - 1; i < poly.length; j = i++) {
      final a = poly[i], b = poly[j];
      if ((a.dy > p.dy) != (b.dy > p.dy) &&
          p.dx < (b.dx - a.dx) * (p.dy - a.dy) / (b.dy - a.dy) + a.dx) {
        inside = !inside;
      }
    }
    return inside;
  }

  void beginMoveSelection(Offset world) {
    if (selection.isEmpty) return;
    draggingSelection = true;
    _dragStart = world;
    dragOffset.value = Offset.zero;
    // Originale ausblenden, solange die Vorschau mitwandert.
    scene.setDeleted(selection, true);
    notifyListeners();
  }

  void moveSelection(Offset world) {
    final start = _dragStart;
    if (start == null) return;
    dragOffset.value = world - start;
  }

  void endMoveSelection() {
    if (!draggingSelection) return;
    final d = dragOffset.value;
    draggingSelection = false;
    _dragStart = null;
    dragOffset.value = Offset.zero;
    if (d.distance * camera.scale < 1) {
      scene.setDeleted(selection, false);
      notifyListeners();
      return;
    }
    _replaceSelection((s) => _copy(s, offset: d));
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
    final shift = Offset(24, 24) / camera.scale;
    final copies = [for (final s in selection) _copy(s, offset: shift)];
    scene.addAll(copies);
    history.push(AddStrokes(copies));
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

  Stroke _copy(Stroke s, {Offset offset = Offset.zero, int? color}) {
    final pts = Float32List.fromList(s.points);
    if (offset != Offset.zero) {
      for (var i = 0; i < pts.length; i += 3) {
        pts[i] += offset.dx;
        pts[i + 1] += offset.dy;
      }
    }
    return Stroke(
      id: _newId(),
      color: color ?? s.color,
      width: s.width,
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
    scene.dispose();
    camera.dispose();
    live.dispose();
    lassoPath.dispose();
    dragOffset.dispose();
    super.dispose();
  }
}
