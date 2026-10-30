import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';

import '../app/theme.dart';
import '../ink/camera.dart';
import '../ink/ink_controller.dart';
import 'clean_menu.dart';

/// Kopfleiste im Editor (Notizbuch, Dokument, Canvas): eine schwebende
/// „Insel“ über dem Schreibtisch – oben die Navigation, darunter die
/// Werkzeuge. Sie liegt über, nicht auf dem Blatt: Das Blatt kann sie
/// nie verdecken.
class EditorTopBar extends StatelessWidget {
  const EditorTopBar({super.key, required this.nav, this.tools});

  final Widget nav;
  final Widget? tools;

  @override
  Widget build(BuildContext context) {
    final mf = context.mf;
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
        child: Material(
          type: MaterialType.transparency,
          child: Container(
            decoration: BoxDecoration(
              color: mf.surface,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color.lerp(mf.surface, mf.accent, mf.isDark ? 0.05 : 0.02)!,
                  mf.surface,
                ],
              ),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: mf.glassEdge),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: mf.isDark ? 0.45 : 0.10),
                  blurRadius: 26,
                  offset: const Offset(0, 10),
                ),
                BoxShadow(
                  color: mf.glow.withValues(alpha: 0.12),
                  blurRadius: 30,
                  spreadRadius: -10,
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(22),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Feine Lichtkante im Markenverlauf.
                  Container(
                    height: 2,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: [
                        mf.accent.withValues(alpha: 0),
                        mf.accent.withValues(alpha: 0.7),
                        mf.accent2.withValues(alpha: 0.7),
                        mf.accent2.withValues(alpha: 0),
                      ]),
                    ),
                  ),
                  SizedBox(height: 48, child: nav),
                  if (tools != null) ...[
                    Container(
                      height: 1,
                      margin: const EdgeInsets.symmetric(horizontal: 14),
                      color: mf.border.withValues(alpha: 0.6),
                    ),
                    SizedBox(height: 58, child: tools),
                  ],
                ],
              ),
            ),
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
    this.icon,
  });

  /// Kleines Symbol vor dem Titel (Notizbuch, PDF, Canvas).
  final IconData? icon;
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
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (icon != null) ...[
                      Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              mf.accent.withValues(alpha: 0.32),
                              mf.accent2.withValues(alpha: 0.16),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(9),
                          border: Border.all(
                              color: mf.accent.withValues(alpha: 0.3)),
                        ),
                        child: Icon(icon, size: 16, color: mf.text),
                      ),
                      const SizedBox(width: 10),
                    ],
                    Flexible(
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
            gradient: active
                ? LinearGradient(colors: [
                    mf.accent.withValues(alpha: 0.28),
                    mf.accent2.withValues(alpha: 0.12),
                  ])
                : null,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: active
                    ? mf.accent.withValues(alpha: 0.4)
                    : Colors.transparent),
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
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: mf.glassEdge),
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

/// Gruppe von Knöpfen in einer dezenten Kapsel – ordnet die Kopfleiste.
class NavGroup extends StatelessWidget {
  const NavGroup({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final mf = context.mf;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 3),
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: mf.surfaceRaised.withValues(alpha: mf.isDark ? 0.75 : 1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: mf.glassEdge),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: children),
    );
  }
}

/// Zoom-Anzeige mit Menü: „125 % ▾“ → einpassen, 100 %, 200 % …
class ZoomPill extends StatelessWidget {
  const ZoomPill({
    super.key,
    required this.camera,
    required this.onFit,
    this.fitLabel = 'Ganze Seite',
    this.onFitWidth,
  });

  final Camera camera;
  final VoidCallback onFit;
  final String fitLabel;
  final VoidCallback? onFitWidth;

  void _zoomTo(double target) {
    final v = camera.viewport;
    if (v.isEmpty || camera.scale <= 0) return;
    camera.zoomAt(Offset(v.width / 2, v.height / 2), target / camera.scale);
  }

  void _zoomBy(double f) {
    final v = camera.viewport;
    if (v.isEmpty) return;
    camera.zoomAt(Offset(v.width / 2, v.height / 2), f);
  }

  @override
  Widget build(BuildContext context) {
    final mf = context.mf;
    return ListenableBuilder(
      listenable: camera,
      builder: (context, _) {
        final pct = (camera.scale * 100).round();
        return CleanMenuButton(
          tooltip: 'Zoom',
          trigger: Container(
            height: 34,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            alignment: Alignment.center,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.zoom_in_rounded, size: 17, color: mf.textMuted),
                const SizedBox(width: 5),
                Text('$pct %',
                    style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        fontFeatures: const [FontFeature.tabularFigures()],
                        color: mf.text)),
                Icon(Icons.expand_more_rounded, size: 16, color: mf.textMuted),
              ],
            ),
          ),
          entries: [
            const CleanMenuEntry('in', 'Vergrößern', icon: Icons.zoom_in_rounded),
            const CleanMenuEntry('out', 'Verkleinern',
                icon: Icons.zoom_out_rounded),
            const CleanMenuEntry.divider(),
            CleanMenuEntry('fit', fitLabel, icon: Icons.fit_screen_outlined),
            if (onFitWidth != null)
              const CleanMenuEntry('width', 'Seitenbreite',
                  icon: Icons.width_full_outlined),
            CleanMenuEntry('100', '100 %',
                icon: Icons.crop_square_rounded, checked: pct == 100),
            CleanMenuEntry('200', '200 %',
                icon: Icons.zoom_out_map_rounded, checked: pct == 200),
          ],
          onSelected: (v) {
            switch (v) {
              case 'in':
                _zoomBy(1.25);
              case 'out':
                _zoomBy(0.8);
              case 'fit':
                onFit();
              case 'width':
                onFitWidth?.call();
              case '100':
                _zoomTo(1);
              case '200':
                _zoomTo(2);
            }
          },
        );
      },
    );
  }
}

/// Schalter „Nur Stift“: an = Finger verschiebt nur, aus = Finger schreibt.
class StylusToggle extends StatelessWidget {
  const StylusToggle({super.key, required this.controller});

  final InkController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final only = controller.stylusOnly;
        return NavIconButton(
          icon: only ? Icons.draw_outlined : Icons.touch_app_outlined,
          tooltip: only
              ? 'Nur Stift schreibt – tippen: auch mit dem Finger schreiben'
              : 'Finger schreibt mit – tippen: nur mit dem Stift schreiben',
          active: !only,
          onTap: () {
            controller.setStylusOnly(!only);
            ScaffoldMessenger.maybeOf(context)?.hideCurrentSnackBar();
            ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
              duration: const Duration(seconds: 2),
              content: Text(only
                  ? 'Mit dem Finger schreiben: an'
                  : 'Nur Stift: Finger verschieben und zoomen'),
            ));
          },
        );
      },
    );
  }
}
