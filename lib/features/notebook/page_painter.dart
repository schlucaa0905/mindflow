import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../data/models.dart';
import '../../ink/camera.dart';

/// A4-Format in Punkten (1/72 Zoll). Seiten liegen in Weltkoordinaten
/// immer bei (0, 0) mit dieser Größe.
const Size kPageSize = Size(595, 842);
const Rect kPageRect = Rect.fromLTWH(0, 0, 595, 842);

/// Zeichnet Schreibtisch, Blatt und Vorlage (Linien, Karos, Punkte).
class PagePainter extends CustomPainter {
  PagePainter({
    required this.camera,
    required this.paper,
    required this.template,
  }) : super(repaint: camera);

  final Camera camera;
  final PaperStyle paper;
  final PageTemplate template;

  static const double _lineGap = 28;
  static const double _gridGap = 22;
  static const double _margin = 48;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = paper.desk);

    canvas.save();
    canvas.translate(camera.offset.dx, camera.offset.dy);
    canvas.scale(camera.scale);

    final sheet = RRect.fromRectAndRadius(kPageRect, const Radius.circular(6));
    canvas.drawRRect(
      sheet.shift(const Offset(0, 4)),
      Paint()
        ..color = const Color(0x33000000)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
    );
    canvas.drawRRect(sheet, Paint()..color = paper.sheet);

    // Linien sollen auf dem Bildschirm immer ca. 1 px dick sein.
    final line = Paint()
      ..color = paper.line
      ..strokeWidth = 1 / camera.scale;

    switch (template) {
      case PageTemplate.blank:
        break;
      case PageTemplate.lined:
        for (var y = _margin + _lineGap; y < kPageSize.height - 24; y += _lineGap) {
          canvas.drawLine(Offset(24, y), Offset(kPageSize.width - 24, y), line);
        }
        canvas.drawLine(
          const Offset(_margin + 24, 24),
          Offset(_margin + 24, kPageSize.height - 24),
          Paint()
            ..color = const Color(0x55F87171)
            ..strokeWidth = 1 / camera.scale,
        );
      case PageTemplate.grid:
        for (var y = _gridGap; y < kPageSize.height; y += _gridGap) {
          canvas.drawLine(Offset(0, y), Offset(kPageSize.width, y), line);
        }
        for (var x = _gridGap; x < kPageSize.width; x += _gridGap) {
          canvas.drawLine(Offset(x, 0), Offset(x, kPageSize.height), line);
        }
      case PageTemplate.dotted:
        final dot = Paint()
          ..color = paper.line
          ..strokeWidth = 2.2 / camera.scale
          ..strokeCap = StrokeCap.round;
        final pts = <Offset>[
          for (var y = _gridGap; y < kPageSize.height; y += _gridGap)
            for (var x = _gridGap; x < kPageSize.width; x += _gridGap)
              Offset(x, y)
        ];
        canvas.drawPoints(ui.PointMode.points, pts, dot);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(PagePainter old) =>
      old.camera != camera || old.paper != paper || old.template != template;
}
