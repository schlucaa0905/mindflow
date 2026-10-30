import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app/theme.dart';
import '../storage/ink_store.dart';
import 'camera.dart';
import 'ink_canvas_view.dart';
import 'ink_controller.dart';
import 'ink_session.dart';
import 'ink_toolbar.dart';

/// Eine fertige Schreibfläche für ein Objekt: Zeichnen, Werkzeugleiste,
/// automatisches Laden und Speichern. Notizbuch und Canvas nutzen dieselbe.
class InkSurface extends StatefulWidget {
  const InkSurface({
    super.key,
    required this.inkId,
    required this.paper,
    this.fitRect,
    this.backgroundBuilder,
    this.overlayBuilder,
    this.toolbarLeading = const [],
    this.toolbarTrailing = const [],
    this.showInkTools = true,
    this.toolbarTop = 12,
    this.onSaved,
    this.onControllerReady,
    this.onBackgroundTap,
  });

  /// ID des Objekts, dessen Handschrift gezeigt wird.
  final String inkId;
  final Paper paper;

  /// Bereich, der beim Öffnen ins Bild gesetzt wird (z. B. die Seite).
  final Rect? fitRect;
  final CustomPainter Function(Camera camera)? backgroundBuilder;

  /// Zusätzliche Ebene über der Handschrift (z. B. Canvas-Karten).
  final Widget Function(BuildContext context, InkController c)? overlayBuilder;
  final List<Widget> toolbarLeading;
  final List<Widget> toolbarTrailing;
  final bool showInkTools;
  final double toolbarTop;
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

  @override
  void initState() {
    super.initState();
    final style = PaperStyle.of(widget.paper);
    controller = InkController()
      ..penColor = style.ink.first
      ..highlighterColor = style.highlighter.first;
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

  void fit(Size view) {
    final r = widget.fitRect;
    if (r == null) return;
    final scale = math.max(
        0.05,
        math.min(view.width / (r.width + 48),
            view.height / (r.height + 120)));
    controller.camera.lookAt(r.center, scale, view);
  }

  @override
  void dispose() {
    final c = controller;
    session.close().whenComplete(c.dispose);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final size = constraints.biggest;
      if (!_fitted && widget.fitRect != null && size.width > 0) {
        _fitted = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) fit(size);
        });
      }
      return Stack(
        children: [
          Positioned.fill(
            child: InkCanvasView(
              controller: controller,
              background: widget.backgroundBuilder?.call(controller.camera),
              onBackgroundTap: widget.onBackgroundTap,
            ),
          ),
          if (widget.overlayBuilder != null)
            Positioned.fill(child: widget.overlayBuilder!(context, controller)),
          if (!session.loaded)
            const Center(child: CircularProgressIndicator()),
          Positioned(
            top: widget.toolbarTop,
            left: 12,
            right: 12,
            child: SafeArea(
              bottom: false,
              child: Center(
                child: InkToolbar(
                  controller: controller,
                  paper: widget.paper,
                  leading: widget.toolbarLeading,
                  trailing: widget.toolbarTrailing,
                  showInkTools: widget.showInkTools,
                ),
              ),
            ),
          ),
        ],
      );
    });
  }
}
