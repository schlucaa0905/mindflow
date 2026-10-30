import 'package:flutter/material.dart';

import '../app/theme.dart';
import '../ui/color_picker.dart';
import '../ui/widgets.dart';
import 'ink_controller.dart';

/// Werkzeugleiste für Handschrift. Wird von Notizbuch und Canvas genutzt.
///
/// Ein Werkzeug antippen wählt es aus. Ein bereits gewähltes Werkzeug
/// nochmal antippen öffnet seine Optionen (Stiftart, Breite, Radierer-Art …).
class InkToolbar extends StatelessWidget {
  const InkToolbar({
    super.key,
    required this.controller,
    required this.paper,
    this.leading = const [],
    this.trailing = const [],
    this.showInkTools = true,
  });

  final InkController controller;
  final Paper paper;
  final List<Widget> leading;
  final List<Widget> trailing;
  final bool showInkTools;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final c = controller;
        final style = PaperStyle.of(paper);
        final hl = c.tool == ToolMode.highlighter;
        final showColors = c.tool == ToolMode.pen ||
            hl ||
            c.tool == ToolMode.shape ||
            c.selection.isNotEmpty;
        final palette = hl ? style.highlighter : style.ink;
        final active = hl ? c.highlighterColor : c.penColor;
        final presets = hl ? const [8.0, 14.0, 22.0] : const [1.5, 2.5, 4.5];

        return FloatingPanel(
          child: Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            alignment: WrapAlignment.center,
            spacing: 2,
            runSpacing: 4,
            children: [
              ...leading,
              if (leading.isNotEmpty && showInkTools) const PanelDivider(),
              if (showInkTools) ...[
                _ToolWithMenu(
                  icon: c.penType == PenType.ballpoint
                      ? Icons.create_outlined
                      : Icons.edit_outlined,
                  label: '${c.penType.label} (nochmal tippen: Optionen)',
                  selected: c.tool == ToolMode.pen,
                  onSelect: () => c.setTool(ToolMode.pen),
                  menu: (context) => _PenOptions(c),
                ),
                _ToolWithMenu(
                  icon: Icons.border_color_outlined,
                  label: 'Textmarker (nochmal tippen: Breite)',
                  selected: hl,
                  onSelect: () => c.setTool(ToolMode.highlighter),
                  menu: (context) => _WidthSlider(
                      c: c, min: 4, max: 32, title: 'Breite Textmarker'),
                ),
                _ToolWithMenu(
                  icon: Icons.auto_fix_normal_outlined,
                  label: 'Radierer (nochmal tippen: Optionen)',
                  selected: c.tool == ToolMode.eraser,
                  onSelect: () => c.setTool(ToolMode.eraser),
                  menu: (context) => _EraserOptions(c),
                ),
                ToolButton(
                  icon: Icons.gesture,
                  label: 'Lasso: einkreisen, dann verschieben',
                  selected: c.tool == ToolMode.lasso,
                  onTap: () => c.setTool(ToolMode.lasso),
                ),
                _ToolWithMenu(
                  icon: _shapeIcon(c.shapeKind),
                  label: 'Formen (nochmal tippen: Form wählen)',
                  selected: c.tool == ToolMode.shape,
                  onSelect: () => c.setTool(ToolMode.shape),
                  menu: (context) => _ShapeOptions(c),
                ),
                if (showColors) ...[
                  const PanelDivider(),
                  for (final color in [...palette, ...c.customColors])
                    ColorDot(
                      color: color,
                      selected: c.selection.isEmpty &&
                          color.toARGB32() == active.toARGB32(),
                      onTap: () => c.setColor(color),
                    ),
                  ToolButton(
                    icon: Icons.colorize_outlined,
                    label: 'Eigene Farbe',
                    onTap: () async {
                      final picked = await pickColor(context, active);
                      if (picked != null) c.addCustomColor(picked);
                    },
                  ),
                ],
                if (c.tool == ToolMode.pen ||
                    hl ||
                    c.tool == ToolMode.shape) ...[
                  const PanelDivider(),
                  for (final w in presets)
                    WidthDot(
                      width: hl ? w / 4 : w,
                      selected: c.activeWidth == w,
                      onTap: () => c.setWidth(w),
                    ),
                ],
                const PanelDivider(),
                ToolButton(
                  icon: Icons.undo,
                  label: 'Rückgängig',
                  onTap: c.history.canUndo ? c.undo : null,
                ),
                ToolButton(
                  icon: Icons.redo,
                  label: 'Wiederholen',
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
              ],
              if (trailing.isNotEmpty) const PanelDivider(),
              ...trailing,
            ],
          ),
        );
      },
    );
  }
}

IconData _shapeIcon(ShapeKind k) => switch (k) {
      ShapeKind.line => Icons.horizontal_rule,
      ShapeKind.arrow => Icons.arrow_right_alt,
      ShapeKind.rectangle => Icons.crop_square,
      ShapeKind.ellipse => Icons.circle_outlined,
    };

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
          child: SizedBox(width: 260, child: Builder(builder: menu)),
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

class _WidthSlider extends StatelessWidget {
  const _WidthSlider(
      {required this.c, required this.min, required this.max, required this.title});

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
            Slider(
              value: v,
              min: min,
              max: max,
              onChanged: c.setWidth,
            ),
          ],
        );
      },
    );
  }
}

class _PenOptions extends StatelessWidget {
  const _PenOptions(this.c);
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
                ButtonSegment(value: t, label: Text(t.label)),
            ],
            selected: {c.penType},
            onSelectionChanged: (s) => c.setPenType(s.first),
          ),
          const SizedBox(height: 6),
          Text(
            c.penType == PenType.fountain
                ? 'Wird dicker, je fester du drückst.'
                : 'Immer gleich dick.',
            style: TextStyle(fontSize: 12, color: context.mf.textMuted),
          ),
          const SizedBox(height: 14),
          _WidthSlider(c: c, min: 0.5, max: 12, title: 'Strichstärke'),
        ],
      ),
    );
  }
}

class _EraserOptions extends StatelessWidget {
  const _EraserOptions(this.c);
  final InkController c;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const _OptionsTitle('Radierer'),
          SegmentedButton<EraserMode>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: EraserMode.stroke, label: Text('Ganzer Strich')),
              ButtonSegment(value: EraserMode.area, label: Text('Bereich')),
            ],
            selected: {c.eraserMode},
            onSelectionChanged: (s) => c.setEraserMode(s.first),
          ),
          const SizedBox(height: 6),
          Text(c.eraserMode.label,
              style: TextStyle(fontSize: 12, color: context.mf.textMuted)),
          const SizedBox(height: 12),
          _OptionsTitle('Größe: ${c.eraserSize.round()}'),
          Slider(
            value: c.eraserSize,
            min: 4,
            max: 40,
            onChanged: c.setEraserSize,
          ),
        ],
      ),
    );
  }
}

class _ShapeOptions extends StatelessWidget {
  const _ShapeOptions(this.c);
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
                  avatar: Icon(_shapeIcon(k), size: 18),
                  label: Text(k.label),
                  selected: c.shapeKind == k,
                  onSelected: (_) => c.setShapeKind(k),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text('Ziehen, um die Form aufzuspannen.',
              style: TextStyle(fontSize: 12, color: context.mf.textMuted)),
        ],
      ),
    );
  }
}
