import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../app/theme.dart';
import '../ui/widgets.dart';
import 'camera.dart';
import 'ink_controller.dart';
import 'ink_scene.dart';
import 'live_stroke.dart';
import 'stroke_renderer.dart';

/// Die Zeichenfläche: nimmt Stift-, Finger-, Maus- und Trackpad-Eingaben
/// entgegen und zeichnet die Ebenen (Hintergrund, Striche, Live-Strich,
/// Auswahl, Laser).
///
/// Eingaberegeln:
/// - Stift: benutzt das gewählte Werkzeug.
/// - Finger (bei "Nur Stift"): 1 Finger verschiebt, 2 Finger zoomen.
///   Während der Stift schreibt, werden Finger ignoriert (Handballen).
/// - Finger (ohne "Nur Stift"): 1 Finger zeichnet, 2 Finger zoomen.
/// - 2 Finger kurz tippen: rückgängig. 3 Finger kurz tippen: wiederholen.
/// - Maus: linke Taste zeichnet, rechte/mittlere verschiebt, Rad zoomt.
/// - Trackpad: zwei Finger verschieben, Pinch zoomt.
/// - Stift mit Füller/Pinsel/Kugelschreiber kurz halten: Formerkennung.
class InkCanvasView extends StatefulWidget {
  const InkCanvasView({
    super.key,
    required this.controller,
    this.background,
    this.onBackgroundTap,
    this.onSwipe,
  });

  final InkController controller;

  /// Mit einem Finger schnell seitlich wischen: +1 = nach links gewischt
  /// (nächste Seite), -1 = nach rechts gewischt (vorige Seite).
  final ValueChanged<int>? onSwipe;

  /// Hintergrund (Seite mit Linien, Punktraster …). Standard: Punktraster.
  final CustomPainter? background;

  /// Kurzes Tippen auf eine leere Stelle, wenn Zeichnen aus ist.
  /// Liefert die Weltkoordinate.
  final ValueChanged<Offset>? onBackgroundTap;

  @override
  State<InkCanvasView> createState() => _InkCanvasViewState();
}

