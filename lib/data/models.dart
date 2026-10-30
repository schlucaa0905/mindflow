import 'dart:convert';

import 'package:sqlite3/sqlite3.dart';

import '../app/theme.dart';

enum ObjectType { notebook, page, board, knowledge, document, flashcard }

/// Seitenvorlagen im Notizbuch.
enum PageTemplate {
  blank('Blanko'),
  lined('Liniert'),
  grid('Kariert'),
  dotted('Punktraster');

  const PageTemplate(this.label);
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

  Paper get paper =>
      data['paper'] == 'light' ? Paper.light : Paper.dark;

  PageTemplate get template => PageTemplate.values.firstWhere(
        (t) => t.name == data['template'],
        orElse: () => PageTemplate.lined,
      );
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
