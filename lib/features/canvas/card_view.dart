import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../data/models.dart';

/// Kartenfarben auf dem Canvas (null = neutral).
const kCardColors = <int>[
  0xFF8B5CF6, // Violett
  0xFF3B82F6, // Blau
  0xFF22D3EE, // Cyan
  0xFF22C55E, // Grün
  0xFFFACC15, // Gelb
  0xFFF97316, // Orange
  0xFFEC4899, // Pink
  0xFFEF4444, // Rot
  0xFF94A3B8, // Grau
];

/// Farben, mit denen eine Karte gezeichnet wird.
class CardColors {
  const CardColors(
      {required this.fill, required this.border, required this.text});

  final Color fill;
  final Color border;
  final Color text;

  static CardColors of(CanvasNode n, PaperStyle paper) {
    final dark = paper.sheet.computeLuminance() < 0.3;
    final base = dark ? const Color(0xFF1E1E29) : Colors.white;
    final ink = dark ? const Color(0xFFF2F2F7) : const Color(0xFF16161D);
    final c = n.color == null ? null : Color(n.color!);
    if (n.kind == CardKind.heading) {
      return CardColors(
        fill: Colors.transparent,
        border: Colors.transparent,
        text: c == null
            ? ink
            : Color.lerp(c, ink, dark ? 0.1 : 0.25)!,
      );
    }
    if (c == null) {
      return CardColors(
        fill: n.kind == CardKind.sticky
            ? (dark ? const Color(0xFF2A2A38) : const Color(0xFFF4F4F8))
            : base,
        border: paper.line,
        text: ink,
      );
    }
    final strength = switch (n.kind) {
      CardKind.sticky => dark ? 0.55 : 0.45,
      CardKind.circle || CardKind.pill => dark ? 0.38 : 0.26,
      _ => dark ? 0.24 : 0.16,
    };
    final fill = Color.lerp(base, c, strength)!;
    // Auf kräftig gefärbten Zetteln muss die Schrift lesbar bleiben.
    final text = fill.computeLuminance() > 0.45
        ? const Color(0xFF16161D)
        : const Color(0xFFF7F7FB);
    return CardColors(
      fill: fill,
      border: c.withValues(alpha: dark ? 0.75 : 0.6),
      text: text,
    );
  }
}

/// Eine Zeile einer Karte: normaler Text oder Aufgabe ([ ] / [x]).
class CardLine {
  const CardLine(this.text, {this.task = false, this.done = false});

  final String text;
  final bool task;
  final bool done;

  static final _task = RegExp(r'^\s*\[( |x|X)\]\s?');

  static List<CardLine> parse(String text) => [
        for (final line in text.split('\n'))
          if (_task.hasMatch(line))
            CardLine(line.replaceFirst(_task, ''),
                task: true,
                done: _task.firstMatch(line)!.group(1)!.toLowerCase() == 'x')
          else
            CardLine(line)
      ];

  static bool hasTasks(String text) =>
      text.split('\n').any((l) => _task.hasMatch(l));

  /// Hakt Aufgabe Nr. [index] (Zeilennummer) ab oder wieder auf.
  static String toggle(String text, int index) {
    final lines = text.split('\n');
    if (index < 0 || index >= lines.length) return text;
    final m = _task.firstMatch(lines[index]);
    if (m == null) return text;
    final done = m.group(1)!.toLowerCase() == 'x';
    lines[index] =
        lines[index].replaceFirst(_task, done ? '[ ] ' : '[x] ');
    return lines.join('\n');
  }

  /// Macht aus allen Zeilen Aufgaben – oder wieder normalen Text.
  static String toggleAll(String text) {
    final lines = text.split('\n');
    final allTasks =
        lines.where((l) => l.trim().isNotEmpty).every(_task.hasMatch);
    return [
      for (final l in lines)
        if (l.trim().isEmpty)
          l
        else if (allTasks)
          l.replaceFirst(_task, '')
        else if (_task.hasMatch(l))
          l
        else
          '[ ] $l'
    ].join('\n');
  }
}

/// Innenabstand einer Karte je nach Art.
EdgeInsets cardPadding(CardKind k) => switch (k) {
      CardKind.heading => const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      CardKind.pill => const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
      CardKind.circle => const EdgeInsets.all(26),
      CardKind.sticky => const EdgeInsets.fromLTRB(16, 18, 16, 16),
      CardKind.card => const EdgeInsets.fromLTRB(16, 14, 16, 14),
    };

TextStyle cardTextStyle(CanvasNode n, Color color) => TextStyle(
      fontSize: n.textSize.size,
      height: 1.35,
      color: color,
      fontWeight: n.kind == CardKind.heading
          ? FontWeight.w800
          : (n.bold ? FontWeight.w700 : FontWeight.w500),
      letterSpacing: n.kind == CardKind.heading ? -0.6 : 0,
    );

