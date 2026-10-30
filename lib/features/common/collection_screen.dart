import 'package:flutter/material.dart';

import '../../app/services.dart';
import '../../data/models.dart';
import '../../ui/widgets.dart';
import 'object_card.dart';

/// Übersicht aller Notizbücher bzw. aller Canvas-Flächen.
class CollectionScreen extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final repo = Services.of(context).objects;
    return ListenableBuilder(
      listenable: repo,
      builder: (context, _) {
        final items = repo.byType(type);
        final createButton = FilledButton.icon(
          onPressed: () => onCreate(context),
          icon: const Icon(Icons.add, size: 18),
          label: Text(createLabel),
        );
        return ListView(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
          children: [
            PageHeader(
              title: title,
              subtitle: subtitle,
              actions: [if (items.isNotEmpty) createButton],
            ),
            if (items.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 40),
                child: EmptyState(
                  icon: emptyIcon,
                  title: emptyTitle,
                  message: emptyMessage,
                  action: createButton,
                ),
              )
            else
              ObjectGrid(objects: items),
          ],
        );
      },
    );
  }
}
