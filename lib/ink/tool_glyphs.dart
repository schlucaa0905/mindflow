import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Welche Werkzeug-Grafik gezeichnet wird.
enum GlyphKind {
  fountain,
  ballpoint,
  brush,
  highlighter,
  eraser,
  lasso,
  shape,
  laser
}

/// Gezeichnete Werkzeuge wie in Goodnotes: Stifte stehen aufrecht, die
/// Spitze trägt die aktuelle Farbe, das gewählte Werkzeug hebt sich an.
class ToolGlyph extends StatelessWidget {
  const ToolGlyph({
    super.key,
    required this.kind,
    required this.tip,
    required this.body,
    required this.outline,
    required this.selected,
  });

  final GlyphKind kind;

  /// Farbe der Spitze (aktuelle Stift- bzw. Markerfarbe).
  final Color tip;

  /// Farbe des Stiftkörpers.
  final Color body;

  /// Linienfarbe für Lasso, Formen und Konturen.
  final Color outline;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(end: selected ? 1 : 0),
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutBack,
      builder: (context, t, _) => CustomPaint(
        size: const Size(30, 36),
        painter: _GlyphPainter(
          kind: kind,
          tip: tip,
          body: body,
          outline: outline,
          lift: t,
        ),
      ),
    );
  }
}

class _GlyphPainter extends CustomPainter {
  _GlyphPainter({
    required this.kind,
    required this.tip,
    required this.body,
    required this.outline,
    required this.lift,
  });

