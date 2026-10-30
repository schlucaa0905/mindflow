import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_selector/file_selector.dart';
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';
import 'package:uuid/uuid.dart';

import '../../data/models.dart';
import '../../data/object_repository.dart';

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
    // Seiten zählen und Größen messen – in sehr niedriger Auflösung, das
    // geht schnell. 72 Punkte = 1 Zoll.
    const dpi = 18.0;
    final sizes = <List<double>>[];
    await for (final raster in Printing.raster(bytes, dpi: dpi)) {
      sizes.add([raster.width * 72 / dpi, raster.height * 72 / dpi]);
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

  // --- Seiten darstellen ---------------------------------------------------

  static final Map<String, Uint8List> _bytes = {};
  static final Map<String, ui.Image> _images = {};
  static final List<String> _order = [];

  static Future<Uint8List?> _load(MfObject doc) async {
    final cached = _bytes[doc.id];
    if (cached != null) return cached;
    final file = await fileFor(doc);
    if (file == null || !await file.exists()) return null;
    final b = await file.readAsBytes();
    _bytes
      ..clear() // nur das zuletzt geöffnete Dokument im Speicher halten
      ..[doc.id] = b;
    return b;
  }

  /// Rendert eine Seite als Bild. Ergebnisse werden zwischengespeichert.
  static Future<ui.Image?> renderPage(MfObject doc, int index,
      {double dpi = 150}) async {
    final key = '${doc.id}#$index@${dpi.round()}';
    final hit = _images[key];
    if (hit != null) return hit;
    final bytes = await _load(doc);
    if (bytes == null) return null;
    await for (final raster in Printing.raster(bytes, pages: [index], dpi: dpi)) {
      final image = await raster.toImage();
      _images[key] = image;
      _order.add(key);
      // Nur die letzten Seiten behalten (Speicher).
      while (_order.length > 8) {
        _images.remove(_order.removeAt(0));
      }
      return image;
    }
    return null;
  }

  /// Löscht die PDF-Datei (nur beim endgültigen Löschen verwenden).
  static Future<void> deleteFile(MfObject doc) async {
    final f = await fileFor(doc);
    if (f != null && await f.exists()) await f.delete();
  }
}
