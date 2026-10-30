import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/navigation.dart';
import '../../app/services.dart';
import '../../app/theme.dart';
import '../../data/models.dart';
import '../../export/pdf_export.dart';
import '../../ink/ink_controller.dart';
import '../../ink/ink_surface.dart';
import '../../storage/ink_store.dart';
import '../../ui/editor_bar.dart';
import '../../ui/widgets.dart';
import '../common/create_dialogs.dart';
import 'page_overview.dart';
import 'page_painter.dart';

/// Ein geöffnetes Notizbuch im Goodnotes-Stil: oben Navigation und
/// Werkzeuge, darunter das Blatt. Geschrieben wird nur auf dem Blatt.
class NotebookScreen extends StatefulWidget {
  const NotebookScreen(
      {super.key, required this.notebookId, this.initialPageId});

  final String notebookId;
  final String? initialPageId;

  @override
  State<NotebookScreen> createState() => _NotebookScreenState();
}

class _NotebookScreenState extends State<NotebookScreen> {
  late AppServices _s;
  MfObject? _notebook;
  List<MfObject> _pages = [];
  int _index = 0;
  GlobalKey<InkSurfaceState> _surfaceKey = GlobalKey();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_notebook != null) return;
    _s = Services.of(context);
    _s.objects.markOpened(widget.notebookId);
    _reload();
    if (widget.initialPageId != null) {
      final i = _pages.indexWhere((p) => p.id == widget.initialPageId);
      if (i >= 0) _index = i;
    }
  }

  void _reload() {
    _notebook = _s.objects.get(widget.notebookId);
    _pages = _s.objects.children(widget.notebookId);
    if (_pages.isEmpty && _notebook != null) {
      _s.objects.create(
        type: ObjectType.page,
        parentId: widget.notebookId,
        data: {'template': _notebook!.template.name},
      );
      _pages = _s.objects.children(widget.notebookId);
    }
    if (_pages.isEmpty) {
      _index = 0;
    } else if (_index >= _pages.length) {
      _index = _pages.length - 1;
    }
  }

  MfObject get _page => _pages[_index];

  Future<void> _flush() async => _surfaceKey.currentState?.flush();

  Future<void> _goTo(int i) async {
    if (i < 0 || i >= _pages.length || i == _index) return;
    await _flush();
    if (!mounted) return;
    setState(() {
      _index = i;
      _surfaceKey = GlobalKey();
    });
  }

  Future<void> _addPage({bool duplicate = false, int? after}) async {
    await _flush();
    final base = _pages[after ?? _index];
    final page = _s.objects.create(
      type: ObjectType.page,
      parentId: widget.notebookId,
      position: _s.objects.positionAfter(base),
      data: duplicate
          ? Map<String, dynamic>.of(base.data)
          : {'template': _notebook!.template.name},
    );
    if (duplicate) await InkStore.duplicate(base.id, page.id);
    if (!mounted) return;
    setState(() {
      _reload();
      _index = _pages.indexWhere((p) => p.id == page.id);
      _surfaceKey = GlobalKey();
    });
  }

  void _deletePage(MfObject page) {
    if (_pages.length <= 1) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Ein Notizbuch braucht mindestens eine Seite.')));
      return;
    }
    _s.objects.trash(page.id);
    setState(() {
      _reload();
      _surfaceKey = GlobalKey();
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: const Text('Seite gelöscht'),
      action: SnackBarAction(
        label: 'Rückgängig',
        onPressed: () {
          _s.objects.restore(page.id);
          if (mounted) setState(_reload);
        },
      ),
    ));
  }

  void _move(MfObject page, int dir) {
    final i = _pages.indexWhere((p) => p.id == page.id);
    final j = i + dir;
    if (i < 0 || j < 0 || j >= _pages.length) return;
    _s.objects.swapPositions(_pages[i], _pages[j]);
    final currentId = _page.id;
    setState(() {
      _reload();
      _index = _pages.indexWhere((p) => p.id == currentId);
    });
  }

  Future<void> _chooseTemplate(MfObject page) async {
    final t = await showDialog<PageTemplate>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Vorlage dieser Seite'),
        children: [
          for (final t in PageTemplate.values)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, t),
              child: Row(children: [
                SizedBox(
                    width: 28,
                    child: page.template == t
                        ? const Icon(Icons.check, size: 18)
                        : null),
                Text(t.label),
              ]),
            ),
        ],
      ),
    );
    if (t == null) return;
    _s.objects.setData(page.id, {...page.data, 'template': t.name});
    setState(_reload);
  }

  /// Titel, Umschlag, Papier, Format, Kategorie ändern.
  Future<void> _editNotebook() async {
    await _flush();
    if (!mounted) return;
    await editNotebook(context, _notebook!);
    if (!mounted) return;
    setState(() {
      _reload();
      _surfaceKey = GlobalKey();
    });
  }

  Future<void> _showOverview() async {
    await _flush();
    if (!mounted) return;
    final nb = _notebook!;
    final rect = pageRectFor(nb.format);
    final paper = PaperStyle.of(nb.paper);
    final picked = await showPageOverview(
      context,
      title: nb.displayTitle,
      count: _pages.length,
      current: _index,
      thumbnail: (context, i) => PageThumbnail(
        inkId: _pages[i].id,
        page: rect,
        paper: paper,
        template: _pages[i].template,
      ),
      onAdd: () => _addPage(after: _pages.length - 1),
      menuItems: (i) => [
        if (i > 0) const PopupMenuItem(value: 'up', child: Text('Nach vorne')),
        if (i < _pages.length - 1)
          const PopupMenuItem(value: 'down', child: Text('Nach hinten')),
        const PopupMenuItem(value: 'dup', child: Text('Duplizieren')),
        const PopupMenuItem(value: 'tpl', child: Text('Vorlage ändern')),
        const PopupMenuItem(value: 'del', child: Text('Löschen')),
      ],
      onMenu: (i, action) async {
        final p = _pages[i];
        switch (action) {
          case 'up':
            _move(p, -1);
          case 'down':
            _move(p, 1);
          case 'dup':
            await _addPage(duplicate: true, after: i);
          case 'tpl':
            await _chooseTemplate(p);
          case 'del':
            _deletePage(p);
        }
      },
    );
    if (picked != null) await _goTo(picked);
  }

  /// Aus der aktuellen Seite einen Wissenseintrag machen (mit Verknüpfung).
  Future<void> _createKnowledgeFromPage() async {
    final title = await askText(context,
        title: 'Wissenseintrag aus dieser Seite',
        hint: 'Thema, z. B. DHCP',
        confirm: 'Erstellen');
    if (title == null || title.trim().isEmpty || !mounted) return;
    final entry = _s.objects.create(
      type: ObjectType.knowledge,
      title: title.trim(),
      data: {'body': '', 'tags': <String>[]},
    );
    _s.objects.link(entry.id, _page.id, type: 'source');
    await openObject(context, entry);
  }

  Future<void> _export() async {
    await _flush();
    if (!mounted) return;
    final nb = _notebook!;
    final rect = pageRectFor(nb.format);
    final paper = PaperStyle.of(nb.paper);
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(const SnackBar(content: Text('PDF wird erstellt …')));
    try {
      final pages = <ExportPage>[];
      for (final p in _pages) {
        final strokes = await InkStore(p.id).load();
        pages.add(await renderPage(
          page: rect,
          strokes: strokes,
          paintBackground: (canvas) => paintSheet(
              canvas, rect, paper, p.template,
              hairline: 0.6, shadow: false),
        ));
      }
      await sharePdf(nb.displayTitle, pages);
    } catch (e) {
      messenger.showSnackBar(
          SnackBar(content: Text('Export fehlgeschlagen: $e')));
    }
  }

  Widget _nav(BuildContext context, InkController c) {
    final nb = _notebook!;
    return EditorNavBar(
      title: nb.displayTitle,
      subtitle: nb.category.isEmpty ? null : nb.category,
      onTitleTap: _editNotebook,
      center: PagePager(
        index: _index,
        count: _pages.length,
        onPrev: () => _goTo(_index - 1),
        onNext: () => _goTo(_index + 1),
        onTap: _showOverview,
      ),
      actions: [
        ListenableBuilder(
          listenable: c,
          builder: (context, _) => Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              NavIconButton(
                icon: Icons.undo,
                tooltip: 'Rückgängig',
                onTap: c.history.canUndo ? c.undo : null,
              ),
              NavIconButton(
                icon: Icons.redo,
                tooltip: 'Wiederholen',
                onTap: c.history.canRedo ? c.redo : null,
              ),
            ],
          ),
        ),
        NavIconButton(
          icon: Icons.grid_view_rounded,
          tooltip: 'Seitenübersicht',
          onTap: _showOverview,
        ),
        NavIconButton(
          icon: Icons.note_add_outlined,
          tooltip: 'Seite dahinter einfügen',
          onTap: () => _addPage(),
        ),
        EditorMoreMenu(
          controller: c,
          onSelected: (v) async {
            switch (v) {
              case 'dup':
                await _addPage(duplicate: true);
              case 'tpl':
                await _chooseTemplate(_page);
              case 'del':
                _deletePage(_page);
              case 'knowledge':
                await _createKnowledgeFromPage();
              case 'export':
                await _export();
              case 'settings':
                await _editNotebook();
            }
          },
          items: const [
            PopupMenuItem(value: 'dup', child: Text('Seite duplizieren')),
            PopupMenuItem(value: 'tpl', child: Text('Vorlage dieser Seite')),
            PopupMenuItem(value: 'del', child: Text('Seite löschen')),
            PopupMenuDivider(),
            PopupMenuItem(
                value: 'knowledge', child: Text('Wissenseintrag aus Seite')),
            PopupMenuItem(value: 'export', child: Text('Als PDF teilen')),
            PopupMenuDivider(),
            PopupMenuItem(
                value: 'settings', child: Text('Umschlag & Einstellungen')),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final nb = _notebook;
    if (nb == null || _pages.isEmpty) {
      return const Scaffold(
          body: Center(child: Text('Notizbuch nicht gefunden')));
    }
    final paper = PaperStyle.of(nb.paper);
    final page = _page;
    final pageRect = pageRectFor(nb.format);

    // Bild auf/ab bzw. Alt+Pfeil: blättern (Tastatur).
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.pageDown): () =>
            _goTo(_index + 1),
        const SingleActivator(LogicalKeyboardKey.pageUp): () =>
            _goTo(_index - 1),
        const SingleActivator(LogicalKeyboardKey.arrowRight, alt: true): () =>
            _goTo(_index + 1),
        const SingleActivator(LogicalKeyboardKey.arrowLeft, alt: true): () =>
            _goTo(_index - 1),
      },
      child: Scaffold(
        backgroundColor: paper.desk,
        body: InkSurface(
          key: _surfaceKey,
          inkId: page.id,
          paper: nb.paper,
          fitRect: pageRect,
          lockToFit: true,
          drawBounds: pageRect,
          navBar: _nav,
          onSaved: () => _s.objects.touch(nb.id),
          backgroundBuilder: (camera) => PagePainter(
            camera: camera,
            paper: paper,
            template: page.template,
            page: pageRect,
          ),
        ),
      ),
    );
  }
}

