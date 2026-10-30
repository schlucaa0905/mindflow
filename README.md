# MindFlow – Phase 0: Stift-Test

*Your thoughts. Connected.*

Dieses Projekt ist der erste echte Baustein von MindFlow: die **Handschrift-Engine**.
Sie wird später von Notebook, Canvas und PDF-Anmerkungen gemeinsam genutzt.
Bevor wir darauf aufbauen, beantwortet dieser Test drei Fragen:

1. Schreibt der Apple Pencil auf dem iPad 9 flüssig und ohne spürbare Verzögerung?
2. Bleibt die Fläche mit 10.000 Strichen beim Zoomen und Verschieben flüssig?
3. Ist nach einem Neustart der App alles noch da?

Sind alle drei Antworten „ja“, bleiben wir bei Flutter und starten Phase 1.

---

## Was schon funktioniert

- Stift mit Druckempfindlichkeit, Glättung und drei Strichstärken
- Textmarker (halbtransparent), Radierer (ganze Striche)
- Fünf Stiftfarben, vier Markerfarben
- Rückgängig / Wiederholen (auch Strg+Z / Strg+Y)
- Unendliche Fläche: Verschieben und Zoomen (5 % bis 800 %)
- „Nur Stift“-Modus: Stift schreibt, Finger navigieren, Handballen wird beim Schreiben ignoriert
- Automatisches Speichern (absturzsicher) und Laden beim Start
- Leistungstest: erzeugt 10.000 Striche und fliegt 8 Sekunden über die Fläche, mit Messergebnis

**Bedienung**

| Gerät | Zeichnen | Verschieben | Zoomen |
|---|---|---|---|
| iPad (Nur Stift an) | Apple Pencil | 1 Finger | 2 Finger |
| iPad (Nur Stift aus) | Stift oder 1 Finger | – | 2 Finger |
| Windows, Maus | linke Taste | rechte oder mittlere Taste | Mausrad |
| Windows, Touchpad | Klicken + ziehen | 2 Finger | Pinch |

---

## Schritt 1 – Windows-Laptop einrichten (einmalig, ca. 1 Stunde)

1. **Git** installieren: <https://git-scm.com/download/win>
2. **Flutter** installieren nach der offiziellen Anleitung für Windows:
   <https://docs.flutter.dev/get-started/install/windows>
3. **Visual Studio 2022 Community** installieren und dabei die Arbeitslast
   **„Desktopentwicklung mit C++“** auswählen (nötig für die Windows-App).
4. **Entwicklermodus** in Windows einschalten
   (Einstellungen → Datenschutz und Sicherheit → Für Entwickler).
   Flutter braucht das für Plugins.
5. **VS Code** mit den Erweiterungen „Flutter“ und „Dart“ installieren.
6. Prüfen: in einem Terminal `flutter doctor` ausführen.
   Wichtig sind die Haken bei *Flutter* und *Visual Studio*.
   Android und Xcode dürfen fehlen.

## Schritt 2 – Projekt starten

Den Ordner `mindflow` entpacken, ein Terminal darin öffnen und:

```bash
# Erzeugt die Plattform-Ordner (ios/, windows/). Bestehende Dateien bleiben unverändert.
# "deinname" durch etwas Eigenes ersetzen, z. B. deinen Nachnamen.
flutter create --org de.deinname --project-name mindflow --platforms=ios,windows .

flutter pub get
flutter test           # alle Tests sollten grün sein
flutter run -d windows # startet die App
```

Für **aussagekräftige Leistungswerte** immer so starten:

```bash
flutter run -d windows --profile
```

Der normale Modus (Debug) ist absichtlich langsam und verfälscht die Messung.

## Schritt 3 – Auf das iPad bringen (kostenlos, ohne Mac)

Ablauf: **GitHub** baut die App auf einem Cloud-Mac → **Sideloadly** auf Windows
signiert sie mit deiner normalen Apple-ID → per USB-Kabel aufs iPad.

**Einschränkungen der kostenlosen Variante**
- Die App läuft **7 Tage**, danach mit Sideloadly einfach neu installieren (Daten bleiben erhalten).
- Höchstens 3 selbst installierte Apps gleichzeitig.
- Für unseren Test reicht das völlig. Ein kostenpflichtiges Konto braucht es erst
  für die Veröffentlichung oder später für bestimmte Cloud-Funktionen.

**Einmalig einrichten**
1. Kostenloses **GitHub**-Konto anlegen und das Projekt hochladen.
   Die Datei `.github/workflows/ios-unsigned.yml` liegt schon bei.
   *Öffentliches* Repository = unbegrenzt kostenlose Builds, aber der Code ist sichtbar.
   *Privates* Repository = begrenztes Gratis-Kontingent (Mac-Minuten zählen mehrfach),
   für gelegentliche Builds meist ausreichend – aktuelles Kontingent bei GitHub prüfen.
