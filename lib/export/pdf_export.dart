import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../ink/stroke.dart';
import '../ink/stroke_renderer.dart';

/// Eine fertig gezeichnete Seite für den Export.
class ExportPage {
  ExportPage(this.size, this.png);

  /// Seitengröße in Punkten.
  final Size size;
  final Uint8List png;
}

/// Zeichnet eine Seite (Hintergrund + Handschrift) als PNG.
/// [scale] 2 ergibt 144 dpi – scharf genug zum Drucken und Teilen.
Future<ExportPage> renderPage({
  required Rect page,
  required void Function(Canvas canvas) paintBackground,
  required List<Stroke> strokes,
  double scale = 2,
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.scale(scale);
  canvas.translate(-page.left, -page.top);
  paintBackground(canvas);
  canvas.clipRect(page);
  for (final s in strokes) {
    if (!s.deleted && s.tool == InkTool.highlighter) paintStroke(canvas, s);
  }
  for (final s in strokes) {
    if (!s.deleted && s.tool != InkTool.highlighter) paintStroke(canvas, s);
  }
  final picture = recorder.endRecording();
  final image = await picture.toImage(
      (page.width * scale).round(), (page.height * scale).round());
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  picture.dispose();
  return ExportPage(page.size, data!.buffer.asUint8List());
}

/// Baut ein PDF aus den Seiten und öffnet den Teilen-/Speichern-Dialog.
Future<void> sharePdf(String fileName, List<ExportPage> pages) async {
  final doc = pw.Document();
  for (final p in pages) {
    final image = pw.MemoryImage(p.png);
    doc.addPage(pw.Page(
      pageFormat: PdfPageFormat(p.size.width, p.size.height, marginAll: 0),
      build: (_) => pw.Image(image, fit: pw.BoxFit.fill),
    ));
  }
  final bytes = await doc.save();
  final safe = fileName.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
  await Printing.sharePdf(bytes: bytes, filename: '$safe.pdf');
}
