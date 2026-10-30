import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mindflow/app/services.dart';
import 'package:mindflow/app/theme.dart';
import 'package:mindflow/data/database.dart';
import 'package:mindflow/data/text_repository.dart';
import 'package:mindflow/features/study/study_screen.dart';
import 'package:mindflow/ink/text_layer.dart';
import 'package:mindflow/ui/futuristic.dart';
import 'package:mindflow/ink/camera.dart';
import 'package:mindflow/ink/ink_controller.dart';
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
}
