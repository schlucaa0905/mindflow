import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:mindflow/data/database.dart';
import 'package:mindflow/data/models.dart';
import 'package:mindflow/data/object_repository.dart';
import 'package:mindflow/data/study_repository.dart';
import 'package:mindflow/data/text_repository.dart';
import 'package:mindflow/features/common/folders.dart';
import 'package:mindflow/features/knowledge/knowledge_graph.dart';
import 'package:mindflow/features/study/quiz_screen.dart';
import 'package:mindflow/ink/ink_codec.dart';
import 'package:mindflow/ink/ink_controller.dart';
import 'package:mindflow/ink/ink_history.dart';
import 'package:mindflow/ink/stroke.dart';
import 'package:mindflow/ui/find_dialog.dart';

/// Einfache Elemente-Ablage für Tests (statt der Textebene).
class _Host implements PageItems {
  final Map<String, TextItem> items = {};

  @override
  List<TextItem> get all => items.values.toList();

  @override
  Rect rectOf(TextItem t) => Rect.fromLTWH(t.x, t.y, t.w, t.isImage ? t.h : 20);

  @override
  void write(List<TextItem> upsert, Set<String> remove) {
    for (final id in remove) {
      items.remove(id);
    }
    for (final t in upsert) {
      items[t.id] = t.copy();
    }
  }
}

