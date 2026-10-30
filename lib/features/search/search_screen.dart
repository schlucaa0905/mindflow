import 'package:flutter/material.dart';

import '../../app/navigation.dart';
import '../../app/services.dart';
import '../../app/theme.dart';
import '../../data/models.dart';
import '../../ui/widgets.dart';

/// SEARCH – globale Suche. Ergebnisse führen direkt zum Inhalt.
///
/// Durchsucht jetzt: Titel von Notizbüchern und Canvas-Flächen sowie den
/// Text aller Canvas-Karten. Handschrift wird erst mit Texterkennung
/// durchsuchbar (spätere Phase).
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _ctrl = TextEditingController();
  String _q = '';

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = Services.of(context);
    final mf = context.mf;
    final objects = s.objects.search(_q);
    final nodes = s.canvas.searchNodes(_q);

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
      children: [
        const PageHeader(title: 'Suche'),
        TextField(
          controller: _ctrl,
          autofocus: true,
          onChanged: (v) => setState(() => _q = v),
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search),
            hintText: 'Notizbücher, Canvas, Karten …',
          ),
        ),
        const SizedBox(height: 24),
        if (_q.trim().isEmpty)
          Text('Tippe einen Suchbegriff ein.',
              style: TextStyle(color: mf.textMuted))
        else if (objects.isEmpty && nodes.isEmpty)
          Text('Keine Treffer für „${_q.trim()}“.',
              style: TextStyle(color: mf.textMuted))
        else ...[
          for (final o in objects)
            _ResultTile(
              icon: o.type == ObjectType.notebook
                  ? Icons.menu_book_outlined
                  : Icons.bubble_chart_outlined,
              title: o.displayTitle,
              subtitle: [
                o.type == ObjectType.notebook ? 'Notizbuch' : 'Canvas',
                if (o.archived) 'archiviert',
              ].join(' · '),
              onTap: () => openObject(context, o),
            ),
          for (final n in nodes)
            Builder(builder: (context) {
              final board = s.objects.get(n.boardId);
              return _ResultTile(
                icon: Icons.sticky_note_2_outlined,
                title: n.text.split('\n').first,
                subtitle: 'Karte in ${board?.displayTitle ?? 'Canvas'}',
                onTap: board == null
                    ? null
                    : () => openObject(context, board, focusNodeId: n.id),
              );
            }),
        ],
      ],
    );
  }
}

class _ResultTile extends StatelessWidget {
  const _ResultTile(
      {required this.icon,
      required this.title,
      required this.subtitle,
      this.onTap});

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

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
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          leading: Icon(icon, color: mf.accent),
          title: Text(title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: mf.text)),
          subtitle: Text(subtitle, style: TextStyle(color: mf.textMuted)),
          trailing: Icon(Icons.chevron_right, color: mf.textMuted),
          onTap: onTap,
        ),
      ),
    );
  }
}
