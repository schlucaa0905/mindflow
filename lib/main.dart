import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart' show pdfrxFlutterInitialize;

import 'app/services.dart';
import 'app/shell.dart';
import 'app/theme.dart';
import 'data/database.dart';
import 'storage/backup.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    // PDF-Darstellung (PDFium) vorbereiten – ohne sie startet die App
    // trotzdem, nur PDFs blieben dann leer.
    try {
      await pdfrxFlutterInitialize();
    } catch (_) {}
    await Backup.applyPending();
    final db = await AppDatabase.open();
    final services = AppServices(db);
    runApp(MindFlowApp(services: services));
    // Automatische Sicherung – etwas später, damit der Start flott bleibt.
    Future.delayed(const Duration(seconds: 20),
            () => Backup.runAuto(db.raw, services.objects))
        .ignore();
  } catch (e) {
    runApp(_StartupError(error: e));
  }
}

class MindFlowApp extends StatelessWidget {
  const MindFlowApp({super.key, required this.services});

  final AppServices services;

  @override
  Widget build(BuildContext context) {
    return Services(
      services: services,
      child: ValueListenableBuilder<ThemeMode>(
        valueListenable: services.themeMode,
        builder: (context, mode, _) => MaterialApp(
          title: 'MindFlow',
          debugShowCheckedModeBanner: false,
          theme: buildTheme(Brightness.light),
          darkTheme: buildTheme(Brightness.dark),
          themeMode: mode,
          home: const AppShell(),
        ),
      ),
    );
  }
}

/// Falls die Datenbank nicht geöffnet werden kann: klare Meldung statt
/// eines leeren Bildschirms.
class _StartupError extends StatelessWidget {
  const _StartupError({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: buildTheme(Brightness.dark),
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: SelectableText(
              'MindFlow konnte nicht starten.\n\n$error',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }
}
