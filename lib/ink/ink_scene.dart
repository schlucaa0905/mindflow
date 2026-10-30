import 'dart:collection';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'stroke.dart';
import 'stroke_renderer.dart';

/// Kantenlänge eines Raster-Abschnitts ("Chunk") in Weltkoordinaten.
const double kChunkSize = 1024;

/// Ein räumlicher Abschnitt der Fläche.
///
/// Alle Striche eines Abschnitts werden einmal in ein [ui.Picture]
/// aufgezeichnet. Beim Verschieben/Zoomen wird nur dieses fertige Bild
/// erneut abgespielt – die Umrisse werden nicht neu berechnet.
/// Abschnitte außerhalb des sichtbaren Bereichs werden übersprungen.
class InkChunk {
  InkChunk(this.key);

  final int key;
  final List<Stroke> strokes = [];
  Rect bounds = Rect.zero;
  bool _hasBounds = false;
  ui.Picture? _picture;

  void add(Stroke s) {
    strokes.add(s);
    bounds = _hasBounds ? bounds.expandToInclude(s.bounds) : s.bounds;
    _hasBounds = true;
    invalidate();
  }

  void invalidate() {
    _picture?.dispose();
    _picture = null;
  }

  ui.Picture get picture => _picture ??= _record();

  ui.Picture _record() {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    // Textmarker liegen immer hinter der Schrift (wie auf Papier).
    for (final s in strokes) {
      if (!s.deleted && s.tool == InkTool.highlighter) paintStroke(canvas, s);
    }
    for (final s in strokes) {
      if (!s.deleted && s.tool != InkTool.highlighter) paintStroke(canvas, s);
    }
    return recorder.endRecording();
  }
}

int chunkKeyFor(Rect bounds) {
  final c = bounds.center;
  final cx = (c.dx / kChunkSize).floor().clamp(-0xFFFFF, 0xFFFFF);
  final cy = (c.dy / kChunkSize).floor().clamp(-0xFFFFF, 0xFFFFF);
  return ((cx + 0x100000) << 21) | (cy + 0x100000);
}

/// Alle Striche einer Fläche (Notizbuchseite oder Canvas).
class InkScene extends ChangeNotifier {
  final Map<String, Stroke> _byId = {};
  final List<Stroke> _strokes = [];
  final Map<int, InkChunk> _chunks = {};
  int _alive = 0;

  /// Zählt jede Änderung hoch – Grundlage für das automatische Speichern.
  int revision = 0;

  UnmodifiableListView<Stroke> get strokes => UnmodifiableListView(_strokes);
  Iterable<InkChunk> get chunks => _chunks.values;
  int get aliveCount => _alive;

  Stroke? byId(String id) => _byId[id];

  void add(Stroke s) {
    if (_insert(s)) _changed();
  }

  void addAll(Iterable<Stroke> list) {
    var any = false;
    for (final s in list) {
      any = _insert(s) || any;
    }
    if (any) _changed();
  }

  /// Ersetzt den kompletten Inhalt (z. B. nach dem Laden).
  /// Erhöht [revision] nicht, damit Laden kein Speichern auslöst.
  void replaceAll(List<Stroke> list) {
    for (final c in _chunks.values) {
      c.invalidate();
    }
    _chunks.clear();
    _byId.clear();
    _strokes.clear();
    _alive = 0;
    for (final s in list) {
      _insert(s);
    }
    notifyListeners();
  }

  bool _insert(Stroke s) {
    if (_byId.containsKey(s.id)) return false;
    _byId[s.id] = s;
    _strokes.add(s);
    if (!s.deleted) _alive++;
    final key = chunkKeyFor(s.bounds);
    _chunks.putIfAbsent(key, () => InkChunk(key)).add(s);
    return true;
  }

  void setDeleted(Iterable<Stroke> list, bool deleted) {
    final touched = <InkChunk>{};
    for (final s in list) {
      if (s.deleted == deleted) continue;
      s.deleted = deleted;
      _alive += deleted ? -1 : 1;
      final chunk = _chunks[chunkKeyFor(s.bounds)];
      if (chunk != null) touched.add(chunk);
    }
    if (touched.isEmpty) return;
    for (final c in touched) {
      c.invalidate();
    }
    _changed();
  }

  /// Sichtbare Striche, die den Punkt berühren.
  List<Stroke> hitTest(Offset p, double radius) {
    final hits = <Stroke>[];
    for (final chunk in _chunks.values) {
      if (!chunk.bounds.inflate(radius).contains(p)) continue;
      for (final s in chunk.strokes) {
        if (!s.deleted && s.hits(p, radius)) hits.add(s);
      }
    }
    return hits;
  }

  /// Grobes, schnelles Rechteck um alle Inhalte (über die Abschnitte).
  /// Für Übersichtskarten, wo es auf Geschwindigkeit ankommt.
  Rect? roughBounds() {
    if (_alive == 0) return null;
    Rect? r;
    for (final c in _chunks.values) {
      if (c.strokes.every((s) => s.deleted)) continue;
      r = r == null ? c.bounds : r.expandToInclude(c.bounds);
    }
    return r;
  }

  /// Umschließendes Rechteck aller sichtbaren Striche.
  Rect? contentBounds() {
    Rect? r;
    for (final s in _strokes) {
      if (s.deleted) continue;
      r = r == null ? s.bounds : r.expandToInclude(s.bounds);
    }
    return r;
  }

  void _changed() {
    revision++;
    notifyListeners();
  }

  @override
  void dispose() {
    for (final c in _chunks.values) {
      c.invalidate();
    }
    super.dispose();
  }
}
