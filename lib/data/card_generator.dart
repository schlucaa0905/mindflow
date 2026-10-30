/// Macht aus dem Text eines Wissenseintrags Karteikarten-Vorschläge.
///
/// Erkannt werden Zeilen wie
///   `DHCP: vergibt IP-Adressen automatisch`
///   `- TCP – verbindungsorientiertes Protokoll`
///   `HTTP = Protokoll für Webseiten`
/// Vorne steht der Begriff, hinten die Erklärung.
library;

typedef CardDraft = ({String front, String back});

final _bullet = RegExp(r'^\s*(?:[-•*·▪>]+|\d+[.)])\s*');
final _separators = [': ', ' – ', ' — ', ' - ', ' = ', ' -> ', ' → '];

List<CardDraft> cardsFromText(String text, {Set<String> skipFronts = const {}}) {
  final out = <CardDraft>[];
  final seen = {for (final f in skipFronts) f.trim().toLowerCase()};
  for (final raw in text.split('\n')) {
    final line = raw.replaceFirst(_bullet, '').trim();
    if (line.length < 3) continue;
    var cut = -1;
    var sepLen = 0;
    for (final sep in _separators) {
      final i = line.indexOf(sep);
      if (i > 0 && (cut < 0 || i < cut)) {
        cut = i;
        sepLen = sep.length;
      }
    }
    // Auch "Begriff:Erklärung" ohne Leerzeichen.
    if (cut < 0) {
      final i = line.indexOf(':');
      if (i > 0 && i < line.length - 1) {
        cut = i;
        sepLen = 1;
      }
    }
    if (cut < 0) continue;
    final front = line.substring(0, cut).trim();
    final back = line.substring(cut + sepLen).trim();
    if (front.isEmpty || back.isEmpty) continue;
    if (front.length > 120) continue;
    // Internetadressen wie "https://…" nicht als Begriff deuten
    // (der Begriff „HTTP“ selbst ist aber erlaubt).
    if (_isUrl(front)) continue;
    if (!seen.add(front.toLowerCase())) continue;
    out.add((front: front, back: back));
  }
  return out;
}

bool _isUrl(String s) {
  final t = s.toLowerCase();
  return t.contains('://') || t.startsWith('www.');
}
