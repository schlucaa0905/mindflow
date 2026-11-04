import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../app/theme.dart';
import '../ui/widgets.dart';
import 'camera.dart';
import 'stroke.dart';
import 'ink_controller.dart';
import 'ink_scene.dart';
import 'live_stroke.dart';
import 'stroke_renderer.dart';
import '../storage/element_library.dart';
import '../storage/image_store.dart';
import 'text_layer.dart' show paintPageImages;

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
    this.onTextTap,
    this.onSelectionToCard,
    this.onLinkTap,
    this.onSelectionToLink,
  });

  /// Link angetippt (Ziel `page:…` oder `obj:…`).
  final ValueChanged<String>? onLinkTap;

  /// Lasso-Auswahl → Link setzen.
  final VoidCallback? onSelectionToLink;

  /// Lasso-Auswahl → Karteikarte.
  final VoidCallback? onSelectionToCard;

  /// Text-Werkzeug: Antippen einer Stelle (Weltkoordinate) legt dort ein
  /// Textfeld an.
  final ValueChanged<Offset>? onTextTap;

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

  /// Letztes Finger-Ereignis (um „vergessene“ Finger zu erkennen).
  DateTime? _lastTouchEvent;

  // Wischen zum Blättern
  int? _swipePointer;
  Offset? _swipeStart;
  DateTime? _swipeTime;

  // Lasso
  bool _movingSelection = false;

  // Lineal mit den Fingern bewegen/drehen
  bool _rulerGrab = false;
  double? _rulerAngle;
  Offset? _rulerFocal;

  // Formerkennung durch Halten
  Timer? _holdTimer;
  Offset? _holdAnchor;

  // Lasso: lange drücken = Zwischenablage hier einfügen
  Timer? _pasteTimer;
  Offset? _pasteAnchor;
  bool _pastedByHold = false;

  /// Position des Radierers auf dem Bildschirm (für den Kreis).
  final ValueNotifier<Offset?> _eraserPos = ValueNotifier(null);

  // Pipette: Lupe unter dem Stift, Farbe beim Abheben.
  int? _pickPointer;
  final ValueNotifier<Offset?> _pickPos = ValueNotifier(null);
  final GlobalKey _surfaceKey = GlobalKey();

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
    _pasteTimer?.cancel();
    _eraserPos.dispose();
    _pickPos.dispose();
    _laserFade.dispose();
    super.dispose();
  }

  double _pressure(PointerEvent e) {
    if (e.kind == PointerDeviceKind.stylus ||
        e.kind == PointerDeviceKind.invertedStylus) {
      final range = e.pressureMax - e.pressureMin;
      if (range > 0) {
        return c.settings.applyPressure(
            ((e.pressure - e.pressureMin) / range).clamp(0.0, 1.0).toDouble());
      }
    }
    return 0.5;
  }

  bool _wantsDraw(PointerDownEvent e) {
    if (!c.drawingEnabled) return false;
    // Text-Werkzeug zeichnet nicht – Antippen legt ein Textfeld an.
    if (c.tool == ToolMode.text) return false;
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
      case ToolMode.shape:
        // Bearbeiten einer Form geht auch knapp neben dem Blatt.
        return c.editShape != null ||
            c.canDrawAt(c.camera.toWorld(e.localPosition));
      case ToolMode.pen:
      case ToolMode.highlighter:
        return c.canDrawAt(c.camera.toWorld(e.localPosition));
      case ToolMode.eraser:
      case ToolMode.lasso:
      case ToolMode.laser:
      case ToolMode.text:
        return true;
    }
  }

  // --- Werkzeuge ----------------------------------------------------------

  /// Werkzeug zu Beginn der Geste – ändert es sich währenddessen
  /// (z. B. Form antippen), läuft die Geste trotzdem sauber zu Ende.
  ToolMode? _gestureTool;
  Offset? _downAt;
  DateTime? _downTime;

  /// Kleines spürbares Klicken, sobald ein Winkel einrastet.
  void _clickOnSnap(bool was) {
    if (!was && c.snapped) HapticFeedback.selectionClick().ignore();
  }

  void _startDraw(PointerEvent e) {
    final world = c.camera.toWorld(e.localPosition);
    _gestureTool = c.tool;
    _downAt = e.localPosition;
    _downTime = DateTime.now();
    c.snapped = false;
    switch (c.tool) {
      case ToolMode.eraser:
        _eraserPos.value = e.localPosition;
        c.eraseAt(world, c.eraserSize);
      case ToolMode.lasso:
        if (c.isOnRotateHandle(world)) {
          _movingSelection = true;
          c.beginRotateSelection(world);
        } else if (c.isOnScaleHandle(world)) {
          _movingSelection = true;
          c.beginScaleSelection(world);
        } else if (c.isInsideSelection(world)) {
          _movingSelection = true;
          c.beginMoveSelection(world);
        } else {
          _movingSelection = false;
          c.beginLasso(world);
          _startPasteHold(e.localPosition, world);
        }
      case ToolMode.shape:
        c.beginShape(world);
      case ToolMode.laser:
        _laserFade.stop();
        _laserFade.value = 0;
        c.beginLaser(world);
      case ToolMode.text:
        break;
      case ToolMode.pen:
      case ToolMode.highlighter:
        c.beginStroke(world, _pressure(e));
        _restartHold(e.localPosition);
    }
  }

  void _moveDraw(PointerEvent e) {
    final world = c.camera.toWorld(e.localPosition);
    _lastDrawPos = e.localPosition;
    switch (_gestureTool ?? c.tool) {
      case ToolMode.eraser:
        _eraserPos.value = e.localPosition;
        c.eraseAt(world, c.eraserSize);
      case ToolMode.lasso:
        if (_movingSelection) {
          final wasL = c.snapped;
          c.moveSelection(world);
          _clickOnSnap(wasL);
        } else if (!_pastedByHold) {
          final anchor = _pasteAnchor;
          if (anchor != null && (e.localPosition - anchor).distance > 8) {
            _cancelPasteHold();
          }
          c.extendLasso(world);
        }
      case ToolMode.shape:
        final wasS = c.snapped;
        c.updateShape(world);
        _clickOnSnap(wasS);
      case ToolMode.laser:
        c.extendLaser(world);
      case ToolMode.text:
        break;
      case ToolMode.pen:
      case ToolMode.highlighter:
        final wasP = c.snapped;
        c.extendStroke(world, _pressure(e));
        _clickOnSnap(wasP);
        // Erst bei echter Bewegung den Halte-Timer neu starten.
        final anchor = _holdAnchor;
        if (anchor == null || (e.localPosition - anchor).distance > 4) {
          _restartHold(e.localPosition);
        }
    }
  }

  Offset? _lastDrawPos;

  /// Kurzes Tippen mit Stift/Textmarker auf eine Form: bearbeiten statt
  /// einen Punkt zu malen.
  bool _tappedShape() {
    final at = _downAt, t0 = _downTime;
    if (at == null || t0 == null) return false;
    final moved = ((_lastDrawPos ?? at) - at).distance;
    if (moved > 6 ||
        DateTime.now().difference(t0) > const Duration(milliseconds: 350)) {
      return false;
    }
    // Kurz auf einen Link getippt: öffnen statt einen Punkt zu malen.
    final link = c.linkAt(c.camera.toWorld(at));
    if (link != null && widget.onLinkTap != null) {
      widget.onLinkTap!(link.file!);
      return true;
    }
    return c.tryEditShapeAt(c.camera.toWorld(at));
  }

  void _endDraw({required bool commit}) {
    _holdTimer?.cancel();
    _holdAnchor = null;
    final tool = _gestureTool ?? c.tool;
    _gestureTool = null;
    switch (tool) {
      case ToolMode.eraser:
        _eraserPos.value = null;
        c.endErase();
      case ToolMode.lasso:
        _cancelPasteHold();
        if (_movingSelection) {
          c.endMoveSelection();
        } else if (!_pastedByHold) {
          c.endLasso();
        }
        _movingSelection = false;
        _pastedByHold = false;
      case ToolMode.shape:
        if (commit) {
          c.commitShape();
        } else {
          c.cancelShape();
        }
      case ToolMode.laser:
        _laserFade.forward(from: 0);
      case ToolMode.text:
        break;
      case ToolMode.pen:
      case ToolMode.highlighter:
        if (commit && !_tappedShape()) {
          c.commitStroke();
        } else {
          c.cancelStroke();
        }
    }
    _lastDrawPos = null;
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
      if (c.recognizeHeldStroke()) HapticFeedback.selectionClick().ignore();
    });
  }

  /// Lasso: Bleibt der Stift 0,5 s an einer Stelle stehen und gibt es etwas
  /// in der Zwischenablage, wird es genau dort eingefügt (wie Goodnotes).
  void _startPasteHold(Offset screen, Offset world) {
    _pasteTimer?.cancel();
    _pastedByHold = false;
    if (!c.canPaste) return;
    _pasteAnchor = screen;
    _pasteTimer = Timer(const Duration(milliseconds: 500), () {
      if (!mounted || _pastedByHold) return;
      _pastedByHold = true;
      c.lassoPath.value = const [];
      c.paste(at: world);
      HapticFeedback.mediumImpact().ignore();
    });
  }

  void _cancelPasteHold() {
    _pasteTimer?.cancel();
    _pasteTimer = null;
    _pasteAnchor = null;
  }

  /// Finger (bei „Nur Stift“) lange auf eine Stelle halten: einfügen.
  void _startFingerPasteHold(PointerDownEvent e) {
    if (c.tool != ToolMode.lasso || !c.canPaste || !c.drawingEnabled) return;
    final world = c.camera.toWorld(e.localPosition);
    if (c.isInsideSelection(world)) return;
    final pointer = e.pointer;
    _pasteTimer?.cancel();
    _pasteTimer = Timer(const Duration(milliseconds: 550), () {
      // Nur wenn der Finger noch liegt und sich nicht bewegt hat.
      if (!mounted || _tapPointer != pointer || _touches.length > 1) return;
      _tapPointer = null;
      _swipePointer = null;
      c.paste(at: world);
      HapticFeedback.mediumImpact().ignore();
    });
  }

  // --- Ereignisse ---------------------------------------------------------

  // --- Pipette ---------------------------------------------------------

  Future<void> _finishPick(Offset local, {required bool commit}) async {
    _pickPointer = null;
    _pickPos.value = null;
    if (!commit) return;
    final color = c.colorAt(c.camera.toWorld(local)) ?? await _screenColor(local);
    if (!mounted) return;
    if (color == null) {
      c.setPicking(false);
      return;
    }
    c.applyPickedColor(color);
    HapticFeedback.selectionClick().ignore();
  }

  /// Farbe eines Bildschirmpunkts (Bilder, PDF-Seiten, Papier).
  Future<Color?> _screenColor(Offset local) async {
    final ro = _surfaceKey.currentContext?.findRenderObject();
    if (ro is! RenderRepaintBoundary) return null;
    try {
      final img = await ro.toImage(pixelRatio: 1);
      final w = img.width, h = img.height;
      final data = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
      img.dispose();
      if (data == null || w == 0 || h == 0) return null;
      final x = local.dx.floor().clamp(0, w - 1).toInt();
      final y = local.dy.floor().clamp(0, h - 1).toInt();
      final i = (y * w + x) * 4;
      return Color.fromARGB(
          255, data.getUint8(i), data.getUint8(i + 1), data.getUint8(i + 2));
    } catch (_) {
      return null;
    }
  }

  void _onDown(PointerDownEvent e) {
    // Pipette: jede Berührung (Stift, Finger, Maus) nimmt die Farbe auf.
    if (c.picking && _touches.isEmpty) {
      _pickPointer = e.pointer;
      _pickPos.value = e.localPosition;
      return;
    }
    if (e.kind == PointerDeviceKind.stylus ||
        e.kind == PointerDeviceKind.invertedStylus) {
      c.onStylusDetected();
    }
    if (e.kind == PointerDeviceKind.touch) {
      _trackMultiTapDown(e);
    }

    // Es gibt nur einen Stift: Setzt er neu auf, während noch ein alter
    // Strich „hängt“ (das Abheben ging z. B. beim Zoomen verloren), wird der
    // alte sauber beendet – sonst ließe sich danach nicht mehr schreiben.
    final stylus = e.kind == PointerDeviceKind.stylus ||
        e.kind == PointerDeviceKind.invertedStylus;
    if (stylus &&
        _drawPointer != null &&
        _drawPointer != e.pointer &&
        (_drawKind == PointerDeviceKind.stylus ||
            _drawKind == PointerDeviceKind.invertedStylus)) {
      _endDraw(commit: true);
    }
    // Ebenso alte Finger, die nie losgelassen wurden: Liegt der Stift auf,
    // während nur noch „Geister“-Finger gemerkt sind, werden sie vergessen.
    if (stylus && _drawPointer == null && _touches.isNotEmpty) {
      final now = DateTime.now();
      final last = _lastTouchEvent;
      if (last == null || now.difference(last) > const Duration(seconds: 2)) {
        _touches.clear();
        _touchStarts.clear();
        _pinchFocal = null;
        _pinchDistance = null;
        _rulerGrab = false;
      }
    }

    if (e.kind == PointerDeviceKind.touch) _lastTouchEvent = DateTime.now();

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
      if (e.kind == PointerDeviceKind.touch) _startFingerPasteHold(e);
    } else {
      _tapPointer = null;
      _cancelPasteHold();
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
      // Erster Finger auf dem Lineal: Finger bewegen/drehen das Lineal.
      if (_touches.isEmpty) {
        _rulerGrab = c.onRuler(c.camera.toWorld(e.localPosition));
        if (_rulerGrab) _swipePointer = null;
      }
      _touches[e.pointer] = e.localPosition;
      // Zweiter Finger, während ein Finger zeichnet: das war ein Zoom.
      if (_drawKind == PointerDeviceKind.touch) _endDraw(commit: false);
      _pinchFocal = null;
      _pinchDistance = null;
    }
  }

  void _onMove(PointerMoveEvent e) {
    if (e.kind == PointerDeviceKind.touch) _lastTouchEvent = DateTime.now();
    if (e.pointer == _pickPointer) {
      _pickPos.value = e.localPosition;
      return;
    }
    if (e.pointer == _tapPointer &&
        _tapStart != null &&
        (e.localPosition - _tapStart!).distance > 8) {
      _tapPointer = null;
      if (_drawPointer == null) _cancelPasteHold();
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
    if (_rulerGrab) {
      final s = c.camera.scale;
      if (_touches.length == 1) {
        c.moveRuler((e.localPosition - prev) / s);
      } else {
        final pts = _touches.values.take(2).toList();
        final ang = (pts[1] - pts[0]).direction;
        final focal = (pts[0] + pts[1]) / 2;
        final pa = _rulerAngle, pf = _rulerFocal;
        if (pa != null && pf != null) {
          var d = ang - pa;
          if (d > math.pi) d -= 2 * math.pi;
          if (d < -math.pi) d += 2 * math.pi;
          c.moveRuler((focal - pf) / s, d);
        }
        _rulerAngle = ang;
        _rulerFocal = focal;
      }
      return;
    }
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
    if (e.pointer == _pickPointer) {
      _finishPick(e.localPosition, commit: e is PointerUpEvent);
      return;
    }
    if (e.pointer == _tapPointer && e is PointerUpEvent) {
      final world = c.camera.toWorld(e.localPosition);
      final link = c.linkAt(world);
      if (link != null && widget.onLinkTap != null) {
        widget.onLinkTap!(link.file!);
      } else if (c.drawingEnabled &&
          c.tool == ToolMode.text &&
          widget.onTextTap != null) {
        widget.onTextTap!(world);
      } else if (c.drawingEnabled && c.tryEditShapeAt(world)) {
        // Form angetippt: Griffe erscheinen.
      } else {
        widget.onBackgroundTap?.call(world);
      }
    }
    if (e.pointer == _tapPointer && _drawPointer == null) _cancelPasteHold();
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
      _rulerAngle = null;
      _rulerFocal = null;
      if (_touches.isEmpty) _rulerGrab = false;
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
        _SelectionActions(
            controller: c,
            onCard: widget.onSelectionToCard,
            onLink: widget.onSelectionToLink),
        _LineActions(controller: c),
        IgnorePointer(
          child: CustomPaint(
              painter: _LoupePainter(_pickPos, c)),
        ),
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
      child: RepaintBoundary(
        key: _surfaceKey,
        child: Stack(
        fit: StackFit.expand,
        children: [
          RepaintBoundary(
            child: CustomPaint(
                painter: widget.background ??
                    DotGridPainter(c.camera, const Color(0x22FFFFFF))),
          ),
          RepaintBoundary(
            child: CustomPaint(painter: _ImagePainter(c)),
          ),
          RepaintBoundary(
            child: CustomPaint(painter: _LinkPainter(c, mf.accent)),
          ),
          RepaintBoundary(
            child: CustomPaint(
                painter: _ScenePainter(c.scene, c.camera, c.drawBounds)),
          ),
          RepaintBoundary(
            child: CustomPaint(painter: _LivePainter(c.live, c.camera)),
          ),
          RepaintBoundary(
            child: CustomPaint(painter: _RulerPainter(c)),
          ),
          RepaintBoundary(
            child: CustomPaint(painter: _SelectionPainter(c, mf.accent)),
          ),
          RepaintBoundary(
            child: CustomPaint(painter: _LaserPainter(c, _laserFade)),
          ),
          RepaintBoundary(
            child: CustomPaint(painter: _ShapeEditPainter(c, mf.accent)),
          ),
          IgnorePointer(
            child: CustomPaint(
              painter: _EraserPainter(_eraserPos, c, mf.textMuted),
            ),
          ),
        ],
      ),
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
          c.dragRotate,
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
    final rot = c.dragRotate.value;
    final anchor = c.scaleAnchor, pivot = c.rotatePivot;

    if (c.draggingSelection) {
      canvas.save();
      canvas.translate(cam.offset.dx, cam.offset.dy);
      canvas.scale(cam.scale);
      canvas.translate(pivot.dx, pivot.dy);
      canvas.rotate(rot);
      canvas.translate(-pivot.dx, -pivot.dy);
      canvas.translate(anchor.dx + d.dx, anchor.dy + d.dy);
      canvas.scale(s);
      canvas.translate(-anchor.dx, -anchor.dy);
      for (final stroke in c.selection) {
        paintStroke(canvas, stroke);
      }
      canvas.restore();
    }
    // Rahmen (mitgedreht) – Weltpunkt → Bildschirm inkl. laufender Änderung.
    final box = bounds.inflate(6 / cam.scale);
    final corners = [
      for (final w in [
        box.topLeft, box.topRight, box.bottomRight, box.bottomLeft,
      ])
        cam.toScreen(c.previewPoint(w))
    ];
    final fill = Paint()..color = accent.withValues(alpha: 0.06);
    final edge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = accent;
    if (rot == 0) {
      final rr = RRect.fromRectAndRadius(
          Rect.fromPoints(corners[0], corners[2]), const Radius.circular(8));
      canvas.drawRRect(rr, fill);
      canvas.drawRRect(rr, edge);
    } else {
      final frame = Path()..addPolygon(corners, true);
      canvas.drawPath(frame, fill);
      canvas.drawPath(frame, edge);
    }
    final knob = Paint()..color = Colors.white;
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = accent;
    if (c.rotatingSelection) {
      // Drehwinkel in der Mitte anzeigen.
      final deg = -rot * 180 / math.pi;
      paintBadge(canvas, cam.toScreen(pivot),
          '${deg >= 0 ? '+' : '−'}${deg.abs().round()}°', accent,
          strong: c.snapped);
      return;
    }
    // Skalier-Griff unten rechts.
    canvas.drawCircle(corners[2], 9, knob);
    canvas.drawCircle(corners[2], 9, ring);
    if (c.draggingSelection) return;
    // Dreh-Griff unter der Auswahl.
    final h = c.rotateHandleScreen();
    if (h == null) return;
    final bottom = (corners[2] + corners[3]) / 2;
    canvas.drawLine(bottom, h - const Offset(0, 11), ring..strokeWidth = 1.5);
    canvas.drawCircle(h, 11, knob);
    canvas.drawCircle(h, 11, ring..strokeWidth = 2);
    const icon = Icons.rotate_right_rounded;
    final tp = TextPainter(
      text: TextSpan(
          text: String.fromCharCode(icon.codePoint),
          style: TextStyle(
              fontFamily: icon.fontFamily,
              package: icon.fontPackage,
              fontSize: 15,
              color: accent)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, h - Offset(tp.width / 2, tp.height / 2));
    tp.dispose();
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
  const _SelectionActions({required this.controller, this.onCard, this.onLink});

  final InkController controller;
  final VoidCallback? onCard;
  final VoidCallback? onLink;

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
          const panelWidth = 720.0;
          final left = (top.dx - panelWidth / 2)
              .clamp(8.0, math.max(8.0, size.width - panelWidth - 8))
              .toDouble();
          final above = top.dy - 70;
          // Passt nichts darüber: darunter, unterhalb des Dreh-Griffs.
          final y = above < 8
              ? math.min(c.camera.toScreen(b.bottomCenter).dy + 58,
                  size.height - 64)
              : above;
          return Stack(
            children: [
              Positioned(
                left: left,
                top: y,
                child: FloatingPanel(
                  child: ConstrainedBox(
                  constraints:
                      BoxConstraints(maxWidth: math.max(120.0, size.width - 40)),
                  child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _ActionPill(
                        icon: Icons.content_copy_rounded,
                        label: 'Kopieren',
                        onTap: () {
                          c.copySelection();
                          _copiedHint(context);
                        },
                      ),
                      _ActionPill(
                        icon: Icons.content_cut_rounded,
                        label: 'Ausschneiden',
                        onTap: () {
                          c.cutSelection();
                          _copiedHint(context);
                        },
                      ),
                      _ActionPill(
                        icon: Icons.copy_all_rounded,
                        label: 'Duplizieren',
                        onTap: c.duplicateSelection,
                      ),
                      if (onCard != null)
                        _ActionPill(
                          icon: Icons.style_outlined,
                          label: 'Karteikarte',
                          onTap: onCard!,
                        ),
                      if (onLink != null)
                        _ActionPill(
                          icon: Icons.link_rounded,
                          label: 'Verlinken',
                          onTap: onLink!,
                        ),
                      _ActionPill(
                        icon: Icons.bookmark_add_outlined,
                        label: 'Als Element',
                        onTap: () => saveSelectionAsElement(context, c),
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
                ),
              ),
            ],
          );
        });
      },
    );
  }
}

