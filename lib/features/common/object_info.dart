import 'package:flutter/material.dart';

import '../../data/models.dart';
import '../../data/object_repository.dart';

/// Symbol und Bezeichnung für jede Art von Objekt – überall gleich.
IconData iconFor(ObjectType t) => switch (t) {
      ObjectType.notebook => Icons.menu_book_outlined,
      ObjectType.page => Icons.description_outlined,
      ObjectType.board => Icons.bubble_chart_outlined,
      ObjectType.knowledge => Icons.hub_outlined,
      ObjectType.document => Icons.picture_as_pdf_outlined,
      ObjectType.flashcard => Icons.style_outlined,
    };

String typeLabel(ObjectType t) => switch (t) {
      ObjectType.notebook => 'Notizbuch',
      ObjectType.page => 'Notizbuchseite',
      ObjectType.board => 'Canvas',
      ObjectType.knowledge => 'Wissenseintrag',
      ObjectType.document => 'Dokument',
      ObjectType.flashcard => 'Karteikarte',
    };

/// Lesbarer Titel – Seiten haben keinen eigenen Titel, daher
/// "Seite 3 · Netzwerktechnik".
String describeTitle(ObjectRepository repo, MfObject o) {
  if (o.type != ObjectType.page || o.parentId == null) return o.displayTitle;
  final parent = repo.get(o.parentId!);
  final pages = repo.children(o.parentId!);
  final index = pages.indexWhere((p) => p.id == o.id);
  final nr = index < 0 ? '?' : '${index + 1}';
  return 'Seite $nr · ${parent?.displayTitle ?? 'Notizbuch'}';
}
