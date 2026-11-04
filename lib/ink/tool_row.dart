import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app/theme.dart';
import '../storage/element_library.dart';
import '../ui/color_picker.dart';
import 'ink_controller.dart';
import 'ink_toolbar.dart';
import 'tool_glyphs.dart';

const _textSizes = [14.0, 18.0, 26.0, 36.0];
const _textSizeLabels = ['S', 'M', 'L', 'XL'];

/// Schwebende Unterleiste wie bei Goodnotes: links Rückgängig/Wiederholen,
/// rechts was zum gewählten Modus gehört (Stifte, Stärken, Farben …).
class ToolRow extends StatelessWidget {
  const ToolRow({super.key, required this.controller});

  final InkController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final c = controller;
        // Lesemodus: nur ein Hinweis mit Knopf zum Weiterschreiben.
        if (!c.drawingEnabled) {
          return Center(
            child: _Floating(children: [
              const SizedBox(width: 10),
              Icon(Icons.visibility_outlined, color: context.mf.textMuted),
              const SizedBox(width: 8),
              Text('Lesemodus',
                  style: TextStyle(
                      fontWeight: FontWeight.w600, color: context.mf.text)),
              const SizedBox(width: 12),
              TextButton(
                onPressed: () => c.setDrawingEnabled(true),
                child: const Text('Schreiben'),
              ),
            ]),
          );
        }
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _Floating(children: [
                _RoundIcon(
                    icon: Icons.undo_rounded,
                    tooltip: 'Rückgängig',
                    flat: true,
                    onTap: c.history.canUndo ? c.undo : null),
                _RoundIcon(
                    icon: Icons.redo_rounded,
                    tooltip: 'Wiederholen',
                    flat: true,
                    onTap: c.history.canRedo ? c.redo : null),
              ]),
              const SizedBox(width: 6),
              _Floating(children: _context(context, c)),
            ],
          ),
        );
      },
    );
  }

  List<Widget> _context(BuildContext context, InkController c) {
    final mf = context.mf;
    switch (c.tool) {
      case ToolMode.pen:
      case ToolMode.highlighter:
      case ToolMode.shape:
        return [
          _PenGroup(c: c),
          if (c.tool != ToolMode.shape) ...[
            const _Divider(),
            _Favorites(c: c),
          ],
          const _Divider(),
          ..._colorsAndWidth(context, c),
          if (c.tool == ToolMode.shape) _FillButton(c: c),
          const _Divider(),
          _Toggle(
            icon: Icons.straighten_rounded,
            tooltip: c.ruler.value == null
                ? 'Lineal einblenden (mit Fingern verschieben/drehen)'
                : 'Lineal ausblenden',
            on: c.ruler.value != null,
            onTap: c.toggleRuler,
          ),
        ];
      case ToolMode.eraser:
        return [
          _Capsule(children: [
            for (final m in EraserMode.values)
              _TextChip(
                label: m.label,
                selected: c.eraserMode == m,
                onTap: () => c.setEraserMode(m),
              ),
          ]),
          const SizedBox(width: 10),
          _Capsule(children: [
            for (final s in const [8.0, 14.0, 24.0])
              _SizeDot(
                size: s / 2,
                selected: (c.eraserSize - s).abs() < 0.5,
                onTap: () => c.setEraserSize(s),
              ),
          ]),
          const _Divider(),
          _Toggle(
            icon: Icons.u_turn_left_rounded,
            label: 'Danach Stift',
            tooltip: c.settings.eraserAutoReturn
                ? 'An: Nach dem Radieren (Stift hochnehmen) geht es '
                    'automatisch mit dem vorigen Stift weiter'
                : 'Aus: Der Radierer bleibt gewählt',
            on: c.settings.eraserAutoReturn,
            onTap: () => c.settings.update(() => c.settings.eraserAutoReturn =
                !c.settings.eraserAutoReturn),
          ),
          _Toggle(
            icon: Icons.border_color_outlined,
            label: 'Nur Marker',
            tooltip: 'Nur Textmarker radieren – die Schrift bleibt stehen',
            on: c.settings.eraseHighlighterOnly,
            onTap: () => c.settings.update(() => c.settings
                .eraseHighlighterOnly = !c.settings.eraseHighlighterOnly),
          ),
        ];
      case ToolMode.lasso:
        return [
          if (c.hasSelection)
            ..._colorsAndWidth(context, c, colorsOnly: true)
          else
              Text(
                c.canPaste
                    ? 'Einkreisen · lange drücken: hier einfügen'
                    : 'Einkreisen – ein Teil des Strichs genügt',
                style: TextStyle(fontSize: 13, color: mf.textMuted)),
          if (c.canPaste) ...[
            const SizedBox(width: 10),
            _PasteChip(onTap: () => c.paste()),
          ],
          const SizedBox(width: 6),
          _Toggle(
            icon: Icons.widgets_outlined,
            label: 'Elemente',
            tooltip: 'Gespeichertes Element einfügen (eigene Bibliothek)',
            on: false,
            onTap: () => showElementPicker(context, c),
          ),
        ];
      case ToolMode.text:
        return [
          ..._colorsAndWidth(context, c, colorsOnly: true),
          const SizedBox(width: 10),
          _Capsule(children: [
            for (var i = 0; i < _textSizes.length; i++)
              _TextChip(
                label: _textSizeLabels[i],
                selected: (c.textSize - _textSizes[i]).abs() < 0.5,
                onTap: () => c.setTextSize(_textSizes[i]),
              ),
          ]),
          const SizedBox(width: 10),
          Text('Tippe aufs Blatt, um zu schreiben',
              style: TextStyle(fontSize: 13, color: mf.textMuted)),
        ];
      case ToolMode.laser:
        return [
          Text('Zeigen, ohne zu schreiben',
              style: TextStyle(fontSize: 13, color: mf.textMuted)),
        ];
    }
  }

  List<Widget> _colorsAndWidth(BuildContext context, InkController c,
      {bool colorsOnly = false}) {
    final hl = c.tool == ToolMode.highlighter;
    final palette = hl ? c.highlighterPalette : c.palette;
    final active = hl ? c.highlighterColor : c.penColor;
    final widths = c.widthSlots;
    return [
      if (!colorsOnly)
        for (var i = 0; i < widths.length; i++)
          _WidthSlot(c: c, index: i, highlighter: hl),
      _Capsule(children: [
        for (var i = 0; i < math.min(3, palette.length); i++)
          _ColorCircle(
            color: palette[i],
            selected: !c.hasSelection &&
                palette[i].toARGB32() == active.toARGB32(),
            onTap: () => c.setColor(palette[i]),
            onLongPress: () async {
              final picked = await pickColor(context, palette[i]);
              if (picked != null) {
                c.replacePaletteColor(i, picked, highlighter: hl);
              }
            },
          ),
        // Zuletzt benutzte Farben (eigene, Pipette, Favoriten).
        if (c.recentColors.isNotEmpty) ...[
          Container(
              width: 1,
              height: 20,
              margin: const EdgeInsets.symmetric(horizontal: 3),
              color: context.mf.border),
          for (final color in c.recentColors.take(4))
            _ColorCircle(
              color: color,
              selected: !c.hasSelection &&
                  color.toARGB32() == active.toARGB32(),
              onTap: () => c.setColor(color),
            ),
        ],
        _RoundIcon(
          icon: Icons.colorize_rounded,
          tooltip: c.picking
              ? 'Pipette: tippe auf eine Stelle (nochmal: abbrechen)'
              : 'Pipette – Farbe von der Seite aufnehmen',
          small: true,
          active: c.picking,
          onTap: () => c.setPicking(!c.picking),
        ),
        _RoundIcon(
          icon: Icons.add,
          tooltip: 'Eigene Farbe (Farbe lange drücken: Palette ändern)',
          small: true,
          onTap: () async {
            final picked = await pickColor(context, active);
            if (picked != null) c.setColor(picked);
          },
        ),
      ]),
    ];
  }
}

