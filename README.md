# MindFlow

*Your thoughts. Connected.*

Version 0.9 – Bilder, Ordner, Tabs, Sicherung, Quiz und Wissensnetz.

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
- **Lernen:** Karteikarten mit Wiederholungsplan (wie Anki), Lernsets pro Wissenseintrag, Fortschritt auf Home.

**Handschrift** (wie in Phase 0 getestet): Druck, Glättung, Textmarker, Radierer, Rückgängig, Handballen-Schutz, „Nur Stift“ schaltet sich automatisch ein, sobald ein Stift erkannt wird.

## Neu in 0.9.6 – Links, Elemente, Mindmap, Bereiche, geteilte Ansicht

- **Elemente-Bibliothek**: Lasso-Auswahl → „Als Element“ speichert Striche, Text und Bilder; einfügen über „Elemente“ in der Lasso-Leiste oder „+“ → „Element einfügen“ (Notizbuch, PDF, Canvas).
- **Links**: Lasso-Auswahl → „Verlinken“ mit einer Seite dieses Notizbuchs oder einem Notizbuch, PDF, Canvas oder Wissenseintrag. Antippen (Finger, kurz mit dem Stift oder im Lesemodus) öffnet das Ziel. Links lassen sich mit dem Lasso verschieben und löschen.
- **Seiten benennen und Inhaltsverzeichnis** („…“ → Inhaltsverzeichnis; benannte Seiten und Lesezeichen).
- **Eigene Vorlagen**: Seite → „Als Vorlage speichern“; auswählbar unter „Seite gestalten“ (lange drücken entfernt sie).
- **Druckempfindlichkeit** einstellbar (Stift nochmal antippen).
- **Mindmap auf dem Canvas**: Unterthema (Tab), Nachbarthema (Umschalt + Enter) – auch als Knöpfe an der Karte – und „Als Mindmap anordnen“.
- **Bereiche**: benannte Ausschnitte im Navigator (Kompass), hinspringen, umbenennen, anpassen – und „Bereiche präsentieren“ mit Vor/Zurück.
- **Canvas teilen**: aktuelle Ansicht, ganzer Canvas oder ein Bereich als Bild (PNG) oder PDF.
- **Zwei Inhalte nebeneinander** („…“ → „Daneben öffnen“): Trennlinie verschiebbar, Griff in der Mitte zum Tauschen oder Schließen.
- **Automatische Sicherung** (Archiv): täglich, wöchentlich (Standard) oder monatlich als ZIP in der Dateien-App unter „Auf meinem iPad › MindFlow › Sicherungen“; die letzten 3 bleiben.
- **Globale Suche findet auch Text in PDFs** (beim ersten Mal werden die PDFs einmal eingelesen).

## Neu in 0.9.5 – PDFs wie in Chrome, Seiten frei gestalten

- PDFs werden jetzt mit PDFium dargestellt (dem PDF-Programmteil von Chrome): Formularfelder, ausgefüllte Werte und Anmerkungen sind sichtbar – bearbeitbare PDFs bleiben nicht mehr leer.
- Suche im PDF findet auch den gedruckten Text (bei gescannten PDFs ohne Text nur deine Textfelder).
- Links im PDF: mit dem Finger antippen öffnet die Webseite bzw. springt zur Zielseite.
- „Seite gestalten …“ (im „…“-Menü, im „+“-Menü und im Seitenmenü): Vorlage mit Vorschaubildern, Abstand der Linien/Kästchen (eng, normal, weit – getippter Text dockt passend an), Blattfarbe aus 22 Farben oder jede eigene Farbe (z. B. für Plakate) – für diese Seite oder alle Seiten, auf Wunsch auch für neue Seiten. Wird das Blatt dunkel bzw. hell, werden die Schriftfarben auf Wunsch angepasst.
- „Notizbuch bearbeiten“: Bei neuer Vorlage wird gefragt, ob sie auch für die vorhandenen Seiten gelten soll.
- Hinweis: Formularfelder direkt im PDF ausfüllen ist mit der verwendeten PDF-Technik nicht möglich – zum Ausfüllen Textfelder (T) auf die Felder setzen; sie kommen mit in den PDF-Export.

