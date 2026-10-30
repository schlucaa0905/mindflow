import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/theme.dart';
import '../data/text_repository.dart';
import '../ui/clean_menu.dart';
import 'ink_controller.dart';
import 'list_formatter.dart';

/// Schriftstil eines Textfelds – identisch auf dem Bildschirm, in
/// Vorschaubildern und im PDF-Export.
TextStyle textItemStyle(TextItem t) {
  final (family, fallback) = switch (t.font) {
    TextFont.sans => (null, null),
    TextFont.serif => ('Georgia', const ['Times New Roman', 'serif']),
    TextFont.mono => ('Menlo', const ['Consolas', 'Courier New', 'monospace']),
    TextFont.rounded =>
      ('Avenir Next', const ['Segoe UI', 'Arial Rounded MT Bold']),
  };
  return TextStyle(
    fontSize: t.size,
    height: 1.3,
    color: Color(t.color),
    fontFamily: family,
    fontFamilyFallback: fallback,
    fontWeight: t.bold ? FontWeight.w700 : FontWeight.w400,
    fontStyle: t.italic ? FontStyle.italic : FontStyle.normal,
    decoration: t.underline ? TextDecoration.underline : null,
    decorationColor: Color(t.color),
  );
}

/// Innenabstand je nach Hintergrund (in Seiten-Punkten).
EdgeInsets textItemPadding(TextItem t) => switch (t.background) {
      TextBackground.none => EdgeInsets.zero,
      TextBackground.marker => const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      TextBackground.box || TextBackground.note => const EdgeInsets.all(10),
    };

/// Hintergrund eines Textfelds (Textmarker, Kasten, Notiz).
BoxDecoration? textItemDecoration(TextItem t) {
  final c = Color(t.color);
  switch (t.background) {
    case TextBackground.none:
      return null;
    case TextBackground.marker:
      return BoxDecoration(
        color: const Color(0xFFFACC15).withValues(alpha: 0.38),
        borderRadius: BorderRadius.circular(3),
      );
    case TextBackground.box:
      return BoxDecoration(
        border: Border.all(color: c.withValues(alpha: 0.55), width: 1.4),
        borderRadius: BorderRadius.circular(8),
      );
    case TextBackground.note:
      return BoxDecoration(
        color: c.withValues(alpha: 0.10),
        border: Border(left: BorderSide(color: c, width: 4)),
        borderRadius: BorderRadius.circular(6),
      );
  }
}

/// Zeichnet Textfelder direkt auf eine Leinwand (Export, Vorschau).
void paintTextItems(Canvas canvas, List<TextItem> items) {
  for (final t in items) {
    if (t.text.trim().isEmpty) continue;
    final pad = textItemPadding(t);
    final inner = math.max(1.0, t.w - pad.horizontal);
    final tp = TextPainter(
      text: TextSpan(text: t.text, style: textItemStyle(t)),
      textDirection: TextDirection.ltr,
      textAlign: t.align,
    )..layout(minWidth: inner, maxWidth: inner);
    final box = Rect.fromLTWH(t.x, t.y, t.w, tp.height + pad.vertical);
    final deco = textItemDecoration(t);
    if (deco != null) {
      final painter = deco.createBoxPainter();
      painter.paint(canvas, box.topLeft, ImageConfiguration(size: box.size));
      painter.dispose();
    }
    tp.paint(canvas, Offset(t.x + pad.left, t.y + pad.top));
    tp.dispose();
  }
}

/// Farben für Textfelder (zusätzlich zur Stiftfarbe).
const _textColors = <int>[
  0xFFF2F2F7, 0xFF16161D, 0xFF8B5CF6, 0xFF3B82F6, 0xFF22D3EE,
  0xFF22C55E, 0xFFFACC15, 0xFFF97316, 0xFFEF4444, 0xFFEC4899,
];

/// Die Ebene mit den Textfeldern über der Handschrift.
///
/// - Text-Werkzeug aktiv: aufs Blatt tippen legt ein Textfeld an,
///   ein vorhandenes antippen bearbeitet es.
/// - Andere Werkzeuge: Textfelder werden nur angezeigt, Stift und Lasso
///   gehen ungestört darüber hinweg.
/// - Leere Textfelder verschwinden beim Verlassen von selbst.
class TextLayer extends StatefulWidget {
  const TextLayer({
    super.key,
    required this.ownerId,
    required this.controller,
    required this.repo,
  });

