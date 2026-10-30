import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';

import '../app/theme.dart';
import '../ink/ink_controller.dart';

/// Kopfleiste im Editor (Notizbuch, Dokument, Canvas) im Stil von
/// Goodnotes: oben die Navigation, darunter die Werkzeuge.
class EditorTopBar extends StatelessWidget {
  const EditorTopBar({super.key, required this.nav, this.tools});

  final Widget nav;
  final Widget? tools;

  @override
  Widget build(BuildContext context) {
    final mf = context.mf;
    return Material(
      color: mf.surface,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: mf.border, width: 0.8)),
          boxShadow: const [
            BoxShadow(
                color: Color(0x14000000), blurRadius: 12, offset: Offset(0, 4)),
          ],
        ),
        child: SafeArea(
          bottom: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(height: 50, child: nav),
              if (tools != null) SizedBox(height: 58, child: tools),
            ],
          ),
        ),
      ),
    );
  }
}

/// Navigationszeile: links zurück + Titel, rechts Aktionen.
class EditorNavBar extends StatelessWidget {
  const EditorNavBar({
    super.key,
    required this.title,
    this.subtitle,
    this.onBack,
    this.onTitleTap,
    this.center,
    this.actions = const [],
  });

  final String title;
  final String? subtitle;
  final VoidCallback? onBack;
  final VoidCallback? onTitleTap;
  final Widget? center;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final mf = context.mf;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          NavIconButton(
            icon: Icons.arrow_back_ios_new,
            tooltip: 'Zurück',
            onTap: onBack ?? () => Navigator.of(context).maybePop(),
          ),
          const SizedBox(width: 4),
          Flexible(
            flex: 2,
            child: InkWell(
              onTap: onTitleTap,
              borderRadius: BorderRadius.circular(10),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            letterSpacing: -0.2,
                            color: mf.text)),
                    if (subtitle != null)
                      Text(subtitle!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 11, color: mf.textMuted)),
                  ],
                ),
              ),
            ),
          ),
          if (center != null) ...[
            const SizedBox(width: 8),
            center!,
          ],
          // Aktionen rechts; auf schmalen Geräten seitlich scrollbar.
          Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                reverse: true,
                child: Row(mainAxisSize: MainAxisSize.min, children: actions),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Runder, flacher Knopf für die Navigationszeile.
class NavIconButton extends StatelessWidget {
  const NavIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    this.onTap,
    this.active = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final mf = context.mf;
    final enabled = onTap != null;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: active ? mf.accentSoft : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon,
              size: 20,
              color: !enabled
                  ? mf.textMuted.withValues(alpha: 0.35)
                  : active
                      ? mf.accent
                      : mf.text),
        ),
      ),
    );
  }
}

/// Seitenanzeige "‹ 3 / 12 ›".
class PagePager extends StatelessWidget {
  const PagePager({
    super.key,
    required this.index,
    required this.count,
    required this.onPrev,
    required this.onNext,
    this.onTap,
  });

  final int index;
  final int count;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final mf = context.mf;
    return Container(
      height: 34,
      decoration: BoxDecoration(
        color: mf.surfaceRaised,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _PagerArrow(
              icon: Icons.chevron_left, onTap: index > 0 ? onPrev : null),
          InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Text('${index + 1} / $count',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      fontFeatures: const [FontFeature.tabularFigures()],
                      color: mf.text)),
            ),
          ),
          _PagerArrow(
              icon: Icons.chevron_right,
              onTap: index < count - 1 ? onNext : null),
        ],
      ),
    );
  }
}

class _PagerArrow extends StatelessWidget {
  const _PagerArrow({required this.icon, this.onTap});
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final mf = context.mf;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: 30,
        height: 34,
        child: Icon(icon,
            size: 20,
            color: onTap == null ? mf.textMuted.withValues(alpha: 0.35) : mf.text),
      ),
    );
  }
}

/// Dünne senkrechte Trennlinie zwischen Gruppen in der Kopfleiste.
class NavDivider extends StatelessWidget {
  const NavDivider({super.key});

  @override
  Widget build(BuildContext context) => Container(
        width: 1,
        height: 22,
        margin: const EdgeInsets.symmetric(horizontal: 6),
        color: context.mf.border,
      );
}

/// Rückgängig / Wiederholen, aktualisiert sich selbst.
class UndoRedoButtons extends StatelessWidget {
  const UndoRedoButtons({super.key, required this.controller});

  final InkController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          NavIconButton(
            icon: Icons.undo_rounded,
            tooltip: 'Rückgängig (2 Finger tippen)',
            onTap: c.history.canUndo ? c.undo : null,
          ),
          NavIconButton(
            icon: Icons.redo_rounded,
            tooltip: 'Wiederholen (3 Finger tippen)',
            onTap: c.history.canRedo ? c.redo : null,
          ),
        ],
      ),
    );
  }
}
