import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../app/services.dart';
import '../app/theme.dart';
import '../data/text_repository.dart';
import '../features/common/links.dart';
import '../features/study/card_editor.dart';
import '../storage/image_store.dart';
import '../storage/ink_store.dart';
import 'stroke_renderer.dart';
import '../ui/editor_bar.dart';
import 'camera.dart';
import 'ink_canvas_view.dart';
import 'ink_controller.dart';
import 'ink_session.dart';
import 'surface_overlays.dart';
import 'text_layer.dart';
import 'tool_row.dart';

/// Eine fertige Schreibfläche für ein Objekt: Zeichnen, Werkzeugleiste,
/// automatisches Laden und Speichern. Notizbuch und Canvas nutzen dieselbe.
///
/// Oben sitzt die Kopfleiste (Navigation + Werkzeuge) wie bei Goodnotes.
class InkSurface extends StatefulWidget {
  const InkSurface({
    super.key,
    required this.inkId,
    required this.paper,
    this.fitRect,
    this.lockToFit = false,
    this.backgroundBuilder,
    this.overlayBuilder,
    this.showInkTools = true,
    this.navBar,
    this.onSwipe,
    this.enterFrom = 0,
    this.presenting = false,
    this.onExitPresentation,
    this.presentationLabel,
    this.drawBounds,
    this.onSaved,
    this.onControllerReady,
    this.onBackgroundTap,
    this.textGrid,
    this.leftPanel,
    this.linkNotebookId,
    this.onOpenLink,
  });

  /// Notizbuch, dessen Seiten als Linkziel angeboten werden.
  final String? linkNotebookId;

  /// Link öffnen (Standard: Seite bzw. Inhalt öffnen).
  final ValueChanged<String>? onOpenLink;

  /// Seitenleiste links unter der Kopfleiste (z. B. Seitenvorschauen).
  final Widget? leftPanel;

  /// Linien/Kästchen des Papiers, an denen Textfelder ausgerichtet werden.
  final TextLineGrid? textGrid;

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
  final bool showInkTools;

  /// Mit einem Finger seitlich wischen: +1 = nächste, -1 = vorige Seite.
  final ValueChanged<int>? onSwipe;

  /// Präsentationsmodus: keine Leisten, nur das Blatt und eine kleine,
  /// fast unsichtbare Steuerkapsel. Ideal zum Spiegeln auf den Beamer.
  final bool presenting;
  final VoidCallback? onExitPresentation;
  final String? presentationLabel;

  /// Beim Öffnen hereingleiten: 1 = von rechts (nächste Seite),
  /// -1 = von links (vorige Seite), 0 = ohne Animation.
  final int enterFrom;

  /// Navigationszeile oben (zurück, Titel, Seiten, Menü).
  final Widget Function(BuildContext context, InkController c)? navBar;

  /// Nur hier darf geschrieben werden (z. B. das Blatt). null = überall.
  final Rect? drawBounds;
  final VoidCallback? onSaved;
  final ValueChanged<InkController>? onControllerReady;
  final ValueChanged<Offset>? onBackgroundTap;

  @override
  State<InkSurface> createState() => InkSurfaceState();
}

