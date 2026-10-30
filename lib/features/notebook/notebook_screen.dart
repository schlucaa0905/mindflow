import 'package:flutter/material.dart';

import '../../app/services.dart';
import '../../app/theme.dart';
import '../../data/models.dart';
import '../../ink/ink_surface.dart';
import '../../storage/ink_store.dart';
import '../../ui/widgets.dart';
import 'page_painter.dart';

/// Ein geöffnetes Notizbuch: eine Seite zur Zeit, Blättern, Seitenverwaltung.
class NotebookScreen extends StatefulWidget {
  const NotebookScreen({super.key, required this.notebookId, this.initialPageId});

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

  Future<void> _goTo(int i) async {
    if (i < 0 || i >= _pages.length || i == _index) return;
    await _surfaceKey.currentState?.flush();
    setState(() {
      _index = i;
      _surfaceKey = GlobalKey();
    });
  }

  Future<void> _addPage({bool duplicate = false}) async {
    await _surfaceKey.currentState?.flush();
    final current = _page;
    final page = _s.objects.create(
      type: ObjectType.page,
      parentId: widget.notebookId,
      position: _s.objects.positionAfter(current),
      data: duplicate
          ? Map<String, dynamic>.of(current.data)
          : {'template': _notebook!.template.name},
    );
    if (duplicate) await InkStore.duplicate(current.id, page.id);
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

  void _setTemplate(MfObject page, PageTemplate t) {
    _s.objects.setData(page.id, {...page.data, 'template': t.name});
    setState(_reload);
  }

  Future<void> _rename() async {
    final t = await askText(context,
        title: 'Notizbuch umbenennen', initial: _notebook!.title);
    if (t == null || t.trim().isEmpty) return;
    _s.objects.rename(widget.notebookId, t.trim());
    setState(_reload);
  }

  void _showPages() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          final mf = ctx.mf;
          void refresh() => setSheet(() {});
          return SafeArea(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(ctx).size.height * 0.7),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 12, 8),
                    child: Row(
                      children: [
                        Text('Seiten',
                            style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w600,
                                color: mf.text)),
                        const Spacer(),
                        TextButton.icon(
                          onPressed: () async {
                            Navigator.pop(ctx);
                            await _addPage();
                          },
                          icon: const Icon(Icons.add, size: 18),
                          label: const Text('Seite hinzufügen'),
                        ),
                      ],
                    ),
                  ),
                  Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: _pages.length,
                      itemBuilder: (_, i) {
                        final p = _pages[i];
                        return ListTile(
                          selected: i == _index,
                          leading: CircleAvatar(
                            radius: 16,
                            backgroundColor:
                                i == _index ? mf.accent : mf.surfaceRaised,
                            child: Text('${i + 1}',
                                style: TextStyle(
                                    fontSize: 13,
                                    color: i == _index
                                        ? Colors.white
                                        : mf.text)),
                          ),
                          title: Text('Seite ${i + 1}'),
                          subtitle: Text(p.template.label),
                          onTap: () {
                            Navigator.pop(ctx);
                            _goTo(i);
                          },
                          trailing: PopupMenuButton<String>(
                            onSelected: (v) async {
                              switch (v) {
                                case 'up':
                                  _move(p, -1);
                                  refresh();
                                case 'down':
                                  _move(p, 1);
                                  refresh();
                                case 'dup':
                                  Navigator.pop(ctx);
                                  if (i != _index) await _goTo(i);
                                  await _addPage(duplicate: true);
                                case 'del':
                                  Navigator.pop(ctx);
                                  _deletePage(p);
                                default:
                                  final t = PageTemplate.values
                                      .where((t) => 'tpl:${t.name}' == v)
                                      .firstOrNull;
                                  if (t != null) {
                                    _setTemplate(p, t);
                                    refresh();
                                  }
                              }
                            },
                            itemBuilder: (_) => [
                              if (i > 0)
                                const PopupMenuItem(
                                    value: 'up', child: Text('Nach oben')),
                              if (i < _pages.length - 1)
                                const PopupMenuItem(
                                    value: 'down', child: Text('Nach unten')),
                              const PopupMenuItem(
                                  value: 'dup', child: Text('Duplizieren')),
                              const PopupMenuDivider(),
                              for (final t in PageTemplate.values)
                                PopupMenuItem(
                                  value: 'tpl:${t.name}',
                                  child: Row(children: [
                                    SizedBox(
                                      width: 24,
                                      child: p.template == t
                                          ? const Icon(Icons.check, size: 16)
                                          : null,
                                    ),
                                    Text('Vorlage: ${t.label}'),
                                  ]),
                                ),
                              const PopupMenuDivider(),
                              const PopupMenuItem(
                                  value: 'del', child: Text('Löschen')),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final nb = _notebook;
    if (nb == null || _pages.isEmpty) {
      return const Scaffold(body: Center(child: Text('Notizbuch nicht gefunden')));
    }
    final paper = PaperStyle.of(nb.paper);
    final page = _page;
    final mf = context.mf;

    return Scaffold(
      backgroundColor: paper.desk,
      body: Stack(
        children: [
          Positioned.fill(
            child: InkSurface(
              key: _surfaceKey,
              inkId: page.id,
              paper: nb.paper,
              fitRect: kPageRect,
              toolbarTop: 64,
              onSaved: () => _s.objects.touch(nb.id),
              backgroundBuilder: (camera) => PagePainter(
                camera: camera,
                paper: paper,
                template: page.template,
              ),
            ),
          ),
          // Kopfzeile
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                child: Row(
                  children: [
                    FloatingPanel(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ToolButton(
                            icon: Icons.arrow_back,
                            label: 'Zurück',
                            onTap: () => Navigator.of(context).maybePop(),
                          ),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 260),
                            child: InkWell(
                              onTap: _rename,
                              borderRadius: BorderRadius.circular(8),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 10),
                                child: Text(nb.displayTitle,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        color: mf.text)),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // Seitennavigation unten
          Positioned(
            bottom: 16,
            left: 0,
            right: 0,
            child: SafeArea(
              top: false,
              child: Center(
                child: FloatingPanel(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ToolButton(
                        icon: Icons.chevron_left,
                        label: 'Vorherige Seite',
                        onTap: _index > 0 ? () => _goTo(_index - 1) : null,
                      ),
                      InkWell(
                        onTap: _showPages,
                        borderRadius: BorderRadius.circular(8),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                          child: Text('${_index + 1} / ${_pages.length}',
                              style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: mf.text)),
                        ),
                      ),
                      ToolButton(
                        icon: Icons.chevron_right,
                        label: 'Nächste Seite',
                        onTap: _index < _pages.length - 1
                            ? () => _goTo(_index + 1)
                            : null,
                      ),
                      const PanelDivider(),
                      ToolButton(
                        icon: Icons.note_add_outlined,
                        label: 'Seite dahinter einfügen',
                        onTap: () => _addPage(),
                      ),
                      ToolButton(
                        icon: Icons.view_agenda_outlined,
                        label: 'Alle Seiten',
                        onTap: _showPages,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
