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
import 'package:mindflow/storage/ink_recolor.dart';
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
      // Hineinzoomen: Das Lasso übernimmt nur Punkte, die auf dem
      // Bildschirm mindestens 3 Punkte auseinanderliegen.
      c.camera.zoomAt(Offset.zero, 8);
      // Sehr schmales Dreieck, das die Linie bei x=50 durchschneidet,
      // ohne dass ein Linienpunkt innen liegen muss.
      c.beginLasso(const Offset(50.5, -30));
      c.extendLasso(const Offset(50.9, -30));
      c.extendLasso(const Offset(50.7, 30));
      c.endLasso();
      expect(c.selection.length, 1);
      // Und direkt geprüft: die Schnitt-Erkennung selbst.
      expect(
          InkController.segmentsIntersect(const Offset(0, 0),
              const Offset(100, 0), const Offset(50, -10), const Offset(50, 10)),
          isTrue);
      expect(
          InkController.segmentsIntersect(const Offset(0, 0),
              const Offset(100, 0), const Offset(50, 5), const Offset(50, 10)),
          isFalse);
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

    test('Einfügen an einer Stelle – und immer auf dem Blatt', () {
      final c = withLine()..setTool(ToolMode.lasso);
      c.selection = alive(c);
      c.copySelection();
      final other = InkController(stylusOnly: true)
        ..drawBounds = const Rect.fromLTWH(0, 0, 595, 842);
      other.paste(at: const Offset(300, 400));
      expect(other.selectionBounds!.center.dx, closeTo(300, 0.5));
      expect(other.selectionBounds!.center.dy, closeTo(400, 0.5));
      expect(other.tool, ToolMode.lasso);
      other.paste(at: const Offset(5000, 5000));
      final b = other.selectionBounds!;
      expect(b.right, lessThanOrEqualTo(595.5));
      expect(b.bottom, lessThanOrEqualTo(842.5));
      expect(other.scene.aliveCount, 2);
      InkController.clipboard = const [];
    });

    test('Formen wie Goodnotes: zeichnen, antippen, Ende ziehen, rückgängig',
        () {
      final c = InkController(stylusOnly: true)..setTool(ToolMode.shape);
      c.beginShape(Offset.zero);
      for (var x = 5.0; x <= 200; x += 5) {
        c.updateShape(Offset(x, x % 10 == 0 ? 1.5 : 0));
      }
      c.commitShape();
      final line = alive(c).single;
      expect(InkController.isLine(line), isTrue);

      // Antippen wählt die Linie aus.
      c.beginShape(const Offset(100, 0.5));
      c.commitShape();
      expect(c.editShape, isNotNull);
      final hs = InkController.shapeHandles(c.editShape!);
      expect(hs.length, 2);

      // Ende nach unten ziehen.
      c.beginShape(hs[1]);
      c.updateShape(const Offset(200, 100));
      c.commitShape();
      final moved = alive(c).single;
      final p = moved.points;
      expect(Offset(p[p.length - 3], p[p.length - 2]),
          offsetMoreOrLessEquals(const Offset(200, 100), epsilon: 0.01));
      expect(Offset(p[0], p[1]), offsetMoreOrLessEquals(hs[0], epsilon: 0.01));

      c.undo();
      expect(alive(c).single.id, line.id);
      expect(c.editShape, isNull);
    });

    test('Form mit dem Stift antippen: bearbeiten, danach zurück zum Stift',
        () {
      final c = InkController(stylusOnly: true)..setTool(ToolMode.shape);
      c.beginShape(Offset.zero);
      for (var x = 5.0; x <= 200; x += 5) {
        c.updateShape(Offset(x, 0));
      }
      c.commitShape();
      expect(alive(c).single.tool, InkTool.shape);
      c.setTool(ToolMode.pen);
      c.beginStroke(const Offset(0, 200), 0.5);
      for (var x = 2.0; x <= 60; x += 2) {
        c.extendStroke(Offset(x, 200), 0.5);
      }
      c.commitStroke();

      // Handschrift lässt sich nicht als Form greifen.
      expect(c.tryEditShapeAt(const Offset(30, 200)), isFalse);
      expect(c.tool, ToolMode.pen);

      expect(c.tryEditShapeAt(const Offset(100, 0)), isTrue);
      expect(c.tool, ToolMode.shape);
      expect(c.editShape, isNotNull);

      // Daneben tippen: fertig, Stift ist wieder da – ohne neue Form.
      c.beginShape(const Offset(100, 400));
      c.updateShape(const Offset(100, 400));
      c.commitShape();
      expect(c.editShape, isNull);
      expect(c.tool, ToolMode.pen);
      expect(alive(c).length, 2);
    });

    test('Formen: Eckgriff ändert die Größe, Verschieben bewegt alles', () {
      final c = InkController(stylusOnly: true);
      final rect = Stroke(
        id: 'r',
        color: 0xFF000000,
        width: 2,
        tool: InkTool.ballpoint,
        points: Float32List.fromList(InkController.shapePoints(
            ShapeKind.rectangle, Offset.zero, const Offset(100, 50), 1)),
      );
      final r = InkController.pointsRect(rect);
      final bigger = c.transformShape(
          rect, 4, r.bottomRight, r.bottomRight + const Offset(100, 50));
      final r2 = InkController.pointsRect(bigger);
      expect(r2.width, closeTo(r.width + 100, 1e-3));
      expect(r2.height, closeTo(r.height + 50, 1e-3));
      expect(r2.topLeft, offsetMoreOrLessEquals(r.topLeft, epsilon: 1e-3));
      final moved =
          c.transformShape(rect, -1, Offset.zero, const Offset(10, 20));
      expect(InkController.pointsRect(moved).topLeft,
          offsetMoreOrLessEquals(r.topLeft + const Offset(10, 20), epsilon: 1e-3));
    });

    test('Lineal: Striche an der Kante werden schnurgerade', () {
      final c = InkController(stylusOnly: true);
      c.toggleRuler();
      expect(c.ruler.value!.center, const Offset(300, 300));
      expect(c.onRuler(const Offset(300, 300)), isTrue);
      // Untere Kante liegt bei y = 300 + 36.
      c.beginStroke(const Offset(100, 340), 0.5);
      for (var x = 110.0; x <= 500; x += 10) {
        c.extendStroke(Offset(x, x % 20 == 0 ? 345 : 331), 0.5);
      }
      c.commitStroke();
      final p = alive(c).single.points;
      for (var i = 0; i < p.length; i += 3) {
        expect(p[i + 1], closeTo(336, 0.01));
      }
      // Weit weg vom Lineal: ganz normal.
      c.beginStroke(const Offset(100, 600), 0.5);
      c.extendStroke(const Offset(150, 650), 0.5);
      c.commitStroke();
      expect(alive(c).last.points[1], closeTo(600, 0.01));
      // Drehen und ausblenden.
      c.moveRuler(const Offset(10, 0), math.pi / 2);
      expect(c.ruler.value!.angle, closeTo(math.pi / 2, 1e-9));
      c.toggleRuler();
      expect(c.ruler.value, isNull);
    });

    test('Strichstärke auf dem Blatt hängt nicht vom Zoom ab', () {
      final c = InkController(stylusOnly: true);
      void line(double y) {
        c.beginStroke(Offset(0, y), 0.5);
        for (var x = 2.0; x <= 60; x += 2) {
          c.extendStroke(Offset(x, y), 0.5);
        }
        c.commitStroke();
      }

      line(0);
      c.camera.zoomAt(Offset.zero, 3);
      line(40);
      final widths = alive(c).map((s) => s.width).toList();
      expect(widths.length, 2);
      expect(widths[0], closeTo(widths[1], 1e-9));
      expect(widths[0], closeTo(c.penWidth, 1e-9));
    });

    test('Text-Werkzeug und Schriftgröße werden gespeichert', () {
      final s = ToolSettings()
        ..tool = ToolMode.text
        ..textSize = 26;
      final again = ToolSettings.fromJson(s.toJson());
      expect(again.tool, ToolMode.text);
      expect(again.textSize, 26);
      final c = InkController(stylusOnly: true)..setTool(ToolMode.text);
      c.setColor(const Color(0xFF22D3EE));
      expect(c.tool, ToolMode.text, reason: 'Farbe wählen bleibt beim Text');
      c.setTextSize(500);
      expect(c.textSize, 96);
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

  group('Goodnotes-Verhalten', () {
    test('Textmarker: Halten macht eine gerade Linie, Ende folgt dem Stift',
        () {
      final c = InkController(stylusOnly: true)..setTool(ToolMode.highlighter);
      c.beginStroke(Offset.zero, 0.5);
      for (var x = 4.0; x <= 100; x += 4) {
        c.extendStroke(Offset(x, x % 8 == 0 ? 6 : -6), 0.5);
      }
      expect(c.recognizeHeldStroke(), isTrue);
      c.extendStroke(const Offset(200, 10), 0.5);
      expect(c.live.points.length, 6);
      c.commitStroke();
      final s = c.scene.strokes.single;
      expect(s.pointCount, 2);
      expect(s.points[3], 200);
      expect(s.points[4], 10);
      expect(s.tool, InkTool.highlighter);
    });

    test('Erkannte Form bekommt keinen alten Punkt angehängt', () {
      final c = InkController(stylusOnly: true);
      c.beginStroke(Offset.zero, 0.5);
      for (var x = 2.0; x <= 120; x += 2) {
        c.extendStroke(Offset(x, 0), 0.5);
      }
      expect(c.recognizeHeldStroke(), isTrue);
      c.commitStroke();
      final s = c.scene.strokes.single;
      final first = Offset(s.points[0], s.points[1]);
      final last =
          Offset(s.points[s.points.length - 3], s.points[s.points.length - 2]);
      final d = (last - first).distance;
      expect(s.pointCount, (d / 6).floor() + 1);
      for (var i = 1; i < s.points.length; i += 3) {
        expect(s.points[i], 0);
      }
    });

    test('Breiten-Plätze frei einstellbar und gespeichert', () {
      final c = InkController(stylusOnly: true);
      c.setWidthSlot(1, 7);
      expect(c.widthSlots[1], 7);
      expect(c.penWidth, 7);
      c.setTool(ToolMode.highlighter);
      c.setWidthSlot(2, 30);
      expect(c.highlighterWidth, 30);
      final again = ToolSettings.fromJson(c.settings.toJson());
      expect(again.penWidths[1], 7);
      expect(again.highlighterWidths[2], 30);
    });

    test('Schriftfarben passen sich ans Papier an', () {
      // Weiß auf dunklem Papier → Schwarz auf hellem Papier.
      expect(mapInkColor(0xFFEDEDF2, toDark: false), 0xFF1C1C22);
      expect(mapInkColor(0xFF1C1C22, toDark: true), 0xFFEDEDF2);
      // Violett bleibt Violett (passender Ton).
      expect(mapInkColor(0xFF8B7CF6, toDark: false), 0xFF6D5DE7);
      // Eigene, mittlere Farbe bleibt unverändert.
      expect(mapInkColor(0xFF2E8B57, toDark: false), isNull);
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

  group('0.9.3: Winkel, Radierer, Favoriten, Pipette, Drehen, Glätten', () {
    List<Stroke> alive(InkController c) =>
        c.scene.strokes.where((s) => !s.deleted).toList();

    Stroke lineStroke(Offset a, Offset b) => Stroke(
          id: 'l',
          color: 0xFF000000,
          width: 2,
          tool: InkTool.shape,
          points: Float32List.fromList(polyPoints([a, b])),
        );

    Offset endOf(Stroke s) => Offset(
        s.points[s.points.length - 3], s.points[s.points.length - 2]);

    Offset at(double deg, double len) => Offset(
        math.cos(deg * math.pi / 180), -math.sin(deg * math.pi / 180)) *
        len;

    test('Linienende rastet nur ganz nah an geraden Winkeln ein', () {
      final c = InkController(stylusOnly: true);
      final l = lineStroke(Offset.zero, const Offset(200, 0));
      double angleAfter(double deg) {
        final t = c.transformShape(l, 9, const Offset(200, 0), at(deg, 200));
        return InkController.lineAngle(t);
      }

      expect(angleAfter(1.5), closeTo(0, 1e-3));
      expect(c.snapped, isTrue);
      expect(angleAfter(88.5), closeTo(90, 1e-3));
      expect(angleAfter(43.5), closeTo(45, 1e-3));
      expect(angleAfter(181.9), closeTo(180, 1e-3));
      expect(angleAfter(358.5), closeTo(0, 1e-3));
      // Weiter weg bleibt der Winkel, wie er ist – 40° springt nicht auf 45°.
      expect(angleAfter(40), closeTo(40, 1e-3));
      expect(c.snapped, isFalse);
      expect(angleAfter(87), closeTo(87, 1e-3));
      expect(angleAfter(47.5), closeTo(47.5, 1e-3));
      // Nur 90°: 45° rastet nicht mehr ein. Aus: gar nichts.
      c.settings.angleSnap = AngleSnap.right;
      expect(angleAfter(44), closeTo(44, 1e-3));
      expect(angleAfter(91), closeTo(90, 1e-3));
      c.settings.angleSnap = AngleSnap.off;
      expect(angleAfter(89), closeTo(89, 1e-3));
      // Länge bleibt beim Einrasten gleich.
      c.settings.angleSnap = AngleSnap.half;
      final t = c.transformShape(l, 9, const Offset(200, 0), at(1, 150));
      expect(InkController.lineLength(t), closeTo(150, 1e-3));
    });

    test('Genauer Winkel per Knopf: 89° bleibt 89°, rückgängig machbar', () {
      final c = InkController(stylusOnly: true)..setTool(ToolMode.shape);
      final l = lineStroke(Offset.zero, const Offset(200, 0));
      c.scene.add(l);
      expect(c.tryEditShapeAt(const Offset(100, 0)), isTrue);
      c.setLineAngle(89);
      final now = alive(c).single;
      expect(InkController.lineAngle(now), closeTo(89, 1e-3));
      expect(InkController.lineLength(now), closeTo(200, 1e-3));
      // Mitte bleibt, wo sie war.
      final mid = (Offset(now.points[0], now.points[1]) + endOf(now)) / 2;
      expect(mid, offsetMoreOrLessEquals(const Offset(100, 0), epsilon: 1e-3));
      // Halten = Vorschau, erst Loslassen übernimmt (ein Schritt).
      c.setLineAngle(90, preview: true);
      c.setLineAngle(91, preview: true);
      expect(InkController.lineAngle(c.editLine!), closeTo(91, 1e-3));
      expect(alive(c), isEmpty, reason: 'Original während der Vorschau aus');
      c.setLineAngle(91);
      expect(InkController.lineAngle(alive(c).single), closeTo(91, 1e-3));
      c.undo();
      expect(InkController.lineAngle(alive(c).single), closeTo(89, 1e-3));
      c.undo();
      expect(alive(c).single.id, 'l');
    });

    test('Werkzeugwechsel mitten in der Vorschau verliert die Linie nicht', () {
      final c = InkController(stylusOnly: true)..setTool(ToolMode.shape);
      c.scene.add(lineStroke(Offset.zero, const Offset(200, 0)));
      c.tryEditShapeAt(const Offset(100, 0));
      c.setLineAngle(30, preview: true);
      c.setTool(ToolMode.pen);
      expect(alive(c).single.id, 'l');
      expect(c.shapePreview.value, isNull);
    });

    test('Gezeichnete und gehaltene Linien rasten ein', () {
      final c = InkController(stylusOnly: true)..setTool(ToolMode.shape);
      c.beginShape(Offset.zero);
      for (var x = 5.0; x <= 200; x += 5) {
        c.updateShape(Offset(x, x * 0.025)); // ca. 1,4° schräg
      }
      c.commitShape();
      expect(InkController.lineAngle(alive(c).single), closeTo(0, 1e-3));

      // Textmarker halten: Ende folgt dem Stift und rastet ein.
      final h = InkController(stylusOnly: true)..setTool(ToolMode.highlighter);
      h.beginStroke(Offset.zero, 0.5);
      for (var y = 4.0; y <= 100; y += 4) {
        h.extendStroke(Offset(y * 0.02, y), 0.5);
      }
      expect(h.recognizeHeldStroke(), isTrue);
      h.extendStroke(const Offset(3, -150), 0.5); // fast senkrecht nach oben
      h.commitStroke();
      final s = h.scene.strokes.single;
      expect(s.points[3], closeTo(0, 1e-3));
    });

    test('Radierer: automatisch zurück ist Standard – auch bei alten Daten',
        () {
      expect(ToolSettings().eraserAutoReturn, isTrue);
      expect(ToolSettings.fromJson({'eraserAutoReturn': false}).eraserAutoReturn,
          isTrue);
      final off = ToolSettings()..eraserAutoReturn = false;
      expect(ToolSettings.fromJson(off.toJson()).eraserAutoReturn, isFalse);

      final c = InkController(stylusOnly: true);
      c.beginStroke(Offset.zero, 0.5);
      c.extendStroke(const Offset(60, 0), 0.5);
      c.commitStroke();
      c.setTool(ToolMode.eraser);
      c.eraseAt(const Offset(30, 0), 5);
      c.endErase();
      expect(c.tool, ToolMode.pen);
    });

    test('Zuletzt benutzte Farben – getrennt für Stift und Textmarker', () {
      final c = InkController(stylusOnly: true);
      c.setColor(c.palette.first);
      expect(c.recentColors, isEmpty, reason: 'feste Farben zählen nicht');
      c.setColor(const Color(0xFF123456));
      c.setColor(const Color(0xFF654321));
      c.setColor(const Color(0xFF123456));
      expect(c.recentColors.map((x) => x.toARGB32()),
          [0xFF123456, 0xFF654321]);
      c.setTool(ToolMode.highlighter);
      expect(c.recentColors, isEmpty);
      c.setColor(const Color(0xFFABCDEF));
      expect(c.recentColors.single.toARGB32(), 0xFFABCDEF);
      expect(c.highlighterColor.toARGB32(), 0xFFABCDEF);
      final again = ToolSettings.fromJson(c.settings.toJson());
      expect(again.recentHighlighter, [0xFFABCDEF]);
      expect(again.customColors.first, 0xFF123456);
    });

    test('Favoriten: auch Textmarker, keine Doppelten, wiederherstellbar', () {
      final c = InkController(stylusOnly: true)..setTool(ToolMode.highlighter);
      c.setWidth(20);
      c.setColor(const Color(0xFF00FF00));
      c.saveCurrentAsPreset();
      c.saveCurrentAsPreset();
      expect(c.settings.presets.length, 1);
      final hl = c.settings.presets.single;
      expect(hl.highlighter, isTrue);
      c.setTool(ToolMode.pen);
      c.applyPreset(hl);
      expect(c.tool, ToolMode.highlighter);
      expect(c.highlighterWidth, 20);
      expect(c.isActivePreset(hl), isTrue);
      expect(PenPreset.fromJson(hl.toJson())!.highlighter, isTrue);
      c.removePreset(hl);
      expect(c.settings.presets, isEmpty);
      c.restorePreset(hl, 0);
      expect(c.settings.presets.single, hl);
    });

    test('Pipette: Schrift, Formfüllung, Textmarker darunter', () {
      final c = InkController(stylusOnly: true);
      c.scene.add(Stroke(
          id: 'hl',
          color: 0xFFFFFF00,
          width: 14,
          tool: InkTool.highlighter,
          points: Float32List.fromList([0, 0, 0.5, 100, 0, 0.5])));
      c.scene.add(Stroke(
          id: 'pen',
          color: 0xFFFF0000,
          width: 2,
          tool: InkTool.pen,
          points: Float32List.fromList([50, -20, 0.5, 50, 20, 0.5])));
      c.scene.add(Stroke(
          id: 'box',
          color: 0xFF000000,
          width: 2,
          tool: InkTool.shape,
          fill: 0x6600FF00,
          points: Float32List.fromList(polyPoints(const [
            Offset(200, 200), Offset(300, 200), Offset(300, 300),
            Offset(200, 300), Offset(200, 200),
          ]))));
      expect(c.colorAt(const Offset(50, 0))!.toARGB32(), 0xFFFF0000);
      expect(c.colorAt(const Offset(10, 0))!.toARGB32(), 0xFFFFFF00);
      expect(c.colorAt(const Offset(250, 250))!.toARGB32(), 0xFF00FF00);
      expect(c.colorAt(const Offset(500, 500)), isNull);
      c.setPicking(true);
      c.applyPickedColor(const Color(0xFF00FF00));
      expect(c.picking, isFalse);
      expect(c.penColor.toARGB32(), 0xFF00FF00);
      expect(c.recentColors.first.toARGB32(), 0xFF00FF00);
    });

    test('Lasso dreht um die Mitte und rastet bei 90° ein', () {
      final c = InkController(stylusOnly: true)..setTool(ToolMode.lasso);
      c.scene.add(Stroke(
          id: 'a',
          color: 0xFF000000,
          width: 2,
          tool: InkTool.pen,
          points: Float32List.fromList([0, 0, 0.5, 50, 0, 0.5, 100, 0, 0.5])));
      c.selection = alive(c);
      final b = c.selectionBounds!;
      c.beginRotateSelection(b.center + const Offset(100, 0));
      // Auf 89° im Uhrzeigersinn ziehen → rastet bei 90° ein.
      c.moveSelection(b.center + at(-89, 100));
      expect(c.snapped, isTrue);
      expect(c.dragRotate.value, closeTo(math.pi / 2, 1e-6));
      c.endMoveSelection();
      final r = alive(c).single;
      expect(r.points[0], closeTo(50, 1e-3));
      expect(r.points[1], closeTo(-50, 1e-3));
      expect(r.points[6], closeTo(50, 1e-3));
      expect(r.points[7], closeTo(50, 1e-3));
      // 30° rastet nicht ein.
      c.selection = alive(c);
      final b2 = c.selectionBounds!;
      c.beginRotateSelection(b2.center + const Offset(100, 0));
      c.moveSelection(b2.center + at(30, 100));
      expect(c.snapped, isFalse);
      expect(c.dragRotate.value, closeTo(-30 * math.pi / 180, 1e-6));
      c.endMoveSelection();
      c.undo();
      c.undo();
      expect(alive(c).single.id, 'a');
    });

    test('Glätten: Mitte = wie bisher, stark = ruhiger, Enden bleiben', () {
      final zig = Float32List.fromList([
        for (var i = 0; i <= 20; i++) ...[i * 5.0, i.isEven ? 3.0 : -3.0, 0.5]
      ]);
      expect(InkController.smoothPoints(zig, 0), same(zig));
      final calm = InkController.smoothPoints(zig, 1);
      double wobble(Float32List p) {
        var m = 0.0;
        for (var i = 3; i < p.length - 3; i += 3) {
          m = math.max(m, p[i + 1].abs());
        }
        return m;
      }

      expect(wobble(calm), lessThan(wobble(zig) * 0.5));
      expect(calm[0], zig[0]);
      expect(calm[calm.length - 3], zig[zig.length - 3]);
      expect(ToolSettings.fromJson({'smoothing': 0.9}).smoothing, 0.9);
      expect(ToolSettings.fromJson({'smoothing': 9}).smoothing, 1);
    });
  });

  test('Canvas: Strichstärke folgt dem Zoom (weit draußen nicht unsichtbar)',
      () {
    final c = InkController(stylusOnly: true)..widthFollowsZoom = true;
    c.camera.zoomAt(Offset.zero, 0.1);
    c.beginStroke(Offset.zero, 0.5);
    c.extendStroke(const Offset(500, 0), 0.5);
    c.commitStroke();
    final s = c.scene.strokes.single;
    expect(s.width * c.camera.scale, closeTo(c.penWidth, 1e-9));
    // Auf Seiten (Standard) bleibt sie fest.
    final page = InkController(stylusOnly: true);
    page.camera.zoomAt(Offset.zero, 0.5);
    page.beginStroke(Offset.zero, 0.5);
    page.extendStroke(const Offset(50, 0), 0.5);
    page.commitStroke();
    expect(page.scene.strokes.single.width, page.penWidth);
  });
}
