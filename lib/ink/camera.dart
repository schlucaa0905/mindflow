import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Die "Kamera" auf die unendliche Fläche: Verschiebung + Zoom.
///
/// Bildschirm = Welt * scale + offset
/// Welt       = (Bildschirm - offset) / scale
class Camera extends ChangeNotifier {
  static const double minScale = 0.05;
  static const double maxScale = 8.0;

  Offset _offset = Offset.zero;
  double _scale = 1.0;

  Offset get offset => _offset;
  double get scale => _scale;

  Offset toWorld(Offset screen) => (screen - _offset) / _scale;
  Offset toScreen(Offset world) => world * _scale + _offset;

  Rect visibleWorldRect(Size viewSize) => Rect.fromPoints(
      toWorld(Offset.zero), toWorld(Offset(viewSize.width, viewSize.height)));

  void panBy(Offset delta) {
    if (delta == Offset.zero) return;
    _offset += delta;
    notifyListeners();
  }

  /// Zoomt so, dass der Weltpunkt unter [focal] (Bildschirm) an Ort bleibt.
  void zoomAt(Offset focal, double factor) {
    final next = (_scale * factor).clamp(minScale, maxScale).toDouble();
    final f = next / _scale;
    if (f == 1.0) return;
    _offset = focal - (focal - _offset) * f;
    _scale = next;
    notifyListeners();
  }

  /// Zentriert einen Weltpunkt im Fenster.
  void lookAt(Offset worldCenter, double scale, Size viewSize) {
    _scale = scale.clamp(minScale, maxScale).toDouble();
    _offset =
        Offset(viewSize.width / 2, viewSize.height / 2) - worldCenter * _scale;
    notifyListeners();
  }

  void reset() {
    _offset = Offset.zero;
    _scale = 1.0;
    notifyListeners();
  }
}
