import 'dart:convert';
import 'dart:ui' show Rect, Size;

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
  todo('Aufgaben'),
  music('Notenlinien'),
  planner('Wochenplan'),
  coords('Koordinaten');

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

  // --- Wissenseinträge ---

  /// Text eines Wissenseintrags.
  String get body => (data['body'] as String?) ?? '';

  List<String> get tags => [
        for (final t in (data['tags'] as List?) ?? const [])
          if (t is String && t.trim().isNotEmpty) t.trim()
      ];

  // --- Dokumente (PDF) ---

  /// Seitengrößen in Punkten, wie beim Import gemessen.
  List<Size> get pageSizes {
    final raw = data['sizes'];
    if (raw is! List) return const [];
    final out = <Size>[];
    for (final e in raw) {
      if (e is List && e.length == 2 && e[0] is num && e[1] is num) {
        out.add(Size((e[0] as num).toDouble(), (e[1] as num).toDouble()));
      }
    }
    return out;
  }

  /// Dateiname der PDF im App-Ordner.
  String? get fileName => data['file'] as String?;
}

DateTime _date(int ms) => DateTime.fromMillisecondsSinceEpoch(ms);

/// Aussehen einer Canvas-Karte.
enum CardKind {
  card('Karte', 'Abgerundete Karte'),
  sticky('Notizzettel', 'Quadratischer Klebezettel'),
  heading('Überschrift', 'Großer Titel ohne Hintergrund'),
  pill('Kapsel', 'Kurzer Begriff, rund'),
  circle('Kreis', 'Zentrales Thema einer Mindmap');

  const CardKind(this.label, this.hint);
  final String label;
  final String hint;
}

/// Schriftgröße auf Karten.
enum CardTextSize {
  small('S', 13),
  medium('M', 16),
  large('L', 22),
  huge('XL', 30);

  const CardTextSize(this.label, this.size);
  final String label;
  final double size;
}

/// Pfeilspitzen einer Verbindung.
enum EdgeArrow {
  none('Ohne Pfeil'),
  end('Pfeil am Ende'),
  both('Pfeile an beiden Enden');

  const EdgeArrow(this.label);
  final String label;
}

Map<String, dynamic> _json(Object? raw) {
  if (raw is! String || raw.isEmpty) return {};
  try {
    final v = jsonDecode(raw);
    return v is Map ? v.cast<String, dynamic>() : {};
  } catch (_) {
    return {};
  }
}

T _enum<T extends Enum>(List<T> values, Object? name, T fallback) {
  for (final v in values) {
    if (v.name == name) return v;
  }
  return fallback;
}

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
    Map<String, dynamic>? data,
  }) : data = data ?? {};

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
        data: _json(r['data']),
      );

  final String id;
  final String boardId;
  double x;
  double y;
  double w;
  double h;
  String text;

  /// Kartenfarbe (ARGB). null = neutral.
  int? color;
  String? refObjectId;

  /// Gestaltung: Art, Schriftgröße, fett, zentriert, Ebene …
  final Map<String, dynamic> data;

  CardKind get kind => _enum(CardKind.values, data['kind'], CardKind.card);
  set kind(CardKind k) => data['kind'] = k.name;

  CardTextSize get textSize => _enum(CardTextSize.values, data['size'],
      kind == CardKind.heading ? CardTextSize.huge : CardTextSize.medium);
  set textSize(CardTextSize s) => data['size'] = s.name;

  bool get bold => data['bold'] == true;
  set bold(bool v) => data['bold'] = v;

  /// null = Standard der Kartenart (Kapsel/Kreis zentriert).
  bool get centered => data['center'] is bool
      ? data['center'] as bool
      : (kind == CardKind.pill || kind == CardKind.circle);
  set centered(bool v) => data['center'] = v;

  /// Höhe von Hand festgelegt (sonst passt sie sich dem Text an).
  bool get fixedHeight => data['fixedH'] == true;
  set fixedHeight(bool v) => data['fixedH'] = v;

  /// Stapel-Reihenfolge (größer = weiter vorne).
  double get z => (data['z'] as num?)?.toDouble() ?? 0;
  set z(double v) => data['z'] = v;

  Rect get rect => Rect.fromLTWH(x, y, w, h);

  CanvasNode copy({String? id, double dx = 0, double dy = 0}) => CanvasNode(
        id: id ?? this.id,
        boardId: boardId,
        x: x + dx,
        y: y + dy,
        w: w,
        h: h,
        text: text,
        color: color,
        refObjectId: refObjectId,
        data: Map<String, dynamic>.of(data),
      );
}

/// Eine sichtbare Verbindung zwischen zwei Karten.
class CanvasEdge {
  CanvasEdge({
    required this.id,
    required this.boardId,
    required this.fromId,
    required this.toId,
    this.label,
    Map<String, dynamic>? data,
  }) : data = data ?? {};

  factory CanvasEdge.fromRow(Row r) => CanvasEdge(
        id: r['id'] as String,
        boardId: r['board_id'] as String,
        fromId: r['from_node'] as String,
        toId: r['to_node'] as String,
        label: r['label'] as String?,
        data: _json(r['data']),
      );

  final String id;
  final String boardId;
  final String fromId;
  final String toId;
  String? label;
  final Map<String, dynamic> data;

  EdgeArrow get arrow => _enum(EdgeArrow.values, data['arrow'], EdgeArrow.none);
  set arrow(EdgeArrow a) => data['arrow'] = a.name;

  bool get dashed => data['dashed'] == true;
  set dashed(bool v) => data['dashed'] = v;

  /// Linienfarbe (ARGB). null = Akzentfarbe.
  int? get color => data['color'] is int ? data['color'] as int : null;
  set color(int? v) {
    if (v == null) {
      data.remove('color');
    } else {
      data['color'] = v;
    }
  }

  CanvasEdge copy({String? id, String? fromId, String? toId}) => CanvasEdge(
        id: id ?? this.id,
        boardId: boardId,
        fromId: fromId ?? this.fromId,
        toId: toId ?? this.toId,
        label: label,
        data: Map<String, dynamic>.of(data),
      );
}
