import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../data/models.dart';
import '../../ink/ink_controller.dart';

/// Übersichtskarte unten rechts: zeigt, wo auf dem Canvas Inhalte liegen
/// und welchen Ausschnitt man gerade sieht. Antippen oder Ziehen springt
/// an die Stelle – so geht nichts "verloren", egal wie weit man scrollt.
class CanvasMinimap extends StatelessWidget {
  const CanvasMinimap({
    super.key,
    required this.controller,
    required this.nodes,
  });

  final InkController controller;
  final List<CanvasNode> nodes;

  static const Size _size = Size(190, 126);

  /// Bereich der Karte in Weltkoordinaten (Inhalte + aktueller Ausschnitt).
  static Rect? contentBounds(InkController c, List<CanvasNode> nodes) {
    Rect? r = c.scene.roughBounds();
    for (final n in nodes) {
      final nr = Rect.fromLTWH(n.x, n.y, n.w, n.h);
      r = r == null ? nr : r.expandToInclude(nr);
    }
    return r;
  }

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final mf = context.mf;
    return ListenableBuilder(
      listenable: Listenable.merge([c.camera, c.scene]),
      builder: (context, _) {
        final content = contentBounds(c, nodes);
        final view = c.camera.viewport;
        if (content == null || view.isEmpty) return const SizedBox.shrink();
        final visible = c.camera.visibleWorldRect(view);
        final world = content.expandToInclude(visible).inflate(40);
        // Weltbereich → Kartenbereich (Seitenverhältnis bleibt erhalten).
        final scale = (_size.width / world.width) < (_size.height / world.height)
            ? _size.width / world.width
            : _size.height / world.height;
        final offset = Offset(
          (_size.width - world.width * scale) / 2 - world.left * scale,
          (_size.height - world.height * scale) / 2 - world.top * scale,
        );
        Offset toWorld(Offset local) => (local - offset) / scale;
        void jump(Offset local) =>
            c.camera.lookAt(toWorld(local), c.camera.scale, view);

        return Tooltip(
          message: 'Übersicht – tippen oder ziehen zum Springen',
          child: GestureDetector(
            onTapDown: (d) => jump(d.localPosition),
            onPanUpdate: (d) => jump(d.localPosition),
            child: Container(
              width: _size.width,
              height: _size.height,
              decoration: BoxDecoration(
                color: mf.surface.withValues(alpha: 0.92),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: mf.border),
                boxShadow: const [
                  BoxShadow(
                      color: Color(0x33000000),
                      blurRadius: 16,
                      offset: Offset(0, 6)),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: CustomPaint(
                  painter: _MinimapPainter(
                    chunks: [
                      for (final ch in c.scene.chunks)
                        if (!ch.strokes.every((s) => s.deleted)) ch.bounds
                    ],
                    nodes: [
                      for (final n in nodes) Rect.fromLTWH(n.x, n.y, n.w, n.h)
                    ],
                    visible: visible,
                    scale: scale,
                    offset: offset,
                    ink: mf.textMuted,
                    accent: mf.accent,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _MinimapPainter extends CustomPainter {
  _MinimapPainter({
    required this.chunks,
    required this.nodes,
    required this.visible,
    required this.scale,
    required this.offset,
    required this.ink,
    required this.accent,
  });

  final List<Rect> chunks;
  final List<Rect> nodes;
  final Rect visible;
  final double scale;
  final Offset offset;
  final Color ink;
  final Color accent;

  Rect _map(Rect r) => Rect.fromLTRB(
        r.left * scale + offset.dx,
        r.top * scale + offset.dy,
        r.right * scale + offset.dx,
        r.bottom * scale + offset.dy,
      );

  @override
  void paint(Canvas canvas, Size size) {
    final inkPaint = Paint()..color = ink.withValues(alpha: 0.35);
    for (final r in chunks) {
      canvas.drawRRect(
          RRect.fromRectAndRadius(_map(r), const Radius.circular(2)), inkPaint);
    }
    final nodePaint = Paint()..color = accent.withValues(alpha: 0.85);
    for (final r in nodes) {
      final m = _map(r);
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromCenter(
                  center: m.center,
                  width: m.width < 4 ? 4 : m.width,
                  height: m.height < 3 ? 3 : m.height),
              const Radius.circular(2)),
          nodePaint);
    }
    final v = _map(visible);
    canvas.drawRRect(
      RRect.fromRectAndRadius(v, const Radius.circular(4)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..color = accent,
    );
    canvas.drawRRect(RRect.fromRectAndRadius(v, const Radius.circular(4)),
        Paint()..color = accent.withValues(alpha: 0.08));
  }

  @override
  bool shouldRepaint(_MinimapPainter old) => true;
}
