import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app/theme.dart';

/// Bausteine des futuristischen Looks: Aurora-Hintergrund, Glasflächen,
/// leuchtende Knöpfe und Verlaufstext.
///
/// Bewusst ohne Dauer-Animationen und ohne teure Weichzeichner im
/// Hintergrund: Das iPad 9 soll flüssig bleiben und der Akku geschont werden.

/// Weiche Farbwolken (Violett, Cyan, Magenta) hinter dem Inhalt.
class AuroraBackground extends StatelessWidget {
  const AuroraBackground({super.key, required this.child, this.intensity = 1});

  final Widget child;

  /// 0 … 1 – wie kräftig die Farbwolken sind.
  final double intensity;

  @override
  Widget build(BuildContext context) {
    final mf = context.mf;
    return CustomPaint(
      painter: _AuroraPainter(
        background: mf.background,
        a: mf.accent,
        b: mf.accent2,
        dark: mf.isDark,
        intensity: intensity,
      ),
      child: child,
    );
  }
}

class _AuroraPainter extends CustomPainter {
  _AuroraPainter({
    required this.background,
    required this.a,
    required this.b,
    required this.dark,
    required this.intensity,
  });

  final Color background;
  final Color a;
  final Color b;
  final bool dark;
  final double intensity;

  void _blob(Canvas canvas, Offset c, double r, Color color, double alpha) {
    final paint = Paint()
      ..shader = RadialGradient(
        colors: [
          color.withValues(alpha: alpha * intensity),
          color.withValues(alpha: 0),
        ],
      ).createShader(Rect.fromCircle(center: c, radius: r));
    canvas.drawCircle(c, r, paint);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(rect, Paint()..color = background);
    if (size.isEmpty) return;
    final m = size.longestSide;
    final k = dark ? 1.0 : 0.55;
    _blob(canvas, Offset(size.width * 0.12, -m * 0.05), m * 0.55, a, 0.22 * k);
    _blob(canvas, Offset(size.width * 0.95, size.height * 0.15), m * 0.45, b,
        0.12 * k);
    _blob(canvas, Offset(size.width * 0.7, size.height * 1.05), m * 0.55,
        const Color(0xFFD946EF), 0.08 * k);
    // Feines Raster wie auf einem Display – nur im Dunkeln sichtbar.
    if (dark) {
      final grid = Paint()
        ..color = const Color(0x08FFFFFF)
        ..strokeWidth = 1;
      const step = 48.0;
      for (var x = step; x < size.width; x += step) {
        canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
      }
      for (var y = step; y < size.height; y += step) {
        canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
      }
    }
  }

  @override
  bool shouldRepaint(_AuroraPainter old) =>
      old.background != background ||
      old.a != a ||
      old.b != b ||
      old.dark != dark ||
      old.intensity != intensity;
}

/// Glasfläche mit feiner Lichtkante und weichem Schatten.
class GlassPanel extends StatelessWidget {
  const GlassPanel({
    super.key,
    required this.child,
    this.radius = 20,
    this.padding = EdgeInsets.zero,
    this.glow = false,
    this.opaque = false,
  });

  final Widget child;
  final double radius;
  final EdgeInsetsGeometry padding;

  /// Zusätzlicher violetter Schein (für hervorgehobene Elemente).
  final bool glow;

  /// Deckende Fläche statt Glas (z. B. über einem hellen Blatt).
  final bool opaque;

  @override
  Widget build(BuildContext context) {
    final mf = context.mf;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: opaque ? mf.surface : null,
        gradient: opaque ? null : mf.glassGradient,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: mf.glassEdge),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: mf.isDark ? 0.35 : 0.08),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
          if (glow)
            BoxShadow(color: mf.glow, blurRadius: 28, spreadRadius: -6),
        ],
      ),
      child: child,
    );
  }
}

/// Hauptknopf mit Verlauf und Leuchten.
class GlowButton extends StatefulWidget {
  const GlowButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.expand = false,
    this.compact = false,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool expand;
  final bool compact;

  @override
  State<GlowButton> createState() => _GlowButtonState();
}

class _GlowButtonState extends State<GlowButton> {
  bool _down = false;
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final mf = context.mf;
    final enabled = widget.onPressed != null;
    final h = widget.compact ? 38.0 : 46.0;
    final content = Row(
      mainAxisSize: widget.expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (widget.icon != null) ...[
          Icon(widget.icon, size: 18, color: Colors.white),
          const SizedBox(width: 8),
        ],
        Flexible(
          child: Text(
            widget.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.1,
            ),
          ),
        ),
      ],
    );
    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.label,
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: enabled ? (_) => setState(() => _down = true) : null,
          onTapCancel: () => setState(() => _down = false),
          onTapUp: (_) => setState(() => _down = false),
          onTap: widget.onPressed,
          child: AnimatedScale(
            scale: _down ? 0.97 : 1,
            duration: const Duration(milliseconds: 110),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              height: h,
              padding: EdgeInsets.symmetric(
                  horizontal: widget.compact ? 14 : 20),
              decoration: BoxDecoration(
                gradient: enabled
                    ? mf.gradient
                    : LinearGradient(colors: [mf.border, mf.border]),
                borderRadius: BorderRadius.circular(h / 2.6),
                border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
                boxShadow: enabled
                    ? [
                        BoxShadow(
                          color: mf.glow,
                          blurRadius: _hover ? 26 : 18,
                          spreadRadius: -4,
                          offset: const Offset(0, 6),
                        ),
                      ]
                    : const [],
              ),
              child: content,
            ),
          ),
        ),
      ),
    );
  }
}

