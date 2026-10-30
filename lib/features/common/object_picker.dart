import 'package:flutter/material.dart';

import '../../app/services.dart';
import '../../app/theme.dart';
import '../../data/models.dart';
import 'object_info.dart';

/// Dialog: ein Objekt suchen und auswählen (zum Verknüpfen).
///
/// [types] schränkt die Auswahl ein (z. B. nur Wissenseinträge).
/// [exclude] blendet Objekte aus (z. B. sich selbst).
Future<MfObject?> pickObject(
  BuildContext context, {
  String title = 'Verknüpfen mit …',
  Set<ObjectType>? types,
  Set<String> exclude = const {},
}) {
  return showDialog<MfObject>(
    context: context,
    builder: (_) =>
        _ObjectPicker(title: title, types: types, exclude: exclude),
  );
}

class _ObjectPicker extends StatefulWidget {
  const _ObjectPicker(
      {required this.title, required this.types, required this.exclude});

  final String title;
  final Set<ObjectType>? types;
  final Set<String> exclude;

  @override
  State<_ObjectPicker> createState() => _ObjectPickerState();
}

class _ObjectPickerState extends State<_ObjectPicker> {
  String _q = '';

  bool _allowed(MfObject o) =>
      !widget.exclude.contains(o.id) &&
      (widget.types == null || widget.types!.contains(o.type));

  List<MfObject> _results(AppServices s) {
    final repo = s.objects;
    if (_q.trim().isNotEmpty) {
      return repo.search(_q).where(_allowed).toList();
    }
    // Ohne Suchbegriff: Wissen zuerst, dann zuletzt Geöffnetes.
    final seen = <String>{};
    final out = <MfObject>[];
    for (final o in [
      ...repo.byType(ObjectType.knowledge),
      ...repo.recent(limit: 20),
    ]) {
      if (_allowed(o) && seen.add(o.id)) out.add(o);
    }
    return out.take(40).toList();
  }

  @override
  Widget build(BuildContext context) {
    final s = Services.of(context);
    final mf = context.mf;
    final results = _results(s);
    return AlertDialog(
      title: Text(widget.title),
      contentPadding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      content: SizedBox(
        width: 460,
        height: 420,
        child: Column(
          children: [
            TextField(
              autofocus: true,
              onChanged: (v) => setState(() => _q = v),
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Suchen …',
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: results.isEmpty
                  ? Center(
                      child: Text('Nichts gefunden',
                          style: TextStyle(color: mf.textMuted)))
                  : ListView.builder(
                      itemCount: results.length,
                      itemBuilder: (_, i) {
                        final o = results[i];
                        return ListTile(
                          leading: Icon(iconFor(o.type), color: mf.accent),
                          title: Text(describeTitle(s.objects, o),
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Text(typeLabel(o.type)),
                          onTap: () => Navigator.pop(context, o),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Abbrechen')),
      ],
    );
  }
}