class _InkCanvasViewState extends State<InkCanvasView>
    with SingleTickerProviderStateMixin {
  InkController get c => widget.controller;

  int? _drawPointer;
  PointerDeviceKind? _drawKind;
  final Map<int, Offset> _touches = {};
  Offset? _pinchFocal;
  double? _pinchDistance;
  int? _panPointer;
  Offset? _panLast;
  double _lastTrackpadScale = 1;
  int? _tapPointer;
  Offset? _tapStart;

  // Mehrfinger-Tippen (rückgängig / wiederholen)
  final Map<int, Offset> _touchStarts = {};
  DateTime? _multiTapStart;
  int _multiTapMax = 0;
  bool _multiTapMoved = false;

  // Wischen zum Blättern
  int? _swipePointer;
  Offset? _swipeStart;
  DateTime? _swipeTime;

  // Lasso
  bool _movingSelection = false;

  // Formerkennung durch Halten
  Timer? _holdTimer;
  Offset? _holdAnchor;

  /// Position des Radierers auf dem Bildschirm (für den Kreis).
  final ValueNotifier<Offset?> _eraserPos = ValueNotifier(null);

  /// Laser verblasst nach dem Abheben.
  late final AnimationController _laserFade = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..addStatusListener((s) {
      if (s == AnimationStatus.completed) {
        c.clearLaser();
        _laserFade.value = 0;
      }
    });

  @override
  void dispose() {
    _holdTimer?.cancel();
    _eraserPos.dispose();
    _laserFade.dispose();
    super.dispose();
  }

  double _pressure(PointerEvent e) {
    if (e.kind == PointerDeviceKind.stylus ||
        e.kind == PointerDeviceKind.invertedStylus) {
      final range = e.pressureMax - e.pressureMin;
      if (range > 0) {
        return ((e.pressure - e.pressureMin) / range).clamp(0.0, 1.0).toDouble();
      }
    }
    return 0.5;
  }

  bool _wantsDraw(PointerDownEvent e) {
    if (!c.drawingEnabled) return false;
    switch (e.kind) {
      case PointerDeviceKind.stylus:
      case PointerDeviceKind.invertedStylus:
        return true;
      case PointerDeviceKind.mouse:
        return (e.buttons & kPrimaryMouseButton) != 0;
      case PointerDeviceKind.touch:
        return !c.stylusOnly && _touches.isEmpty;
      default:
        return false;
    }
  }

  /// Schreiben nur auf dem Blatt. Außerhalb verschiebt der Stift die
  /// Ansicht, statt zu zeichnen. Lasso, Radierer und Laser gehen überall.
  bool _allowedHere(PointerDownEvent e) {
    switch (c.tool) {
      case ToolMode.pen:
      case ToolMode.highlighter:
      case ToolMode.shape:
        return c.canDrawAt(c.camera.toWorld(e.localPosition));
      case ToolMode.eraser:
      case ToolMode.lasso:
      case ToolMode.laser:
        return true;
    }
  }

  // --- Werkzeuge ----------------------------------------------------------

  void _startDraw(PointerEvent e) {
    final world = c.camera.toWorld(e.localPosition);
    switch (c.tool) {
      case ToolMode.eraser:
        _eraserPos.value = e.localPosition;
        c.eraseAt(world, c.eraserSize);
      case ToolMode.lasso:
        if (c.isOnScaleHandle(world)) {
          _movingSelection = true;
          c.beginScaleSelection(world);
        } else if (c.isInsideSelection(world)) {
          _movingSelection = true;
          c.beginMoveSelection(world);
        } else {
          _movingSelection = false;
          c.beginLasso(world);
        }
      case ToolMode.shape:
        c.beginShape(world);
      case ToolMode.laser:
        _laserFade.stop();
        _laserFade.value = 0;
        c.beginLaser(world);
      case ToolMode.pen:
      case ToolMode.highlighter:
        c.beginStroke(world, _pressure(e));
        _restartHold(e.localPosition);
    }
  }

  void _moveDraw(PointerEvent e) {
    final world = c.camera.toWorld(e.localPosition);
    switch (c.tool) {
      case ToolMode.eraser:
        _eraserPos.value = e.localPosition;
        c.eraseAt(world, c.eraserSize);
      case ToolMode.lasso:
        if (_movingSelection) {
          c.moveSelection(world);
        } else {
          c.extendLasso(world);
        }
      case ToolMode.shape:
        c.updateShape(world);
      case ToolMode.laser:
        c.extendLaser(world);
      case ToolMode.pen:
      case ToolMode.highlighter:
        c.extendStroke(world, _pressure(e));
        // Erst bei echter Bewegung den Halte-Timer neu starten.
        final anchor = _holdAnchor;
        if (anchor == null || (e.localPosition - anchor).distance > 4) {
          _restartHold(e.localPosition);
        }
    }
  }

  void _endDraw({required bool commit}) {
    _holdTimer?.cancel();
    _holdAnchor = null;
    switch (c.tool) {
      case ToolMode.eraser:
        _eraserPos.value = null;
        c.endErase();
      case ToolMode.lasso:
        if (_movingSelection) {
          c.endMoveSelection();
        } else {
          c.endLasso();
        }
        _movingSelection = false;
      case ToolMode.shape:
        if (commit) {
          c.commitShape();
        } else {
          c.cancelStroke();
        }
      case ToolMode.laser:
        _laserFade.forward(from: 0);
      case ToolMode.pen:
      case ToolMode.highlighter:
        if (commit) {
          c.commitStroke();
        } else {
          c.cancelStroke();
        }
    }
    _drawPointer = null;
    _drawKind = null;
  }

  /// "Zeichnen und halten": Steht der Stift 0,55 s still, wird der Strich
  /// als Form erkannt.
  void _restartHold(Offset screen) {
    _holdAnchor = screen;
    _holdTimer?.cancel();
    _holdTimer = Timer(const Duration(milliseconds: 550), () {
      if (_drawPointer == null || !mounted) return;
      c.recognizeHeldStroke();
    });
  }

  // --- Ereignisse ---------------------------------------------------------

  void _onDown(PointerDownEvent e) {
    if (e.kind == PointerDeviceKind.stylus ||
        e.kind == PointerDeviceKind.invertedStylus) {
      c.onStylusDetected();
    }
    if (e.kind == PointerDeviceKind.touch) _trackMultiTapDown(e);

    if (_drawPointer == null && _wantsDraw(e) && _allowedHere(e)) {
      _drawPointer = e.pointer;
      _drawKind = e.kind;
      if (e.kind == PointerDeviceKind.touch) {
        _touches[e.pointer] = e.localPosition;
      }
      _startDraw(e);
      return;
    }
    // Mögliches Antippen einer leeren Stelle merken.
    if (_touches.isEmpty && _panPointer == null) {
      _tapPointer = e.pointer;
      _tapStart = e.localPosition;
    } else {
      _tapPointer = null;
    }
    if (e.kind == PointerDeviceKind.mouse ||
        e.kind == PointerDeviceKind.stylus ||
        e.kind == PointerDeviceKind.invertedStylus) {
      _panPointer = e.pointer;
      _panLast = e.localPosition;
      return;
    }
    if (e.kind == PointerDeviceKind.touch) {
      if (_touches.isEmpty) {
        _swipePointer = e.pointer;
        _swipeStart = e.localPosition;
        _swipeTime = DateTime.now();
      } else {
        _swipePointer = null; // zwei Finger = zoomen, nicht blättern
      }
      _touches[e.pointer] = e.localPosition;
      // Zweiter Finger, während ein Finger zeichnet: das war ein Zoom.
      if (_drawKind == PointerDeviceKind.touch) _endDraw(commit: false);
      _pinchFocal = null;
      _pinchDistance = null;
    }
  }

  void _onMove(PointerMoveEvent e) {
    if (e.pointer == _tapPointer &&
        _tapStart != null &&
        (e.localPosition - _tapStart!).distance > 8) {
      _tapPointer = null;
    }
    final start = _touchStarts[e.pointer];
    if (start != null && (e.localPosition - start).distance > 12) {
      _multiTapMoved = true;
    }
    if (e.pointer == _drawPointer) {
      if (e.kind == PointerDeviceKind.touch) {
        _touches[e.pointer] = e.localPosition;
      }
      _moveDraw(e);
      return;
    }
    if (e.pointer == _panPointer && _panLast != null) {
      c.camera.panBy(e.localPosition - _panLast!);
      _panLast = e.localPosition;
      return;
    }
    final prev = _touches[e.pointer];
    if (prev == null) return;
    _touches[e.pointer] = e.localPosition;
    // Handballen-Schutz: solange der Stift schreibt, keine Finger-Navigation.
    if (_drawKind == PointerDeviceKind.stylus) return;
    if (_touches.length == 1) {
      c.camera.panBy(e.localPosition - prev);
    } else {
      _updatePinch();
    }
  }

  void _updatePinch() {
    final pts = _touches.values.take(2).toList();
    final focal = (pts[0] + pts[1]) / 2;
    final dist = (pts[0] - pts[1]).distance;
    if (_pinchFocal != null && _pinchDistance != null && _pinchDistance! > 0) {
      c.camera.panBy(focal - _pinchFocal!);
      c.camera.zoomAt(focal, dist / _pinchDistance!);
    }
    _pinchFocal = focal;
    _pinchDistance = dist;
  }

  void _onUp(PointerEvent e, {required bool commit}) {
    if (e.pointer == _tapPointer && e is PointerUpEvent) {
      widget.onBackgroundTap?.call(c.camera.toWorld(e.localPosition));
    }
    if (e.pointer == _tapPointer) _tapPointer = null;
    if (e.pointer == _swipePointer) {
      _swipePointer = null;
      final start = _swipeStart, time = _swipeTime;
      if (e is PointerUpEvent && start != null && time != null) {
        final d = e.localPosition - start;
        final quick =
            DateTime.now().difference(time) < const Duration(milliseconds: 700);
        if (quick && d.dx.abs() > 70 && d.dx.abs() > d.dy.abs() * 1.8) {
          widget.onSwipe?.call(d.dx < 0 ? 1 : -1);
        }
      }
    }
    if (e.pointer == _drawPointer) _endDraw(commit: commit);
    if (e.pointer == _panPointer) {
      _panPointer = null;
      _panLast = null;
    }
    if (_touches.remove(e.pointer) != null) {
      _pinchFocal = null;
      _pinchDistance = null;
    }
    if (e.kind == PointerDeviceKind.touch) {
      _trackMultiTapUp(e, cancelled: e is PointerCancelEvent);
    }
  }

  // Zwei bzw. drei Finger kurz antippen.
  void _trackMultiTapDown(PointerDownEvent e) {
    if (_touchStarts.isEmpty) {
      _multiTapStart = DateTime.now();
      _multiTapMax = 0;
      _multiTapMoved = false;
    }
    _touchStarts[e.pointer] = e.localPosition;
    _multiTapMax = math.max(_multiTapMax, _touchStarts.length);
  }

  void _trackMultiTapUp(PointerEvent e, {required bool cancelled}) {
    _touchStarts.remove(e.pointer);
    if (cancelled) _multiTapMoved = true;
    if (_touchStarts.isNotEmpty) return;
    final start = _multiTapStart;
    _multiTapStart = null;
    if (start == null || _multiTapMoved) return;
    final quick =
        DateTime.now().difference(start) < const Duration(milliseconds: 300);
    if (!quick) return;
    if (_multiTapMax == 2) {
      c.undo();
    } else if (_multiTapMax == 3) {
      c.redo();
    }
  }

  void _onSignal(PointerSignalEvent e) {
    if (e is PointerScrollEvent) {
      c.camera.zoomAt(e.localPosition, math.exp(-e.scrollDelta.dy / 300));
    }
  }

  @override
  Widget build(BuildContext context) {
    // Die Auswahl-Aktionen liegen außerhalb des Listeners, damit ein Tippen
    // auf einen Knopf nicht gleichzeitig als Lasso-Strich zählt.
    return Stack(
      fit: StackFit.expand,
      children: [
        _input(context),
        _SelectionActions(controller: c),
      ],
    );
  }

  Widget _input(BuildContext context) {
    final mf = context.mf;
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: _onDown,
      onPointerMove: _onMove,
      onPointerUp: (e) => _onUp(e, commit: true),
      // iOS bricht Berührungen z. B. bei Systemgesten ab – der Strich
      // bleibt trotzdem erhalten, damit nichts verloren geht.
      onPointerCancel: (e) => _onUp(e, commit: true),
      onPointerSignal: _onSignal,
      onPointerPanZoomStart: (_) => _lastTrackpadScale = 1,
      onPointerPanZoomUpdate: (e) {
        c.camera.panBy(e.localPanDelta);
        if (_lastTrackpadScale > 0) {
          c.camera.zoomAt(e.localPosition, e.scale / _lastTrackpadScale);
        }
        _lastTrackpadScale = e.scale;
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          RepaintBoundary(
            child: CustomPaint(
                painter: widget.background ??
                    DotGridPainter(c.camera, const Color(0x22FFFFFF))),
          ),
          RepaintBoundary(
            child: CustomPaint(
                painter: _ScenePainter(c.scene, c.camera, c.drawBounds)),
          ),
          RepaintBoundary(
            child: CustomPaint(painter: _LivePainter(c.live, c.camera)),
          ),
          RepaintBoundary(
            child: CustomPaint(painter: _SelectionPainter(c, mf.accent)),
          ),
          RepaintBoundary(
            child: CustomPaint(painter: _LaserPainter(c, _laserFade)),
          ),
          IgnorePointer(
            child: CustomPaint(
              painter: _EraserPainter(_eraserPos, c, mf.textMuted),
            ),
          ),
        ],
      ),
    );
  }
}