## Neu in 0.9.4 – Canvas-Schreibfehler behoben

- Canvas: Weit herausgezoomt waren neue Striche winzig dünn (praktisch unsichtbar) – es sah aus, als ginge Schreiben nicht mehr. Auf der unendlichen Fläche richtet sich die Strichstärke jetzt nach dem Bildschirm (wie in Goodnotes-Whiteboards); in Notizbüchern und PDFs bleibt sie fest wie auf Papier.
- Schreibfläche robuster: Ging beim Zoomen das Abheben eines Fingers oder des Stifts verloren, konnte das Schreiben blockieren – das wird jetzt beim nächsten Aufsetzen des Stifts automatisch bereinigt.

## Neu in 0.9.3 – Linien, Favoriten, Pipette & mehr

- Gerade Linien rasten beim Ziehen, Zeichnen und Textmarker-Halten bei 0°, 90°, 180°, 270° (und 45°-Schritten) ein – nur ganz nah dran (±2°), 40° bleibt also 40°. Winkel und Länge werden angezeigt; angetippte Linie: ±1°-Knöpfe (halten = weiterdrehen), Gradzahl antippen zum Eintippen (z. B. 44 oder 89,5), Einrasten umschalten (aus / 90° / 45°+90°).
- Radierer: „Danach Stift“ (Standard an) – Stift hochnehmen, und es geht mit dem vorigen Stift weiter. Dazu „Nur Marker“ direkt in der Leiste.
- Lieblingsstifte (auch Textmarker) in der Leiste: Stern speichert, antippen wählt, lange drücken entfernt (mit Rückgängig).
- Zuletzt benutzte Farben neben den festen Farben, getrennt für Stift und Textmarker.
- Pipette: Farbe von Schrift, Formfüllung, Text, Bildern, PDF-Seiten oder Papier aufnehmen – mit Lupe; auch zum Umfärben einer Lasso-Auswahl.
- Lasso drehen: Griff unter der Auswahl, rastet ebenfalls ein, Winkel wird angezeigt (Textfelder und Bilder wandern mit, bleiben aber aufrecht).
- Seitenzahlen pro Notizbuch („…“ → Seitenzahlen): aus, „3“ oder „3 / 12“ – auch in Vorschau und PDF-Export.
- Glättung der Handschrift (Stift nochmal antippen): von „genau wie geschrieben“ bis „sehr ruhig“.
- Behoben: Fehler in der Seiten-Vorschau, der das Bauen verhindert hätte.

## Neu in 0.9.2 – Orientierung & Goodnotes-Bearbeitung

- Canvas: feste, einklappbare Übersichtskarte (antippen = hinfliegen), weiche Kamerafahrten, Navigator (Kompass-Knopf) mit gespeicherten Ansichten und durchsuchbarer Kartenliste, „Zu deinen Inhalten“ auch ganz weit draußen.
- Notizbuch & PDF: Seitenleiste mit Vorschauen (im Notizbuch per Ziehen sortierbar, mit Seitenmenü), Lesemodus (Auge), nach der letzten Seite weiterwischen legt eine neue an.
- Lineal in der Stift-Leiste: mit Fingern verschieben und drehen, Stift und Textmarker ziehen an der Kante gerade Linien.

## Neu in 0.9.1 – neue Startseite & Feinschliff

- Startseite neu: ruhiger Kopf mit Suche, großes „Weitermachen“, vier Schnell-Knöpfe, Regale für Angeheftetes und Zuletzt geöffnetes, kompakter Lernstand.
- Seitenleiste zeigt bei „Lernen“ die Zahl fälliger Karten.
- Notizbücher duplizieren (mit Seiten, Handschrift, Textfeldern, Bildern).
- Übersichten nach Datum oder Name sortieren.

## Neu in 0.9 – großes Funktions-Update

