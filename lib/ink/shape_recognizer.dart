import 'dart:math' as math;
import 'dart:ui';

/// "Zeichnen und halten": erkennt aus einem freihändigen Strich eine
/// saubere Form.
///
/// Vorgehen:
/// 1. Offener Strich (Anfang weit vom Ende) → gerade Linie.
/// 2. Geschlossener Strich, der gut auf eine Ellipse passt → Ellipse.
/// 3. Sonst Ecken suchen (Douglas-Peucker-Vereinfachung):
///    3 Ecken → Dreieck, 4 Ecken → Viereck (fast achsparallel → Rechteck),
///    5–8 Ecken → Vieleck.
/// Passt nichts davon, bleibt der Strich, wie er ist (null).
List<double>? recognizeShape(List<double> pts, {double minSize = 12}) {
  final n = pts.length ~/ 3;
  if (n < 4) return null;
  final points = [for (var i = 0; i < n; i++) Offset(pts[i * 3], pts[i * 3 + 1])];

  var bounds = Rect.fromPoints(points.first, points.first);
  var length = 0.0;
  for (var i = 1; i < n; i++) {
    bounds = bounds.expandToInclude(Rect.fromPoints(points[i], points[i]));
    length += (points[i] - points[i - 1]).distance;
  }
  final diag = math.sqrt(
      bounds.width * bounds.width + bounds.height * bounds.height);
  if (diag < minSize) return null;

  final gap = (points.first - points.last).distance;
  final closed = gap < math.max(diag * 0.18, minSize * 0.8);

  if (!closed) {
    // Nur wenn der Strich wirklich ungefähr gerade war.
    final straight = (points.first - points.last).distance;
    if (straight < length * 0.8) return null;
    return polyPoints([points.first, points.last]);
  }

  // Ellipse?
  final c = bounds.center;
  final rx = bounds.width / 2, ry = bounds.height / 2;
  if (rx > 1 && ry > 1) {
    var err = 0.0;
    for (final p in points) {
      final dx = (p.dx - c.dx) / rx, dy = (p.dy - c.dy) / ry;
      err += (math.sqrt(dx * dx + dy * dy) - 1).abs();
    }
    err /= points.length;
    if (err < 0.11) {
      // Fast gleiche Achsen → echter Kreis.
      if ((rx - ry).abs() / math.max(rx, ry) < 0.12) {
        final r = (rx + ry) / 2;
        return ellipsePoints(Rect.fromCircle(center: c, radius: r));
      }
      return ellipsePoints(bounds);
    }
  }

  // Ecken suchen.
  final closedPath = [...points, points.first];
  var corners = simplify(closedPath, diag * 0.07);
  if (corners.length > 2 && (corners.first - corners.last).distance < 1e-6) {
    corners = corners.sublist(0, corners.length - 1);
  }
  corners = _dropNearDuplicates(corners, diag * 0.08);
  if (corners.length < 3 || corners.length > 8) return null;

  if (corners.length == 4 && _isAxisAligned(corners)) {
    return polyPoints([
      bounds.topLeft,
      bounds.topRight,
      bounds.bottomRight,
      bounds.bottomLeft,
      bounds.topLeft,
    ]);
  }
  return polyPoints([...corners, corners.first]);
}

/// Punkte (x, y, Druck) aus einer Liste von Ecken. Gerade Strecken werden
/// unterteilt, damit Radierer und Lasso überall greifen.
List<double> polyPoints(List<Offset> corners, {double pressure = 0.6}) {
  final out = <double>[];
  for (var i = 0; i < corners.length; i++) {
    final p = corners[i];
    if (i > 0) {
      final prev = corners[i - 1];
      final d = (p - prev).distance;
      final steps = (d / 6).floor();
      for (var k = 1; k < steps; k++) {
        final t = k / steps;
        final q = Offset.lerp(prev, p, t)!;
        out.addAll([q.dx, q.dy, pressure]);
      }
    }
    out.addAll([p.dx, p.dy, pressure]);
  }
  return out;
}

List<double> ellipsePoints(Rect r, {double pressure = 0.6}) {
  const steps = 72;
  final out = <double>[];
  for (var i = 0; i <= steps; i++) {
    final a = i / steps * math.pi * 2;
    out.addAll([
      r.center.dx + r.width / 2 * math.cos(a),
      r.center.dy + r.height / 2 * math.sin(a),
      pressure,
    ]);
  }
  return out;
}

/// Douglas-Peucker: behält nur Punkte, die mehr als [epsilon] von der
/// Verbindungslinie abweichen – übrig bleiben die Ecken.
List<Offset> simplify(List<Offset> pts, double epsilon) {
  if (pts.length < 3) return List.of(pts);
  var maxDist = 0.0;
  var index = 0;
  final a = pts.first, b = pts.last;
  for (var i = 1; i < pts.length - 1; i++) {
    final d = _distToLine(pts[i], a, b);
    if (d > maxDist) {
      maxDist = d;
      index = i;
    }
  }
  if (maxDist <= epsilon) return [a, b];
  final left = simplify(pts.sublist(0, index + 1), epsilon);
  final right = simplify(pts.sublist(index), epsilon);
  return [...left.sublist(0, left.length - 1), ...right];
}

double _distToLine(Offset p, Offset a, Offset b) {
  final ab = b - a;
  final len = ab.distance;
  if (len < 1e-9) {
    // Anfang = Ende (geschlossene Form): Abstand zum Punkt.
    return (p - a).distance;
  }
  return ((ab.dx * (a.dy - p.dy)) - (ab.dy * (a.dx - p.dx))).abs() / len;
}

List<Offset> _dropNearDuplicates(List<Offset> pts, double minDist) {
  final out = <Offset>[];
  for (final p in pts) {
    if (out.isEmpty || (out.last - p).distance >= minDist) out.add(p);
  }
  if (out.length > 2 && (out.first - out.last).distance < minDist) {
    out.removeLast();
  }
  return out;
}

bool _isAxisAligned(List<Offset> quad) {
  for (var i = 0; i < quad.length; i++) {
    final a = quad[i], b = quad[(i + 1) % quad.length];
    final angle = math.atan2((b.dy - a.dy).abs(), (b.dx - a.dx).abs());
    // Jede Kante fast waagrecht (< 12°) oder fast senkrecht (> 78°).
    if (angle > 0.21 && angle < math.pi / 2 - 0.21) return false;
  }
  return true;
}

bool pointInPolygon(Offset p, List<Offset> poly) {
  var inside = false;
  for (var i = 0, j = poly.length - 1; i < poly.length; j = i++) {
    final a = poly[i], b = poly[j];
    if ((a.dy > p.dy) != (b.dy > p.dy) &&
        p.dx < (b.dx - a.dx) * (p.dy - a.dy) / (b.dy - a.dy) + a.dx) {
      inside = !inside;
    }
  }
  return inside;
}
