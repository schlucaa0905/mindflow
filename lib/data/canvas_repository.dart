import 'dart:convert';

import 'package:sqlite3/sqlite3.dart';
import 'package:uuid/uuid.dart';

import 'models.dart';

/// Karten und Verbindungen auf Canvas-Flächen.
class CanvasRepository {
  CanvasRepository(this._db);

  final Database _db;
  static const _uuid = Uuid();

  int _now() => DateTime.now().millisecondsSinceEpoch;

  /// Alle Karten, hinten liegende zuerst.
  List<CanvasNode> nodes(String boardId) {
    final list = [
      for (final r in _db.select(
          'SELECT * FROM canvas_nodes WHERE board_id = ? '
          'AND deleted_at IS NULL ORDER BY created_at',
          [boardId]))
        CanvasNode.fromRow(r)
    ];
    // Stabil nach Ebene sortieren (gleiche Ebene: Erstellreihenfolge).
    final indexed = list.asMap().entries.toList()
      ..sort((a, b) {
        final c = a.value.z.compareTo(b.value.z);
        return c != 0 ? c : a.key.compareTo(b.key);
      });
    return [for (final e in indexed) e.value];
  }

  List<CanvasEdge> edges(String boardId) => [
        for (final r in _db.select(
            'SELECT * FROM canvas_edges WHERE board_id = ? '
            'AND deleted_at IS NULL',
            [boardId]))
          CanvasEdge.fromRow(r)
      ];

  CanvasNode createNode(String boardId,
      {required double x,
      required double y,
      double w = 220,
      double h = 110,
      String text = '',
      int? color,
      String? refObjectId,
      Map<String, dynamic>? data}) {
    final node = CanvasNode(
      id: _uuid.v4(),
      boardId: boardId,
      x: x,
      y: y,
      w: w,
      h: h,
      text: text,
      color: color,
      refObjectId: refObjectId,
      data: data == null ? null : Map<String, dynamic>.of(data),
    );
    _insertNode(node);
    return node;
  }

  void _insertNode(CanvasNode n) {
    final now = _now();
    _db.execute(
        'INSERT INTO canvas_nodes (id, board_id, x, y, w, h, text, color, '
        'ref_object_id, data, created_at, updated_at) '
        'VALUES (?,?,?,?,?,?,?,?,?,?,?,?)',
        [
          n.id, n.boardId, n.x, n.y, n.w, n.h, n.text, n.color,
          n.refObjectId, jsonEncode(n.data), now, now
        ]);
  }

  /// Neue ID für kopierte Karten.
  String newId() => _uuid.v4();

  void updateNode(CanvasNode n) => _db.execute(
      'UPDATE canvas_nodes SET x = ?, y = ?, w = ?, h = ?, text = ?, '
      'color = ?, ref_object_id = ?, data = ?, updated_at = ? WHERE id = ?',
      [
        n.x, n.y, n.w, n.h, n.text, n.color, n.refObjectId,
        jsonEncode(n.data), _now(), n.id
      ]);

  /// Eine (kopierte) Karte mit vorgegebener ID speichern.
  void insertNode(CanvasNode n) => _insertNode(n);

  /// Löscht eine Karte samt ihrer Verbindungen (als Grabstein).
  void deleteNode(String id) {
    final now = _now();
    _db.execute(
        'UPDATE canvas_nodes SET deleted_at = ?, updated_at = ? WHERE id = ?',
        [now, now, id]);
    _db.execute(
        'UPDATE canvas_edges SET deleted_at = ?, updated_at = ? '
        'WHERE (from_node = ? OR to_node = ?) AND deleted_at IS NULL',
        [now, now, id, id]);
  }

