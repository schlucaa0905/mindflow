import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../data/canvas_repository.dart';
import '../data/database.dart';
import '../data/object_repository.dart';
import '../data/study_repository.dart';
import '../data/text_repository.dart';
import '../ink/tool_settings.dart';

/// Alle zentralen Dienste der App an einer Stelle.
class AppServices {
  AppServices(this.db)
      : objects = ObjectRepository(db.raw),
        canvas = CanvasRepository(db.raw),
        texts = TextRepository(db.raw) {
    study = StudyRepository(db.raw, objects);
    themeMode.value = switch (objects.setting('theme')) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
    tools = ToolSettings.fromJson(_readJson('tools'));
    tools.addListener(_scheduleToolSave);
  }

  factory AppServices.inMemory() => AppServices(AppDatabase.inMemory());

  final AppDatabase db;
  final ObjectRepository objects;
  final CanvasRepository canvas;

  /// Textfelder (Tastatur) auf Seiten, PDFs und Canvas.
  final TextRepository texts;

  /// Karteikarten und Lernplan.
  late final StudyRepository study;
  final ValueNotifier<ThemeMode> themeMode = ValueNotifier(ThemeMode.system);

  /// Werkzeug-Einstellungen, app-weit geteilt und dauerhaft gespeichert.
  late final ToolSettings tools;
  Timer? _toolSaveTimer;

  void setThemeMode(ThemeMode mode) {
    themeMode.value = mode;
    objects.setSetting('theme', mode.name);
  }

  Map<String, dynamic>? _readJson(String key) {
    final raw = objects.setting(key);
    if (raw == null) return null;
    try {
      final v = jsonDecode(raw);
      return v is Map<String, dynamic> ? v : null;
    } catch (_) {
      return null; // Kaputte Einstellungen: mit Standardwerten weiter.
    }
  }

  void _scheduleToolSave() {
    _toolSaveTimer?.cancel();
    _toolSaveTimer = Timer(const Duration(milliseconds: 600), saveTools);
  }

  void saveTools() {
    _toolSaveTimer?.cancel();
    objects.setSetting('tools', jsonEncode(tools.toJson()));
  }
}

/// Macht [AppServices] überall im Widget-Baum verfügbar.
class Services extends InheritedWidget {
  const Services({super.key, required this.services, required super.child});

  final AppServices services;

  static AppServices of(BuildContext context) =>
      context.getInheritedWidgetOfExactType<Services>()!.services;

  static AppServices? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<Services>()?.services;

  @override
  bool updateShouldNotify(Services oldWidget) => false;
}
