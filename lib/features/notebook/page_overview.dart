import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../app/services.dart';
import '../../app/theme.dart';
import '../../data/text_repository.dart';
import '../../data/models.dart';
import '../../ink/stroke.dart';
import '../../ink/stroke_renderer.dart';
import '../../ink/text_layer.dart';
import '../../storage/image_store.dart';
import '../../storage/ink_store.dart';
import '../../ui/clean_menu.dart';
import 'page_painter.dart';

/// Alle Seiten als Vorschaubilder (wie die Seitenübersicht in Goodnotes).
/// Gibt die gewählte Seite zurück.
Future<int?> showPageOverview(
  BuildContext context, {
  required String title,
  required int count,
  required int current,
  required Widget Function(BuildContext context, int index) thumbnail,
  List<CleanMenuEntry> Function(int index)? menuItems,
  Future<void> Function(int index, String action)? onMenu,
  VoidCallback? onAdd,
}) {
  return Navigator.of(context).push<int>(MaterialPageRoute(
    fullscreenDialog: true,
    builder: (_) => _PageOverview(
      title: title,
      count: count,
      current: current,
      thumbnail: thumbnail,
      menuItems: menuItems,
      onMenu: onMenu,
      onAdd: onAdd,
    ),
  ));
}

class _PageOverview extends StatelessWidget {
  const _PageOverview({
    required this.title,
    required this.count,
    required this.current,
    required this.thumbnail,
    this.menuItems,
    this.onMenu,
    this.onAdd,
  });

  final String title;
  final int count;
  final int current;
  final Widget Function(BuildContext context, int index) thumbnail;
  final List<CleanMenuEntry> Function(int index)? menuItems;
  final Future<void> Function(int index, String action)? onMenu;
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    final mf = context.mf;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: mf.surface,
        title: Text('$title · $count ${count == 1 ? 'Seite' : 'Seiten'}',
            style: TextStyle(fontSize: 16, color: mf.text)),
        actions: [
          if (onAdd != null)
            TextButton.icon(
              onPressed: () {
                Navigator.pop(context);
                onAdd!();
              },
              icon: const Icon(Icons.add),
              label: const Text('Seite hinzufügen'),
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: GridView.builder(
        padding: const EdgeInsets.all(24),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 180,
          mainAxisExtent: 270,
          crossAxisSpacing: 20,
          mainAxisSpacing: 24,
        ),
        itemCount: count,
        itemBuilder: (context, i) {
          final selected = i == current;
          return Column(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () => Navigator.pop(context, i),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: selected ? mf.accent : Colors.transparent,
                          width: 3),
                    ),
                    child: thumbnail(context, i),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('${i + 1}',
                      style: TextStyle(
                          fontWeight:
                              selected ? FontWeight.w700 : FontWeight.w500,
                          color: selected ? mf.accent : mf.textMuted)),
                  if (menuItems != null)
                    CleanMenuButton(
                      size: 32,
                      iconColor: mf.textMuted,
                      entries: menuItems!(i),
                      onSelected: (a) async {
                        Navigator.pop(context);
                        await onMenu?.call(i, a);
                      },
                    ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Vorschaubild einer Seite: Blatt + Handschrift (+ optional PDF-Seite).
class PageThumbnail extends StatefulWidget {
  const PageThumbnail({
    super.key,
    required this.inkId,
    required this.page,
    required this.paper,
    this.template = PageTemplate.blank,
    this.image,
    this.background,
    this.pageLabel,
  });

  /// Seitenzahl auf dem Blatt (wenn im Notizbuch eingeschaltet).
  final String? pageLabel;

  final String inkId;
  final Rect page;
  final PaperStyle paper;
  final PageTemplate template;

  /// Eigene Vorlage (Bild), falls gesetzt.
  final String? image;

  /// Lädt ein Hintergrundbild (z. B. die PDF-Seite).
  final Future<ui.Image?> Function()? background;

  @override
  State<PageThumbnail> createState() => _PageThumbnailState();
}

class _PageThumbnailState extends State<PageThumbnail> {
  List<Stroke> _strokes = const [];
  List<TextItem> _texts = const [];
  ui.Image? _image;

  @override
  void initState() {
    super.initState();
    _texts = Services.maybeOf(context)?.texts.items(widget.inkId) ?? const [];
    ImageStore.preload([
      for (final t in _texts)
        if (t.file != null) t.file!,
      if (widget.image != null) widget.image!,
    ])
        .then((_) {
      if (mounted) setState(() {});
    });
    InkStore(widget.inkId).load().then((s) {
      if (mounted) setState(() => _strokes = s);
    }).catchError((_) {});
    widget.background?.call().then((img) {
      if (mounted) setState(() => _image = img);
    });
  }

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: widget.page.width / widget.page.height,
      child: DecoratedBox(
        decoration: const BoxDecoration(boxShadow: [
          BoxShadow(
              color: Color(0x26000000), blurRadius: 10, offset: Offset(0, 4)),
        ]),
        child: CustomPaint(
          painter: _ThumbPainter(
            page: widget.page,
            paper: widget.paper,
            template: widget.template,
            bgImage: widget.image,
            pageLabel: widget.pageLabel,
            strokes: _strokes,
            texts: _texts,
            image: _image,
          ),
        ),
      ),
    );
  }
}

class _ThumbPainter extends CustomPainter {
  _ThumbPainter({
    required this.page,
    required this.paper,
    required this.template,
    required this.strokes,
    required this.texts,
    this.bgImage,
    this.pageLabel,
    required this.image,
  });

  final String? pageLabel;

  final Rect page;
  final PaperStyle paper;
  final PageTemplate template;
  final List<Stroke> strokes;
  final List<TextItem> texts;
  final String? bgImage;
  final ui.Image? image;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / page.width;
    canvas.save();
    canvas.scale(s);
    canvas.translate(-page.left, -page.top);
    paintSheet(canvas, page, paper, template,
        hairline: 1 / s, shadow: false, image: bgImage);
    final img = image;
    if (img != null) {
      canvas.drawImageRect(
        img,
        Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
        page,
        Paint()..filterQuality = FilterQuality.medium,
      );
    }
    canvas.clipRect(page);
    paintPageImages(canvas, texts);
    for (final st in strokes) {
      if (!st.deleted && st.tool == InkTool.highlighter) paintStroke(canvas, st);
    }
    for (final st in strokes) {
      if (!st.deleted && st.tool != InkTool.highlighter) paintStroke(canvas, st);
    }
    paintTextItems(canvas, texts);
    paintPageLabel(canvas, page, paper, pageLabel);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_ThumbPainter old) => true;
}

/// Seitenleiste mit Vorschauen (wie Goodnotes): antippen springt hin,
/// lange drücken und ziehen sortiert um, „…“ öffnet das Seitenmenü.
class PageSidebar extends StatelessWidget {
  const PageSidebar({
    super.key,
    required this.count,
    required this.current,
    required this.thumbnail,
    required this.onSelect,
    this.onReorder,
    this.menuItems,
    this.onMenu,
  });

