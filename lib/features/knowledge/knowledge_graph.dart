import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/navigation.dart';
import '../../app/services.dart';
import '../../app/theme.dart';
import '../../data/models.dart';

/// Ordnet Punkte so an, dass verbundene nah beieinander und alle anderen
/// mit Abstand liegen (einfaches Feder-Modell, immer gleiches Ergebnis).
Map<String, Offset> layoutGraph(
    List<String> ids, List<(String, String)> edges,
    {int iterations = 300}) {
  final n = ids.length;
  final pos = <String, Offset>{
    for (var i = 0; i < n; i++)
      ids[i]: Offset(math.cos(i * 2.399) * 40.0 * math.sqrt(i + 1),
          math.sin(i * 2.399) * 40.0 * math.sqrt(i + 1)),
  };
  const k = 140.0;
  for (var it = 0; it < iterations; it++) {
    final force = {for (final id in ids) id: Offset.zero};
    for (var i = 0; i < n; i++) {
      for (var j = i + 1; j < n; j++) {
        final d = pos[ids[i]]! - pos[ids[j]]!;
        final dist = math.max(1.0, d.distance);
        final f = d / dist * (k * k / dist);
        force[ids[i]] = force[ids[i]]! + f;
        force[ids[j]] = force[ids[j]]! - f;
      }
    }
    for (final e in edges) {
      final a = e.$1, b = e.$2;
      final pa = pos[a], pb = pos[b];
      if (pa == null || pb == null) continue;
      final d = pa - pb;
      final dist = math.max(1.0, d.distance);
      final f = d / dist * (dist * dist / k);
      force[a] = force[a]! - f;
      force[b] = force[b]! + f;
    }
    final t = 20.0 * (1 - it / iterations) + 1;
    for (final id in ids) {
      final f = force[id]! - pos[id]! * 0.01; // leichter Zug zur Mitte
      final len = f.distance;
      if (len > 0) pos[id] = pos[id]! + f / len * math.min(len, t);
    }
  }
  return pos;
}

/// Alle Wissenseinträge als Netz – wie die Graph-Ansicht in Obsidian.
class KnowledgeGraphScreen extends StatelessWidget {
  const KnowledgeGraphScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final repo = Services.of(context).objects;
    final mf = context.mf;
    final entries = repo.byType(ObjectType.knowledge);
    final ids = {for (final e in entries) e.id};
    final edges = <(String, String)>{};
    for (final e in entries) {
      if (e.parentId != null && ids.contains(e.parentId)) {
        edges.add((e.parentId!, e.id));
      }
      for (final o in repo.linkedIds(e.id)) {
        if (ids.contains(o) && e.id.compareTo(o) < 0) edges.add((e.id, o));
      }
    }
    final pos = layoutGraph([for (final e in entries) e.id], edges.toList());
    var bounds = Rect.zero;
    for (final p in pos.values) {
      bounds = bounds.expandToInclude(Rect.fromCircle(center: p, radius: 1));
    }
    final area = bounds.inflate(160);
    Offset at(String id) => pos[id]! - area.topLeft;
    final degree = <String, int>{};
    for (final e in edges) {
      degree[e.$1] = (degree[e.$1] ?? 0) + 1;
      degree[e.$2] = (degree[e.$2] ?? 0) + 1;
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Wissensnetz')),
      body: entries.isEmpty
          ? const Center(child: Text('Noch keine Wissenseinträge.'))
          : InteractiveViewer(
              constrained: false,
              minScale: 0.2,
              maxScale: 3,
              boundaryMargin: const EdgeInsets.all(400),
              child: SizedBox(
                width: area.width,
                height: area.height,
                child: Stack(children: [
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _EdgesPainter(
                          [for (final e in edges) (at(e.$1), at(e.$2))],
                          mf.accent.withValues(alpha: 0.5)),
                    ),
                  ),
                  for (final e in entries)
                    Positioned(
                      left: at(e.id).dx - 70,
                      top: at(e.id).dy - 18,
                      width: 140,
                      child: Center(
                        child: ActionChip(
                          avatar: CircleAvatar(
                            radius: 5 + math.min(6, (degree[e.id] ?? 0)).toDouble(),
                            backgroundColor: mf.accent,
                          ),
                          label: Text(e.displayTitle,
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                          onPressed: () => openObject(context, e),
                        ),
                      ),
                    ),
                ]),
              ),
            ),
    );
  }
}

class _EdgesPainter extends CustomPainter {
  _EdgesPainter(this.lines, this.color);
  final List<(Offset, Offset)> lines;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..strokeWidth = 1.6;
    for (final l in lines) {
      canvas.drawLine(l.$1, l.$2, p);
    }
  }

  @override
  bool shouldRepaint(_EdgesPainter old) => true;
}
