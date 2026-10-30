import 'package:flutter/material.dart';

import '../app/theme.dart';
import '../ui/color_picker.dart';
import '../ui/widgets.dart';
import 'ink_controller.dart';

/// Werkzeugleiste für Handschrift. Wird von Notizbuch und Canvas genutzt.
///
/// - Werkzeug antippen wählt es aus, nochmal antippen öffnet die Optionen.
/// - Am Griff (⋮⋮) ziehen verschiebt die Leiste.
/// - Farbe lange drücken (oder Rechtsklick) ändert sie.
class InkToolbar extends StatelessWidget {
  const InkToolbar({
    super.key,
    required this.controller,
    required this.paper,
    this.leading = const [],
    this.trailing = const [],
    this.showInkTools = true,
    this.axis = Axis.horizontal,
    this.collapsed = false,
    this.onToggleCollapsed,
    this.onDragStart,
    this.onDragUpdate,
    this.onDragEnd,
  });

  final InkController controller;
  final Paper paper;
  final List<Widget> leading;
  final List<Widget> trailing;
  final bool showInkTools;
  final Axis axis;
  final bool collapsed;
  final VoidCallback? onToggleCollapsed;
  final GestureDragStartCallback? onDragStart;
  final GestureDragUpdateCallback? onDragUpdate;
  final GestureDragEndCallback? onDragEnd;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final c = controller;
        final div = _Div(axis);
        final children = <Widget>[
          _DragHandle(
            axis: axis,
            onStart: onDragStart,
            onUpdate: onDragUpdate,
            onEnd: onDragEnd,
          ),
          ...leading,
          if (collapsed) ...[
            if (showInkTools)
              ToolButton(
                icon: toolIcon(c),
                label: 'Aktuelles Werkzeug',
                selected: true,
                onTap: onToggleCollapsed,
              ),
          ] else if (showInkTools) ...[
            if (leading.isNotEmpty) div,
            ..._tools(context, c),
            div,
            ..._colorsAndWidths(context, c, div),
            ..._history(c),
          ],
          if (trailing.isNotEmpty) div,
          ...trailing,
          ToolButton(
            icon: collapsed
                ? (axis == Axis.vertical ? Icons.unfold_more : Icons.chevron_right)
                : (axis == Axis.vertical ? Icons.unfold_less : Icons.chevron_left),
            label: collapsed ? 'Leiste ausklappen' : 'Leiste einklappen',
            onTap: onToggleCollapsed,
          ),
        ];
        return FloatingPanel(
          padding: const EdgeInsets.all(6),
          child: Wrap(
            direction: axis,
            crossAxisAlignment: WrapCrossAlignment.center,
            alignment: WrapAlignment.center,
            spacing: 2,
            runSpacing: 4,
            children: children,
          ),
        );
      },
    );
  }

  List<Widget> _tools(BuildContext context, InkController c) => [
        _ToolWithMenu(
          icon: penIcon(c.penType),
          label: '${c.penType.label} (P) – nochmal tippen: Optionen',
          selected: c.tool == ToolMode.pen,
          onSelect: () => c.setTool(ToolMode.pen),
          menu: (context) => PenOptions(c),
        ),
        _ToolWithMenu(
          icon: Icons.border_color_outlined,
          label: 'Textmarker (H) – nochmal tippen: Optionen',
          selected: c.tool == ToolMode.highlighter,
          onSelect: () => c.setTool(ToolMode.highlighter),
          menu: (context) => HighlighterOptions(c),
        ),
        _ToolWithMenu(
          icon: Icons.auto_fix_normal_outlined,
          label: 'Radierer (E) – nochmal tippen: Optionen',
          selected: c.tool == ToolMode.eraser,
          onSelect: () => c.setTool(ToolMode.eraser),
          menu: (context) => EraserOptions(c),
        ),
        ToolButton(
          icon: Icons.gesture,
          label: 'Lasso (L): einkreisen, dann verschieben oder skalieren',
          selected: c.tool == ToolMode.lasso,
          onTap: () => c.setTool(ToolMode.lasso),
        ),
        _ToolWithMenu(
          icon: shapeIcon(c.shapeKind),
          label: 'Formen (S) – nochmal tippen: Form wählen',
          selected: c.tool == ToolMode.shape,
          onSelect: () => c.setTool(ToolMode.shape),
          menu: (context) => ShapeOptions(c),
        ),
        ToolButton(
          icon: Icons.highlight_alt,
          label: 'Laserpointer (R): zeigt, ohne etwas zu speichern',
          selected: c.tool == ToolMode.laser,
          onTap: () => c.setTool(ToolMode.laser),
        ),
        if (c.tool == ToolMode.lasso && c.canPaste)
          ToolButton(
            icon: Icons.content_paste,
            label: 'Einfügen',
            onTap: c.paste,
          ),
      ];

  List<Widget> _colorsAndWidths(
      BuildContext context, InkController c, Widget div) {
    final hl = c.tool == ToolMode.highlighter;
    final showColors = c.tool == ToolMode.pen ||
        hl ||
        c.tool == ToolMode.shape ||
        c.selection.isNotEmpty;
    if (!showColors) return const [];
    final palette = hl ? c.highlighterPalette : c.palette;
    final active = hl ? c.highlighterColor : c.penColor;
    final presets = hl ? const [8.0, 14.0, 22.0] : const [1.5, 2.5, 4.5];
    final showWidths = c.tool == ToolMode.pen || hl || c.tool == ToolMode.shape;
    return [
      // Lieblingsstifte
      if (c.tool == ToolMode.pen && c.settings.presets.isNotEmpty) ...[
        for (final p in c.settings.presets)
          PresetButton(preset: p, controller: c),
        div,
      ],
      for (var i = 0; i < palette.length; i++)
        ColorDot(
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
        for (final color in c.customColors)
          ColorDot(
            color: color,
            selected: c.selection.isEmpty &&
                color.toARGB32() == active.toARGB32(),
            onTap: () => c.setColor(color),
          ),
      ToolButton(
        icon: Icons.colorize_outlined,
        label: 'Eigene Farbe (Farbpunkt lange drücken: Palette ändern)',
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
      if (showWidths) ...[
        div,
        for (final w in presets)
          WidthDot(
            width: hl ? w / 4 : w,
            selected: c.activeWidth == w,
            onTap: () => c.setWidth(w),
          ),
      ],
      div,
    ];
  }

  List<Widget> _history(InkController c) => [
        ToolButton(
          icon: Icons.undo,
          label: 'Rückgängig (Strg+Z, 2 Finger tippen)',
          onTap: c.history.canUndo ? c.undo : null,
        ),
        ToolButton(
          icon: Icons.redo,
          label: 'Wiederholen (Strg+Y, 3 Finger tippen)',
          onTap: c.history.canRedo ? c.redo : null,
        ),
        ToolButton(
          icon: Icons.pan_tool_outlined,
          label: c.stylusOnly
              ? 'Nur Stift zeichnet – Finger navigieren'
              : 'Finger und Maus zeichnen',
          selected: c.stylusOnly,
          onTap: () => c.setStylusOnly(!c.stylusOnly),
        ),
      ];
}

IconData penIcon(PenType t) => switch (t) {
      PenType.fountain => Icons.edit_outlined,
      PenType.ballpoint => Icons.create_outlined,
      PenType.brush => Icons.brush_outlined,
    };

IconData shapeIcon(ShapeKind k) => switch (k) {
      ShapeKind.line => Icons.horizontal_rule,
      ShapeKind.arrow => Icons.arrow_right_alt,
      ShapeKind.rectangle => Icons.crop_square,
      ShapeKind.ellipse => Icons.circle_outlined,
      ShapeKind.triangle => Icons.change_history,
    };

IconData toolIcon(InkController c) => switch (c.tool) {
      ToolMode.pen => penIcon(c.penType),
      ToolMode.highlighter => Icons.border_color_outlined,
      ToolMode.eraser => Icons.auto_fix_normal_outlined,
      ToolMode.lasso => Icons.gesture,
      ToolMode.shape => shapeIcon(c.shapeKind),
      ToolMode.laser => Icons.highlight_alt,
    };

/// Trennlinie, passend zur Ausrichtung der Leiste.
class _Div extends StatelessWidget {
  const _Div(this.axis);
  final Axis axis;

  @override
  Widget build(BuildContext context) {
    final vertical = axis == Axis.vertical;
    return Container(
      width: vertical ? 24 : 1,
      height: vertical ? 1 : 24,
      margin: vertical
          ? const EdgeInsets.symmetric(vertical: 6)
          : const EdgeInsets.symmetric(horizontal: 6),
      color: context.mf.border,
    );
  }
}

/// Griff zum Verschieben der Leiste.
class _DragHandle extends StatelessWidget {
  const _DragHandle({
    required this.axis,
    this.onStart,
    this.onUpdate,
    this.onEnd,
  });

  final Axis axis;
  final GestureDragStartCallback? onStart;
  final GestureDragUpdateCallback? onUpdate;
  final GestureDragEndCallback? onEnd;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Ziehen: Leiste verschieben oder an einen Rand andocken',
      child: MouseRegion(
        cursor: SystemMouseCursors.grab,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanStart: onStart,
          onPanUpdate: onUpdate,
          onPanEnd: onEnd,
          child: SizedBox(
            width: axis == Axis.vertical ? 40 : 26,
            height: axis == Axis.vertical ? 26 : 40,
            child: Icon(Icons.drag_indicator,
                size: 18, color: context.mf.textMuted),
          ),
        ),
      ),
    );
  }
}

