import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:mindflow/ink/camera.dart';
import 'package:mindflow/ink/ink_codec.dart';
import 'package:mindflow/ink/ink_controller.dart';
import 'package:mindflow/ink/ink_scene.dart';
import 'package:mindflow/ink/stroke.dart';
import 'package:mindflow/spike/stress_generator.dart';

Stroke line(String id, double y, {bool deleted = false}) => Stroke(
      id: id,
      color: 0xFFEDEDF2,
      width: 2,
      tool: InkTool.pen,
      points: Float32List.fromList([0, y, 0.5, 50, y, 0.6, 100, y, 0.7]),
      deleted: deleted,
    );

void main() {
  group('Speicherformat', () {
    test('Hin- und Rückweg verliert nichts', () {
      final input = [
        line('a', 0),
        line('ä-ü-ß', 10, deleted: true),
        ...generateHandwriting(count: 50),
      ];
      final out = decodeInk(encodeInk(input));
      expect(out.length, input.length);
      for (var i = 0; i < input.length; i++) {
        expect(out[i].id, input[i].id);
        expect(out[i].color, input[i].color);
        expect(out[i].tool, input[i].tool);
        expect(out[i].deleted, input[i].deleted);
        expect(out[i].points, input[i].points);
      }
    });

    test('Fremde Datei wird erkannt', () {
      expect(() => decodeInk(Uint8List.fromList(List.filled(20, 7))),
          throwsFormatException);
    });

    test('Abgeschnittene Datei wird erkannt', () {
      final bytes = encodeInk([line('a', 0), line('b', 5)]);
      expect(() => decodeInk(Uint8List.sublistView(bytes, 0, bytes.length - 5)),
          throwsFormatException);
    });
  });

  group('Szene', () {
    test('Radierer trifft nur berührte Striche', () {
      final scene = InkScene()..addAll([line('a', 0), line('b', 100)]);
      final hits = scene.hitTest(const Offset(50, 1), 3);
      expect(hits.map((s) => s.id), ['a']);
    });

    test('Gelöschte Striche bleiben als Grabstein erhalten', () {
      final scene = InkScene()..add(line('a', 0));
      scene.setDeleted([scene.byId('a')!], true);
      expect(scene.aliveCount, 0);
      expect(scene.strokes.length, 1);
      expect(scene.hitTest(const Offset(50, 0), 3), isEmpty);
    });

    test('Doppelte IDs werden nicht doppelt eingefügt', () {
      final scene = InkScene()..add(line('a', 0));
      scene.add(line('a', 0));
      expect(scene.strokes.length, 1);
    });
  });

  group('Rückgängig', () {
    test('Zeichnen und Radieren lassen sich zurücknehmen', () {
      final c = InkController(stylusOnly: true);
      c.beginStroke(Offset.zero, 0.5);
      c.extendStroke(const Offset(30, 0), 0.5);
      c.extendStroke(const Offset(60, 0), 0.5);
      c.commitStroke();
      expect(c.scene.aliveCount, 1);

      c.eraseAt(const Offset(30, 0), 5);
      c.endErase();
      expect(c.scene.aliveCount, 0);

      c.undo();
      expect(c.scene.aliveCount, 1);
      c.undo();
      expect(c.scene.aliveCount, 0);
      c.redo();
      expect(c.scene.aliveCount, 1);
    });
  });

  group('Eingabemodus', () {
    test('Stift schaltet automatisch auf "Nur Stift"', () {
      final c = InkController(stylusOnly: false)..onStylusDetected();
      expect(c.stylusOnly, isTrue);
    });

    test('Eigene Wahl des Nutzers wird respektiert', () {
      final c = InkController(stylusOnly: true)..setStylusOnly(false);
      c.onStylusDetected();
      expect(c.stylusOnly, isFalse);
    });
  });

  group('Kamera', () {
    test('Zoom hält den Punkt unter den Fingern fest', () {
      final cam = Camera()..panBy(const Offset(40, -20));
      const focal = Offset(300, 200);
      final before = cam.toWorld(focal);
      cam.zoomAt(focal, 2.5);
      final after = cam.toWorld(focal);
      expect((before - after).distance, lessThan(1e-9));
    });

    test('Mit Grenzen: nicht weiter heraus als erlaubt, Seite bleibt im Bild',
        () {
      final cam = Camera()
        ..limit = const Rect.fromLTWH(0, 0, 595, 842)
        ..minZoom = 0.5
        ..maxZoom = 6
        ..setViewport(const Size(800, 1000));
      cam.zoomAt(const Offset(400, 500), 0.01);
      expect(cam.scale, 0.5);
      // Seite ist kleiner als das Fenster → bleibt mittig, egal wie man schiebt.
      cam.panBy(const Offset(5000, 5000));
      final center = cam.toScreen(const Offset(595 / 2, 842 / 2));
      expect((center - const Offset(400, 500)).distance, lessThan(1e-6));

      // Hineingezoomt: Seite kann nicht ganz aus dem Bild geschoben werden.
      cam.zoomAt(const Offset(400, 500), 6);
      cam.panBy(const Offset(-100000, 0));
      final rightEdge = cam.toScreen(const Offset(595, 0)).dx;
      expect(rightEdge, greaterThanOrEqualTo(800 - cam.limitMargin - 1e-6));
    });
  });

  group('Werkzeuge', () {
    InkController withLine() {
      final c = InkController(stylusOnly: true);
      c.beginStroke(Offset.zero, 0.5);
      for (var x = 2.0; x <= 100; x += 2) {
        c.extendStroke(Offset(x, 0), 0.5);
      }
      c.commitStroke();
      return c;
    }

    test('Bereichsradierer teilt einen Strich in zwei Teile', () {
      final c = withLine()..eraserMode = EraserMode.area;
      c.eraseAt(const Offset(50, 0), 5);
      c.endErase();
      final alive = c.scene.strokes.where((s) => !s.deleted).toList();
      expect(alive.length, 2);
      // Rückgängig stellt den Originalstrich wieder her.
      c.undo();
      final restored = c.scene.strokes.where((s) => !s.deleted).toList();
      expect(restored.length, 1);
      expect(restored.single.points.length, greaterThan(alive.first.points.length));
    });

    test('Lasso wählt aus, Verschieben ist rückgängig machbar', () {
      final c = withLine()..setTool(ToolMode.lasso);
      c.beginLasso(const Offset(-10, -10));
      c.extendLasso(const Offset(120, -10));
      c.extendLasso(const Offset(120, 10));
      c.extendLasso(const Offset(-10, 10));
      c.endLasso();
      expect(c.selection.length, 1);
      final before = c.selection.single.bounds;

      c.beginMoveSelection(const Offset(50, 0));
      c.moveSelection(const Offset(50, 200));
      c.endMoveSelection();
      final moved = c.scene.strokes.where((s) => !s.deleted).single;
      expect(moved.bounds.top, closeTo(before.top + 200, 0.01));

      c.undo();
      final back = c.scene.strokes.where((s) => !s.deleted).single;
      expect(back.bounds.top, closeTo(before.top, 0.01));
    });

    test('Umfärben und Duplizieren', () {
      final c = withLine()..setTool(ToolMode.lasso);
      c.selection = c.scene.strokes.where((s) => !s.deleted).toList();
      c.recolorSelection(const Color(0xFFFF0000));
      expect(c.scene.strokes.where((s) => !s.deleted).single.color, 0xFFFF0000);
      c.duplicateSelection();
      expect(c.scene.aliveCount, 2);
    });

    test('Formen erzeugen Punkte', () {
      final rect = InkController.shapePoints(
          ShapeKind.rectangle, Offset.zero, const Offset(10, 20), 1);
      expect(rect.length, 5 * 3);
      final ellipse = InkController.shapePoints(
          ShapeKind.ellipse, Offset.zero, const Offset(10, 20), 1);
      expect(ellipse.length, 73 * 3);
      final arrow = InkController.shapePoints(
          ShapeKind.arrow, Offset.zero, const Offset(100, 0), 1);
      expect(arrow.length, 5 * 3);
    });

    test('Kugelschreiber-Striche überleben Speichern und Laden', () {
      final c = InkController(stylusOnly: true)..setPenType(PenType.ballpoint);
      c.beginStroke(Offset.zero, 0.5);
      c.extendStroke(const Offset(40, 0), 0.5);
      c.commitStroke();
      final out = decodeInk(encodeInk(c.scene.strokes.toList()));
      expect(out.single.tool, InkTool.ballpoint);
    });
  });
}