  /// Dieselbe ID, unter der die Handschrift gespeichert ist.
  final String ownerId;
  final InkController controller;
  final TextRepository repo;

  @override
  State<TextLayer> createState() => TextLayerState();
}

class TextLayerState extends State<TextLayer> {
  InkController get c => widget.controller;

  List<TextItem> _items = [];
  String? _activeId;
  final Map<String, TextEditingController> _texts = {};
  final Map<String, FocusNode> _nodes = {};
  late int _seenColor;
  late double _seenSize;
  late ToolMode _seenTool;
  Offset? _dragLast;
  double _ensuredFor = -1;

  @override
  void initState() {
    super.initState();
    _items = widget.repo.items(widget.ownerId);
    _seenColor = c.penColor.toARGB32();
    _seenSize = c.textSize;
    _seenTool = c.tool;
    c.addListener(_onController);
  }

  @override
  void dispose() {
    c.removeListener(_onController);
    // Beim Schließen still speichern (keine Meldungen während des Abbaus).
    final active = _active;
    if (active != null) {
      final ctrl = _texts[active.id];
      if (ctrl != null) active.text = ctrl.text;
      if (active.text.trim().isEmpty) {
        widget.repo.delete(active.id, notify: false);
      } else {
        widget.repo.update(active, notify: false);
      }
    }
    for (final t in _texts.values) {
      t.dispose();
    }
    for (final n in _nodes.values) {
      n.dispose();
    }
    super.dispose();
  }

  TextItem? get _active {
    final id = _activeId;
    if (id == null) return null;
    for (final t in _items) {
      if (t.id == id) return t;
    }
    return null;
  }

  /// Gibt es gerade ein Textfeld in Bearbeitung?
  bool get editing => _activeId != null;

  TextEditingController _textFor(TextItem t) =>
      _texts.putIfAbsent(t.id, () => TextEditingController(text: t.text));

  FocusNode _nodeFor(TextItem t) =>
      _nodes.putIfAbsent(t.id, () => FocusNode(debugLabel: 'text-${t.id}'));

  void _onController() {
    if (!mounted) return;
    final tool = c.tool;
    final color = c.penColor.toARGB32();
    final size = c.textSize;
    final active = _active;
    if (tool != ToolMode.text && active != null) {
      finishEditing();
    } else if (active != null) {
      // Farbe oder Größe in der Leiste geändert: gilt für das offene Feld.
      var changed = false;
      if (color != _seenColor && active.color != color) {
        active.color = color;
        changed = true;
      }
      if (size != _seenSize && active.size != size) {
        active.size = size;
        changed = true;
      }
      if (changed) widget.repo.update(active);
      if (changed && tool == _seenTool) setState(() {});
    }
    final toolChanged = tool != _seenTool;
    _seenColor = color;
    _seenSize = size;
    _seenTool = tool;
    if (toolChanged) setState(() {});
  }

  /// Neues Textfeld an einer Stelle der Seite (Weltkoordinate).
  void createAt(Offset world) {
    if (!c.canDrawAt(world)) return;
    finishEditing();
    final size = c.textSize;
    final b = c.drawBounds;
    var x = world.dx;
    var y = world.dy - size * 0.65;
    var w = 340.0;
    if (b != null) {
      const minW = 140.0;
      w = math.min(w, b.right - 12 - x);
      if (w < minW) {
        w = math.min(minW, b.width - 24);
        x = math.max(b.left + 12, b.right - 12 - w);
      }
      y = y.clamp(b.top + 4, math.max(b.top + 4, b.bottom - size * 1.4)).toDouble();
    }
    final item = widget.repo.create(
      ownerId: widget.ownerId,
      x: x,
      y: y,
      w: math.max(60.0, w),
      size: size,
      color: c.penColor.toARGB32(),
    );
    setState(() {
      _items.add(item);
      _activeId = item.id;
      _ensuredFor = -1;
    });
    _focusLater(item);
  }

