import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/services.dart';
import '../../app/theme.dart';
import '../../data/srs.dart';
import '../../data/study_repository.dart';
import '../../ui/futuristic.dart';

/// Startet eine Lernrunde mit allen fälligen Karten (optional nur die
/// eines Wissenseintrags). Gibt es nichts zu tun, kommt ein Hinweis.
Future<void> startReview(BuildContext context, {String? entryId}) async {
  final study = Services.of(context).study;
  final due = study.dueCards(DateTime.now(), entryId: entryId);
  if (due.isEmpty) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(const SnackBar(
        content: Text('Gerade ist keine Karte fällig – sehr gut!')));
    return;
  }
  await Navigator.of(context).push(MaterialPageRoute<void>(
    fullscreenDialog: true,
    builder: (_) => ReviewScreen(cardIds: [for (final c in due) c.id]),
  ));
}

/// Lernmodus: Frage ansehen, umdrehen, ehrlich bewerten.
/// „Nochmal“ legt die Karte ans Ende der Runde.
class ReviewScreen extends StatefulWidget {
  const ReviewScreen({super.key, required this.cardIds});

  final List<String> cardIds;

  @override
  State<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends State<ReviewScreen> {
  late final StudyRepository _study = Services.of(context).study;
  late final List<String> _queue = List.of(widget.cardIds);
  int _pos = 0;
  bool _revealed = false;
  int _answered = 0;
  final Map<Rating, int> _tally = {for (final r in Rating.values) r: 0};
  final FocusNode _focus = FocusNode(debugLabel: 'review');

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  Flashcard? get _current {
    while (_pos < _queue.length) {
      final c = _study.card(_queue[_pos]);
      if (c != null && c.object.deletedAt == null) return c;
      _pos++; // gelöschte Karte überspringen
    }
    return null;
  }

  void _reveal() {
    if (_current == null) return;
    setState(() => _revealed = true);
  }

  void _rate(Rating r) {
    final card = _current;
    if (card == null || !_revealed) return;
    HapticFeedback.selectionClick().ignore();
    _study.answer(card.id, r);
    setState(() {
      _answered++;
      _tally[r] = _tally[r]! + 1;
      if (r == Rating.again) _queue.add(card.id);
      _pos++;
      _revealed = false;
    });
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    final k = e.logicalKey;
    if (!_revealed &&
        (k == LogicalKeyboardKey.space || k == LogicalKeyboardKey.enter)) {
      _reveal();
      return KeyEventResult.handled;
    }
    if (_revealed) {
      final map = {
        LogicalKeyboardKey.digit1: Rating.again,
        LogicalKeyboardKey.digit2: Rating.hard,
        LogicalKeyboardKey.digit3: Rating.good,
        LogicalKeyboardKey.digit4: Rating.easy,
        LogicalKeyboardKey.space: Rating.good,
        LogicalKeyboardKey.enter: Rating.good,
      };
      final r = map[k];
      if (r != null) {
        _rate(r);
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final mf = context.mf;
    final card = _current;
    final remaining = card == null ? 0 : _queue.length - _pos;
    final total = _answered + remaining;
    final progress = total == 0 ? 1.0 : _answered / total;
    return Focus(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: _onKey,
      child: Scaffold(
        backgroundColor: mf.background,
        body: AuroraBackground(
          intensity: 0.8,
          child: SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 20, 8),
                  child: Row(
                    children: [
                      IconButton(
                        tooltip: 'Beenden',
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => Navigator.of(context).maybePop(),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: Stack(
                            children: [
                              Container(height: 6, color: mf.border),
                              AnimatedFractionallySizedBox(
                                duration: const Duration(milliseconds: 300),
                                curve: Curves.easeOutCubic,
                                alignment: Alignment.centerLeft,
                                widthFactor: progress.clamp(0.0, 1.0),
                                child: Container(
                                  height: 6,
                                  decoration:
                                      BoxDecoration(gradient: mf.gradient),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Text(card == null ? 'Fertig' : 'Noch $remaining',
                          style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: mf.textMuted)),
                    ],
                  ),
                ),
                Expanded(
                  child: card == null
                      ? _Done(answered: _answered, tally: _tally)
                      : _cardView(context, card),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _cardView(BuildContext context, Flashcard card) {
    final mf = context.mf;
    final now = DateTime.now();
    final entry = card.entryId == null
        ? null
        : Services.of(context).objects.get(card.entryId!);
    return Column(
      children: [
        Expanded(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: GestureDetector(
                  onTap: _revealed ? null : _reveal,
                  child: _FlipCard(
                    key: ValueKey('${card.id}-$_answered'),
                    revealed: _revealed,
                    label: entry?.displayTitle,
                    front: card.front,
                    back: card.back,
                  ),
                ),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            child: !_revealed
                ? SizedBox(
                    key: const ValueKey('show'),
                    width: 320,
                    child: GlowButton(
                      label: 'Antwort zeigen',
                      icon: Icons.flip_rounded,
                      expand: true,
                      onPressed: _reveal,
                    ),
                  )
                : Wrap(
                    key: const ValueKey('rate'),
                    alignment: WrapAlignment.center,
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      for (final r in Rating.values)
                        _RateButton(
                          rating: r,
                          when: previewLabel(card.schedule, r, now),
                          color: switch (r) {
                            Rating.again => mf.danger,
                            Rating.hard => const Color(0xFFF59E0B),
                            Rating.good => mf.success,
                            Rating.easy => mf.accent2,
                          },
                          onTap: () => _rate(r),
                        ),
                    ],
                  ),
          ),
        ),
      ],
    );
  }
}

/// Karte mit 3D-Umdreh-Animation.
class _FlipCard extends StatelessWidget {
  const _FlipCard({
    super.key,
    required this.revealed,
    required this.front,
    required this.back,
    this.label,
  });

  final bool revealed;
  final String front;
  final String back;
  final String? label;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(end: revealed ? 1 : 0),
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeInOutCubic,
      builder: (context, t, _) {
        final angle = t * math.pi;
        final showBack = t > 0.5;
        return Transform(
          alignment: Alignment.center,
          transform: Matrix4.identity()
            ..setEntry(3, 2, 0.0012)
            ..rotateY(angle),
          child: showBack
              ? Transform(
                  alignment: Alignment.center,
                  transform: Matrix4.identity()..rotateY(math.pi),
                  child: _face(context, isBack: true),
                )
              : _face(context, isBack: false),
        );
      },
    );
  }

  Widget _face(BuildContext context, {required bool isBack}) {
    final mf = context.mf;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 280),
      child: GlassPanel(
        radius: 28,
        glow: isBack,
        padding: const EdgeInsets.fromLTRB(28, 22, 28, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                StatusPill(isBack ? 'Antwort' : 'Frage',
                    color: isBack ? mf.accent2 : mf.accent),
                const Spacer(),
                if (label != null)
                  Flexible(
                    child: Text(label!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: mf.textMuted)),
                  ),
              ],
            ),
            const SizedBox(height: 28),
            Text(
              front,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: isBack ? 18 : 26,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.4,
                height: 1.25,
                color: isBack ? mf.textMuted : mf.text,
              ),
            ),
            if (isBack) ...[
              const SizedBox(height: 18),
              Container(
                height: 1,
                margin: const EdgeInsets.symmetric(horizontal: 40),
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [
                    mf.accent.withValues(alpha: 0),
                    mf.accent,
                    mf.accent2,
                    mf.accent2.withValues(alpha: 0),
                  ]),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                back,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 22, height: 1.4, color: mf.text),
              ),
            ] else ...[
              const SizedBox(height: 28),
              Text('Antippen zum Umdrehen',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: mf.textMuted)),
            ],
          ],
        ),
      ),
    );
  }
}

