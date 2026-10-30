# MindFlow

*Your thoughts. Connected.*

Version 0.1 – Fundament, Notizbuch und Infinite Canvas.

## Was drin ist

**Fundament**
- Lokale Datenbank (SQLite) mit stabilen IDs für alles. Umbenennen oder Verschieben bricht nie eine Verbindung.
- Tabelle für Verknüpfungen zwischen beliebigen Objekten (Grundlage für Knowledge).
- Papierkorb statt endgültigem Löschen. Alles lässt sich wiederherstellen.
- Designsystem mit hellem und dunklem Modus (Umschalter unten in der Seitenleiste).
- Navigation: Seitenleiste auf iPad quer und Windows, untere Leiste auf iPhone bzw. schmalen Fenstern.

**Bereiche**
- **Home:** Begrüßung, Schnellaktionen, Angeheftet, Zuletzt geöffnet, alle Bereiche.
- **Notizbuch:** Notizbücher mit Umschlagfarbe, Papier (hell/dunkel) und Vorlage. Seiten im A4-Format, blättern, hinzufügen, duplizieren, verschieben, löschen, Vorlage pro Seite (blanko, liniert, kariert, Punktraster).
- **Canvas:** Unendliche Fläche mit vier Modi: Schreiben, Auswählen, Verbinden, Navigieren. Textkarten anlegen (auch per Doppeltippen), verschieben, bearbeiten, löschen. Verbindungen ziehen; dieselben Karten nochmal verbinden löst die Verbindung. Alles wird dauerhaft gespeichert.
- **Suche:** Titel von Notizbüchern und Canvas sowie der Text aller Karten. Ein Treffer springt direkt zur Karte.
- **Archiv:** Archivierte Inhalte und Papierkorb, jeweils mit „Wiederherstellen“.
- **Lernen:** Platzhalter mit Plan, kommt in Phase 7.

**Handschrift** (wie in Phase 0 getestet): Druck, Glättung, Textmarker, Radierer, Rückgängig, Handballen-Schutz, „Nur Stift“ schaltet sich automatisch ein, sobald ein Stift erkannt wird.

## Neu in 0.5 – noch mehr Goodnotes

- Kopfleiste ist fest oben und wird nie mehr von der Seite verdeckt.
- Seiten wechseln durch Wischen mit einem Finger (Notizbuch und PDF), mit Gleit-Animation.
- Textmarker: am Ende kurz halten → gerade Linie, das Ende lässt sich danach noch ausrichten.
- Strichstärken: drei Plätze, deutlich unterschiedlich. Gewählten Platz nochmal antippen → Regler mit Vorschau, Wert wird gemerkt.
- Füller etwas kräftiger, damit Stärken sichtbar unterschiedlich sind.
- Aussehen nachträglich ändern: Notizbuch (Paletten-Symbol oben) und Canvas (Titel antippen). Beim Wechsel zwischen dunklem und hellem Papier werden die Schriftfarben auf Wunsch angepasst.
- Canvas: Übersichtskarte unten rechts (antippen/ziehen zum Springen) und „Zu deinen Inhalten“, wenn nichts mehr im Bild ist.
- Fehler behoben: erkannte Formen bekamen manchmal einen zusätzlichen Punkt am Ende.

## Neu in 0.4 – Goodnotes-Gefühl, Dokumente, Wissen

**Editor (Notizbuch, PDF, Canvas)**
- Neue Kopfleiste im Goodnotes-Stil: oben Navigation (zurück, Titel, Seiten „‹ 3 / 12 ›“, Rückgängig/Wiederholen, Seitenübersicht, Seite hinzufügen, Menü „…“), darunter die Werkzeuge.
- Modernes Design: Werkzeuge in einer Kapsel, gewähltes Werkzeug farbig gefüllt, Farben als Kreise, Strichstärken als Punkte.
- Leiste lösbar (Symbol ganz rechts oder „…“ → „Werkzeugleiste frei verschiebbar“), zurück per Ziehen an den oberen Rand.
- Geschrieben wird nur noch auf dem Blatt. Außerhalb verschiebt der Stift die Ansicht.
- Seitenübersicht mit echten Vorschaubildern, Seiten sortieren, duplizieren, löschen, Vorlage ändern.
- Notizbuch als PDF teilen/speichern.
- Lasso: Schon ein kleiner Teil eines Strichs genügt (wie Goodnotes 6).

