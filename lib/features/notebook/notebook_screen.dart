import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/navigation.dart';
import '../../app/services.dart';
import '../../app/theme.dart';
import '../../data/models.dart';
import '../../export/pdf_export.dart';
import '../../ink/ink_controller.dart';
import '../../ink/ink_surface.dart';
import '../../ink/text_layer.dart';
import '../../ink/tool_row.dart';
import '../../storage/element_library.dart';
import '../../storage/image_store.dart';
import '../../storage/ink_store.dart';
import '../../ui/clean_menu.dart';
import '../../ui/editor_bar.dart';
import '../../ui/find_dialog.dart';
import '../../ui/widgets.dart';
import '../common/create_dialogs.dart';
import '../common/links.dart';
import '../common/object_picker.dart';
import '../documents/pdf_service.dart';
import 'page_design_dialog.dart';
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

  /// Richtung, aus der die nächste Seite hereingleitet.
  int _enterFrom = 0;

  /// Präsentationsmodus: nur das Blatt ist zu sehen.
  bool _presenting = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_notebook != null) return;
    _s = Services.of(context);
    _s.objects.markOpened(widget.notebookId);
    _reload();
    final start = widget.initialPageId ?? _s.lastPage[widget.notebookId];
    if (start != null) {
      final i = _pages.indexWhere((p) => p.id == start);
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
        data: _newPageData(),
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

  /// Daten einer neuen Seite: Vorlage, Abstand und Blattfarbe des Notizbuchs.
  Map<String, dynamic> _newPageData() {
    final d = _notebook!.data;
    return {
      'template': _notebook!.template.name,
      if (d['gap'] is num) 'gap': d['gap'],
      if (d['paperColor'] is int) 'paperColor': d['paperColor'],
      if (d['bgImage'] is String) 'bgImage': d['bgImage'],
    };
  }

  /// Seite benennen (für Inhaltsverzeichnis und Links).
  Future<void> _namePage(MfObject p) async {
    final v = await askText(context,
        title: 'Seite benennen',
        initial: p.title,
        hint: 'z. B. Kapitel 2 – DHCP',
        confirm: 'Speichern');
    if (v == null || !mounted) return;
    _s.objects.rename(p.id, v.trim());
    setState(_reload);
  }

  /// Inhaltsverzeichnis: benannte Seiten und Lesezeichen.
  Future<void> _showContents() async {
    final entries = [
      for (var i = 0; i < _pages.length; i++)
        if (_pages[i].title.trim().isNotEmpty || _isBookmarked(_pages[i])) i
    ];
    final picked = await showDialog<int>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Inhaltsverzeichnis'),
        children: [
          if (entries.isEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(24, 8, 24, 16),
              child: Text('Noch leer. Benenne Seiten über ihr Menü '
                  '(„Seite benennen“) oder setze Lesezeichen.'),
            ),
          for (final i in entries)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, i),
              child: Row(children: [
                SizedBox(
                    width: 44,
                    child: Text('S. ${i + 1}',
                        style: const TextStyle(fontWeight: FontWeight.w600))),
                Expanded(
                    child: Text(_pages[i].title.trim().isEmpty
                        ? 'Lesezeichen'
                        : _pages[i].title.trim())),
                if (_isBookmarked(_pages[i]))
                  const Icon(Icons.bookmark_rounded, size: 18),
              ]),
            ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, -1),
            child: const Row(children: [
              Icon(Icons.edit_outlined, size: 18),
              SizedBox(width: 10),
              Text('Diese Seite benennen …'),
            ]),
          ),
        ],
      ),
    );
    if (picked == null || !mounted) return;
    if (picked < 0) {
      await _namePage(_page);
    } else {
      await _goTo(picked);
    }
  }

  /// Seite (mit Handschrift, Text und Bildern) als eigene Vorlage sichern.
  Future<void> _saveAsTemplate(MfObject p) async {
    final name = await askText(context,
        title: 'Als Vorlage speichern',
        initial: p.title,
        hint: 'z. B. Wochenplan blau',
        confirm: 'Speichern');
    if (name == null || !mounted) return;
    await _flush();
    final nb = _notebook!;
    final rect = pageRectFor(nb.format);
    final ps = pageStyle(PaperStyle.of(nb.paper), p);
    final texts = _s.texts.items(p.id);
    final bg = p.data['bgImage'] as String?;
    await ImageStore.preload([
      for (final t in texts)
        if (t.file != null && t.isImage) t.file!,
      if (bg != null) bg,
    ]);
    final img = await renderPage(
      page: rect,
      strokes: await InkStore(p.id).load(),
      paintForeground: (canvas) => paintTextItems(canvas, texts),
      paintBackground: (canvas) {
        paintSheet(canvas, rect, ps, p.template,
            hairline: 0.6, shadow: false, image: bg);
        paintPageImages(canvas, texts);
      },
    );
    final file = await ImageStore.save(img.png, 'png');
    saveCustomTemplates(_s.objects, [
      ...loadCustomTemplates(_s.objects),
      (name: name.trim().isEmpty ? 'Eigene Vorlage' : name.trim(), file: file),
    ]);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Gespeichert – zu finden unter „Seite gestalten“.')));
  }

  /// Schreibfläche: dunkles oder helles Papier (für die Stiftfarben).
  static Paper _inkPaper(PaperStyle style, Paper notebook) =>
      isDarkSheet(style.sheet)
          ? Paper.dark
          : notebook == Paper.dark
              ? Paper.light
              : notebook;

  /// „Seite gestalten“: Vorlage, Abstand, Blattfarbe – für diese, alle
  /// und auf Wunsch auch neue Seiten.
  Future<void> _designPage(MfObject page) async {
    final nb = _notebook!;
    final base = PaperStyle.of(nb.paper);
    final d = await showPageDesign(context,
        page: page, notebookPaper: base, format: nb.format, repo: _s.objects);
    if (d == null || !mounted) return;
    await _flush();
    final switched = <String>[];
    var toDark = false;
    for (final p in d.allPages ? _pages : [page]) {
      final wasDark = isDarkSheet(pageStyle(base, p).sheet);
      final data = {...p.data, 'template': d.template.name, 'gap': d.gap};
      if (d.bgImage == null) {
        data.remove('bgImage');
      } else {
        data['bgImage'] = d.bgImage;
      }
      if (d.color == null) {
        data.remove('paperColor');
      } else {
        data['paperColor'] = d.color;
      }
      _s.objects.setData(p.id, data);
      toDark = isDarkSheet(d.color == null ? base.sheet : Color(d.color!));
      if (wasDark != toDark) switched.add(p.id);
    }
    if (d.forNewPages) {
      final data = {...nb.data, 'template': d.template.name, 'gap': d.gap};
      if (d.color == null) {
        data.remove('paperColor');
      } else {
        data['paperColor'] = d.color;
      }
      if (d.bgImage == null) {
        data.remove('bgImage');
      } else {
        data['bgImage'] = d.bgImage;
      }
      _s.objects.setData(nb.id, data);
    }
    // Hell ↔ dunkel: Schriftfarben anbieten anzupassen.
    if (switched.isNotEmpty && mounted) {
      await offerRecolor(context, switched, toDark: toDark);
    }
    if (!mounted) return;
    setState(() {
      _reload();
      _enterFrom = 0;
      _surfaceKey = GlobalKey();
    });
  }

  /// Seitenzahl für Seite [i] (null, wenn ausgeschaltet).
  String? _pageLabel(int i) =>
      PageNumbers.of(_notebook!).textFor(i, _pages.length);

  Future<void> _choosePageNumbers() async {
    final nb = _notebook!;
    final now = PageNumbers.of(nb);
    final picked = await showDialog<PageNumbers>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Seitenzahlen'),
        children: [
          for (final m in PageNumbers.values)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, m),
              child: Row(children: [
                Icon(m == now ? Icons.check_rounded : null, size: 20),
                const SizedBox(width: 10),
                Text(m.label),
              ]),
            ),
        ],
      ),
    );
    if (picked == null || picked == now || !mounted) return;
    _s.objects.setData(nb.id, {...nb.data, 'pageNumbers': picked.index});
    setState(_reload);
  }

  Future<void> _flush() async => _surfaceKey.currentState?.flush();

  Future<void> _goTo(int i) async {
    if (i < 0 || i >= _pages.length || i == _index) return;
    await _flush();
    if (!mounted) return;
    setState(() {
      _enterFrom = i > _index ? 1 : -1;
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
          : _newPageData(),
    );
    if (duplicate) {
      await InkStore.duplicate(base.id, page.id);
      _s.texts.duplicateAll(base.id, page.id);
    }
    if (!mounted) return;
    setState(() {
      _reload();
      _index = _pages.indexWhere((p) => p.id == page.id);
      _enterFrom = 1;
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
      _enterFrom = 0;
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

  /// Eine Seite aus einem importierten PDF als Hintergrund dieser Seite.
  Future<void> _pdfAsTemplate() async {
    final doc = await pickObject(context,
        title: 'Welches Dokument?', types: {ObjectType.document});
    if (doc == null || !mounted) return;
    final count = doc.pageSizes.length;
    var index = 0;
    if (count > 1) {
      final v = await askText(context,
          title: 'Welche Seite?', hint: '1 – $count', confirm: 'Übernehmen');
      final n = int.tryParse(v?.trim() ?? '');
      if (n == null) return;
      index = (n - 1).clamp(0, count - 1).toInt();
    }
    final img = await PdfService.renderPage(doc, index, dpi: 150);
    final png = await img?.toByteData(format: ui.ImageByteFormat.png);
    if (png == null || !mounted) return;
    final name = await ImageStore.save(png.buffer.asUint8List(), 'png');
    final p = _s.objects.get(_page.id);
    if (p == null || !mounted) return;
    _s.objects.setData(p.id, {...p.data, 'bgImage': name});
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
      _enterFrom = 0;
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
      thumbnail: (context, i) => Stack(
        children: [
          PageThumbnail(
            inkId: _pages[i].id,
            page: rect,
            paper: pageStyle(paper, _pages[i]),
            template: _pages[i].template,
            image: _pages[i].data['bgImage'] as String?,
            pageLabel: _pageLabel(i),
          ),
          if (_isBookmarked(_pages[i]))
            Positioned(
              top: 0,
              right: 10,
              child: Icon(Icons.bookmark_rounded,
                  size: 26, color: context.mf.accent),
            ),
        ],
      ),
      onAdd: () => _addPage(after: _pages.length - 1),
      menuItems: _pageMenu,
      onMenu: _onPageMenu,
    );
    if (picked != null) await _goTo(picked);
  }

  List<CleanMenuEntry> _pageMenu(int i) => [
        if (i > 0)
          const CleanMenuEntry('up', 'Nach vorne', icon: Icons.arrow_back),
        if (i < _pages.length - 1)
          const CleanMenuEntry('down', 'Nach hinten',
              icon: Icons.arrow_forward),
        const CleanMenuEntry('dup', 'Duplizieren', icon: Icons.copy_all_outlined),
        const CleanMenuEntry('tpl', 'Seite gestalten …',
            icon: Icons.palette_outlined,
            subtitle: 'Vorlage, Abstand, Farbe'),
        const CleanMenuEntry('name', 'Seite benennen …',
            icon: Icons.label_outline_rounded),
        const CleanMenuEntry('savetpl', 'Als Vorlage speichern …',
            icon: Icons.save_as_outlined),
        const CleanMenuEntry.divider(),
        const CleanMenuEntry('del', 'Löschen',
            icon: Icons.delete_outline, destructive: true),
      ];

  Future<void> _onPageMenu(int i, String action) async {
    final p = _pages[i];
    switch (action) {
      case 'up':
        _move(p, -1);
      case 'down':
        _move(p, 1);
      case 'dup':
        await _addPage(duplicate: true, after: i);
      case 'tpl':
        await _designPage(p);
      case 'name':
        await _namePage(p);
      case 'savetpl':
        await _saveAsTemplate(p);
      case 'del':
        _deletePage(p);
    }
  }

  /// Seitenleiste: Seite per Ziehen an eine neue Stelle setzen.
  void _reorder(int from, int to) {
    if (to > from) to--;
    if (to == from) return;
    final list = [..._pages];
    final p = list.removeAt(from);
    list.insert(to, p);
    final before = to > 0 ? list[to - 1].position : null;
    final after = to < list.length - 1 ? list[to + 1].position : null;
    final pos = before == null
        ? after! - 1
        : after == null
            ? before + 1
            : (before + after) / 2;
    _s.objects.setPosition(p.id, pos);
    final cur = _page.id;
    setState(() {
      _reload();
      _index = _pages.indexWhere((x) => x.id == cur);
    });
  }

  /// Seitenleiste links ein-/ausgeblendet (bleibt für die Sitzung).
  static bool _sidebar = false;

  /// Lesemodus an?
  bool _reading = false;

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
      final numbers = PageNumbers.of(nb);
      for (var i = 0; i < _pages.length; i++) {
        final p = _pages[i];
        final label = numbers.textFor(i, _pages.length);
        final strokes = await InkStore(p.id).load();
        final texts = _s.texts.items(p.id);
        final bg = p.data['bgImage'] as String?;
        await ImageStore.preload([
          for (final t in texts)
            if (t.file != null) t.file!,
          if (bg != null) bg,
        ]);
        pages.add(await renderPage(
          page: rect,
          strokes: strokes,
          paintForeground: (canvas) => paintTextItems(canvas, texts),
          paintBackground: (canvas) {
            final ps = pageStyle(paper, p);
            paintSheet(canvas, rect, ps, p.template,
                hairline: 0.6, shadow: false, image: bg);
            paintPageLabel(canvas, rect, ps, label);
            paintPageImages(canvas, texts);
          },
        ));
      }
      await sharePdf(nb.displayTitle, pages);
    } catch (e) {
      messenger.showSnackBar(
          SnackBar(content: Text('Export fehlgeschlagen: $e')));
    }
  }

  bool _isBookmarked(MfObject p) => p.data['bookmark'] == true;

  void _toggleBookmark() {
    final p = _page;
    final on = !_isBookmarked(p);
    _s.objects.setData(p.id, {...p.data, 'bookmark': on});
    setState(_reload);
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        duration: const Duration(seconds: 2),
        content: Text(on
            ? 'Lesezeichen auf Seite ${_index + 1} gesetzt'
            : 'Lesezeichen entfernt')));
  }

  /// Springt zum nächsten Lesezeichen (danach wieder von vorn).
  Future<void> _nextBookmark() async {
    for (var k = 1; k <= _pages.length; k++) {
      final i = (_index + k) % _pages.length;
      if (_isBookmarked(_pages[i])) {
        await _goTo(i);
        return;
      }
    }
  }

  Future<void> _askGoTo() async {
    final v = await askText(context,
        title: 'Zu Seite springen',
        hint: '1 – ${_pages.length}',
        confirm: 'Springen');
    final n = int.tryParse(v?.trim() ?? '');
    if (n == null || !mounted) return;
    await _goTo((n - 1).clamp(0, _pages.length - 1).toInt());
  }

  Future<void> _addPageBefore() async {
    await _flush();
    final base = _page;
    final position = _index == 0
        ? base.position - 1
        : _s.objects.positionAfter(_pages[_index - 1]);
    final page = _s.objects.create(
      type: ObjectType.page,
      parentId: widget.notebookId,
      position: position,
      data: _newPageData(),
    );
    if (!mounted) return;
    setState(() {
      _reload();
      _index = _pages.indexWhere((p) => p.id == page.id);
      _enterFrom = -1;
      _surfaceKey = GlobalKey();
    });
  }

  Widget _nav(BuildContext context, InkController c) {
    final nb = _notebook!;
    final bookmarked = _isBookmarked(_page);
    final anyBookmark = _pages.any(_isBookmarked);
    return EditorNavBar(
      icon: Icons.menu_book_rounded,
      tabId: nb.id,
      title: nb.displayTitle,
      subtitle: nb.category.isEmpty ? null : nb.category,
      onTitleTap: _editNotebook,
      leading: [
        NavIconButton(
          icon: Icons.view_sidebar_outlined,
          tooltip: 'Seitenleiste',
          active: _sidebar,
          onTap: () => setState(() => _sidebar = !_sidebar),
        ),
        ListenableBuilder(
          listenable: c,
          builder: (context, _) => NavIconButton(
            icon: c.drawingEnabled
                ? Icons.visibility_outlined
                : Icons.visibility_rounded,
            tooltip: c.drawingEnabled
                ? 'Lesemodus (nichts aus Versehen malen)'
                : 'Lesemodus beenden',
            active: !c.drawingEnabled,
            onTap: () => c.setDrawingEnabled(!c.drawingEnabled),
          ),
        ),
        NavIconButton(
          icon: Icons.search_rounded,
          tooltip: 'Im Notizbuch suchen',
          onTap: () async {
            await _flush();
            if (!context.mounted) return;
            await showFindDialog(context, (q) => [
                  for (var i = 0; i < _pages.length; i++)
                    for (final t in _s.texts.items(_pages[i].id))
                      if (!t.isImage &&
                          t.text.toLowerCase().contains(q.toLowerCase()))
                        (
                          title: 'Seite ${i + 1}',
                          snippet: snippetOf(t.text, q),
                          open: () => _goTo(i),
                        ),
                ]);
          },
        ),
        NavIconButton(
          icon: bookmarked
              ? Icons.bookmark_rounded
              : Icons.bookmark_border_rounded,
          tooltip: bookmarked ? 'Lesezeichen entfernen' : 'Lesezeichen setzen',
          active: bookmarked,
          onTap: _toggleBookmark,
        ),
      ],
      center: ToolModeButtons(controller: c),
      actions: [
        PagePager(
          index: _index,
          count: _pages.length,
          onPrev: () => _goTo(_index - 1),
          onNext: () => _goTo(_index + 1),
          onTap: _showOverview,
        ),
        ZoomPill(
          camera: c.camera,
          onFit: () => _surfaceKey.currentState?.fitPage(),
          onFitWidth: () => _surfaceKey.currentState?.fitWidth(),
        ),
        StylusToggle(controller: c),
        CleanMenuButton(
          tooltip: 'Seite hinzufügen',
          icon: Icons.note_add_outlined,
          entries: const [
            CleanMenuEntry('after', 'Neue Seite danach',
                icon: Icons.note_add_outlined),
            CleanMenuEntry('before', 'Neue Seite davor',
                icon: Icons.post_add_rounded),
            CleanMenuEntry('dup', 'Seite duplizieren',
                icon: Icons.copy_all_outlined),
            CleanMenuEntry('tpl', 'Seite gestalten …',
                icon: Icons.palette_outlined,
                subtitle: 'Vorlage, Abstand, Farbe'),
            CleanMenuEntry('pdfbg', 'PDF-Seite als Vorlage',
                icon: Icons.picture_as_pdf_outlined,
                subtitle: 'Aus deinen Dokumenten'),
            CleanMenuEntry.divider(),
            CleanMenuEntry('photo', 'Bild aus Fotos',
                icon: Icons.photo_library_outlined),
            CleanMenuEntry('file', 'Bild aus Dateien',
                icon: Icons.image_outlined),
            CleanMenuEntry('element', 'Element einfügen …',
                icon: Icons.widgets_outlined,
                subtitle: 'Aus deiner Bibliothek'),
          ],
          onSelected: (v) async {
            switch (v) {
              case 'element':
                await showElementPicker(context, c);
              case 'pdfbg':
                await _pdfAsTemplate();
              case 'photo':
                await _surfaceKey.currentState?.insertImage();
              case 'file':
                await _surfaceKey.currentState?.insertImage(fromFiles: true);
              case 'after':
                await _addPage();
              case 'before':
                await _addPageBefore();
              case 'dup':
                await _addPage(duplicate: true);
              case 'tpl':
                await _designPage(_page);
            }
          },
        ),
        NavIconButton(
          icon: Icons.ios_share_rounded,
          tooltip: 'Als PDF teilen',
          onTap: _export,
        ),
        NavIconButton(
          icon: Icons.co_present_outlined,
          tooltip: 'Präsentieren (nur das Blatt zeigen)',
          onTap: () => setState(() => _presenting = true),
        ),
        EditorMoreMenu(
          entries: [
            const CleanMenuEntry('design', 'Seite gestalten …',
                icon: Icons.format_paint_outlined,
                subtitle: 'Vorlage, Abstand, Farbe dieser Seite'),
            const CleanMenuEntry('settings', 'Notizbuch bearbeiten',
                icon: Icons.palette_outlined,
                subtitle: 'Umschlag, Papier, Format, Vorlage'),
            const CleanMenuEntry.divider(),
            const CleanMenuEntry('goto', 'Zu Seite springen …',
                icon: Icons.low_priority_rounded),
            if (anyBookmark)
              const CleanMenuEntry('nextmark', 'Nächstes Lesezeichen',
                  icon: Icons.bookmarks_outlined),
            const CleanMenuEntry('toc', 'Inhaltsverzeichnis',
                icon: Icons.toc_rounded),
            const CleanMenuEntry('name', 'Seite benennen …',
                icon: Icons.label_outline_rounded),
            const CleanMenuEntry('savetpl', 'Als Vorlage speichern …',
                icon: Icons.save_as_outlined),
            const CleanMenuEntry('split', 'Daneben öffnen …',
                icon: Icons.vertical_split_outlined,
                subtitle: 'Zwei Inhalte nebeneinander'),
            const CleanMenuEntry('knowledge', 'Wissenseintrag aus Seite',
                icon: Icons.hub_outlined),
            CleanMenuEntry('pagenum', 'Seitenzahlen …',
                icon: Icons.format_list_numbered_rounded,
                subtitle: PageNumbers.of(_notebook!).label),
            const CleanMenuEntry.divider(),
            const CleanMenuEntry('export', 'Als PDF teilen',
                icon: Icons.ios_share_outlined),
            const CleanMenuEntry.divider(),
            const CleanMenuEntry('del', 'Seite löschen',
                icon: Icons.delete_outline, destructive: true),
          ],
          onSelected: (v) async {
            switch (v) {
              case 'goto':
                await _askGoTo();
              case 'nextmark':
                await _nextBookmark();
              case 'del':
                _deletePage(_page);
              case 'knowledge':
                await _createKnowledgeFromPage();
              case 'export':
                await _export();
              case 'settings':
                await _editNotebook();
              case 'pagenum':
                await _choosePageNumbers();
              case 'design':
                await _designPage(_page);
              case 'toc':
                await _showContents();
              case 'name':
                await _namePage(_page);
              case 'savetpl':
                await _saveAsTemplate(_page);
              case 'split':
                await openSplitWith(context, _notebook!);
            }
          },
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
    final style = pageStyle(paper, page);
    _s.lastPage[nb.id] = page.id;
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
          paper: _inkPaper(style, nb.paper),
          linkNotebookId: nb.id,
          onOpenLink: (t) => openLinkTarget(context, t, goToPage: (id) {
            final i = _pages.indexWhere((p) => p.id == id);
            if (i < 0) return false;
            _goTo(i);
            return true;
          }),
          fitRect: pageRect,
          lockToFit: true,
          drawBounds: pageRect,
          textGrid: textGridFor(page.template, style.gap),
          navBar: _nav,
          presenting: _presenting,
          onExitPresentation: () => setState(() => _presenting = false),
          presentationLabel: '${_index + 1} / ${_pages.length}',
          enterFrom: _enterFrom,
          // Nach der letzten Seite weiterwischen: neue Seite (wie Goodnotes).
          onSwipe: (d) => d > 0 && _index == _pages.length - 1
              ? _addPage()
              : _goTo(_index + d),
          // Lesemodus gilt fürs ganze Dokument, auch beim Blättern.
          onControllerReady: (c) {
            c.setDrawingEnabled(!_reading);
            c.addListener(() => _reading = !c.drawingEnabled);
          },
          leftPanel: !_sidebar
              ? null
              : PageSidebar(
                  count: _pages.length,
                  current: _index,
                  onSelect: _goTo,
                  onReorder: _reorder,
                  menuItems: _pageMenu,
                  onMenu: _onPageMenu,
                  thumbnail: (context, i) => PageThumbnail(
                    key: ValueKey('${_pages[i].id}${_pageLabel(i)}'),
                    inkId: _pages[i].id,
                    page: pageRect,
                    paper: pageStyle(paper, _pages[i]),
                    template: _pages[i].template,
                    image: _pages[i].data['bgImage'] as String?,
                    pageLabel: _pageLabel(i),
                  ),
                ),
          onSaved: () => _s.objects.touch(nb.id),
          backgroundBuilder: (camera) => PagePainter(
            camera: camera,
            paper: style,
            template: page.template,
            page: pageRect,
            image: page.data['bgImage'] as String?,
            pageLabel: _pageLabel(_index),
          ),
        ),
      ),
    );
  }
}

/// "…"-Menü in der Kopfleiste – modern und aufgeräumt.
class EditorMoreMenu extends StatelessWidget {
  const EditorMoreMenu({
    super.key,
    required this.entries,
    required this.onSelected,
  });

  final List<CleanMenuEntry> entries;
  final Future<void> Function(String value) onSelected;

  @override
  Widget build(BuildContext context) {
    return CleanMenuButton(
      entries: entries,
      onSelected: (v) => onSelected(v),
    );
  }
}
