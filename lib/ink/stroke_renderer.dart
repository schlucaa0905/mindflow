import 'dart:math' as math;
import 'dart:ui';

import 'stroke.dart';

/// Zwischenspeicher für fertig berechnete Umrisse.
/// Liegt bewusst außerhalb von [Stroke], damit Striche reine Daten
/// bleiben (wichtig für das Speichern in einem Hintergrund-Isolate).
final Expando<Path> _pathCache = Expando<Path>('strokePath');

/// Zeichnet einen fertigen Strich.
void paintStroke(Canvas canvas, Stroke s) {
  final path = _pathCache[s] ??= buildStrokePath(s.points, s.width, s.tool);
  canvas.drawPath(path, paintFor(s.tool, Color(s.color), s.width));
}

/// Zeichnet Punktdaten, die noch kein fertiger Strich sind (Live-Strich).
void paintPoints(Canvas canvas, List<double> pts, double width, Color color,
    InkTool tool) {
  if (pts.isEmpty) return;
  canvas.drawPath(
      buildStrokePath(pts, width, tool), paintFor(tool, color, width));
}

Paint paintFor(InkTool tool, Color color, double width) {
  final p = Paint()..isAntiAlias = true;
  switch (tool) {
    case InkTool.pen:
    case InkTool.brush:
      p
        ..style = PaintingStyle.fill
        ..color = color;
    case InkTool.highlighter:
      p
        ..style = PaintingStyle.stroke
        ..strokeWidth = width
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = color.withValues(alpha: 0.35);
    case InkTool.ballpoint:
      // Gleichmäßige Breite, etwa wie ein Füller mit mittlerem Druck.
      p
        ..style = PaintingStyle.stroke
        ..strokeWidth = width * 0.8
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = color;
  }
  return p;
}

Path buildStrokePath(List<double> pts, double width, InkTool tool) {
  switch (tool) {
    case InkTool.pen:
      return _penOutline(pts, width);
    case InkTool.brush:
      return _penOutline(pts, width, brush: true);
    case InkTool.highlighter:
    case InkTool.ballpoint:
      return _polyline(pts);
  }
}

Path _polyline(List<double> pts) {
  final path = Path();
  final n = pts.length ~/ 3;
  if (n == 0) return path;
  path.moveTo(pts[0], pts[1]);
  if (n == 1) {
    path.lineTo(pts[0] + 0.01, pts[1]);
    return path;
  }
  for (var i = 1; i < n; i++) {
    path.lineTo(pts[i * 3], pts[i * 3 + 1]);
  }
  return path;
}

/// Baut einen gefüllten Umriss mit druckabhängiger Breite.
///
/// Für jeden Punkt wird senkrecht zur Laufrichtung nach links und rechts
/// versetzt. Die linke Kante läuft vorwärts, die rechte rückwärts, die
/// Enden werden mit Halbkreisen geschlossen. Ergebnis: eine einzige Form,
/// die sehr schnell gezeichnet werden kann.
///
/// Pinselstift ([brush]): viel stärkerer Druckeffekt und spitz zulaufende
/// Enden, wie bei einem echten Brush-Pen.
Path _penOutline(List<double> pts, double width, {bool brush = false}) {
  final path = Path();
  final n = pts.length ~/ 3;
  if (n == 0) return path;

  double radius(int i) {
    final p = pts[i * 3 + 2].clamp(0.0, 1.0).toDouble();
    if (!brush) return math.max(0.3, width / 2 * (0.5 + 0.7 * p));
    // Spitze Enden: die ersten und letzten 15 % laufen aus.
    final edge = math.max(1, (n * 0.15).round());
    final fromEdge = math.min(i, n - 1 - i);
    final taper = fromEdge >= edge ? 1.0 : 0.25 + 0.75 * (fromEdge / edge);
    return math.max(0.2, width / 2 * (0.15 + 1.7 * math.pow(p, 1.3)) * taper);
  }

  if (n == 1) {
    return path
      ..addOval(Rect.fromCircle(
          center: Offset(pts[0], pts[1]), radius: radius(0)));
  }

  final left = List<Offset>.filled(n, Offset.zero);
  final right = List<Offset>.filled(n, Offset.zero);
  var nx = 0.0, ny = 1.0;
  for (var i = 0; i < n; i++) {
    final prev = i == 0 ? 0 : i - 1;
    final next = i == n - 1 ? n - 1 : i + 1;
    final dx = pts[next * 3] - pts[prev * 3];
    final dy = pts[next * 3 + 1] - pts[prev * 3 + 1];
    final len = math.sqrt(dx * dx + dy * dy);
    if (len > 1e-6) {
      nx = -dy / len;
      ny = dx / len;
    }
    final r = radius(i);
    final x = pts[i * 3], y = pts[i * 3 + 1];
    left[i] = Offset(x + nx * r, y + ny * r);
    right[i] = Offset(x - nx * r, y - ny * r);
  }

  path.moveTo(left[0].dx, left[0].dy);
  for (var i = 1; i < n; i++) {
    path.lineTo(left[i].dx, left[i].dy);
  }
  path.arcToPoint(right[n - 1],
      radius: Radius.circular(radius(n - 1)), clockwise: false);
  for (var i = n - 2; i >= 0; i--) {
    path.lineTo(right[i].dx, right[i].dy);
  }
  path.arcToPoint(left[0], radius: Radius.circular(radius(0)), clockwise: false);
  path.close();
  return path;
}
