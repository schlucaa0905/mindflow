import 'package:flutter/material.dart';

import '../../app/navigation.dart';
import '../../app/services.dart';
import '../../app/theme.dart';
import '../../data/models.dart';
import '../../ui/widgets.dart';

/// Karte für Notizbuch oder Canvas in Übersichten.
class ObjectCard extends StatelessWidget {
  const ObjectCard({super.key, required this.object});

  final MfObject object;

  @override
  Widget build(BuildContext context) {
    final mf = context.mf;
    final repo = Services.of(context).objects;
    final o = object;
    final isNotebook = o.type == ObjectType.notebook;
    final paper = PaperStyle.of(o.paper);
    final cover = Color((o.data['cover'] as int?) ?? 0xFF8B7CF6);
    final pages = isNotebook ? repo.childCount(o.id) : 0;

    return Material(
      color: mf.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: mf.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => openObject(context, o),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Container(
                color: paper.desk,
                child: Stack(
                  children: [
                    if (isNotebook)
                      Positioned(
                          left: 0,
                          top: 0,
                          bottom: 0,
                          width: 10,
                          child: ColoredBox(color: cover)),
                    Center(
                      child: Icon(
                        isNotebook
                            ? Icons.menu_book_outlined
                            : Icons.bubble_chart_outlined,
                        size: 36,
                        color: isNotebook ? cover : mf.accent,
                      ),
                    ),
                    if (o.pinned)
                      Positioned(
                        top: 8,
                        right: 8,
                        child: Icon(Icons.push_pin, size: 16, color: mf.accent),
                      ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 4, 10),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(o.displayTitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontWeight: FontWeight.w600, color: mf.text)),
                        const SizedBox(height: 2),
                        Text(
                          [
                            if (isNotebook)
                              '$pages ${pages == 1 ? 'Seite' : 'Seiten'}',
                            relativeTime(o.updatedAt),
                          ].join(' · '),
                          maxLines: 1,
                          style: TextStyle(fontSize: 12, color: mf.textMuted),
                        ),
                      ],
                    ),
                  ),
                  ObjectMenu(object: o),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Das "…"-Menü eines Objekts.
class ObjectMenu extends StatelessWidget {
  const ObjectMenu({super.key, required this.object});

  final MfObject object;

  @override
  Widget build(BuildContext context) {
    final repo = Services.of(context).objects;
    final o = object;
    return PopupMenuButton<String>(
      tooltip: 'Mehr',
      icon: Icon(Icons.more_horiz, color: context.mf.textMuted),
      onSelected: (v) async {
        switch (v) {
          case 'rename':
            final t = await askText(context,
                title: 'Umbenennen', initial: o.title);
            if (t != null && t.trim().isNotEmpty) repo.rename(o.id, t.trim());
          case 'pin':
            repo.setPinned(o.id, !o.pinned);
          case 'archive':
            repo.setArchived(o.id, true);
            _snack(context, '„${o.displayTitle}“ archiviert',
                () => repo.setArchived(o.id, false));
          case 'trash':
            repo.trash(o.id);
            _snack(context, '„${o.displayTitle}“ in den Papierkorb gelegt',
                () => repo.restore(o.id));
        }
      },
      itemBuilder: (_) => [
        const PopupMenuItem(value: 'rename', child: Text('Umbenennen')),
        PopupMenuItem(
            value: 'pin', child: Text(o.pinned ? 'Lösen' : 'Anheften')),
        const PopupMenuItem(value: 'archive', child: Text('Archivieren')),
        const PopupMenuItem(value: 'trash', child: Text('In den Papierkorb')),
      ],
    );
  }
}

void _snack(BuildContext context, String text, VoidCallback undo) {
  ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
    content: Text(text),
    action: SnackBarAction(label: 'Rückgängig', onPressed: undo),
  ));
}

/// Raster aus Objekt-Karten.
class ObjectGrid extends StatelessWidget {
  const ObjectGrid({super.key, required this.objects});

  final List<MfObject> objects;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 240,
        mainAxisExtent: 190,
        crossAxisSpacing: 14,
        mainAxisSpacing: 14,
      ),
      itemCount: objects.length,
      itemBuilder: (_, i) => ObjectCard(object: objects[i]),
    );
  }
}
