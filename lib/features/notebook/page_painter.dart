import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../data/models.dart';
import '../../ink/camera.dart';
import '../../ink/text_layer.dart';
import '../../storage/image_store.dart';

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
    this.image,
    this.pageLabel,
  }) : super(repaint: Listenable.merge([camera, ImageStore.loaded]));

  /// Eigene Vorlage (Bild einer PDF-Seite) statt Linien.
  final String? image;

  /// Seitenzahl unten auf dem Blatt (null = keine).
  final String? pageLabel;

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
        hairline: 1 / camera.scale, shadow: true, image: image);
    paintPageLabel(canvas, page, paper, pageLabel);
    canvas.restore();
  }

  @override
  bool shouldRepaint(PagePainter old) =>
      old.camera != camera ||
      old.paper != paper ||
      old.template != template ||
      old.page != page ||
      old.pageLabel != pageLabel;
}

/// Kleine Vorschau einer Vorlage (z. B. im Dialog "Neues Notizbuch").
class TemplatePreviewPainter extends CustomPainter {
  TemplatePreviewPainter(this.paper, this.template, this.format, {this.image})
      : super(repaint: ImageStore.loaded);

  final PaperStyle paper;
  final PageTemplate template;
  final PageFormat format;

  /// Eigene Vorlage (Bild) statt der Linien.
  final String? image;

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
    paintSheet(canvas, page, paper, template,
        hairline: 1.2 / s, shadow: false, image: image);
    canvas.restore();
  }

  @override
  bool shouldRepaint(TemplatePreviewPainter old) =>
      old.paper != paper ||
      old.template != template ||
      old.format != format ||
      old.image != image;
}

/// Seitenzahlen eines Notizbuchs (Einstellung `pageNumbers` im Notizbuch).
enum PageNumbers {
  off('Aus'),
  number('Nur Nummer (3)'),
  ofTotal('Mit Gesamtzahl (3 / 12)');

  const PageNumbers(this.label);
  final String label;

  static PageNumbers of(MfObject notebook) {
    final v = notebook.data['pageNumbers'];
    return v is int && v >= 0 && v < values.length ? values[v] : off;
  }

  /// Text für Seite [index] (ab 0) von [total] – oder null.
  String? textFor(int index, int total) => switch (this) {
        PageNumbers.off => null,
        PageNumbers.number => '${index + 1}',
        PageNumbers.ofTotal => '${index + 1} / $total',
      };
}

/// Seitenzahl unten in der Mitte des Blatts (auch im PDF-Export).
void paintPageLabel(Canvas canvas, Rect page, PaperStyle paper, String? text) {
  if (text == null) return;
  final dark = paper.sheet.computeLuminance() < 0.4;
  final tp = TextPainter(
    text: TextSpan(
        text: text,
        style: TextStyle(
            fontSize: 10,
            letterSpacing: 0.4,
            color: dark ? const Color(0x99FFFFFF) : const Color(0x8C000000))),
    textDirection: TextDirection.ltr,
  )..layout();
  tp.paint(canvas,
      Offset(page.center.dx - tp.width / 2, page.bottom - 20 - tp.height / 2));
  tp.dispose();
}

