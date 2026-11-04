import 'dart:convert';

import 'dart:ui' show Rect, TextAlign;
import 'package:flutter/foundation.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:uuid/uuid.dart';

/// Schriftart eines Textfelds.
enum TextFont {
  sans('Standard'),
  serif('Serif'),
  mono('Mono'),
  rounded('Rund');

  const TextFont(this.label);
  final String label;
}

/// Hintergrund eines Textfelds.
enum TextBackground {
  none('Ohne'),
  marker('Textmarker'),
  box('Kasten'),
  note('Notiz');

  const TextBackground(this.label);
  final String label;
}

/// Ein Textfeld auf einer Seite (mit der Tastatur geschrieben).
/// Koordinaten in Welt- bzw. Seiten-Punkten, wie die Handschrift.
class TextItem {
  TextItem({
    required this.id,
    required this.ownerId,
    required this.x,
    required this.y,
    required this.w,
    required this.text,
    required this.size,
    required this.color,
    this.bold = false,
    this.italic = false,
    this.underline = false,
    this.font = TextFont.sans,
    this.align = TextAlign.left,
    this.background = TextBackground.none,
    this.lineHeight,
    this.kind = 'text',
    this.h = 0,
    this.file,
  });

  /// Ein eingefügtes Bild (liegt unter der Handschrift).
  factory TextItem.image(
          {required String id,
          required String ownerId,
          required double x,
          required double y,
          required double w,
          required double h,
          required String file}) =>
      TextItem(
          id: id,
          ownerId: ownerId,
          x: x,
          y: y,
          w: w,
          text: '',
          size: 18,
          color: 0,
          kind: 'image',
          h: h,
          file: file);

  /// Ein Link: Fläche auf der Seite, die zu [target] führt
  /// (`page:<Seiten-ID>` oder `obj:<Objekt-ID>`).
  factory TextItem.link(
          {required String id,
          required String ownerId,
          required Rect rect,
          required String target}) =>
      TextItem(
          id: id,
          ownerId: ownerId,
          x: rect.left,
          y: rect.top,
          w: rect.width,
          text: '',
          size: 18,
          color: 0,
          kind: 'link',
          h: rect.height,
          file: target);

  /// Gespeicherte Form (gleiche Schlüssel wie die Datenbank-Zeile).
  Map<String, dynamic> toJson() => {
        'id': id,
        'owner_id': ownerId,
        'kind': kind,
        'x': x,
        'y': y,
        'w': w,
        'h': h,
        'data': jsonEncode(data),
      };

  factory TextItem.fromRow(Map<String, dynamic> r) {
    Map<String, dynamic> data;
    try {
      data = (jsonDecode(r['data'] as String) as Map).cast<String, dynamic>();
    } catch (_) {
      data = const {};
    }
    final size = data['size'];
    final color = data['color'];
    return TextItem(
      id: r['id'] as String,
      ownerId: r['owner_id'] as String,
      x: (r['x'] as num).toDouble(),
      y: (r['y'] as num).toDouble(),
      w: (r['w'] as num).toDouble(),
      text: (data['text'] as String?) ?? '',
      size: size is num ? size.toDouble().clamp(6, 120).toDouble() : 18,
      color: color is int ? color : 0xFF1C1C22,
      bold: data['bold'] == true,
      italic: data['italic'] == true,
      underline: data['underline'] == true,
      font: TextFont.values.firstWhere((f) => f.name == data['font'],
          orElse: () => TextFont.sans),
      align: switch (data['align']) {
        'center' => TextAlign.center,
        'right' => TextAlign.right,
        _ => TextAlign.left,
      },
      background: TextBackground.values.firstWhere(
          (b) => b.name == data['bg'],
          orElse: () => TextBackground.none),
      lineHeight: data['lh'] is num ? (data['lh'] as num).toDouble() : null,
      kind: r['kind'] as String,
      h: (r['h'] as num).toDouble(),
      file: data['file'] as String?,
    );
  }

  final String id;
  final String ownerId;
  double x;
  double y;

  /// Breite des Textfelds; die Höhe ergibt sich aus dem Text.
  double w;
  String text;
  double size;
  int color;
  bool bold;
  bool italic;
  bool underline;
  TextFont font;
  TextAlign align;
  TextBackground background;

  /// 'text', 'image' oder 'link'.
  final String kind;
  bool get isImage => kind == 'image';
  bool get isLink => kind == 'link';
  bool get isText => kind == 'text';

  /// Höhe (nur Bilder; Text richtet sich nach dem Inhalt).
  double h;

  /// Bilddatei im App-Ordner (Bilder) bzw. Linkziel (Links).
  final String? file;

  /// Zeilenabstand in Seiten-Punkten, wenn der Text an den Linien bzw.
  /// Kästchen des Papiers ausgerichtet ist (sonst null).
  double? lineHeight;

  Map<String, dynamic> get data => {
        'text': text,
        'size': size,
        'color': color,
        'bold': bold,
        if (italic) 'italic': true,
        if (underline) 'underline': true,
        if (font != TextFont.sans) 'font': font.name,
        if (align != TextAlign.left)
          'align': align == TextAlign.center ? 'center' : 'right',
        if (background != TextBackground.none) 'bg': background.name,
        if (lineHeight != null) 'lh': lineHeight,
        if (file != null) 'file': file,
      };

