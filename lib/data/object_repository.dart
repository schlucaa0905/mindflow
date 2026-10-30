import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:uuid/uuid.dart';

import 'models.dart';

/// Lesen und Schreiben von Objekten und Verknüpfungen.
/// Meldet jede Änderung, damit offene Listen sich aktualisieren.
class ObjectRepository extends ChangeNotifier {
  ObjectRepository(this._db);

  final Database _db;
  static const _uuid = Uuid();

  int _now() => DateTime.now().millisecondsSinceEpoch;

  List<MfObject> _query(String sql, [List<Object?> params = const []]) =>
      [for (final r in _db.select(sql, params)) MfObject.fromRow(r)];

  static const _active = 'deleted_at IS NULL AND archived = 0';

  // --- Lesen ------------------------------------------------------------

  MfObject? get(String id) {
    final list = _query('SELECT * FROM objects WHERE id = ?', [id]);
    return list.isEmpty ? null : list.first;
  }

  List<MfObject> byType(ObjectType type) => _query(
      'SELECT * FROM objects WHERE type = ? AND $_active '
      'ORDER BY updated_at DESC',
      [type.name]);

  List<MfObject> children(String parentId) => _query(
      'SELECT * FROM objects WHERE parent_id = ? AND deleted_at IS NULL '
      'ORDER BY position',
      [parentId]);

  int childCount(String parentId) => _db.select(
      'SELECT COUNT(*) AS n FROM objects WHERE parent_id = ? '
      'AND deleted_at IS NULL',
      [parentId]).first['n'] as int;

  /// Zuletzt geöffnete Notizbücher und Canvas-Flächen.
  List<MfObject> recent({int limit = 8}) => _query(
      "SELECT * FROM objects WHERE type IN ('notebook','board','document') "
      'AND $_active ORDER BY COALESCE(opened_at, updated_at) DESC LIMIT ?',
      [limit]);

  List<MfObject> pinned() => _query(
      'SELECT * FROM objects WHERE pinned = 1 AND $_active '
      'ORDER BY title COLLATE NOCASE');

  List<MfObject> archivedItems() => _query(
      'SELECT * FROM objects WHERE archived = 1 AND deleted_at IS NULL '
      'AND parent_id IS NULL ORDER BY updated_at DESC');

  List<MfObject> trashed() => _query(
      'SELECT * FROM objects WHERE deleted_at IS NOT NULL '
      "AND type IN ('notebook','board','document','knowledge') "
      'ORDER BY deleted_at DESC');

  /// Alle vergebenen Kategorien eines Typs, alphabetisch.
  List<String> categories(ObjectType type) {
    final set = <String>{};
    for (final o in byType(type)) {
      if (o.category.isNotEmpty) set.add(o.category);
    }
    return set.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  }

