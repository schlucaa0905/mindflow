import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:mindflow/ink/camera.dart';
import 'package:mindflow/ink/ink_codec.dart';
import 'package:mindflow/ink/ink_controller.dart';
import 'package:mindflow/ink/ink_scene.dart';
import 'package:mindflow/ink/shape_recognizer.dart';
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
    InkController withLine({ToolSettings? settings}) {
      final c = InkController(stylusOnly: true, settings: settings);
      c.beginStroke(Offset.zero, 0.5);
      for (var x = 2.0; x <= 100; x += 2) {
        c.extendStroke(Offset(x, 0), 0.5);
      }
      c.commitStroke();
      return c;
    }

    List<Stroke> alive(InkController c) =>
        c.scene.strokes.where((s) => !s.deleted).toList();

    test('Bereichsradierer teilt einen Strich in zwei Teile', () {
      final c = withLine()..eraserMode = EraserMode.area;
      c.eraseAt(const Offset(50, 0), 5);
      c.endErase();
      final pieces = alive(c);
      expect(pieces.length, 2);
      // Rückgängig stellt den Originalstrich wieder her.
      c.undo();
      final restored = alive(c);
      expect(restored.length, 1);
      expect(restored.single.points.length,
          greaterThan(pieces.first.points.length));
    });

    test('Radierer "nur Textmarker" lässt Schrift stehen', () {
      final c = withLine();
      c.settings.eraseHighlighterOnly = true;
      c.eraseAt(const Offset(50, 0), 5);
      c.endErase();
      expect(alive(c).length, 1);
    });

    test('Radierer springt auf Wunsch zum vorigen Werkzeug zurück', () {
      final c = withLine();
      c.settings.eraserAutoReturn = true;
      c.setTool(ToolMode.highlighter);
      c.setTool(ToolMode.eraser);
      c.eraseAt(const Offset(50, 0), 5);
      c.endErase();
      expect(c.tool, ToolMode.highlighter);
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
      expect(alive(c).single.bounds.top, closeTo(before.top + 200, 0.01));

      c.undo();
      expect(alive(c).single.bounds.top, closeTo(before.top, 0.01));
    });

    test('Lasso: ein kleiner Teil des Strichs genügt (wie Goodnotes 6)', () {
      final c = withLine()..setTool(ToolMode.lasso);
      // Lasso umschließt nur den Anfang (x 0..10) der 100 langen Linie.
      c.beginLasso(const Offset(-5, -5));
      c.extendLasso(const Offset(10, -5));
      c.extendLasso(const Offset(10, 5));
      c.extendLasso(const Offset(-5, 5));
      c.endLasso();
      expect(c.selection.length, 1);
    });

    test('Lasso: Strich, der die Lasso-Linie nur kreuzt, wird gewählt', () {
      final c = withLine()..setTool(ToolMode.lasso);
      // Sehr schmales Dreieck, das die Linie bei x=50 durchschneidet,
      // ohne dass ein Linienpunkt innen liegt.
      c.beginLasso(const Offset(50.5, -30));
      c.extendLasso(const Offset(50.9, -30));
      c.extendLasso(const Offset(50.7, 30));
      c.endLasso();
      expect(c.selection.length, 1);
    });

    test('Lasso: weit entfernte Striche bleiben unberührt', () {
      final c = withLine()..setTool(ToolMode.lasso);
      c.beginLasso(const Offset(0, 100));
      c.extendLasso(const Offset(50, 100));
      c.extendLasso(const Offset(50, 150));
      c.endLasso();
      expect(c.selection, isEmpty);
    });

    test('Nur auf dem Blatt schreiben', () {
      final c = InkController(stylusOnly: true)
        ..drawBounds = const Rect.fromLTWH(0, 0, 100, 100);
      expect(c.canDrawAt(const Offset(50, 50)), isTrue);
      expect(c.canDrawAt(const Offset(150, 50)), isFalse);
      c.beginStroke(const Offset(90, 50), 0.5);
      for (var x = 92.0; x < 200; x += 2) {
        c.extendStroke(Offset(x, 50), 0.5);
      }
      c.commitStroke();
      final s = c.scene.strokes.single;
      for (var i = 0; i < s.points.length; i += 3) {
        expect(s.points[i], lessThanOrEqualTo(100));
      }
    });

    test('Lasso skaliert um die linke obere Ecke', () {
      final c = withLine()..setTool(ToolMode.lasso);
      c.selection = alive(c);
      final b = c.selectionBounds!;
      c.beginScaleSelection(b.bottomRight);
      c.moveSelection(b.topLeft + (b.bottomRight - b.topLeft) * 2);
      c.endMoveSelection();
      final scaled = alive(c).single;
      expect(scaled.bounds.width, greaterThan(b.width * 1.8));
      expect(scaled.width, closeTo(c.selection.single.width, 1e-9));
    });

    test('Kopieren und Einfügen erzeugt neue Striche mit neuen IDs', () {
      final c = withLine()..setTool(ToolMode.lasso);
      c.selection = alive(c);
      c.copySelection();
      final other = InkController(stylusOnly: true);
      other.paste();
      expect(other.scene.aliveCount, 1);
      expect(other.scene.strokes.single.id,
          isNot(c.scene.strokes.single.id));
      InkController.clipboard = const [];
    });

    test('Umfärben und Duplizieren', () {
      final c = withLine()..setTool(ToolMode.lasso);
      c.selection = alive(c);
      c.recolorSelection(const Color(0xFFFF0000));
      expect(alive(c).single.color, 0xFFFF0000);
      c.duplicateSelection();
      expect(c.scene.aliveCount, 2);
    });

    test('Formen-Werkzeug: Rechteck, Ellipse, Pfeil', () {
      Rect boundsOf(List<double> pts) =>
          Stroke.computeBounds(Float32List.fromList(pts), 0).deflate(1);
      final rect = InkController.shapePoints(
          ShapeKind.rectangle, Offset.zero, const Offset(10, 20), 1);
      expect(boundsOf(rect), const Rect.fromLTWH(0, 0, 10, 20));
      expect(rect.sublist(0, 2), rect.sublist(rect.length - 3, rect.length - 1));
      final ellipse = InkController.shapePoints(
          ShapeKind.ellipse, Offset.zero, const Offset(10, 20), 1);
      expect(ellipse.length, 73 * 3);
      final arrow = InkController.shapePoints(
          ShapeKind.arrow, Offset.zero, const Offset(100, 0), 1);
      expect(arrow.length, greaterThanOrEqualTo(5 * 3));
    });

    test('Textmarker "gerade Linien" macht aus Zickzack eine Gerade', () {
      final c = InkController(stylusOnly: true)..setTool(ToolMode.highlighter);
      c.settings.highlighterStraight = true;
      c.beginStroke(Offset.zero, 0.5);
      for (var x = 4.0; x <= 100; x += 4) {
        c.extendStroke(Offset(x, x % 8 == 0 ? 5 : -5), 0.5);
      }
      c.commitStroke();
      expect(alive(c).single.pointCount, 2);
    });

    test('Kugelschreiber- und Pinsel-Striche überleben Speichern und Laden',
        () {
      for (final type in [PenType.ballpoint, PenType.brush]) {
        final c = InkController(stylusOnly: true)..setPenType(type);
        c.beginStroke(Offset.zero, 0.5);
        c.extendStroke(const Offset(40, 0), 0.5);
        c.commitStroke();
        final out = decodeInk(encodeInk(c.scene.strokes.toList()));
        expect(out.single.tool,
            type == PenType.ballpoint ? InkTool.ballpoint : InkTool.brush);
      }
    });

    test('Laser wird nie gespeichert', () {
      final c = InkController(stylusOnly: true)..setTool(ToolMode.laser);
      c.beginLaser(Offset.zero);
      c.extendLaser(const Offset(50, 50));
      expect(c.laserPath.value.length, 2);
      expect(c.scene.strokes, isEmpty);
    });

    test('Lieblingsstifte speichern und anwenden', () {
      final c = InkController(stylusOnly: true);
      c.setPenType(PenType.brush);
      c.setWidth(6);
      c.saveCurrentAsPreset();
      c.setPenType(PenType.ballpoint);
      c.setWidth(1);
      c.applyPreset(c.settings.presets.single);
      expect(c.penType, PenType.brush);
      expect(c.penWidth, 6);
      expect(c.isActivePreset(c.settings.presets.single), isTrue);
    });

    test('Einstellungen überleben Speichern und Laden', () {
      final s = ToolSettings()
        ..penType = PenType.brush
        ..penWidth = 3.5
        ..dock = ToolbarDock.left
        ..collapsed = true
        ..presets = [
          const PenPreset(type: PenType.ballpoint, color: 0xFF112233, width: 2)
        ];
      final again = ToolSettings.fromJson(s.toJson());
      expect(again.penType, PenType.brush);
      expect(again.penWidth, 3.5);
      expect(again.dock, ToolbarDock.left);
      expect(again.collapsed, isTrue);
      expect(again.presets.single.color, 0xFF112233);
      // Kaputte Daten führen nicht zum Absturz.
      final broken = ToolSettings.fromJson({'penWidth': 'x', 'dock': 42});
      expect(broken.penWidth, 2.5);
      expect(broken.dock, ToolbarDock.top);
    });
  });

  group('Formerkennung', () {
    List<double> pts(List<Offset> o) => [
          for (final p in o) ...[p.dx, p.dy, 0.5]
        ];

    test('Kreis wird erkannt', () {
      final circle = [
        for (var i = 0; i <= 60; i++)
          Offset(100 + 50 * math.cos(i / 60 * math.pi * 2),
              100 + 50 * math.sin(i / 60 * math.pi * 2))
      ];
      final r = recognizeShape(pts(circle));
      expect(r, isNotNull);
      expect(r!.length, 73 * 3);
    });

    test('Wackeliges Quadrat wird zum Rechteck', () {
      final sq = <Offset>[];
      void edge(Offset a, Offset b) {
        for (var i = 0; i < 20; i++) {
          final p = Offset.lerp(a, b, i / 20)!;
          sq.add(p + Offset(i.isEven ? 1 : -1, i.isEven ? -1 : 1));
        }
      }
      edge(const Offset(0, 0), const Offset(100, 0));
      edge(const Offset(100, 0), const Offset(100, 100));
      edge(const Offset(100, 100), const Offset(0, 100));
      edge(const Offset(0, 100), const Offset(0, 2));
      final r = recognizeShape(pts(sq));
      expect(r, isNotNull);
      final b = Stroke.computeBounds(Float32List.fromList(r!), 0).deflate(1);
      expect(b.width, closeTo(b.height, 4));
    });

    test('Gerader Strich wird zur Linie', () {
      final line = [for (var i = 0; i <= 30; i++) Offset(i * 5.0, i.isEven ? 1 : -1)];
      final r = recognizeShape(pts(line));
      expect(r, isNotNull);
      expect(r!.sublist(0, 2), [0, 1]);
    });

    test('Gekritzel bleibt Gekritzel', () {
      final scribble = [
        for (var i = 0; i < 80; i++)
          Offset(50 + 40 * math.cos(i * 2.7), 50 + 40 * math.sin(i * 1.9))
      ];
      expect(recognizeShape(pts(scribble)), isNull);
    });
  });
}
