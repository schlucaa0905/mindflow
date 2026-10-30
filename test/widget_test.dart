import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mindflow/app/services.dart';
import 'package:mindflow/main.dart';

void main() {
  testWidgets('App startet mit Seitenleiste und Startseite', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MindFlowApp(services: AppServices.inMemory()));
    await tester.pump();

    expect(find.text('MindFlow'), findsOneWidget);
    expect(find.text('Neues Notizbuch'), findsWidgets);
    expect(find.text('Archiv'), findsWidgets);
  });

  testWidgets('Navigation zum Archiv', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MindFlowApp(services: AppServices.inMemory()));
    await tester.pump();
    await tester.tap(find.text('Archiv').first);
    await tester.pumpAndSettle();
    expect(find.text('Der Papierkorb ist leer.'), findsOneWidget);
  });
}