  final int count;
  final int current;
  final Widget Function(BuildContext context, int index) thumbnail;
  final ValueChanged<int> onSelect;
  final void Function(int from, int to)? onReorder;
  final List<CleanMenuEntry> Function(int index)? menuItems;
  final Future<void> Function(int index, String action)? onMenu;

  @override
  Widget build(BuildContext context) {
    final mf = context.mf;
    Widget item(BuildContext context, int i) => Padding(
          key: ValueKey(i),
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
          child: Column(children: [
            GestureDetector(
              onTap: () => onSelect(i),
              child: Container(
                height: 150,
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: i == current ? mf.accent : Colors.transparent,
                      width: 2.5),
                ),
                child: Center(child: thumbnail(context, i)),
              ),
            ),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text('${i + 1}',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight:
                          i == current ? FontWeight.w700 : FontWeight.w400,
                      color: i == current ? mf.accent : mf.textMuted)),
              if (menuItems != null)
                CleanMenuButton(
                  size: 28,
                  iconColor: mf.textMuted,
                  entries: menuItems!(i),
                  onSelected: (a) => onMenu?.call(i, a),
                ),
            ]),
          ]),
        );
    return Container(
      width: 150,
      decoration: BoxDecoration(
        color: mf.surface,
        border: Border(right: BorderSide(color: mf.border)),
      ),
      child: onReorder == null
          ? ListView.builder(itemCount: count, itemBuilder: item)
          : ReorderableListView.builder(
              itemCount: count,
              buildDefaultDragHandles: false,
              onReorder: onReorder!,
              itemBuilder: (context, i) => ReorderableDelayedDragStartListener(
                key: ValueKey('p$i'),
                index: i,
                child: item(context, i),
              ),
            ),
    );
  }
}
