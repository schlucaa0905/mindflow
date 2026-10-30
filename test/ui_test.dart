import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mindflow/app/theme.dart';
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
}
