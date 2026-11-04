import 'dart:typed_data';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mindflow/app/services.dart';
import 'package:mindflow/app/theme.dart';
import 'package:mindflow/data/database.dart';
import 'package:mindflow/data/models.dart';
import 'package:mindflow/data/object_repository.dart';
import 'package:mindflow/features/notebook/page_design_dialog.dart';
import 'package:mindflow/features/notebook/page_painter.dart';
import 'package:mindflow/data/text_repository.dart';
import 'package:mindflow/features/study/study_screen.dart';
import 'package:mindflow/ink/text_layer.dart';
import 'package:mindflow/ui/futuristic.dart';
import 'package:mindflow/ink/camera.dart';
import 'package:mindflow/ink/ink_canvas_view.dart';
import 'package:mindflow/ink/ink_controller.dart';
import 'package:mindflow/storage/element_library.dart';
import 'package:mindflow/ink/shape_recognizer.dart';
import 'package:mindflow/ink/stroke.dart';
import 'package:mindflow/ink/surface_overlays.dart';
import 'package:mindflow/ink/tool_glyphs.dart';
import 'package:mindflow/ink/tool_row.dart';
import 'package:mindflow/ui/clean_menu.dart';

Widget _app(Widget child, {Brightness b = Brightness.dark}) => MaterialApp(
      theme: buildTheme(b),
      home: Scaffold(body: Center(child: child)),
    );

