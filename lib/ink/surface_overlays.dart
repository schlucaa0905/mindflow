import 'dart:async';

import 'package:flutter/material.dart';

import '../app/theme.dart';
import 'camera.dart';
import 'ink_controller.dart';

/// Kleine Kapsel im Präsentationsmodus: Stift, Laser, Radierer,
/// Rückgängig und Beenden. Sie wird fast durchsichtig, solange man sie
/// nicht benutzt – auf dem Beamer sieht man vor allem das Blatt.
class PresenterControls extends StatefulWidget {
  const PresenterControls({
    super.key,
    required this.controller,
    required this.onExit,
    this.label,
  });

  final InkController controller;
  final VoidCallback onExit;

  /// z. B. "3 / 12".
  final String? label;

  @override
  State<PresenterControls> createState() => _PresenterControlsState();
}

class _PresenterControlsState extends State<PresenterControls> {
  bool _awake = true;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _wake();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _wake() {
    _timer?.cancel();
    if (!_awake) setState(() => _awake = true);
    _timer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _awake = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final mf = context.mf;
    Widget btn(IconData icon, String tip, VoidCallback onTap,
            {bool active = false}) =>
        Tooltip(
          message: tip,
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () {
              _wake();
              onTap();
            },
            child: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: active ? mf.accent : Colors.transparent,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon,
                  size: 19, color: active ? Colors.white : mf.text),
            ),
          ),
        );

    return Listener(
      onPointerDown: (_) => _wake(),
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 300),
        opacity: _awake ? 1 : 0.28,
        child: ListenableBuilder(
          listenable: c,
          builder: (context, _) => Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: mf.surface.withValues(alpha: 0.92),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: mf.border),
              boxShadow: const [
                BoxShadow(
                    color: Color(0x33000000),
                    blurRadius: 14,
                    offset: Offset(0, 4)),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                btn(Icons.edit_outlined, 'Stift',
                    () => c.setTool(ToolMode.pen),
                    active: c.tool == ToolMode.pen),
                btn(Icons.highlight_alt, 'Laserpointer',
                    () => c.setTool(ToolMode.laser),
                    active: c.tool == ToolMode.laser),
                btn(Icons.auto_fix_normal_outlined, 'Radierer',
                    () => c.setTool(ToolMode.eraser),
                    active: c.tool == ToolMode.eraser),
                btn(Icons.undo_rounded, 'Rückgängig', c.undo),
                if (widget.label != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Text(widget.label!,
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: mf.textMuted)),
                  ),
                btn(Icons.close_fullscreen, 'Präsentation beenden',
                    widget.onExit),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Zeigt beim Zoomen kurz "125 %" an (wie Goodnotes).
class ZoomBadge extends StatefulWidget {
  const ZoomBadge({super.key, required this.camera});

  final Camera camera;

  @override
  State<ZoomBadge> createState() => _ZoomBadgeState();
}

class _ZoomBadgeState extends State<ZoomBadge> {
  final DateTime _born = DateTime.now();
  double? _lastScale;
  bool _visible = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    widget.camera.addListener(_onCamera);
  }

  @override
  void dispose() {
    widget.camera.removeListener(_onCamera);
    _timer?.cancel();
    super.dispose();
  }

  void _onCamera() {
    final s = widget.camera.scale;
    final last = _lastScale;
    _lastScale = s;
    // Erster Wert (Einpassen beim Öffnen) zählt nicht.
    if (last == null || (s - last).abs() < 1e-4) return;
    // Das automatische Einpassen beim Öffnen soll keine Anzeige auslösen.
    if (DateTime.now().difference(_born) < const Duration(milliseconds: 800)) {
      return;
    }
    _timer?.cancel();
    if (!_visible) setState(() => _visible = true);
    _timer = Timer(const Duration(milliseconds: 900), () {
      if (mounted) setState(() => _visible = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final mf = context.mf;
    return IgnorePointer(
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 200),
        opacity: _visible ? 1 : 0,
        child: ListenableBuilder(
          listenable: widget.camera,
          builder: (context, _) => Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: mf.text.withValues(alpha: 0.78),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              '${(widget.camera.scale * 100).round()} %',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: mf.surface),
            ),
          ),
        ),
      ),
    );
  }
}
