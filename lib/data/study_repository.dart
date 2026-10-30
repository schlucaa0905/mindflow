import 'package:sqlite3/sqlite3.dart';

import 'models.dart';
import 'object_repository.dart';
import 'srs.dart';

/// Eine Karteikarte (gespeichert als Objekt vom Typ `flashcard`).
///
/// - `parentId` zeigt auf den Wissenseintrag, zu dem sie gehört
///   (oder ist leer bei freien Karten).
/// - Vorder- und Rückseite sowie der Lernstand liegen im `data`-Feld.
class Flashcard {
  Flashcard(this.object)
      : front = (object.data['front'] as String?) ?? object.title,
        back = (object.data['back'] as String?) ?? '',
        schedule = CardSchedule.fromJson(object.data);

  final MfObject object;
  final String front;
  final String back;
  final CardSchedule schedule;

  String get id => object.id;
  String? get entryId => object.parentId;
}

/// Ein Lernset = alle Karten eines Wissenseintrags.
class StudyDeck {
  StudyDeck({required this.entry, required this.cards});

  /// null = „Freie Karten“ ohne Wissenseintrag.
  final MfObject? entry;
  final List<Flashcard> cards;

  String get title => entry?.displayTitle ?? 'Freie Karten';

  int due(DateTime now) => cards.where((c) => c.schedule.isDue(now)).length;
  int get difficult => cards.where((c) => c.schedule.isDifficult).length;
}

/// Kennzahlen für Home und Lernbereich.
class StudyStats {
  const StudyStats({
    required this.total,
    required this.due,
    required this.fresh,
    required this.learned,
    required this.difficult,
  });

  final int total;
  final int due;

  /// Noch nie gelernt.
  final int fresh;

  /// Mindestens einmal richtig mit Abstand ≥ 3 Tage.
  final int learned;
  final int difficult;

  double get progress => total == 0 ? 0 : learned / total;
}

/// Karteikarten lesen, anlegen und nach dem Lernen planen.
/// Schreiben läuft über [ObjectRepository], damit alle Listen
/// automatisch aktualisiert werden.
class StudyRepository {
  StudyRepository(this._db, this._objects);

  final Database _db;
  final ObjectRepository _objects;

  /// Alle aktiven Karten. Karten eines gelöschten oder archivierten
  /// Wissenseintrags zählen nicht mit.
  List<Flashcard> allCards() {
    final rows = _db.select(
        'SELECT c.* FROM objects c LEFT JOIN objects p ON p.id = c.parent_id '
        "WHERE c.type = 'flashcard' AND c.deleted_at IS NULL "
        'AND c.archived = 0 AND (c.parent_id IS NULL OR '
        '(p.id IS NOT NULL AND p.deleted_at IS NULL AND p.archived = 0)) '
        'ORDER BY c.position');
    return [for (final r in rows) Flashcard(MfObject.fromRow(r))];
  }

  List<Flashcard> cardsOf(String entryId) => [
        for (final o in _objects.children(entryId))
          if (o.type == ObjectType.flashcard && !o.archived) Flashcard(o)
      ];

  Flashcard? card(String id) {
    final o = _objects.get(id);
    if (o == null || o.type != ObjectType.flashcard) return null;
    return Flashcard(o);
  }

  /// Fällige Karten, die am längsten überfälligen zuerst, neue zuletzt.
  List<Flashcard> dueCards(DateTime now, {String? entryId}) {
    final list = (entryId == null ? allCards() : cardsOf(entryId))
        .where((c) => c.schedule.isDue(now))
        .toList();
    list.sort((a, b) {
      final da = a.schedule.due, db = b.schedule.due;
      if (da == null && db == null) return 0;
      if (da == null) return 1;
      if (db == null) return -1;
      return da.compareTo(db);
    });
    return list;
  }

  List<StudyDeck> decks() {
    final byEntry = <String?, List<Flashcard>>{};
    for (final c in allCards()) {
      byEntry.putIfAbsent(c.entryId, () => []).add(c);
    }
    final out = <StudyDeck>[];
    for (final e in byEntry.entries) {
      final entry = e.key == null ? null : _objects.get(e.key!);
      out.add(StudyDeck(entry: entry, cards: e.value));
    }
    out.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    return out;
  }

  StudyStats stats(DateTime now) {
    final cards = allCards();
    return StudyStats(
      total: cards.length,
      due: cards.where((c) => c.schedule.isDue(now)).length,
      fresh: cards.where((c) => c.schedule.isNew).length,
      learned: cards
          .where((c) => c.schedule.reps > 0 && c.schedule.interval >= 3)
          .length,
      difficult: cards.where((c) => c.schedule.isDifficult).length,
    );
  }

  Flashcard create({
    required String front,
    required String back,
    String? entryId,
  }) {
    final o = _objects.create(
      type: ObjectType.flashcard,
      title: front.trim(),
      parentId: entryId,
      data: {'front': front.trim(), 'back': back.trim()},
    );
    return Flashcard(o);
  }

  void edit(String id, {required String front, required String back}) {
    final o = _objects.get(id);
    if (o == null) return;
    _objects.setData(id, {...o.data, 'front': front.trim(), 'back': back.trim()});
    if (o.title != front.trim()) _objects.rename(id, front.trim());
  }

  void delete(String id) => _objects.trash(id);

  /// Antwort speichern und nächste Fälligkeit berechnen.
  CardSchedule answer(String id, Rating r, {DateTime? now}) {
    final o = _objects.get(id);
    if (o == null) return const CardSchedule();
    final next = schedule(CardSchedule.fromJson(o.data), r, now ?? DateTime.now());
    _objects.setData(id, {...o.data, ...next.toJson()});
    return next;
  }

  /// Lernstand einer Karte zurücksetzen.
  void reset(String id) {
    final o = _objects.get(id);
    if (o == null) return;
    final data = Map<String, dynamic>.from(o.data)
      ..remove('ease')
      ..remove('interval')
      ..remove('reps')
      ..remove('lapses')
      ..remove('due');
    _objects.setData(id, data);
  }
}
