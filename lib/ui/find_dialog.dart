import 'package:flutter/material.dart';

import '../app/theme.dart';

/// Ein Treffer der Suche im Dokument.
typedef FindHit = ({String title, String snippet, VoidCallback open});

/// Ausschnitt um den Treffer herum.
String snippetOf(String text, String q) {
  final i = text.toLowerCase().indexOf(q.toLowerCase());
  if (i < 0) return text;
  final a = (i - 30).clamp(0, text.length).toInt();
  final b = (i + q.length + 50).clamp(0, text.length).toInt();
  return '${a > 0 ? '…' : ''}${text.substring(a, b).replaceAll('\n', ' ')}'
      '${b < text.length ? '…' : ''}';
}

/// Suche im geöffneten Notizbuch, PDF oder Canvas.
Future<void> showFindDialog(
    BuildContext context, List<FindHit> Function(String q) search) {
  var q = '';
  return showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(builder: (ctx, setState) {
      final mf = ctx.mf;
      final hits = q.trim().isEmpty ? const <FindHit>[] : search(q.trim());
      return AlertDialog(
        title: const Text('Im Dokument suchen'),
        content: SizedBox(
          width: 480,
          height: 380,
          child: Column(children: [
            TextField(
              autofocus: true,
              decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Wort oder Satz …'),
              onChanged: (v) => setState(() => q = v),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: q.trim().isEmpty
                  ? const SizedBox.shrink()
                  : hits.isEmpty
                      ? Text('Keine Treffer.',
                          style: TextStyle(color: mf.textMuted))
                      : ListView(children: [
                          for (final h in hits)
                            ListTile(
                              title: Text(h.title),
                              subtitle: Text(h.snippet,
                                  maxLines: 2, overflow: TextOverflow.ellipsis),
                              onTap: () {
                                Navigator.pop(ctx);
                                h.open();
                              },
                            ),
                        ]),
            ),
          ]),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Schließen')),
        ],
      );
    }),
  );
}
