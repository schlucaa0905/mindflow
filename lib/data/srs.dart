/// Wiederholungsplan für Karteikarten (angelehnt an SM-2, den Algorithmus
/// hinter Anki). Reine Rechenlogik ohne Datenbank – deshalb gut testbar.
library;

import 'dart:math' as math;

/// Höchstens 100 Jahre Abstand.
const _maxDays = 36500;

int _days(num raw, int atLeast) =>
    math.min(_maxDays, math.max(atLeast, raw.round()));

/// Wie gut wusste man die Antwort?
enum Rating {
  again('Nochmal'),
  hard('Schwer'),
  good('Gut'),
  easy('Leicht');

  const Rating(this.label);
  final String label;
}

/// Lernstand einer Karte.
class CardSchedule {
  const CardSchedule({
    this.ease = 2.5,
    this.interval = 0,
    this.reps = 0,
    this.lapses = 0,
    this.due,
  });

  /// Leichtigkeitsfaktor (1,3 … ca. 3,5). Höher = Abstände wachsen schneller.
  final double ease;

  /// Aktueller Abstand in Tagen (0 = noch in der Lernphase).
  final int interval;

  /// Wie oft in Folge richtig beantwortet.
  final int reps;

  /// Wie oft insgesamt vergessen.
  final int lapses;

  /// Wann die Karte wieder dran ist. null = neu, sofort fällig.
  final DateTime? due;

  bool get isNew => due == null && reps == 0;

  bool isDue(DateTime now) => due == null || !due!.isAfter(now);

  /// Gilt als „schwierig“, wenn sie öfter vergessen wurde oder der
  /// Leichtigkeitsfaktor stark gesunken ist.
  bool get isDifficult => lapses >= 2 || ease < 2.0;

  static const minEase = 1.3;

  Map<String, dynamic> toJson() => {
        'ease': ease,
        'interval': interval,
        'reps': reps,
        'lapses': lapses,
        'due': due?.millisecondsSinceEpoch,
      };

  factory CardSchedule.fromJson(Map<String, dynamic> j) {
    double d(Object? v, double f) => v is num ? v.toDouble() : f;
    int i(Object? v) => v is num ? v.toInt() : 0;
    final dueRaw = j['due'];
    return CardSchedule(
      ease: d(j['ease'], 2.5).clamp(minEase, 5.0).toDouble(),
      interval: i(j['interval']).clamp(0, _maxDays).toInt(),
      reps: i(j['reps']).clamp(0, 1000000).toInt(),
      lapses: i(j['lapses']).clamp(0, 1000000).toInt(),
      due: dueRaw is num
          ? DateTime.fromMillisecondsSinceEpoch(dueRaw.toInt())
          : null,
    );
  }
}

/// Berechnet den neuen Lernstand nach einer Antwort.
CardSchedule schedule(CardSchedule s, Rating r, DateTime now) {
  switch (r) {
    case Rating.again:
      // Vergessen: kurz danach noch einmal, Abstand von vorn.
      return CardSchedule(
        ease: (s.ease - 0.2).clamp(CardSchedule.minEase, 5.0).toDouble(),
        interval: 0,
        reps: 0,
        lapses: s.reps > 0 || s.interval > 0 ? s.lapses + 1 : s.lapses,
        due: now.add(const Duration(minutes: 1)),
      );
    case Rating.hard:
      final days =
          s.interval <= 0 ? 1 : _days(s.interval * 1.2, s.interval + 1);
      return CardSchedule(
        ease: (s.ease - 0.15).clamp(CardSchedule.minEase, 5.0).toDouble(),
        interval: days,
        reps: s.reps + 1,
        lapses: s.lapses,
        due: now.add(Duration(days: days)),
      );
    case Rating.good:
      final days = s.reps == 0
          ? 1
          : s.reps == 1
              ? 3
              : _days(s.interval * s.ease, s.interval + 1);
      return CardSchedule(
        ease: s.ease,
        interval: days,
        reps: s.reps + 1,
        lapses: s.lapses,
        due: now.add(Duration(days: days)),
      );
    case Rating.easy:
      final days = s.reps == 0
          ? 4
          : _days(math.max(1, s.interval) * s.ease * 1.3, s.interval + 2);
      return CardSchedule(
        ease: (s.ease + 0.15).clamp(CardSchedule.minEase, 5.0).toDouble(),
        interval: days,
        reps: s.reps + 1,
        lapses: s.lapses,
        due: now.add(Duration(days: days)),
      );
  }
}

/// Kurzer Text, wann die Karte bei dieser Antwort wiederkommt.
String previewLabel(CardSchedule s, Rating r, DateTime now) {
  final next = schedule(s, r, now);
  final d = next.due!.difference(now);
  if (d.inDays >= 365) return '${(d.inDays / 365).toStringAsFixed(1)} J.';
  if (d.inDays >= 30) return '${(d.inDays / 30).round()} Mon.';
  if (d.inDays >= 1) return '${d.inDays} T.';
  if (d.inHours >= 1) return '${d.inHours} Std.';
  return '${d.inMinutes.clamp(1, 59)} Min.';
}
