import 'package:flutter/material.dart';

import '../../app/navigation.dart';
import '../../app/services.dart';
import '../../app/theme.dart';
import '../../data/models.dart';
import '../notebook/new_notebook_dialog.dart';

Paper _defaultPaper(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark ? Paper.dark : Paper.light;

/// Neues Notizbuch anlegen und direkt öffnen.
Future<void> createNotebook(BuildContext context) async {
  final repo = Services.of(context).objects;
  final count = repo.byType(ObjectType.notebook).length;
  final draft = await showNotebookDialog(
    context,
    categories: repo.categories(ObjectType.notebook),
    suggestedCover: kCoverColors[count % kCoverColors.length],
  );
  if (draft == null || !context.mounted) return;

  final nb = repo.create(
    type: ObjectType.notebook,
    title: draft.title,
    data: draft.toData(),
  );
  repo.create(
    type: ObjectType.page,
    parentId: nb.id,
    data: {'template': draft.template.name},
  );
  await openObject(context, nb);
}

/// Umschlag, Kategorie, Papier usw. eines Notizbuchs ändern.
Future<void> editNotebook(BuildContext context, MfObject notebook) async {
  final repo = Services.of(context).objects;
  final draft = await showNotebookDialog(
    context,
    categories: repo.categories(ObjectType.notebook),
    suggestedCover: notebook.coverColor,
    initial: notebook,
  );
  if (draft == null) return;
  repo.rename(notebook.id, draft.title);
  final data = {...notebook.data, ...draft.toData()};
  if (draft.category.isEmpty) data.remove('category');
  repo.setData(notebook.id, data);
}

/// Neue Canvas-Fläche anlegen und direkt öffnen.
Future<void> createBoard(BuildContext context) async {
  final services = Services.of(context);
  final titleCtrl = TextEditingController();
  var paper = _defaultPaper(context);

  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: const Text('Neuer Canvas'),
        content: SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: titleCtrl,
                autofocus: true,
                decoration:
                    const InputDecoration(hintText: 'Titel, z. B. Informatik'),
                onSubmitted: (_) => Navigator.pop(ctx, true),
              ),
              const SizedBox(height: 20),
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text('Hintergrund',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: ctx.mf.textMuted)),
              ),
              SegmentedButton<Paper>(
                showSelectedIcon: false,
                segments: [
                  for (final p in Paper.values)
                    ButtonSegment(value: p, label: Text(p.label)),
                ],
                selected: {paper},
                onSelectionChanged: (s) => setState(() => paper = s.first),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Abbrechen')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Erstellen')),
        ],
      ),
    ),
  );
  if (ok != true || !context.mounted) return;

  final title =
      titleCtrl.text.trim().isEmpty ? 'Neuer Canvas' : titleCtrl.text.trim();
  final board = services.objects.create(
    type: ObjectType.board,
    title: title,
    data: {'paper': paper.name},
  );
  await openObject(context, board);
}

/// Menü "Neu" mit allen Dingen, die man anlegen kann.
Future<void> showCreateMenu(BuildContext context) async {
  final choice = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.menu_book_outlined),
            title: const Text('Notizbuch'),
            subtitle: const Text('Handschriftliche Seiten'),
            onTap: () => Navigator.pop(ctx, 'notebook'),
          ),
          ListTile(
            leading: const Icon(Icons.bubble_chart_outlined),
            title: const Text('Canvas'),
            subtitle: const Text('Unendliche Fläche, Mindmaps'),
            onTap: () => Navigator.pop(ctx, 'board'),
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
  if (!context.mounted) return;
  if (choice == 'notebook') await createNotebook(context);
  if (choice == 'board') await createBoard(context);
}
