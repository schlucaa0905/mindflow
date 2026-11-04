import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:ui' show Rect, Size;

import 'package:file_selector/file_selector.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdfrx/pdfrx.dart' as pdfrx;
import 'package:uuid/uuid.dart';

import '../../data/models.dart';
import '../../data/object_repository.dart';

/// Ein Link auf einer PDF-Seite.
typedef PdfLinkArea = ({Rect rect, Uri? url, int? page});

/// Import, Speicherung und Darstellung von PDF-Dateien.
///
/// Die PDF selbst bleibt unverändert im App-Ordner liegen. Anmerkungen
/// werden – wie bei Notizbüchern – als Handschrift pro Seite gespeichert.
/// So kann das Original nie beschädigt werden.
class PdfService {
  PdfService._();

  static Future<Directory> _dir() async {
    final base = await getApplicationSupportDirectory();
    final sep = Platform.pathSeparator;
    final dir = Directory('${base.path}${sep}mindflow${sep}docs');
    await dir.create(recursive: true);
    return dir;
  }

  static Future<File?> fileFor(MfObject doc) async {
    final name = doc.fileName;
    if (name == null) return null;
    final dir = await _dir();
    return File('${dir.path}${Platform.pathSeparator}$name');
  }

  /// ID der Handschrift-Datei einer Dokumentseite.
  static String inkIdFor(MfObject doc, int page) => '${doc.id}-p$page';

  /// Datei auswählen. Gibt null zurück, wenn abgebrochen.
  static Future<({Uint8List bytes, String title})?> pick() async {
    const group = XTypeGroup(
      label: 'PDF',
      extensions: ['pdf'],
      mimeTypes: ['application/pdf'],
      uniformTypeIdentifiers: ['com.adobe.pdf'],
    );
    final picked = await openFile(acceptedTypeGroups: [group]);
    if (picked == null) return null;
    final bytes = await picked.readAsBytes();
    var title = picked.name;
    if (title.toLowerCase().endsWith('.pdf')) {
      title = title.substring(0, title.length - 4);
    }
    return (bytes: bytes, title: title);
  }

  /// Mehrere Dateien auf einmal auswählen (z. B. alle Goodnotes-Exporte).
  static Future<List<({Uint8List bytes, String title})>> pickMany() async {
    const group = XTypeGroup(
      label: 'PDF',
      extensions: ['pdf'],
      mimeTypes: ['application/pdf'],
      uniformTypeIdentifiers: ['com.adobe.pdf'],
    );
    final files = await openFiles(acceptedTypeGroups: [group]);
    final out = <({Uint8List bytes, String title})>[];
    for (final f in files) {
      var title = f.name;
      if (title.toLowerCase().endsWith('.pdf')) {
        title = title.substring(0, title.length - 4);
      }
      out.add((bytes: await f.readAsBytes(), title: title));
    }
    return out;
  }

  /// Liest die PDF ein und legt das Dokument an.
  /// Wirft eine Ausnahme mit lesbarer Meldung, wenn die PDF unlesbar ist.
  static Future<MfObject> importBytes(ObjectRepository repo, Uint8List bytes,
      {required String title}) async {
    final sizes = <List<double>>[];
    pdfrx.PdfDocument? d;
    try {
      d = await pdfrx.PdfDocument.openData(Uint8List.fromList(bytes));
      for (final p in d.pages) {
        sizes.add([p.width, p.height]);
      }
    } catch (_) {
      throw const FormatException(
          'Die PDF ist beschädigt oder mit einem Passwort geschützt.');
    } finally {
      d?.dispose();
    }
    if (sizes.isEmpty) {
      throw const FormatException('Die PDF hat keine lesbaren Seiten.');
    }
    final fileName = '${const Uuid().v4()}.pdf';
    final dir = await _dir();
    await File('${dir.path}${Platform.pathSeparator}$fileName')
        .writeAsBytes(bytes, flush: true);
    return repo.create(
      type: ObjectType.document,
      title: title.trim().isEmpty ? 'Dokument' : title.trim(),
      data: {'file': fileName, 'sizes': sizes, 'paper': 'light'},
    );
  }

  // --- Seiten darstellen (PDFium: inkl. Formularfeldern und Anmerkungen) ---

