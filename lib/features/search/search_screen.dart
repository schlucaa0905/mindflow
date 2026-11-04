import 'package:flutter/material.dart';

import '../../app/navigation.dart';
import '../../app/services.dart';
import '../../app/theme.dart';
import '../../data/models.dart';
import '../../ui/widgets.dart';
import '../common/object_info.dart';
import '../../ui/find_dialog.dart';
import '../documents/document_screen.dart';
import '../documents/pdf_service.dart';

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

  /// Gedruckter Text aller PDFs (wird im Hintergrund geladen).
  final Map<MfObject, List<String>> _pdf = {};
  bool _pdfLoading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadPdfTexts());
  }

  Future<void> _loadPdfTexts() async {
    if (!mounted) return;
    final docs = Services.of(context)
        .objects
        .byType(ObjectType.document)
        .where((d) => d.deletedAt == null)
        .toList();
    for (final d in docs) {
      try {
        _pdf[d] = await PdfService.pageTexts(d);
      } catch (_) {}
      if (!mounted) return;
    }
    setState(() => _pdfLoading = false);
  }

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
    final texts = s.texts.search(_q);
    final ql = _q.trim().toLowerCase();
    final pdfHits = ql.isEmpty
        ? const <({MfObject doc, int page, String text})>[]
        : [
            for (final e in _pdf.entries)
              for (var i = 0; i < e.value.length; i++)
                if (e.value[i].toLowerCase().contains(ql))
                  (doc: e.key, page: i, text: e.value[i]),
          ].take(60).toList();

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
            hintText: 'Notizbücher, PDFs, Wissen, Canvas, Karten …',
          ),
        ),
        const SizedBox(height: 24),
        if (_q.trim().isEmpty)
          Text('Tippe einen Suchbegriff ein.',
              style: TextStyle(color: mf.textMuted))
        else if (objects.isEmpty &&
            nodes.isEmpty &&
            texts.isEmpty &&
            pdfHits.isEmpty)
          Text(
              _pdfLoading
                  ? 'Keine Treffer für „${_q.trim()}“ – PDFs werden noch '
                      'durchsucht …'
                  : 'Keine Treffer für „${_q.trim()}“.',
              style: TextStyle(color: mf.textMuted))
        else ...[
          for (final o in objects)
            _ResultTile(
              icon: iconFor(o.type),
              title: o.displayTitle,
              subtitle: [
                typeLabel(o.type),
                if (o.type == ObjectType.knowledge && o.body.trim().isNotEmpty)
                  o.body.trim().split('\n').first,
                if (o.type == ObjectType.flashcard)
                  ((o.data['back'] as String?) ?? '').split('\n').first,
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
          for (final h in pdfHits)
            _ResultTile(
              icon: Icons.picture_as_pdf_outlined,
              title: snippetOf(h.text, _q.trim()),
              subtitle: 'Seite ${h.page + 1} · ${h.doc.displayTitle}',
              onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) =>
                      DocumentScreen(documentId: h.doc.id, initialPage: h.page))),
            ),
          if (_pdfLoading && _q.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text('PDFs werden durchsucht …',
                  style: TextStyle(fontSize: 12.5, color: mf.textMuted)),
            ),
          for (final t in texts)
            Builder(builder: (context) {
              final target = _textOwner(s, t.ownerId);
              if (target == null) return const SizedBox.shrink();
              return _ResultTile(
                icon: Icons.title,
                title: t.snippet,
                subtitle: 'Text in ${target.label}',
                onTap: () => target.open(context),
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

/// Wohin gehört ein Textfeld? Seite, Canvas oder PDF-Seite.
({String label, void Function(BuildContext) open})? _textOwner(
    AppServices s, String ownerId) {
  final o = s.objects.get(ownerId);
  if (o != null) {
    if (o.deletedAt != null) return null;
    return (
      label: describeTitle(s.objects, o),
      open: (context) => openObject(context, o),
    );
  }
  // PDF-Seiten: "<Dokument-ID>-p<Nummer>"
  final m = RegExp(r'^(.+)-p(\d+)$').firstMatch(ownerId);
  if (m == null) return null;
  final doc = s.objects.get(m.group(1)!);
  if (doc == null || doc.deletedAt != null) return null;
  final page = int.tryParse(m.group(2)!) ?? 0;
  return (
    label: 'Seite ${page + 1} · ${doc.displayTitle}',
    open: (context) => Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => DocumentScreen(documentId: doc.id, initialPage: page))),
  );
}
