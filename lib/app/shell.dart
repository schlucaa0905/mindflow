import 'package:flutter/material.dart';

import '../data/models.dart';
import '../features/archive/archive_screen.dart';
import '../features/common/collection_screen.dart';
import '../features/common/coming_soon.dart';
import '../features/common/create_dialogs.dart';
import '../features/home/home_screen.dart';
import '../features/search/search_screen.dart';
import 'sections.dart';
import 'services.dart';
import 'theme.dart';

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
      case Section.knowledge:
      case Section.study:
        return ComingSoonScreen(section: _section);
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final wide = constraints.maxWidth >= 720;
      final body = KeyedSubtree(key: ValueKey(_section), child: _body());
      if (wide) {
        return Scaffold(
          body: Row(
            children: [
              _Sidebar(current: _section, onSelect: _go),
              VerticalDivider(width: 1, color: context.mf.border),
              Expanded(child: SafeArea(left: false, child: body)),
            ],
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
    return Container(
      width: 236,
      color: mf.surface,
      child: SafeArea(
        right: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 18, 14, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  children: [
                    Container(
                      width: 26,
                      height: 26,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(colors: [
                          mf.accent,
                          mf.accent.withValues(alpha: 0.55)
                        ]),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.blur_on,
                          size: 16, color: Colors.white),
                    ),
                    const SizedBox(width: 10),
                    Text('MindFlow',
                        style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.3,
                            color: mf.text)),
                  ],
                ),
              ),
              const SizedBox(height: 22),
              FilledButton.icon(
                onPressed: () => showCreateMenu(context),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Neu'),
                style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(42),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12))),
              ),
              const SizedBox(height: 16),
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
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem(
      {required this.section, required this.selected, required this.onTap});

  final Section section;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final mf = context.mf;
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: selected ? mf.accentSoft : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Icon(selected ? section.selectedIcon : section.icon,
                    size: 20, color: selected ? mf.accent : mf.textMuted),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(section.label,
                      style: TextStyle(
                          fontWeight:
                              selected ? FontWeight.w600 : FontWeight.w500,
                          color: selected ? mf.text : mf.textMuted)),
                ),
                if (section.comingInPhase != null)
                  Text('bald',
                      style: TextStyle(fontSize: 11, color: mf.textMuted)),
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
    return Scaffold(
      body: SafeArea(bottom: false, child: body),
      floatingActionButton: FloatingActionButton(
        onPressed: () => showCreateMenu(context),
        tooltip: 'Neu',
        child: const Icon(Icons.add),
      ),
      bottomNavigationBar: NavigationBar(
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