/// Ein Breiten-Platz. Antippen wählt ihn, nochmal antippen öffnet einen
/// Regler, mit dem man genau diesen Platz frei einstellt (wie bei Goodnotes).
class _WidthSlot extends StatelessWidget {
  const _WidthSlot(
      {required this.c, required this.index, required this.highlighter});

  final InkController c;
  final int index;
  final bool highlighter;

  @override
  Widget build(BuildContext context) {
    final mf = context.mf;
    final w = c.widthSlots[index];
    final selected = (c.activeWidth - w).abs() < 0.01;
    final min = highlighter ? 2.0 : 0.3;
    final max = highlighter ? 40.0 : 20.0;
    return MenuAnchor(
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(mf.surface),
        shape: WidgetStatePropertyAll(RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: mf.border),
        )),
      ),
      menuChildren: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
          child: SizedBox(
            width: 280,
            child: ListenableBuilder(
              listenable: c,
              builder: (context, _) {
                final v = c.widthSlots[index].clamp(min, max).toDouble();
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Strichstärke: ${v.toStringAsFixed(1)}',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: mf.textMuted)),
                    const SizedBox(height: 10),
                    // Vorschau der Linie
                    SizedBox(
                      height: 40,
                      child: Center(
                        child: Container(
                          height: (highlighter ? v : v * 1.2)
                              .clamp(1.0, 36.0)
                              .toDouble(),
                          decoration: BoxDecoration(
                            color: highlighter
                                ? c.highlighterColor.withValues(alpha: 0.4)
                                : c.penColor,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                                color: mf.border.withValues(alpha: 0.5)),
                          ),
                        ),
                      ),
                    ),
                    Slider(
                      value: v,
                      min: min,
                      max: max,
                      onChanged: (x) => c.setWidthSlot(index,
                          double.parse(x.toStringAsFixed(1))),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ],
      builder: (context, menu, _) => Tooltip(
        message: selected
            ? 'Nochmal tippen: Stärke genau einstellen'
            : 'Strichstärke ${w.toStringAsFixed(1)}',
        child: _WidthBar(
          thickness: (highlighter ? w / 3 : 1.5 + w * 0.9).clamp(1.5, 9.0).toDouble(),
          selected: selected,
          onTap: () {
            if (!selected) {
              c.setWidth(w);
            } else if (menu.isOpen) {
              menu.close();
            } else {
              menu.open();
            }
          },
        ),
      ),
    );
  }
}

