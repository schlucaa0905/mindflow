import 'package:flutter/material.dart';

import '../../data/models.dart';

/// Umschlag eines Notizbuchs – in der Übersicht und als Vorschau beim Anlegen.
class NotebookCover extends StatelessWidget {
  const NotebookCover({
    super.key,
    required this.color,
    required this.style,
    required this.title,
    this.category = '',
    this.compact = false,
  });

  final Color color;
  final CoverStyle style;
  final String title;
  final String category;

  /// Kleine Darstellung (Karten in Übersichten).
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final onCover =
        color.computeLuminance() > 0.55 ? const Color(0xFF1C1C22) : Colors.white;
    return ClipRRect(
      borderRadius: const BorderRadius.only(
        topLeft: Radius.circular(4),
        bottomLeft: Radius.circular(4),
        topRight: Radius.circular(12),
        bottomRight: Radius.circular(12),
      ),
      child: CustomPaint(
        painter: _CoverPainter(color, style),
        child: Padding(
          padding: EdgeInsets.fromLTRB(
              compact ? 22 : 30, compact ? 14 : 22, compact ? 12 : 18, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (category.isNotEmpty)
                Text(category.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: compact ? 9 : 11,
                        letterSpacing: 1.2,
                        fontWeight: FontWeight.w600,
                        color: onCover.withValues(alpha: 0.75))),
              const Spacer(),
              // Etikett mit Titel
              Container(
                width: double.infinity,
                padding: EdgeInsets.symmetric(
                    horizontal: compact ? 8 : 12, vertical: compact ? 6 : 10),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.92),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  title.trim().isEmpty ? 'Ohne Titel' : title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: compact ? 12 : 15,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF1C1C22),
                  ),
                ),
              ),
              SizedBox(height: compact ? 8 : 18),
            ],
          ),
        ),
      ),
    );
  }
}

class _CoverPainter extends CustomPainter {
  _CoverPainter(this.color, this.style);

  final Color color;
  final CoverStyle style;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final hsl = HSLColor.fromColor(color);
    final darker = hsl.withLightness((hsl.lightness - 0.15).clamp(0.0, 1.0)).toColor();
    final lighter = hsl.withLightness((hsl.lightness + 0.1).clamp(0.0, 1.0)).toColor();

    if (style == CoverStyle.gradient) {
      canvas.drawRect(
          rect,
          Paint()
            ..shader = LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [lighter, darker],
            ).createShader(rect));
    } else {
      canvas.drawRect(rect, Paint()..color = color);
    }

    final pattern = Paint()
      ..color = Colors.white.withValues(alpha: 0.12)
      ..strokeWidth = 1;
    switch (style) {
      case CoverStyle.solid:
      case CoverStyle.gradient:
        break;
      case CoverStyle.linen:
        for (var y = 0.0; y < size.height; y += 3) {
          canvas.drawLine(Offset(0, y), Offset(size.width, y),
              pattern..color = Colors.black.withValues(alpha: 0.05));
        }
        for (var x = 0.0; x < size.width; x += 3) {
          canvas.drawLine(Offset(x, 0), Offset(x, size.height),
              pattern..color = Colors.white.withValues(alpha: 0.05));
        }
      case CoverStyle.dots:
        final dot = Paint()..color = Colors.white.withValues(alpha: 0.18);
        for (var y = 10.0; y < size.height; y += 14) {
          for (var x = 10.0 + (y ~/ 14 % 2) * 7; x < size.width; x += 14) {
            canvas.drawCircle(Offset(x, y), 1.6, dot);
          }
        }
      case CoverStyle.stripes:
        final stripe = Paint()
          ..color = Colors.white.withValues(alpha: 0.10)
          ..strokeWidth = 8;
        for (var x = -size.height; x < size.width; x += 22) {
          canvas.drawLine(
              Offset(x, size.height), Offset(x + size.height, 0), stripe);
        }
      case CoverStyle.grid:
        for (var y = 12.0; y < size.height; y += 12) {
          canvas.drawLine(Offset(0, y), Offset(size.width, y), pattern);
        }
        for (var x = 12.0; x < size.width; x += 12) {
          canvas.drawLine(Offset(x, 0), Offset(x, size.height), pattern);
        }
    }

    // Buchrücken mit Gummiband-Andeutung.
    final spine = size.width * 0.06 + 6;
    canvas.drawRect(Rect.fromLTWH(0, 0, spine, size.height),
        Paint()..color = darker.withValues(alpha: 0.9));
    canvas.drawRect(
        Rect.fromLTWH(spine, 0, 1.5, size.height),
        Paint()..color = Colors.black.withValues(alpha: 0.18));
    canvas.drawRect(
        Rect.fromLTWH(size.width - size.width * 0.12, 0, 4, size.height),
        Paint()..color = darker.withValues(alpha: 0.55));
  }

  @override
  bool shouldRepaint(_CoverPainter old) =>
      old.color != color || old.style != style;
}