  void _activate(TextItem t) {
    if (_activeId == t.id) return;
    finishEditing();
    setState(() {
      _activeId = t.id;
      _ensuredFor = -1;
    });
    _focusLater(t);
  }

  void _focusLater(TextItem t) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _activeId != t.id) return;
      _nodeFor(t).requestFocus();
    });
  }

  void _saveActive() {
    final a = _active;
    if (a == null) return;
    final ctrl = _texts[a.id];
    if (ctrl != null && ctrl.text != a.text) {
      a.text = ctrl.text;
      widget.repo.update(a);
    }
  }

  /// Bearbeitung beenden. Leere Felder werden gelöscht.
  void finishEditing() {
    final a = _active;
    if (a == null) return;
    _saveActive();
    // Fokus zurück an die Schreibfläche, damit Tastenkürzel wieder gehen.
    _nodes[a.id]?.unfocus(
        disposition: UnfocusDisposition.previouslyFocusedChild);
    final empty = a.text.trim().isEmpty;
    if (empty) widget.repo.delete(a.id);
    if (!mounted) return;
    setState(() {
      _activeId = null;
      if (empty) _items.removeWhere((t) => t.id == a.id);
    });
    if (empty) _disposeLater(a.id);
  }

  void _disposeLater(String id) {
    final t = _texts.remove(id);
    final n = _nodes.remove(id);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      t?.dispose();
      n?.dispose();
    });
  }

  void _delete(TextItem t) {
    widget.repo.delete(t.id);
    setState(() {
      _items.removeWhere((x) => x.id == t.id);
      if (_activeId == t.id) _activeId = null;
    });
    _disposeLater(t.id);
    if (t.text.trim().isEmpty) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
      content: const Text('Textfeld gelöscht'),
      action: SnackBarAction(
        label: 'Rückgängig',
        onPressed: () {
          widget.repo.restore(t.id);
          if (mounted) {
            setState(() => _items = widget.repo.items(widget.ownerId));
          }
        },
      ),
    ));
  }

  void _changeSize(TextItem t, double factor) {
    final next = (t.size * factor).clamp(8.0, 96.0).toDouble();
    setState(() => t.size = double.parse(next.toStringAsFixed(1)));
    widget.repo.update(t);
  }

  void _toggleBold(TextItem t) {
    setState(() => t.bold = !t.bold);
    widget.repo.update(t);
  }

  // --- Verschieben und Breite ändern (in Weltkoordinaten) ---------------

  void _dragStart(DragStartDetails d) => _dragLast = d.globalPosition;

  void _move(TextItem t, DragUpdateDetails d) {
    final last = _dragLast;
    _dragLast = d.globalPosition;
    if (last == null) return;
    final delta = (d.globalPosition - last) / c.camera.scale;
    var x = t.x + delta.dx, y = t.y + delta.dy;
    final b = c.drawBounds;
    if (b != null) {
      x = x.clamp(b.left - t.w * 0.5, b.right - 20).toDouble();
      y = y.clamp(b.top - 10, b.bottom - 20).toDouble();
    }
    setState(() {
      t.x = x;
      t.y = y;
    });
  }

  void _resize(TextItem t, DragUpdateDetails d) {
    final last = _dragLast;
    _dragLast = d.globalPosition;
    if (last == null) return;
    final dx = (d.globalPosition.dx - last.dx) / c.camera.scale;
    var w = math.max(60.0, t.w + dx);
    final b = c.drawBounds;
    if (b != null) w = math.min(w, math.max(60.0, b.right - t.x));
    setState(() => t.w = w);
  }

  void _dragEnd(TextItem t) {
    _dragLast = null;
    widget.repo.update(t);
  }

  // --- Anzeige ------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final interactive = c.tool == ToolMode.text && c.drawingEnabled;
    return IgnorePointer(
      ignoring: !interactive,
      child: LayoutBuilder(builder: (context, constraints) {
        return AnimatedBuilder(
          animation: c.camera,
          builder: (context, _) {
            _ensureVisible(constraints.biggest);
            final active = _active;
            return Stack(
              clipBehavior: Clip.none,
              children: [
                for (final t in _items) _item(context, t, interactive),
                if (active != null && interactive)
                  _toolbar(context, active, constraints.biggest),
              ],
            );
          },
        );
      }),
    );
  }

  /// Liegt das bearbeitete Feld unter der Bildschirmtastatur, wird die
  /// Ansicht einmal ein Stück nach oben geschoben.
  void _ensureVisible(Size view) {
    final a = _active;
    if (a == null || view.height <= 0 || _ensuredFor == view.height) return;
    _ensuredFor = view.height;
    final top = c.camera.toScreen(Offset(a.x, a.y)).dy;
    final limit = view.height - 70;
    if (top > limit) {
      final dy = top - view.height * 0.35;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) c.camera.panBy(Offset(0, -dy));
      });
    }
  }

  Widget _item(BuildContext context, TextItem t, bool interactive) {
    final mf = context.mf;
    final cam = c.camera;
    final pos = cam.toScreen(Offset(t.x, t.y));
    final s = cam.scale;
    final active = t.id == _activeId && interactive;
    final style = textItemStyle(t);

    Widget content;
    if (active) {
      content = CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.keyB, control: true): () =>
              _set(t, () => t.bold = !t.bold),
          const SingleActivator(LogicalKeyboardKey.keyB, meta: true): () =>
              _set(t, () => t.bold = !t.bold),
          const SingleActivator(LogicalKeyboardKey.keyI, control: true): () =>
              _set(t, () => t.italic = !t.italic),
          const SingleActivator(LogicalKeyboardKey.keyI, meta: true): () =>
              _set(t, () => t.italic = !t.italic),
          const SingleActivator(LogicalKeyboardKey.keyU, control: true): () =>
              _set(t, () => t.underline = !t.underline),
          const SingleActivator(LogicalKeyboardKey.keyU, meta: true): () =>
              _set(t, () => t.underline = !t.underline),
        },
        child: TextField(
        controller: _textFor(t),
        focusNode: _nodeFor(t),
        maxLines: null,
        textAlign: t.align,
        inputFormatters: const [ListContinuationFormatter()],
        style: style,
        cursorColor: mf.accent,
        keyboardType: TextInputType.multiline,
        textCapitalization: TextCapitalization.sentences,
        onTapOutside: (_) {},
        onChanged: (v) {
          t.text = v;
          widget.repo.update(t);
        },
        decoration: InputDecoration.collapsed(
          hintText: 'Text eingeben …',
          hintStyle: style.copyWith(color: Color(t.color).withValues(alpha: 0.4)),
        ),
      ),
      );
    } else {
      content = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _activate(t),
        child: SizedBox(
          width: double.infinity,
          child: Text(t.text.isEmpty ? ' ' : t.text,
              textAlign: t.align, style: style),
        ),
      );
    }
    content = Container(
      padding: textItemPadding(t),
      decoration: textItemDecoration(t),
      child: content,
    );

    return Positioned(
      left: pos.dx,
      top: pos.dy,
      child: Transform.scale(
        scale: s,
        alignment: Alignment.topLeft,
        child: Container(
          width: t.w,
          decoration: active
              ? BoxDecoration(
                  border: Border.all(
                      color: mf.accent.withValues(alpha: 0.8),
                      width: 1.4 / s),
                  borderRadius: BorderRadius.circular(4 / s),
                  color: mf.accent.withValues(alpha: 0.05),
                )
              : interactive
                  ? BoxDecoration(
                      border: Border.all(
                          color: mf.textMuted.withValues(alpha: 0.35),
                          width: 1 / s),
                      borderRadius: BorderRadius.circular(4 / s),
                    )
                  : null,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              content,
              if (active)
                Positioned(
                  right: -14 / s,
                  top: 0,
                  bottom: 0,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onHorizontalDragStart: _dragStart,
                    onHorizontalDragUpdate: (d) => _resize(t, d),
                    onHorizontalDragEnd: (_) => _dragEnd(t),
                    child: MouseRegion(
                      cursor: SystemMouseCursors.resizeLeftRight,
                      child: SizedBox(
                        width: 26 / s,
                        child: Center(
                          child: Container(
                            width: 6 / s,
                            height: 26 / s,
                            decoration: BoxDecoration(
                              color: mf.accent,
                              borderRadius: BorderRadius.circular(3 / s),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _set(TextItem t, VoidCallback change) {
    setState(change);
    widget.repo.update(t);
  }

  void _duplicate(TextItem t) {
    _saveActive();
    final copy = widget.repo.create(
      ownerId: widget.ownerId,
      x: t.x + 18,
      y: t.y + 18,
      w: t.w,
      text: t.text,
      size: t.size,
      color: t.color,
      bold: t.bold,
    )
      ..italic = t.italic
      ..underline = t.underline
      ..font = t.font
      ..align = t.align
      ..background = t.background;
    widget.repo.update(copy);
    finishEditing();
    setState(() {
      _items.add(copy);
      _activeId = copy.id;
      _ensuredFor = -1;
    });
    _focusLater(copy);
  }

  void _toggleList(TextItem t) {
    final ctrl = _textFor(t);
    final next = toggleBullets(ctrl.text);
    ctrl.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: next.length),
    );
    _set(t, () => t.text = next);
  }

  static IconData _alignIcon(TextAlign a) => switch (a) {
        TextAlign.center => Icons.format_align_center_rounded,
        TextAlign.right => Icons.format_align_right_rounded,
        _ => Icons.format_align_left_rounded,
      };

  static TextAlign _nextAlign(TextAlign a) => switch (a) {
        TextAlign.left => TextAlign.center,
        TextAlign.center => TextAlign.right,
        _ => TextAlign.left,
      };

  /// Leiste über dem bearbeiteten Feld (in Bildschirmgröße, scrollbar).
  Widget _toolbar(BuildContext context, TextItem t, Size view) {
    final mf = context.mf;
    final pos = c.camera.toScreen(Offset(t.x, t.y));
    final maxW = math.max(200.0, view.width - 16);
    const estWidth = 560.0;
    final left = math.max(8.0, math.min(pos.dx, view.width - math.min(estWidth, maxW) - 8));
    Widget divider() => Container(
          width: 1,
          height: 22,
          margin: const EdgeInsets.symmetric(horizontal: 4),
          color: mf.border,
        );
    return Positioned(
      left: left,
      top: math.max(8.0, pos.dy - 56),
      child: TextFieldTapRegion(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxW),
          child: Container(
            height: 46,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            decoration: BoxDecoration(
              color: mf.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: mf.glassEdge),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withValues(alpha: mf.isDark ? 0.45 : 0.15),
                    blurRadius: 18,
                    offset: const Offset(0, 6)),
              ],
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Tooltip(
                    message: 'Ziehen zum Verschieben',
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onPanStart: _dragStart,
                      onPanUpdate: (d) => _move(t, d),
                      onPanEnd: (_) => _dragEnd(t),
                      child: MouseRegion(
                        cursor: SystemMouseCursors.move,
                        child: SizedBox(
                          width: 36,
                          height: 42,
                          child: Icon(Icons.open_with_rounded,
                              size: 18, color: mf.textMuted),
                        ),
                      ),
                    ),
                  ),
                  divider(),
                  CleanMenuButton(
                    tooltip: 'Schriftart',
                    trigger: SizedBox(
                      height: 34,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Center(
                          child: Text('Aa ${t.font.label}',
                              style: textItemStyle(TextItem(
                                id: '',
                                ownerId: '',
                                x: 0,
                                y: 0,
                                w: 0,
                                text: '',
                                size: 13,
                                color: mf.text.toARGB32(),
                                font: t.font,
                              ))),
                        ),
                      ),
                    ),
                    entries: [
                      for (final f in TextFont.values)
                        CleanMenuEntry(f.name, f.label,
                            icon: Icons.font_download_outlined,
                            checked: t.font == f),
                    ],
                    onSelected: (v) => _set(t,
                        () => t.font = TextFont.values.firstWhere((f) => f.name == v)),
                  ),
                  _bar(context, Icons.text_decrease_rounded, 'Kleiner',
                      () => _changeSize(t, 1 / 1.15)),
                  _bar(context, Icons.text_increase_rounded, 'Größer',
                      () => _changeSize(t, 1.15)),
                  divider(),
                  _bar(context, Icons.format_bold_rounded, 'Fett (Strg/⌘ + B)',
                      () => _set(t, () => t.bold = !t.bold),
                      selected: t.bold),
                  _bar(context, Icons.format_italic_rounded, 'Kursiv (Strg/⌘ + I)',
                      () => _set(t, () => t.italic = !t.italic),
                      selected: t.italic),
                  _bar(context, Icons.format_underlined_rounded,
                      'Unterstrichen (Strg/⌘ + U)',
                      () => _set(t, () => t.underline = !t.underline),
                      selected: t.underline),
                  _bar(context, _alignIcon(t.align), 'Ausrichtung',
                      () => _set(t, () => t.align = _nextAlign(t.align))),
                  _bar(context, Icons.format_list_bulleted_rounded,
                      'Aufzählung', () => _toggleList(t)),
                  divider(),
                  _colorMenu(context, t),
                  CleanMenuButton(
                    tooltip: 'Hintergrund',
                    icon: Icons.format_color_fill_rounded,
                    size: 36,
                    entries: [
                      for (final b in TextBackground.values)
                        CleanMenuEntry(b.name, b.label,
                            icon: switch (b) {
                              TextBackground.none => Icons.block_rounded,
                              TextBackground.marker => Icons.highlight_rounded,
                              TextBackground.box => Icons.crop_square_rounded,
                              TextBackground.note => Icons.sticky_note_2_outlined,
                            },
                            checked: t.background == b),
                    ],
                    onSelected: (v) => _set(
                        t,
                        () => t.background = TextBackground.values
                            .firstWhere((b) => b.name == v)),
                  ),
                  divider(),
                  _bar(context, Icons.copy_all_rounded, 'Duplizieren',
                      () => _duplicate(t)),
                  _bar(context, Icons.delete_outline_rounded, 'Löschen',
                      () => _delete(t),
                      danger: true),
                  divider(),
                  _bar(context, Icons.check_rounded, 'Fertig (Esc)',
                      finishEditing,
                      accent: true),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _colorMenu(BuildContext context, TextItem t) {
    final mf = context.mf;
    final colors = <int>{c.penColor.toARGB32(), ..._textColors}.toList();
    return CleanMenuButton(
      tooltip: 'Textfarbe',
      trigger: SizedBox(
        width: 36,
        height: 34,
        child: Center(
          child: Container(
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              color: Color(t.color),
              shape: BoxShape.circle,
              border: Border.all(color: mf.text.withValues(alpha: 0.35)),
            ),
          ),
        ),
      ),
      entries: [
        for (final col in colors)
          CleanMenuEntry('$col', _colorName(col),
              icon: Icons.circle, checked: col == t.color),
      ],
      onSelected: (v) {
        final col = int.tryParse(v);
        if (col != null) _set(t, () => t.color = col);
      },
    );
  }

  static String _colorName(int c) => switch (c) {
        0xFFF2F2F7 => 'Weiß',
        0xFF16161D => 'Schwarz',
        0xFF8B5CF6 => 'Violett',
        0xFF3B82F6 => 'Blau',
        0xFF22D3EE => 'Cyan',
        0xFF22C55E => 'Grün',
        0xFFFACC15 => 'Gelb',
        0xFFF97316 => 'Orange',
        0xFFEF4444 => 'Rot',
        0xFFEC4899 => 'Pink',
        _ => 'Aktuelle Stiftfarbe',
      };

  Widget _bar(BuildContext context, IconData icon, String tip, VoidCallback onTap,
      {bool selected = false, bool danger = false, bool accent = false}) {
    final mf = context.mf;
    final color = danger
        ? mf.danger
        : accent || selected
            ? mf.accent
            : mf.text;
    return Tooltip(
      message: tip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: 36,
          height: 34,
          decoration: BoxDecoration(
            color: selected ? mf.accentSoft : null,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 19, color: color),
        ),
      ),
    );
  }
}
