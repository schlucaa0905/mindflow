import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:uuid/uuid.dart';

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
  });

  factory TextItem.fromRow(Row r) {
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

  Map<String, dynamic> get data =>
      {'text': text, 'size': size, 'color': color, 'bold': bold};

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
      );
}

/// Speichert Textfelder. Meldet Änderungen pro Besitzer nicht einzeln –
/// die offene Seite hält ihre Liste selbst und schreibt nur durch.
class TextRepository extends ChangeNotifier {
  TextRepository(this._db);

  final Database _db;
  static const _uuid = Uuid();

  int _now() => DateTime.now().millisecondsSinceEpoch;

  List<TextItem> items(String ownerId) => [
        for (final r in _db.select(
            "SELECT * FROM page_items WHERE owner_id = ? AND kind = 'text' "
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

  void _insert(TextItem item) {
    final now = _now();
    _db.execute(
        'INSERT INTO page_items (id, owner_id, kind, x, y, w, h, data, '
        "created_at, updated_at) VALUES (?, ?, 'text', ?, ?, ?, 0, ?, ?, ?)",
        [
          item.id,
          item.ownerId,
          item.x,
          item.y,
          item.w,
          jsonEncode(item.data),
          now,
          now
        ]);
  }

  void update(TextItem item, {bool notify = true}) {
    _db.execute(
        'UPDATE page_items SET x = ?, y = ?, w = ?, data = ?, updated_at = ? '
        'WHERE id = ?',
        [item.x, item.y, item.w, jsonEncode(item.data), _now(), item.id]);
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