void _copiedHint(BuildContext context) {
  final m = ScaffoldMessenger.maybeOf(context);
  m?.hideCurrentSnackBar();
  m?.showSnackBar(const SnackBar(
    duration: Duration(seconds: 4),
    content: Text('Kopiert. Zum Einfügen mit dem Lasso lange auf eine Stelle '
        'drücken – auch auf einer anderen Seite oder in einem anderen '
        'Notizbuch.'),
  ));
}

/// Knopf mit Symbol und Text in der Auswahl-Leiste.
class _ActionPill extends StatelessWidget {
  const _ActionPill(
      {required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final mf = context.mf;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 17, color: mf.text),
            const SizedBox(width: 6),
            Text(label,
                style: TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600, color: mf.text)),
          ],
        ),
      ),
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

/// Form-Bearbeitung wie bei Goodnotes: dünner Rahmen mit runden Griffen,
/// bei Linien nur die beiden Enden.
class _ShapeEditPainter extends CustomPainter {
  _ShapeEditPainter(this.c, this.accent)
      : super(repaint: Listenable.merge([c, c.camera, c.shapePreview]));

  final InkController c;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final base = c.editShape;
    if (base == null || c.tool != ToolMode.shape) return;
    final s = c.shapePreview.value ?? base;
    final cam = c.camera;
    if (c.shapePreview.value != null) {
      canvas.save();
      canvas.translate(cam.offset.dx, cam.offset.dy);
      canvas.scale(cam.scale);
      paintStroke(canvas, s);
      canvas.restore();
    }
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = accent;
    final handles = InkController.shapeHandles(s);
    if (handles.length > 2) {
      final r = InkController.pointsRect(s);
      canvas.drawRect(
          Rect.fromPoints(cam.toScreen(r.topLeft), cam.toScreen(r.bottomRight)),
          line);
    }
    for (final h in handles) {
      final p = cam.toScreen(h);
      canvas.drawCircle(p, 7, Paint()..color = Colors.white);
      canvas.drawCircle(p, 7, line..strokeWidth = 2);
    }
    // Beim Ziehen eines Linienendes: Winkel und Länge anzeigen.
    if (handles.length == 2 && c.draggingShape) {
      final a = cam.toScreen(handles[0]), b = cam.toScreen(handles[1]);
      final n = b - a;
      final len = n.distance;
      final side = len < 1 ? Offset.zero : Offset(n.dy, -n.dx) / len * 30;
      paintBadge(canvas, (a + b) / 2 + side, lineLabel(s), accent,
          strong: c.snapped);
    }
  }

  @override
  bool shouldRepaint(_ShapeEditPainter old) => true;
}

