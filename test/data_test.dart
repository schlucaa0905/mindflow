import 'package:flutter_test/flutter_test.dart';
import 'package:mindflow/data/canvas_repository.dart';
import 'package:mindflow/data/database.dart';
import 'package:mindflow/data/models.dart';
import 'package:mindflow/data/object_repository.dart';

void main() {
  late AppDatabase db;
  late ObjectRepository objects;
  late CanvasRepository canvas;

  setUp(() {
    db = AppDatabase.inMemory();
    objects = ObjectRepository(db.raw);
    canvas = CanvasRepository(db.raw);
  });

  tearDown(() => db.dispose());

  group('Objekte', () {
    test('Umbenennen ändert nie die ID', () {
      final nb = objects.create(type: ObjectType.notebook, title: 'Netzwerk');
      objects.rename(nb.id, 'Netzwerktechnik');
      final again = objects.get(nb.id)!;
      expect(again.id, nb.id);
      expect(again.title, 'Netzwerktechnik');
    });

    test('Seiten bleiben in Reihenfolge, Einfügen dazwischen klappt', () {
      final nb = objects.create(type: ObjectType.notebook);
      final p1 = objects.create(type: ObjectType.page, parentId: nb.id);
      final p3 = objects.create(type: ObjectType.page, parentId: nb.id);
      final p2 = objects.create(
          type: ObjectType.page,
          parentId: nb.id,
          position: objects.positionAfter(p1));
      expect(objects.children(nb.id).map((p) => p.id), [p1.id, p2.id, p3.id]);

      objects.swapPositions(objects.get(p1.id)!, objects.get(p2.id)!);
      expect(objects.children(nb.id).map((p) => p.id), [p2.id, p1.id, p3.id]);
    });

    test('Papierkorb und Wiederherstellen', () {
      final nb = objects.create(type: ObjectType.notebook, title: 'A');
      objects.trash(nb.id);
      expect(objects.byType(ObjectType.notebook), isEmpty);
      expect(objects.trashed().map((o) => o.id), [nb.id]);
      objects.restore(nb.id);
      expect(objects.byType(ObjectType.notebook).map((o) => o.id), [nb.id]);
    });

    test('Archivieren blendet aus, Suche findet trotzdem', () {
      final nb = objects.create(type: ObjectType.notebook, title: 'DHCP Notizen');
      objects.setArchived(nb.id, true);
      expect(objects.byType(ObjectType.notebook), isEmpty);
      expect(objects.archivedItems().length, 1);
      expect(objects.search('dhcp').map((o) => o.id), [nb.id]);
    });

    test('Suche behandelt Sonderzeichen korrekt', () {
      objects.create(type: ObjectType.board, title: '100% sicher');
      objects.create(type: ObjectType.board, title: '100 Gründe');
      expect(objects.search('100%').length, 1);
    });

    test('Verknüpfungen in beide Richtungen', () {
      final a = objects.create(type: ObjectType.notebook, title: 'DHCP');
      final b = objects.create(type: ObjectType.board, title: 'TCP/IP');
      objects.link(a.id, b.id);
      expect(objects.linkedIds(a.id), [b.id]);
      expect(objects.linkedIds(b.id), [a.id]);
    });

    test('Papier und Vorlage werden gespeichert', () {
      final nb = objects.create(
          type: ObjectType.notebook,
          data: {'paper': 'light', 'template': 'grid'});
      final o = objects.get(nb.id)!;
      expect(o.paper.name, 'light');
      expect(o.template, PageTemplate.grid);
    });
  });

  group('Canvas', () {
    test('Karten und Verbindungen bleiben gespeichert', () {
      final board = objects.create(type: ObjectType.board);
      final a = canvas.createNode(board.id, x: 0, y: 0, text: 'DHCP');
      final b = canvas.createNode(board.id, x: 300, y: 0, text: 'TCP/IP');
      expect(canvas.createEdge(board.id, a.id, b.id), isNotNull);
      // Doppelt (auch rückwärts) gibt es nicht.
      expect(canvas.createEdge(board.id, b.id, a.id), isNull);

      a.x = 50;
      canvas.updateNode(a);
      final nodes = canvas.nodes(board.id);
      expect(nodes.firstWhere((n) => n.id == a.id).x, 50);
      expect(canvas.edges(board.id).length, 1);
    });

    test('Karte löschen entfernt auch ihre Verbindungen', () {
      final board = objects.create(type: ObjectType.board);
      final a = canvas.createNode(board.id, x: 0, y: 0);
      final b = canvas.createNode(board.id, x: 300, y: 0);
      canvas.createEdge(board.id, a.id, b.id);
      canvas.deleteNode(a.id);
      expect(canvas.nodes(board.id).map((n) => n.id), [b.id]);
      expect(canvas.edges(board.id), isEmpty);
    });

    test('Kartentext ist durchsuchbar', () {
      final board = objects.create(type: ObjectType.board);
      canvas.createNode(board.id, x: 0, y: 0, text: 'Router vergibt IPs');
      expect(canvas.searchNodes('router').length, 1);
    });
  });
}
