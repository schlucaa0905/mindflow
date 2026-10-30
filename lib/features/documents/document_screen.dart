import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/navigation.dart';
import '../../app/services.dart';
import '../../app/theme.dart';
import '../../data/models.dart';
import '../../export/pdf_export.dart';
import '../../ink/camera.dart';
import '../../ink/ink_controller.dart';
import '../../ink/ink_surface.dart';
import '../../ink/text_layer.dart';
import '../../storage/ink_store.dart';
import '../../ui/clean_menu.dart';
import '../../ui/editor_bar.dart';
import '../../ui/widgets.dart';
import '../notebook/notebook_screen.dart';
import '../notebook/page_overview.dart';
import 'pdf_service.dart';

/// Ein geöffnetes PDF: lesen, mit dem Stift hineinschreiben, markieren.
/// Das Original bleibt unverändert, Anmerkungen liegen darüber.
class DocumentScreen extends StatefulWidget {
  const DocumentScreen({super.key, required this.documentId, this.initialPage = 0});

  final String documentId;
  final int initialPage;

  @override
  State<DocumentScreen> createState() => _DocumentScreenState();
}

class _DocumentScreenState extends State<DocumentScreen> {
  late AppServices _s;
  MfObject? _doc;
  int _index = 0;
  GlobalKey<InkSurfaceState> _surfaceKey = GlobalKey();

  /// Richtung, aus der die nächste Seite hereingleitet.
  int _enterFrom = 0;

