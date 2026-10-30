import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../ink/ink_codec.dart';
import '../ink/stroke.dart';

/// Speichert die Handschrift eines Objekts (Seite, Canvas) als Datei.
/// Dateiname = stabile Objekt-ID.
///
/// Absturzsicher: Erst in eine Temp-Datei schreiben, dann umbenennen.
/// Eine halb geschriebene Datei ersetzt also nie die letzte gute Version.
class InkStore {
  InkStore(this.objectId);

  final String objectId;
  File? _file;

  static Future<Directory> _dir() async {
    final base = await getApplicationSupportDirectory();
    final sep = Platform.pathSeparator;
    final dir = Directory('${base.path}${sep}mindflow${sep}ink');
    await dir.create(recursive: true);
    return dir;
  }

  Future<File> _target() async {
    if (_file != null) return _file!;
    final dir = await _dir();
    return _file =
        File('${dir.path}${Platform.pathSeparator}$objectId.mfink');
  }

  Future<List<Stroke>> load() async {
    final file = await _target();
    if (!await file.exists()) return [];
    final bytes = await file.readAsBytes();
    try {
      return await Isolate.run(() => decodeInk(bytes));
    } on FormatException {
      // Nie still löschen: beschädigte Datei zur Seite legen.
      final stamp = DateTime.now().millisecondsSinceEpoch;
      await file.rename('${file.path}.beschaedigt-$stamp');
      rethrow;
    }
  }

  Future<int> save(List<Stroke> strokes) async {
    // Momentaufnahme sofort – bevor irgendetwas anderes passiert.
    final snapshot = List<Stroke>.of(strokes);
    final file = await _target();
    final Uint8List bytes = await Isolate.run(() => encodeInk(snapshot));
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsBytes(bytes, flush: true);
    await tmp.rename(file.path);
    return bytes.length;
  }

  /// Kopiert die Handschrift auf ein neues Objekt (z. B. Seite duplizieren).
  /// Jeder Strich bekommt eine neue ID, gelöschte werden nicht mitkopiert.
  static Future<void> duplicate(String fromId, String toId) async {
    final source = await InkStore(fromId).load();
    const uuid = Uuid();
    final copies = [
      for (final s in source)
        if (!s.deleted)
          Stroke(
            id: uuid.v4(),
            color: s.color,
            width: s.width,
            tool: s.tool,
            points: Float32List.fromList(s.points),
          ),
    ];
    if (copies.isEmpty) return;
    await InkStore(toId).save(copies);
  }
}