/// Die Schreibwerkzeuge wie bei Goodnotes: drei Stifte, Textmarker, Formen.
class _PenGroup extends StatelessWidget {
  const _PenGroup({required this.c});
  final InkController c;

  @override
  Widget build(BuildContext context) {
    Widget pen(PenType t, GlyphKind g) => _ToolItem(
          c: c,
          tool: ToolMode.pen,
          glyph: g,
          tip: c.penColor,
          label: '${t.label} (P)',
          isSelected: c.tool == ToolMode.pen && c.penType == t,
          select: () {
            c.setTool(ToolMode.pen);
            c.setPenType(t);
          },
          menu: (_) => PenOptions(c),
        );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        pen(PenType.fountain, GlyphKind.fountain),
        pen(PenType.ballpoint, GlyphKind.ballpoint),
        pen(PenType.brush, GlyphKind.brush),
        _ToolItem(
          c: c,
          tool: ToolMode.highlighter,
          glyph: GlyphKind.highlighter,
          tip: c.highlighterColor,
          label: 'Textmarker (H)',
          menu: (_) => HighlighterOptions(c),
        ),
        _ToolItem(
          c: c,
          tool: ToolMode.shape,
          glyph: GlyphKind.shape,
          tip: context.mf.accent,
          label: 'Formen (S)',
          menu: (_) => ShapeOptions(c),
        ),
      ],
    );
  }
}

/// Ein Werkzeug in der Kapsel – als gezeichneter Stift. Gewählt: hebt sich
/// an und liegt auf einer hellen Fläche. Nochmal antippen: Optionen.
class _ToolItem extends StatelessWidget {
  const _ToolItem({
    required this.c,
    required this.tool,
    required this.glyph,
    required this.tip,
    required this.label,
    this.menu,
    this.isSelected,
    this.select,
  });

  final bool? isSelected;
  final VoidCallback? select;
  final InkController c;
  final ToolMode tool;
  final GlyphKind glyph;
  final Color tip;
  final String label;
  final WidgetBuilder? menu;

