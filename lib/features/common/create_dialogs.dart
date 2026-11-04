import 'package:flutter/material.dart';

import '../../app/navigation.dart';
import '../../app/services.dart';
import '../../app/theme.dart';
import '../../data/models.dart';
import '../../storage/ink_recolor.dart';
import '../documents/pdf_service.dart';
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

  // Neue Vorlage: auch auf die vorhandenen Seiten anwenden?
  if (draft.template != notebook.template && context.mounted) {
    final all = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Neue Vorlage'),
        content: Text('„${draft.template.label}“ für neue Seiten – und auch '
            'für die vorhandenen Seiten? Handschrift bleibt erhalten.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Nur neue Seiten')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Alle Seiten')),
        ],
      ),
    );
    if (all == true) {
      for (final p in repo.children(notebook.id)) {
        if (p.type != ObjectType.page) continue;
        repo.setData(p.id,
            {...p.data, 'template': draft.template.name}..remove('bgImage'));
      }
    }
  }

  // Papier von dunkel auf hell (oder umgekehrt)? Dann Schriftfarben anbieten
  // anzupassen, sonst wäre z. B. weiße Schrift auf weißem Papier unsichtbar.
  final wasDark = isDarkPaper(notebook.paper);
  final nowDark = isDarkPaper(draft.paper);
  if (wasDark != nowDark && context.mounted) {
    final pages = repo.children(notebook.id);
    await offerRecolor(context, [for (final p in pages) p.id], toDark: nowDark);
  }
}

bool isDarkPaper(Paper p) =>
    PaperStyle.of(p).sheet.computeLuminance() < 0.3;

/// Fragt, ob die Schriftfarben ans neue Papier angepasst werden sollen.
Future<void> offerRecolor(BuildContext context, List<String> inkIds,
    {required bool toDark}) async {
  final texts = Services.maybeOf(context)?.texts;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Schriftfarben anpassen?'),
      content: Text(toDark
          ? 'Das Papier ist jetzt dunkel. Soll dunkle Schrift hell werden, '
              'damit sie lesbar bleibt?'
          : 'Das Papier ist jetzt hell. Soll helle Schrift dunkel werden, '
              'damit sie lesbar bleibt?'),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('So lassen')),
        FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Anpassen')),
      ],
    ),
  );
  if (ok != true) return;
  for (final id in inkIds) {
    await recolorInk(id, toDark: toDark);
    // Textfelder ebenso anpassen.
    if (texts != null) {
      for (final t in texts.items(id).where((t) => !t.isImage)) {
        final mapped = mapInkColor(t.color, toDark: toDark);
        if (mapped != null && mapped != t.color) {
          t.color = mapped;
          texts.update(t, notify: false);
        }
      }
    }
  }
}

/// Titel und Hintergrund eines Canvas ändern.
Future<void> editBoard(BuildContext context, MfObject board) async {
  final repo = Services.of(context).objects;
  final titleCtrl = TextEditingController(text: board.title);
  var paper = board.paper;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: const Text('Canvas bearbeiten'),
        content: SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: titleCtrl,
                autofocus: true,
                decoration: const InputDecoration(hintText: 'Titel'),
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
              child: const Text('Speichern')),
        ],
      ),
    ),
  );
  if (ok != true) return;
  final title = titleCtrl.text.trim();
  if (title.isNotEmpty) repo.rename(board.id, title);
  repo.setData(board.id, {...board.data, 'paper': paper.name});
  if (isDarkPaper(board.paper) != isDarkPaper(paper) && context.mounted) {
    await offerRecolor(context, [board.id], toDark: isDarkPaper(paper));
  }
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

/// PDF(s) auswählen und importieren. Eine Datei wird direkt geöffnet,
/// bei mehreren erscheint eine kurze Bestätigung.
Future<void> importDocument(BuildContext context) async {
  final repo = Services.of(context).objects;
  final messenger = ScaffoldMessenger.maybeOf(context);
  final picked = await PdfService.pickMany();
  if (picked.isEmpty || !context.mounted) return;
  final navigator = Navigator.of(context, rootNavigator: true);
  final progress = ValueNotifier<int>(0);
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => AlertDialog(
      content: ValueListenableBuilder<int>(
        valueListenable: progress,
        builder: (_, done, __) => Row(children: [
          const SizedBox(
              width: 24, height: 24, child: CircularProgressIndicator()),
          const SizedBox(width: 16),
          Expanded(
            child: Text(picked.length == 1
                ? 'PDF wird importiert …'
                : 'Importiere ${done + 1} von ${picked.length} …'),
          ),
        ]),
      ),
    ),
  );
  final imported = <MfObject>[];
  final failed = <String>[];
  for (var i = 0; i < picked.length; i++) {
    progress.value = i;
    try {
      imported.add(await PdfService.importBytes(repo, picked[i].bytes,
          title: picked[i].title));
    } catch (_) {
      failed.add(picked[i].title);
    }
  }
  navigator.pop();
  // progress nicht freigeben: Der Dialog blendet noch aus.
  if (failed.isNotEmpty) {
    messenger?.showSnackBar(SnackBar(
        content: Text('Nicht lesbar: ${failed.join(', ')}')));
  }
  if (imported.length == 1 && context.mounted) {
    await openObject(context, imported.single);
  } else if (imported.length > 1) {
    messenger?.showSnackBar(SnackBar(
        content: Text('${imported.length} Dokumente importiert – '
            'du findest sie unter „Dokumente“.')));
  }
}