class InkSurfaceState extends State<InkSurface>
    with SingleTickerProviderStateMixin {
  late final InkController controller;
  late final AnimationController _enter = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
    value: widget.enterFrom == 0 ? 1 : 0,
  );
  late final InkSession session;
  final GlobalKey<TextLayerState> _textKey = GlobalKey();
  bool _fitted = false;

  @override
  void initState() {
    super.initState();
    final shared = Services.maybeOf(context)?.tools;
    controller = InkController(
      settings: shared,
      darkPaper: PaperStyle.of(widget.paper).sheet.computeLuminance() < 0.3,
    );
    controller.drawBounds = widget.drawBounds;
    session = InkSession(
      controller: controller,
      store: InkStore(widget.inkId),
      onSaved: widget.onSaved,
    );
    session.start().then((_) {
      if (mounted) setState(() {});
    });
    widget.onControllerReady?.call(controller);
    if (widget.enterFrom != 0) _enter.forward();
    if (widget.presenting) _applySystemUi(true);
  }

  /// Bild einfügen (Fotos oder Dateien).
  Future<void> insertImage({bool fromFiles = false}) async =>
      _textKey.currentState?.insertImage(fromFiles: fromFiles);

  /// Lasso-Auswahl als Bild auf die Vorderseite einer Karteikarte.
  Future<void> selectionToCard() async {
    final c = controller;
    final b = c.selectionBounds;
    final items = c.items;
    if (b == null) return;
    final r = b.inflate(12);
    const scale = 2.0;
    final rec = ui.PictureRecorder();
    final canvas = Canvas(rec)
      ..scale(scale)
      ..translate(-r.left, -r.top)
      ..drawRect(r, Paint()..color = PaperStyle.of(widget.paper).sheet);
    final sel = [
      if (items != null)
        for (final t in items.all)
          if (c.selectedItems.contains(t.id)) t
    ];
    await ImageStore.preload([for (final t in sel) if (t.file != null) t.file!]);
    paintPageImages(canvas, sel);
    for (final s in c.selection) {
      paintStroke(canvas, s);
    }
    paintTextItems(canvas, sel);
    final img = await rec
        .endRecording()
        .toImage((r.width * scale).round(), (r.height * scale).round());
    final png = await img.toByteData(format: ui.ImageByteFormat.png);
    img.dispose();
    if (png == null || !mounted) return;
    final name = await ImageStore.save(png.buffer.asUint8List(), 'png');
    if (!mounted) return;
    await editFlashcard(context, image: name);
  }

  /// Lasso-Auswahl zum Link machen (Fläche um die Auswahl).
  Future<void> linkSelection() async {
    final c = controller;
    final b = c.selectionBounds;
    final repo = Services.maybeOf(context)?.texts;
    if (b == null || repo == null) return;
    final target =
        await pickLinkTarget(context, notebookId: widget.linkNotebookId);
    if (target == null || !mounted) return;
    c.insertItems([
      TextItem.link(
          id: repo.newId(),
          ownerId: widget.inkId,
          rect: b.inflate(4),
          target: target)
    ]);
  }

  void _openLink(String target) {
    final open = widget.onOpenLink;
    if (open != null) {
      open(target);
    } else {
      openLinkTarget(context, target);
    }
  }

  final GlobalKey _contentKey = GlobalKey();

  /// Bild der Fläche ohne Leisten (Seite, Handschrift, Text, Karten) –
  /// z. B. für den Export des Canvas.
  Future<ui.Image?> captureContent({double pixelRatio = 2}) async {
    final ro = _contentKey.currentContext?.findRenderObject();
    if (ro is! RenderRepaintBoundary) return null;
    return ro.toImage(pixelRatio: pixelRatio);
  }

  /// Sofort speichern (z. B. vor dem Duplizieren einer Seite).
  Future<void> flush() {
    _textKey.currentState?.finishEditing();
    return session.saveNow();
  }

  @override
  void didUpdateWidget(InkSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    controller.drawBounds = widget.drawBounds;
    if (oldWidget.presenting != widget.presenting) {
      _applySystemUi(widget.presenting);
      // Nach dem Umschalten (Leiste weg/da) das Blatt neu einpassen.
      _lastSize = Size.zero;
      _fitted = false;
    }
  }

  /// Vollbild (Statusleiste weg) während der Präsentation.
  void _applySystemUi(bool presenting) {
    SystemChrome.setEnabledSystemUIMode(
        presenting ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge);
  }

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

  /// Ganze Seite ins Bild setzen.
  void fitPage() {
    final v = controller.camera.viewport;
    if (!v.isEmpty) fit(v);
  }

  /// Seitenbreite füllen, oben am Blatt beginnen.
  void fitWidth() {
    final r = widget.fitRect;
    final v = controller.camera.viewport;
    if (r == null || v.isEmpty) return;
    final scale = (v.width - 32) / r.width;
    final cam = controller.camera;
    final s = scale.clamp(cam.minZoom, cam.maxZoom).toDouble();
    final top = r.top - 16 / s;
    controller.camera.lookAt(
        Offset(r.center.dx, top + v.height / 2 / s), s, v);
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
    if (widget.presenting) _applySystemUi(false);
    _enter.dispose();
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
    LogicalKeyboardKey.keyT: ToolMode.text,
  };

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    // Wird gerade in ein Textfeld getippt, gehören alle Tasten dem Text.
    final focused = FocusManager.instance.primaryFocus;
    final typing = focused != null &&
        focused != node &&
        focused.context?.findAncestorStateOfType<EditableTextState>() != null;
    if (typing) {
      if (event.logicalKey == LogicalKeyboardKey.escape) {
        _textKey.currentState?.finishEditing();
        node.requestFocus();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    final c = controller;
    // Zeichnen aus (z. B. Canvas im Auswahlmodus): Tasten gehören der
    // Seite darüber (Karten rückgängig machen, kopieren …).
    if (!c.drawingEnabled) return KeyEventResult.ignored;
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
      } else if (key == LogicalKeyboardKey.keyC && c.hasSelection) {
        c.copySelection();
      } else if (key == LogicalKeyboardKey.keyX && c.hasSelection) {
        c.cutSelection();
      } else if (key == LogicalKeyboardKey.keyV && c.canPaste &&
          c.drawingEnabled) {
        c.paste();
      } else if (key == LogicalKeyboardKey.keyD && c.hasSelection) {
        c.duplicateSelection();
      } else {
        return KeyEventResult.ignored;
      }
      return KeyEventResult.handled;
    }

    if (c.editShape != null &&
        (key == LogicalKeyboardKey.delete ||
            key == LogicalKeyboardKey.backspace)) {
      c.deleteEditShape();
      return KeyEventResult.handled;
    }
    if (c.hasSelection &&
        (key == LogicalKeyboardKey.delete ||
            key == LogicalKeyboardKey.backspace)) {
      c.deleteSelection();
      return KeyEventResult.handled;
    }
    if (c.hasSelection && key == LogicalKeyboardKey.escape) {
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

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: true,
      onKeyEvent: _onKey,
      child: Column(
        children: [
          // Kopfleiste im Goodnotes-Stil: Navigation + Werkzeuge, fest oben.
          // Im Präsentationsmodus ausgeblendet.
          Builder(builder: (context) {
            if (widget.presenting) return const SizedBox.shrink();
            final nav = widget.navBar?.call(context, controller);
            if (nav == null) return const SizedBox.shrink();
            return EditorTopBar(nav: nav);
          }),
          // ClipRect: Blatt und Striche dürfen nie über die Leiste malen.
          Expanded(
            child: Row(children: [
              if (widget.leftPanel != null && !widget.presenting)
                widget.leftPanel!,
              Expanded(
            child: Stack(
              children: [
                Positioned.fill(
            child: ClipRect(
              child: AnimatedBuilder(
                animation: _enter,
                builder: (context, child) {
                  final t = Curves.easeOutCubic.transform(_enter.value);
                  return FractionalTranslation(
                    translation:
                        Offset((1 - t) * 0.35 * widget.enterFrom, 0),
                    child: Opacity(opacity: 0.3 + 0.7 * t, child: child),
                  );
                },
                child: _surface(),
              ),
            ),
                ),
                // Schwebende Unterleiste wie bei Goodnotes.
                if (widget.showInkTools && !widget.presenting)
                  Positioned(
                    top: 10,
                    left: 0,
                    right: 0,
                    child: Center(child: ToolRow(controller: controller)),
                  ),
              ],
            ),
              ),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _surface() {
    return LayoutBuilder(builder: (context, constraints) {
      final size = constraints.biggest;
      _onSize(size);
      if (!_fitted && widget.fitRect != null && size.width > 0) {
        _fitted = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) fit(size);
        });
      }
      final services = Services.maybeOf(context);
      return Stack(
        children: [
          Positioned.fill(
            child: RepaintBoundary(
              key: _contentKey,
              child: Stack(children: [
          Positioned.fill(
            child: InkCanvasView(
              controller: controller,
              background: widget.backgroundBuilder?.call(controller.camera),
              onBackgroundTap: widget.onBackgroundTap,
              onSwipe: widget.onSwipe == null ? null : _handleSwipe,
              onTextTap: (world) => _textKey.currentState?.createAt(world),
              onSelectionToCard: selectionToCard,
              onLinkTap: _openLink,
              onSelectionToLink: services == null ? null : linkSelection,
            ),
          ),
          if (services != null)
            Positioned.fill(
              child: TextLayer(
                key: _textKey,
                ownerId: widget.inkId,
                controller: controller,
                repo: services.texts,
                lineGrid: widget.textGrid,
              ),
            ),
          if (widget.overlayBuilder != null)
            Positioned.fill(child: widget.overlayBuilder!(context, controller)),
              ]),
            ),
          ),
          if (!session.loaded) const Center(child: CircularProgressIndicator()),
          // Zoom-Anzeige oben in der Mitte.
          Positioned(
            top: widget.showInkTools ? 76 : 12,
            left: 0,
            right: 0,
            child: Center(child: ZoomBadge(camera: controller.camera)),
          ),
          if (widget.presenting)
            Positioned(
              right: 16,
              bottom: 16,
              child: SafeArea(
                child: PresenterControls(
                  controller: controller,
                  label: widget.presentationLabel,
                  onExit: widget.onExitPresentation ?? () {},
                ),
              ),
            ),
        ],
      );
    });
  }

  /// Wischen blättert nur, wenn die Seite nicht stark vergrößert ist –
  /// sonst ist es ganz normales Verschieben.
  void _handleSwipe(int direction) {
    final cam = controller.camera;
    if (cam.scale > cam.minZoom * 1.6) return;
    widget.onSwipe?.call(direction);
  }
}