/// Lasso-Linie, Auswahlrahmen, Skalier-Griff und die mitwandernde Vorschau.
class _SelectionPainter extends CustomPainter {
  _SelectionPainter(this.c, this.accent)
      : super(
            repaint: Listenable.merge([
          c,
          c.camera,
          c.lassoPath,
          c.dragOffset,
          c.dragScale,
          c.scene,
        ]));

  final InkController c;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final cam = c.camera;
    final path = c.lassoPath.value;
    if (path.length > 1) {
      final first = cam.toScreen(path.first);
      final p = Path()..moveTo(first.dx, first.dy);
      for (final w in path.skip(1)) {
        final s = cam.toScreen(w);
        p.lineTo(s.dx, s.dy);
      }
      canvas.drawPath(
          p,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5
            ..color = accent);
      p.close();
      canvas.drawPath(p, Paint()..color = accent.withValues(alpha: 0.08));
    }

    final bounds = c.selectionBounds;
    if (bounds == null || c.tool != ToolMode.lasso) return;
    final d = c.dragOffset.value;
    final s = c.dragScale.value;
    final anchor = c.scaleAnchor;

    // Weltpunkt → Bildschirm, inkl. laufender Verschiebung/Skalierung.
    Offset tf(Offset w) =>
        cam.toScreen(anchor + (w - anchor) * s + d);