2. Auf Windows **iTunes** (von Apples Website, nicht aus dem Microsoft Store) und
   **Sideloadly** (<https://sideloadly.io>) installieren.
3. Auf dem iPad **Entwicklermodus** einschalten: Einstellungen → Datenschutz & Sicherheit
   → Entwicklermodus (erscheint evtl. erst nach dem ersten Installationsversuch).
4. Tipp: eine **zweite Apple-ID** nur für Sideloadly verwenden, nicht dein Hauptkonto.

**Jedes Mal, wenn du eine neue Version willst**
1. Auf GitHub → *Actions* → „iOS-App bauen (unsigniert)“ → *Run workflow*.
2. Nach ca. 10–20 Minuten unten bei *Artifacts* `MindFlow-ipa` herunterladen und entpacken.
3. iPad per Kabel anschließen, Sideloadly öffnen, die `.ipa` hineinziehen,
   Apple-ID eingeben, *Start*.
4. Auf dem iPad: Einstellungen → Allgemein → VPN & Geräteverwaltung →
   deiner Apple-ID vertrauen. Fertig.

So gebaute Apps sind Release-Builds, die Messwerte sind also echt.

*Hinweis:* `codemagic.yaml` ist nur für später, falls du doch ein kostenpflichtiges
Apple-Developer-Konto und TestFlight nutzen willst. Jetzt kannst du sie ignorieren.

## Schritt 4 – Den Test durchführen

Auf dem iPad 9 mit dem Apple Pencil:

| Prüfung | Bestanden, wenn … |
|---|---|
| Schreibgefühl | Eine Seite Notizen schreiben fühlt sich natürlich an, der Strich hängt nicht sichtbar hinter der Stiftspitze |
| Handballen | Beim Schreiben mit aufgelegter Hand verschiebt sich die Fläche nicht |
| Leistung | Leistungstest (Tacho-Symbol) meldet „Bestanden“: Ø ≤ 12 ms und höchstens 5 % langsame Bilder |
| Zoom | Mit 10.000 Strichen zoomen und verschieben fühlt sich ruckelfrei an |
| Speichern | App komplett beenden (aus dem App-Umschalter wischen), neu öffnen: alles ist da |
| Rückgängig | Zeichnen, radieren, mehrfach rückgängig und wiederholen ergibt das Erwartete |

Das Ergebnis des Leistungstests lässt sich mit „Kopieren“ in die Zwischenablage
übernehmen – schick es mir einfach, dann werten wir es zusammen aus.

---

## Aufbau des Codes

```
lib/
  main.dart                 Einstieg
  app/theme.dart            Farben und Design-Tokens (Anthrazit + Violett)
  ink/                      Die Handschrift-Engine (wird später überall genutzt)
    stroke.dart             Ein Strich: stabile ID, Punkte, Druck, Grabstein
    stroke_renderer.dart    Umriss mit druckabhängiger Breite berechnen und zeichnen
    ink_scene.dart          Alle Striche, aufgeteilt in räumliche Abschnitte
    live_stroke.dart        Der Strich, der gerade entsteht (eigene Ebene)
    camera.dart             Verschieben und Zoomen
    ink_history.dart        Rückgängig / Wiederholen
    ink_codec.dart          Kompaktes Binärformat (.mfink)
    ink_controller.dart     Verbindet alles; die Oberfläche spricht nur hiermit
    ink_canvas_view.dart    Eingabe (Stift, Finger, Maus, Trackpad) und Ebenen
  storage/ink_store.dart    Absturzsicheres Speichern auf dem Gerät
  spike/                    Nur für diesen Test (Werkzeugleiste, Messung)
test/ink_test.dart          Automatische Tests
```

**Die wichtigsten Entscheidungen, kurz erklärt**

- **Striche sind unveränderlich.** Radieren markiert einen Strich nur als gelöscht.
  Dadurch kann die spätere Synchronisation Änderungen von zwei Geräten
  zusammenführen, ohne dass etwas verloren geht.
- **Drei Zeichenebenen.** Raster, fertige Striche und der aktuelle Strich werden
  getrennt gemalt. Beim Schreiben wird nur der aktuelle Strich neu gezeichnet.
- **Räumliche Abschnitte.** Die Fläche ist in Felder von 1024 × 1024 Einheiten
  aufgeteilt. Jedes Feld wird einmal als fertiges Bild aufgezeichnet; beim
  Zoomen werden nur sichtbare Felder abgespielt.
- **Speichern im Hintergrund.** Das Umwandeln in Bytes läuft in einem eigenen
  Thread (Isolate), damit die Oberfläche dabei nicht hängt.

## Bekannte Grenzen dieses Tests

- Der Radierer löscht ganze Striche; ein „Pixel-Radierer“ kommt in Phase 2.
- Beim starken Herauszoomen werden alle Striche voll gezeichnet. Falls der Test
  hier schwächelt, ist eine vereinfachte Darstellung für weite Zoomstufen der
  nächste Optimierungsschritt.
- Flutter liefert keine Strichvorhersage wie Apples PencilKit. Wie stark man
  das merkt, ist genau das, was dieser Test klären soll.
- Gespeichert wird lokal auf dem Gerät. Cloud und Synchronisation folgen in Phase 6;
  das Datenformat ist dafür schon vorbereitet.
