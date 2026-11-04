import 'package:flutter/material.dart';

import '../data/models.dart';
import '../features/archive/archive_screen.dart';
import '../features/common/collection_screen.dart';
import '../features/common/create_dialogs.dart';
import '../features/home/home_screen.dart';
import '../features/knowledge/knowledge_screen.dart';
import '../features/search/search_screen.dart';
import '../features/study/study_screen.dart';
import 'sections.dart';
import 'services.dart';
import 'theme.dart';
import '../ui/futuristic.dart';

/// Rahmen der App: Seitenleiste (iPad quer, Windows) oder
/// untere Leiste (iPhone, iPad hochkant schmal).
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  Section _section = Section.home;

  void _go(Section s) => setState(() => _section = s);

  Widget _body() {
    switch (_section) {
      case Section.home:
        return HomeScreen(onNavigate: _go);
      case Section.notebook:
        return const CollectionScreen(
          type: ObjectType.notebook,
          title: 'Notizbücher',
          subtitle: 'Handschrift, Seiten, Vorlagen',
          createLabel: 'Neues Notizbuch',
          onCreate: createNotebook,
          emptyIcon: Icons.menu_book_outlined,
          emptyTitle: 'Noch kein Notizbuch',
          emptyMessage:
              'Leg dein erstes Notizbuch an und schreib los – mit Apple Pencil, '
              'Maus oder Finger.',
        );
      case Section.canvas:
        return const CollectionScreen(
          type: ObjectType.board,
          title: 'Canvas',
          subtitle: 'Unendliche Flächen für Mindmaps und Ideen',
          createLabel: 'Neuer Canvas',
          onCreate: createBoard,
          emptyIcon: Icons.bubble_chart_outlined,
          emptyTitle: 'Noch kein Canvas',
          emptyMessage:
              'Eine unendliche Fläche für Karten, Verbindungen und Handschrift.',
        );
      case Section.search:
        return const SearchScreen();
      case Section.archive:
        return const ArchiveScreen();
      case Section.documents:
        return const CollectionScreen(
          type: ObjectType.document,
          title: 'Dokumente',
          subtitle: 'PDFs lesen, markieren und hineinschreiben',
          createLabel: 'PDF importieren',
          onCreate: importDocument,
          emptyIcon: Icons.picture_as_pdf_outlined,
          emptyTitle: 'Noch keine Dokumente',
          emptyMessage:
              'Importiere eine PDF – z. B. ein Skript oder Arbeitsblatt – und '
              'schreib mit dem Stift direkt hinein. Das Original bleibt unverändert.',
        );
      case Section.knowledge:
        return const KnowledgeScreen();
      case Section.study:
        return const StudyScreen();
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final wide = constraints.maxWidth >= 720;
      final body = AnimatedSwitcher(
        duration: const Duration(milliseconds: 220),
        switchInCurve: Curves.easeOutCubic,
        transitionBuilder: (child, anim) => FadeTransition(
          opacity: anim,
          child: SlideTransition(
            position: Tween(begin: const Offset(0, 0.015), end: Offset.zero)
                .animate(anim),
            child: child,
          ),
        ),
        child: KeyedSubtree(key: ValueKey(_section), child: _body()),
      );
      if (wide) {
        return Scaffold(
          backgroundColor: Colors.transparent,
          body: AuroraBackground(
            child: Row(
              children: [
                _Sidebar(current: _section, onSelect: _go),
                Expanded(child: SafeArea(left: false, child: body)),
              ],
            ),
          ),
        );
      }
      return _MobileShell(current: _section, onSelect: _go, body: body);
    });
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({required this.current, required this.onSelect});

  final Section current;
  final ValueChanged<Section> onSelect;

  @override
  Widget build(BuildContext context) {
    final mf = context.mf;
    return SafeArea(
      right: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 0, 12),
        child: SizedBox(
          width: 232,
          child: GlassPanel(
            radius: 24,
            padding: const EdgeInsets.fromLTRB(12, 18, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Row(
                    children: [
                      const MindFlowLogo(size: 30),
                      const SizedBox(width: 11),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('MindFlow',
                                style: TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: -0.3,
                                    color: mf.text)),
                            Text('Your thoughts. Connected.',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    fontSize: 10.5,
                                    letterSpacing: 0.2,
                                    color: mf.textMuted)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 22),
                GlowButton(
                  label: 'Neu erstellen',
                  icon: Icons.add_rounded,
                  expand: true,
                  onPressed: () => showCreateMenu(context),
                ),
                const SizedBox(height: 18),
                Expanded(
                  child: ListView(
                    children: [
                      for (final s in Section.values)
                        _NavItem(
                          section: s,
                          selected: s == current,
                          onTap: () => onSelect(s),
                        ),
                    ],
                  ),
                ),
                const _ThemeSwitch(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatefulWidget {
  const _NavItem(
      {required this.section, required this.selected, required this.onTap});

  final Section section;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_NavItem> createState() => _NavItemState();
}

class _NavItemState extends State<_NavItem> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final mf = context.mf;
    final sel = widget.selected;
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              gradient: sel
                  ? LinearGradient(colors: [
                      mf.accent.withValues(alpha: mf.isDark ? 0.26 : 0.14),
                      mf.accent2.withValues(alpha: mf.isDark ? 0.10 : 0.06),
                    ])
                  : null,
              color: !sel && _hover ? mf.surfaceRaised : null,
              border: Border.all(
                  color: sel
                      ? mf.accent.withValues(alpha: 0.35)
                      : Colors.transparent),
            ),
            child: Row(
              children: [
                sel
                    ? GradientIcon(widget.section.selectedIcon, size: 20)
                    : Icon(widget.section.icon, size: 20, color: mf.textMuted),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(widget.section.label,
                      style: TextStyle(
                          fontWeight: sel ? FontWeight.w600 : FontWeight.w500,
                          color: sel ? mf.text : mf.textMuted)),
                ),
                if (widget.section == Section.study)
                  ListenableBuilder(
                    listenable: Services.of(context).objects,
                    builder: (context, _) {
                      final due = Services.of(context)
                          .study
                          .stats(DateTime.now())
                          .due;
                      if (due == 0) return const SizedBox.shrink();
                      return Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 2),
                        margin: const EdgeInsets.only(right: 6),
                        decoration: BoxDecoration(
                          color: mf.accent,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text('$due',
                            style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: Colors.white)),
                      );
                    },
                  ),
                if (sel)
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: mf.accent2,
                      boxShadow: [BoxShadow(color: mf.accent2, blurRadius: 8)],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Umschalter System / Hell / Dunkel.
class _ThemeSwitch extends StatelessWidget {
  const _ThemeSwitch();

  @override
  Widget build(BuildContext context) {
    final services = Services.of(context);
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: services.themeMode,
      builder: (context, mode, _) => SegmentedButton<ThemeMode>(
        showSelectedIcon: false,
        segments: const [
          ButtonSegment(
              value: ThemeMode.system,
              icon: Icon(Icons.brightness_auto_outlined, size: 18),
              tooltip: 'Wie System'),
          ButtonSegment(
              value: ThemeMode.light,
              icon: Icon(Icons.light_mode_outlined, size: 18),
              tooltip: 'Hell'),
          ButtonSegment(
              value: ThemeMode.dark,
              icon: Icon(Icons.dark_mode_outlined, size: 18),
              tooltip: 'Dunkel'),
        ],
        selected: {mode},
        onSelectionChanged: (s) => services.setThemeMode(s.first),
      ),
    );
  }
}

/// Mobile Navigation: 4 Hauptbereiche + "Mehr".
class _MobileShell extends StatelessWidget {
  const _MobileShell(
      {required this.current, required this.onSelect, required this.body});

  final Section current;
  final ValueChanged<Section> onSelect;
  final Widget body;

  static const _main = [
    Section.home,
    Section.notebook,
    Section.canvas,
    Section.search,
  ];

  @override
  Widget build(BuildContext context) {
    final index = _main.indexOf(current);
    final mf = context.mf;
    return Scaffold(
      backgroundColor: mf.background,
      body: AuroraBackground(child: SafeArea(bottom: false, child: body)),
      floatingActionButton: _GlowFab(onTap: () => showCreateMenu(context)),
      bottomNavigationBar: NavigationBar(
        backgroundColor: mf.surface,
        indicatorColor: mf.accentSoft,
        surfaceTintColor: Colors.transparent,
        height: 66,
        selectedIndex: index < 0 ? _main.length : index,
        onDestinationSelected: (i) {
          if (i < _main.length) {
            onSelect(_main[i]);
          } else {
            _showMore(context);
          }
        },
        destinations: [
          for (final s in _main)
            NavigationDestination(
                icon: Icon(s.icon),
                selectedIcon: Icon(s.selectedIcon),
                label: s.label),
          const NavigationDestination(
              icon: Icon(Icons.more_horiz), label: 'Mehr'),
        ],
      ),
    );
  }

  void _showMore(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final s in Section.values)
                if (!_main.contains(s))
                  ListTile(
                    leading: Icon(s.icon),
                    title: Text(s.label),
                    trailing: s.comingInPhase == null
                        ? null
                        : Text('Phase ${s.comingInPhase}'),
                    onTap: () {
                      Navigator.pop(ctx);
                      onSelect(s);
                    },
                  ),
              const SizedBox(height: 12),
              const _ThemeSwitch(),
            ],
          ),
        ),
      ),
    );
  }
}

/// Runder Plus-Knopf mit Verlauf (iPhone).
class _GlowFab extends StatelessWidget {
  const _GlowFab({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final mf = context.mf;
    return Tooltip(
      message: 'Neu',
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 58,
          height: 58,
          decoration: BoxDecoration(
            gradient: mf.gradient,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
            boxShadow: [
              BoxShadow(
                  color: mf.glow,
                  blurRadius: 22,
                  spreadRadius: -2,
                  offset: const Offset(0, 8)),
            ],
          ),
          child: const Icon(Icons.add_rounded, color: Colors.white, size: 28),
        ),
      ),
    );
  }
}
