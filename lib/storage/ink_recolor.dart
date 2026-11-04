import 'dart:ui' show Color;

import '../ink/stroke.dart';
import '../ink/tool_settings.dart';
import 'ink_store.dart';

/// Ordnet eine Schriftfarbe beim Wechsel zwischen dunklem und hellem Papier
/// neu zu – damit z. B. weiße Schrift auf weißem Papier nicht verschwindet.
///
/// - Standardfarben werden auf die passende Standardfarbe des anderen
///   Papiers abgebildet (Weiß ↔ Schwarz, Violett ↔ Violett …).
/// - Andere sehr helle bzw. sehr dunkle Farben werden zur Grundfarbe.
/// - Alles andere bleibt, wie es ist.
/// Gibt null zurück, wenn die Farbe bleiben soll.
int? mapInkColor(int color, {required bool toDark}) {
  final from = toDark ? kDefaultPaletteLight : kDefaultPaletteDark;
  final to = toDark ? kDefaultPaletteDark : kDefaultPaletteLight;
  final i = from.indexOf(color);
  if (i >= 0) return to[i];
  final lum = Color(color).computeLuminance();
  if (toDark && lum < 0.06) return to.first;
  if (!toDark && lum > 0.75) return to.first;
  return null;
}

/// Passt die Farben aller Striche einer Fläche an. Textmarker bleiben.
/// Gibt die Anzahl geänderter Striche zurück.
Future<int> recolorInk(String inkId, {required bool toDark}) async {
  final store = InkStore(inkId);
  final strokes = await store.load();
  var changed = 0;
  final out = <Stroke>[];
  for (final s in strokes) {
    final mapped = s.deleted || s.tool == InkTool.highlighter
        ? null
        : mapInkColor(s.color, toDark: toDark);
    if (mapped == null || mapped == s.color) {
      out.add(s);
      continue;
    }
    changed++;
    out.add(Stroke(
      id: s.id,
      color: mapped,
      width: s.width,
      tool: s.tool,
      points: s.points,
      deleted: s.deleted,
      fill: s.fill,
    ));
  }
  if (changed > 0) await store.save(out);
  return changed;
}