  TextItem copy({String? id, String? ownerId, double dx = 0, double dy = 0}) =>
      TextItem(
        id: id ?? this.id,
        ownerId: ownerId ?? this.ownerId,
        x: x + dx,
        y: y + dy,
        w: w,
        text: text,
        size: size,
        color: color,
        bold: bold,
        italic: italic,
        underline: underline,
        font: font,
        align: align,
        background: background,
        lineHeight: lineHeight,
        kind: kind,
        h: h,
        file: file,
      );
}

/// Speichert Textfelder. Meldet Änderungen pro Besitzer nicht einzeln –
/// die offene Seite hält ihre Liste selbst und schreibt nur durch.
class TextRepository extends ChangeNotifier {
  TextRepository(this._db);

  final Database _db;
  static const _uuid = Uuid();

  int _now() => DateTime.now().millisecondsSinceEpoch;

  /// Alle Textfelder und Bilder einer Seite.
  List<TextItem> items(String ownerId) => [
        for (final r in _db.select(
            'SELECT * FROM page_items WHERE owner_id = ? '
            'AND deleted_at IS NULL ORDER BY created_at',
            [ownerId]))
          TextItem.fromRow(r)
      ];

  TextItem create({
    required String ownerId,
    required double x,
    required double y,
    required double w,
    String text = '',
    double size = 18,
    int color = 0xFF1C1C22,
    bool bold = false,
  }) {
    final item = TextItem(
      id: _uuid.v4(),
      ownerId: ownerId,
      x: x,
      y: y,
      w: w,
      text: text,
      size: size,
      color: color,
      bold: bold,
    );
    _insert(item);
    notifyListeners();
    return item;
  }

  void _insert(TextItem item) => upsert(item);

  /// Speichert ein Element – neu oder geändert, auch ein gelöschtes zurück.
  void upsert(TextItem item) {
    final now = _now();
    _db.execute(
        'INSERT INTO page_items (id, owner_id, kind, x, y, w, h, data, '
        'created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?) '
        'ON CONFLICT(id) DO UPDATE SET owner_id = excluded.owner_id, '
        'x = excluded.x, y = excluded.y, w = excluded.w, h = excluded.h, '
        'data = excluded.data, updated_at = excluded.updated_at, '
        'deleted_at = NULL',
        [
          item.id, item.ownerId, item.kind, item.x, item.y, item.w, item.h,
          jsonEncode(item.data), now, now
        ]);
  }

  /// Neue ID für kopierte Elemente.
  String newId() => _uuid.v4();

  void update(TextItem item, {bool notify = true}) {
    _db.execute(
        'UPDATE page_items SET x = ?, y = ?, w = ?, h = ?, data = ?, '
        'updated_at = ? WHERE id = ?',
        [item.x, item.y, item.w, item.h, jsonEncode(item.data), _now(), item.id]);
    if (notify) notifyListeners();
  }

  void delete(String id, {bool notify = true}) {
    final now = _now();
    _db.execute(
        'UPDATE page_items SET deleted_at = ?, updated_at = ? WHERE id = ?',
        [now, now, id]);
    if (notify) notifyListeners();
  }

  /// Gelöschtes Textfeld zurückholen (Rückgängig).
  void restore(String id) {
    _db.execute(
        'UPDATE page_items SET deleted_at = NULL, updated_at = ? WHERE id = ?',
        [_now(), id]);
    notifyListeners();
  }

  /// Alle Textfelder eines Besitzers kopieren (z. B. Seite duplizieren).
  void duplicateAll(String fromOwner, String toOwner) {
    for (final t in items(fromOwner)) {
      _insert(t.copy(id: _uuid.v4(), ownerId: toOwner));
    }
    notifyListeners();
  }

  /// Volltextsuche über alle Textfelder. Liefert (Besitzer-ID, Ausschnitt).
  List<({String ownerId, String snippet})> search(String query,
      {int limit = 40}) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return const [];
    final out = <({String ownerId, String snippet})>[];
    final seen = <String>{};
    for (final r in _db.select(
        "SELECT owner_id, data FROM page_items WHERE kind = 'text' "
        'AND deleted_at IS NULL ORDER BY updated_at DESC')) {
      String text;
      try {
        text = ((jsonDecode(r['data'] as String) as Map)['text'] as String?) ?? '';
      } catch (_) {
        continue;
      }
      final i = text.toLowerCase().indexOf(q);
      if (i < 0) continue;
      final owner = r['owner_id'] as String;
      if (!seen.add(owner)) continue;
      final start = (i - 30).clamp(0, text.length).toInt();
      final end = (i + q.length + 50).clamp(0, text.length).toInt();
      out.add((
        ownerId: owner,
        snippet: '${start > 0 ? '…' : ''}${text.substring(start, end).replaceAll('\n', ' ')}${end < text.length ? '…' : ''}',
      ));
      if (out.length >= limit) break;
    }
    return out;
  }
}