void main() {
  testWidgets('Alle Werkzeug-Grafiken lassen sich zeichnen', (tester) async {
    for (final b in Brightness.values) {
      await tester.pumpWidget(_app(
        Wrap(children: [
          for (final k in GlyphKind.values)
            for (final selected in [false, true])
              ToolGlyph(
                kind: k,
                tip: const Color(0xFF8B7CF6),
                body: const Color(0xFFE6E6EE),
                outline: const Color(0xFF1C1C22),
                selected: selected,
              ),
        ]),
        b: b,
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('Werkzeugzeile baut sich für jedes Werkzeug', (tester) async {
    final c = InkController(stylusOnly: true);
    for (final t in ToolMode.values) {
      c.setTool(t);
      await tester.pumpWidget(_app(SizedBox(
        width: 900,
        height: 60,
        child: ToolRow(controller: c),
      )));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('Sauberes Menü öffnet sich und meldet die Auswahl',
      (tester) async {
    String? chosen;
    await tester.pumpWidget(_app(CleanMenuButton(
      entries: const [
        CleanMenuEntry('a', 'Erster Punkt', icon: Icons.star_outline),
        CleanMenuEntry.divider(),
        CleanMenuEntry('b', 'Löschen',
            icon: Icons.delete_outline, destructive: true),
      ],
      onSelected: (v) => chosen = v,
    )));
    await tester.tap(find.byIcon(Icons.more_horiz));
    await tester.pumpAndSettle();
    expect(find.text('Erster Punkt'), findsOneWidget);
    await tester.tap(find.text('Löschen'));
    await tester.pumpAndSettle();
    expect(chosen, 'b');
    expect(find.text('Erster Punkt'), findsNothing);
  });

  testWidgets('Präsentations-Steuerung schaltet Werkzeuge', (tester) async {
    final c = InkController(stylusOnly: true);
    var exited = false;
    await tester.pumpWidget(_app(PresenterControls(
      controller: c,
      label: '1 / 3',
      onExit: () => exited = true,
    )));
    await tester.tap(find.byIcon(Icons.highlight_alt));
    await tester.pump();
    expect(c.tool, ToolMode.laser);
    await tester.tap(find.byIcon(Icons.close_fullscreen));
    expect(exited, isTrue);
    // Ausblend-Timer ablaufen lassen.
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('Zoom-Anzeige erscheint beim Zoomen', (tester) async {
    final cam = Camera();
    await tester.pumpWidget(_app(ZoomBadge(camera: cam)));
    await tester.pump(const Duration(seconds: 1));
    cam.zoomAt(Offset.zero, 1.5);
    cam.zoomAt(Offset.zero, 1.1);
    await tester.pump();
    expect(find.text('165 %'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('Textfeld anlegen, tippen, speichern – leere verschwinden',
      (tester) async {
    final db = AppDatabase.inMemory();
    addTearDown(db.dispose);
    final repo = TextRepository(db.raw);
    final c = InkController(stylusOnly: true)
      ..drawBounds = const Rect.fromLTWH(0, 0, 595, 842)
      ..setTool(ToolMode.text);
    final key = GlobalKey<TextLayerState>();
    await tester.pumpWidget(_app(SizedBox(
      width: 800,
      height: 600,
      child: Stack(children: [
        Positioned.fill(
          child: TextLayer(
              key: key, ownerId: 'seite', controller: c, repo: repo),
        ),
      ]),
    )));
    key.currentState!.createAt(const Offset(60, 80));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Hallo MindFlow');
    key.currentState!.finishEditing();
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);
    expect(find.text('Hallo MindFlow'), findsOneWidget);
    expect(repo.items('seite').single.text, 'Hallo MindFlow');

    // Leeres Feld: verschwindet beim Beenden.
    key.currentState!.createAt(const Offset(60, 300));
    await tester.pumpAndSettle();
    key.currentState!.finishEditing();
    await tester.pumpAndSettle();
    expect(repo.items('seite').length, 1);

    // Außerhalb des Blatts entsteht kein Textfeld.
    key.currentState!.createAt(const Offset(-50, -50));
    await tester.pumpAndSettle();
    expect(key.currentState!.editing, isFalse);

    // Werkzeug wechseln beendet die Bearbeitung.
    key.currentState!.createAt(const Offset(60, 500));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Zweites');
    c.setTool(ToolMode.pen);
    await tester.pumpAndSettle();
    expect(repo.items('seite').length, 2);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('Leuchtknopf und Fortschrittsring', (tester) async {
    var taps = 0;
    await tester.pumpWidget(_app(Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GlowButton(label: 'Los', onPressed: () => taps++),
        const ProgressRing(value: 0.5),
        const MindFlowLogo(),
        const StatusPill('Neu'),
      ],
    )));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Los'));
    expect(taps, 1);
    expect(find.text('50 %'), findsOneWidget);
  });

  testWidgets('Lernrunde: Antwort zeigen, bewerten, fertig', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final services = AppServices.inMemory();
    services.study.create(front: 'Was macht DHCP?', back: 'Vergibt IPs');
    await tester.pumpWidget(Services(
      services: services,
      child: MaterialApp(
        theme: buildTheme(Brightness.dark),
        home: const Scaffold(body: StudyScreen()),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('1 fällig'), findsWidgets);
    await tester.tap(find.text('Lernen starten'));
    await tester.pumpAndSettle();
    expect(find.text('Was macht DHCP?'), findsOneWidget);
    await tester.tap(find.text('Antwort zeigen'));
    await tester.pumpAndSettle();
    expect(find.text('Vergibt IPs'), findsOneWidget);
    await tester.tap(find.text('Gut'));
    await tester.pumpAndSettle();
    expect(find.text('Runde geschafft!'), findsOneWidget);
    expect(services.study.stats(DateTime.now()).due, 0);
  });

  testWidgets('Textfeld-Leiste: fett, kursiv, Aufzählung', (tester) async {
    final db = AppDatabase.inMemory();
    addTearDown(db.dispose);
    final repo = TextRepository(db.raw);
    final c = InkController(stylusOnly: true)..setTool(ToolMode.text);
    final key = GlobalKey<TextLayerState>();
    await tester.pumpWidget(_app(SizedBox(
      width: 900,
      height: 600,
      child: Stack(children: [
        Positioned.fill(
          child: TextLayer(key: key, ownerId: 's', controller: c, repo: repo),
        ),
      ]),
    )));
    key.currentState!.createAt(const Offset(40, 200));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Fett (Strg/⌘ + B)'));
    await tester.pump();
    await tester.tap(find.byTooltip('Kursiv (Strg/⌘ + I)'));
    await tester.pump();
    await tester.tap(find.byTooltip('Aufzählung'));
    await tester.pump();
    final t = repo.items('s').single;
    expect(t.bold, isTrue);
    expect(t.italic, isTrue);
    expect(t.text, '• ');
    key.currentState!.finishEditing();
    await tester.pumpAndSettle();
  });

  testWidgets('Modus-Knöpfe wie bei Goodnotes', (tester) async {
    final c = InkController(stylusOnly: true)..setTool(ToolMode.highlighter);
    await tester.pumpWidget(_app(ToolModeButtons(controller: c)));
    await tester.tap(find.byTooltip('Radierer (E)'));
    await tester.pump();
    expect(c.tool, ToolMode.eraser);
    await tester.tap(find.byTooltip('Schreiben (P)'));
    await tester.pump();
    expect(c.tool, ToolMode.highlighter, reason: 'zurück zum letzten Stift');
    await tester.tap(find.byTooltip('Textfeld (T)'));
    await tester.pump();
    expect(c.tool, ToolMode.text);
  });

  testWidgets('Stiftwahl in der Unterleiste', (tester) async {
    final c = InkController(stylusOnly: true)..setTool(ToolMode.eraser);
    await tester.pumpWidget(_app(SizedBox(
        width: 1000, height: 70, child: ToolRow(controller: c))));
    c.setTool(ToolMode.pen);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Kugelschreiber (P) – nochmal tippen: Optionen'));
    await tester.pump();
    expect(c.penType, PenType.ballpoint);
    expect(c.tool, ToolMode.pen);
  });

  testWidgets('Text dockt an Kästchen an – oder bleibt frei', (tester) async {
    const grid = TextLineGrid(22, 0, snapX: true);
    double baseline(TextItem t) {
      final tp = TextPainter(
        text: TextSpan(text: 'Hg', style: textItemStyle(t)),
        strutStyle: textItemStrut(t),
        textDirection: TextDirection.ltr,
      )..layout();
      final b = tp.computeDistanceToActualBaseline(TextBaseline.alphabetic);
      tp.dispose();
      return b;
    }

    for (final size in [14.0, 18.0, 26.0, 36.0]) {
      final t = TextItem(
          id: 'a', ownerId: 'p', x: 300, y: 300, w: 200,
          text: 'Zeile 1\nZeile 2', size: size, color: 0xFF000000);
      grid.snap(t); // legt die Zeilenhöhe fest
      expect(t.lineHeight! % 22, closeTo(0, 1e-9));
      expect(t.lineHeight, greaterThanOrEqualTo(size));
      final b = baseline(t);

      // Nah dran (3 Punkte unter einer Linie, 4 neben einer Kante): dockt an.
      t
        ..y = 110 - b + 3
        ..x = 43;
      grid.snap(t);
      expect(t.y + b, closeTo(110, 0.01));
      expect(t.x, 47);

      // Mehrzeilig: jede Zeile ist genau so hoch wie die Zeilenhöhe.
      final tp = TextPainter(
        text: TextSpan(text: t.text, style: textItemStyle(t)),
        strutStyle: textItemStrut(t),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: t.w);
      expect(tp.height, closeTo(t.lineHeight! * 2, 0.01));
      tp.dispose();

      // Ein halbes Kästchen daneben: bleibt frei.
      t
        ..y = 110 - b + 11
        ..x = 58;
      grid.snap(t);
      expect(t.y, closeTo(110 - b + 11, 1e-9));
      expect(t.x, 58);
    }
  });

  testWidgets('Unterleiste: Favorit, Pipette, Radierer-Rückkehr',
      (tester) async {
    final c = InkController(stylusOnly: true);
    await tester.pumpWidget(_app(SizedBox(
        width: 800, height: 70, child: ToolRow(controller: c))));
    Future<void> tapTip(String tip) async {
      await tester.ensureVisible(find.byTooltip(tip));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip(tip));
      await tester.pumpAndSettle();
    }

    await tapTip('Aktuellen Stift als Favorit speichern');
    expect(c.settings.presets.length, 1);
    await tapTip('Pipette – Farbe von der Seite aufnehmen');
    expect(c.picking, isTrue);
    c.setTool(ToolMode.eraser);
    await tester.pumpAndSettle();
    expect(c.picking, isFalse);
    expect(c.settings.eraserAutoReturn, isTrue);
    await tester.ensureVisible(find.text('Danach Stift'));
    await tester.tap(find.text('Danach Stift'));
    await tester.pumpAndSettle();
    expect(c.settings.eraserAutoReturn, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Linie: ±1°, Pipette und Lasso-Drehgriff auf der Fläche',
      (tester) async {
    final c = InkController(stylusOnly: true)..setTool(ToolMode.shape);
    c.scene.add(Stroke(
        id: 'l',
        color: 0xFFFF0000,
        width: 2,
        tool: InkTool.shape,
        points: Float32List.fromList(
            polyPoints(const [Offset(100, 200), Offset(400, 200)]))));
    await tester.pumpWidget(_app(SizedBox(
        width: 800, height: 600, child: InkCanvasView(controller: c))));
    expect(c.tryEditShapeAt(const Offset(250, 200)), isTrue);
    await tester.pump();
    expect(find.text('0° · 10,6 cm'), findsOneWidget);

    await tester.tap(find.byTooltip('1° mehr (halten: weiterdrehen)'));
    await tester.pump();
    expect(find.text('1° · 10,6 cm'), findsOneWidget);
    await tester.tap(find.byTooltip('1° weniger (halten: weiterdrehen)'));
    await tester.pump();
    await tester.tap(find.byTooltip('1° weniger (halten: weiterdrehen)'));
    await tester.pump();
    expect(find.text('359° · 10,6 cm'), findsOneWidget);

    // Pipette: Antippen der Linie nimmt ihre Farbe.
    c.setTool(ToolMode.pen);
    c.setPicking(true);
    await tester.pump();
    await tester.tapAt(const Offset(250, 200));
    await tester.pump();
    expect(c.picking, isFalse);
    expect(c.penColor.toARGB32(), 0xFFFF0000);

    // Lasso: auswählen und am Griff unter der Auswahl um 90° drehen.
    c.setTool(ToolMode.lasso);
    c.beginLasso(const Offset(80, 150));
    c.extendLasso(const Offset(420, 150));
    c.extendLasso(const Offset(420, 250));
    c.extendLasso(const Offset(80, 250));
    c.endLasso();
    await tester.pump();
    expect(c.selection.length, 1);
    final handle = c.rotateHandleScreen()!;
    final pivot = c.selectionBounds!.center;
    final g = await tester.startGesture(handle, kind: PointerDeviceKind.stylus);
    await g.moveTo(pivot + const Offset(60, 1));
    await tester.pump();
    await g.moveTo(pivot + const Offset(100, 1));
    await tester.pump();
    await g.up();
    await tester.pump();
    final s = c.scene.strokes.where((x) => !x.deleted).single;
    expect(InkController.lineAngle(s), closeTo(89, 0.01));
    expect(tester.takeException(), isNull);
  });

  test('Seite: eigene Blattfarbe und Linienabstand', () {
    MfObject page(Map<String, dynamic> data) => MfObject(
        id: 'p',
        type: ObjectType.page,
        title: '',
        parentId: 'n',
        position: 0,
        data: data,
        pinned: false,
        archived: false,
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
        openedAt: null,
        deletedAt: null);
    expect(pageStyle(PaperStyle.light, page({'template': 'grid'})),
        same(PaperStyle.light));
    final poster = pageStyle(
        PaperStyle.light, page({'paperColor': 0xFF1565C0, 'gap': 1.35}));
    expect(poster.sheet, const Color(0xFF1565C0));
    expect(isDarkSheet(poster.sheet), isTrue);
    expect(poster.line.computeLuminance(), greaterThan(0.5));
    expect(poster.gap, 1.35);
    expect(poster.desk, PaperStyle.light.desk);
    expect(textGridFor(PageTemplate.lined, 0.75)!.gap, 21);
    expect(textGridFor(PageTemplate.grid)!.gap, 22);
    final yellow = pageStyle(PaperStyle.dark, page({'paperColor': 0xFFFFF59D}));
    expect(isDarkSheet(yellow.sheet), isFalse);
    expect(yellow.gap, 1.0);
  });

  testWidgets('Seite gestalten: Vorlage, Abstand, Farbe, alle Seiten',
      (tester) async {
    final page = MfObject(
        id: 'p',
        type: ObjectType.page,
        title: '',
        parentId: 'n',
        position: 0,
        data: {'template': 'lined', 'paperColor': 0xFFFFF59D},
        pinned: false,
        archived: false,
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
        openedAt: null,
        deletedAt: null);
    PageDesign? result;
    await tester.pumpWidget(_app(Builder(
      builder: (ctx) => TextButton(
        onPressed: () async => result = await showPageDesign(ctx,
            page: page,
            notebookPaper: PaperStyle.light,
            format: PageFormat.a4Portrait,
            repo: ObjectRepository(AppDatabase.inMemory().raw)),
        child: const Text('öffnen'),
      ),
    )));
    await tester.tap(find.text('öffnen'));
    await tester.pumpAndSettle();
    Future<void> tapIt(Finder f) async {
      await tester.ensureVisible(f);
      await tester.pumpAndSettle();
      await tester.tap(f);
      await tester.pumpAndSettle();
    }

    await tapIt(find.text('Kariert'));
    await tapIt(find.text('Weit'));
    await tapIt(find.text('Alle Seiten'));
    await tapIt(find.text('Auch für neue Seiten verwenden'));
    await tester.tap(find.text('Übernehmen'));
    await tester.pumpAndSettle();
    expect(result, isNotNull);
    expect(result!.template, PageTemplate.grid);
    expect(result!.gap, 1.35);
    expect(result!.color, 0xFFFFF59D, reason: 'eigene Farbe bleibt');
    expect(result!.allPages, isTrue);
    expect(result!.forNewPages, isTrue);
    expect(tester.takeException(), isNull);
  });

  test('Links und Elemente: speichern, laden, finden', () {
    final link = TextItem.link(
        id: 'l',
        ownerId: 'p',
        rect: const Rect.fromLTWH(10, 20, 100, 40),
        target: 'page:abc');
    final again = TextItem.fromRow(link.toJson());
    expect(again.isLink, isTrue);
    expect(again.isText, isFalse);
    expect(again.file, 'page:abc');
    expect(again.h, 40);
    final c = InkController(stylusOnly: true);
    c.pageLinks.value = [again];
    expect(c.linkAt(const Offset(50, 40))?.file, 'page:abc');
    expect(c.linkAt(const Offset(500, 40)), isNull);

    final repo = ObjectRepository(AppDatabase.inMemory().raw);
    final stroke = Stroke(
        id: 's',
        color: 0xFF000000,
        width: 2,
        tool: InkTool.pen,
        points: Float32List.fromList([0, 0, 0.5, 30, 10, 0.5]));
    final text = TextItem(
        id: 't', ownerId: 'p', x: 5, y: 5, w: 80, text: 'Router',
        size: 18, color: 0xFF112233);
    ElementLibrary.save(repo, [SavedElement('e', 'Symbol', [stroke], [text])]);
    final loaded = ElementLibrary.load(repo).single;
    expect(loaded.name, 'Symbol');
    expect(loaded.strokes.single.points.length, 6);
    expect(loaded.items.single.text, 'Router');
    expect(loaded.items.single.color, 0xFF112233);
    repo.setSetting('elements', 'kaputt');
    expect(ElementLibrary.load(repo), isEmpty);
  });

  test('Druckempfindlichkeit', () {
    final s = ToolSettings();
    expect(s.applyPressure(0.4), 0.4);
    s.pressure = 1;
    expect(s.applyPressure(0.4), greaterThan(0.5));
    s.pressure = 0;
    expect(s.applyPressure(0.4), lessThan(0.25));
    expect(ToolSettings.fromJson(s.toJson()).pressure, 0);
  });

  test('Eigene Vorlagen speichern und laden', () {
    final repo = ObjectRepository(AppDatabase.inMemory().raw);
    expect(loadCustomTemplates(repo), isEmpty);
    saveCustomTemplates(repo, [(name: 'Plan', file: 'a.png')]);
    expect(loadCustomTemplates(repo).single.file, 'a.png');
  });
}