  @override
  Widget build(BuildContext context) {
    final mf = context.mf;
    final selected = isSelected ?? c.tool == tool;
    final choose = select ?? () => c.setTool(tool);
    final dark = Theme.of(context).brightness == Brightness.dark;
    Widget button(VoidCallback onTap) => Tooltip(
          message: menu == null ? label : '$label – nochmal tippen: Optionen',
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
              height: 42,
              padding: EdgeInsets.only(left: 8, right: selected && menu != null ? 2 : 8),
              margin: const EdgeInsets.symmetric(horizontal: 2),
              decoration: BoxDecoration(
                color: selected ? _kSelected : null,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ToolGlyph(
                    kind: glyph,
                    tip: tip,
                    body: dark || selected
                        ? const Color(0xFFE6E6EE)
                        : const Color(0xFF2A2A33),
                    outline: selected ? Colors.white : mf.text,
                    selected: false,
                  ),
                  if (selected && menu != null)
                    const Icon(Icons.expand_more_rounded,
                        size: 16, color: Colors.white),
                ],
              ),
            ),
          ),
        );

    final m = menu;
    if (m == null) return button(choose);
    return MenuAnchor(
      alignmentOffset: const Offset(0, 8),
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(mf.surface),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        elevation: const WidgetStatePropertyAll(14),
        shadowColor: const WidgetStatePropertyAll(Color(0x40000000)),
        shape: WidgetStatePropertyAll(RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: mf.border.withValues(alpha: 0.7)),
        )),
      ),
      menuChildren: [
        Padding(
          padding: const EdgeInsets.all(18),
          child: SizedBox(width: 290, child: Builder(builder: m)),
        ),
      ],
      builder: (context, ctrl, _) => button(() {
        if (!selected) {
          choose();
        } else if (ctrl.isOpen) {
          ctrl.close();
        } else {
          ctrl.open();
        }
      }),
    );
  }
}

/// Abgerundete Kapsel als Hintergrund für eine Gruppe.
class _Capsule extends StatelessWidget {
  const _Capsule({required this.children, this.padding = 3});
  final List<Widget> children;
  final double padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.all(padding),
      child: Row(mainAxisSize: MainAxisSize.min, children: children),
    );
  }
}

class _ColorCircle extends StatelessWidget {
  const _ColorCircle({
    required this.color,
    required this.selected,
    required this.onTap,
    this.onLongPress,
  });

  final Color color;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final mf = context.mf;
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      onSecondaryTap: onLongPress,
      child: SizedBox(
        width: 34,
        height: 38,
        child: Center(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            width: 26,
            height: 26,
            padding: EdgeInsets.all(selected ? 3 : 0),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                  color: selected ? mf.accent : Colors.transparent, width: 2),
            ),
            child: Container(
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(
                    color: mf.text.withValues(alpha: 0.15), width: 1),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SizeDot extends StatelessWidget {
  const _SizeDot(
      {required this.size, required this.selected, required this.onTap});

  final double size;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final mf = context.mf;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: selected ? mf.accentSoft : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Center(
          child: Container(
            width: size.clamp(3.0, 16.0).toDouble(),
            height: size.clamp(3.0, 16.0).toDouble(),
            decoration: BoxDecoration(
              color: selected ? mf.accent : mf.text,
              shape: BoxShape.circle,
            ),
          ),
        ),
      ),
    );
  }
}

class _TextChip extends StatelessWidget {
  const _TextChip(
      {required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final mf = context.mf;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? mf.accent : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: selected ? Colors.white : mf.text)),
      ),
    );
  }
}

class _RoundIcon extends StatelessWidget {
  const _RoundIcon(
      {required this.icon,
      required this.tooltip,
      this.onTap,
      this.small = false,
      this.flat = false,
      this.active = false});

  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final bool small;

  /// Eingeschaltet (z. B. Pipette aktiv): farbig hinterlegt.
  final bool active;

  /// Ohne Rand (Rückgängig/Wiederholen in der schwebenden Leiste).
  final bool flat;

  @override
  Widget build(BuildContext context) {
    final mf = context.mf;
    final d = flat ? 44.0 : (small ? 30.0 : 38.0);
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Container(
          width: d,
          height: d,
          margin: const EdgeInsets.symmetric(horizontal: 2),
          decoration: flat
              ? null
              : BoxDecoration(
                  shape: BoxShape.circle,
                  color: active
                      ? _kSelected
                      : small
                          ? Colors.transparent
                          : mf.surfaceRaised,
                  border: Border.all(color: active ? _kSelected : mf.border),
                ),
          child: Icon(icon,
              size: flat ? 24 : (small ? 16 : 18),
              color: onTap == null
                  ? mf.textMuted.withValues(alpha: 0.4)
                  : active
                      ? Colors.white
                      : mf.text),
        ),
      ),
    );
  }
}

