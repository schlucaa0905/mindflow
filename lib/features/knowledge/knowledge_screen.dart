import 'package:flutter/material.dart';

import '../../app/navigation.dart';
import '../../app/services.dart';
import '../../app/theme.dart';
import '../../data/models.dart';
import '../../ui/widgets.dart';
import '../common/create_dialogs.dart';

/// KNOWLEDGE – das zentrale Wissensarchiv als Baum
/// (z. B. Informatik → Netzwerktechnik → DHCP).
class KnowledgeScreen extends StatefulWidget {
  const KnowledgeScreen({super.key});

  @override
  State<KnowledgeScreen> createState() => _KnowledgeScreenState();
}

class _KnowledgeScreenState extends State<KnowledgeScreen> {
  String _q = '';
  final Set<String> _collapsed = {};

  @override
  Widget build(BuildContext context) {
    final repo = Services.of(context).objects;
    final mf = context.mf;
    return ListenableBuilder(
      listenable: repo,
      builder: (context, _) {
        final all = repo.byType(ObjectType.knowledge);
        final ids = {for (final o in all) o.id};
        final byParent = <String?, List<MfObject>>{};
        for (final o in all) {
          // Eltern gelöscht oder archiviert → als oberste Ebene zeigen.
          final parent = ids.contains(o.parentId) ? o.parentId : null;
          byParent.putIfAbsent(parent, () => []).add(o);
        }
        for (final list in byParent.values) {
          list.sort((a, b) =>
              a.displayTitle.toLowerCase().compareTo(b.displayTitle.toLowerCase()));
        }

        final rows = <Widget>[];
        void addTree(String? parent, int depth) {
          for (final o in byParent[parent] ?? const <MfObject>[]) {
            final kids = byParent[o.id]?.length ?? 0;
            final open = !_collapsed.contains(o.id);
            rows.add(_EntryTile(
              entry: o,
              depth: depth,
              childCount: kids,
              expanded: open,
              linkCount: repo.linkedIds(o.id).length,
              onToggle: kids == 0
                  ? null
                  : () => setState(() =>
                      open ? _collapsed.add(o.id) : _collapsed.remove(o.id)),
              onAddChild: () => createKnowledge(context, parentId: o.id),
            ));
            if (open) addTree(o.id, depth + 1);
          }
        }

        final searching = _q.trim().isNotEmpty;
        if (searching) {
          for (final o in repo
              .search(_q)
              .where((o) => o.type == ObjectType.knowledge)) {
            rows.add(_EntryTile(
              entry: o,
              depth: 0,
              childCount: byParent[o.id]?.length ?? 0,
              expanded: false,
              linkCount: repo.linkedIds(o.id).length,
              onAddChild: () => createKnowledge(context, parentId: o.id),
            ));
          }
        } else {
          addTree(null, 0);
        }

        final newButton = FilledButton.icon(
          onPressed: () => createKnowledge(context),
          icon: const Icon(Icons.add, size: 18),
          label: const Text('Neuer Eintrag'),
        );

        return ListView(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
          children: [
            PageHeader(
              title: 'Wissen',
              subtitle: all.isEmpty
                  ? 'Themen, Unterthemen und ihre Verbindungen'
                  : '${all.length} ${all.length == 1 ? 'Eintrag' : 'Einträge'}',
              actions: [if (all.isNotEmpty) newButton],
            ),
            if (all.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 40),
                child: EmptyState(
                  icon: Icons.hub_outlined,
                  title: 'Noch kein Wissen gesammelt',
                  message:
                      'Lege Themen an, ordne Unterthemen darunter und verknüpfe '
                      'sie mit Notizbuchseiten, PDFs und dem Canvas. Tipp: Im '
                      'Notizbuch über „…“ → „Wissenseintrag aus Seite“.',
                  action: newButton,
                ),
              )
            else ...[
              TextField(
                onChanged: (v) => setState(() => _q = v),
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Im Wissen suchen (Titel und Text)',
                ),
              ),
              const SizedBox(height: 16),
              if (rows.isEmpty)
                Text('Keine Treffer.', style: TextStyle(color: mf.textMuted))
              else
                ...rows,
            ],
          ],
        );
      },
    );
  }
}

class _EntryTile extends StatelessWidget {
  const _EntryTile({
    required this.entry,
    required this.depth,
    required this.childCount,
    required this.expanded,
    required this.linkCount,
    required this.onAddChild,
    this.onToggle,
  });

  final MfObject entry;
  final int depth;
  final int childCount;
  final bool expanded;
  final int linkCount;
  final VoidCallback? onToggle;
  final VoidCallback onAddChild;

  @override
  Widget build(BuildContext context) {
    final mf = context.mf;
    final preview = entry.body.trim().split('\n').first;
    return Padding(
      padding: EdgeInsets.only(left: depth * 22.0, bottom: 6),
      child: Material(
        color: mf.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: mf.border),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => openObject(context, entry),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
            child: Row(
              children: [
                SizedBox(
                  width: 36,
                  child: onToggle == null
                      ? Icon(Icons.circle, size: 6, color: mf.textMuted)
                      : IconButton(
                          visualDensity: VisualDensity.compact,
                          icon: Icon(
                              expanded ? Icons.expand_more : Icons.chevron_right,
                              color: mf.textMuted),
                          onPressed: onToggle,
                        ),
                ),
                Icon(Icons.hub_outlined, size: 18, color: mf.accent),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(entry.displayTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontWeight: FontWeight.w600, color: mf.text)),
                      if (preview.isNotEmpty)
                        Text(preview,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style:
                                TextStyle(fontSize: 12, color: mf.textMuted)),
                    ],
                  ),
                ),
                for (final t in entry.tags.take(3))
                  Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: mf.accentSoft,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text('#$t',
                          style: TextStyle(fontSize: 11, color: mf.accent)),
                    ),
                  ),
                if (linkCount > 0)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Row(children: [
                      Icon(Icons.link, size: 14, color: mf.textMuted),
                      Text(' $linkCount',
                          style: TextStyle(fontSize: 12, color: mf.textMuted)),
                    ]),
                  ),
                IconButton(
                  tooltip: 'Unterthema hinzufügen',
                  icon: Icon(Icons.add, size: 18, color: mf.textMuted),
                  onPressed: onAddChild,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
