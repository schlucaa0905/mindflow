import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../data/models.dart';
import '../../ink/ink_controller.dart';

/// Übersichtskarte unten rechts: zeigt, wo auf dem Canvas Inhalte liegen
/// und welchen Ausschnitt man gerade sieht. Antippen oder Ziehen springt
/// an die Stelle – so geht nichts "verloren", egal wie weit man scrollt.
class CanvasMinimap extends StatefulWidget {
  const CanvasMinimap({
    super.key,
    required this.controller,
    required this.nodes,
    required this.onJump,
  });

  final InkController controller;
  final List<CanvasNode> nodes;

  /// Springt (weich) zu dieser Weltkoordinate.
  final ValueChanged<Offset> onJump;

  /// Bereich der Karte in Weltkoordinaten (alle Inhalte).
  static Rect? contentBounds(InkController c, List<CanvasNode> nodes) {
    Rect? r = c.scene.roughBounds();
    for (final n in nodes) {
      final nr = Rect.fromLTWH(n.x, n.y, n.w, n.h);
      r = r == null ? nr : r.expandToInclude(nr);
    }
    return r;
  }

  @override
  State<CanvasMinimap> createState() => _CanvasMinimapState();
}

class _CanvasMinimapState extends State<CanvasMinimap> {
  bool _open = true;

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final mf = context.mf;
    if (!_open) {
      return FloatingActionButton.small(
        heroTag: null,
        tooltip: 'Übersichtskarte zeigen',
        onPressed: () => setState(() => _open = true),
        child: const Icon(Icons.map_outlined),
      );
    }
    const size = Size(260, 170);
    return ListenableBuilder(
      listenable: Listenable.merge([c.camera, c.scene]),
      builder: (context, _) {
        final content = CanvasMinimap.contentBounds(c, widget.nodes);
        final view = c.camera.viewport;
        if (content == null || view.isEmpty) return const SizedBox.shrink();
        final visible = c.camera.visibleWorldRect(view);
        // Feste Karte über alle Inhalte – sie springt beim Verschieben
        // nicht mehr hin und her.
        final world =
            content.inflate(content.longestSide * 0.08 + 40);
        final scale = (size.width / world.width) < (size.height / world.height)
            ? size.width / world.width
            : size.height / world.height;
        final offset = Offset(
          (size.width - world.width * scale) / 2 - world.left * scale,
          (size.height - world.height * scale) / 2 - world.top * scale,
        );
        Offset toWorld(Offset local) => (local - offset) / scale;

        return Container(
          width: size.width,
          height: size.height + 30,
          decoration: BoxDecoration(
            color: mf.surface.withValues(alpha: 0.95),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: mf.border),
            boxShadow: const [
              BoxShadow(
                  color: Color(0x33000000), blurRadius: 16, offset: Offset(0, 6)),
            ],
          ),
          child: Column(children: [
            SizedBox(
              height: 30,
              child: Row(children: [
                const SizedBox(width: 12),
                Expanded(
                  child: Text('Übersicht · ${(c.camera.scale * 100).round()} %',
                      style: TextStyle(fontSize: 12, color: mf.textMuted)),
                ),
                IconButton(
                  iconSize: 16,
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Übersicht einklappen',
                  onPressed: () => setState(() => _open = false),
                  icon: Icon(Icons.close_fullscreen_rounded, color: mf.textMuted),
                ),
              ]),
            ),
            Expanded(
              child: ClipRRect(
                borderRadius:
                    const BorderRadius.vertical(bottom: Radius.circular(16)),
                child: GestureDetector(
                  onTapUp: (d) => widget.onJump(toWorld(d.localPosition)),
                  onPanUpdate: (d) => c.camera.lookAt(
                      toWorld(d.localPosition), c.camera.scale, view),
                  child: CustomPaint(
                    size: size,
                    painter: _MinimapPainter(
                      chunks: [
                        for (final ch in c.scene.chunks)
                          if (!ch.strokes.every((s) => s.deleted)) ch.bounds
                      ],
                      nodes: [
                        for (final n in widget.nodes)
                          (Rect.fromLTWH(n.x, n.y, n.w, n.h),
                              n.color == null ? mf.accent : Color(n.color!))
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
          ]),
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
  final List<(Rect, Color)> nodes;
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
    for (final n in nodes) {
      final m = _map(n.$1);
      final nodePaint = Paint()..color = n.$2.withValues(alpha: 0.9);
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromCenter(
                  center: m.center,
                  width: m.width < 4 ? 4 : m.width,
                  height: m.height < 3 ? 3 : m.height),
              const Radius.circular(2)),
          nodePaint);
    }
    // Ausschnitt; liegt er außerhalb, zeigt ein Punkt am Rand die Richtung.
    final v = _map(visible);
    final box = Offset.zero & size;
    if (!v.overlaps(box)) {
      final p = Offset(v.center.dx.clamp(6.0, size.width - 6).toDouble(),
          v.center.dy.clamp(6.0, size.height - 6).toDouble());
      canvas.drawCircle(p, 6, Paint()..color = accent);
      return;
    }
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
