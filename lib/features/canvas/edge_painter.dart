import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../data/models.dart';
import '../../ink/camera.dart';

/// Geometrie einer Verbindung: weiche Kurve von Kartenrand zu Kartenrand.
class EdgeGeometry {
  const EdgeGeometry(this.p0, this.c1, this.c2, this.p1);

  final Offset p0;
  final Offset c1;
  final Offset c2;
  final Offset p1;

  Offset at(double t) {
    final u = 1 - t;
    return p0 * (u * u * u) +
        c1 * (3 * u * u * t) +
        c2 * (3 * u * t * t) +
        p1 * (t * t * t);
  }

  Path get path => Path()
    ..moveTo(p0.dx, p0.dy)
    ..cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, p1.dx, p1.dy);

  Offset get middle => at(0.5);

  /// Kleinster Abstand von [p] zur Kurve.
  double distanceTo(Offset p) {
    var best = double.infinity;
    var prev = p0;
    for (var i = 1; i <= 32; i++) {
      final cur = at(i / 32);
      best = math.min(best, _segDist(p, prev, cur));
      prev = cur;
    }
    return best;
  }

  static double _segDist(Offset p, Offset a, Offset b) {
    final ab = b - a;
    final len2 = ab.dx * ab.dx + ab.dy * ab.dy;
    if (len2 == 0) return (p - a).distance;
    final t = (((p - a).dx * ab.dx + (p - a).dy * ab.dy) / len2)
        .clamp(0.0, 1.0)
        .toDouble();
    return (p - (a + ab * t)).distance;
  }

  /// Kurve zwischen zwei Rechtecken (beliebiges Koordinatensystem).
  /// Angedockt wird an der Seitenmitte, die zum anderen Rechteck zeigt.
  static EdgeGeometry between(Rect a, Rect b) {
    final d = b.center - a.center;
    final horizontal =
        d.dx.abs() / (a.width + b.width + 1) >= d.dy.abs() / (a.height + b.height + 1);
    Offset p0, p1, n0, n1;
    if (horizontal) {
      final right = d.dx >= 0;
      p0 = right ? a.centerRight : a.centerLeft;
      p1 = right ? b.centerLeft : b.centerRight;
      n0 = Offset(right ? 1 : -1, 0);
      n1 = Offset(right ? -1 : 1, 0);
    } else {
      final down = d.dy >= 0;
      p0 = down ? a.bottomCenter : a.topCenter;
      p1 = down ? b.topCenter : b.bottomCenter;
      n0 = Offset(0, down ? 1 : -1);
      n1 = Offset(0, down ? -1 : 1);
    }
    final k = math.max(24.0, (p1 - p0).distance * 0.42);
    return EdgeGeometry(p0, p0 + n0 * k, p1 + n1 * k, p1);
  }

  /// Kurve von einer Karte zu einem freien Punkt (beim Ziehen).
  static EdgeGeometry toPoint(Rect a, Offset p) =>
      between(a, Rect.fromCenter(center: p, width: 2, height: 2));
}

Rect screenRectOf(CanvasNode n, Camera cam) {
  final p = cam.toScreen(Offset(n.x, n.y));
  return Rect.fromLTWH(p.dx, p.dy, n.w * cam.scale, n.h * cam.scale);
}

/// Findet die Verbindung unter einem Bildschirmpunkt (oder null).
CanvasEdge? hitEdge(Offset screen, Camera cam, Map<String, CanvasNode> nodes,
    List<CanvasEdge> edges,
    {double tolerance = 12}) {
  CanvasEdge? best;
  var bestDist = tolerance;
  for (final e in edges) {
    final a = nodes[e.fromId], b = nodes[e.toId];
    if (a == null || b == null) continue;
    final g = EdgeGeometry.between(screenRectOf(a, cam), screenRectOf(b, cam));
    final d = g.distanceTo(screen);
    if (d < bestDist) {
      bestDist = d;
      best = e;
    }
  }
  return best;
}

/// Zeichnet alle Verbindungen: Kurven, Pfeile, gestrichelt, Beschriftung.
class EdgePainter extends CustomPainter {
  EdgePainter({
    required this.camera,
    required this.nodes,
    required this.edges,
    required this.accent,
    required this.labelFill,
    required this.labelText,
    this.selectedEdge,
    this.pendingFrom,
    this.pendingTo,
  });

