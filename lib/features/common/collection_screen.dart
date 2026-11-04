import 'package:flutter/material.dart';

import '../../app/services.dart';
import '../../app/theme.dart';
import '../../data/models.dart';
import '../../ui/clean_menu.dart';
import '../../ui/widgets.dart';
import 'folders.dart';
import 'object_card.dart';

/// Übersicht aller Notizbücher bzw. aller Canvas-Flächen.
/// Notizbücher lassen sich nach Kategorie filtern und werden danach gruppiert.
class CollectionScreen extends StatefulWidget {
  const CollectionScreen({
    super.key,
    required this.type,
    required this.title,
    required this.subtitle,
    required this.createLabel,
    required this.onCreate,
    required this.emptyIcon,
    required this.emptyTitle,
    required this.emptyMessage,
  });

  final ObjectType type;
  final String title;
  final String subtitle;
  final String createLabel;
  final Future<void> Function(BuildContext) onCreate;
  final IconData emptyIcon;
  final String emptyTitle;
  final String emptyMessage;

  @override
  State<CollectionScreen> createState() => _CollectionScreenState();
}

class _CollectionScreenState extends State<CollectionScreen> {
  /// Geöffneter Ordner ('' = oberste Ebene).
  String _path = '';

  /// Sortierung: false = zuletzt geändert, true = nach Name.
  bool _byName = false;

  Future<void> _create(BuildContext context) async {
    final repo = Services.of(context).objects;
    final before = {for (final o in repo.byType(widget.type)) o.id};
    await widget.onCreate(context);
    // Neu Angelegtes landet im geöffneten Ordner.
    if (_path.isEmpty) return;
    for (final o in repo.byType(widget.type)) {
      if (!before.contains(o.id)) {
        repo.setData(o.id, {...o.data, 'category': _path});
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final repo = Services.of(context).objects;
    final mf = context.mf;
    return ListenableBuilder(
      listenable: repo,
      builder: (context, _) {
        final all = repo.byType(widget.type);
        final folders = allFolders(repo, widget.type);
        if (_path.isNotEmpty && !folders.contains(_path)) _path = '';
        final subs = subFolders(folders, _path);
        final here = [for (final o in all) if (o.category == _path) o];
        if (_byName) {
          here.sort((a, b) => a.displayTitle
              .toLowerCase()
              .compareTo(b.displayTitle.toLowerCase()));
        }
        final createButton = FilledButton.icon(
          onPressed: () => _create(context),
          icon: const Icon(Icons.add, size: 18),
          label: Text(widget.createLabel),
        );
        final parts = _path.isEmpty ? const <String>[] : _path.split('/');

        return ListView(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
          children: [
            PageHeader(
              title: _path.isEmpty ? widget.title : folderName(_path),
              subtitle: _path.isEmpty
                  ? '${widget.subtitle}${all.isEmpty ? '' : ' · ${all.length}'}'
                  : '${widget.title} · Ordner',
              actions: [
                IconButton(
                  tooltip: _byName
                      ? 'Sortiert nach Name – tippen: nach Datum'
                      : 'Sortiert nach Datum – tippen: nach Name',
                  icon: Icon(_byName
                      ? Icons.sort_by_alpha_rounded
                      : Icons.schedule_rounded),
                  onPressed: () => setState(() => _byName = !_byName),
                ),
                const SizedBox(width: 4),
                OutlinedButton.icon(
                  onPressed: () async {
                    final p = await askNewFolder(context, _path);
                    if (p != null) {
                      addFolder(repo, widget.type, p);
                      setState(() {});
                    }
                  },
                  icon: const Icon(Icons.create_new_folder_outlined, size: 18),
                  label: const Text('Ordner'),
                ),
                const SizedBox(width: 8),
                if (all.isNotEmpty || _path.isNotEmpty) createButton,
              ],
            ),
            if (_path.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 18),
                child: Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    TextButton.icon(
                      onPressed: () => setState(() => _path = ''),
                      icon: const Icon(Icons.home_outlined, size: 18),
                      label: Text(widget.title),
                    ),
                    for (var i = 0; i < parts.length; i++) ...[
                      Icon(Icons.chevron_right, size: 18, color: mf.textMuted),
                      TextButton(
                        onPressed: () => setState(
                            () => _path = parts.take(i + 1).join('/')),
                        child: Text(parts[i]),
                      ),
                    ],
                  ],
                ),
              ),
            if (subs.isNotEmpty) ...[
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (final f in subs)
                    _FolderTile(
                      path: f,
                      count: all
                          .where((o) =>
                              o.category == f || o.category.startsWith('$f/'))
                          .length,
                      onOpen: () => setState(() => _path = f),
                      onRename: () async {
                        final n = await askText(context,
                            title: 'Ordner umbenennen',
                            initial: folderName(f));
                        final name = n?.trim().replaceAll('/', '-') ?? '';
                        if (name.isEmpty) return;
                        final parent = f.contains('/')
                            ? f.substring(0, f.lastIndexOf('/'))
                            : '';
                        moveFolder(repo, widget.type, f,
                            parent.isEmpty ? name : '$parent/$name');
                      },
                      onDissolve: () => moveFolder(repo, widget.type, f,
                          f.contains('/') ? f.substring(0, f.lastIndexOf('/')) : ''),
                    ),
                ],
              ),
              const SizedBox(height: 28),
            ],
            if (all.isEmpty && _path.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 40),
                child: EmptyState(
                  icon: widget.emptyIcon,
                  title: widget.emptyTitle,
                  message: widget.emptyMessage,
                  action: createButton,
                ),
              )
            else if (here.isEmpty && _path.isNotEmpty && subs.isEmpty)
              Text('Dieser Ordner ist leer.',
                  style: TextStyle(color: mf.textMuted))
            else
              ObjectGrid(objects: here),
          ],
        );
      },
    );
  }
}

class _FolderTile extends StatelessWidget {
  const _FolderTile({
    required this.path,
    required this.count,
    required this.onOpen,
    required this.onRename,
    required this.onDissolve,
  });

  final String path;
  final int count;
  final VoidCallback onOpen;
  final VoidCallback onRename;
  final VoidCallback onDissolve;

  @override
  Widget build(BuildContext context) {
    final mf = context.mf;
    return Material(
      color: mf.surface,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: mf.border)),
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(16),
        child: SizedBox(
          width: 210,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 4, 10),
            child: Row(
              children: [
                Icon(Icons.folder_rounded, color: mf.accent, size: 30),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(folderName(path),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontWeight: FontWeight.w600, color: mf.text)),
                      Text('$count ${count == 1 ? 'Eintrag' : 'Einträge'}',
                          style: TextStyle(fontSize: 12, color: mf.textMuted)),
                    ],
                  ),
                ),
                CleanMenuButton(
                  size: 32,
                  iconColor: mf.textMuted,
                  entries: const [
                    CleanMenuEntry('rename', 'Umbenennen',
                        icon: Icons.drive_file_rename_outline),
                    CleanMenuEntry('dissolve', 'Ordner auflösen',
                        icon: Icons.folder_off_outlined,
                        subtitle: 'Inhalt wandert eine Ebene höher'),
                  ],
                  onSelected: (v) => v == 'rename' ? onRename() : onDissolve(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
