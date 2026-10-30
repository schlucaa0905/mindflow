import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/services.dart';
import '../app/theme.dart';
import '../storage/ink_store.dart';
import 'camera.dart';
import 'ink_canvas_view.dart';
import 'ink_controller.dart';
import 'ink_session.dart';
import 'ink_toolbar.dart';

/// Eine fertige Schreibfläche für ein Objekt: Zeichnen, Werkzeugleiste,
/// automatisches Laden und Speichern. Notizbuch und Canvas nutzen dieselbe.
///
/// Die Werkzeugleiste lässt sich am Griff verschieben: in die Nähe eines
/// Randes ziehen dockt sie dort an (oben, unten, links, rechts), sonst
/// schwebt sie frei. Die Position wird gemerkt.
class InkSurface extends StatefulWidget {
  const InkSurface({
    super.key,
    required this.inkId,
    required this.paper,
    this.fitRect,
    this.lockToFit = false,
    this.backgroundBuilder,
    this.overlayBuilder,
    this.toolbarLeading = const [],
    this.toolbarTrailing = const [],
    this.showInkTools = true,
    this.toolbarInsets = const EdgeInsets.fromLTRB(12, 64, 12, 16),
    this.onSaved,
    this.onControllerReady,
    this.onBackgroundTap,
  });

  /// ID des Objekts, dessen Handschrift gezeigt wird.
  final String inkId;
  final Paper paper;

  /// Bereich, der beim Öffnen ins Bild gesetzt wird (z. B. die Seite).
  final Rect? fitRect;

  /// true: [fitRect] bleibt immer im Bild, Herauszoomen ist begrenzt.
  final bool lockToFit;
  final CustomPainter Function(Camera camera)? backgroundBuilder;

  /// Zusätzliche Ebene über der Handschrift (z. B. Canvas-Karten).
  final Widget Function(BuildContext context, InkController c)? overlayBuilder;
  final List<Widget> toolbarLeading;
  final List<Widget> toolbarTrailing;
  final bool showInkTools;

  /// Abstand der angedockten Leiste zu den Rändern (Platz für Kopfzeile,
  /// Seitennavigation usw.).
  final EdgeInsets toolbarInsets;
  final VoidCallback? onSaved;
  final ValueChanged<InkController>? onControllerReady;
  final ValueChanged<Offset>? onBackgroundTap;

  @override
  State<InkSurface> createState() => InkSurfaceState();
}

class InkSurfaceState extends State<InkSurface> {
  late final InkController controller;
  late final InkSession session;
  bool _fitted = false;
  final GlobalKey _stackKey = GlobalKey();

  /// Position der Leiste (linke obere Ecke) während des Ziehens.
  Offset? _dragPos;

  ToolSettings get _settings => controller.settings;

  @override
  void initState() {
    super.initState();
    final shared = Services.maybeOf(context)?.tools;
    controller = InkController(
      settings: shared,
      darkPaper: PaperStyle.of(widget.paper).sheet.computeLuminance() < 0.3,
    );
    session = InkSession(
      controller: controller,
      store: InkStore(widget.inkId),
      onSaved: widget.onSaved,
    );
    session.start().then((_) {
      if (mounted) setState(() {});
    });
    widget.onControllerReady?.call(controller);
  }

  /// Sofort speichern (z. B. vor dem Duplizieren einer Seite).
  Future<void> flush() => session.saveNow();

  double _fitScale(Size view, Rect r) => math.max(
      0.05,
      math.min(view.width / (r.width + 48), view.height / (r.height + 120)));

  void fit(Size view) {
    final r = widget.fitRect;
    if (r == null) return;
    final scale = _fitScale(view, r);
    _applyZoomLimits(view);
    controller.camera.lookAt(r.center, scale, view);
  }

  /// Notizbuch: etwas weiter als "ganze Seite" herauszoomen, dann Schluss.
  void _applyZoomLimits(Size view) {
    final r = widget.fitRect;
    if (!widget.lockToFit || r == null) return;
    final cam = controller.camera;
    cam.limit = r;
    cam.minZoom = _fitScale(view, r) * 0.8;
    cam.maxZoom = 6;
  }

  Size _lastSize = Size.zero;