    if (c.draggingSelection) {
      canvas.save();
      canvas.translate(cam.offset.dx, cam.offset.dy);
      canvas.scale(cam.scale);
      canvas.translate(anchor.dx + d.dx, anchor.dy + d.dy);
      canvas.scale(s);
      canvas.translate(-anchor.dx, -anchor.dy);
      for (final stroke in c.selection) {
        paintStroke(canvas, stroke);
      }
      canvas.restore();
    }
    final r = Rect.fromPoints(tf(bounds.topLeft), tf(bounds.bottomRight))
        .inflate(6);
    final rr = RRect.fromRectAndRadius(r, const Radius.circular(8));
    canvas.drawRRect(rr, Paint()..color = accent.withValues(alpha: 0.06));
    canvas.drawRRect(
        rr,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = accent);
    // Skalier-Griff unten rechts.
    canvas.drawCircle(r.bottomRight, 9, Paint()..color = Colors.white);
    canvas.drawCircle(
        r.bottomRight,
        9,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = accent);
  }

  @override
  bool shouldRepaint(_SelectionPainter old) => true;
}

/// Laserpointer: leuchtende rote Linie, verblasst nach dem Abheben.
class _LaserPainter extends CustomPainter {
  _LaserPainter(this.c, this.fade)
      : super(repaint: Listenable.merge([c.laserPath, c.camera, fade]));

