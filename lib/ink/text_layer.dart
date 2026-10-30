import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app/theme.dart';
import '../data/text_repository.dart';
import 'ink_controller.dart';

/// Schriftstil eines Textfelds – identisch auf dem Bildschirm, in
/// Vorschaubildern und im PDF-Export.
TextStyle textItemStyle(TextItem t) => TextStyle(
      fontSize: t.size,
      height: 1.3,
      color: Color(t.color),
      fontWeight: t.bold ? FontWeight.w700 : FontWeight.w400,
    );

/// Zeichnet Textfelder direkt auf eine Leinwand (Export, Vorschau).
void paintTextItems(Canvas canvas, List<TextItem> items) {
  for (final t in items) {
    if (t.text.trim().isEmpty) continue;
    final tp = TextPainter(
      text: TextSpan(text: t.text, style: textItemStyle(t)),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: math.max(1.0, t.w));
    tp.paint(canvas, Offset(t.x, t.y));
    tp.dispose();
  }
}

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
      content = TextField(
        controller: _textFor(t),
        focusNode: _nodeFor(t),
        maxLines: null,
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
      );
    } else {
      content = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _activate(t),
        child: Text(t.text.isEmpty ? ' ' : t.text, style: style),
      );
    }

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

  /// Kleine Leiste über dem bearbeiteten Feld (in Bildschirmgröße).
  Widget _toolbar(BuildContext context, TextItem t, Size view) {
    final mf = context.mf;
    final pos = c.camera.toScreen(Offset(t.x, t.y));
    const barWidth = 270.0;
    return Positioned(
      left: math.max(8.0, math.min(pos.dx, view.width - barWidth - 8)),
      top: math.max(8.0, pos.dy - 52),
      child: TextFieldTapRegion(
        child: Container(
          height: 42,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            color: mf.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: mf.glassEdge),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withValues(alpha: mf.isDark ? 0.45 : 0.15),
                  blurRadius: 18,
                  offset: const Offset(0, 6)),
            ],
          ),
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
              _bar(context, Icons.text_decrease_rounded, 'Kleiner',
                  () => _changeSize(t, 1 / 1.15)),
              _bar(context, Icons.text_increase_rounded, 'Größer',
                  () => _changeSize(t, 1.15)),
              _bar(context, Icons.format_bold_rounded, 'Fett',
                  () => _toggleBold(t),
                  selected: t.bold),
              _bar(context, Icons.delete_outline_rounded, 'Löschen',
                  () => _delete(t),
                  danger: true),
              Container(
                width: 1,
                height: 22,
                margin: const EdgeInsets.symmetric(horizontal: 4),
                color: mf.border,
              ),
              _bar(context, Icons.check_rounded, 'Fertig', finishEditing,
                  accent: true),
            ],
          ),
        ),
      ),
    );
  }

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
