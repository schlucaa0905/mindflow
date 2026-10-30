import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import '../ink/stroke.dart';

/// Erzeugt handschriftähnliche Kritzel-Striche für den Leistungstest.
/// Zeilen wie auf einer beschriebenen Seite, 100 "Wörter" pro Zeile.
List<Stroke> generateHandwriting({
  required int count,
  Offset origin = const Offset(0, 0),
  int seed = 42,
  int color = 0xFFEDEDF2,
}) {
  final rnd = math.Random(seed);
  const perRow = 100;
  final runId = DateTime.now().microsecondsSinceEpoch;
  final result = <Stroke>[];
  for (var i = 0; i < count; i++) {
    final row = i ~/ perRow;
    final col = i % perRow;
    final x0 = origin.dx + col * 60 + rnd.nextDouble() * 10;
    final y0 = origin.dy + row * 55;
    final n = 20 + rnd.nextInt(25);
    final freq = 0.3 + rnd.nextDouble() * 0.5;
    final amp = 6 + rnd.nextDouble() * 9;
    final phase = rnd.nextDouble() * math.pi * 2;
    final pts = Float32List(n * 3);
    for (var j = 0; j < n; j++) {
      pts[j * 3] = x0 + j * 1.6;
      pts[j * 3 + 1] = y0 +
          math.sin(j * freq + phase) * amp +
          math.cos(j * freq * 0.37) * amp * 0.4;
      pts[j * 3 + 2] = 0.3 + 0.4 * math.sin(j / n * math.pi);
    }
    result.add(Stroke(
      id: 'stress-$runId-$i',
      color: color,
      width: 2.2,
      tool: InkTool.pen,
      points: pts,
    ));
  }
  return result;
}
