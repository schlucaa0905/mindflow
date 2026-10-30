import 'package:flutter/material.dart';

import '../../app/navigation.dart';
import '../../app/services.dart';
import '../../app/theme.dart';
import '../../data/models.dart';

/// Farben für Notizbuch-Umschläge.
const kCoverColors = <int>[
  0xFF8B7CF6,
  0xFF5AA9FF,
  0xFF4ADE80,
  0xFFF59E0B,
  0xFFF472B6,
  0xFF94A3B8,
];

Paper _defaultPaper(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark ? Paper.dark : Paper.light;

/// Neues Notizbuch anlegen und direkt öffnen.
Future<void> createNotebook(BuildContext context) async {
  final services = Services.of(context);
  final titleCtrl = TextEditingController();
  var paper = _defaultPaper(context);
  var template = PageTemplate.lined;
  var cover = kCoverColors[
      services.objects.byType(ObjectType.notebook).length % kCoverColors.length];

  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) {
        final mf = ctx.mf;
        return AlertDialog(
          title: const Text('Neues Notizbuch'),
          content: SizedBox(
            width: 460,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: titleCtrl,
                  autofocus: true,
                  decoration: const InputDecoration(
                      hintText: 'Titel, z. B. Netzwerktechnik'),
                  onSubmitted: (_) => Navigator.pop(ctx, true),
                ),
                const SizedBox(height: 20),
                _Label('Umschlag', mf),
                Wrap(
                  spacing: 10,
                  children: [
                    for (final c in kCoverColors)
                      GestureDetector(
                        onTap: () => setState(() => cover = c),
                        child: Container(
                          width: 30,
                          height: 30,
                          decoration: BoxDecoration(
                            color: Color(c),
                            shape: BoxShape.circle,
                            border: Border.all(
                                color: cover == c ? mf.text : Colors.transparent,
                                width: 2.5),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 20),
                _Label('Papier', mf),
                SegmentedButton<Paper>(
                  segments: const [
                    ButtonSegment(value: Paper.dark, label: Text('Dunkel')),
                    ButtonSegment(value: Paper.light, label: Text('Hell')),
                  ],
                  selected: {paper},
                  onSelectionChanged: (s) => setState(() => paper = s.first),
                ),
                const SizedBox(height: 20),
                _Label('Vorlage für neue Seiten', mf),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final t in PageTemplate.values)
                      ChoiceChip(
                        label: Text(t.label),
                        selected: template == t,
                        onSelected: (_) => setState(() => template = t),
                      ),
                  ],
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
        );
      },
    ),
  );
  if (ok != true || !context.mounted) return;

  final repo = services.objects;
  final title = titleCtrl.text.trim().isEmpty ? 'Neues Notizbuch' : titleCtrl.text.trim();
  final nb = repo.create(
    type: ObjectType.notebook,
    title: title,
    data: {'paper': paper.name, 'cover': cover, 'template': template.name},
  );
  repo.create(
    type: ObjectType.page,
    parentId: nb.id,
    data: {'template': template.name},
  );
  await openObject(context, nb);
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
              _Label('Hintergrund', ctx.mf),
              SegmentedButton<Paper>(
                segments: const [
                  ButtonSegment(value: Paper.dark, label: Text('Dunkel')),
                  ButtonSegment(value: Paper.light, label: Text('Hell')),
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

  final title = titleCtrl.text.trim().isEmpty ? 'Neuer Canvas' : titleCtrl.text.trim();
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

class _Label extends StatelessWidget {
  const _Label(this.text, this.mf);
  final String text;
  final MfPalette mf;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text,
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: mf.textMuted)),
      );
}
