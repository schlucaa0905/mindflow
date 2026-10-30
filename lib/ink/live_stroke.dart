import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'stroke.dart';

/// Der Strich, der gerade gezeichnet wird.
///
/// Er wird auf einer eigenen Ebene gezeichnet, damit beim Schreiben nur
/// dieser eine Strich neu gemalt wird – nicht die ganze Seite.
class LiveStroke extends ChangeNotifier {
  /// Glättung: 1.0 = keine, kleiner = ruhiger, aber mehr Verzögerung.
  static const double smoothing = 0.6;

  final List<double> points = [];
  bool active = false;
  double width = 2.5;
  Color color = const Color(0xFFEDEDF2);
  InkTool tool = InkTool.pen;

  double _sx = 0, _sy = 0, _sp = 0.5;
  double _rawX = 0, _rawY = 0, _rawP = 0.5;

  void begin(Offset world, double pressure,
      {required double width, required Color color, required InkTool tool}) {
    points.clear();
    active = true;
    this.width = width;
    this.color = color;
    this.tool = tool;
    _sx = _rawX = world.dx;
    _sy = _rawY = world.dy;
    _sp = _rawP = pressure;
    points.addAll([world.dx, world.dy, pressure]);
    notifyListeners();
  }

  /// [minDistance] in Weltkoordinaten: kleinere Bewegungen werden
  /// ignoriert, das spart Punkte ohne sichtbaren Unterschied.
  void extend(Offset world, double pressure, double minDistance) {
    if (!active) return;
    _rawX = world.dx;
    _rawY = world.dy;
    _rawP = pressure;
    _sx += (world.dx - _sx) * smoothing;
    _sy += (world.dy - _sy) * smoothing;
    _sp += (pressure - _sp) * 0.3;
    final lx = points[points.length - 3], ly = points[points.length - 2];
    final dx = _sx - lx, dy = _sy - ly;
    if (dx * dx + dy * dy < minDistance * minDistance) return;
    points.addAll([_sx, _sy, _sp]);
    notifyListeners();
  }

  /// Beendet den Strich und gibt die Punkte zurück (oder null).
  Float32List? finish() {
    if (!active) return null;
    // Glättung hinkt leicht hinterher – der Strich endet dort, wo der
    // Stift wirklich abgehoben wurde.
    final lx = points[points.length - 3], ly = points[points.length - 2];
    if (lx != _rawX || ly != _rawY) points.addAll([_rawX, _rawY, _rawP]);
    final result = Float32List.fromList(points);
    _clear();
    return result;
  }

  void cancel() => _clear();

  /// Ersetzt die Punkte komplett (für Formen, die sich beim Ziehen ändern).
  void setPoints(List<double> pts,
      {required double width, required Color color, required InkTool tool}) {
    points
      ..clear()
      ..addAll(pts);
    active = true;
    this.width = width;
    this.color = color;
    this.tool = tool;
    notifyListeners();
  }

  void _clear() {
    points.clear();
    active = false;
    notifyListeners();
  }
}
