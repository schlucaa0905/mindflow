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

  group('Kamera', () {
    test('Zoom hält den Punkt unter den Fingern fest', () {
      final cam = Camera()..panBy(const Offset(40, -20));
      const focal = Offset(300, 200);
      final before = cam.toWorld(focal);
      cam.zoomAt(focal, 2.5);
      final after = cam.toWorld(focal);
      expect((before - after).distance, lessThan(1e-9));
    });
  });
}