**Dokumente (PDF)**
- PDF importieren (Startseite, „Neu“ oder Bereich Dokumente), Seiten lesen, mit allen Werkzeugen hineinschreiben und markieren.
- Seitenübersicht, Wissenseintrag zum Dokument, mit Notizen als PDF teilen.
- Das Original bleibt unverändert, Anmerkungen liegen darüber.

**Wissen**
- Einträge mit Unterthemen (Baum), Text, Tags, Suche im Titel und Text.
- Verknüpfungen zu allem: andere Einträge, Notizbuchseiten, PDFs, Canvas. Rückverweise erscheinen automatisch.
- Notizbuch „…“ → „Wissenseintrag aus Seite“ verknüpft den Eintrag mit der Seite.
- Eintrag „Auf einen Canvas legen“ und im Canvas „Wissen, PDF oder Notizbuch einfügen“ (Verweis-Karten, Doppeltippen öffnet das Ziel).
- Zwei verbundene Verweis-Karten verknüpfen auch die Einträge dahinter.

## Neu in 0.3 – Werkzeuge auf Goodnotes-Niveau

**Werkzeugleiste**
- Am Griff (⋮⋮) ziehen: an einen Rand (oben, unten, links, rechts) andocken oder frei schweben lassen. Einklappbar. Position wird gemerkt.
- Alle Werkzeug-Einstellungen gelten app-weit und bleiben nach dem Neustart erhalten.

**Stifte**
- Füller, Kugelschreiber, Pinselstift (starker Druckeffekt, spitze Enden)
- Lieblingsstifte: im Stift-Menü speichern, erscheinen direkt in der Leiste
- Formerkennung: Form zeichnen und Stift kurz halten → Linie, Kreis, Ellipse, Rechteck, Dreieck oder Vieleck
- Farbe lange drücken (Windows: Rechtsklick) → Palette anpassen

**Textmarker:** liegt immer hinter der Schrift, optional „gerade Linien“
**Radierer:** ganze Striche oder Bereich, „nur Textmarker“, „danach zurück zum vorigen Werkzeug“
**Lasso:** verschieben, skalieren (Griff unten rechts), ausschneiden, kopieren, einfügen (auch in andere Seiten/Notizbücher/Canvas), duplizieren, umfärben, löschen
**Formen:** Linie, Pfeil, Rechteck, Ellipse, Dreieck
**Laserpointer:** leuchtende Linie zum Zeigen, verschwindet von selbst, wird nie gespeichert

**Gesten & Tastatur**
- 2 Finger tippen = rückgängig, 3 Finger tippen = wiederholen
- Tasten: P Stift, H Textmarker, E Radierer, L Lasso, S Formen, R Laser
- Strg+Z / Strg+Y, Strg+C / X / V / D für die Auswahl, Entf löscht, Esc hebt auf
- Notizbuch: Bild auf / Bild ab bzw. Alt+Pfeil zum Blättern

## Neu in 0.2

- **Notizbuch anlegen:** Live-Vorschau, 14 Umschlagfarben, 6 Umschlag-Designs, Papier Dunkel/Weiß/Creme, Format A4 hoch/quer/quadratisch, 8 Vorlagen mit Mini-Vorschau (u. a. Cornell, Aufgaben, Kariert klein), Kategorie/Fach.
- **Notizbuch-Übersicht:** echte Umschläge, Filter und Gruppen nach Kategorie, „Umschlag & Einstellungen“ nachträglich änderbar.
- **Zoom im Notizbuch:** nur bis kurz unter Seitengröße heraus, bis 600 % hinein, Seite bleibt immer im Bild.
- **Werkzeuge** (gewähltes Werkzeug nochmal antippen = Optionen):
  - Stift: Füller (druckabhängig) oder Kugelschreiber (gleichmäßig), Strichstärke stufenlos
  - Textmarker mit eigener Breite
  - Radierer: ganze Striche oder nur berührte Stellen, Größe einstellbar, Kreis zeigt die Größe
  - Lasso: einkreisen → verschieben, löschen, duplizieren, umfärben (Farbe antippen)
  - Formen: Linie, Pfeil, Rechteck, Ellipse
  - Eigene Farben über den Farbwähler

