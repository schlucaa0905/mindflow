import 'package:flutter/material.dart';

import '../../app/services.dart';
import '../../app/theme.dart';
import '../../data/models.dart';
import '../../storage/backup.dart';
import '../../ui/widgets.dart';
import '../common/object_info.dart';

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
            const SectionHeader('Datensicherung'),
            const _BackupCard(),
            const SizedBox(height: 28),
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
          leading: Icon(iconFor(object.type), color: mf.textMuted),
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

/// Sichern und Wiederherstellen aller Daten.
class _BackupCard extends StatelessWidget {
  const _BackupCard();

  Future<void> _export(BuildContext context) async {
    final s = Services.of(context);
    final box = context.findRenderObject() as RenderBox?;
    final origin = box == null
        ? const Rect.fromLTWH(0, 0, 10, 10)
        : box.localToGlobal(Offset.zero) & box.size;
    final m = ScaffoldMessenger.of(context);
    try {
      await Backup.export(s.db.raw, origin);
    } catch (e) {
      m.showSnackBar(SnackBar(content: Text('Sicherung fehlgeschlagen: $e')));
    }
  }

  Future<void> _restore(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sicherung wiederherstellen?'),
        content: const Text(
            'Alle jetzigen Daten werden durch die Sicherung ersetzt. '
            'Mach vorher am besten selbst eine Sicherung.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Abbrechen')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Datei wählen')),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final m = ScaffoldMessenger.of(context);
    try {
      if (!await Backup.prepareRestore()) return;
      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Fast fertig'),
          content: const Text(
              'Schließ MindFlow jetzt ganz (in der App-Übersicht nach oben '
              'wischen) und öffne es neu. Beim Start wird die Sicherung '
              'übernommen.'),
          actions: [
            FilledButton(
                onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
          ],
        ),
      );
    } catch (e) {
      m.showSnackBar(SnackBar(content: Text('Wiederherstellen fehlgeschlagen: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final mf = context.mf;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: mf.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: mf.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
              'Speichert alles – Notizen, Handschrift, PDFs, Bilder, Karten – '
              'in eine Datei. Leg sie in iCloud Drive oder auf deinem PC ab.',
              style: TextStyle(color: mf.textMuted, height: 1.4)),
          const SizedBox(height: 14),
          StatefulBuilder(builder: (context, setLocal) {
            final s = Services.of(context);
            final days =
                int.tryParse(s.objects.setting('autoBackupDays') ?? '') ?? 7;
            final last =
                DateTime.tryParse(s.objects.setting('lastAutoBackup') ?? '');
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Automatisch sichern (in der Dateien-App unter „Auf '
                    'meinem iPad › MindFlow › Sicherungen“, die letzten 3):',
                    style: TextStyle(color: mf.text, height: 1.4)),
                const SizedBox(height: 8),
                SegmentedButton<int>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: 0, label: Text('Aus')),
                    ButtonSegment(value: 1, label: Text('Täglich')),
                    ButtonSegment(value: 7, label: Text('Wöchentlich')),
                    ButtonSegment(value: 30, label: Text('Monatlich')),
                  ],
                  selected: {
                    const [0, 1, 7, 30].contains(days) ? days : 7
                  },
                  onSelectionChanged: (v) {
                    s.objects.setSetting('autoBackupDays', '${v.first}');
                    setLocal(() {});
                  },
                ),
                const SizedBox(height: 6),
                Row(children: [
                  Expanded(
                    child: Text(
                        last == null
                            ? 'Noch keine automatische Sicherung.'
                            : 'Letzte: ${last.day}.${last.month}.${last.year}',
                        style: TextStyle(fontSize: 12.5, color: mf.textMuted)),
                  ),
                  TextButton.icon(
                    onPressed: () async {
                      final m = ScaffoldMessenger.of(context);
                      m.showSnackBar(const SnackBar(
                          content: Text('Sicherung wird erstellt …')));
                      final f = await Backup.runAuto(s.db.raw, s.objects,
                          force: true);
                      m.hideCurrentSnackBar();
                      m.showSnackBar(SnackBar(
                          content: Text(f == null
                              ? 'Sicherung fehlgeschlagen.'
                              : 'Gesichert in „Sicherungen“ (Dateien-App).')));
                      setLocal(() {});
                    },
                    icon: const Icon(Icons.folder_open_outlined, size: 18),
                    label: const Text('Jetzt sichern'),
                  ),
                ]),
                const SizedBox(height: 14),
              ],
            );
          }),
          Wrap(spacing: 10, runSpacing: 10, children: [
            Builder(
              builder: (ctx) => FilledButton.icon(
                onPressed: () => _export(ctx),
                icon: const Icon(Icons.save_alt_rounded, size: 18),
                label: const Text('Sicherung erstellen'),
              ),
            ),
            OutlinedButton.icon(
              onPressed: () => _restore(context),
              icon: const Icon(Icons.settings_backup_restore_rounded, size: 18),
              label: const Text('Wiederherstellen'),
            ),
          ]),
        ],
      ),
    );
  }
}
