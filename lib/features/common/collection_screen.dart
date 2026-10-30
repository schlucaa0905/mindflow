import 'package:flutter/material.dart';

import '../../app/services.dart';
import '../../app/theme.dart';
import '../../data/models.dart';
import '../../ui/widgets.dart';
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
  /// null = alle Kategorien.
  String? _filter;

  @override
  Widget build(BuildContext context) {
    final repo = Services.of(context).objects;
    final mf = context.mf;
    return ListenableBuilder(
      listenable: repo,
      builder: (context, _) {
        final all = repo.byType(widget.type);
        final categories = widget.type == ObjectType.notebook
            ? repo.categories(widget.type)
            : const <String>[];
        if (_filter != null && !categories.contains(_filter)) _filter = null;
        final createButton = FilledButton.icon(
          onPressed: () => widget.onCreate(context),
          icon: const Icon(Icons.add, size: 18),
          label: Text(widget.createLabel),
        );

        // Gruppen: je Kategorie eine, "Ohne Kategorie" zuletzt.
        final groups = <String, List<MfObject>>{};
        for (final o in all) {
          if (_filter != null && o.category != _filter) continue;
          groups.putIfAbsent(o.category, () => []).add(o);
        }
        final keys = groups.keys.toList()
          ..sort((a, b) {
            if (a.isEmpty) return 1;
            if (b.isEmpty) return -1;
            return a.toLowerCase().compareTo(b.toLowerCase());
          });
        final grouped = categories.isNotEmpty;

        return ListView(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
          children: [
            PageHeader(
              title: widget.title,
              subtitle: '${widget.subtitle}${all.isEmpty ? '' : ' · ${all.length}'}',
              actions: [if (all.isNotEmpty) createButton],
            ),
            if (categories.isNotEmpty) ...[
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ChoiceChip(
                    label: const Text('Alle'),
                    selected: _filter == null,
                    onSelected: (_) => setState(() => _filter = null),
                  ),
                  for (final c in categories)
                    ChoiceChip(
                      label: Text(c),
                      selected: _filter == c,
                      onSelected: (_) => setState(() => _filter = c),
                    ),
                ],
              ),
              const SizedBox(height: 24),
            ],
            if (all.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 40),
                child: EmptyState(
                  icon: widget.emptyIcon,
                  title: widget.emptyTitle,
                  message: widget.emptyMessage,
                  action: createButton,
                ),
              )
            else if (!grouped)
              ObjectGrid(objects: all)
            else
              for (final k in keys) ...[
                Padding(
                  padding: const EdgeInsets.only(bottom: 14, top: 4),
                  child: Text(k.isEmpty ? 'Ohne Kategorie' : k,
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: mf.text)),
                ),
                ObjectGrid(objects: groups[k]!),
                const SizedBox(height: 28),
              ],
          ],
        );
      },
    );
  }
}