  /// Geöffnete PDFs (höchstens zwei, z. B. Dokument + PDF-Vorlage).
  static final Map<String, Future<pdfrx.PdfDocument?>> _open = {};
  static final Map<String, ui.Image> _images = {};
  static final List<String> _order = [];

  static Future<pdfrx.PdfDocument?> _doc(MfObject doc) {
    final hit = _open.remove(doc.id);
    if (hit != null) return _open[doc.id] = hit; // ans Ende = zuletzt benutzt
    final f = () async {
      final file = await fileFor(doc);
      if (file == null || !await file.exists()) return null;
      try {
        return await pdfrx.PdfDocument.openData(await file.readAsBytes(),
            sourceName: doc.id);
      } catch (_) {
        return null;
      }
    }();
    _open[doc.id] = f;
    while (_open.length > 2) {
      final old = _open.remove(_open.keys.first)!;
      // Etwas warten, damit laufende Darstellungen noch fertig werden.
      Future.delayed(const Duration(seconds: 10), () => old)
          .then((d) => d?.dispose())
          .ignore();
    }
    return f;
  }

  /// Rendert eine Seite als Bild. Ergebnisse werden zwischengespeichert.
  static Future<ui.Image?> renderPage(MfObject doc, int index,
      {double dpi = 150}) async {
    final key = '${doc.id}#$index@${dpi.round()}';
    final hit = _images[key];
    if (hit != null) return hit;
    final d = await _doc(doc);
    if (d == null || index < 0 || index >= d.pages.length) return null;
    final page = d.pages[index];
    final raw = await page.render(
      fullWidth: page.width * dpi / 72,
      fullHeight: page.height * dpi / 72,
      annotationRenderingMode:
          pdfrx.PdfAnnotationRenderingMode.annotationAndForms,
    );
    if (raw == null) return null;
    try {
      final image = await raw.createImage();
      _images[key] = image;
      _order.add(key);
      // Nur die letzten Seiten behalten (Speicher).
      while (_order.length > 8) {
        _images.remove(_order.removeAt(0));
      }
      return image;
    } finally {
      raw.dispose();
    }
  }

  static final Map<String, List<String>> _texts = {};

  /// Gedruckter Text jeder Seite (für die Suche). Leere Einträge bei
  /// gescannten Seiten ohne Text. Wird einmal gelesen und neben der PDF
  /// gespeichert – danach ist die Suche sofort da.
  static Future<List<String>> pageTexts(MfObject doc) async {
    final hit = _texts[doc.id];
    if (hit != null) return hit;
    final dir = await _dir();
    final index = File('${dir.path}${Platform.pathSeparator}${doc.id}.text.json');
    try {
      if (await index.exists()) {
        final list = [
          for (final t in jsonDecode(await index.readAsString()) as List)
            '$t'
        ];
        return _texts[doc.id] = list;
      }
    } catch (_) {
      // Kaputte Datei: neu einlesen.
    }
    final d = await _doc(doc);
    if (d == null) return const [];
    final out = <String>[];
    for (final p in d.pages) {
      try {
        out.add((await p.loadText())?.fullText ?? '');
      } catch (_) {
        out.add('');
      }
    }
    try {
      await index.writeAsString(jsonEncode(out), flush: true);
    } catch (_) {}
    return _texts[doc.id] = out;
  }

  /// Links einer Seite in Seiten-Koordinaten (Größe [size], oben links 0,0):
  /// Internet-Adresse oder Zielseite (ab 1).
  static Future<List<PdfLinkArea>> links(
      MfObject doc, int index, Size size) async {
    final d = await _doc(doc);
    if (d == null || index < 0 || index >= d.pages.length) return const [];
    final page = d.pages[index];
    try {
      return [
        for (final l in await page.loadLinks(compact: true))
          for (final r in l.rects)
            (
              rect: r.toRect(page: page, scaledPageSize: size),
              url: l.url,
              page: l.dest?.pageNumber,
            ),
      ];
    } catch (_) {
      return const [];
    }
  }

  /// Löscht die PDF-Datei (nur beim endgültigen Löschen verwenden).
  static Future<void> deleteFile(MfObject doc) async {
    final f = await fileFor(doc);
    if (f != null && await f.exists()) await f.delete();
    final dir = await _dir();
    final index =
        File('${dir.path}${Platform.pathSeparator}${doc.id}.text.json');
    if (await index.exists()) await index.delete();
  }
}