/// Eingefügte Bilder – unter der Handschrift, damit man darauf schreiben kann.
class _ImagePainter extends CustomPainter {
  _ImagePainter(this.c)
      : super(
            repaint: Listenable.merge([
          c,
          c.camera,
          c.pageImages,
          c.dragOffset,
          c.dragScale,
          c.dragRotate,
          ImageStore.loaded,
        ]));

  final InkController c;

  @override
  void paint(Canvas canvas, Size size) {
    final list = c.pageImages.value;
    if (list.isEmpty) return;
    final cam = c.camera;
    canvas.save();
    canvas.translate(cam.offset.dx, cam.offset.dy);
    canvas.scale(cam.scale);
    paintPageImages(canvas, [
      for (final t in list)
        c.draggingSelection && c.selectedItems.contains(t.id)
            ? c.previewItem(t)
            : t
    ]);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_ImagePainter old) => true;
}

/// Das Lineal: halbdurchsichtig, mit Zentimeter-Skala und Winkelanzeige.
class _RulerPainter extends CustomPainter {
  _RulerPainter(this.c) : super(repaint: Listenable.merge([c.ruler, c.camera]));

  final InkController c;

  @override
  void paint(Canvas canvas, Size size) {
    final r = c.ruler.value;
    if (r == null) return;
    final cam = c.camera;
    const l = InkController.rulerLength, w = InkController.rulerWidth;
    canvas.save();
    canvas.translate(cam.offset.dx, cam.offset.dy);
    canvas.scale(cam.scale);
    canvas.translate(r.center.dx, r.center.dy);
    canvas.rotate(r.angle);
    final body = RRect.fromRectAndRadius(
        const Rect.fromLTWH(-l / 2, -w / 2, l, w), const Radius.circular(8));
    canvas.drawRRect(body, Paint()..color = const Color(0xB3303036));
    canvas.drawRRect(
        body,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1 / cam.scale
          ..color = const Color(0x66FFFFFF));
    // Skala: 1 cm = 28,35 Punkte, halbe Zentimeter kürzer.
    final tick = Paint()
      ..color = const Color(0xCCFFFFFF)
      ..strokeWidth = 1 / cam.scale;
    const cm = 28.3465;
    for (var i = 0; -l / 2 + i * cm / 2 <= l / 2; i++) {
      final x = -l / 2 + i * cm / 2;
      final len = i.isEven ? 14.0 : 8.0;
      canvas.drawLine(Offset(x, -w / 2), Offset(x, -w / 2 + len), tick);
      canvas.drawLine(Offset(x, w / 2), Offset(x, w / 2 - len), tick);
    }
    final deg = ((r.angle * 180 / math.pi) % 360 + 360) % 360;
    final tp = TextPainter(
      text: TextSpan(
          text: '${deg.round() % 360}°',
          style: const TextStyle(
              color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
    tp.dispose();
    canvas.restore();
  }

  @override
  bool shouldRepaint(_RulerPainter old) => true;
}

/// „37,5° · 5,2 cm“ – Winkel und Länge einer Linie.
String lineLabel(Stroke s) {
  final deg = InkController.lineAngle(s);
  final cm = InkController.lineLength(s) / 28.3465;
  return '${formatDegrees(deg)} · ${cm.toStringAsFixed(1).replaceAll('.', ',')} cm';
}

/// Grad mit höchstens einer Nachkommastelle (deutsch: Komma).
String formatDegrees(double deg) {
  var d = (deg * 10).round() / 10;
  if (d >= 360) d -= 360;
  final whole = d == d.roundToDouble();
  return '${whole ? d.round() : d.toStringAsFixed(1).replaceAll('.', ',')}°';
}

/// Kleines dunkles Schild mit Text (Winkel beim Ziehen/Drehen).
/// [strong]: eingerastet – in der Akzentfarbe.
void paintBadge(Canvas canvas, Offset center, String text, Color accent,
    {bool strong = false}) {
  final tp = TextPainter(
    text: TextSpan(
        text: text,
        style: const TextStyle(
            color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700)),
    textDirection: TextDirection.ltr,
  )..layout();
  final r = RRect.fromRectAndRadius(
      Rect.fromCenter(
          center: center, width: tp.width + 18, height: tp.height + 10),
      const Radius.circular(10));
  canvas.drawRRect(
      r, Paint()..color = strong ? accent : const Color(0xE6202026));
  tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
  tp.dispose();
}

/// Pipette: Lupe über dem Stift mit der Farbe darunter.
class _LoupePainter extends CustomPainter {
  _LoupePainter(this.pos, this.c)
      : super(repaint: Listenable.merge([pos, c.camera]));

  final ValueNotifier<Offset?> pos;
  final InkController c;

  @override
  void paint(Canvas canvas, Size size) {
    final p = pos.value;
    if (p == null) return;
    final color = c.colorAt(c.camera.toWorld(p));
    // Kreuz an der Spitze, Lupe darüber (nicht unter der Hand).
    final cross = Paint()
      ..color = Colors.white
      ..strokeWidth = 1.5;
    canvas.drawLine(p - const Offset(8, 0), p + const Offset(8, 0), cross);
    canvas.drawLine(p - const Offset(0, 8), p + const Offset(0, 8), cross);
    final at = Offset(p.dx, math.max(34.0, p.dy - 64));
    canvas.drawCircle(at, 26, Paint()..color = const Color(0x55000000));
    canvas.drawCircle(at, 24,
        Paint()..color = color ?? const Color(0x00000000));
    canvas.drawCircle(
        at,
        24,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4
          ..color = Colors.white);
  }

  @override
  bool shouldRepaint(_LoupePainter old) => true;
}

/// Bearbeitete Linie: Winkel genau einstellen (±1°, Eingabe), Einrasten
/// umschalten, löschen. Hält man ± gedrückt, dreht sie weiter.
class _LineActions extends StatelessWidget {
  const _LineActions({required this.controller});

  final InkController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return ListenableBuilder(
      listenable: Listenable.merge([c, c.camera, c.shapePreview]),
      builder: (context, _) {
        final e = c.editShape;
        final line = c.editLine;
        if (e == null ||
            line == null ||
            c.tool != ToolMode.shape ||
            c.draggingShape) {
          return const SizedBox.shrink();
        }
        final mf = context.mf;
        final p = line.points;
        final a = c.camera.toScreen(Offset(p[0], p[1]));
        final b = c.camera.toScreen(Offset(p[p.length - 3], p[p.length - 2]));
        final deg = InkController.lineAngle(line);
        return LayoutBuilder(builder: (context, box) {
          const w = 330.0, h = 48.0;
          final below = math.max(a.dy, b.dy) + 26;
          final top = below + h > box.maxHeight - 8
              ? math.max(8.0, math.min(a.dy, b.dy) - h - 26)
              : below;
          final left = ((a.dx + b.dx) / 2 - w / 2)
              .clamp(8.0, math.max(8.0, box.maxWidth - w - 8))
              .toDouble();
          return Stack(children: [
            Positioned(
              left: left,
              top: top,
              child: FloatingPanel(
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  _RepeatButton(
                    icon: Icons.remove_rounded,
                    tooltip: '1° weniger (halten: weiterdrehen)',
                    step: (cur) => (cur - 1e-6).ceilToDouble() - 1,
                    controller: c,
                  ),
                  Tooltip(
                    message: 'Winkel genau eingeben',
                    child: InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: () => _askAngle(context, c, deg),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 8),
                        child: Text(lineLabel(line),
                            style: TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w700,
                                fontFeatures: const [
                                  ui.FontFeature.tabularFigures()
                                ],
                                color: mf.text)),
                      ),
                    ),
                  ),
                  _RepeatButton(
                    icon: Icons.add_rounded,
                    tooltip: '1° mehr (halten: weiterdrehen)',
                    step: (cur) => (cur + 1e-6).floorToDouble() + 1,
                    controller: c,
                  ),
                  ToolButton(
                    icon: c.settings.angleSnap == AngleSnap.off
                        ? Icons.grid_off_rounded
                        : Icons.grid_on_rounded,
                    label: 'Einrasten: ${c.settings.angleSnap.label} – '
                        'tippen zum Wechseln',
                    selected: c.settings.angleSnap != AngleSnap.off,
                    onTap: () => c.settings.update(() => c.settings.angleSnap =
                        AngleSnap.values[(c.settings.angleSnap.index + 1) %
                            AngleSnap.values.length]),
                  ),
                  ToolButton(
                    icon: Icons.delete_outline,
                    label: 'Linie löschen',
                    danger: true,
                    onTap: c.deleteEditShape,
                  ),
                ]),
              ),
            ),
          ]);
        });
      },
    );
  }

  static Future<void> _askAngle(
      BuildContext context, InkController c, double current) async {
    final v = await askText(context,
        title: 'Winkel der Linie',
        initial: formatDegrees(current).replaceAll('°', ''),
        hint: '0 – 360, z. B. 44 oder 89,5',
        confirm: 'Übernehmen');
    final n = double.tryParse((v ?? '').replaceAll('°', '').replaceAll(',', '.').trim());
    if (n == null || !n.isFinite) return;
    c.setLineAngle((n % 360 + 360) % 360);
  }
}

