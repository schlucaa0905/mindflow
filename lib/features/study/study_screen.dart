import 'package:flutter/material.dart';

import '../../app/navigation.dart';
import '../../app/services.dart';
import '../../app/theme.dart';
import '../../data/models.dart';
import '../../data/study_repository.dart';
import '../../ui/clean_menu.dart';
import '../../ui/futuristic.dart';
import '../../ui/widgets.dart';
import '../common/object_picker.dart';
import 'card_editor.dart';
import 'quiz_screen.dart';
import 'review_screen.dart';

/// STUDY – Lernbereich mit Karteikarten und Wiederholungsplan.
class StudyScreen extends StatelessWidget {
  const StudyScreen({super.key});

  Future<void> _newCard(BuildContext context) async {
    final entry = await pickObject(context,
        title: 'Zu welchem Wissenseintrag? (Abbrechen = freie Karte)',
        types: {ObjectType.knowledge});
    if (!context.mounted) return;
    await editFlashcard(context, entryId: entry?.id);
  }

  @override
  Widget build(BuildContext context) {
    final s = Services.of(context);
    final mf = context.mf;
    return ListenableBuilder(
      listenable: s.objects,
      builder: (context, _) {
        final now = DateTime.now();
        final stats = s.study.stats(now);
        final decks = s.study.decks();
        final difficult = s.study
            .allCards()
            .where((c) => c.schedule.isDifficult)
            .take(8)
            .toList();
        return ListView(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 48),
          children: [
            PageHeader(
              title: 'Lernen',
              subtitle: 'Karteikarten mit klugem Wiederholungsplan',
              actions: [
                OutlinedButton.icon(
                  onPressed: () => startQuiz(context),
                  icon: const Icon(Icons.quiz_outlined, size: 18),
                  label: const Text('Quiz'),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: () => _newCard(context),
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('Karte'),
                ),
              ],
            ),
            GlassPanel(
              radius: 26,
              padding: const EdgeInsets.all(24),
              child: Wrap(
                spacing: 24,
                runSpacing: 18,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  ProgressRing(value: stats.progress, size: 96),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 360),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        GradientText(
                          stats.due == 0
                              ? (stats.total == 0
                                  ? 'Los geht’s'
                                  : 'Alles erledigt')
                              : '${stats.due} fällig',
                          style: const TextStyle(
                              fontSize: 30,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -1),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          stats.total == 0
                              ? 'Erstelle Karten – am schnellsten direkt aus '
                                  'einem Wissenseintrag („Karten aus dem Text“).'
                              : 'Gesamt ${stats.total} · neu ${stats.fresh} · '
                                  'sicher ${stats.learned} · '
                                  'schwierig ${stats.difficult}',
                          style: TextStyle(color: mf.textMuted, height: 1.4),
                        ),
                      ],
                    ),
                  ),
                  GlowButton(
                    label: stats.due > 0 ? 'Lernen starten' : 'Neue Karte',
                    icon: stats.due > 0
                        ? Icons.play_arrow_rounded
                        : Icons.add_rounded,
                    onPressed: stats.due > 0
                        ? () => startReview(context)
                        : () => _newCard(context),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 30),
            const SectionHeader('Lernsets'),
            if (decks.isEmpty)
              const EmptyState(
                icon: Icons.style_outlined,
                title: 'Noch keine Lernsets',
                message:
                    'Jeder Wissenseintrag mit Karteikarten wird automatisch '
                    'zu einem Lernset. Öffne einen Eintrag und tippe auf '
                    '„Karte hinzufügen“.',
              )
            else
              for (final d in decks) _DeckTile(deck: d, now: now),
            if (difficult.isNotEmpty) ...[
              const SizedBox(height: 30),
              const SectionHeader('Schwierige Karten'),
              for (final c in difficult) _CardTile(card: c),
            ],
          ],
        );
      },
    );
  }
}

class _DeckTile extends StatelessWidget {
  const _DeckTile({required this.deck, required this.now});

  final StudyDeck deck;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final mf = context.mf;
    final due = deck.due(now);
    final learned = deck.cards
        .where((c) => c.schedule.reps > 0 && c.schedule.interval >= 3)
        .length;
    final share = deck.cards.isEmpty ? 0.0 : learned / deck.cards.length;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: HoverLift(
        lift: 2,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: deck.entry == null
              ? null
              : () => openObject(context, deck.entry!),
          child: GlassPanel(
            radius: 18,
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
            child: Row(
              children: [
                ProgressRing(value: share, size: 46),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(deck.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                              color: mf.text)),
                      const SizedBox(height: 3),
                      Text(
                        '${deck.cards.length} '
                        '${deck.cards.length == 1 ? 'Karte' : 'Karten'}'
                        '${deck.difficult > 0 ? ' · ${deck.difficult} schwierig' : ''}',
                        style: TextStyle(fontSize: 12.5, color: mf.textMuted),
                      ),
                    ],
                  ),
                ),
                if (due > 0) ...[
                  StatusPill('$due fällig'),
                  const SizedBox(width: 10),
                  GlowButton(
                    label: 'Lernen',
                    compact: true,
                    onPressed: () =>
                        startReview(context, entryId: deck.entry?.id),
                  ),
                ] else
                  StatusPill('erledigt', color: mf.success),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Eine Karte in Listen (Lernbereich und Wissenseintrag).
class FlashcardTile extends StatelessWidget {
  const FlashcardTile({super.key, required this.card});

  final Flashcard card;

  @override
  Widget build(BuildContext context) => _CardTile(card: card);
}

class _CardTile extends StatelessWidget {
  const _CardTile({required this.card});

  final Flashcard card;

  String _state(DateTime now) {
    final s = card.schedule;
    if (s.isNew) return 'neu';
    final due = s.due;
    if (due == null || !due.isAfter(now)) return 'fällig';
    final d = due.difference(now);
    if (d.inDays >= 1) return 'in ${d.inDays} ${d.inDays == 1 ? 'Tag' : 'Tagen'}';
    if (d.inHours >= 1) return 'in ${d.inHours} Std.';
    return 'gleich';
  }

  @override
  Widget build(BuildContext context) {
    final mf = context.mf;
    final study = Services.of(context).study;
    final state = _state(DateTime.now());
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GlassPanel(
        radius: 16,
        padding: const EdgeInsets.fromLTRB(16, 12, 6, 12),
        child: Row(
          children: [
            Container(
              width: 4,
              height: 36,
              decoration: BoxDecoration(
                gradient: card.schedule.isDifficult
                    ? LinearGradient(colors: [mf.danger, mf.danger])
                    : mf.gradient,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(card.front,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontWeight: FontWeight.w600, color: mf.text)),
                  const SizedBox(height: 2),
                  Text(card.back.replaceAll('\n', ' '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12.5, color: mf.textMuted)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(state, style: TextStyle(fontSize: 12, color: mf.textMuted)),
            CleanMenuButton(
              size: 34,
              iconColor: mf.textMuted,
              entries: const [
                CleanMenuEntry('edit', 'Bearbeiten', icon: Icons.edit_outlined),
                CleanMenuEntry('reset', 'Lernstand zurücksetzen',
                    icon: Icons.restart_alt_rounded),
                CleanMenuEntry.divider(),
                CleanMenuEntry('delete', 'Löschen',
                    icon: Icons.delete_outline, destructive: true),
              ],
              onSelected: (v) {
                switch (v) {
                  case 'edit':
                    editFlashcard(context, card: card);
                  case 'reset':
                    study.reset(card.id);
                  case 'delete':
                    study.delete(card.id);
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}
