import 'package:flutter/material.dart';

import '../../app/sections.dart';
import '../../app/services.dart';
import '../../app/theme.dart';
import '../../ui/widgets.dart';
import '../common/create_dialogs.dart';
import '../common/object_card.dart';

/// HOME – die zentrale Übersicht.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, required this.onNavigate});

  final ValueChanged<Section> onNavigate;

  String _greeting() {
    final h = DateTime.now().hour;
    if (h < 5) return 'Gute Nacht';
    if (h < 11) return 'Guten Morgen';
    if (h < 18) return 'Guten Tag';
    return 'Guten Abend';
  }

  String _date() {
    const days = [
      'Montag', 'Dienstag', 'Mittwoch', 'Donnerstag', 'Freitag', 'Samstag',
      'Sonntag'
    ];
    const months = [
      'Januar', 'Februar', 'März', 'April', 'Mai', 'Juni', 'Juli', 'August',
      'September', 'Oktober', 'November', 'Dezember'
    ];
    final d = DateTime.now();
    return '${days[d.weekday - 1]}, ${d.day}. ${months[d.month - 1]}';
  }

  @override
  Widget build(BuildContext context) {
    final repo = Services.of(context).objects;
    final mf = context.mf;
    return ListenableBuilder(
      listenable: repo,
      builder: (context, _) {
        final pinned = repo.pinned();
        final recent = repo.recent();
        return ListView(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
          children: [
            PageHeader(title: _greeting(), subtitle: _date()),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _QuickAction(
                  icon: Icons.menu_book_outlined,
                  label: 'Neues Notizbuch',
                  onTap: () => createNotebook(context),
                ),
                _QuickAction(
                  icon: Icons.bubble_chart_outlined,
                  label: 'Neuer Canvas',
                  onTap: () => createBoard(context),
                ),
                _QuickAction(
                  icon: Icons.search,
                  label: 'Suchen',
                  onTap: () => onNavigate(Section.search),
                ),
              ],
            ),
            const SizedBox(height: 32),
            if (pinned.isNotEmpty) ...[
              const SectionHeader('Angeheftet'),
              ObjectGrid(objects: pinned),
              const SizedBox(height: 32),
            ],
            SectionHeader(
              'Zuletzt geöffnet',
              action: recent.isEmpty
                  ? null
                  : TextButton(
                      onPressed: () => onNavigate(Section.notebook),
                      child: const Text('Alle Notizbücher')),
            ),
            if (recent.isEmpty)
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: mf.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: mf.border),
                ),
                child: Text(
                  'Noch nichts hier. Leg oben dein erstes Notizbuch oder '
                  'deinen ersten Canvas an.',
                  style: TextStyle(color: mf.textMuted),
                ),
              )
            else
              ObjectGrid(objects: recent),
            const SizedBox(height: 32),
            const SectionHeader('Bereiche'),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final s in Section.values)
                  if (s != Section.home)
                    _AreaTile(section: s, onTap: () => onNavigate(s)),
              ],
            ),
            const SizedBox(height: 32),
            const SectionHeader('Lernfortschritt'),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: mf.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: mf.border),
              ),
              child: Row(
                children: [
                  Icon(Icons.school_outlined, color: mf.accent),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      'Sobald der Lernbereich da ist (Phase 7), siehst du hier '
                      'fällige Karteikarten und schwierige Themen.',
                      style: TextStyle(color: mf.textMuted),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _QuickAction extends StatelessWidget {
  const _QuickAction(
      {required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final mf = context.mf;
    return Material(
      color: mf.surface,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: mf.border)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 20, color: mf.accent),
              const SizedBox(width: 10),
              Text(label,
                  style:
                      TextStyle(fontWeight: FontWeight.w600, color: mf.text)),
            ],
          ),
        ),
      ),
    );
  }
}

class _AreaTile extends StatelessWidget {
  const _AreaTile({required this.section, required this.onTap});

  final Section section;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final mf = context.mf;
    return SizedBox(
      width: 150,
      child: Material(
        color: mf.surface,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: mf.border)),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(section.icon, color: mf.accent),
                const SizedBox(height: 10),
                Text(section.label,
                    style: TextStyle(
                        fontWeight: FontWeight.w600, color: mf.text)),
                if (section.comingInPhase != null)
                  Text('ab Phase ${section.comingInPhase}',
                      style: TextStyle(fontSize: 12, color: mf.textMuted)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
