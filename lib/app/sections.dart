import 'package:flutter/material.dart';

/// Die acht Hauptbereiche von MindFlow.
enum Section {
  home('Home', Icons.home_outlined, Icons.home),
  notebook('Notizbuch', Icons.menu_book_outlined, Icons.menu_book),
  canvas('Canvas', Icons.bubble_chart_outlined, Icons.bubble_chart),
  documents('Dokumente', Icons.picture_as_pdf_outlined, Icons.picture_as_pdf,
      comingInPhase: 4),
  knowledge('Wissen', Icons.hub_outlined, Icons.hub, comingInPhase: 5),
  study('Lernen', Icons.school_outlined, Icons.school, comingInPhase: 7),
  search('Suche', Icons.search, Icons.search),
  archive('Archiv', Icons.inventory_2_outlined, Icons.inventory_2);

  const Section(this.label, this.icon, this.selectedIcon,
      {this.comingInPhase});

  final String label;
  final IconData icon;
  final IconData selectedIcon;

  /// Phase, in der der Bereich gebaut wird (null = schon da).
  final int? comingInPhase;
}
