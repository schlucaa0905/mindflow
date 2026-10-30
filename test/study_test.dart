import 'package:flutter_test/flutter_test.dart';
import 'package:mindflow/data/card_generator.dart';
import 'package:mindflow/data/database.dart';
import 'package:mindflow/data/models.dart';
import 'package:mindflow/data/object_repository.dart';
import 'package:mindflow/data/srs.dart';
import 'package:mindflow/data/study_repository.dart';
import 'package:mindflow/data/text_repository.dart';

void main() {
  final now = DateTime(2026, 10, 30, 12);

  group('Wiederholungsplan', () {
    test('Neue Karte: Gut → 1 Tag, dann 3 Tage, dann wachsend', () {
      var s = const CardSchedule();
      expect(s.isNew, isTrue);
      expect(s.isDue(now), isTrue);
      s = schedule(s, Rating.good, now);
      expect(s.interval, 1);
      expect(s.due, now.add(const Duration(days: 1)));
      s = schedule(s, Rating.good, now);
      expect(s.interval, 3);
      s = schedule(s, Rating.good, now);
      expect(s.interval, 8); // 3 × 2,5 = 7,5 → 8
      expect(s.reps, 3);
      expect(s.isDue(now), isFalse);
    });

    test('Nochmal: Abstand von vorn, Leichtigkeit sinkt, Fehler zählt', () {
      var s = schedule(const CardSchedule(), Rating.good, now);
      s = schedule(s, Rating.good, now);
      final before = s.ease;
      s = schedule(s, Rating.again, now);
      expect(s.interval, 0);
      expect(s.reps, 0);
      expect(s.lapses, 1);
      expect(s.ease, closeTo(before - 0.2, 1e-9));
      expect(s.due!.difference(now).inMinutes, 1);
    });

    test('Leichtigkeit fällt nie unter 1,3', () {
      var s = const CardSchedule();
      for (var i = 0; i < 20; i++) {
        s = schedule(s, Rating.again, now);
      }
      expect(s.ease, CardSchedule.minEase);
      expect(s.isDifficult, isTrue);
    });

    test('Leicht wächst schneller als Gut, Schwer langsamer', () {
      final base = schedule(
          schedule(const CardSchedule(), Rating.good, now), Rating.good, now);
      final hard = schedule(base, Rating.hard, now).interval;
      final good = schedule(base, Rating.good, now).interval;
      final easy = schedule(base, Rating.easy, now).interval;
      expect(hard, lessThan(good));
      expect(good, lessThan(easy));
    });

    test('Sehr lange Abstände laufen nicht über', () {
      var s = const CardSchedule(ease: 5, interval: 36500, reps: 9);
      s = schedule(s, Rating.easy, now);
      expect(s.interval, 36500);
      s = schedule(s, Rating.hard, now);
      expect(s.interval, 36500);
    });

    test('Kaputte gespeicherte Werte werden abgefangen', () {
      final s = CardSchedule.fromJson(
          {'ease': 'x', 'interval': -5, 'reps': 2.0, 'due': 'gestern'});
      expect(s.ease, 2.5);
      expect(s.interval, 0);
      expect(s.reps, 2);
      expect(s.due, isNull);
    });

    test('Vorschau-Texte', () {
      const s = CardSchedule();
      expect(previewLabel(s, Rating.again, now), '1 Min.');
      expect(previewLabel(s, Rating.good, now), '1 T.');
      expect(previewLabel(s, Rating.easy, now), '4 T.');
    });
  });

  group('Karten aus Text', () {
    test('erkennt Begriff: Erklärung und Aufzählungen', () {
      final cards = cardsFromText('''
Netzwerktechnik
- DHCP: vergibt IP-Adressen automatisch
• DNS – übersetzt Namen in IP-Adressen
1. HTTP = Protokoll für Webseiten
Quelle: https://example.org
TCP:verbindungsorientiert
''');
      expect(cards.map((c) => c.front).toList(),
          ['DHCP', 'DNS', 'HTTP', 'Quelle', 'TCP']);
      expect(cards.first.back, 'vergibt IP-Adressen automatisch');
      expect(cards[1].back, 'übersetzt Namen in IP-Adressen');
    });

    test('überspringt vorhandene und doppelte Begriffe', () {
      final cards = cardsFromText('A: 1\nB: 2\na: 3',
          skipFronts: {'B'});
      expect(cards.map((c) => c.front).toList(), ['A']);
    });

    test('ignoriert URLs als Begriff und leere Seiten', () {
      expect(cardsFromText('https://x.de: test\n: leer\nleer:'), isEmpty);
      expect(cardsFromText('www.x.de - Seite'), isEmpty);
      expect(cardsFromText('HTTPS: verschlüsseltes HTTP').single.front, 'HTTPS');
    });
  });

  group('Lernsets in der Datenbank', () {
    late AppDatabase db;
    late ObjectRepository objects;
    late StudyRepository study;

    setUp(() {
      db = AppDatabase.inMemory();
      objects = ObjectRepository(db.raw);
      study = StudyRepository(db.raw, objects);
    });
    tearDown(() => db.dispose());

    test('Karten gehören zum Wissenseintrag und sind sofort fällig', () {
      final entry = objects.create(type: ObjectType.knowledge, title: 'DHCP');
      study.create(front: 'Was macht DHCP?', back: 'IPs vergeben', entryId: entry.id);
      study.create(front: 'Port?', back: '67/68', entryId: entry.id);
      study.create(front: 'Frei', back: 'ohne Eintrag');
      expect(study.cardsOf(entry.id).length, 2);
      expect(study.allCards().length, 3);
      expect(study.dueCards(DateTime.now()).length, 3);
      final decks = study.decks();
      expect(decks.map((d) => d.title), containsAll(['DHCP', 'Freie Karten']));
    });

    test('Antworten verschiebt die Fälligkeit, Statistik stimmt', () {
      final c = study.create(front: 'F', back: 'A');
      final t = DateTime.now();
      study.answer(c.id, Rating.good, now: t);
      expect(study.dueCards(t).length, 0);
      expect(study.dueCards(t.add(const Duration(days: 2))).length, 1);
      final stats = study.stats(t);
      expect(stats.total, 1);
      expect(stats.due, 0);
      expect(stats.fresh, 0);
      study.reset(c.id);
      expect(study.card(c.id)!.schedule.isNew, isTrue);
    });

    test('Karten eines gelöschten Eintrags zählen nicht mehr', () {
      final entry = objects.create(type: ObjectType.knowledge, title: 'X');
      study.create(front: 'F', back: 'A', entryId: entry.id);
      expect(study.allCards().length, 1);
      objects.trash(entry.id);
      expect(study.allCards(), isEmpty);
      objects.restore(entry.id);
      expect(study.allCards().length, 1);
    });

    test('Bearbeiten und Löschen', () {
      final c = study.create(front: 'alt', back: 'a');
      study.edit(c.id, front: 'neu', back: 'b');
      expect(study.card(c.id)!.front, 'neu');
      expect(study.card(c.id)!.back, 'b');
      study.delete(c.id);
      expect(study.allCards(), isEmpty);
    });

    test('Karteikarten werden gefunden', () {
      study.create(front: 'Subnetzmaske', back: 'trennt Netz und Host');
      expect(objects.search('subnetz').length, 1);
      expect(objects.search('Host').length, 1);
    });
  });

  group('Textfelder', () {
    late AppDatabase db;
    late TextRepository texts;

    setUp(() {
      db = AppDatabase.inMemory();
      texts = TextRepository(db.raw);
    });
    tearDown(() => db.dispose());

    test('Anlegen, ändern, löschen, wiederherstellen', () {
      final t = texts.create(ownerId: 'seite-1', x: 10, y: 20, w: 200);
      t.text = 'Hallo Welt';
      t.size = 24;
      t.bold = true;
      texts.update(t);
      final loaded = texts.items('seite-1').single;
      expect(loaded.id, t.id);
      expect(loaded.text, 'Hallo Welt');
      expect(loaded.size, 24);
      expect(loaded.bold, isTrue);
      texts.delete(t.id);
      expect(texts.items('seite-1'), isEmpty);
      texts.restore(t.id);
      expect(texts.items('seite-1').length, 1);
    });

    test('Seite duplizieren kopiert Textfelder mit neuer ID', () {
      final t = texts.create(ownerId: 'a', x: 0, y: 0, w: 100, text: 'Hi');
      texts.duplicateAll('a', 'b');
      final copy = texts.items('b').single;
      expect(copy.text, 'Hi');
      expect(copy.id, isNot(t.id));
      expect(texts.items('a').length, 1);
    });

    test('Suche findet Text und liefert Ausschnitt', () {
      texts.create(
          ownerId: 'p1', x: 0, y: 0, w: 100, text: 'Das OSI-Modell hat 7 Schichten');
      texts.create(ownerId: 'p2', x: 0, y: 0, w: 100, text: 'nichts');
      final hits = texts.search('osi');
      expect(hits.length, 1);
      expect(hits.first.ownerId, 'p1');
      expect(hits.first.snippet, contains('OSI'));
    });

    test('Datenbank ist auf Version 2', () {
      expect(db.raw.userVersion, 2);
    });
  });
}