class _RateButton extends StatelessWidget {
  const _RateButton({
    required this.rating,
    required this.when,
    required this.color,
    required this.onTap,
  });

  final Rating rating;
  final String when;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final mf = context.mf;
    return HoverLift(
      lift: 3,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          width: 132,
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: color.withValues(alpha: 0.5)),
            boxShadow: [
              BoxShadow(
                  color: color.withValues(alpha: 0.18),
                  blurRadius: 18,
                  spreadRadius: -6),
            ],
          ),
          child: Column(
            children: [
              Text(rating.label,
                  style: TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 15, color: color)),
              const SizedBox(height: 2),
              Text(when, style: TextStyle(fontSize: 12, color: mf.textMuted)),
            ],
          ),
        ),
      ),
    );
  }
}

class _Done extends StatelessWidget {
  const _Done({required this.answered, required this.tally});

  final int answered;
  final Map<Rating, int> tally;

  @override
  Widget build(BuildContext context) {
    final mf = context.mf;
    final known = (tally[Rating.good] ?? 0) + (tally[Rating.easy] ?? 0);
    final quote = answered == 0 ? 0.0 : known / answered;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: GlassPanel(
            radius: 28,
            glow: true,
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ProgressRing(value: quote, size: 110),
                const SizedBox(height: 20),
                const GradientText('Runde geschafft!',
                    style:
                        TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                Text(
                  '$answered ${answered == 1 ? 'Antwort' : 'Antworten'} · '
                  '$known gewusst',
                  style: TextStyle(color: mf.textMuted),
                ),
                const SizedBox(height: 22),
                GlowButton(
                  label: 'Zurück',
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
