import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'camera.dart';
import 'ink_controller.dart';
import 'ink_scene.dart';
import 'live_stroke.dart';
import 'stroke_renderer.dart';

/// Die Zeichenfläche: nimmt Stift-, Finger-, Maus- und Trackpad-Eingaben
/// entgegen und zeichnet drei Ebenen (Raster, fertige Striche, Live-Strich).
///
/// Eingaberegeln:
/// - Stift: zeichnet immer.
/// - Finger (bei "Nur Stift"): 1 Finger verschiebt, 2 Finger zoomen.
///   Während der Stift schreibt, werden Finger ignoriert (Handballen).
/// - Finger (ohne "Nur Stift"): 1 Finger zeichnet, 2 Finger zoomen.
/// - Maus: linke Taste zeichnet, rechte/mittlere verschiebt, Rad zoomt.
/// - Trackpad: zwei Finger verschieben, Pinch zoomt.
class InkCanvasView extends StatefulWidget {
  const InkCanvasView({super.key, required this.controller});

  final InkController controller;

  @override
  State<InkCanvasView> createState() => _InkCanvasViewState();
}

class _InkCanvasViewState extends State<InkCanvasView> {
  static const double _eraserScreenRadius = 12;

  InkController get c => widget.controller;

  int? _drawPointer;
  PointerDeviceKind? _drawKind;
  final Map<int, Offset> _touches = {};
  Offset? _pinchFocal;
  double? _pinchDistance;
  int? _panPointer;
  Offset? _panLast;
  double _lastTrackpadScale = 1;

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

  // --- Zeichnen / Radieren ----------------------------------------------

  void _startDraw(PointerEvent e) {
    final world = c.camera.toWorld(e.localPosition);
    if (c.tool == ToolMode.eraser) {
      c.eraseAt(world, _eraserScreenRadius);
    } else {
      c.beginStroke(world, _pressure(e));
    }
  }

  void _moveDraw(PointerEvent e) {
    final world = c.camera.toWorld(e.localPosition);
    if (c.tool == ToolMode.eraser) {
      c.eraseAt(world, _eraserScreenRadius);
    } else {
      c.extendStroke(world, _pressure(e));
    }
  }

  void _endDraw({required bool commit}) {
    if (c.tool == ToolMode.eraser) {
      c.endErase();
    } else if (commit) {
      c.commitStroke();
    } else {
      c.cancelStroke();
    }
    _drawPointer = null;
    _drawKind = null;
  }

  // --- Ereignisse -------------------------------------------------------

  void _onDown(PointerDownEvent e) {
    if (_drawPointer == null && _wantsDraw(e)) {
      _drawPointer = e.pointer;
      _drawKind = e.kind;
      if (e.kind == PointerDeviceKind.touch) _touches[e.pointer] = e.localPosition;
      _startDraw(e);
      return;
    }
    if (e.kind == PointerDeviceKind.mouse) {
      _panPointer = e.pointer;
      _panLast = e.localPosition;
      return;
    }
    if (e.kind == PointerDeviceKind.touch) {
      _touches[e.pointer] = e.localPosition;
      // Zweiter Finger, während ein Finger zeichnet: das war ein Zoom.
      if (_drawKind == PointerDeviceKind.touch) _endDraw(commit: false);
      _pinchFocal = null;
      _pinchDistance = null;
    }
  }

  void _onMove(PointerMoveEvent e) {
    if (e.pointer == _drawPointer) {
      if (e.kind == PointerDeviceKind.touch) _touches[e.pointer] = e.localPosition;
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
    if (e.pointer == _drawPointer) _endDraw(commit: commit);
    if (e.pointer == _panPointer) {
      _panPointer = null;
      _panLast = null;
    }
    if (_touches.remove(e.pointer) != null) {
      _pinchFocal = null;
      _pinchDistance = null;
    }
  }

  void _onSignal(PointerSignalEvent e) {
    if (e is PointerScrollEvent) {
      c.camera.zoomAt(e.localPosition, math.exp(-e.scrollDelta.dy / 300));
    }
  }

  @override
  Widget build(BuildContext context) {
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
            child: CustomPaint(painter: _GridPainter(c.camera)),
          ),
          RepaintBoundary(
            child: CustomPaint(painter: _ScenePainter(c.scene, c.camera)),
          ),
          RepaintBoundary(
            child: CustomPaint(painter: _LivePainter(c.live, c.camera)),
          ),
        ],
      ),
    );
  }
}

/// Dezentes Punktraster, damit Bewegung und Zoom sichtbar sind.
class _GridPainter extends CustomPainter {
  _GridPainter(this.camera) : super(repaint: camera);

  final Camera camera;
  static const double _worldSpacing = 40;

  @override
  void paint(Canvas canvas, Size size) {
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
        ..color = const Color(0x22FFFFFF)
        ..strokeWidth = 1.6
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_GridPainter old) => old.camera != camera;
}

/// Zeichnet die fertigen Striche – nur Abschnitte, die sichtbar sind.
class _ScenePainter extends CustomPainter {
  _ScenePainter(this.scene, this.camera)
      : super(repaint: Listenable.merge([scene, camera]));

  final InkScene scene;
  final Camera camera;

  @override
  void paint(Canvas canvas, Size size) {
    final visible = camera.visibleWorldRect(size);
    canvas.save();
    canvas.translate(camera.offset.dx, camera.offset.dy);
    canvas.scale(camera.scale);
    for (final chunk in scene.chunks) {
      if (chunk.bounds.overlaps(visible)) canvas.drawPicture(chunk.picture);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_ScenePainter old) =>
      old.scene != scene || old.camera != camera;
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
