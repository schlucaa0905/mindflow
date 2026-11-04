import 'package:flutter/material.dart';

import '../../app/navigation.dart';
import '../../app/sections.dart';
import '../../app/services.dart';
import '../../app/theme.dart';
import '../../data/models.dart';
import '../../ui/futuristic.dart';
import '../../ui/widgets.dart';
import '../common/create_dialogs.dart';
import '../common/object_card.dart';
import '../common/object_info.dart';
import '../notebook/notebook_cover.dart';
import '../study/review_screen.dart';

/// HOME – ruhig und aufs Wesentliche: weitermachen, schnell anlegen,
/// zuletzt Geöffnetes, Angeheftetes, Lernstand.
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
    final s = Services.of(context);
    final mf = context.mf;
    return ListenableBuilder(
      listenable: s.objects,
      builder: (context, _) {
        final recent = s.objects.recent(limit: 12);
        final pinned = s.objects.pinned();
        final stats = s.study.stats(DateTime.now());
        return ListView(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 48),
          children: [
            // Kopf: Begrüßung links, Suche rechts.
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_date(),
                          style: TextStyle(fontSize: 13, color: mf.textMuted)),
                      const SizedBox(height: 4),
                      Text(_greeting(),
                          style: TextStyle(
                              fontSize: 30,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -1,
                              color: mf.text)),
                    ],
                  ),
                ),
                IconButton.filledTonal(
                  tooltip: 'Suchen',
                  onPressed: () => onNavigate(Section.search),
                  icon: const Icon(Icons.search_rounded),
                ),
              ],
            ),
            const SizedBox(height: 22),
            if (recent.isNotEmpty) _Continue(object: recent.first),
            if (recent.isNotEmpty) const SizedBox(height: 22),
            // Schnell anlegen
            Row(children: [
              _Create(
                  icon: Icons.menu_book_rounded,
                  label: 'Neues Notizbuch',
                  onTap: () => createNotebook(context)),
              _Create(
                  icon: Icons.bubble_chart_rounded,
                  label: 'Canvas',
                  onTap: () => createBoard(context)),
              _Create(
                  icon: Icons.picture_as_pdf_rounded,
                  label: 'PDF',
                  onTap: () => importDocument(context)),
              _Create(
                  icon: Icons.hub_rounded,
                  label: 'Wissen',
                  onTap: () => createKnowledge(context)),
            ]),
            const SizedBox(height: 30),
            if (pinned.isNotEmpty) ...[
              const SectionHeader('Angeheftet'),
              _Shelf(objects: pinned),
              const SizedBox(height: 24),
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
              Text('Noch nichts geöffnet – leg oben dein erstes Notizbuch an.',
                  style: TextStyle(color: mf.textMuted))
            else
              _Shelf(objects: recent),
            const SizedBox(height: 24),
            const SectionHeader('Lernen'),
            _StudyRow(
              due: stats.due,
              total: stats.total,
              progress: stats.progress,
              onOpen: () => onNavigate(Section.study),
            ),
          ],
        );
      },
    );
  }
}

/// Großes „Weitermachen“ mit dem zuletzt geöffneten Inhalt.
class _Continue extends StatelessWidget {
  const _Continue({required this.object});
  final MfObject object;

  @override
  Widget build(BuildContext context) {
    final mf = context.mf;
    final o = object;
    final when = o.openedAt ?? o.updatedAt;
    return HoverLift(
      lift: 2,
      child: Material(
        color: mf.surface,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: mf.border)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => openObject(context, o),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              SizedBox(
                width: 64,
                height: 84,
                child: o.type == ObjectType.notebook
                    ? NotebookCover(
                        color: Color(o.coverColor),
                        style: o.coverStyle,
                        title: '',
                        compact: true)
                    : Container(
                        decoration: BoxDecoration(
                          color: mf.accentSoft,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(iconFor(o.type), color: mf.accent),
                      ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('WEITERMACHEN',
                        style: TextStyle(
                            fontSize: 11,
                            letterSpacing: 1.2,
                            fontWeight: FontWeight.w700,
                            color: mf.accent)),
                    const SizedBox(height: 4),
                    Text(o.displayTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w700,
                            color: mf.text)),
                    const SizedBox(height: 2),
                    Text('${typeLabel(o.type)} · ${relativeTime(when)}',
                        style: TextStyle(fontSize: 13, color: mf.textMuted)),
                  ],
                ),
              ),
              Icon(Icons.arrow_forward_rounded, color: mf.textMuted),
            ]),
          ),
        ),
      ),
    );
  }
}

class _Create extends StatelessWidget {
  const _Create({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final mf = context.mf;
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 5),
        child: Material(
          color: mf.surface,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: mf.border)),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
              child: Column(children: [
                Icon(icon, color: mf.accent, size: 24),
                const SizedBox(height: 6),
                Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: mf.text)),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// Waagerechtes Regal mit Karten (wie die Bibliothek in Goodnotes).
class _Shelf extends StatelessWidget {
  const _Shelf({required this.objects});
  final List<MfObject> objects;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 250,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: objects.length,
        separatorBuilder: (_, __) => const SizedBox(width: 18),
        itemBuilder: (_, i) =>
            SizedBox(width: 170, child: ObjectCard(object: objects[i])),
      ),
    );
  }
}

class _StudyRow extends StatelessWidget {
  const _StudyRow(
      {required this.due,
      required this.total,
      required this.progress,
      required this.onOpen});

  final int due;
  final int total;
  final double progress;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final mf = context.mf;
    return Material(
      color: mf.surface,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: mf.border)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(children: [
          ProgressRing(value: progress, size: 56),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              total == 0
                  ? 'Noch keine Karteikarten.'
                  : due == 0
                      ? 'Alles gelernt – stark!'
                      : '$due ${due == 1 ? 'Karte ist' : 'Karten sind'} fällig',
              style: TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w600, color: mf.text),
            ),
          ),
          FilledButton(
            onPressed: due > 0 ? () => startReview(context) : onOpen,
            child: Text(due > 0 ? 'Lernen' : 'Öffnen'),
          ),
        ]),
      ),
    );
  }
}
