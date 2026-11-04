import 'package:flutter/material.dart';

import '../../app/navigation.dart';
import '../../app/services.dart';
import '../../data/models.dart';
import 'object_picker.dart';

/// Links auf Seiten: Ziel `page:<Seiten-ID>` oder `obj:<Objekt-ID>`.
/// Über stabile IDs – Umbenennen oder Verschieben macht nichts kaputt.

/// Ziel wählen: eine Seite dieses Notizbuchs oder ein beliebiger Inhalt.
Future<String?> pickLinkTarget(BuildContext context,
    {String? notebookId}) async {
  final repo = Services.of(context).objects;
  final pages = notebookId == null
      ? const <MfObject>[]
      : repo
          .children(notebookId)
          .where((p) => p.type == ObjectType.page)
          .toList();
  if (pages.isNotEmpty) {
    final picked = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Verlinken mit …'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'other'),
            child: const Row(children: [
              Icon(Icons.travel_explore_rounded, size: 20),
              SizedBox(width: 10),
              Text('Anderem Inhalt (Notizbuch, PDF, Canvas, Wissen) …'),
            ]),
          ),
          const Divider(),
          for (var i = 0; i < pages.length; i++)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, 'page:${pages[i].id}'),
              child: Text(pages[i].title.trim().isEmpty
                  ? 'Seite ${i + 1}'
                  : 'Seite ${i + 1} · ${pages[i].title.trim()}'),
            ),
        ],
      ),
    );
    if (picked != 'other') return picked;
    if (!context.mounted) return null;
  }
  final o = await pickObject(context, title: 'Verlinken mit …', types: {
    ObjectType.notebook,
    ObjectType.page,
    ObjectType.document,
    ObjectType.board,
    ObjectType.knowledge,
  });
  return o == null ? null : 'obj:${o.id}';
}

/// Öffnet ein Linkziel. [goToPage] springt innerhalb des offenen
/// Notizbuchs, wenn die Seite dort liegt (gibt dann true zurück).
Future<void> openLinkTarget(BuildContext context, String target,
    {bool Function(String pageId)? goToPage}) async {
  final i = target.indexOf(':');
  if (i < 0) return;
  final id = target.substring(i + 1);
  if (target.startsWith('page:') && (goToPage?.call(id) ?? false)) return;
  final o = Services.of(context).objects.get(id);
  if (o == null || o.deletedAt != null) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(const SnackBar(
        content: Text('Das Linkziel gibt es nicht mehr (gelöscht).')));
    return;
  }
  await openObject(context, o);
}