  void _onSize(Size size) {
    if (size == _lastSize || size.isEmpty) return;
    _lastSize = size;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _applyZoomLimits(size);
      final cam = controller.camera;
      cam.setViewport(size);
      // Nach Drehen des Geräts nie kleiner als erlaubt.
      if (cam.scale < cam.minZoom) {
        cam.zoomAt(Offset(size.width / 2, size.height / 2),
            cam.minZoom / cam.scale);
      }
    });
  }

  @override
  void dispose() {
    final c = controller;
    session.close().whenComplete(c.dispose);
    super.dispose();
  }

  // --- Tastatur -----------------------------------------------------------

  static final Map<LogicalKeyboardKey, ToolMode> _toolKeys = {
    LogicalKeyboardKey.keyP: ToolMode.pen,
    LogicalKeyboardKey.keyH: ToolMode.highlighter,
    LogicalKeyboardKey.keyE: ToolMode.eraser,
    LogicalKeyboardKey.keyL: ToolMode.lasso,
    LogicalKeyboardKey.keyS: ToolMode.shape,
    LogicalKeyboardKey.keyR: ToolMode.laser,
  };

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final c = controller;
    final key = event.logicalKey;
    final hw = HardwareKeyboard.instance;
    final ctrl = hw.isControlPressed || hw.isMetaPressed;

    if (ctrl) {
      if (key == LogicalKeyboardKey.keyZ) {
        if (hw.isShiftPressed) {
          c.redo();
        } else {
          c.undo();
        }
      } else if (key == LogicalKeyboardKey.keyY) {
        c.redo();
      } else if (key == LogicalKeyboardKey.keyC && c.selection.isNotEmpty) {
        c.copySelection();
      } else if (key == LogicalKeyboardKey.keyX && c.selection.isNotEmpty) {
        c.cutSelection();
      } else if (key == LogicalKeyboardKey.keyV && c.canPaste &&
          c.drawingEnabled) {
        c.paste();
      } else if (key == LogicalKeyboardKey.keyD && c.selection.isNotEmpty) {
        c.duplicateSelection();
      } else {
        return KeyEventResult.ignored;
      }
      return KeyEventResult.handled;
    }

    if (c.selection.isNotEmpty &&
        (key == LogicalKeyboardKey.delete ||
            key == LogicalKeyboardKey.backspace)) {
      c.deleteSelection();
      return KeyEventResult.handled;
    }
    if (c.selection.isNotEmpty && key == LogicalKeyboardKey.escape) {
      c.clearSelection();
      return KeyEventResult.handled;
    }
    if (!c.drawingEnabled || hw.isAltPressed || hw.isShiftPressed) {
      return KeyEventResult.ignored;
    }
    final tool = _toolKeys[key];
    if (tool == null) return KeyEventResult.ignored;
    c.setTool(tool);
    return KeyEventResult.handled;
  }

  // --- Werkzeugleiste verschieben ----------------------------------------

  Offset? _toLocal(Offset global) {
    final box = _stackKey.currentContext?.findRenderObject() as RenderBox?;
    return box?.globalToLocal(global);
  }

  void _dragStart(DragStartDetails d) {
    final p = _toLocal(d.globalPosition);
    if (p == null) return;
    setState(() => _dragPos = p - const Offset(20, 20));
  }

  void _dragUpdate(DragUpdateDetails d) {
    final p = _toLocal(d.globalPosition);
    if (p == null) return;
    setState(() => _dragPos = p - const Offset(20, 20));
  }

  void _dragEnd(Size size) {
    final pos = _dragPos;
    setState(() => _dragPos = null);
    if (pos == null || size.isEmpty) return;
    final pointer = pos + const Offset(20, 20);
    const snap = 90.0;
    final distances = <ToolbarDock, double>{
      ToolbarDock.left: pointer.dx,
      ToolbarDock.right: size.width - pointer.dx,
      ToolbarDock.top: pointer.dy,
      ToolbarDock.bottom: size.height - pointer.dy,
    };
    final nearest =
        distances.entries.reduce((a, b) => a.value <= b.value ? a : b);
    _settings.update(() {
      if (nearest.value < snap) {
        _settings.dock = nearest.key;
      } else {
        _settings.dock = ToolbarDock.floating;
        _settings.floatX = (pos.dx / size.width).clamp(0.0, 1.0).toDouble();
        _settings.floatY = (pos.dy / size.height).clamp(0.0, 1.0).toDouble();
      }
    });
  }

  /// Die Leiste liegt in einer eigenen, durchlässigen Ebene über der Fläche.
  Widget _toolbar(Size size) {
    return Positioned.fill(
      child: ListenableBuilder(
        listenable: _settings,
        builder: (context, _) => Stack(children: [_positionedBar(size)]),
      ),
    );
  }

  Widget _positionedBar(Size size) {
    return Builder(
      builder: (context) {
        final s = _settings;
        final insets = widget.toolbarInsets;
        final dragging = _dragPos != null;
        final dock = dragging ? ToolbarDock.floating : s.dock;
        final vertical = dock == ToolbarDock.left || dock == ToolbarDock.right;

        final bar = InkToolbar(
          controller: controller,
          paper: widget.paper,
          leading: widget.toolbarLeading,
          trailing: widget.toolbarTrailing,
          showInkTools: widget.showInkTools,
          axis: vertical ? Axis.vertical : Axis.horizontal,
          collapsed: s.collapsed,
          onToggleCollapsed: () => s.update(() => s.collapsed = !s.collapsed),
          onDragStart: _dragStart,
          onDragUpdate: _dragUpdate,
          onDragEnd: (_) => _dragEnd(size),
        );

        // Immer derselbe Aufbau (nur die Werte ändern sich), damit das
        // Ziehen am Griff beim Umschalten nicht abbricht.
        double? left, top, right, bottom;
        var alignment = Alignment.center;
        var safe = const EdgeInsets.all(0);
        var maxWidth = double.infinity;
        switch (dock) {
          case ToolbarDock.top:
            top = insets.top;
            left = insets.left;
            right = insets.right;
            alignment = Alignment.topCenter;
            safe = const EdgeInsets.only(top: 1);
          case ToolbarDock.bottom:
            bottom = insets.bottom;
            left = insets.left;
            right = insets.right;
            alignment = Alignment.bottomCenter;
            safe = const EdgeInsets.only(bottom: 1);
          case ToolbarDock.left:
            top = insets.top;
            bottom = insets.bottom;
            left = insets.left;
            alignment = Alignment.centerLeft;
            safe = const EdgeInsets.only(left: 1);
          case ToolbarDock.right:
            top = insets.top;
            bottom = insets.bottom;
            right = insets.right;
            alignment = Alignment.centerRight;
            safe = const EdgeInsets.only(right: 1);
          case ToolbarDock.floating:
            final maxX = math.max(8.0, size.width - 120);
            final maxY = math.max(8.0, size.height - 64);
            final pos = _dragPos ??
                Offset(s.floatX * size.width, s.floatY * size.height);
            left = pos.dx.clamp(8.0, maxX).toDouble();
            top = pos.dy.clamp(8.0, maxY).toDouble();
            alignment = Alignment.topLeft;
            maxWidth = math.max(120.0, size.width - left - 8);
        }
        return Positioned(
          left: left,
          top: top,
          right: right,
          bottom: bottom,
          child: SafeArea(
            left: safe.left > 0,
            top: safe.top > 0,
            right: safe.right > 0,
            bottom: safe.bottom > 0,
            child: Align(
              alignment: alignment,
              widthFactor: 1,
              heightFactor: 1,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxWidth),
                child: Opacity(opacity: dragging ? 0.85 : 1, child: bar),
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: true,
      onKeyEvent: _onKey,
      child: LayoutBuilder(builder: (context, constraints) {
        final size = constraints.biggest;
        _onSize(size);
        if (!_fitted && widget.fitRect != null && size.width > 0) {
          _fitted = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) fit(size);
          });
        }
        return Stack(
          key: _stackKey,
          children: [
            Positioned.fill(
              child: InkCanvasView(
                controller: controller,
                background: widget.backgroundBuilder?.call(controller.camera),
                onBackgroundTap: widget.onBackgroundTap,
              ),
            ),
            if (widget.overlayBuilder != null)
              Positioned.fill(
                  child: widget.overlayBuilder!(context, controller)),
            if (!session.loaded)
              const Center(child: CircularProgressIndicator()),
            _toolbar(size),
          ],
        );
      }),
    );
  }
}
