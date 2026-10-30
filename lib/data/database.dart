import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

/// Die lokale Datenbank. Sie ist die einzige Datenquelle der App;
/// die Cloud (Phase 6) gleicht später nur noch ab.
///
/// Regeln für alle Tabellen (wichtig für die spätere Synchronisation):
/// - `id` ist eine UUID und ändert sich nie.
/// - `created_at` / `updated_at` in Millisekunden.
/// - Löschen setzt nur `deleted_at` (Papierkorb), nichts verschwindet sofort.
class AppDatabase {
  AppDatabase._(this.raw);

  final Database raw;

  static Future<AppDatabase> open() async {
    final base = await getApplicationSupportDirectory();
    final dir = Directory('${base.path}${Platform.pathSeparator}mindflow');
    await dir.create(recursive: true);
    final db = sqlite3.open('${dir.path}${Platform.pathSeparator}mindflow.db');
    return AppDatabase._(db)..migrate();
  }

  /// Für Tests: Datenbank nur im Arbeitsspeicher.
  factory AppDatabase.inMemory() =>
      AppDatabase._(sqlite3.openInMemory())..migrate();

  void migrate() {
    raw.execute('PRAGMA journal_mode = WAL');
    final version = raw.userVersion;
    if (version < 1) {
      for (final sql in _schemaV1) {
        raw.execute(sql);
      }
      raw.userVersion = 1;
    }
    if (version < 2) {
      for (final sql in _schemaV2) {
        raw.execute(sql);
      }
      raw.userVersion = 2;
    }
    if (version < 3) {
      for (final sql in _schemaV3) {
        raw.execute(sql);
      }
      raw.userVersion = 3;
    }
  }

  void dispose() => raw.dispose();
}

const _schemaV1 = <String>[
  // Alles, was verknüpfbar ist: Notizbücher, Seiten, Canvas-Flächen,
  // später Wissenseinträge, Dokumente, Karteikarten.
  '''
  CREATE TABLE objects (
    id          TEXT PRIMARY KEY,
    type        TEXT NOT NULL,
    title       TEXT NOT NULL DEFAULT '',
    parent_id   TEXT,
    position    REAL NOT NULL DEFAULT 0,
    data        TEXT NOT NULL DEFAULT '{}',
    pinned      INTEGER NOT NULL DEFAULT 0,
    archived    INTEGER NOT NULL DEFAULT 0,
    created_at  INTEGER NOT NULL,
    updated_at  INTEGER NOT NULL,
    opened_at   INTEGER,
    deleted_at  INTEGER
  )
  ''',
  'CREATE INDEX idx_objects_parent ON objects(parent_id, position)',
  'CREATE INDEX idx_objects_type ON objects(type, updated_at)',
  // Das Rückgrat des Systems: Verbindungen zwischen beliebigen Objekten.
  '''
  CREATE TABLE links (
    id          TEXT PRIMARY KEY,
    source_id   TEXT NOT NULL,
    target_id   TEXT NOT NULL,
    type        TEXT NOT NULL DEFAULT 'related',
    label       TEXT,
    created_at  INTEGER NOT NULL,
    updated_at  INTEGER NOT NULL,
    deleted_at  INTEGER
  )
  ''',
  'CREATE INDEX idx_links_source ON links(source_id)',
  'CREATE INDEX idx_links_target ON links(target_id)',
  // Karten auf einer Canvas-Fläche. ref_object_id kann später auf einen
  // Wissenseintrag, eine Seite oder ein PDF zeigen.
  '''
  CREATE TABLE canvas_nodes (
    id            TEXT PRIMARY KEY,
    board_id      TEXT NOT NULL,
    x             REAL NOT NULL,
    y             REAL NOT NULL,
    w             REAL NOT NULL,
    h             REAL NOT NULL,
    text          TEXT NOT NULL DEFAULT '',
    color         INTEGER,
    ref_object_id TEXT,
    created_at    INTEGER NOT NULL,
    updated_at    INTEGER NOT NULL,
    deleted_at    INTEGER
  )
  ''',
  'CREATE INDEX idx_nodes_board ON canvas_nodes(board_id)',
  '''
  CREATE TABLE canvas_edges (
    id          TEXT PRIMARY KEY,
    board_id    TEXT NOT NULL,
    from_node   TEXT NOT NULL,
    to_node     TEXT NOT NULL,
    label       TEXT,
    created_at  INTEGER NOT NULL,
    updated_at  INTEGER NOT NULL,
    deleted_at  INTEGER
  )
  ''',
  'CREATE INDEX idx_edges_board ON canvas_edges(board_id)',
  'CREATE TABLE settings (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
];

/// Version 2: Textfelder (mit der Tastatur geschrieben) auf Seiten,
/// PDF-Seiten und Canvas-Flächen. `owner_id` ist dieselbe ID, unter der
/// auch die Handschrift gespeichert ist.
const _schemaV2 = <String>[
  '''
  CREATE TABLE page_items (
    id          TEXT PRIMARY KEY,
    owner_id    TEXT NOT NULL,
    kind        TEXT NOT NULL DEFAULT 'text',
    x           REAL NOT NULL,
    y           REAL NOT NULL,
    w           REAL NOT NULL,
    h           REAL NOT NULL DEFAULT 0,
    data        TEXT NOT NULL DEFAULT '{}',
    created_at  INTEGER NOT NULL,
    updated_at  INTEGER NOT NULL,
    deleted_at  INTEGER
  )
  ''',
  'CREATE INDEX idx_items_owner ON page_items(owner_id)',
];

/// Version 3: Gestaltung von Canvas-Karten und Verbindungen
/// (Art, Schriftgröße, Pfeile, gestrichelt …) als JSON.
const _schemaV3 = <String>[
  "ALTER TABLE canvas_nodes ADD COLUMN data TEXT NOT NULL DEFAULT '{}'",
  "ALTER TABLE canvas_edges ADD COLUMN data TEXT NOT NULL DEFAULT '{}'",
];
