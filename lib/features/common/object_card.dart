import 'package:flutter/material.dart';

import '../../app/navigation.dart';
import '../../app/services.dart';
import '../../app/theme.dart';
import '../../data/models.dart';
import '../../ui/widgets.dart';
import '../notebook/notebook_cover.dart';
import 'create_dialogs.dart';

/// Karte für Notizbuch oder Canvas in Übersichten.
class ObjectCard extends StatelessWidget {
  const ObjectCard({super.key, required this.object});

  final MfObject object;

  @override
  Widget build(BuildContext context) {
    final o = object;
    return o.type == ObjectType.notebook
        ? _NotebookCard(o)
        : _BoardCard(o);
  }
}

class _NotebookCard extends StatelessWidget {
  const _NotebookCard(this.o);
  final MfObject o;

  @override
  Widget build(BuildContext context) {
    final mf = context.mf;
    final pages = Services.of(context).objects.childCount(o.id);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: GestureDetector(
            onTap: () => openObject(context, o),
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: Center(
                child: AspectRatio(
                  aspectRatio: 0.74,
                  child: DecoratedBox(
                    decoration: const BoxDecoration(boxShadow: [
                      BoxShadow(
                          color: Color(0x33000000),
                          blurRadius: 14,
                          offset: Offset(0, 8)),
                    ]),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        NotebookCover(
                          color: Color(o.coverColor),
                          style: o.coverStyle,
                          title: o.displayTitle,
                          category: o.category,
                          compact: true,
                        ),
                        if (o.pinned)
                          const Positioned(
                            top: 8,
                            right: 8,
                            child: Icon(Icons.push_pin,
                                size: 16, color: Colors.white),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
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
                  Text(
                    '$pages ${pages == 1 ? 'Seite' : 'Seiten'} · ${relativeTime(o.updatedAt)}',
                    maxLines: 1,
                    style: TextStyle(fontSize: 12, color: mf.textMuted),
                  ),
                ],
              ),
            ),
            ObjectMenu(object: o),
          ],
        ),
      ],
    );
  }
}

class _BoardCard extends StatelessWidget {
  const _BoardCard(this.o);
  final MfObject o;

  @override
  Widget build(BuildContext context) {
    final mf = context.mf;
    final paper = PaperStyle.of(o.paper);
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
                color: paper.sheet,
                child: Stack(
                  children: [
                    Center(
                      child: Icon(Icons.bubble_chart_outlined,
                          size: 36, color: mf.accent),
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
                        Text('Canvas · ${relativeTime(o.updatedAt)}',
                            maxLines: 1,
                            style:
                                TextStyle(fontSize: 12, color: mf.textMuted)),
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
    final isNotebook = o.type == ObjectType.notebook;
    return PopupMenuButton<String>(
      tooltip: 'Mehr',
      icon: Icon(Icons.more_horiz, color: context.mf.textMuted),
      onSelected: (v) async {
        switch (v) {
          case 'edit':
            await editNotebook(context, o);
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
        if (isNotebook)
          const PopupMenuItem(
              value: 'edit', child: Text('Umschlag & Einstellungen'))
        else
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
        maxCrossAxisExtent: 200,
        mainAxisExtent: 250,
        crossAxisSpacing: 18,
        mainAxisSpacing: 22,
      ),
      itemCount: objects.length,
      itemBuilder: (_, i) => ObjectCard(object: objects[i]),
    );
  }
}
