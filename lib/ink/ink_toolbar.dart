import 'package:flutter/material.dart';

import '../app/theme.dart';
import '../ui/widgets.dart';
import 'ink_controller.dart';

/// Werkzeugleiste für Handschrift. Wird von Notizbuch und Canvas genutzt.
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
        final palette = hl ? style.highlighter : style.ink;
        final active = hl ? c.highlighterColor : c.penColor;
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
                ToolButton(
                  icon: Icons.edit_outlined,
                  label: 'Stift',
                  selected: c.tool == ToolMode.pen,
                  onTap: () => c.setTool(ToolMode.pen),
                ),
                ToolButton(
                  icon: Icons.border_color_outlined,
                  label: 'Textmarker',
                  selected: hl,
                  onTap: () => c.setTool(ToolMode.highlighter),
                ),
                ToolButton(
                  icon: Icons.auto_fix_normal_outlined,
                  label: 'Radierer',
                  selected: c.tool == ToolMode.eraser,
                  onTap: () => c.setTool(ToolMode.eraser),
                ),
                const PanelDivider(),
                for (final color in palette)
                  ColorDot(
                    color: color,
                    selected: c.tool != ToolMode.eraser &&
                        color.toARGB32() == active.toARGB32(),
                    onTap: () => c.setColor(color),
                  ),
                const PanelDivider(),
                for (final w in const [1.5, 2.5, 4.5])
                  WidthDot(
                    width: w,
                    selected: c.penWidth == w,
                    onTap: () => c.setWidth(w),
                  ),
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
