import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../app/services.dart';
import '../app/theme.dart';
import '../data/object_repository.dart';
import '../data/text_repository.dart';
import '../ink/ink_codec.dart';
import '../ink/ink_controller.dart';
import '../ink/stroke.dart';
import '../ink/stroke_renderer.dart';
import '../ink/text_layer.dart' show paintPageImages, paintTextItems;
import '../ui/widgets.dart';
import 'image_store.dart';

/// Ein gespeichertes Element: Striche, Textfelder und Bilder aus einer
/// Lasso-Auswahl – überall wieder einfügbar (Skizzen, Symbole, Stempel).
class SavedElement {
  SavedElement(this.id, this.name, this.strokes, this.items);

  final String id;
  String name;
  final List<Stroke> strokes;
  final List<TextItem> items;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'ink': base64Encode(encodeInk(strokes)),
        'items': [for (final t in items) t.toJson()],
      };

  static SavedElement? fromJson(Object? j) {
    if (j is! Map) return null;
    try {
      return SavedElement(
        j['id'] as String,
        (j['name'] as String?) ?? 'Element',
        decodeInk(base64Decode(j['ink'] as String)),
        [
          for (final t in (j['items'] as List? ?? const []))
            TextItem.fromRow((t as Map).cast<String, dynamic>())
        ],
      );
    } catch (_) {
      return null; // Kaputter Eintrag: einfach überspringen.
    }
  }

  /// Umriss (Striche und Elemente; Text grob geschätzt).
  Rect get bounds {
    Rect? r;
    for (final s in strokes) {
      r = r == null ? s.bounds : r.expandToInclude(s.bounds);
    }
    for (final t in items) {
      final b = Rect.fromLTWH(
          t.x, t.y, t.w, t.isText ? t.size * 1.4 * (1 + '\n'.allMatches(t.text).length) : t.h);
      r = r == null ? b : r.expandToInclude(b);
    }
    return r ?? Rect.zero;
  }
}

/// Die Bibliothek (in den App-Einstellungen gespeichert).
class ElementLibrary {
  static const _key = 'elements';

  static List<SavedElement> load(ObjectRepository repo) {
    try {
      final list = jsonDecode(repo.setting(_key) ?? '[]') as List;
      return list.map(SavedElement.fromJson).whereType<SavedElement>().toList();
    } catch (_) {
      return [];
    }
  }

  static void save(ObjectRepository repo, List<SavedElement> list) =>
      repo.setSetting(_key, jsonEncode([for (final e in list) e.toJson()]));
}

/// Lasso-Auswahl als Element speichern.
Future<void> saveSelectionAsElement(
    BuildContext context, InkController c) async {
  final repo = Services.of(context).objects;
  if (!c.hasSelection) return;
  final items = [
    if (c.items != null)
      for (final t in c.items!.all)
        if (c.selectedItems.contains(t.id)) t.copy(ownerId: '')
  ];
  final strokes = [for (final s in c.selection) s];
  final name = await askText(context,
      title: 'Als Element speichern',
      hint: 'Name, z. B. Router-Symbol',
      confirm: 'Speichern');
  if (name == null || !context.mounted) return;
  final list = ElementLibrary.load(repo)
    ..add(SavedElement(const Uuid().v4(),
        name.trim().isEmpty ? 'Element' : name.trim(), strokes, items));
  ElementLibrary.save(repo, list);
  ScaffoldMessenger.maybeOf(context)?.showSnackBar(const SnackBar(
      duration: Duration(seconds: 3),
      content: Text('Gespeichert – einfügen mit „Element einfügen“ '
          '(im Lasso oder im „+“-Menü).')));
}

/// Bibliothek zeigen; antippen fügt ein (als Lasso-Auswahl in der Mitte).
Future<void> showElementPicker(BuildContext context, InkController c) {
  final repo = Services.of(context).objects;
  return showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(builder: (ctx, setState) {
      final list = ElementLibrary.load(repo);
      final mf = ctx.mf;
      return AlertDialog(
        title: const Text('Element einfügen'),
        content: SizedBox(
          width: 520,
          child: list.isEmpty
              ? Text(
                  'Noch keine Elemente. Kreise etwas mit dem Lasso ein und '
                  'tippe auf „Als Element“.',
                  style: TextStyle(color: mf.textMuted))
              : SingleChildScrollView(
                  child: Wrap(spacing: 10, runSpacing: 10, children: [
                    for (final e in list)
                      GestureDetector(
                        onTap: () {
                          Navigator.pop(ctx);
                          c.insertClip(e.strokes, e.items);
                        },
                        child: Column(children: [
                          Container(
                            width: 110,
                            height: 90,
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: mf.surfaceRaised,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: mf.border),
                            ),
                            child: CustomPaint(painter: _ElementPainter(e)),
                          ),
                          SizedBox(
                            width: 110,
                            child: Row(children: [
                              Expanded(
                                child: Text(e.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        fontSize: 12, color: mf.text)),
                              ),
                              InkWell(
                                onTap: () async {
                                  final ok = await showDialog<bool>(
                                    context: ctx,
                                    builder: (d) => AlertDialog(
                                      title: Text('„${e.name}“ löschen?'),
                                      actions: [
                                        TextButton(
                                            onPressed: () =>
                                                Navigator.pop(d, false),
                                            child: const Text('Abbrechen')),
                                        FilledButton(
                                            onPressed: () =>
                                                Navigator.pop(d, true),
                                            child: const Text('Löschen')),
                                      ],
                                    ),
                                  );
                                  if (ok != true) return;
                                  ElementLibrary.save(repo, [
                                    for (final x in list)
                                      if (x.id != e.id) x
                                  ]);
                                  setState(() {});
                                },
                                child: Icon(Icons.close_rounded,
                                    size: 16, color: mf.textMuted),
                              ),
                            ]),
                          ),
                        ]),
                      ),
                  ]),
                ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Schließen')),
        ],
      );
    }),
  );
}

/// Vorschau eines Elements, eingepasst.
class _ElementPainter extends CustomPainter {
  _ElementPainter(this.e) : super(repaint: ImageStore.loaded);
  final SavedElement e;

  @override
  void paint(Canvas canvas, Size size) {
    final b = e.bounds;
    if (b.isEmpty) return;
    final s = math.min(size.width / b.width, size.height / b.height);
    canvas.save();
    canvas.translate((size.width - b.width * s) / 2, (size.height - b.height * s) / 2);
    canvas.scale(s);
    canvas.translate(-b.left, -b.top);
    paintPageImages(canvas, e.items);
    for (final st in e.strokes) {
      paintStroke(canvas, st);
    }
    paintTextItems(canvas, [for (final t in e.items) if (t.isText) t]);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_ElementPainter old) => old.e != e;
}