  /// Legt eine Verbindung an – oder gibt null zurück, wenn es sie schon gibt.
  CanvasEdge? createEdge(String boardId, String fromId, String toId,
      {Map<String, dynamic>? data}) {
    if (fromId == toId) return null;
    final exists = _db.select(
        'SELECT 1 FROM canvas_edges WHERE deleted_at IS NULL AND '
        '((from_node = ? AND to_node = ?) OR (from_node = ? AND to_node = ?))',
        [fromId, toId, toId, fromId]);
    if (exists.isNotEmpty) return null;
    final id = _uuid.v4();
    final now = _now();
    final e = CanvasEdge(
        id: id,
        boardId: boardId,
        fromId: fromId,
        toId: toId,
        data: data == null ? null : Map<String, dynamic>.of(data));
    _db.execute(
        'INSERT INTO canvas_edges (id, board_id, from_node, to_node, data, '
        'created_at, updated_at) VALUES (?,?,?,?,?,?,?)',
        [id, boardId, fromId, toId, jsonEncode(e.data), now, now]);
    return e;
  }

  void updateEdge(CanvasEdge e) => _db.execute(
      'UPDATE canvas_edges SET label = ?, data = ?, updated_at = ? WHERE id = ?',
      [e.label, jsonEncode(e.data), _now(), e.id]);

  /// Setzt eine Fläche auf einen früheren Stand zurück (Rückgängig).
  /// Karten und Verbindungen, die im Stand fehlen, werden gelöscht;
  /// alle anderen werden wiederhergestellt bzw. überschrieben.
  void restoreState(
      String boardId, List<CanvasNode> nodes, List<CanvasEdge> edges) {
    final now = _now();
    _db.execute('BEGIN');
    try {
      _db.execute(
          'UPDATE canvas_nodes SET deleted_at = ?, updated_at = ? '
          'WHERE board_id = ? AND deleted_at IS NULL',
          [now, now, boardId]);
      _db.execute(
          'UPDATE canvas_edges SET deleted_at = ?, updated_at = ? '
          'WHERE board_id = ? AND deleted_at IS NULL',
          [now, now, boardId]);
      for (final n in nodes) {
        _db.execute(
            'INSERT INTO canvas_nodes (id, board_id, x, y, w, h, text, color, '
            'ref_object_id, data, created_at, updated_at, deleted_at) '
            'VALUES (?,?,?,?,?,?,?,?,?,?,?,?,NULL) '
            'ON CONFLICT(id) DO UPDATE SET x = excluded.x, y = excluded.y, '
            'w = excluded.w, h = excluded.h, text = excluded.text, '
            'color = excluded.color, ref_object_id = excluded.ref_object_id, '
            'data = excluded.data, updated_at = excluded.updated_at, '
            'deleted_at = NULL',
            [
              n.id, boardId, n.x, n.y, n.w, n.h, n.text, n.color,
              n.refObjectId, jsonEncode(n.data), now, now
            ]);
      }
      for (final e in edges) {
        _db.execute(
            'INSERT INTO canvas_edges (id, board_id, from_node, to_node, '
            'label, data, created_at, updated_at, deleted_at) '
            'VALUES (?,?,?,?,?,?,?,?,NULL) '
            'ON CONFLICT(id) DO UPDATE SET label = excluded.label, '
            'data = excluded.data, updated_at = excluded.updated_at, '
            'deleted_at = NULL',
            [
              e.id, boardId, e.fromId, e.toId, e.label, jsonEncode(e.data),
              now, now
            ]);
      }
      _db.execute('COMMIT');
    } catch (_) {
      _db.execute('ROLLBACK');
      rethrow;
    }
  }

  void deleteEdge(String id) {
    final now = _now();
    _db.execute(
        'UPDATE canvas_edges SET deleted_at = ?, updated_at = ? WHERE id = ?',
        [now, now, id]);
  }

  /// Karten, deren Text den Suchbegriff enthält.
  List<CanvasNode> searchNodes(String text) {
    final q = text.trim();
    if (q.isEmpty) return [];
    return [
      for (final r in _db.select(
          'SELECT n.* FROM canvas_nodes n JOIN objects o ON o.id = n.board_id '
          'WHERE n.deleted_at IS NULL AND o.deleted_at IS NULL '
          "AND n.text LIKE ? ESCAPE '\\' LIMIT 50",
          ['%${q.replaceAll(r'\', r'\\').replaceAll('%', r'\%').replaceAll('_', r'\_')}%']))
        CanvasNode.fromRow(r)
    ];
  }
}
