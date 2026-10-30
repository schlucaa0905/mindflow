import 'package:flutter/material.dart';

import '../../app/services.dart';
import '../../app/theme.dart';
import '../../data/models.dart';
import '../../ui/widgets.dart';

/// ARCHIVE – archivierte Inhalte und Papierkorb, alles wiederherstellbar.
class ArchiveScreen extends StatelessWidget {
  const ArchiveScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final repo = Services.of(context).objects;
    final mf = context.mf;
    return ListenableBuilder(
      listenable: repo,
      builder: (context, _) {
        final archived = repo.archivedItems();
        final trashed = repo.trashed();
        return ListView(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
          children: [
            const PageHeader(
              title: 'Archiv',
              subtitle: 'Nichts geht verloren – alles lässt sich wiederherstellen.',
            ),
            const SectionHeader('Archiviert'),
            if (archived.isEmpty)
              _hint('Nichts archiviert.', mf)
            else
              for (final o in archived)
                _Row(
                  object: o,
                  info: 'archiviert · ${relativeTime(o.updatedAt)}',
                  onRestore: () => repo.setArchived(o.id, false),
                ),
            const SizedBox(height: 28),
            const SectionHeader('Papierkorb'),
            if (trashed.isEmpty)
              _hint('Der Papierkorb ist leer.', mf)
            else
              for (final o in trashed)
                _Row(
                  object: o,
                  info: 'gelöscht ${relativeTime(o.deletedAt!)}',
                  onRestore: () => repo.restore(o.id),
                ),
          ],
        );
      },
    );
  }

  Widget _hint(String t, MfPalette mf) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(t, style: TextStyle(color: mf.textMuted)),
      );
}

class _Row extends StatelessWidget {
  const _Row(
      {required this.object, required this.info, required this.onRestore});

  final MfObject object;
  final String info;
  final VoidCallback onRestore;

  @override
  Widget build(BuildContext context) {
    final mf = context.mf;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: mf.surface,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: mf.border)),
        child: ListTile(
          leading: Icon(
            object.type == ObjectType.notebook
                ? Icons.menu_book_outlined
                : Icons.bubble_chart_outlined,
            color: mf.textMuted,
          ),
          title: Text(object.displayTitle, style: TextStyle(color: mf.text)),
          subtitle: Text(info, style: TextStyle(color: mf.textMuted)),
          trailing: TextButton.icon(
            onPressed: onRestore,
            icon: const Icon(Icons.restore, size: 18),
            label: const Text('Wiederherstellen'),
          ),
        ),
      ),
    );
  }
}
