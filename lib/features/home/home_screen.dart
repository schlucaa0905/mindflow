import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/sections.dart';
import '../../app/services.dart';
import '../../app/theme.dart';
import '../../data/models.dart';
import '../../ui/futuristic.dart';
import '../../ui/widgets.dart';
import '../common/create_dialogs.dart';
import '../common/object_card.dart';
import '../study/review_screen.dart';

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
    final s = Services.of(context);
    final repo = s.objects;
    return ListenableBuilder(
      listenable: repo,
      builder: (context, _) {
        final pinned = repo.pinned();
        final recent = repo.recent();
        final stats = s.study.stats(DateTime.now());
        final counts = (
          notebooks: repo.byType(ObjectType.notebook).length,
          boards: repo.byType(ObjectType.board).length,
          knowledge: repo.byType(ObjectType.knowledge).length,
        );
        return ListView(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 48),
          children: [
            _Hero(
              greeting: _greeting(),
              date: _date(),
              chips: [
                ('${counts.notebooks}', 'Notizbücher'),
                ('${counts.boards}', 'Canvas'),
                ('${counts.knowledge}', 'Wissen'),
                ('${stats.due}', 'Karten fällig'),
              ],
            ),
            const SizedBox(height: 22),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _QuickAction(
                  icon: Icons.menu_book_rounded,
                  label: 'Neues Notizbuch',
                  hint: 'Schreiben',
                  onTap: () => createNotebook(context),
                ),
                _QuickAction(
                  icon: Icons.bubble_chart_rounded,
                  label: 'Neuer Canvas',
                  hint: 'Denken',
                  onTap: () => createBoard(context),
                ),
                _QuickAction(
                  icon: Icons.picture_as_pdf_rounded,
                  label: 'PDF importieren',
                  hint: 'Markieren',
                  onTap: () => importDocument(context),
                ),
                _QuickAction(
                  icon: Icons.hub_rounded,
                  label: 'Wissenseintrag',
                  hint: 'Verknüpfen',
                  onTap: () => createKnowledge(context),
                ),
                _QuickAction(
                  icon: Icons.style_rounded,
                  label: 'Lernen',
                  hint: stats.due > 0 ? '${stats.due} fällig' : 'Karteikarten',
                  onTap: () => onNavigate(Section.study),
                ),
                _QuickAction(
                  icon: Icons.move_down_rounded,
                  label: 'Aus Goodnotes',
                  hint: 'Übernehmen',
                  onTap: () => importFromGoodnotes(context),
                ),
              ],
            ),
            const SizedBox(height: 34),
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
              const GlassPanel(
                padding: EdgeInsets.all(24),
                child: _EmptyRecent(),
              )
            else
              ObjectGrid(objects: recent),
            const SizedBox(height: 34),
            const SectionHeader('Lernfortschritt'),
            _StudyCard(
              total: stats.total,
              due: stats.due,
              learned: stats.learned,
              difficult: stats.difficult,
              progress: stats.progress,
              onOpen: () => onNavigate(Section.study),
            ),
            const SizedBox(height: 34),
            const SectionHeader('Bereiche'),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final sec in Section.values)
                  if (sec != Section.home)
                    _AreaTile(section: sec, onTap: () => onNavigate(sec)),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _EmptyRecent extends StatelessWidget {
  const _EmptyRecent();

  @override
  Widget build(BuildContext context) {
    return Text(
      'Noch nichts hier. Leg oben dein erstes Notizbuch oder deinen '
      'ersten Canvas an.',
      style: TextStyle(color: context.mf.textMuted),
    );
  }
}

/// Großer Begrüßungsbereich mit Verlaufstitel und Kennzahlen.
class _Hero extends StatelessWidget {
  const _Hero({required this.greeting, required this.date, required this.chips});

  final String greeting;
  final String date;
  final List<(String, String)> chips;