/// Ein gespeicherter Lieblingsstift in der Leiste.
class PresetButton extends StatelessWidget {
  const PresetButton({required this.preset, required this.controller});

  final PenPreset preset;
  final InkController controller;

  @override
  Widget build(BuildContext context) {
    final mf = context.mf;
    final active = controller.isActivePreset(preset);
    return Tooltip(
      message:
          '${preset.type.label}, ${preset.width.toStringAsFixed(1)} – lange drücken: entfernen',
      child: GestureDetector(
        onTap: () => controller.applyPreset(preset),
        onLongPress: () => controller.removePreset(preset),
        onSecondaryTap: () => controller.removePreset(preset),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 36,
          height: 40,
          decoration: BoxDecoration(
            color: active ? mf.accentSoft : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(penIcon(preset.type), size: 16, color: Color(preset.color)),
              const SizedBox(height: 3),
              Container(
                width: 18,
                height: (preset.width * 0.8).clamp(1.5, 6.0).toDouble(),
                decoration: BoxDecoration(
                  color: Color(preset.color),
                  borderRadius: BorderRadius.circular(3),
                  border: Border.all(color: mf.border, width: 0.5),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Werkzeugknopf mit Optionsmenü.
class _ToolWithMenu extends StatelessWidget {
  const _ToolWithMenu({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onSelect,
    required this.menu,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onSelect;
  final WidgetBuilder menu;

  @override
  Widget build(BuildContext context) {
    final mf = context.mf;
    return MenuAnchor(
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(mf.surface),
        shape: WidgetStatePropertyAll(RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: mf.border),
        )),
      ),
      menuChildren: [
        Padding(
          padding: const EdgeInsets.all(14),
          child: SizedBox(width: 280, child: Builder(builder: menu)),
        ),
      ],
      builder: (context, ctrl, _) => Stack(
        clipBehavior: Clip.none,
        children: [
          ToolButton(
            icon: icon,
            label: label,
            selected: selected,
            onTap: () {
              if (!selected) {
                onSelect();
              } else if (ctrl.isOpen) {
                ctrl.close();
              } else {
                ctrl.open();
              }
            },
          ),
          // Kleiner Punkt: hier gibt es Optionen.
          if (selected)
            Positioned(
              right: 5,
              bottom: 5,
              child: IgnorePointer(
                child: Container(
                  width: 4,
                  height: 4,
                  decoration:
                      BoxDecoration(color: mf.accent, shape: BoxShape.circle),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// --- Optionsmenüs -----------------------------------------------------------

class _OptionsTitle extends StatelessWidget {
  const _OptionsTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text,
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: context.mf.textMuted)),
      );
}

class _Hint extends StatelessWidget {
  const _Hint(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Text(text,
            style: TextStyle(fontSize: 12, color: context.mf.textMuted)),
      );
}

/// Ein Schalter mit Beschriftung (ohne Material-ListTile, damit es im Menü
/// kompakt bleibt).
class _Toggle extends StatelessWidget {
  const _Toggle(
      {required this.label, required this.value, required this.onChanged});

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onChanged(!value),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Expanded(
              child: Text(label,
                  style: TextStyle(fontSize: 14, color: context.mf.text)),
            ),
            Switch(value: value, onChanged: onChanged),
          ],
        ),
      ),
    );
  }
}

class _WidthSlider extends StatelessWidget {
  const _WidthSlider(
      {required this.c,
      required this.min,
      required this.max,
      required this.title});

  final InkController c;
  final double min;
  final double max;
  final String title;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final v = c.activeWidth.clamp(min, max).toDouble();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            _OptionsTitle('$title: ${v.toStringAsFixed(1)}'),
            Slider(value: v, min: min, max: max, onChanged: c.setWidth),
          ],
        );
      },
    );
  }
}

class PenOptions extends StatelessWidget {
  const PenOptions(this.c);
  final InkController c;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const _OptionsTitle('Stiftart'),
          SegmentedButton<PenType>(
            showSelectedIcon: false,
            segments: [
              for (final t in PenType.values)
                ButtonSegment(
                    value: t,
                    icon: Icon(penIcon(t), size: 16),
                    tooltip: t.label),
            ],
            selected: {c.penType},
            onSelectionChanged: (s) => c.setPenType(s.first),
          ),
          _Hint('${c.penType.label}: ${c.penType.hint}'),
          const SizedBox(height: 14),
          _WidthSlider(c: c, min: 0.5, max: 12, title: 'Strichstärke'),
          _Toggle(
            label: 'Formerkennung (Stift kurz halten)',
            value: c.settings.shapeRecognition,
            onChanged: (v) =>
                c.settings.update(() => c.settings.shapeRecognition = v),
          ),
          const SizedBox(height: 10),
          const _OptionsTitle('Lieblingsstifte'),
          OutlinedButton.icon(
            onPressed: c.saveCurrentAsPreset,
            icon: const Icon(Icons.star_outline, size: 18),
            label: const Text('Aktuellen Stift speichern'),
          ),
          const _Hint('Gespeicherte Stifte erscheinen in der Leiste. '
              'Lange drücken entfernt sie.'),
        ],
      ),
    );
  }
}