/// Zeichnet ein Blatt mit Vorlage in Weltkoordinaten.
void paintSheet(Canvas canvas, Rect page, PaperStyle paper,
    PageTemplate template,
    {required double hairline, required bool shadow, String? image}) {
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
  final k = paper.gap;
  final bg = image == null ? null : ImageStore.cached(image);
  if (image != null && bg == null) ImageStore.load(image);
  if (bg != null) {
    canvas.drawImageRect(
        bg,
        Rect.fromLTWH(0, 0, bg.width.toDouble(), bg.height.toDouble()),
        page,
        Paint()..filterQuality = FilterQuality.medium);
  }
  if (image != null) {
    canvas.restore();
    return;
  }

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
      hLines(28 * k, 76, 24, w - 24);
      canvas.drawLine(const Offset(72, 24), Offset(72, h - 24), accentLine);
    case PageTemplate.linedNarrow:
      hLines(21 * k, 70, 24, w - 24);
      canvas.drawLine(const Offset(72, 24), Offset(72, h - 24), accentLine);
    case PageTemplate.grid:
      grid(22 * k);
    case PageTemplate.gridSmall:
      grid(14 * k);
    case PageTemplate.dotted:
      final dot = Paint()
        ..color = paper.line
        ..strokeWidth = hairline * 2.4
        ..strokeCap = StrokeCap.round;
      canvas.drawPoints(ui.PointMode.points, [
        for (var y = 22 * k; y < h; y += 22 * k)
          for (var x = 22 * k; x < w; x += 22 * k) Offset(x, y)
      ], dot);
    case PageTemplate.cornell:
      // Kopf, Stichwortspalte links, Zusammenfassung unten.
      final cue = w * 0.28;
      final summaryTop = h - h * 0.2;
      canvas.drawLine(Offset(24, 72), Offset(w - 24, 72), accentLine);
      canvas.drawLine(Offset(cue, 72), Offset(cue, summaryTop), line);
      for (var y = 100.0; y < summaryTop; y += 28 * k) {
        canvas.drawLine(Offset(cue + 8, y), Offset(w - 24, y), line);
      }
      canvas.drawLine(
          Offset(24, summaryTop), Offset(w - 24, summaryTop), accentLine);
    case PageTemplate.music:
      // Notensysteme: je 5 Linien, Abstand 7, zwischen den Systemen Luft.
      for (var top = 70.0; top + 28 * k < h - 30; top += 64 * k) {
        for (var i = 0; i < 5; i++) {
          canvas.drawLine(
              Offset(32, top + i * 7 * k), Offset(w - 32, top + i * 7 * k), line);
        }
      }
    case PageTemplate.planner:
      // Kopfzeile + 7 Tage (2 Spalten) + Notizfeld.
      canvas.drawLine(Offset(24, 64), Offset(w - 24, 64), accentLine);
      const days = ['Montag', 'Dienstag', 'Mittwoch', 'Donnerstag', 'Freitag',
        'Samstag', 'Sonntag', 'Notizen'];
      final cellH = (h - 64 - 24) / 4, cellW = (w - 48) / 2;
      for (var i = 0; i < 8; i++) {
        final r = Rect.fromLTWH(24 + (i % 2) * cellW, 64 + (i ~/ 2) * cellH, cellW, cellH);
        canvas.drawRect(r, line..style = PaintingStyle.stroke);
        final tp = TextPainter(
          text: TextSpan(
              text: days[i],
              style: TextStyle(fontSize: 11, color: paper.line.withValues(alpha: 1))),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, r.topLeft + const Offset(8, 6));
        tp.dispose();
      }
      line.style = PaintingStyle.fill;
    case PageTemplate.coords:
      // Feines Raster mit Achsen in der Mitte.
      final step = 20 * k;
      grid(step);
      final axis = Paint()
        ..color = paper.line.withValues(alpha: 1)
        ..strokeWidth = hairline * 2;
      final cx = (w / 2 / step).round() * step,
          cy = (h / 2 / step).round() * step;
      canvas.drawLine(Offset(0, cy), Offset(w, cy), axis);
      canvas.drawLine(Offset(cx, 0), Offset(cx, h), axis);
    case PageTemplate.todo:
      final box = Paint()
        ..color = paper.line
        ..style = PaintingStyle.stroke
        ..strokeWidth = hairline * 1.4;
      canvas.drawLine(Offset(24, 72), Offset(w - 24, 72), accentLine);
      for (var y = 108.0; y < h - 40; y += 34 * k) {
        canvas.drawRRect(
            RRect.fromRectAndRadius(
                Rect.fromLTWH(32, y - 18, 14, 14), const Radius.circular(3)),
            box);
        canvas.drawLine(Offset(58, y), Offset(w - 24, y), line);
      }
  }
  canvas.restore();
}

/// Linienabstand der Vorlage für Textfelder (passend zu [paintSheet]);
/// [k] = Abstand der Seite (eng/normal/weit).
TextLineGrid? textGridFor(PageTemplate t, [double k = 1]) => switch (t) {
      PageTemplate.blank => null,
      PageTemplate.lined => TextLineGrid(28 * k, 76),
      PageTemplate.linedNarrow => TextLineGrid(21 * k, 70),
      PageTemplate.grid => TextLineGrid(22 * k, 0, snapX: true),
      PageTemplate.gridSmall => TextLineGrid(14 * k, 0, snapX: true),
      PageTemplate.dotted => TextLineGrid(22 * k, 0, snapX: true),
      PageTemplate.cornell => TextLineGrid(28 * k, 100),
      PageTemplate.todo => TextLineGrid(34 * k, 108),
      PageTemplate.music || PageTemplate.planner => null,
      PageTemplate.coords => TextLineGrid(20 * k, 0, snapX: true),
    };

/// Abstände für Linien und Kästchen.
const kPageGaps = <double, String>{0.75: 'Eng', 1.0: 'Normal', 1.35: 'Weit'};

/// Ist die Blattfarbe dunkel (dann helle Schrift)?
bool isDarkSheet(Color c) => c.computeLuminance() < 0.3;

/// Papier einer Seite: das des Notizbuchs, ggf. mit eigener Blattfarbe
/// (`paperColor`) und eigenem Linienabstand (`gap`).
PaperStyle pageStyle(PaperStyle base, MfObject page) {
  final c = page.data['paperColor'], g = page.data['gap'];
  if (c is! int && g is! num) return base;
  return base.copyWith(
    sheet: c is int ? Color(c) : null,
    // Linien passend zur Farbe: dezent dunkel auf hell, hell auf dunkel.
    line: c is int
        ? (isDarkSheet(Color(c))
            ? const Color(0x38FFFFFF)
            : const Color(0x30000000))
        : null,
    gap: g is num ? g.toDouble().clamp(0.5, 2.0).toDouble() : null,
  );
}