void main() {
  test('Füllfarbe wird gespeichert und alte Dateien bleiben lesbar', () {
    final s = Stroke(
        id: 'a',
        color: 0xFF000000,
        width: 2,
        tool: InkTool.shape,
        points: Float32List.fromList([0, 0, .5, 10, 0, .5, 10, 10, .5, 0, 0, .5]),
        fill: 0x668B5CF6);
    final plain = Stroke(
        id: 'b',
        color: 0xFF000000,
        width: 2,
        tool: InkTool.pen,
        points: Float32List.fromList([0, 0, .5]),
        deleted: true);
    final back = decodeInk(encodeInk([s, plain]));
    expect(back[0].fill, 0x668B5CF6);
    expect(back[0].tool, InkTool.shape);
    expect(back[1].fill, isNull);
    expect(back[1].deleted, isTrue);
  });

  group('Lasso mit Textfeldern und Bildern', () {
    late InkController c;
    late _Host host;

    setUp(() {
      c = InkController(stylusOnly: true)..setTool(ToolMode.lasso);
      host = _Host();
      c.items = host;
      host.items['t'] = TextItem(
          id: 't', ownerId: 'p', x: 10, y: 10, w: 100, text: 'Hallo',
          size: 18, color: 0xFF000000);
      host.items['i'] = TextItem.image(
          id: 'i', ownerId: 'p', x: 300, y: 300, w: 80, h: 40, file: 'x.png');
    });

    void lasso(Rect r) {
      c.beginLasso(r.topLeft);
      c.extendLasso(r.topRight);
      c.extendLasso(r.bottomRight);
      c.extendLasso(r.bottomLeft);
      c.endLasso();
    }

    test('einkreisen, verschieben, rückgängig', () {
      lasso(const Rect.fromLTWH(0, 0, 200, 100));
      expect(c.selectedItems, {'t'});
      expect(c.hasSelection, isTrue);
      c.beginMoveSelection(const Offset(50, 20));
      c.moveSelection(const Offset(150, 70));
      c.endMoveSelection();
      expect(host.items['t']!.x, 110);
      expect(host.items['t']!.y, 60);
      c.undo();
      expect(host.items['t']!.x, 10);
      c.redo();
      expect(host.items['t']!.x, 110);
    });

    test('Bild skalieren, duplizieren, löschen, einfügen', () {
      lasso(const Rect.fromLTWH(290, 290, 100, 60));
      expect(c.selectedItems, {'i'});
      final b = c.selectionBounds!;
      c.beginScaleSelection(b.bottomRight);
      c.moveSelection(b.topLeft + (b.bottomRight - b.topLeft) * 2);
      c.endMoveSelection();
      expect(host.items['i']!.w, closeTo(160, 1e-6));
      expect(host.items['i']!.h, closeTo(80, 1e-6));

      c.duplicateSelection();
      expect(host.items.length, 3);
      c.deleteSelection();
      expect(host.items.length, 2);
      c.undo();
      expect(host.items.length, 3);

      // Nur das erste Bild einkreisen, kopieren und woanders einfügen.
      lasso(const Rect.fromLTWH(295, 295, 15, 15));
      expect(c.selectedItems, {'i'});
      c.copySelection();
      c.paste(at: const Offset(600, 600));
      expect(host.items.length, 4);
      expect(c.selectedItems.length, 1);
      InkController.clipboard = const [];
      InkController.itemClipboard = const [];
    });

    test('Bild einfügen ist rückgängig machbar', () {
      c.insertItems([
        TextItem.image(
            id: 'n', ownerId: 'p', x: 0, y: 0, w: 10, h: 10, file: 'y.png')
      ]);
      expect(host.items.containsKey('n'), isTrue);
      expect(c.selectedItems, {'n'});
      c.undo();
      expect(host.items.containsKey('n'), isFalse);
    });

    test('Umfärben ändert Text, nicht Bilder', () {
      lasso(const Rect.fromLTWH(0, 0, 500, 500));
      c.recolorSelection(const Color(0xFFFF0000));
      expect(host.items['t']!.color, 0xFFFF0000);
      expect(host.items['i']!.isImage, isTrue);
    });
  });

  test('Bilder werden in der Datenbank gespeichert und kopiert', () {
    final db = AppDatabase.inMemory();
    addTearDown(db.dispose);
    final repo = TextRepository(db.raw);
    repo.upsert(TextItem.image(
        id: 'i', ownerId: 'a', x: 1, y: 2, w: 30, h: 40, file: 'f.png'));
    final i = repo.items('a').single;
    expect(i.isImage, isTrue);
    expect(i.h, 40);
    expect(i.file, 'f.png');
    repo.delete('i');
    expect(repo.items('a'), isEmpty);
    repo.upsert(i);
    expect(repo.items('a').length, 1);
    repo.duplicateAll('a', 'b');
    expect(repo.items('b').single.file, 'f.png');
    expect(repo.search('f.png'), isEmpty);
  });

  group('Ordner', () {
    late AppDatabase db;
    late ObjectRepository repo;
    setUp(() {
      db = AppDatabase.inMemory();
      repo = ObjectRepository(db.raw);
    });
    tearDown(() => db.dispose());

    test('verschachtelt, umbenennen, auflösen', () {
      final nb = repo.create(
          type: ObjectType.notebook, data: {'category': 'Schule/Mathe'});
      addFolder(repo, ObjectType.notebook, 'Privat');
      expect(allFolders(repo, ObjectType.notebook),
          ['Privat', 'Schule', 'Schule/Mathe']);
      expect(subFolders(allFolders(repo, ObjectType.notebook), 'Schule'),
          ['Schule/Mathe']);
      moveFolder(repo, ObjectType.notebook, 'Schule', 'Uni');
      expect(repo.get(nb.id)!.category, 'Uni/Mathe');
      moveFolder(repo, ObjectType.notebook, 'Uni/Mathe', 'Uni');
      expect(repo.get(nb.id)!.category, 'Uni');
      moveFolder(repo, ObjectType.notebook, 'Uni', '');
      expect(repo.get(nb.id)!.category, '');
      expect(allFolders(repo, ObjectType.notebook), ['Privat']);
    });
  });

  test('Quiz: 4 Antworten, eine richtig, verschiedene Rückseiten', () {
    final db = AppDatabase.inMemory();
    addTearDown(db.dispose);
    final study = StudyRepository(db.raw, ObjectRepository(db.raw));
    for (final p in const [['A', '1'], ['B', '2'], ['C', '3']]) {
      study.create(front: p[0], back: p[1]);
    }
    expect(buildQuiz(study.allCards(), math.Random(1)), isEmpty);
    study.create(front: 'D', back: '4');
    final quiz = buildQuiz(study.allCards(), math.Random(1));
    expect(quiz.length, 4);
    for (final q in quiz) {
      expect(q.options.length, 4);
      expect(q.options.toSet().length, 4);
      expect(q.options[q.correct], q.card.back);
    }
  });

  test('Wissensnetz: verbundene liegen näher als unverbundene', () {
    final pos = layoutGraph(['a', 'b', 'c', 'd'], [('a', 'b'), ('c', 'd')]);
    double d(String x, String y) => (pos[x]! - pos[y]!).distance;
    expect(d('a', 'b'), lessThan(d('a', 'c')));
    expect(d('c', 'd'), lessThan(d('b', 'd')));
    expect(layoutGraph(['x'], const []).length, 1);
  });

  test('Suche zeigt einen Ausschnitt', () {
    expect(snippetOf('Das OSI-Modell hat sieben Schichten', 'osi'),
        contains('OSI'));
    final long = '${'x' * 60} Treffer ${'y' * 80}';
    final s = snippetOf(long, 'treffer');
    expect(s.startsWith('…'), isTrue);
    expect(s.endsWith('…'), isTrue);
  });

  test('Neue Vorlagen haben Namen', () {
    expect(PageTemplate.music.label, 'Notenlinien');
    expect(PageTemplate.values.length, 11);
  });
}