/// ±-Knopf: Tippen = ein Schritt; Halten = weiterdrehen (Vorschau),
/// Loslassen übernimmt es als einen Rückgängig-Schritt.
class _RepeatButton extends StatefulWidget {
  const _RepeatButton(
      {required this.icon,
      required this.tooltip,
      required this.step,
      required this.controller});

  final IconData icon;
  final String tooltip;
  final double Function(double current) step;
  final InkController controller;

  @override
  State<_RepeatButton> createState() => _RepeatButtonState();
}

class _RepeatButtonState extends State<_RepeatButton> {
  Timer? _timer;
  bool _down = false;

  InkController get c => widget.controller;

  void _next({required bool preview}) {
    final line = c.editLine;
    if (line == null) return;
    final to = widget.step(InkController.lineAngle(line));
    c.setLineAngle((to % 360 + 360) % 360, preview: preview);
  }

  void _start() {
    _down = true;
    _next(preview: true);
    var ticks = 0;
    _timer = Timer(const Duration(milliseconds: 380), () {
      _timer = Timer.periodic(const Duration(milliseconds: 70), (_) {
        // Nach einer Weile schneller (5°-Schritte bleiben ganzzahlig).
        ticks++;
        _next(preview: true);
        if (ticks > 25) _next(preview: true);
      });
    });
  }

