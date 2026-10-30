import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:uuid/uuid.dart';

import 'camera.dart';
import 'ink_history.dart';
import 'ink_scene.dart';
import 'live_stroke.dart';
import 'stroke.dart';

enum ToolMode { pen, highlighter, eraser }

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

  ToolMode tool = ToolMode.pen;
  Color penColor = const Color(0xFFEDEDF2);
  Color highlighterColor = const Color(0xFFFACC15);
  double penWidth = 2.5;

  /// true: nur der Stift zeichnet, Finger verschieben und zoomen.
  bool stylusOnly;

  /// false: niemand zeichnet, jede Eingabe verschiebt die Fläche
  /// (z. B. im Canvas-Modus "Auswählen" oder "Navigieren").
  bool drawingEnabled = true;

  void setDrawingEnabled(bool v) {
    if (drawingEnabled == v) return;
    drawingEnabled = v;
    if (!v) live.cancel();
    notifyListeners();
  }

  final List<Stroke> _eraseBatch = [];

  void setTool(ToolMode t) {
    tool = t;
    notifyListeners();
  }

  void setColor(Color c) {
    if (tool == ToolMode.highlighter) {
      highlighterColor = c;
    } else {
      penColor = c;
      if (tool == ToolMode.eraser) tool = ToolMode.pen;
    }
    notifyListeners();
  }

  void setWidth(double w) {
    penWidth = w;
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

  // --- Zeichnen ---------------------------------------------------------

  void beginStroke(Offset world, double pressure) {
    final hl = tool == ToolMode.highlighter;
    // Breite in Weltkoordinaten: am Bildschirm wirkt der Stift immer gleich
    // dick, egal wie weit hineingezoomt ist.
    final screenWidth = hl ? penWidth * 6 : penWidth;
    live.begin(world, pressure,
        width: screenWidth / camera.scale,
        color: hl ? highlighterColor : penColor,
        tool: hl ? InkTool.highlighter : InkTool.pen);
  }

  void extendStroke(Offset world, double pressure) =>
      live.extend(world, pressure, 0.6 / camera.scale);

  void commitStroke() {
    final width = live.width, color = live.color, t = live.tool;
    final pts = live.finish();
    if (pts == null || pts.isEmpty) return;
    final s = Stroke(
      id: _uuid.v4(),
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

  // --- Radieren ---------------------------------------------------------

  void eraseAt(Offset world, double screenRadius) {
    final hits = scene.hitTest(world, screenRadius / camera.scale);
    if (hits.isEmpty) return;
    scene.setDeleted(hits, true);
    _eraseBatch.addAll(hits);
  }

  void endErase() {
    if (_eraseBatch.isEmpty) return;
    history.push(EraseStrokes(List.of(_eraseBatch)));
    _eraseBatch.clear();
    notifyListeners();
  }

  // --- Verlauf ----------------------------------------------------------

  void undo() {
    if (history.undo(scene)) notifyListeners();
  }

  void redo() {
    if (history.redo(scene)) notifyListeners();
  }

  void clearAll() {
    final alive = scene.strokes.where((s) => !s.deleted).toList();
    if (alive.isEmpty) return;
    scene.setDeleted(alive, true);
    history.push(EraseStrokes(alive));
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
    super.dispose();
  }
}