  List<MfObject> search(String text) {
    final q = text.trim();
    if (q.isEmpty) return [];
    final like = '%${_escapeLike(q)}%';
    // Titel aller Hauptobjekte; bei Wissenseinträgen auch der Text.
    return _query(
        "SELECT * FROM objects WHERE type IN ('notebook','board','document',"
        "'knowledge') AND deleted_at IS NULL AND (title LIKE ? ESCAPE ? "
        "OR (type = 'knowledge' AND data LIKE ? ESCAPE ?)) "
        'ORDER BY archived, updated_at DESC LIMIT 60',
        [like, r'\', like, r'\']);
  }

  // --- Schreiben --------------------------------------------------------

  MfObject create({
    required ObjectType type,
    String title = '',
    String? parentId,
    double? position,
    Map<String, dynamic> data = const {},
  }) {
    final id = _uuid.v4();
    final now = _now();
    final pos = position ?? _nextPosition(parentId);
    _db.execute(
        'INSERT INTO objects (id, type, title, parent_id, position, data, '
        'created_at, updated_at, opened_at) VALUES (?,?,?,?,?,?,?,?,?)',
        [id, type.name, title, parentId, pos, jsonEncode(data), now, now, now]);
    notifyListeners();
    return get(id)!;
  }

  double _nextPosition(String? parentId) {
    final r = _db.select(
        'SELECT COALESCE(MAX(position), 0) AS p FROM objects '
        'WHERE parent_id IS ?',
        [parentId]);
    return (r.first['p'] as num).toDouble() + 1;
  }

  /// Position direkt hinter [after] (Bruchzahl: kein Umnummerieren nötig).
  double positionAfter(MfObject after) {
    final r = _db.select(
        'SELECT MIN(position) AS p FROM objects WHERE parent_id IS ? '
        'AND deleted_at IS NULL AND position > ?',
        [after.parentId, after.position]);
    final next = r.first['p'] as num?;
    return next == null ? after.position + 1 : (after.position + next) / 2;
  }

  void _update(String id, String setSql, List<Object?> params,
      {bool touch = true}) {
    final sets = touch ? '$setSql, updated_at = ?' : setSql;
    _db.execute('UPDATE objects SET $sets WHERE id = ?',
        [...params, if (touch) _now(), id]);
    notifyListeners();
  }

  void rename(String id, String title) => _update(id, 'title = ?', [title]);

  void setPinned(String id, bool v) =>
      _update(id, 'pinned = ?', [v ? 1 : 0]);

  void setArchived(String id, bool v) =>
      _update(id, 'archived = ?', [v ? 1 : 0]);

  void setData(String id, Map<String, dynamic> data) =>
      _update(id, 'data = ?', [jsonEncode(data)]);

  void setPosition(String id, double position) =>
      _update(id, 'position = ?', [position]);

  void trash(String id) => _update(id, 'deleted_at = ?', [_now()]);

  void restore(String id) =>
      _update(id, 'deleted_at = NULL, archived = 0', const []);

  void markOpened(String id) =>
      _update(id, 'opened_at = ?', [_now()], touch: false);

  /// Inhalt wurde geändert (z. B. Handschrift gespeichert).
  void touch(String id) {
    _db.execute(
        'UPDATE objects SET updated_at = ? WHERE id = ?', [_now(), id]);
    notifyListeners();
  }

  /// Tauscht die Reihenfolge zweier Geschwister.
  void swapPositions(MfObject a, MfObject b) {
    _db.execute('UPDATE objects SET position = ? WHERE id = ?',
        [b.position, a.id]);
    _db.execute('UPDATE objects SET position = ? WHERE id = ?',
        [a.position, b.id]);
    notifyListeners();
  }

  // --- Verknüpfungen (Grundlage für Knowledge, Phase 5) -----------------

  String link(String sourceId, String targetId, {String type = 'related'}) {
    final id = _uuid.v4();
    final now = _now();
    _db.execute(
        'INSERT INTO links (id, source_id, target_id, type, created_at, '
        'updated_at) VALUES (?,?,?,?,?,?)',
        [id, sourceId, targetId, type, now, now]);
    notifyListeners();
    return id;
  }

  /// Sind zwei Objekte schon verbunden (egal in welche Richtung)?
  bool isLinked(String a, String b) => _db.select(
      'SELECT 1 FROM links WHERE deleted_at IS NULL AND '
      '((source_id = ? AND target_id = ?) OR (source_id = ? AND target_id = ?))',
      [a, b, b, a]).isNotEmpty;

  /// Verbindet zwei Objekte nur, wenn sie noch nicht verbunden sind.
  void linkOnce(String a, String b, {String type = 'related'}) {
    if (a == b || isLinked(a, b)) return;
    link(a, b, type: type);
  }

  /// Löst die Verbindung zweier Objekte (als Grabstein).
  void unlink(String a, String b) {
    final now = _now();
    _db.execute(
        'UPDATE links SET deleted_at = ?, updated_at = ? WHERE deleted_at IS NULL '
        'AND ((source_id = ? AND target_id = ?) OR (source_id = ? AND target_id = ?))',
        [now, now, a, b, b, a]);
    notifyListeners();
  }

  /// Alle verbundenen, nicht gelöschten Objekte.
  List<MfObject> linkedObjects(String id) {
    final out = <MfObject>[];
    for (final other in linkedIds(id)) {
      final o = get(other);
      if (o != null && o.deletedAt == null) out.add(o);
    }
    return out;
  }

  /// IDs aller Objekte, die mit [id] verbunden sind (beide Richtungen).
  List<String> linkedIds(String id) => [
        for (final r in _db.select(
            'SELECT target_id AS o FROM links WHERE source_id = ? '
            'AND deleted_at IS NULL UNION '
            'SELECT source_id AS o FROM links WHERE target_id = ? '
            'AND deleted_at IS NULL',
            [id, id]))
          r['o'] as String
      ];

  // --- Einstellungen ----------------------------------------------------

  String? setting(String key) {
    final r = _db.select('SELECT value FROM settings WHERE key = ?', [key]);
    return r.isEmpty ? null : r.first['value'] as String;
  }

  void setSetting(String key, String value) => _db.execute(
      'INSERT INTO settings (key, value) VALUES (?, ?) '
      'ON CONFLICT(key) DO UPDATE SET value = excluded.value',
      [key, value]);
}

String _escapeLike(String s) => s
    .replaceAll(r'\', r'\\')
    .replaceAll('%', r'\%')
    .replaceAll('_', r'\_');