/// Höhe, die der Text einer Karte bei ihrer Breite braucht.
double measureCardHeight(CanvasNode n) {
  final pad = cardPadding(n.kind);
  final lines = CardLine.parse(n.text.isEmpty ? ' ' : n.text);
  var h = 0.0;
  final width = math.max(20.0, n.w - pad.horizontal);
  for (final l in lines) {
    final tp = TextPainter(
      text: TextSpan(
          text: l.text.isEmpty ? ' ' : l.text,
          style: cardTextStyle(n, Colors.black)),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: math.max(10.0, l.task ? width - 28 : width));
    h += math.max(tp.height, l.task ? 24.0 : 0.0);
    tp.dispose();
  }
  final min = switch (n.kind) {
    CardKind.heading => 40.0,
    CardKind.pill => 52.0,
    CardKind.circle => n.w * 0.6,
    CardKind.sticky => n.w * 0.75,
    CardKind.card => 64.0,
  };
  return math.min(1600, math.max(min, h + pad.vertical + 2));
}

/// So sieht eine Karte aus. Gezeichnet in Welt-Größe; die Ansicht
/// skaliert sie mit dem Zoom.
class CanvasCardView extends StatelessWidget {
  const CanvasCardView({
    super.key,
    required this.node,
    required this.paper,
    required this.selected,
    this.editor,
    this.reference,
    this.onToggleTask,
  });

  final CanvasNode node;
  final PaperStyle paper;
  final bool selected;

  /// Eingabefeld, wenn die Karte gerade bearbeitet wird.
  final Widget? editor;

  /// Verweis-Ziel (Wissenseintrag, PDF …) – ändert die Darstellung.
  final ({IconData icon, String type, String title})? reference;
  final ValueChanged<int>? onToggleTask;

  @override
  Widget build(BuildContext context) {
    final mf = context.mf;
    final n = node;
    final colors = CardColors.of(n, paper);
    final style = cardTextStyle(n, colors.text);
    final align = n.centered ? TextAlign.center : TextAlign.left;

    Widget content;
    if (editor != null) {
      content = editor!;
    } else if (reference != null) {
      content = Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [
                mf.accent.withValues(alpha: 0.35),
                mf.accent2.withValues(alpha: 0.2),
              ]),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(reference!.icon, size: 18, color: colors.text),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(reference!.type.toUpperCase(),
                    style: TextStyle(
                        fontSize: 10,
                        letterSpacing: 1.2,
                        fontWeight: FontWeight.w700,
                        color: colors.text.withValues(alpha: 0.55))),
                const SizedBox(height: 2),
                Text(reference!.title,
                    overflow: TextOverflow.fade,
                    style: style.copyWith(fontWeight: FontWeight.w700)),
              ],
            ),
          ),
          Icon(Icons.north_east_rounded,
              size: 16, color: colors.text.withValues(alpha: 0.5)),
        ],
      );
    } else if (n.text.isEmpty) {
      content = Text('Doppeltippen zum Schreiben',
          textAlign: align,
          style: style.copyWith(color: colors.text.withValues(alpha: 0.38)));
    } else if (CardLine.hasTasks(n.text)) {
      final lines = CardLine.parse(n.text);
      content = Column(
        crossAxisAlignment:
            n.centered ? CrossAxisAlignment.center : CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < lines.length; i++)
            if (lines[i].task)
              Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: onToggleTask == null ? null : () => onToggleTask!(i),
                    child: Padding(
                      padding: const EdgeInsets.only(right: 8, top: 1),
                      child: Icon(
                        lines[i].done
                            ? Icons.check_circle_rounded
                            : Icons.radio_button_unchecked_rounded,
                        size: 20,
                        color: lines[i].done
                            ? mf.success
                            : colors.text.withValues(alpha: 0.55),
                      ),
                    ),
                  ),
                  Flexible(
                    child: Text(lines[i].text,
                        style: style.copyWith(
                          decoration: lines[i].done
                              ? TextDecoration.lineThrough
                              : null,
                          color: lines[i].done
                              ? colors.text.withValues(alpha: 0.5)
                              : colors.text,
                        )),
                  ),
                ],
              )
            else
              Text(lines[i].text, textAlign: align, style: style),
        ],
      );
    } else {
      content = Text(n.text,
          textAlign: align, overflow: TextOverflow.fade, style: style);
    }

    final centeredBox = n.kind == CardKind.circle || n.kind == CardKind.pill;
    final radius = switch (n.kind) {
      CardKind.card => BorderRadius.circular(16),
      CardKind.sticky => BorderRadius.circular(5),
      CardKind.heading => BorderRadius.circular(10),
      CardKind.pill => BorderRadius.circular(n.h / 2),
      CardKind.circle =>
        BorderRadius.all(Radius.elliptical(n.w / 2, n.h / 2)),
    };
    final heading = n.kind == CardKind.heading;
    return Container(
      padding: cardPadding(n.kind),
      alignment: centeredBox ? Alignment.center : Alignment.topLeft,
      decoration: BoxDecoration(
        color: colors.fill,
        borderRadius: radius,
        border: Border.all(
          color: selected
              ? mf.accent
              : (heading ? Colors.transparent : colors.border),
          width: selected ? 2.4 : 1,
        ),
        boxShadow: heading
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(
                      alpha: n.kind == CardKind.sticky ? 0.28 : 0.18),
                  blurRadius: n.kind == CardKind.sticky ? 16 : 14,
                  offset: Offset(0, n.kind == CardKind.sticky ? 8 : 5),
                ),
                if (selected)
                  BoxShadow(
                      color: mf.accent.withValues(alpha: 0.35),
                      blurRadius: 22,
                      spreadRadius: -2),
              ],
      ),
      child: ClipRect(child: content),
    );
  }
}
