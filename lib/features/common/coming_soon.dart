import 'package:flutter/material.dart';

import '../../app/sections.dart';
import '../../app/theme.dart';
import '../../ui/widgets.dart';

/// Platzhalter für Bereiche, die in einer späteren Phase kommen.
class ComingSoonScreen extends StatelessWidget {
  const ComingSoonScreen({super.key, required this.section});

  final Section section;

  static const _plans = {
    Section.documents: [
      'PDFs importieren und ansehen',
      'Mit dem Apple Pencil hineinschreiben und markieren',
      'Mit Wissenseinträgen und dem Canvas verknüpfen',
      'Mit Anmerkungen exportieren',
    ],
    Section.knowledge: [
      'Themen und Unterthemen, z. B. Informatik → Netzwerktechnik → DHCP',
      'Kategorien, Tags und Beziehungen zwischen Einträgen',
      'Aus einer Notizbuchseite einen Wissenseintrag erstellen',
      'Einträge auf den Canvas ziehen',
    ],
    Section.study: [
      'Karteikarten direkt aus Wissenseinträgen',
      'Lernsets, Quizze und Wiederholungen nach Plan',
      'Übersicht über schwierige Themen',
    ],
  };

  @override
  Widget build(BuildContext context) {
    final mf = context.mf;
    final plan = _plans[section] ?? const <String>[];
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
      children: [
        PageHeader(
          title: section.label,
          subtitle: 'Kommt in Phase ${section.comingInPhase}',
        ),
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: mf.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: mf.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(section.icon, color: mf.accent),
                  const SizedBox(width: 12),
                  Text('Was hier entsteht',
                      style: TextStyle(
                          fontWeight: FontWeight.w600, color: mf.text)),
                ],
              ),
              const SizedBox(height: 16),
              for (final p in plan)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 7),
                        child: Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                              color: mf.accent, shape: BoxShape.circle),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                          child: Text(p,
                              style: TextStyle(
                                  color: mf.textMuted, height: 1.5))),
                    ],
                  ),
                ),
              const SizedBox(height: 8),
              Text(
                'Die Datenbank ist dafür schon vorbereitet: Alles bekommt eine '
                'feste ID und kann später mit allem verknüpft werden.',
                style: TextStyle(color: mf.textMuted, fontSize: 13),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