  void _end() {
    _timer?.cancel();
    _timer = null;
    if (!_down) return;
    _down = false;
    final line = c.editLine;
    if (line != null) {
      c.setLineAngle(InkController.lineAngle(line));
    }
  }

  @override
  void dispose() {
    // Verschwindet der Knopf mitten im Halten (Werkzeugwechsel), stellt
    // der Controller die Linie selbst wieder her.
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mf = context.mf;
    return Tooltip(
      message: widget.tooltip,
      child: Listener(
        onPointerDown: (_) => _start(),
        onPointerUp: (_) => _end(),
        onPointerCancel: (_) => _end(),
        child: Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: mf.text.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(widget.icon, size: 20, color: mf.text),
        ),
      ),
    );
  }
}

/// Links auf der Seite: zarte Fläche mit gestrichelter Unterkante und
/// Link-Zeichen – antippen öffnet das Ziel.
class _LinkPainter extends CustomPainter {
  _LinkPainter(this.c, this.accent)
      : super(
            repaint: Listenable.merge([
          c.camera,
          c.pageLinks,
          c.dragOffset,
          c.dragScale,
          c.dragRotate,
        ]));

  final InkController c;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final cam = c.camera;
    for (final raw in c.pageLinks.value) {
      final t = c.draggingSelection && c.selectedItems.contains(raw.id)
          ? c.previewItem(raw)
          : raw;
      final r = Rect.fromPoints(
          cam.toScreen(Offset(t.x, t.y)), cam.toScreen(Offset(t.x + t.w, t.y + t.h)));
      canvas.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(6)),
          Paint()..color = accent.withValues(alpha: 0.08));
      final dash = Paint()
        ..color = accent.withValues(alpha: 0.8)
        ..strokeWidth = 1.5;
      for (var x = r.left; x < r.right; x += 8) {
        canvas.drawLine(Offset(x, r.bottom), Offset(math.min(x + 4, r.right), r.bottom), dash);
      }
      canvas.drawCircle(r.topRight, 9, Paint()..color = accent);
      const icon = Icons.link_rounded;
      final tp = TextPainter(
        text: TextSpan(
            text: String.fromCharCode(icon.codePoint),
            style: TextStyle(
                fontFamily: icon.fontFamily,
                package: icon.fontPackage,
                fontSize: 13,
                color: Colors.white)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, r.topRight - Offset(tp.width / 2, tp.height / 2));
      tp.dispose();
    }
  }

  @override
  bool shouldRepaint(_LinkPainter old) => true;
}
