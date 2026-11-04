import 'dart:convert';

import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../data/models.dart';
import '../../data/object_repository.dart';
import '../../ui/widgets.dart';

/// Ordner für Notizbücher, Canvas und Dokumente. Ein Ordner ist ein Pfad
/// wie „Schule/Mathe“ (gespeichert als Kategorie des Objekts). Leere Ordner
/// merkt sich die App in den Einstellungen.
String _key(ObjectType t) => 'folders.${t.name}';

List<String> _saved(ObjectRepository repo, ObjectType t) {
  try {
    final v = jsonDecode(repo.setting(_key(t)) ?? '[]');
    return [for (final e in v as List) if (e is String && e.isNotEmpty) e];
  } catch (_) {
    return const [];
  }
}

/// Alle Ordner (inkl. übergeordneter), alphabetisch.
List<String> allFolders(ObjectRepository repo, ObjectType t) {
  final set = <String>{};
  for (final f in [...repo.categories(t), ..._saved(repo, t)]) {
    final parts = f.split('/');
    for (var i = 1; i <= parts.length; i++) {
      set.add(parts.take(i).join('/'));
    }
  }
  return set.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
}

/// Direkte Unterordner von [path] ('' = oberste Ebene).
List<String> subFolders(List<String> all, String path) => [
      for (final f in all)
        if (path.isEmpty
            ? !f.contains('/')
            : f.startsWith('$path/') && !f.substring(path.length + 1).contains('/'))
          f
    ];

void addFolder(ObjectRepository repo, ObjectType t, String path) => repo
    .setSetting(_key(t), jsonEncode({..._saved(repo, t), path}.toList()));

/// Ordner umbenennen bzw. auflösen ([to] = übergeordneter Ordner).
void moveFolder(ObjectRepository repo, ObjectType t, String from, String to) {
  for (final o in repo.byType(t)) {
    final c = o.category;
    if (c == from || c.startsWith('$from/')) {
      final rest = c.substring(from.length);
      var next = '$to$rest';
      if (next.startsWith('/')) next = next.substring(1);
      repo.setData(o.id, {...o.data, 'category': next});
    }
  }
  final saved = [
    for (final f in _saved(repo, t))
      if (f == from || f.startsWith('$from/'))
        ('$to${f.substring(from.length)}').replaceFirst(RegExp(r'^/'), '')
      else
        f
  ].where((f) => f.isNotEmpty).toSet().toList();
  repo.setSetting(_key(t), jsonEncode(saved));
}

String folderName(String path) => path.split('/').last;

/// Fragt nach einem neuen Ordnernamen unter [parent].
Future<String?> askNewFolder(BuildContext context, String parent) async {
  final name = await askText(context,
      title: parent.isEmpty ? 'Neuer Ordner' : 'Neuer Ordner in „${folderName(parent)}“',
      hint: 'z. B. Schule',
      confirm: 'Erstellen');
  final n = name?.trim().replaceAll('/', '-') ?? '';
  if (n.isEmpty) return null;
  return parent.isEmpty ? n : '$parent/$n';
}

/// Ordner auswählen (Verschieben). '' = oberste Ebene, null = abgebrochen.
Future<String?> pickFolder(
    BuildContext context, ObjectRepository repo, ObjectType t) {
  final folders = allFolders(repo, t);
  return showDialog<String>(
    context: context,
    builder: (ctx) => SimpleDialog(
      title: const Text('Verschieben nach …'),
      children: [
        SimpleDialogOption(
          onPressed: () => Navigator.pop(ctx, ''),
          child: const Row(children: [
            Icon(Icons.home_outlined, size: 20),
            SizedBox(width: 12),
            Text('Oberste Ebene'),
          ]),
        ),
        for (final f in folders)
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, f),
            child: Padding(
              padding: EdgeInsets.only(left: 16.0 * '/'.allMatches(f).length),
              child: Row(children: [
                Icon(Icons.folder_outlined, size: 20, color: ctx.mf.accent),
                const SizedBox(width: 12),
                Flexible(child: Text(folderName(f))),
              ]),
            ),
          ),
        SimpleDialogOption(
          onPressed: () async {
            final p = await askNewFolder(ctx, '');
            if (p != null && ctx.mounted) Navigator.pop(ctx, p);
          },
          child: const Row(children: [
            Icon(Icons.create_new_folder_outlined, size: 20),
            SizedBox(width: 12),
            Text('Neuer Ordner …'),
          ]),
        ),
      ],
    ),
  );
}