/// Deutlicher „Einfügen“-Knopf, sobald etwas kopiert wurde.
class _PasteChip extends StatelessWidget {
  const _PasteChip({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final mf = context.mf;
    return Tooltip(
      message: 'In der Mitte einfügen (oder mit dem Lasso lange drücken)',
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            gradient: mf.gradient,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(color: mf.glow, blurRadius: 14, spreadRadius: -4),
            ],
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.content_paste_rounded, size: 16, color: Colors.white),
              SizedBox(width: 6),
              Text('Einfügen',
                  style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 13)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Hintergrund des gewählten Stifts (Goodnotes: Petrol).
const _kSelected = Color(0xFF3F8792);

/// Schwebende, abgerundete Kapsel über dem Blatt.
class _Floating extends StatelessWidget {
  const _Floating({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final mf = context.mf;
    return Container(
      height: 54,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: mf.isDark ? const Color(0xFF2A2A2D) : Colors.white,
        borderRadius: BorderRadius.circular(27),
        border: Border.all(
            color: mf.isDark ? const Color(0xFF3C3C40) : const Color(0xFFDADCE3)),
        boxShadow: const [
          BoxShadow(color: Color(0x33000000), blurRadius: 16, offset: Offset(0, 6)),
        ],
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: children),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) => Container(
        width: 1,
        height: 30,
        margin: const EdgeInsets.symmetric(horizontal: 8),
        color: context.mf.border,
      );
}

/// Strichstärke als Linie (wie bei Goodnotes).
class _WidthBar extends StatelessWidget {
  const _WidthBar(
      {required this.thickness, required this.selected, required this.onTap});

  final double thickness;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final mf = context.mf;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        width: 50,
        height: 42,
        margin: const EdgeInsets.symmetric(horizontal: 2),
        decoration: BoxDecoration(
          color: selected ? mf.text.withValues(alpha: 0.14) : null,
          borderRadius: BorderRadius.circular(12),
        ),
        alignment: Alignment.center,
        child: Container(
          width: 22,
          height: thickness,
          decoration: BoxDecoration(
            color: mf.text,
            borderRadius: BorderRadius.circular(thickness),
          ),
        ),
      ),
    );
  }
}

/// Die Modus-Knöpfe in der Kopfleiste wie bei Goodnotes:
/// Lasso | Schreiben, Radierer, Text, ⌄ (Laser).
class ToolModeButtons extends StatelessWidget {
  const ToolModeButtons({super.key, required this.controller});

