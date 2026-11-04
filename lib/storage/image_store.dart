import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

/// Eingefügte Bilder: Dateien in `mindflow/images`, dekodiert im Speicher.
class ImageStore {
  static final Map<String, ui.Image> _cache = {};
  static final Set<String> _loading = {};

  /// Zählt hoch, sobald ein Bild fertig geladen ist (zum Neuzeichnen).
  static final ValueNotifier<int> loaded = ValueNotifier(0);

  static Future<Directory> dir() async {
    final base = await getApplicationSupportDirectory();
    final sep = Platform.pathSeparator;
    final d = Directory('${base.path}${sep}mindflow${sep}images');
    await d.create(recursive: true);
    return d;
  }

  /// Speichert ein Bild und gibt seinen Dateinamen zurück.
  static Future<String> save(Uint8List bytes, String ext) async {
    final name = '${const Uuid().v4()}.${ext.toLowerCase()}';
    final d = await dir();
    await File('${d.path}${Platform.pathSeparator}$name').writeAsBytes(bytes);
    return name;
  }

  static ui.Image? cached(String name) => _cache[name];

  /// Lädt ein Bild (einmalig) und meldet es über [loaded].
  static Future<ui.Image?> load(String name) async {
    final hit = _cache[name];
    if (hit != null || !_loading.add(name)) return hit;
    try {
      final d = await dir();
      final bytes =
          await File('${d.path}${Platform.pathSeparator}$name').readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      _cache[name] = frame.image;
      loaded.value++;
      return frame.image;
    } catch (_) {
      return null;
    } finally {
      _loading.remove(name);
    }
  }

  static Future<void> preload(Iterable<String> names) =>
      Future.wait(names.map(load));

  /// Größe in Pixeln (für das Seitenverhältnis beim Einfügen).
  static Future<ui.Size?> sizeOf(Uint8List bytes) async {
    try {
      final codec = await ui.instantiateImageCodec(bytes);
      final f = await codec.getNextFrame();
      final s = ui.Size(f.image.width.toDouble(), f.image.height.toDouble());
      f.image.dispose();
      return s;
    } catch (_) {
      return null;
    }
  }
}

/// Zeigt ein gespeichertes Bild (lädt es bei Bedarf).
class StoredImage extends StatelessWidget {
  const StoredImage(this.name, {super.key, this.height = 160});

  final String name;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: FutureBuilder<ui.Image?>(
        future: ImageStore.load(name),
        initialData: ImageStore.cached(name),
        builder: (context, snap) => snap.data == null
            ? const SizedBox.shrink()
            : RawImage(image: snap.data, fit: BoxFit.contain),
      ),
    );
  }
}