  @override
  Widget build(BuildContext context) {
    final mf = context.mf;
    return GlassPanel(
      radius: 28,
      padding: const EdgeInsets.fromLTRB(26, 24, 26, 22),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Dezente Kreisbahnen rechts oben – „Orbit“-Motiv.
          Positioned(
            right: -10,
            top: -14,
            child: IgnorePointer(
              child: CustomPaint(
                size: const Size(150, 110),
                painter: _OrbitPainter(mf.accent, mf.accent2),
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              StatusPill(date),
              const SizedBox(height: 14),
              GradientText(
                greeting,
                style: const TextStyle(
                  fontSize: 38,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -1.4,
                  height: 1.05,
                ),
              ),
              const SizedBox(height: 6),
              Text('Your thoughts. Connected.',
                  style: TextStyle(
                      fontSize: 14, letterSpacing: 0.3, color: mf.textMuted)),
              const SizedBox(height: 20),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final chip in chips)
                    _StatChip(value: chip.$1, label: chip.$2),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _OrbitPainter extends CustomPainter {
  _OrbitPainter(this.a, this.b);

  final Color a;
  final Color b;

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width * 0.62, size.height * 0.45);
    for (var i = 0; i < 3; i++) {
      final r = 26.0 + i * 20;
      canvas.drawOval(
        Rect.fromCenter(center: c, width: r * 2.4, height: r * 1.3),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = Color.lerp(a, b, i / 2)!.withValues(alpha: 0.28 - i * 0.06),
      );
    }
    canvas.drawCircle(c, 5, Paint()..color = a.withValues(alpha: 0.9));
    canvas.drawCircle(c, 12, Paint()..color = a.withValues(alpha: 0.15));
    final sat = c + Offset(math.cos(-0.6) * 31 * 1.2, math.sin(-0.6) * 31 * 0.65);
    canvas.drawCircle(sat, 3.2, Paint()..color = b);
    canvas.drawCircle(sat, 8, Paint()..color = b.withValues(alpha: 0.18));
  }

  @override
  bool shouldRepaint(_OrbitPainter old) => old.a != a || old.b != b;
}

class _StatChip extends StatelessWidget {
  const _StatChip({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final mf = context.mf;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: mf.surfaceRaised.withValues(alpha: mf.isDark ? 0.6 : 1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: mf.glassEdge),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(value,
              style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                  color: mf.text)),
          const SizedBox(width: 7),
          Text(label, style: TextStyle(fontSize: 12.5, color: mf.textMuted)),
        ],
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({
    required this.icon,
    required this.label,
    required this.hint,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String hint;
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
          width: 184,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            gradient: mf.glassGradient,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: mf.glassEdge),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: mf.isDark ? 0.25 : 0.05),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      mf.accent.withValues(alpha: 0.30),
                      mf.accent2.withValues(alpha: 0.16),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: mf.accent.withValues(alpha: 0.3)),
                ),
                child: Icon(icon, size: 21, color: mf.text),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13.5,
                            color: mf.text)),
                    const SizedBox(height: 2),
                    Text(hint,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11.5, color: mf.textMuted)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Lernstand mit Fortschrittsring.
class _StudyCard extends StatelessWidget {
  const _StudyCard({
    required this.total,
    required this.due,
    required this.learned,
    required this.difficult,
    required this.progress,
    required this.onOpen,
  });

  final int total;
  final int due;
  final int learned;
  final int difficult;
  final double progress;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final mf = context.mf;
    if (total == 0) {
      return GlassPanel(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            const GradientIcon(Icons.style_rounded, size: 28),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                'Noch keine Karteikarten. Erstelle sie in einem '
                'Wissenseintrag oder im Lernbereich.',
                style: TextStyle(color: mf.textMuted, height: 1.4),
              ),
            ),
            const SizedBox(width: 12),
            GlowButton(label: 'Zum Lernen', compact: true, onPressed: onOpen),
          ],
        ),
      );
    }
    return GlassPanel(
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          ProgressRing(value: progress, size: 74),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                    due == 0
                        ? 'Alles erledigt – stark!'
                        : '$due ${due == 1 ? 'Karte ist' : 'Karten sind'} fällig',
                    style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: mf.text)),
                const SizedBox(height: 4),
                Text(
                  '$learned von $total sicher gelernt'
                  '${difficult > 0 ? ' · $difficult schwierig' : ''}',
                  style: TextStyle(color: mf.textMuted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          GlowButton(
            label: due > 0 ? 'Jetzt lernen' : 'Lernbereich',
            icon: due > 0 ? Icons.play_arrow_rounded : null,
            compact: true,
            onPressed: due > 0
                ? () => startReview(context)
                : onOpen,
          ),
        ],
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
    return HoverLift(
      lift: 3,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          width: 150,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: mf.glassGradient,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: mf.glassEdge),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GradientIcon(section.selectedIcon, size: 24),
              const SizedBox(height: 12),
              Text(section.label,
                  style:
                      TextStyle(fontWeight: FontWeight.w600, color: mf.text)),
            ],
          ),
        ),
      ),
    );
  }
}