  final InkController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        Widget b(IconData? icon, String tip, bool on, VoidCallback tap) =>
            Tooltip(
              message: tip,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: tap,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  width: 44,
                  height: 38,
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  decoration: BoxDecoration(
                    color: on ? const Color(0xFFD5DCE8) : null,
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: icon == null
                      ? CustomPaint(
                          painter: _EraserIcon(
                              on ? const Color(0xFF1E2A44) : Colors.white))
                      : Icon(icon,
                          size: 23,
                          color: on ? const Color(0xFF1E2A44) : Colors.white),
                ),
              ),
            );
        final t = c.tool;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            b(Icons.highlight_alt_rounded, 'Lasso (L)', t == ToolMode.lasso,
                () => c.setTool(ToolMode.lasso)),
            Container(
                width: 1,
                height: 24,
                margin: const EdgeInsets.symmetric(horizontal: 6),
                color: Colors.white24),
            b(Icons.edit_outlined, 'Schreiben (P)',
                InkController.isWriteTool(t), () => c.setTool(c.lastWriteTool)),
            b(null, 'Radierer (E)', t == ToolMode.eraser,
                () => c.setTool(ToolMode.eraser)),
            b(Icons.title_rounded, 'Textfeld (T)', t == ToolMode.text,
                () => c.setTool(ToolMode.text)),
            Tooltip(
              message: 'Laserpointer (R)',
              child: GestureDetector(
                onTap: () => c.setTool(ToolMode.laser),
                child: Container(
                  width: 34,
                  height: 34,
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: t == ToolMode.laser
                        ? const Color(0xFFD5DCE8)
                        : Colors.white24,
                  ),
                  child: Icon(Icons.flare_rounded,
                      size: 18,
                      color: t == ToolMode.laser
                          ? const Color(0xFF1E2A44)
                          : Colors.white),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Füllfarbe für Formen (wie Goodnotes): ohne oder eine zarte Farbe.
class _FillButton extends StatelessWidget {
  const _FillButton({required this.c});
  final InkController c;

  @override
  Widget build(BuildContext context) {
    final mf = context.mf;
    final current = c.editShape?.fill ?? c.settings.shapeFill;
    final colors = <int?>[
      null,
      for (final col in [...c.palette, ...c.highlighterPalette])
        col.withAlpha(0x66).toARGB32(),
    ];
    return MenuAnchor(
      menuChildren: [
        Padding(
          padding: const EdgeInsets.all(10),
          child: SizedBox(
            width: 210,
            child: Wrap(children: [
              for (final f in colors)
                GestureDetector(
                  onTap: () => c.setShapeFill(f),
                  child: Container(
                    width: 34,
                    height: 34,
                    margin: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: f == null ? null : Color(f),
                      border: Border.all(
                          color: f == current ? mf.accent : mf.border,
                          width: f == current ? 2.5 : 1),
                    ),
                    child: f == null
                        ? Icon(Icons.block, size: 16, color: mf.textMuted)
                        : null,
                  ),
                ),
            ]),
          ),
        ),
      ],
      builder: (context, menu, _) => Tooltip(
        message: 'Füllung',
        child: InkWell(
          onTap: () => menu.isOpen ? menu.close() : menu.open(),
          customBorder: const CircleBorder(),
          child: SizedBox(
            width: 42,
            height: 42,
            child: Icon(Icons.format_color_fill_rounded,
                color: current == null ? mf.text : Color(current).withAlpha(255)),
          ),
        ),
      ),
    );
  }
}

/// Ein-/Aus-Knopf in der Unterleiste (z. B. Lineal), optional mit Text.
class _Toggle extends StatelessWidget {
  const _Toggle(
      {required this.icon,
      required this.tooltip,
      required this.on,
      required this.onTap,
      this.label});

  final IconData icon;
  final String tooltip;
  final bool on;
  final VoidCallback onTap;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final mf = context.mf;
    final fg = on ? Colors.white : mf.text;
    final text = label;
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          height: 42,
          margin: const EdgeInsets.symmetric(horizontal: 2),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: on ? _kSelected : null,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, color: fg, size: 22),
            if (text != null) ...[
              const SizedBox(width: 6),
              Text(text,
                  style: TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600, color: fg)),
            ],
          ]),
        ),
      ),
    );
  }
}

/// Lieblingsstifte (wie Goodnotes-Favoriten): antippen wählt Stift, Farbe
/// und Stärke auf einmal; der Stern speichert den aktuellen Stift.
class _Favorites extends StatelessWidget {
  const _Favorites({required this.c});
  final InkController c;

  @override
  Widget build(BuildContext context) {
    final presets = c.settings.presets;
    final current = presets.any(c.isActivePreset);
    return Row(mainAxisSize: MainAxisSize.min, children: [
      for (final p in presets) PresetButton(preset: p, controller: c),
      _RoundIcon(
        icon: current ? Icons.star_rounded : Icons.star_outline_rounded,
        tooltip: current
            ? 'Ist ein Favorit (Favorit lange drücken: entfernen)'
            : 'Aktuellen Stift als Favorit speichern',
        small: true,
        onTap: current ? null : c.saveCurrentAsPreset,
      ),
    ]);
  }
}

/// Radierer-Symbol (schräger Radiergummi), selbst gezeichnet.
class _EraserIcon extends CustomPainter {
  const _EraserIcon(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeJoin = StrokeJoin.round;
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.rotate(-math.pi / 4);
    final body = RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset.zero, width: 20, height: 10),
        const Radius.circular(2.5));
    canvas.drawRRect(body, p);
    canvas.drawRect(const Rect.fromLTRB(-10, -5, -3, 5),
        Paint()..color = color.withValues(alpha: 0.85));
    canvas.restore();
    canvas.drawLine(Offset(size.width * 0.3, size.height * 0.86),
        Offset(size.width * 0.86, size.height * 0.86), p..strokeWidth = 1.4);
  }

  @override
  bool shouldRepaint(_EraserIcon old) => old.color != color;
}