- **Bilder** aus Fotos oder Dateien in Notizbuch, PDF und Canvas einfügen. Sie liegen unter der Handschrift (man kann darauf schreiben) und kommen mit in Vorschau und PDF-Export.
- **Lasso erfasst Textfelder und Bilder**: verschieben, vergrößern, umfärben, duplizieren, kopieren/einfügen (auch auf andere Seiten), löschen – alles mit Rückgängig.
- **Lasso → Karteikarte**: die Auswahl wird als Bild zur Vorderseite einer Karte.
- **Füllfarbe für Formen** (Knopf in der Formen-Leiste; gilt für neue und die angetippte Form).
- **Ordner** (auch verschachtelt) für Notizbücher, Canvas und Dokumente; „In Ordner verschieben“ im Menü jeder Karte.
- **Tabs** wie bei Goodnotes: offene Dokumente oben, Startseite-Knopf, Tabs schließen.
- **Datensicherung** im Archiv: alles als eine ZIP-Datei sichern und wiederherstellen.
- **Vorlagen**: Notenlinien, Wochenplan, Koordinaten – und jede PDF-Seite als eigene Vorlage.
- **Suche im Dokument** (Lupe): Textfelder in Notizbuch und PDF, Karten und Textfelder auf dem Canvas.
- **Quiz** (Multiple Choice) aus Karteikarten – im Lernbereich oder pro Wissenseintrag.
- **Wissensnetz**: alle Wissenseinträge als Netz mit ihren Verbindungen (Knopf „Netz“ im Wissen).

## Neu in 0.8.5 – Text auf Linien und Kästchen

- Textfelder im Notizbuch sind frei platzierbar und docken wie ein Magnet an, sobald sie nah genug (ca. ein Drittel Kästchen) an einer Linie bzw. Kästchenkante sind – auch live beim Ziehen. Angedockt sitzt jede Schriftzeile genau auf einer Linie (liniert, Cornell, Aufgaben) bzw. in den Kästchen (kariert, Punktraster).
- Große Schrift belegt mehrere Linien/Kästchen. Gilt auch nach Verschieben, Größe oder Schriftart ändern, und im PDF-Export.

## Neu in 0.8.3 – Formen wie Goodnotes

- Formen-Werkzeug: frei Hand zeichnen, beim Abheben wird es zur perfekten Form (Linie, Kreis, Ellipse, Rechteck, Dreieck, Vieleck).
- Form oder Linie mit jedem Werkzeug antippen (Stift, Textmarker, Finger): Rahmen mit Griffen; daneben tippen kehrt zum vorherigen Werkzeug zurück. Handschrift bleibt davon unberührt.
- Griffe: Ecken/Kanten ziehen ändert die Größe, Linienenden einzeln versetzen, hineintippen und ziehen verschiebt. Entf löscht. Alles mit Rückgängig.

## Neu in 0.8.2 – Leisten wie Goodnotes 6

- Blaue Kopfleiste: links Zurück, Seitenübersicht, Lesezeichen; Mitte Lasso | Schreiben, Radierer, Text, Laser; rechts Seite, Zoom, Nur-Stift, Seite hinzufügen, Teilen, Präsentieren, Mehr.
- Schwebende Unterleiste über dem Blatt: Rückgängig/Wiederholen | Füller, Kugelschreiber, Pinsel, Textmarker, Formen | 3 Stärken | 3 Farben | +.

## Neu in 0.8.1 – Goodnotes-Leiste & feste Strichstärken

- Kopf- und Werkzeugleiste flach über die ganze Breite wie bei Goodnotes; Werkzeuge in Goodnotes-Reihenfolge (Stift, Radierer, Textmarker, Formen, Lasso, Text, Laser), daneben 3 Farben und 3 Stärken.
- Textfelder: ohne Rahmen, beim Bearbeiten dünner Rahmen mit Griff; dunkles Kontextmenü.
- Strichstärke gilt auf dem Blatt: Ein Strich ist gleich dick, egal bei welchem Zoom er geschrieben wurde.

## Neu in 0.8 – Canvas, Text und Kopfleiste ausgebaut