  final InkController c;
  final Animation<double> fade;

  @override
  void paint(Canvas canvas, Size size) {
    final pts = c.laserPath.value;
    if (pts.isEmpty) return;
    final opacity = (1 - fade.value).clamp(0.0, 1.0).toDouble();
    if (opacity <= 0) return;
    final path = Path();
    final first = c.camera.toScreen(pts.first);
    path.moveTo(first.dx, first.dy);
    for (final w in pts.skip(1)) {
      final s = c.camera.toScreen(w);
      path.lineTo(s.dx, s.dy);
    }
    canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..strokeWidth = 10
          ..color = const Color(0xFFFF3B30).withValues(alpha: 0.25 * opacity)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4));
    canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..strokeWidth = 3
          ..color = const Color(0xFFFF453A).withValues(alpha: opacity));
    final last = c.camera.toScreen(pts.last);
    canvas.drawCircle(
        last, 5, Paint()..color = Colors.white.withValues(alpha: opacity));
  }

  @override
  bool shouldRepaint(_LaserPainter old) => true;
}

/// Kreis, der zeigt, wie groß der Radierer ist.
class _EraserPainter extends CustomPainter {
  _EraserPainter(this.pos, this.c, this.color) : super(repaint: pos);

  final ValueNotifier<Offset?> pos;
  final InkController c;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final p = pos.value;
    if (p == null) return;
    canvas.drawCircle(
        p,
        c.eraserSize,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..color = color);
  }

  @override
  bool shouldRepaint(_EraserPainter old) => true;
}

/// Aktionen für die Lasso-Auswahl, schwebend über der Auswahl.
class _SelectionActions extends StatelessWidget {
  const _SelectionActions({required this.controller});

