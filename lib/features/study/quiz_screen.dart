import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/services.dart';
import '../../app/theme.dart';
import '../../data/study_repository.dart';
import '../../storage/image_store.dart';
import '../../ui/futuristic.dart';

/// Eine Quizfrage: Karte + 4 Antworten, eine davon richtig.
class QuizQuestion {
  QuizQuestion(this.card, this.options, this.correct);
  final Flashcard card;
  final List<String> options;
  final int correct;
}

/// Baut ein Multiple-Choice-Quiz: Falsche Antworten sind die Rückseiten
/// anderer Karten. Braucht mindestens 4 verschiedene Rückseiten.
List<QuizQuestion> buildQuiz(List<Flashcard> cards, math.Random rnd) {
  final backs = {for (final c in cards) c.back.trim()}..remove('');
  if (backs.length < 4) return const [];
  final out = <QuizQuestion>[];
  for (final c in [...cards]..shuffle(rnd)) {
    final right = c.back.trim();
    if (right.isEmpty) continue;
    final wrong = (backs.toList()..remove(right))..shuffle(rnd);
    final options = [right, ...wrong.take(3)]..shuffle(rnd);
    out.add(QuizQuestion(c, options, options.indexOf(right)));
  }
  return out;
}

Future<void> startQuiz(BuildContext context, {String? entryId}) async {
  final study = Services.of(context).study;
  final cards = entryId == null ? study.allCards() : study.cardsOf(entryId);
  final quiz = buildQuiz(cards, math.Random());
  if (quiz.isEmpty) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(const SnackBar(
        content: Text('Für ein Quiz braucht es mindestens 4 Karten '
            'mit verschiedenen Antworten.')));
    return;
  }
  await Navigator.of(context).push(MaterialPageRoute<void>(
      fullscreenDialog: true, builder: (_) => QuizScreen(questions: quiz)));
}

/// Quiz-Modus: Frage, vier Antworten, sofort Rückmeldung.
class QuizScreen extends StatefulWidget {
  const QuizScreen({super.key, required this.questions});
  final List<QuizQuestion> questions;

  @override
  State<QuizScreen> createState() => _QuizScreenState();
}

class _QuizScreenState extends State<QuizScreen> {
  int _i = 0;
  int _right = 0;
  int? _picked;

  void _pick(int k) {
    if (_picked != null) return;
    setState(() {
      _picked = k;
      if (k == widget.questions[_i].correct) _right++;
    });
  }

  void _next() => setState(() {
        _i++;
        _picked = null;
      });

  @override
  Widget build(BuildContext context) {
    final mf = context.mf;
    final n = widget.questions.length;
    final done = _i >= n;
    return Scaffold(
      appBar: AppBar(
        title: Text(done ? 'Quiz' : 'Frage ${_i + 1} von $n'),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: done
                ? [
                    const SizedBox(height: 40),
                    Center(child: ProgressRing(value: _right / n, size: 120)),
                    const SizedBox(height: 20),
                    Text('$_right von $n richtig',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w700,
                            color: mf.text)),
                    const SizedBox(height: 24),
                    Center(
                      child: GlowButton(
                          label: 'Fertig',
                          onPressed: () => Navigator.of(context).maybePop()),
                    ),
                  ]
                : _question(context, widget.questions[_i]),
          ),
        ),
      ),
    );
  }

  List<Widget> _question(BuildContext context, QuizQuestion q) {
    final mf = context.mf;
    return [
      if (q.card.image != null) StoredImage(q.card.image!, height: 180),
      if (q.card.front.isNotEmpty)
        Text(q.card.front,
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 24, fontWeight: FontWeight.w700, color: mf.text)),
      const SizedBox(height: 24),
      for (var k = 0; k < q.options.length; k++)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Material(
            color: _picked == null
                ? mf.surface
                : k == q.correct
                    ? mf.success.withValues(alpha: 0.22)
                    : k == _picked
                        ? mf.danger.withValues(alpha: 0.22)
                        : mf.surface,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(color: mf.border)),
            child: ListTile(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
              title: Text(q.options[k], style: TextStyle(color: mf.text)),
              trailing: _picked == null
                  ? null
                  : k == q.correct
                      ? Icon(Icons.check_circle, color: mf.success)
                      : k == _picked
                          ? Icon(Icons.cancel, color: mf.danger)
                          : null,
              onTap: () => _pick(k),
            ),
          ),
        ),
      if (_picked != null) ...[
        const SizedBox(height: 12),
        Center(child: GlowButton(label: 'Weiter', onPressed: _next)),
      ],
    ];
  }
}