/// Text mit Markenverlauf.
class GradientText extends StatelessWidget {
  const GradientText(this.text, {super.key, required this.style});

  final String text;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    final mf = context.mf;
    return ShaderMask(
      blendMode: BlendMode.srcIn,
      shaderCallback: (r) => mf.gradient.createShader(Offset.zero & r.size),
      child: Text(text, style: style.copyWith(color: Colors.white)),
    );
  }
}

/// Symbol mit Markenverlauf.
class GradientIcon extends StatelessWidget {
  const GradientIcon(this.icon, {super.key, this.size = 22});

  final IconData icon;
  final double size;

  @override
  Widget build(BuildContext context) {
    final mf = context.mf;
    return ShaderMask(
      blendMode: BlendMode.srcIn,
      shaderCallback: (r) => mf.gradient.createShader(Offset.zero & r.size),
      child: Icon(icon, size: size, color: Colors.white),
    );
  }
}

/// Das MindFlow-Logo: leuchtender Verlaufs-Kern.
class MindFlowLogo extends StatelessWidget {
  const MindFlowLogo({super.key, this.size = 30});

  final double size;

  @override
  Widget build(BuildContext context) {
    final mf = context.mf;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: mf.gradient,
        borderRadius: BorderRadius.circular(size * 0.32),
        boxShadow: [
          BoxShadow(color: mf.glow, blurRadius: size * 0.6, spreadRadius: -2),
        ],
      ),
      child: CustomPaint(painter: _LogoPainter()),
    );
  }
}

class _LogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.09
      ..strokeCap = StrokeCap.round;
    final w = size.width, h = size.height;
    // Zwei verbundene Knoten – „Your thoughts. Connected.“
    final a = Offset(w * 0.32, h * 0.62);
    final b = Offset(w * 0.68, h * 0.38);
    final path = Path()
      ..moveTo(a.dx, a.dy)
      ..cubicTo(w * 0.45, h * 0.62, w * 0.55, h * 0.38, b.dx, b.dy);
    canvas.drawPath(path, p);
    final dot = Paint()..color = Colors.white;
    canvas.drawCircle(a, w * 0.1, dot);
    canvas.drawCircle(b, w * 0.1, dot);
  }

  @override
  bool shouldRepaint(_LogoPainter old) => false;
}

/// Kleines Etikett mit Leuchtpunkt („Neu“, „3 fällig“ …).
class StatusPill extends StatelessWidget {
  const StatusPill(this.label, {super.key, this.color});

  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final mf = context.mf;
    final c = color ?? mf.accent2;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: c.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: c,
              shape: BoxShape.circle,
              boxShadow: [BoxShadow(color: c, blurRadius: 6)],
            ),
          ),
          const SizedBox(width: 6),
          Text(label,
              style: TextStyle(
                  fontSize: 11.5, fontWeight: FontWeight.w600, color: c)),
        ],
      ),
    );
  }
}

/// Hebt ein Element beim Darüberfahren (Maus) oder Drücken (Finger,
/// Stift) leicht an – gibt Karten ein lebendiges, hochwertiges Gefühl.
class HoverLift extends StatefulWidget {
  const HoverLift({super.key, required this.child, this.lift = 4});

  final Widget child;
  final double lift;

  @override
  State<HoverLift> createState() => _HoverLiftState();
}

class _HoverLiftState extends State<HoverLift> {
  bool _hover = false;
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final up = _hover && !_down;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Listener(
        onPointerDown: (_) => setState(() => _down = true),
        onPointerUp: (_) => setState(() => _down = false),
        onPointerCancel: (_) => setState(() => _down = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          transform: Matrix4.translationValues(
              0, up ? -widget.lift : (_down ? 1.5 : 0), 0),
          child: AnimatedScale(
            scale: _down ? 0.985 : 1,
            duration: const Duration(milliseconds: 120),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

/// Fortschrittsring mit Verlauf und Prozentzahl in der Mitte.
class ProgressRing extends StatelessWidget {
  const ProgressRing({super.key, required this.value, this.size = 64});

  /// 0 … 1
  final double value;
  final double size;

  @override
  Widget build(BuildContext context) {
    final mf = context.mf;
    final v = value.clamp(0.0, 1.0).toDouble();
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: v),
      duration: const Duration(milliseconds: 700),
      curve: Curves.easeOutCubic,
      builder: (context, t, _) => SizedBox(
        width: size,
        height: size,
        child: CustomPaint(
          painter: _RingPainter(
            value: t,
            track: mf.border,
            a: mf.accent,
            b: mf.accent2,
          ),
          child: Center(
            child: Text('${(t * 100).round()} %',
                style: TextStyle(
                    fontSize: size * 0.2,
                    fontWeight: FontWeight.w800,
                    color: mf.text)),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter(
      {required this.value,
      required this.track,
      required this.a,
      required this.b});

  final double value;
  final Color track;
  final Color a;
  final Color b;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.width * 0.1;
    final rect = (Offset.zero & size).deflate(stroke / 2);
    canvas.drawArc(
        rect,
        0,
        math.pi * 2,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..color = track);
    if (value <= 0) return;
    final sweep = math.pi * 2 * value;
    canvas.drawArc(
      rect,
      -math.pi / 2,
      sweep,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..shader = SweepGradient(
          startAngle: 0,
          endAngle: math.pi * 2,
          colors: [a, b, a],
          transform: const GradientRotation(-math.pi / 2),
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.value != value || old.track != track || old.a != a || old.b != b;
}
