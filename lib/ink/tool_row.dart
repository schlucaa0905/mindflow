import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app/theme.dart';
import '../ui/color_picker.dart';
import 'ink_controller.dart';
import 'ink_toolbar.dart';

/// Moderne Werkzeugzeile im Goodnotes-Stil – fest unter der Kopfleiste.
///
/// Mitte: die Werkzeuge in einer Kapsel. Rechts daneben: was zum gewählten
/// Werkzeug passt (Farben, Strichstärken, Lieblingsstifte, Radierer-Art …).
/// Ein gewähltes Werkzeug nochmal antippen öffnet alle Optionen.
class ToolRow extends StatelessWidget {
  const ToolRow({super.key, required this.controller});

  final InkController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final c = controller;
        return LayoutBuilder(builder: (context, constraints) {
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: ConstrainedBox(
              constraints:
                  BoxConstraints(minWidth: math.max(0.0, constraints.maxWidth - 24)),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _ToolCapsule(c: c),
                  const SizedBox(width: 14),
                  ..._context(context, c),
                ],
              ),
            ),
          );
        });
      },
    );
  }

  List<Widget> _context(BuildContext context, InkController c) {
    final mf = context.mf;
    switch (c.tool) {
      case ToolMode.pen:
      case ToolMode.highlighter:
      case ToolMode.shape:
        return _colorsAndWidth(context, c);
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
        ];
      case ToolMode.lasso:
        return [
          if (c.selection.isNotEmpty)
            ..._colorsAndWidth(context, c, colorsOnly: true)
          else
            Text('Einkreisen – ein Teil des Strichs genügt',
                style: TextStyle(fontSize: 13, color: mf.textMuted)),
          if (c.canPaste) ...[
            const SizedBox(width: 10),
            _RoundIcon(
              icon: Icons.content_paste,
              tooltip: 'Einfügen',
              onTap: c.paste,
            ),
          ],
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
      if (!colorsOnly && c.tool == ToolMode.pen && c.settings.presets.isNotEmpty) ...[
        _Capsule(children: [
          for (final p in c.settings.presets)
            PresetButton(preset: p, controller: c),
        ]),
        const SizedBox(width: 10),
      ],
      _Capsule(children: [
        for (var i = 0; i < palette.length; i++)
          _ColorCircle(
            color: palette[i],
            selected: c.selection.isEmpty &&
                palette[i].toARGB32() == active.toARGB32(),
            onTap: () => c.setColor(palette[i]),
            onLongPress: () async {
              final picked = await pickColor(context, palette[i]);
              if (picked != null) {
                c.replacePaletteColor(i, picked, highlighter: hl);
              }
            },
          ),
        if (!hl)
          for (final color in c.customColors.take(3))
            _ColorCircle(
              color: color,
              selected: c.selection.isEmpty &&
                  color.toARGB32() == active.toARGB32(),
              onTap: () => c.setColor(color),
            ),
        _RoundIcon(
          icon: Icons.add,
          tooltip: 'Eigene Farbe (Farbe lange drücken: Palette ändern)',
          small: true,
          onTap: () async {
            final picked = await pickColor(context, active);
            if (picked == null) return;
            if (hl) {
              c.setColor(picked);
            } else {
              c.addCustomColor(picked);
            }
          },
        ),
      ]),
      if (!colorsOnly) ...[
        const SizedBox(width: 10),
        _Capsule(children: [
          for (var i = 0; i < widths.length; i++)
            _WidthSlot(c: c, index: i, highlighter: hl),
        ]),
      ],
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
        child: _SizeDot(
          size: highlighter ? w / 2.5 : 3 + w * 1.8,
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

/// Kapsel mit allen Werkzeugen.
class _ToolCapsule extends StatelessWidget {
  const _ToolCapsule({required this.c});
  final InkController c;

  @override
  Widget build(BuildContext context) {
    return _Capsule(
      padding: 4,
      children: [
        _ToolItem(
          c: c,
          tool: ToolMode.pen,
          icon: penIcon(c.penType),
          label: '${c.penType.label} (P)',
          menu: (_) => PenOptions(c),
        ),
        _ToolItem(
          c: c,
          tool: ToolMode.highlighter,
          icon: Icons.border_color_outlined,
          label: 'Textmarker (H)',
          menu: (_) => HighlighterOptions(c),
        ),
        _ToolItem(
          c: c,
          tool: ToolMode.eraser,
          icon: Icons.auto_fix_normal_outlined,
          label: 'Radierer (E)',
          menu: (_) => EraserOptions(c),
        ),
        _ToolItem(
          c: c,
          tool: ToolMode.lasso,
          icon: Icons.gesture,
          label: 'Lasso (L)',
        ),
        _ToolItem(
          c: c,
          tool: ToolMode.shape,
          icon: shapeIcon(c.shapeKind),
          label: 'Formen (S)',
          menu: (_) => ShapeOptions(c),
        ),
        _ToolItem(
          c: c,
          tool: ToolMode.laser,
          icon: Icons.highlight_alt,
          label: 'Laserpointer (R)',
        ),
      ],
    );
  }
}

/// Ein Werkzeug in der Kapsel. Gewählt: gefüllt in Akzentfarbe.
/// Nochmal antippen: Optionen.
class _ToolItem extends StatelessWidget {
  const _ToolItem({
    required this.c,
    required this.tool,
    required this.icon,
    required this.label,
    this.menu,
  });

  final InkController c;
  final ToolMode tool;
  final IconData icon;
  final String label;
  final WidgetBuilder? menu;

  @override
  Widget build(BuildContext context) {
    final mf = context.mf;
    final selected = c.tool == tool;
    Widget button(VoidCallback onTap) => Tooltip(
          message: menu == null ? label : '$label – nochmal tippen: Optionen',
          child: GestureDetector(
            onTap: onTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              width: 46,
              height: 40,
              margin: const EdgeInsets.symmetric(horizontal: 1),
              decoration: BoxDecoration(
                color: selected ? mf.accent : Colors.transparent,
                borderRadius: BorderRadius.circular(11),
                boxShadow: selected
                    ? [
                        BoxShadow(
                            color: mf.accent.withValues(alpha: 0.35),
                            blurRadius: 10,
                            offset: const Offset(0, 3)),
                      ]
                    : null,
              ),
              child: Icon(icon,
                  size: 21, color: selected ? Colors.white : mf.text),
            ),
          ),
        );

    final m = menu;
    if (m == null) return button(() => c.setTool(tool));
    return MenuAnchor(
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(mf.surface),
        elevation: const WidgetStatePropertyAll(8),
        shape: WidgetStatePropertyAll(RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: mf.border),
        )),
      ),
      menuChildren: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: SizedBox(width: 290, child: Builder(builder: m)),
        ),
      ],
      builder: (context, ctrl, _) => button(() {
        if (!selected) {
          c.setTool(tool);
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
    final mf = context.mf;
    return Container(
      padding: EdgeInsets.all(padding),
      decoration: BoxDecoration(
        color: mf.surfaceRaised,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: mf.border.withValues(alpha: 0.6)),
      ),
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
      this.small = false});

  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final bool small;

  @override
  Widget build(BuildContext context) {
    final mf = context.mf;
    final d = small ? 30.0 : 38.0;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Container(
          width: d,
          height: d,
          margin: const EdgeInsets.symmetric(horizontal: 2),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: small ? Colors.transparent : mf.surfaceRaised,
            border: Border.all(color: mf.border),
          ),
          child: Icon(icon, size: small ? 16 : 18, color: mf.text),
        ),
      ),
    );
  }
}
