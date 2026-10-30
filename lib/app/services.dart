import 'package:flutter/material.dart';

import '../data/canvas_repository.dart';
import '../data/database.dart';
import '../data/object_repository.dart';

/// Alle zentralen Dienste der App an einer Stelle.
class AppServices {
  AppServices(this.db)
      : objects = ObjectRepository(db.raw),
        canvas = CanvasRepository(db.raw) {
    themeMode.value = switch (objects.setting('theme')) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
  }

  factory AppServices.inMemory() => AppServices(AppDatabase.inMemory());

  final AppDatabase db;
  final ObjectRepository objects;
  final CanvasRepository canvas;
  final ValueNotifier<ThemeMode> themeMode = ValueNotifier(ThemeMode.system);

  void setThemeMode(ThemeMode mode) {
    themeMode.value = mode;
    objects.setSetting('theme', mode.name);
  }
}

/// Macht [AppServices] überall im Widget-Baum verfügbar.
class Services extends InheritedWidget {
  const Services({super.key, required this.services, required super.child});

  final AppServices services;

  static AppServices of(BuildContext context) =>
      context.getInheritedWidgetOfExactType<Services>()!.services;

  @override
  bool updateShouldNotify(Services oldWidget) => false;
}