## Noch nicht drin (nächste Runden)

Lasso, Formen, Textfelder und Bilder im Notizbuch · Karten mit Wissenseinträgen verknüpfen · Ordner · Cloud-Sync · Texterkennung für Handschrift-Suche.

## Neue Version aufs iPad bringen

1. Geänderte Dateien in deinen `mindflow`-Ordner kopieren (alte ersetzen).
2. GitHub Desktop: unten links kurze Beschreibung eintippen → **Commit to main** → oben **Push origin**.
3. GitHub baut automatisch (Actions). Nach dem grünen Haken: Lauf öffnen → **Summary** → unten **Artifacts** → `MindFlow-ipa`.
4. Mit Sideloadly installieren wie gewohnt.

**Hinweis:** Die neue Version nutzt eine Datenbank. Notizen aus dem Stift-Test (Phase 0) werden nicht übernommen.

## Auf Windows starten

```bash
flutter create --org de.mindflow --project-name mindflow --platforms=windows .
flutter pub get
flutter run -d windows
```

Voraussetzung: Flutter, Visual Studio 2022 mit „Desktopentwicklung mit C++“ und der Windows-Entwicklermodus (siehe offizielle Flutter-Anleitung).

Die automatischen Tests laufen bei jedem Build auf GitHub. Lokal unter Windows brauchen die Datenbank-Tests eine `sqlite3.dll`; die App selbst bringt SQLite mit.

## Aufbau des Codes

```
lib/
  main.dart                 Start: Datenbank öffnen, App starten
  app/                      Rahmen der App
    theme.dart              Design-Tokens (hell/dunkel), Papierfarben
    services.dart           Zentrale Dienste (Datenbank, Repositories, Thema)
    sections.dart           Die 8 Hauptbereiche
    shell.dart              Seitenleiste bzw. mobile Navigation
    navigation.dart         Öffnet jedes Objekt über seine ID
  data/                     Datenschicht
    database.dart           SQLite-Schema und Migrationen
    models.dart             Objekt, Karte, Verbindung
    object_repository.dart  Notizbücher, Seiten, Canvas, Links, Papierkorb
    canvas_repository.dart  Karten und Verbindungen
  ink/                      Handschrift-Engine (überall gleich)
    ink_surface.dart        Fertige Schreibfläche inkl. Laden/Speichern
    ink_toolbar.dart        Werkzeugleiste
    ink_session.dart        Automatisches, absturzsicheres Speichern
    …                       Striche, Kamera, Rendering, Rückgängig
  features/                 Die Bereiche
    home/  notebook/  canvas/  search/  archive/  common/
  storage/ink_store.dart    Handschrift-Dateien pro Objekt-ID
  ui/widgets.dart           Wiederverwendbare Bausteine
test/                       Automatische Tests (Daten, Handschrift, App-Start)
```

**Wichtige Entscheidungen**
- **Ein gemeinsames Objekt-Modell:** Notizbuch, Seite und Canvas liegen in einer Tabelle und haben alle eine feste ID. Später kommen Wissenseinträge, Dokumente und Karteikarten dazu, ohne dass sich etwas Bestehendes ändert.
- **Handschrift als Datei pro Objekt:** Striche sind viele kleine Zahlen. In einer kompakten Datei pro Seite sind sie schneller und kleiner als in der Datenbank. Die Datei heißt wie die ID des Objekts.
- **Papier statt App-Thema:** Jedes Notizbuch und jeder Canvas hat sein eigenes Papier. So wird weiße Schrift nie unsichtbar, wenn du auf den hellen Modus wechselst.
