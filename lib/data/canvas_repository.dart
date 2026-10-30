import 'package:sqlite3/sqlite3.dart';
import 'package:uuid/uuid.dart';

import 'models.dart';

/// Karten und Verbindungen auf Canvas-Flächen.
class CanvasRepository {
  CanvasRepository(this._db);

  final Database _db;
  static const _uuid = Uuid();

  int _now() => DateTime.now().millisecondsSinceEpoch;

  List<CanvasNode> nodes(String boardId) => [
        for (final r in _db.select(
            'SELECT * FROM canvas_nodes WHERE board_id = ? '
            'AND deleted_at IS NULL ORDER BY created_at',
            [boardId]))
          CanvasNode.fromRow(r)
      ];

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
      String text = ''}) {
    final id = _uuid.v4();
    final now = _now();
    _db.execute(
        'INSERT INTO canvas_nodes (id, board_id, x, y, w, h, text, '
        'created_at, updated_at) VALUES (?,?,?,?,?,?,?,?,?)',
        [id, boardId, x, y, w, h, text, now, now]);
    return CanvasNode(
        id: id, boardId: boardId, x: x, y: y, w: w, h: h, text: text);
  }

  void updateNode(CanvasNode n) => _db.execute(
      'UPDATE canvas_nodes SET x = ?, y = ?, w = ?, h = ?, text = ?, '
      'color = ?, ref_object_id = ?, updated_at = ? WHERE id = ?',
      [n.x, n.y, n.w, n.h, n.text, n.color, n.refObjectId, _now(), n.id]);

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
  CanvasEdge? createEdge(String boardId, String fromId, String toId) {
    if (fromId == toId) return null;
    final exists = _db.select(
        'SELECT 1 FROM canvas_edges WHERE deleted_at IS NULL AND '
        '((from_node = ? AND to_node = ?) OR (from_node = ? AND to_node = ?))',
        [fromId, toId, toId, fromId]);
    if (exists.isNotEmpty) return null;
    final id = _uuid.v4();
    final now = _now();
    _db.execute(
        'INSERT INTO canvas_edges (id, board_id, from_node, to_node, '
        'created_at, updated_at) VALUES (?,?,?,?,?,?)',
        [id, boardId, fromId, toId, now, now]);
    return CanvasEdge(id: id, boardId: boardId, fromId: fromId, toId: toId);
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