  final InkController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return ListenableBuilder(
      listenable: Listenable.merge([c, c.camera]),
      builder: (context, _) {
        final b = c.selectionBounds;
        if (b == null || c.draggingSelection || c.tool != ToolMode.lasso) {
          return const SizedBox.shrink();
        }
        return LayoutBuilder(builder: (context, constraints) {
          final size = constraints.biggest;
          final top = c.camera.toScreen(b.topCenter);
          const panelWidth = 300.0;
          final left = (top.dx - panelWidth / 2)
              .clamp(8.0, math.max(8.0, size.width - panelWidth - 8))
              .toDouble();
          final above = top.dy - 70;
          final y = above < 8
              ? math.min(c.camera.toScreen(b.bottomCenter).dy + 20,
                  size.height - 64)
              : above;
          return Stack(
            children: [
              Positioned(
                left: left,
                top: y,
                child: FloatingPanel(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ToolButton(
                        icon: Icons.content_cut,
                        label: 'Ausschneiden',
                        onTap: c.cutSelection,
                      ),
                      ToolButton(
                        icon: Icons.content_copy,
                        label: 'Kopieren',
                        onTap: c.copySelection,
                      ),
                      ToolButton(
                        icon: Icons.copy_all_outlined,
                        label: 'Duplizieren',
                        onTap: c.duplicateSelection,
                      ),
                      ToolButton(
                        icon: Icons.delete_outline,
                        label: 'Löschen',
                        danger: true,
                        onTap: c.deleteSelection,
                      ),
                      ToolButton(
                        icon: Icons.close,
                        label: 'Auswahl aufheben',
                        onTap: c.clearSelection,
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        child: Text('${c.selection.length}',
                            style: TextStyle(
                                fontSize: 12, color: context.mf.textMuted)),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        });
      },
    );
  }
}

/// Dezentes Punktraster, damit Bewegung und Zoom sichtbar sind.
class DotGridPainter extends CustomPainter {
  DotGridPainter(this.camera, this.color, {this.fill})
      : super(repaint: camera);

  final Camera camera;
  final Color color;

  /// Optionale Hintergrundfarbe der Fläche.
  final Color? fill;
  static const double _worldSpacing = 40;

  @override
  void paint(Canvas canvas, Size size) {
    if (fill != null) {
      canvas.drawRect(Offset.zero & size, Paint()..color = fill!);
    }
    var spacing = _worldSpacing * camera.scale;
    // Beim Herauszoomen gröberes Raster, damit es nicht zu dicht wird.
    while (spacing < 14) {
      spacing *= 4;
    }
    final ox = camera.offset.dx % spacing;
    final oy = camera.offset.dy % spacing;
    final pts = <Offset>[];
    for (var x = ox; x < size.width; x += spacing) {
      for (var y = oy; y < size.height; y += spacing) {
        pts.add(Offset(x, y));
      }
    }
    canvas.drawPoints(
      ui.PointMode.points,
      pts,
      Paint()
        ..color = color
        ..strokeWidth = 1.6
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(DotGridPainter old) =>
      old.camera != camera || old.color != color || old.fill != fill;
}

/// Zeichnet die fertigen Striche – nur Abschnitte, die sichtbar sind.
class _ScenePainter extends CustomPainter {
  _ScenePainter(this.scene, this.camera, this.clip)
      : super(repaint: Listenable.merge([scene, camera]));

  final InkScene scene;
  final Camera camera;

  /// Nur innerhalb dieses Bereichs zeichnen (das Blatt).
  final Rect? clip;

  @override
  void paint(Canvas canvas, Size size) {
    final visible = camera.visibleWorldRect(size);
    canvas.save();
    canvas.translate(camera.offset.dx, camera.offset.dy);
    canvas.scale(camera.scale);
    final clip = this.clip;
    if (clip != null) canvas.clipRect(clip);
    for (final chunk in scene.chunks) {
      if (chunk.bounds.overlaps(visible)) canvas.drawPicture(chunk.picture);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_ScenePainter old) =>
      old.scene != scene || old.camera != camera || old.clip != clip;
}

/// Zeichnet nur den Strich, der gerade entsteht.
class _LivePainter extends CustomPainter {
  _LivePainter(this.live, this.camera)
      : super(repaint: Listenable.merge([live, camera]));

  final LiveStroke live;
  final Camera camera;

  @override
  void paint(Canvas canvas, Size size) {
    if (!live.active || live.points.isEmpty) return;
    canvas.save();
    canvas.translate(camera.offset.dx, camera.offset.dy);
    canvas.scale(camera.scale);
    paintPoints(canvas, live.points, live.width, live.color, live.tool);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_LivePainter old) =>
      old.live != live || old.camera != camera;
}