  /// Präsentationsmodus: nur das Blatt ist zu sehen.
  bool _presenting = false;
  final ValueNotifier<ui.Image?> _image = ValueNotifier(null);
  bool _failed = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_doc != null) return;
    _s = Services.of(context);
    _doc = _s.objects.get(widget.documentId);
    _s.objects.markOpened(widget.documentId);
    final count = _doc?.pageSizes.length ?? 0;
    _index = widget.initialPage.clamp(0, count == 0 ? 0 : count - 1).toInt();
    _loadImage();
  }

  @override
  void dispose() {
    _image.dispose();
    super.dispose();
  }

  Future<void> _loadImage() async {
    final doc = _doc;
    if (doc == null) return;
    final index = _index;
    _image.value = null;
    try {
      final img = await PdfService.renderPage(doc, index, dpi: 160);
      if (!mounted || index != _index) return;
      _image.value = img;
      if (img == null) setState(() => _failed = true);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  Rect _rectFor(int i) {
    final sizes = _doc!.pageSizes;
    final s = sizes[i];
    return Rect.fromLTWH(0, 0, s.width, s.height);
  }

  Future<void> _goTo(int i) async {
    final count = _doc!.pageSizes.length;
    if (i < 0 || i >= count || i == _index) return;
    await _surfaceKey.currentState?.flush();
    if (!mounted) return;
    setState(() {
      _enterFrom = i > _index ? 1 : -1;
      _index = i;
      _failed = false;
      _surfaceKey = GlobalKey();
    });
    _loadImage();
  }

  Future<void> _showOverview() async {
    await _surfaceKey.currentState?.flush();
    if (!mounted) return;
    final doc = _doc!;
    final picked = await showPageOverview(
      context,
      title: doc.displayTitle,
      count: doc.pageSizes.length,
      current: _index,
      thumbnail: (context, i) => PageThumbnail(
        inkId: PdfService.inkIdFor(doc, i),
        page: _rectFor(i),
        paper: PaperStyle.light,
        background: () => PdfService.renderPage(doc, i, dpi: 40),
      ),
    );
    if (picked != null) await _goTo(picked);
  }

  Future<void> _createKnowledge() async {
    final title = await askText(context,
        title: 'Wissenseintrag zu diesem Dokument',
        hint: 'Thema',
        confirm: 'Erstellen');
    if (title == null || title.trim().isEmpty || !mounted) return;
    final entry = _s.objects.create(
      type: ObjectType.knowledge,
      title: title.trim(),
      data: {
        'body': 'Quelle: ${_doc!.displayTitle}, Seite ${_index + 1}',
        'tags': <String>[],
      },
    );
    _s.objects.link(entry.id, _doc!.id, type: 'source');
    await openObject(context, entry);
  }

  Future<void> _export() async {
    await _surfaceKey.currentState?.flush();
    if (!mounted) return;
    final doc = _doc!;
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
        const SnackBar(content: Text('PDF mit Anmerkungen wird erstellt …')));
    try {
      final pages = <ExportPage>[];
      for (var i = 0; i < doc.pageSizes.length; i++) {
        final rect = _rectFor(i);
        final img = await PdfService.renderPage(doc, i, dpi: 144);
        final strokes = await InkStore(PdfService.inkIdFor(doc, i)).load();
        final texts = _s.texts.items(PdfService.inkIdFor(doc, i));
        pages.add(await renderPage(
          page: rect,
          strokes: strokes,
          paintForeground: (canvas) => paintTextItems(canvas, texts),
          paintBackground: (canvas) {
            canvas.drawRect(rect, Paint()..color = Colors.white);
            if (img != null) {
              canvas.drawImageRect(
                  img,
                  Rect.fromLTWH(
                      0, 0, img.width.toDouble(), img.height.toDouble()),
                  rect,
                  Paint()..filterQuality = FilterQuality.medium);
            }
          },
        ));
      }
      await sharePdf('${doc.displayTitle} (mit Notizen)', pages);
    } catch (e) {
      messenger.showSnackBar(
          SnackBar(content: Text('Export fehlgeschlagen: $e')));
    }
  }

  Widget _nav(BuildContext context, InkController c) {
    final doc = _doc!;
    return EditorNavBar(
      icon: Icons.picture_as_pdf_rounded,
      title: doc.displayTitle,
      subtitle: 'PDF · ${doc.pageSizes.length} Seiten',
      onTitleTap: () async {
        final t = await askText(context,
            title: 'Dokument umbenennen', initial: doc.title);
        if (t == null || t.trim().isEmpty) return;
        _s.objects.rename(doc.id, t.trim());
        setState(() => _doc = _s.objects.get(doc.id));
      },
      center: PagePager(
        index: _index,
        count: doc.pageSizes.length,
        onPrev: () => _goTo(_index - 1),
        onNext: () => _goTo(_index + 1),
        onTap: _showOverview,
      ),
      actions: [
        NavGroup(children: [
          NavIconButton(
            icon: Icons.grid_view_rounded,
            tooltip: 'Seitenübersicht',
            onTap: _showOverview,
          ),
        ]),
        NavGroup(children: [UndoRedoButtons(controller: c)]),
        NavGroup(children: [
          ZoomPill(
            camera: c.camera,
            onFit: () => _surfaceKey.currentState?.fitPage(),
            onFitWidth: () => _surfaceKey.currentState?.fitWidth(),
          ),
        ]),
        NavGroup(children: [
          ListenableBuilder(
            listenable: c,
            builder: (context, _) => NavIconButton(
              icon: Icons.title_rounded,
              tooltip: 'Textfeld (Tastatur) – dann aufs Blatt tippen',
              active: c.tool == ToolMode.text,
              onTap: () => c.setTool(ToolMode.text),
            ),
          ),
          StylusToggle(controller: c),
          NavIconButton(
            icon: Icons.co_present_outlined,
            tooltip: 'Präsentieren (nur das Blatt zeigen)',
            onTap: () => setState(() => _presenting = true),
          ),
        ]),
        EditorMoreMenu(
          entries: const [
            CleanMenuEntry('goto', 'Zu Seite springen …',
                icon: Icons.low_priority_rounded),
            CleanMenuEntry('knowledge', 'Wissenseintrag erstellen',
                icon: Icons.hub_outlined,
                subtitle: 'Mit diesem Dokument verknüpft'),
            CleanMenuEntry.divider(),
            CleanMenuEntry('export', 'Mit Notizen als PDF teilen',
                icon: Icons.ios_share_outlined),
          ],
          onSelected: (v) async {
            if (v == 'goto') {
              final t = await askText(context,
                  title: 'Zu Seite springen',
                  hint: '1 – ${doc.pageSizes.length}',
                  confirm: 'Springen');
              final n = int.tryParse(t?.trim() ?? '');
              if (n != null && mounted) {
                await _goTo((n - 1).clamp(0, doc.pageSizes.length - 1).toInt());
              }
            }
            if (v == 'knowledge') await _createKnowledge();
            if (v == 'export') await _export();
          },
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final doc = _doc;
    if (doc == null || doc.pageSizes.isEmpty) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('Dokument nicht gefunden')),
      );
    }
    final rect = _rectFor(_index);
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.pageDown): () =>
            _goTo(_index + 1),
        const SingleActivator(LogicalKeyboardKey.pageUp): () =>
            _goTo(_index - 1),
      },
      child: Scaffold(
        backgroundColor: PaperStyle.light.desk,
        body: Stack(
          children: [
            Positioned.fill(
              child: InkSurface(
                key: _surfaceKey,
                inkId: PdfService.inkIdFor(doc, _index),
                paper: Paper.light,
                fitRect: rect,
                lockToFit: true,
                drawBounds: rect,
                navBar: _nav,
                presenting: _presenting,
                onExitPresentation: () => setState(() => _presenting = false),
                presentationLabel: '${_index + 1} / ${doc.pageSizes.length}',
                enterFrom: _enterFrom,
                onSwipe: (d) => _goTo(_index + d),
                onSaved: () => _s.objects.touch(doc.id),
                backgroundBuilder: (camera) =>
                    PdfPagePainter(camera: camera, image: _image, page: rect),
              ),
            ),
            if (_failed)
              Positioned(
                left: 16,
                right: 16,
                bottom: 24,
                child: Center(
                  child: FloatingPanel(
                    padding: const EdgeInsets.all(14),
                    child: Text(
                      'Diese Seite konnte nicht dargestellt werden. '
                      'Deine Notizen bleiben trotzdem erhalten.',
                      style: TextStyle(color: context.mf.textMuted),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Zeichnet Schreibtisch, weißes Blatt und die gerenderte PDF-Seite.
class PdfPagePainter extends CustomPainter {
  PdfPagePainter({
    required this.camera,
    required this.image,
    required this.page,
  }) : super(repaint: Listenable.merge([camera, image]));

  final Camera camera;
  final ValueNotifier<ui.Image?> image;
  final Rect page;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = PaperStyle.light.desk);
    canvas.save();
    canvas.translate(camera.offset.dx, camera.offset.dy);
    canvas.scale(camera.scale);
    canvas.drawRect(
      page.shift(const Offset(0, 4)),
      Paint()
        ..color = const Color(0x33000000)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
    );
    canvas.drawRect(page, Paint()..color = Colors.white);
    final img = image.value;
    if (img != null) {
      canvas.drawImageRect(
        img,
        Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
        page,
        Paint()..filterQuality = FilterQuality.medium,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(PdfPagePainter old) =>
      old.camera != camera || old.image != image || old.page != page;
}
