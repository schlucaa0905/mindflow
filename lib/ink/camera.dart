import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Die "Kamera" auf die Fläche: Verschiebung + Zoom.
///
/// Bildschirm = Welt * scale + offset
/// Welt       = (Bildschirm - offset) / scale
///
/// Optional mit Grenzen ([limit]): Dann bleibt dieser Bereich (z. B. eine
/// Notizbuchseite) immer im Bild, und man kann nicht beliebig weit
/// herauszoomen.
class Camera extends ChangeNotifier {
  double minZoom = 0.05;
  double maxZoom = 8.0;

  /// Bereich in Weltkoordinaten, der im Bild bleiben muss (null = frei).
  Rect? limit;

  /// Rand in Bildschirmpunkten, der um [limit] erlaubt ist.
  double limitMargin = 40;

  Offset _offset = Offset.zero;
  double _scale = 1.0;
  Size _viewport = Size.zero;

  Offset get offset => _offset;
  double get scale => _scale;
  Size get viewport => _viewport;

  Offset toWorld(Offset screen) => (screen - _offset) / _scale;
  Offset toScreen(Offset world) => world * _scale + _offset;

  Rect visibleWorldRect(Size viewSize) => Rect.fromPoints(
      toWorld(Offset.zero), toWorld(Offset(viewSize.width, viewSize.height)));

  /// Größe des sichtbaren Bereichs – nötig für die Grenzen.
  void setViewport(Size size) {
    if (size == _viewport) return;
    _viewport = size;
    _applyLimits();
    notifyListeners();
  }

  void panBy(Offset delta) {
    if (delta == Offset.zero) return;
    _offset += delta;
    _applyLimits();
    notifyListeners();
  }

  /// Zoomt so, dass der Weltpunkt unter [focal] (Bildschirm) an Ort bleibt.
  void zoomAt(Offset focal, double factor) {
    final next = (_scale * factor).clamp(minZoom, maxZoom).toDouble();
    final f = next / _scale;
    if (f == 1.0) return;
    _offset = focal - (focal - _offset) * f;
    _scale = next;
    _applyLimits();
    notifyListeners();
  }

  /// Zentriert einen Weltpunkt im Fenster.
  void lookAt(Offset worldCenter, double scale, Size viewSize) {
    _scale = scale.clamp(minZoom, maxZoom).toDouble();
    _offset =
        Offset(viewSize.width / 2, viewSize.height / 2) - worldCenter * _scale;
    if (_viewport == Size.zero) _viewport = viewSize;
    _applyLimits();
    notifyListeners();
  }

  void reset() {
    _offset = Offset.zero;
    _scale = 1.0;
    _applyLimits();
    notifyListeners();
  }

  /// Hält [limit] im Bild: Ist der Bereich kleiner als das Fenster, wird er
  /// mittig gehalten; ist er größer, darf man ihn nur bis zum Rand schieben.
  void _applyLimits() {
    final r = limit;
    if (r == null || _viewport.isEmpty) return;
    double axis(double off, double start, double length, double view) {
      final screenLen = length * _scale;
      if (screenLen + limitMargin * 2 <= view) {
        return (view - screenLen) / 2 - start * _scale;
      }
      final minOff = view - limitMargin - (start + length) * _scale;
      final maxOff = limitMargin - start * _scale;
      return math.min(maxOff, math.max(minOff, off));
    }

    _offset = Offset(
      axis(_offset.dx, r.left, r.width, _viewport.width),
      axis(_offset.dy, r.top, r.height, _viewport.height),
    );
  }
}
