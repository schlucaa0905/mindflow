import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import '../ink/ink_codec.dart';
import '../ink/stroke.dart';

/// Speichert eine Tinten-Fläche als Datei auf dem Gerät.
///
/// Sicher gegen Abstürze: Es wird erst in eine Temp-Datei geschrieben und
/// diese dann umbenannt. Eine halb geschriebene Datei ersetzt also nie
/// die letzte gute Version.
class InkStore {
  InkStore(this.name);

  final String name;
  File? _file;

  Future<File> _target() async {
    if (_file != null) return _file!;
    final base = await getApplicationSupportDirectory();
    final dir = Directory('${base.path}${Platform.pathSeparator}mindflow');
    await dir.create(recursive: true);
    return _file = File('${dir.path}${Platform.pathSeparator}$name.mfink');
  }

  Future<String> get path async => (await _target()).path;

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
    final file = await _target();
    final snapshot = List<Stroke>.of(strokes);
    final Uint8List bytes = await Isolate.run(() => encodeInk(snapshot));
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsBytes(bytes, flush: true);
    await tmp.rename(file.path);
    return bytes.length;
  }
}
