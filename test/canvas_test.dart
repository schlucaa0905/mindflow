import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mindflow/app/theme.dart';
import 'package:mindflow/data/canvas_repository.dart';
import 'package:mindflow/data/database.dart';
import 'package:mindflow/data/models.dart';
import 'package:mindflow/data/object_repository.dart';
import 'package:mindflow/data/text_repository.dart';
import 'package:mindflow/features/canvas/card_view.dart';
import 'package:mindflow/features/canvas/edge_painter.dart';
import 'package:mindflow/ink/camera.dart';
import 'package:mindflow/ink/list_formatter.dart';
import 'package:mindflow/ui/editor_bar.dart';

void main() {
  group('Canvas-Daten (Version 3)', () {
    late AppDatabase db;
    late ObjectRepository objects;
    late CanvasRepository canvas;
    late String board;

    setUp(() {
      db = AppDatabase.inMemory();
      objects = ObjectRepository(db.raw);
      canvas = CanvasRepository(db.raw);
      board = objects.create(type: ObjectType.board, title: 'Mindmap').id;
    });
    tearDown(() => db.dispose());

    test('Kartengestaltung wird gespeichert und geladen', () {
      final n = canvas.createNode(board,
          x: 10, y: 20, text: 'DHCP', color: 0xFF22C55E,
          data: {'kind': 'sticky'});
      n.textSize = CardTextSize.large;
      n.bold = true;
      n.centered = true;
      n.fixedHeight = true;
      n.z = 3;
      canvas.updateNode(n);
      final again = canvas.nodes(board).single;
      expect(again.kind, CardKind.sticky);
      expect(again.textSize, CardTextSize.large);
      expect(again.bold, isTrue);
      expect(again.centered, isTrue);
      expect(again.fixedHeight, isTrue);
      expect(again.z, 3);
      expect(again.color, 0xFF22C55E);
    });

    test('Standardwerte: Kapsel und Kreis zentriert, Überschrift groß', () {
      final n = canvas.createNode(board, x: 0, y: 0);
      expect(n.kind, CardKind.card);
      expect(n.centered, isFalse);
      n.kind = CardKind.circle;
      expect(n.centered, isTrue);
      n.kind = CardKind.heading;
      expect(n.textSize, CardTextSize.huge);
    });

    test('Karten werden nach Ebene sortiert', () {
      final a = canvas.createNode(board, x: 0, y: 0, text: 'a');
      canvas.createNode(board, x: 0, y: 0, text: 'b');
      a.z = 10;
      canvas.updateNode(a);
      expect(canvas.nodes(board).map((n) => n.text), ['b', 'a']);
    });

    test('Verbindung: Pfeil, gestrichelt, Farbe und Text bleiben', () {
      final a = canvas.createNode(board, x: 0, y: 0);
      final b = canvas.createNode(board, x: 300, y: 0);
      final e = canvas.createEdge(board, a.id, b.id,
          data: {'arrow': 'end'})!;
      e.dashed = true;
      e.color = 0xFFEF4444;
      e.label = 'führt zu';
      canvas.updateEdge(e);
      final again = canvas.edges(board).single;
      expect(again.arrow, EdgeArrow.end);
      expect(again.dashed, isTrue);
      expect(again.color, 0xFFEF4444);
      expect(again.label, 'führt zu');
      again.color = null;
      expect(again.data.containsKey('color'), isFalse);
    });

    test('Rückgängig: früherer Stand kommt vollständig zurück', () {
      final a = canvas.createNode(board, x: 0, y: 0, text: 'A');
      final b = canvas.createNode(board, x: 300, y: 0, text: 'B');
      canvas.createEdge(board, a.id, b.id);
      final before = (
        nodes: [for (final n in canvas.nodes(board)) n.copy()],
        edges: [for (final e in canvas.edges(board)) e.copy()],
      );
      // Änderungen: verschieben, löschen, neue Karte
      a.x = 999;
      canvas.updateNode(a);
      canvas.deleteNode(b.id);
      canvas.createNode(board, x: 5, y: 5, text: 'neu');
      expect(canvas.nodes(board).length, 2);
      expect(canvas.edges(board), isEmpty);

      canvas.restoreState(board, before.nodes, before.edges);
      final nodes = canvas.nodes(board);
      expect(nodes.map((n) => n.text).toSet(), {'A', 'B'});
      expect(nodes.firstWhere((n) => n.text == 'A').x, 0);
      expect(canvas.edges(board).length, 1);
    });

    test('Kopierte Karte bekommt neue ID', () {
      final a = canvas.createNode(board, x: 0, y: 0, text: 'A');
      final copy = a.copy(id: canvas.newId(), dx: 30, dy: 30);
      canvas.insertNode(copy);
      final nodes = canvas.nodes(board);
      expect(nodes.length, 2);
      final other = nodes.firstWhere((n) => n.id != a.id);
      expect(other.id, copy.id);
      expect(other.x, 30);
      expect(other.text, 'A');
    });

    test('Datenbank ist auf Version 3', () {
      expect(db.raw.userVersion, 3);
    });
  });

  group('Aufgaben auf Karten', () {
    test('erkennen, abhaken, umwandeln', () {
      const text = 'Einkaufen\n[ ] Milch\n[x] Brot';
      final lines = CardLine.parse(text);
      expect(lines[0].task, isFalse);
      expect(lines[1].task, isTrue);
      expect(lines[1].done, isFalse);
      expect(lines[2].done, isTrue);
      expect(lines[2].text, 'Brot');
      expect(CardLine.toggle(text, 1), 'Einkaufen\n[x] Milch\n[x] Brot');
      expect(CardLine.toggle(text, 2), 'Einkaufen\n[ ] Milch\n[ ] Brot');
      expect(CardLine.toggle(text, 0), text);
      expect(CardLine.toggleAll('A\n\nB'), '[ ] A\n\n[ ] B');
      expect(CardLine.toggleAll('[ ] A\n[x] B'), 'A\nB');
      expect(CardLine.hasTasks('nur Text'), isFalse);
    });
  });

  group('Verbindungslinien', () {
    test('docken seitlich bzw. oben/unten an', () {
      const a = Rect.fromLTWH(0, 0, 100, 50);
      const right = Rect.fromLTWH(300, 0, 100, 50);
      final g = EdgeGeometry.between(a, right);
      expect(g.p0, a.centerRight);
      expect(g.p1, right.centerLeft);
      const below = Rect.fromLTWH(0, 300, 100, 50);
      final v = EdgeGeometry.between(a, below);
      expect(v.p0, a.bottomCenter);
      expect(v.p1, below.topCenter);
      expect(g.distanceTo(g.middle), lessThan(0.5));
      expect(g.distanceTo(const Offset(200, 400)), greaterThan(100));
    });

    test('Antippen findet die nächste Verbindung', () {
      final cam = Camera();
      final a = CanvasNode(
          id: 'a', boardId: 'b', x: 0, y: 0, w: 100, h: 50, text: '');
      final b = CanvasNode(
          id: 'b', boardId: 'b', x: 300, y: 0, w: 100, h: 50, text: '');
      final e = CanvasEdge(id: 'e', boardId: 'b', fromId: 'a', toId: 'b');
      final nodes = {'a': a, 'b': b};
      expect(hitEdge(const Offset(200, 25), cam, nodes, [e])?.id, 'e');
      expect(hitEdge(const Offset(200, 200), cam, nodes, [e]), isNull);
    });
  });

  group('Listen beim Tippen', () {
    TextEditingValue type(String before, String after) =>
        const ListContinuationFormatter().formatEditUpdate(
          TextEditingValue(
              text: before,
              selection: TextSelection.collapsed(offset: before.length)),
          TextEditingValue(
              text: after,
              selection: TextSelection.collapsed(offset: after.length)),
        );

    test('Aufzählung wird fortgesetzt', () {
      final v = type('• Milch', '• Milch\n');
      expect(v.text, '• Milch\n• ');
      expect(v.selection.baseOffset, v.text.length);
    });

    test('Nummerierung zählt weiter', () {
      expect(type('Liste\n3. Punkt', 'Liste\n3. Punkt\n').text,
          'Liste\n3. Punkt\n4. ');
    });

    test('Leerer Punkt beendet die Liste', () {
      final v = type('• A\n• ', '• A\n• \n');
      expect(v.text, '• A\n');
      expect(v.selection.baseOffset, 4);
    });

    test('Normaler Text bleibt unverändert', () {
      expect(type('Hallo', 'Hallo\n').text, 'Hallo\n');
      expect(type('', '\n').text, '\n');
    });

    test('Aufzählung ein- und ausschalten', () {
      expect(toggleBullets('A\nB'), '• A\n• B');
      expect(toggleBullets('• A\n• B'), 'A\nB');
      expect(toggleBullets(''), '• ');
    });
  });

  group('Textfeld-Gestaltung', () {
    test('Schrift, Ausrichtung und Hintergrund werden gespeichert', () {
      final db = AppDatabase.inMemory();
      addTearDown(db.dispose);
      final texts = TextRepository(db.raw);
      final t = texts.create(ownerId: 'p', x: 0, y: 0, w: 200, text: 'Hi')
        ..italic = true
        ..underline = true
        ..font = TextFont.serif
        ..align = TextAlign.center
        ..background = TextBackground.note;
      texts.update(t);
      final again = texts.items('p').single;
      expect(again.italic, isTrue);
      expect(again.underline, isTrue);
      expect(again.font, TextFont.serif);
      expect(again.align, TextAlign.center);
      expect(again.background, TextBackground.note);
      final copy = again.copy(id: 'x');
      expect(copy.font, TextFont.serif);
      expect(copy.background, TextBackground.note);
    });
  });

  testWidgets('Alle Kartenarten lassen sich zeichnen', (tester) async {
    for (final paper in [PaperStyle.dark, PaperStyle.light]) {
      for (final k in CardKind.values) {
        final n = CanvasNode(
            id: k.name,
            boardId: 'b',
            x: 0,
            y: 0,
            w: 220,
            h: 120,
            text: k == CardKind.card ? 'Titel\n[ ] Aufgabe\n[x] Fertig' : 'Text',
            color: k == CardKind.sticky ? 0xFFFACC15 : null,
            data: {'kind': k.name});
        n.h = measureCardHeight(n);
        expect(n.h, greaterThan(30));
        var toggled = -1;
        await tester.pumpWidget(MaterialApp(
          theme: buildTheme(Brightness.dark),
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: n.w,
                height: n.h,
                child: CanvasCardView(
                  node: n,
                  paper: paper,
                  selected: true,
                  onToggleTask: (i) => toggled = i,
                ),
              ),
            ),
          ),
        ));
        expect(tester.takeException(), isNull);
        if (k == CardKind.card) {
          await tester.tap(find.byIcon(Icons.radio_button_unchecked_rounded));
          expect(toggled, 1);
        }
      }
    }
  });

  testWidgets('Längerer Text macht die Karte höher', (tester) async {
    final n = CanvasNode(
        id: 'n', boardId: 'b', x: 0, y: 0, w: 200, h: 60, text: 'kurz');
    final short = measureCardHeight(n);
    n.text = List.filled(12, 'Eine ziemlich lange Zeile Text').join(' ');
    expect(measureCardHeight(n), greaterThan(short));
  });

  testWidgets('Zoom-Menü stellt 200 % ein', (tester) async {
    final cam = Camera()..setViewport(const Size(800, 600));
    var fitted = false;
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(Brightness.dark),
      home: Scaffold(
        body: Center(
          child: ZoomPill(camera: cam, onFit: () => fitted = true),
        ),
      ),
    ));
    expect(find.text('100 %'), findsOneWidget);
    await tester.tap(find.text('100 %'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('200 %'));
    await tester.pumpAndSettle();
    expect(cam.scale, closeTo(2, 1e-9));
    await tester.tap(find.text('200 %'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ganze Seite'));
    await tester.pumpAndSettle();
    expect(fitted, isTrue);
  });

  test('Tastatur-Hilfsklasse ist erreichbar', () {
    // Stellt sicher, dass die Formatierer-Klasse ein TextInputFormatter ist.
    expect(const ListContinuationFormatter(), isA<TextInputFormatter>());
  });
}