/// "…"-Menü mit Zusatzpunkt für die Werkzeugleiste.
class EditorMoreMenu extends StatelessWidget {
  const EditorMoreMenu({
    required this.controller,
    required this.items,
    required this.onSelected,
  });

  final InkController controller;
  final List<PopupMenuEntry<String>> items;
  final Future<void> Function(String value) onSelected;

  @override
  Widget build(BuildContext context) {
    final s = controller.settings;
    return PopupMenuButton<String>(
      tooltip: 'Mehr',
      icon: Icon(Icons.more_horiz, color: context.mf.text),
      onSelected: (v) {
        if (v == '_toolbar') {
          s.update(() {
            if (s.dock == ToolbarDock.top) {
              s.dock = ToolbarDock.floating;
              s.floatX = 0.3;
              s.floatY = 0.05;
            } else {
              s.dock = ToolbarDock.top;
            }
            s.collapsed = false;
          });
          return;
        }
        onSelected(v);
      },
      itemBuilder: (_) => [
        ...items,
        const PopupMenuDivider(),
        PopupMenuItem(
          value: '_toolbar',
          child: Text(s.dock == ToolbarDock.top
              ? 'Werkzeugleiste frei verschiebbar'
              : 'Werkzeugleiste oben fest'),
        ),
      ],
    );
  }
}

