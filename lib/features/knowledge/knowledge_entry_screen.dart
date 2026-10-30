import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/navigation.dart';
import '../../app/services.dart';
import '../../app/theme.dart';
import '../../data/models.dart';
import '../../ui/clean_menu.dart';
import '../../ui/widgets.dart';
import '../common/create_dialogs.dart';
import '../common/object_info.dart';
import '../common/object_picker.dart';

/// Detailseite eines Wissenseintrags: Titel, Text, Tags, Unterthemen und
/// alle Verknüpfungen (zu anderen Einträgen, Seiten, PDFs, Canvas).
/// Alles speichert automatisch.
class KnowledgeEntryScreen extends StatefulWidget {
  const KnowledgeEntryScreen({super.key, required this.entryId});

  final String entryId;

  @override
  State<KnowledgeEntryScreen> createState() => _KnowledgeEntryScreenState();
}

class _KnowledgeEntryScreenState extends State<KnowledgeEntryScreen> {
  late AppServices _s;
  bool _ready = false;
  final _title = TextEditingController();
  final _body = TextEditingController();
  final _tag = TextEditingController();
  Timer? _saveTimer;
  bool _dirty = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_ready) return;
    _s = Services.of(context);
    final e = _s.objects.get(widget.entryId);
    _title.text = e?.title ?? '';
    _body.text = e?.body ?? '';
    _s.objects.markOpened(widget.entryId);
    _ready = true;
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    if (_dirty) {
      // Erst nach dem Schließen speichern: während des Abbaus der Ansicht
      // dürfen andere Ansichten nicht neu gezeichnet werden.
      final title = _title.text, body = _body.text;
      _dirty = false;
      scheduleMicrotask(() => _persist(title, body));
    }
    _title.dispose();
    _body.dispose();
    _tag.dispose();
    super.dispose();
  }

  void _changed() {
    _dirty = true;
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 600), _saveNow);
  }

  void _saveNow() {
    if (!_dirty) return;
    _dirty = false;
    _persist(_title.text, _body.text);
  }

  void _persist(String title, String body) {
    final cur = _s.objects.get(widget.entryId);
    if (cur == null) return;
    final t = title.trim();
    if (t.isNotEmpty && t != cur.title) _s.objects.rename(cur.id, t);
    if (body != cur.body) {
      _s.objects.setData(cur.id, {...cur.data, 'body': body});
    }
  }

  void _setTags(List<String> tags) {
    final cur = _s.objects.get(widget.entryId);
    if (cur == null) return;
    _s.objects.setData(cur.id, {...cur.data, 'tags': tags});
  }

  void _addTag(String raw) {
    final t = raw.trim().replaceAll('#', '');
    _tag.clear();
    if (t.isEmpty) return;
    final cur = _s.objects.get(widget.entryId);
    if (cur == null || cur.tags.contains(t)) return;
    _setTags([...cur.tags, t]);
  }

  Future<void> _link() async {
    final o = await pickObject(context, exclude: {widget.entryId});
    if (o == null) return;
    _s.objects.linkOnce(widget.entryId, o.id);
  }

  /// Eintrag als Karte auf einen Canvas legen.
  Future<void> _addToCanvas() async {
    final board = await pickObject(context,
        title: 'Auf welchen Canvas?', types: {ObjectType.board});
    if (board == null || !mounted) return;
    _saveNow();
    final entry = _s.objects.get(widget.entryId);
    if (entry == null) return;
    final existing = _s.canvas.nodes(board.id);
    final y = existing.isEmpty
        ? 0.0
        : existing.map((n) => n.y + n.h).reduce((a, b) => a > b ? a : b) + 40;
    final node = _s.canvas.createNode(board.id,
        x: 0, y: y, text: entry.displayTitle);
    node.refObjectId = entry.id;
    _s.canvas.updateNode(node);
    _s.objects.linkOnce(entry.id, board.id, type: 'canvas');
    if (!mounted) return;
    await openObject(context, board, focusNodeId: node.id);
  }

  @override
  Widget build(BuildContext context) {
    final mf = context.mf;
    return ListenableBuilder(
      listenable: _s.objects,
      builder: (context, _) {
        final entry = _s.objects.get(widget.entryId);
        if (entry == null || entry.deletedAt != null) {
          return Scaffold(
            appBar: AppBar(),
            body: const Center(child: Text('Eintrag nicht gefunden')),
          );
        }
        // Pfad nach oben (Informatik › Netzwerktechnik › …).
        final path = <MfObject>[];
        var parentId = entry.parentId;
        while (parentId != null && path.length < 12) {
          final p = _s.objects.get(parentId);
          if (p == null || p.deletedAt != null) break;
          path.insert(0, p);
          parentId = p.parentId;
        }
        final children = _s.objects
            .children(entry.id)
            .where((o) => o.type == ObjectType.knowledge && !o.archived)
            .toList();
        final links = _s.objects.linkedObjects(entry.id);

        return Scaffold(
          appBar: AppBar(
            backgroundColor: mf.surface,
            title: Text('Wissen', style: TextStyle(color: mf.textMuted, fontSize: 15)),
            actions: [
              IconButton(
                tooltip: 'Auf einen Canvas legen',
                icon: const Icon(Icons.bubble_chart_outlined),
                onPressed: _addToCanvas,
              ),
              IconButton(
                tooltip: 'Verknüpfen',
                icon: const Icon(Icons.add_link),
                onPressed: _link,
              ),
              CleanMenuButton(
                entries: const [
                  CleanMenuEntry('archive', 'Archivieren',
                      icon: Icons.inventory_2_outlined),
                  CleanMenuEntry('trash', 'In den Papierkorb',
                      icon: Icons.delete_outline, destructive: true),
                ],
                onSelected: (v) {
                  if (v == 'archive') {
                    _s.objects.setArchived(entry.id, true);
                    Navigator.of(context).maybePop();
                  } else if (v == 'trash') {
                    _s.objects.trash(entry.id);
                    Navigator.of(context).maybePop();
                  }
                },
              ),
              const SizedBox(width: 8),
            ],
          ),
          body: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 780),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 48),
                children: [
                  if (path.isNotEmpty)
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        for (final p in path) ...[
                          InkWell(
                            onTap: () => openObject(context, p),
                            child: Text(p.displayTitle,
                                style: TextStyle(
                                    fontSize: 13, color: mf.accent)),
                          ),
                          Icon(Icons.chevron_right,
                              size: 16, color: mf.textMuted),
                        ],
                      ],
                    ),
                  TextField(
                    controller: _title,
                    onChanged: (_) => _changed(),
                    style: TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.5,
                        color: mf.text),
                    decoration: const InputDecoration.collapsed(
                        hintText: 'Titel'),
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      for (final t in entry.tags)
                        InputChip(
                          label: Text('#$t'),
                          onDeleted: () => _setTags(
                              entry.tags.where((x) => x != t).toList()),
                        ),
                      SizedBox(
                        width: 160,
                        child: TextField(
                          controller: _tag,
                          onSubmitted: _addTag,
                          decoration: const InputDecoration(
                            isDense: true,
                            hintText: '+ Tag',
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: _body,
                    onChanged: (_) => _changed(),
                    minLines: 8,
                    maxLines: null,
                    style: TextStyle(fontSize: 16, height: 1.5, color: mf.text),
                    decoration: const InputDecoration(
                      hintText: 'Notizen, Definition, Stichpunkte …',
                    ),
                  ),
                  const SizedBox(height: 28),
                  SectionHeader(
                    'Unterthemen',
                    action: TextButton.icon(
                      onPressed: () =>
                          createKnowledge(context, parentId: entry.id),
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('Unterthema'),
                    ),
                  ),
                  if (children.isEmpty)
                    Text('Noch keine Unterthemen.',
                        style: TextStyle(color: mf.textMuted))
                  else
                    for (final c in children)
                      _LinkTile(
                        icon: Icons.subdirectory_arrow_right,
                        title: c.displayTitle,
                        subtitle: c.body.split('\n').first,
                        onTap: () => openObject(context, c),
                      ),
                  const SizedBox(height: 28),
                  SectionHeader(
                    'Verknüpfungen',
                    action: TextButton.icon(
                      onPressed: _link,
                      icon: const Icon(Icons.add_link, size: 18),
                      label: const Text('Verknüpfen'),
                    ),
                  ),
                  if (links.isEmpty)
                    Text(
                        'Verbinde diesen Eintrag mit anderen Themen, '
                        'Notizbuchseiten, PDFs oder einem Canvas.',
                        style: TextStyle(color: mf.textMuted))
                  else
                    for (final o in links)
                      _LinkTile(
                        icon: iconFor(o.type),
                        title: describeTitle(_s.objects, o),
                        subtitle: typeLabel(o.type),
                        onTap: () => openObject(context, o),
                        onRemove: () => _s.objects.unlink(entry.id, o.id),
                      ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _LinkTile extends StatelessWidget {
  const _LinkTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.onRemove,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final mf = context.mf;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: mf.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: mf.border),
        ),
        child: ListTile(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          leading: Icon(icon, color: mf.accent),
          title: Text(title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: mf.text)),
          subtitle: subtitle.isEmpty
              ? null
              : Text(subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: mf.textMuted)),
          onTap: onTap,
          trailing: onRemove == null
              ? Icon(Icons.chevron_right, color: mf.textMuted)
              : IconButton(
                  tooltip: 'Verknüpfung lösen',
                  icon: Icon(Icons.link_off, color: mf.textMuted),
                  onPressed: onRemove,
                ),
        ),
      ),
    );
  }
}