**Canvas-Karten**
- Fünf Kartenarten: Karte, Notizzettel, Überschrift, Kapsel, Kreis. Dazu 9 Farben plus eigene Farbe.
- Direkt auf der Karte schreiben (Doppeltippen oder Enter), ohne Dialog. Die Höhe passt sich dem Text an.
- Schwebende Leiste an der gewählten Karte: Farbe, Art, Schriftgröße, fett, zentriert, Aufgabenliste, duplizieren, kopieren, als Wissenseintrag, verknüpfen, nach vorne/hinten, löschen.
- „+“ an allen vier Seiten: neue, gleich verbundene Karte. Oder vom „+“ ziehen: zu einer Karte verbinden bzw. ins Leere ziehen für eine neue Karte.
- Größe ändern am Griff unten rechts. Aufgaben `[ ]` direkt auf der Karte abhaken.
- Verbindungen als weiche Kurven, mit Pfeil (keiner, einer, beide), gestrichelt, Farbe, Beschriftung und „Richtung umdrehen“. Verbindung antippen zum Bearbeiten.
- Rückgängig/Wiederholen auch für Karten. Kopieren und Einfügen zwischen verschiedenen Canvas-Flächen. Am Raster ausrichten.
- Tastatur: Enter, Esc, Tab (verbundene Karte), Pfeiltasten, Entf, Strg/⌘ + Z/Y/C/X/V/D.

**Textfelder (Tastatur)**
- Schriftarten Standard, Serif, Mono, Rund. Fett, kursiv, unterstrichen (auch Strg/⌘ + B/I/U).
- Ausrichtung links, mittig, rechts. Aufzählungen und Nummerierung laufen beim Enter automatisch weiter.
- Textfarbe, Hintergrund (Textmarker, Kasten, Notiz), duplizieren.

**Kopfleiste**
- Aufgeräumt in Gruppen, mit Symbol vor dem Titel.
- Zoom-Menü mit Prozentanzeige: ganze Seite, Seitenbreite, 100 %, 200 %.
- Schalter „Nur Stift / Finger schreibt mit“ direkt in der Leiste.
- Notizbuch: Lesezeichen, „Nächstes Lesezeichen“, „Zu Seite springen“, Einfügen-Menü (Seite davor/danach, duplizieren, Textfeld, Vorlage).
- PDF: Textfeld-Knopf, Zoom, „Zu Seite springen“.

## Neu in 0.7 – Neues Design, Textfelder, Lernen

**Design „Deep Space“**
- Fast schwarzes Blau mit violett-cyanfarbenen Verläufen und weichen Farbwolken im Hintergrund.
- Seitenleiste als schwebende Glasfläche mit neuem Logo, leuchtendem „Neu erstellen“-Knopf und Verlaufs-Markierung.
- Home neu: großer Begrüßungsbereich mit Kennzahlen, Schnellaktionen als Kacheln, Lernfortschritt als Ring.
- Editor-Kopfleiste als schwebende „Insel“ mit Lichtkante; gewählte Werkzeuge leuchten.
- Karten heben sich beim Berühren leicht an, Bereiche wechseln mit sanfter Überblendung.

**Mit der Tastatur schreiben**
- Neues Werkzeug „Text“ (T) in der Werkzeugleiste: aufs Blatt tippen → Textfeld → lostippen.
- Farbe und Größe (S/M/L/XL) wie bei den Stiften; kleine Leiste am Feld: verschieben, kleiner/größer, fett, löschen, fertig. Breite am violetten Griff rechts ändern.
- Textfelder gibt es in Notizbüchern, PDFs und auf dem Canvas. Sie landen im PDF-Export, in den Seiten-Vorschauen und in der globalen Suche.

**Lasso: Kopieren & Einfügen wie Goodnotes**
- Auswahl-Leiste jetzt mit Beschriftung: Kopieren, Ausschneiden, Duplizieren.
- Einfügen: Mit dem Lasso lange auf eine Stelle drücken – auch auf einer anderen Seite oder in einem anderen Notizbuch. Oder „Einfügen“ in der Leiste.

