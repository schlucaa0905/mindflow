import 'dart:convert';

import 'package:sqlite3/sqlite3.dart';

import '../app/theme.dart';

enum ObjectType { notebook, page, board, knowledge, document, flashcard }

/// Seitenvorlagen im Notizbuch. Gespeichert wird der Name, nicht die Position.
enum PageTemplate {
  blank('Blanko'),
  lined('Liniert'),
  linedNarrow('Liniert eng'),
  grid('Kariert'),
  gridSmall('Kariert klein'),
  dotted('Punktraster'),
  cornell('Cornell'),
  todo('Aufgaben');

  const PageTemplate(this.label);
  final String label;
}

/// Seitenformat eines Notizbuchs.
enum PageFormat {
  a4Portrait('A4 hoch', 595, 842),
  a4Landscape('A4 quer', 842, 595),
  square('Quadratisch', 700, 700);

  const PageFormat(this.label, this.width, this.height);
  final String label;
  final double width;
  final double height;
}

/// Gestaltung eines Notizbuch-Umschlags.
enum CoverStyle {
  solid('Einfarbig'),
  gradient('Verlauf'),
  linen('Leinen'),
  dots('Punkte'),
  stripes('Streifen'),
  grid('Raster');

  const CoverStyle(this.label);
  final String label;
}

/// Ein verknüpfbares Objekt (Notizbuch, Seite, Canvas …).
class MfObject {
  MfObject({
    required this.id,
    required this.type,
    required this.title,
    required this.parentId,
    required this.position,
    required this.data,
    required this.pinned,
    required this.archived,
    required this.createdAt,
    required this.updatedAt,
    required this.openedAt,
    required this.deletedAt,
  });

  factory MfObject.fromRow(Row r) => MfObject(
        id: r['id'] as String,
        type: ObjectType.values.byName(r['type'] as String),
        title: r['title'] as String,
        parentId: r['parent_id'] as String?,
        position: (r['position'] as num).toDouble(),
        data: (jsonDecode(r['data'] as String) as Map).cast<String, dynamic>(),
        pinned: (r['pinned'] as int) == 1,
        archived: (r['archived'] as int) == 1,
        createdAt: _date(r['created_at'] as int),
        updatedAt: _date(r['updated_at'] as int),
        openedAt: r['opened_at'] == null ? null : _date(r['opened_at'] as int),
        deletedAt:
            r['deleted_at'] == null ? null : _date(r['deleted_at'] as int),
      );

  final String id;
  final ObjectType type;
  final String title;
  final String? parentId;
  final double position;
  final Map<String, dynamic> data;
  final bool pinned;
  final bool archived;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? openedAt;
  final DateTime? deletedAt;

  String get displayTitle => title.trim().isEmpty ? 'Ohne Titel' : title;

  Paper get paper => Paper.values.firstWhere(
        (p) => p.name == data['paper'],
        orElse: () => Paper.dark,
      );

  PageTemplate get template => PageTemplate.values.firstWhere(
        (t) => t.name == data['template'],
        orElse: () => PageTemplate.lined,
      );

  PageFormat get format => PageFormat.values.firstWhere(
        (f) => f.name == data['format'],
        orElse: () => PageFormat.a4Portrait,
      );

  CoverStyle get coverStyle => CoverStyle.values.firstWhere(
        (s) => s.name == data['coverStyle'],
        orElse: () => CoverStyle.solid,
      );

  int get coverColor => (data['cover'] as int?) ?? 0xFF8B7CF6;

  /// Kategorie bzw. Fach, z. B. "Informatik". Leer = keine.
  String get category => (data['category'] as String?)?.trim() ?? '';

  String get description => (data['description'] as String?)?.trim() ?? '';
}

DateTime _date(int ms) => DateTime.fromMillisecondsSinceEpoch(ms);

/// Eine Karte auf der Canvas-Fläche.
class CanvasNode {
  CanvasNode({
    required this.id,
    required this.boardId,
    required this.x,
    required this.y,
    required this.w,
    required this.h,
    required this.text,
    this.color,
    this.refObjectId,
  });

  factory CanvasNode.fromRow(Row r) => CanvasNode(
        id: r['id'] as String,
        boardId: r['board_id'] as String,
        x: (r['x'] as num).toDouble(),
        y: (r['y'] as num).toDouble(),
        w: (r['w'] as num).toDouble(),
        h: (r['h'] as num).toDouble(),
        text: r['text'] as String,
        color: r['color'] as int?,
        refObjectId: r['ref_object_id'] as String?,
      );

  final String id;
  final String boardId;
  double x;
  double y;
  double w;
  double h;
  String text;
  int? color;
  String? refObjectId;
}

/// Eine sichtbare Verbindung zwischen zwei Karten.
class CanvasEdge {
  CanvasEdge({
    required this.id,
    required this.boardId,
    required this.fromId,
    required this.toId,
    this.label,
  });

  factory CanvasEdge.fromRow(Row r) => CanvasEdge(
        id: r['id'] as String,
        boardId: r['board_id'] as String,
        fromId: r['from_node'] as String,
        toId: r['to_node'] as String,
        label: r['label'] as String?,
      );

  final String id;
  final String boardId;
  final String fromId;
  final String toId;
  String? label;
}
