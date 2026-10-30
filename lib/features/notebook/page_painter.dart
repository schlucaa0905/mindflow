import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../data/models.dart';
import '../../ink/camera.dart';

/// Seitenrechteck in Weltkoordinaten. Seiten liegen immer bei (0, 0).
/// Einheit: Punkt (1/72 Zoll), A4 = 595 × 842.
Rect pageRectFor(PageFormat f) => Rect.fromLTWH(0, 0, f.width, f.height);

/// Zeichnet Schreibtisch, Blatt und Vorlage auf der geöffneten Seite.
class PagePainter extends CustomPainter {
  PagePainter({
    required this.camera,
    required this.paper,
    required this.template,
    required this.page,
  }) : super(repaint: camera);

  final Camera camera;
  final PaperStyle paper;
  final PageTemplate template;
  final Rect page;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = paper.desk);
    canvas.save();
    canvas.translate(camera.offset.dx, camera.offset.dy);
    canvas.scale(camera.scale);
    paintSheet(canvas, page, paper, template,
        hairline: 1 / camera.scale, shadow: true);
    canvas.restore();
  }

  @override
  bool shouldRepaint(PagePainter old) =>
      old.camera != camera ||
      old.paper != paper ||
      old.template != template ||
      old.page != page;
}

/// Kleine Vorschau einer Vorlage (z. B. im Dialog "Neues Notizbuch").
class TemplatePreviewPainter extends CustomPainter {
  TemplatePreviewPainter(this.paper, this.template, this.format);

  final PaperStyle paper;
  final PageTemplate template;
  final PageFormat format;

  @override
  void paint(Canvas canvas, Size size) {
    final page = pageRectFor(format);
    final s = size.width / page.width < size.height / page.height
        ? size.width / page.width
        : size.height / page.height;
    canvas.save();
    canvas.translate((size.width - page.width * s) / 2,
        (size.height - page.height * s) / 2);
    canvas.scale(s);
    paintSheet(canvas, page, paper, template, hairline: 1.2 / s, shadow: false);
    canvas.restore();
  }

  @override
  bool shouldRepaint(TemplatePreviewPainter old) =>
      old.paper != paper || old.template != template || old.format != format;
}

/// Zeichnet ein Blatt mit Vorlage in Weltkoordinaten.
void paintSheet(Canvas canvas, Rect page, PaperStyle paper,
    PageTemplate template,
    {required double hairline, required bool shadow}) {
  final sheet = RRect.fromRectAndRadius(page, const Radius.circular(6));
  if (shadow) {
    canvas.drawRRect(
      sheet.shift(const Offset(0, 4)),
      Paint()
        ..color = const Color(0x33000000)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
    );
  }
  canvas.drawRRect(sheet, Paint()..color = paper.sheet);

  canvas.save();
  canvas.clipRRect(sheet);
  final line = Paint()
    ..color = paper.line
    ..strokeWidth = hairline;
  final accentLine = Paint()
    ..color = const Color(0x66F87171)
    ..strokeWidth = hairline;
  final w = page.width, h = page.height;

  void hLines(double gap, double from, double left, double right) {
    for (var y = from; y < h - 24; y += gap) {
      canvas.drawLine(Offset(left, y), Offset(right, y), line);
    }
  }

  void grid(double gap) {
    for (var y = gap; y < h; y += gap) {
      canvas.drawLine(Offset(0, y), Offset(w, y), line);
    }
    for (var x = gap; x < w; x += gap) {
      canvas.drawLine(Offset(x, 0), Offset(x, h), line);
    }
  }

  switch (template) {
    case PageTemplate.blank:
      break;
    case PageTemplate.lined:
      hLines(28, 76, 24, w - 24);
      canvas.drawLine(const Offset(72, 24), Offset(72, h - 24), accentLine);
    case PageTemplate.linedNarrow:
      hLines(21, 70, 24, w - 24);
      canvas.drawLine(const Offset(72, 24), Offset(72, h - 24), accentLine);
    case PageTemplate.grid:
      grid(22);
    case PageTemplate.gridSmall:
      grid(14);
    case PageTemplate.dotted:
      final dot = Paint()
        ..color = paper.line
        ..strokeWidth = hairline * 2.4
        ..strokeCap = StrokeCap.round;
      canvas.drawPoints(ui.PointMode.points, [
        for (var y = 22.0; y < h; y += 22)
          for (var x = 22.0; x < w; x += 22) Offset(x, y)
      ], dot);
    case PageTemplate.cornell:
      // Kopf, Stichwortspalte links, Zusammenfassung unten.
      final cue = w * 0.28;
      final summaryTop = h - h * 0.2;
      canvas.drawLine(Offset(24, 72), Offset(w - 24, 72), accentLine);
      canvas.drawLine(Offset(cue, 72), Offset(cue, summaryTop), line);
      for (var y = 100.0; y < summaryTop; y += 28) {
        canvas.drawLine(Offset(cue + 8, y), Offset(w - 24, y), line);
      }
      canvas.drawLine(
          Offset(24, summaryTop), Offset(w - 24, summaryTop), accentLine);
    case PageTemplate.todo:
      final box = Paint()
        ..color = paper.line
        ..style = PaintingStyle.stroke
        ..strokeWidth = hairline * 1.4;
      canvas.drawLine(Offset(24, 72), Offset(w - 24, 72), accentLine);
      for (var y = 108.0; y < h - 40; y += 34) {
        canvas.drawRRect(
            RRect.fromRectAndRadius(
                Rect.fromLTWH(32, y - 18, 14, 14), const Radius.circular(3)),
            box);
        canvas.drawLine(Offset(58, y), Offset(w - 24, y), line);
      }
  }
  canvas.restore();
}