  final GlyphKind kind;
  final Color tip;
  final Color body;
  final Color outline;
  final double lift;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.clipRect(Offset.zero & size);
    final cx = size.width / 2;
    switch (kind) {
      case GlyphKind.fountain:
      case GlyphKind.ballpoint:
      case GlyphKind.brush:
      case GlyphKind.highlighter:
      case GlyphKind.eraser:
      case GlyphKind.laser:
        // Stehende Werkzeuge: angehoben, wenn gewählt.
        canvas.save();
        canvas.translate(0, 9 - 9 * lift);
        _instrument(canvas, size, cx);
        canvas.restore();
      case GlyphKind.lasso:
        _lasso(canvas, size, cx);
      case GlyphKind.shape:
        _shapes(canvas, size, cx);
    }
  }

  Paint get _bodyPaint => Paint()..color = body;
  Paint get _edge => Paint()
    ..color = outline.withValues(alpha: 0.25)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1;

  void _instrument(Canvas canvas, Size size, double cx) {
    final bottom = size.height + 4;
    switch (kind) {
      case GlyphKind.fountain: {
        const top = 14.0;
        final bodyRect = RRect.fromLTRBAndCorners(cx - 5, top, cx + 5, bottom,
            topLeft: const Radius.circular(2), topRight: const Radius.circular(2));
        canvas.drawRRect(bodyRect, _bodyPaint);
        canvas.drawRRect(bodyRect, _edge);
        // Farbring
        canvas.drawRect(Rect.fromLTRB(cx - 5, top + 5, cx + 5, top + 8),
            Paint()..color = tip);
        // Feder
        final nib = Path()
          ..moveTo(cx - 5, top)
          ..lineTo(cx + 5, top)
          ..lineTo(cx + 1.2, 3)
          ..quadraticBezierTo(cx, 1.5, cx - 1.2, 3)
          ..close();
        canvas.drawPath(nib, Paint()..color = tip);
        canvas.drawLine(Offset(cx, top - 1), Offset(cx, 6),
            Paint()
              ..color = Colors.white.withValues(alpha: 0.55)
              ..strokeWidth = 0.8);
      }
      case GlyphKind.ballpoint: {
        const top = 13.0;
        final bodyRect = RRect.fromLTRBAndCorners(cx - 4.5, top, cx + 4.5, bottom,
            topLeft: const Radius.circular(2), topRight: const Radius.circular(2));
        canvas.drawRRect(bodyRect, _bodyPaint);
        canvas.drawRRect(bodyRect, _edge);
        canvas.drawRect(Rect.fromLTRB(cx - 4.5, top + 6, cx + 4.5, top + 9),
            Paint()..color = tip);
        final cone = Path()
          ..moveTo(cx - 4.5, top)
          ..lineTo(cx + 4.5, top)
          ..lineTo(cx + 1, 4)
          ..lineTo(cx - 1, 4)
          ..close();
        canvas.drawPath(cone, Paint()..color = body.withValues(alpha: 0.85));
        canvas.drawPath(cone, _edge);
        canvas.drawCircle(Offset(cx, 3.2), 1.6, Paint()..color = tip);
      }
      case GlyphKind.brush: {
        const top = 15.0;
        final bodyRect = RRect.fromLTRBAndCorners(cx - 5, top, cx + 5, bottom,
            topLeft: const Radius.circular(3), topRight: const Radius.circular(3));
        canvas.drawRRect(bodyRect, _bodyPaint);
        canvas.drawRRect(bodyRect, _edge);
        final hair = Path()
          ..moveTo(cx - 4, top)
          ..quadraticBezierTo(cx - 5, 8, cx, 1)
          ..quadraticBezierTo(cx + 5, 8, cx + 4, top)
          ..close();
        canvas.drawPath(hair, Paint()..color = tip);
      }
      case GlyphKind.highlighter: {
        const top = 14.0;
        final bodyRect = RRect.fromLTRBAndCorners(cx - 7, top, cx + 7, bottom,
            topLeft: const Radius.circular(3), topRight: const Radius.circular(3));
        canvas.drawRRect(bodyRect, _bodyPaint);
        canvas.drawRRect(bodyRect, _edge);
        canvas.drawRect(Rect.fromLTRB(cx - 7, top + 4, cx + 7, top + 9),
            Paint()..color = tip.withValues(alpha: 0.9));
        // Schräge Keilspitze
        final chisel = Path()
          ..moveTo(cx - 5, top)
          ..lineTo(cx + 5, top)
          ..lineTo(cx + 5, 6)
          ..lineTo(cx - 3, 3)
          ..close();
        canvas.drawPath(chisel, Paint()..color = tip);
      }
      case GlyphKind.eraser: {
        const top = 6.0;
        final block = RRect.fromLTRBR(cx - 7, top, cx + 7, bottom,
            const Radius.circular(4));
        canvas.drawRRect(block, _bodyPaint);
        canvas.drawRRect(block, _edge);
        final rubber = RRect.fromLTRBAndCorners(cx - 7, top, cx + 7, top + 9,
            topLeft: const Radius.circular(4), topRight: const Radius.circular(4));
        canvas.drawRRect(rubber, Paint()..color = const Color(0xFFF9A8C4));
        canvas.drawLine(Offset(cx - 7, top + 9), Offset(cx + 7, top + 9),
            Paint()
              ..color = outline.withValues(alpha: 0.3)
              ..strokeWidth = 1);
      }
      case GlyphKind.laser: {
        const top = 12.0;
        final bodyRect = RRect.fromLTRBAndCorners(cx - 4.5, top, cx + 4.5, bottom,
            topLeft: const Radius.circular(4), topRight: const Radius.circular(4));
        canvas.drawRRect(bodyRect, Paint()..color = const Color(0xFF3A3A44));
        canvas.drawCircle(
            Offset(cx, 6),
            6,
            Paint()
              ..color = const Color(0xFFFF3B30).withValues(alpha: 0.35)
              ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3));
        canvas.drawCircle(Offset(cx, 6), 2.6, Paint()..color = const Color(0xFFFF453A));
      }
      case GlyphKind.lasso:
      case GlyphKind.shape:
        break;
    }
  }

  void _lasso(Canvas canvas, Size size, double cx) {
    final s = 1 + 0.08 * lift;
    canvas.save();
    canvas.translate(cx, size.height / 2);
    canvas.scale(s);
    canvas.translate(-cx, -size.height / 2);
    final paint = Paint()
      ..color = outline
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round;
    // Gestrichelte Schlaufe
    final rect = Rect.fromCenter(center: Offset(cx, 15), width: 22, height: 15);
    const dashes = 14;
    for (var i = 0; i < dashes; i++) {
      if (i.isOdd) continue;
      final a0 = i / dashes * math.pi * 2;
      final a1 = (i + 1) / dashes * math.pi * 2;
      canvas.drawArc(rect, a0, a1 - a0, false, paint);
    }
    // Schweif
    final tail = Path()
      ..moveTo(cx - 3, 22)
      ..quadraticBezierTo(cx - 7, 28, cx - 2, 32);
    canvas.drawPath(tail, paint);
    canvas.restore();
  }

  void _shapes(Canvas canvas, Size size, double cx) {
    final s = 1 + 0.08 * lift;
    canvas.save();
    canvas.translate(cx, size.height / 2);
    canvas.scale(s);
    canvas.translate(-cx, -size.height / 2);
    final paint = Paint()
      ..color = outline
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8;
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(cx - 12, 12, 13, 13), const Radius.circular(2)),
        paint);
    canvas.drawCircle(Offset(cx + 5, 14), 7,
        paint..color = tip.withValues(alpha: 0.95));
    canvas.restore();
  }

  @override
  bool shouldRepaint(_GlyphPainter old) =>
      old.kind != kind ||
      old.tip != tip ||
      old.body != body ||
      old.outline != outline ||
      old.lift != lift;
}