class HighlighterOptions extends StatelessWidget {
  const HighlighterOptions(this.c);
  final InkController c;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _WidthSlider(c: c, min: 4, max: 32, title: 'Breite'),
          _Toggle(
            label: 'Gerade Linien',
            value: c.settings.highlighterStraight,
            onChanged: (v) =>
                c.settings.update(() => c.settings.highlighterStraight = v),
          ),
          const _Hint('Textmarker liegt immer hinter der Schrift.'),
        ],
      ),
    );
  }
}

class EraserOptions extends StatelessWidget {
  const EraserOptions(this.c);
  final InkController c;

  @override
  Widget build(BuildContext context) {
    final s = c.settings;
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          SegmentedButton<EraserMode>(
            showSelectedIcon: false,
            segments: [
              for (final m in EraserMode.values)
                ButtonSegment(value: m, label: Text(m.label)),
            ],
            selected: {c.eraserMode},
            onSelectionChanged: (sel) => c.setEraserMode(sel.first),
          ),
          _Hint(c.eraserMode.hint),
          const SizedBox(height: 12),
          _OptionsTitle('Größe: ${c.eraserSize.round()}'),
          Slider(
            value: c.eraserSize.clamp(4.0, 40.0).toDouble(),
            min: 4,
            max: 40,
            onChanged: c.setEraserSize,
          ),
          _Toggle(
            label: 'Nur Textmarker radieren',
            value: s.eraseHighlighterOnly,
            onChanged: (v) => s.update(() => s.eraseHighlighterOnly = v),
          ),
          _Toggle(
            label: 'Danach zurück zum vorigen Werkzeug',
            value: s.eraserAutoReturn,
            onChanged: (v) => s.update(() => s.eraserAutoReturn = v),
          ),
        ],
      ),
    );
  }
}

class ShapeOptions extends StatelessWidget {
  const ShapeOptions(this.c);
  final InkController c;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const _OptionsTitle('Form'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final k in ShapeKind.values)
                ChoiceChip(
                  avatar: Icon(shapeIcon(k), size: 18),
                  label: Text(k.label),
                  selected: c.shapeKind == k,
                  onSelected: (_) => c.setShapeKind(k),
                ),
            ],
          ),
          const _Hint('Ziehen, um die Form aufzuspannen. Tipp: Mit dem Stift '
              'eine Form zeichnen und kurz halten geht auch.'),
        ],
      ),
    );
  }
}