/// Geführter Import aus Goodnotes (über PDF-Export).
Future<void> importFromGoodnotes(BuildContext context) async {
  final go = await showDialog<bool>(
    context: context,
    builder: (ctx) {
      final mf = ctx.mf;
      Widget step(String nr, String text) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 26,
                  height: 26,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                      color: mf.accentSoft, shape: BoxShape.circle),
                  child: Text(nr,
                      style: TextStyle(
                          fontWeight: FontWeight.w700, color: mf.accent)),
                ),
                const SizedBox(width: 12),
                Expanded(
                    child: Text(text,
                        style: TextStyle(height: 1.45, color: mf.text))),
              ],
            ),
          );
      return AlertDialog(
        title: const Text('Aus Goodnotes übernehmen'),
        content: SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              step('1',
                  'In Goodnotes die Notizbücher auswählen (in der Übersicht auf „Auswählen“ tippen).'),
              step('2',
                  '„Exportieren“ → Format „PDF“ → „In Dateien sichern“.'),
              step('3',
                  'Hier auf „PDFs auswählen“ tippen und alle exportierten Dateien markieren.'),
              const SizedBox(height: 4),
              Text(
                  'Deine Handschrift bleibt sichtbar und du kannst direkt weiterschreiben. '
                  'Das Goodnotes-Format selbst ist nicht offen lesbar – der Weg über PDF '
                  'ist deshalb der zuverlässigste.',
                  style: TextStyle(fontSize: 12, color: mf.textMuted)),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Abbrechen')),
          FilledButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.file_open_outlined, size: 18),
            label: const Text('PDFs auswählen'),
          ),
        ],
      );
    },
  );
  if (go == true && context.mounted) await importDocument(context);
}

/// Neuen Wissenseintrag anlegen und öffnen.
Future<void> createKnowledge(BuildContext context, {String? parentId}) async {
  final repo = Services.of(context).objects;
  final title = await showDialog<String>(
    context: context,
    builder: (ctx) {
      final ctrl = TextEditingController();
      return AlertDialog(
        title: Text(parentId == null ? 'Neuer Wissenseintrag' : 'Neues Unterthema'),
        content: SizedBox(
          width: 420,
          child: TextField(
            controller: ctrl,
            autofocus: true,
            decoration: const InputDecoration(hintText: 'z. B. TCP/IP'),
            onSubmitted: (v) => Navigator.pop(ctx, v),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Abbrechen')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text),
              child: const Text('Erstellen')),
        ],
      );
    },
  );
  if (title == null || title.trim().isEmpty || !context.mounted) return;
  final entry = repo.create(
    type: ObjectType.knowledge,
    title: title.trim(),
    parentId: parentId,
    data: {'body': '', 'tags': <String>[]},
  );
  await openObject(context, entry);
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
          ListTile(
            leading: const Icon(Icons.picture_as_pdf_outlined),
            title: const Text('PDF importieren'),
            subtitle: const Text('Lesen, markieren, hineinschreiben'),
            onTap: () => Navigator.pop(ctx, 'pdf'),
          ),
          ListTile(
            leading: const Icon(Icons.move_down_outlined),
            title: const Text('Aus Goodnotes übernehmen'),
            subtitle: const Text('Notizbücher als PDF importieren'),
            onTap: () => Navigator.pop(ctx, 'goodnotes'),
          ),
          ListTile(
            leading: const Icon(Icons.hub_outlined),
            title: const Text('Wissenseintrag'),
            subtitle: const Text('Thema mit Verknüpfungen'),
            onTap: () => Navigator.pop(ctx, 'knowledge'),
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
  if (!context.mounted) return;
  if (choice == 'notebook') await createNotebook(context);
  if (choice == 'board') await createBoard(context);
  if (choice == 'pdf') await importDocument(context);
  if (choice == 'goodnotes') await importFromGoodnotes(context);
  if (choice == 'knowledge') await createKnowledge(context);
}