**Lernen**
- Karteikarten in jedem Wissenseintrag; „Aus dem Text“ erzeugt Karten automatisch aus Zeilen wie `DHCP: vergibt IP-Adressen`.
- Lernmodus mit Umdreh-Animation und Bewertung Nochmal / Schwer / Gut / Leicht (Tastatur: Leertaste, 1–4).
- Wiederholungsplan nach dem Anki-Prinzip: Gewusstes kommt seltener, Vergessenes bald wieder.

## Neu in 0.6 – Feinschliff & Präsentieren

- Neue Werkzeugleiste: gezeichnete Stifte wie in Goodnotes (Füller, Kugelschreiber, Pinsel, Textmarker, Radierer, Lasso, Formen, Laser). Die Spitze zeigt die aktuelle Farbe, das gewählte Werkzeug hebt sich an.
- Saubere, moderne Menüs überall („…“ im Editor, auf Karten, in der Seitenübersicht, im Wissen) – mit Symbolen, Gruppen und roten Lösch-Einträgen.
- Kopfleiste geordnet: Seitenübersicht | Rückgängig/Wiederholen | Neue Seite, Präsentieren, Menü.
- Präsentationsmodus (Symbol „Präsentieren“): nur das Blatt im Vollbild, kleine Steuerkapsel (Stift, Laser, Radierer, Rückgängig, Beenden), die fast unsichtbar wird. Zum Spiegeln per AirPlay/HDMI.
- Zoom-Anzeige („125 %“) beim Zoomen.
- Aus Goodnotes übernehmen: geführter Import über PDF-Export, mehrere PDFs auf einmal.

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

Bilder einfügen · Textfelder mit dem Lasso auswählen · Ordner · Cloud-Sync · Texterkennung für Handschrift-Suche · Goodnotes-Dateien direkt (nur nach Analyse einer Beispieldatei).

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
    canvas_repository.dart  Karten, Verbindungen, Rückgängig-Stände
    text_repository.dart    Textfelder (Tastatur) pro Seite
    study_repository.dart   Karteikarten, Lernsets, Statistik
    srs.dart                Wiederholungsplan (Anki-Prinzip)
    card_generator.dart     Karten aus „Begriff: Erklärung“-Zeilen
  ink/                      Handschrift-Engine (überall gleich)
    ink_surface.dart        Fertige Schreibfläche inkl. Laden/Speichern
    ink_toolbar.dart        Werkzeugleiste
    ink_session.dart        Automatisches, absturzsicheres Speichern
    text_layer.dart         Textfelder über der Handschrift
    list_formatter.dart     Aufzählungen beim Tippen fortsetzen
    …                       Striche, Kamera, Rendering, Rückgängig
  features/                 Die Bereiche
    home/  notebook/  canvas/  documents/  knowledge/  study/  search/  archive/  common/
  storage/ink_store.dart    Handschrift-Dateien pro Objekt-ID
  ui/widgets.dart           Wiederverwendbare Bausteine
  ui/futuristic.dart        Aurora-Hintergrund, Glas, Leuchtknöpfe, Fortschrittsring
test/                       Automatische Tests (Daten, Handschrift, App-Start)
```

**Wichtige Entscheidungen**
- **Ein gemeinsames Objekt-Modell:** Notizbuch, Seite und Canvas liegen in einer Tabelle und haben alle eine feste ID. Später kommen Wissenseinträge, Dokumente und Karteikarten dazu, ohne dass sich etwas Bestehendes ändert.
- **Handschrift als Datei pro Objekt:** Striche sind viele kleine Zahlen. In einer kompakten Datei pro Seite sind sie schneller und kleiner als in der Datenbank. Die Datei heißt wie die ID des Objekts.
- **Papier statt App-Thema:** Jedes Notizbuch und jeder Canvas hat sein eigenes Papier. So wird weiße Schrift nie unsichtbar, wenn du auf den hellen Modus wechselst.
