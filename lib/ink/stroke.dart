import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

/// Werkzeug, mit dem ein Strich gezeichnet wurde.
/// Neue Werte nur hinten anhängen – die Position wird gespeichert.
enum InkTool { pen, highlighter, ballpoint }

/// Ein einzelner Strich – reine Daten, keine Rendering-Objekte.
///
/// Wichtig für später (Sync): Ein Strich ist nach dem Zeichnen
/// unveränderlich. Löschen setzt nur [deleted] (ein "Grabstein"),
/// damit zwei Geräte ihre Änderungen verlustfrei zusammenführen können.
class Stroke {
  Stroke({
    required this.id,
    required this.color,
    required this.width,
    required this.tool,
    required this.points,
    this.deleted = false,
  })  : assert(points.length % 3 == 0, 'points = x,y,druck-Tripel'),
        bounds = computeBounds(points, width);

  /// Stabile, weltweit eindeutige ID (UUID).
  final String id;

  /// Farbe als ARGB-Zahl.
  final int color;

  /// Grundbreite in Weltkoordinaten.
  final double width;

  final InkTool tool;

  /// Punkte als flache Liste: x0, y0, druck0, x1, y1, druck1, ...
  /// Koordinaten in Weltkoordinaten, Druck 0..1.
  final Float32List points;

  bool deleted;

  /// Umschließendes Rechteck inklusive Strichbreite.
  final Rect bounds;

  int get pointCount => points.length ~/ 3;

  static Rect computeBounds(Float32List pts, double width) {
    if (pts.isEmpty) return Rect.zero;
    var minX = double.infinity, minY = double.infinity;
    var maxX = double.negativeInfinity, maxY = double.negativeInfinity;
    for (var i = 0; i < pts.length; i += 3) {
      final x = pts[i], y = pts[i + 1];
      minX = math.min(minX, x);
      minY = math.min(minY, y);
      maxX = math.max(maxX, x);
      maxY = math.max(maxY, y);
    }
    return Rect.fromLTRB(minX, minY, maxX, maxY).inflate(width + 1);
  }

  /// Prüft, ob der Punkt [p] den Strich innerhalb von [radius] berührt.
  bool hits(Offset p, double radius) {
    if (!bounds.inflate(radius).contains(p)) return false;
    final reach = radius + width / 2;
    final reach2 = reach * reach;
    final n = pointCount;
    if (n == 1) {
      return (Offset(points[0], points[1]) - p).distanceSquared <= reach2;
    }
    for (var i = 0; i < n - 1; i++) {
      final a = Offset(points[i * 3], points[i * 3 + 1]);
      final b = Offset(points[i * 3 + 3], points[i * 3 + 4]);
      if (distanceToSegmentSquared(p, a, b) <= reach2) return true;
    }
    return false;
  }
}

double distanceToSegmentSquared(Offset p, Offset a, Offset b) {
  final ab = b - a;
  final len2 = ab.distanceSquared;
  if (len2 == 0) return (p - a).distanceSquared;
  var t = ((p.dx - a.dx) * ab.dx + (p.dy - a.dy) * ab.dy) / len2;
  t = t.clamp(0.0, 1.0).toDouble();
  final proj = Offset(a.dx + ab.dx * t, a.dy + ab.dy * t);
  return (p - proj).distanceSquared;
}