  final Camera camera;
  final Map<String, CanvasNode> nodes;
  final List<CanvasEdge> edges;
  final Color accent;
  final Color labelFill;
  final Color labelText;
  final String? selectedEdge;
  final CanvasNode? pendingFrom;
  final Offset? pendingTo;

  @override
  void paint(Canvas canvas, Size size) {
    final s = camera.scale.clamp(0.35, 2.0).toDouble();
    for (final e in edges) {
      final a = nodes[e.fromId], b = nodes[e.toId];
      if (a == null || b == null) continue;
      final g = EdgeGeometry.between(
          screenRectOf(a, camera), screenRectOf(b, camera));
      final selected = e.id == selectedEdge;
      final color = e.color == null ? accent : Color(e.color!);
      if (selected) {
        canvas.drawPath(
            g.path,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 10 * s
              ..strokeCap = StrokeCap.round
              ..color = color.withValues(alpha: 0.22));
      }
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = (selected ? 2.8 : 2.2) * s
        ..strokeCap = StrokeCap.round
        ..color = color.withValues(alpha: 0.9);
      if (e.dashed) {
        _dashed(canvas, g.path, paint, 9 * s, 6 * s);
      } else {
        canvas.drawPath(g.path, paint);
      }
      final fill = Paint()..color = color;
      if (e.arrow == EdgeArrow.end || e.arrow == EdgeArrow.both) {
        _arrow(canvas, g.p1, g.p1 - g.c2, fill, 11 * s);
      } else {
        canvas.drawCircle(g.p1, 3.5 * s, fill);
      }
      if (e.arrow == EdgeArrow.both) {
        _arrow(canvas, g.p0, g.p0 - g.c1, fill, 11 * s);
      } else {
        canvas.drawCircle(g.p0, 3.5 * s, fill);
      }
      final label = e.label?.trim() ?? '';
      if (label.isNotEmpty) _label(canvas, g.middle, label, color, s);
    }

    final from = pendingFrom, to = pendingTo;
    if (from != null && to != null) {
      final target = camera.toScreen(to);
      final g = EdgeGeometry.toPoint(screenRectOf(from, camera), target);
      _dashed(
          canvas,
          g.path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.4
            ..strokeCap = StrokeCap.round
            ..color = accent.withValues(alpha: 0.8),
          8,
          6);
      canvas.drawCircle(target, 7, Paint()..color = accent.withValues(alpha: 0.25));
      canvas.drawCircle(target, 4, Paint()..color = accent);
    }
  }

  void _arrow(Canvas canvas, Offset tip, Offset dir, Paint paint, double size) {
    if (dir.distance == 0) return;
    final d = dir / dir.distance;
    final n = Offset(-d.dy, d.dx);
    final base = tip - d * size;
    final path = Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(base.dx + n.dx * size * 0.55, base.dy + n.dy * size * 0.55)
      ..lineTo(base.dx - n.dx * size * 0.55, base.dy - n.dy * size * 0.55)
      ..close();
    canvas.drawPath(path, paint);
  }

  void _dashed(Canvas canvas, Path path, Paint paint, double dash, double gap) {
    for (final m in path.computeMetrics()) {
      var d = 0.0;
      while (d < m.length) {
        final end = math.min(m.length, d + dash);
        canvas.drawPath(m.extractPath(d, end), paint);
        d = end + gap;
      }
    }
  }

  void _label(Canvas canvas, Offset at, String text, Color color, double s) {
    final tp = TextPainter(
      text: TextSpan(
          text: text,
          style: TextStyle(
              fontSize: 12.5 * s,
              fontWeight: FontWeight.w600,
              color: labelText)),
      textDirection: ui.TextDirection.ltr,
      maxLines: 2,
      ellipsis: '…',
    )..layout(maxWidth: 220 * s);
    final r = Rect.fromCenter(
        center: at, width: tp.width + 18 * s, height: tp.height + 10 * s);
    final rr = RRect.fromRectAndRadius(r, Radius.circular(r.height / 2));
    canvas.drawRRect(rr, Paint()..color = labelFill);
    canvas.drawRRect(
        rr,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..color = color.withValues(alpha: 0.6));
    tp.paint(canvas, Offset(r.left + 9 * s, r.top + 5 * s));
    tp.dispose();
  }

  @override
  bool shouldRepaint(EdgePainter old) => true;
}
