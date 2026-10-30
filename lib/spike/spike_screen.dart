import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/theme.dart';
import '../ink/ink_canvas_view.dart';
import '../ink/ink_controller.dart';
import '../storage/ink_store.dart';
import 'frame_monitor.dart';
import 'stress_generator.dart';

/// Phase 0: Der Stift-Test.
///
/// Prüft die drei Fragen, an denen die Plattform-Entscheidung hängt:
/// 1. Fühlt sich das Schreiben mit dem Apple Pencil flüssig an?
/// 2. Bleibt die Fläche mit 10.000 Strichen beim Zoomen/Verschieben flüssig?
/// 3. Überlebt alles einen Neustart der App?
class SpikeScreen extends StatefulWidget {
  const SpikeScreen({super.key});

  @override
  State<SpikeScreen> createState() => _SpikeScreenState();
}

class _SpikeScreenState extends State<SpikeScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final InkController _c = InkController();
  final InkStore _store = InkStore('spike');
  final FrameMonitor _monitor = FrameMonitor();
  final ValueNotifier<String> _saveStatus = ValueNotifier('Lade …');

  late final AnimationController _tour = AnimationController(
      vsync: this, duration: const Duration(seconds: 8));
  Rect _tourArea = Rect.zero;
  Size _viewSize = Size.zero;

  bool _loaded = false;
  int _savedRevision = 0;
  Timer? _saveTimer;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _monitor.start();
    _c.addListener(_rebuild);
    _c.scene.addListener(_scheduleSave);
    _tour.addListener(_tourStep);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _saveTimer?.cancel();
    _tour.dispose();
    _monitor.dispose();
    _saveStatus.dispose();
    _c.removeListener(_rebuild);
    _c.dispose();
    super.dispose();
  }

  void _rebuild() => setState(() {});

  // --- Speichern / Laden ------------------------------------------------

  Future<void> _load() async {
    try {
      final strokes = await _store.load();
      _c.scene.replaceAll(strokes);
      _saveStatus.value = strokes.isEmpty
          ? 'Neue Fläche'
          : '${_c.scene.aliveCount} Striche geladen';
    } on FormatException catch (e) {
      _saveStatus.value = 'Datei beschädigt, beiseitegelegt: ${e.message}';
    } catch (e) {
      _saveStatus.value = 'Laden fehlgeschlagen: $e';
    }
    _savedRevision = _c.scene.revision;
    if (mounted) setState(() => _loaded = true);
  }

  void _scheduleSave() {
    if (!_loaded || _c.scene.revision == _savedRevision) return;
    _saveStatus.value = 'Ungespeichert';
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 800), _saveNow);
  }

  Future<void> _saveNow() async {
    if (_saving) {
      _saveTimer = Timer(const Duration(milliseconds: 300), _saveNow);
      return;
    }
    final rev = _c.scene.revision;
    if (rev == _savedRevision) return;
    _saving = true;
    try {
      final watch = Stopwatch()..start();
      final bytes = await _store.save(_c.scene.strokes);
      _savedRevision = rev;
      if (_c.scene.revision == rev) {
        _saveStatus.value =
            'Gespeichert · ${(bytes / 1024).toStringAsFixed(0)} KB · ${watch.elapsedMilliseconds} ms';
      }
    } catch (e) {
      _saveStatus.value = 'Speichern fehlgeschlagen: $e';
    } finally {
      _saving = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // App geht in den Hintergrund: sofort speichern.
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _saveTimer?.cancel();
      _saveNow();
    }
  }

  // --- Leistungstest ----------------------------------------------------

  Future<void> _runStressTest() async {
    final origin = (_c.scene.contentBounds()?.bottomLeft ?? Offset.zero) +
        const Offset(0, 200);
    final strokes = generateHandwriting(count: 10000, origin: origin);
    final watch = Stopwatch()..start();
    _c.scene.addAll(strokes);
    final addMs = watch.elapsedMilliseconds;
    _tourArea = strokes
        .map((s) => s.bounds)
        .reduce((a, b) => a.expandToInclude(b));
    _saveStatus.value = '10.000 Striche erzeugt ($addMs ms) – Rundflug startet';
    setState(() {});
    await Future<void>.delayed(const Duration(milliseconds: 300));
    _monitor.beginRecording();
    await _tour.forward(from: 0);
    final report = _monitor.endRecording();
    if (!mounted) return;
    setState(() {});
    _showReport(report);
  }

  void _tourStep() {
    if (_tourArea.isEmpty || _viewSize.isEmpty) return;
    final t = _tour.value;
    final zoom = 0.5 - 0.5 * math.cos(t * math.pi * 4); // 0..1..0..1..0
    final scale = 0.12 + (1.8 - 0.12) * zoom;
    final center = _tourArea.center +
        Offset(math.cos(t * math.pi * 2) * _tourArea.width * 0.35,
            math.sin(t * math.pi * 4) * _tourArea.height * 0.35);
    _c.camera.lookAt(center, scale, _viewSize);
  }

  void _showReport(FrameReport r) {
    final verdict = r.passes
        ? 'Bestanden – die Fläche bleibt flüssig.'
        : 'Nicht bestanden – hier muss optimiert werden.';
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ergebnis Leistungstest'),
        content: SelectableText(
          '${r.frames} Bilder in ${r.seconds.toStringAsFixed(1)} s '
          '(${r.fps.toStringAsFixed(0)} Bilder/s)\n'
          'Arbeit pro Bild: Ø ${r.avgMs.toStringAsFixed(1)} ms, '
          'schlechtestes ${r.worstMs.toStringAsFixed(1)} ms\n'
          'Bilder über 16,7 ms: ${(r.slowShare * 100).toStringAsFixed(1)} %\n'
          'Striche gesamt: ${_c.scene.aliveCount}\n\n'
          '$verdict\n\n'
          'Hinweis: Nur im Profil- oder Release-Modus aussagekräftig.',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(
                  text: 'MindFlow Spike: ${r.fps.toStringAsFixed(0)} fps, '
                      'Ø ${r.avgMs.toStringAsFixed(1)} ms, max '
                      '${r.worstMs.toStringAsFixed(1)} ms, '
                      '${(r.slowShare * 100).toStringAsFixed(1)} % langsam, '
                      '${_c.scene.aliveCount} Striche'));
              Navigator.pop(ctx);
            },
            child: const Text('Kopieren'),
          ),
          FilledButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
        ],
      ),
    );
  }

  // --- Oberfläche -------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Shortcuts(
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.keyZ, control: true): _UndoIntent(),
        SingleActivator(LogicalKeyboardKey.keyY, control: true): _RedoIntent(),
        SingleActivator(LogicalKeyboardKey.keyZ, meta: true): _UndoIntent(),
        SingleActivator(LogicalKeyboardKey.keyZ, meta: true, shift: true):
            _RedoIntent(),
      },
      child: Actions(
        actions: {
          _UndoIntent: CallbackAction<_UndoIntent>(onInvoke: (_) => _c.undo()),
          _RedoIntent: CallbackAction<_RedoIntent>(onInvoke: (_) => _c.redo()),
        },
        child: Focus(
          autofocus: true,
          child: Scaffold(
            body: LayoutBuilder(builder: (context, constraints) {
              _viewSize = constraints.biggest;
              return Stack(
                children: [
                  Positioned.fill(child: InkCanvasView(controller: _c)),
                  if (!_loaded)
                    const Center(child: CircularProgressIndicator()),
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: SafeArea(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Center(child: _toolbar()),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 0,
                    bottom: 0,
                    child: SafeArea(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: _statusPanel(),
                      ),
                    ),
                  ),
                ],
              );
            }),
          ),
        ),
      ),
    );
  }

  Widget _toolbar() {
    final hl = _c.tool == ToolMode.highlighter;
    final palette = hl ? MfColors.highlighterPalette : MfColors.inkPalette;
    final activeColor = hl ? _c.highlighterColor : _c.penColor;
    final busy = _tour.isAnimating;
    return _Panel(
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 2,
        runSpacing: 4,
        children: [
          _ToolButton(
            icon: Icons.edit_outlined,
            label: 'Stift',
            selected: _c.tool == ToolMode.pen,
            onTap: () => _c.setTool(ToolMode.pen),
          ),
          _ToolButton(
            icon: Icons.border_color_outlined,
            label: 'Textmarker',
            selected: hl,
            onTap: () => _c.setTool(ToolMode.highlighter),
          ),
          _ToolButton(
            icon: Icons.auto_fix_normal_outlined,
            label: 'Radierer',
            selected: _c.tool == ToolMode.eraser,
            onTap: () => _c.setTool(ToolMode.eraser),
          ),
          const _Divider(),
          for (final color in palette)
            _ColorDot(
              color: color,
              selected: _c.tool != ToolMode.eraser &&
                  color.toARGB32() == activeColor.toARGB32(),
              onTap: () => _c.setColor(color),
            ),
          const _Divider(),
          for (final w in const [1.5, 2.5, 4.5])
            _WidthDot(
              width: w,
              selected: _c.penWidth == w,
              onTap: () => _c.setWidth(w),
            ),
          const _Divider(),
          _ToolButton(
            icon: Icons.undo,
            label: 'Rückgängig',
            onTap: _c.history.canUndo ? _c.undo : null,
          ),
          _ToolButton(
            icon: Icons.redo,
            label: 'Wiederholen',
            onTap: _c.history.canRedo ? _c.redo : null,
          ),
          const _Divider(),
          _ToolButton(
            icon: Icons.pan_tool_outlined,
            label: _c.stylusOnly
                ? 'Nur Stift zeichnet (Finger navigieren)'
                : 'Finger und Maus zeichnen',
            selected: _c.stylusOnly,
            onTap: () => _c.setStylusOnly(!_c.stylusOnly),
          ),
          _ToolButton(
            icon: Icons.fit_screen_outlined,
            label: 'Alles zeigen',
            onTap: () => _c.fitContent(_viewSize),
          ),
          _ToolButton(
            icon: Icons.speed,
            label: 'Leistungstest (10.000 Striche + Rundflug)',
            onTap: busy || !_loaded ? null : _runStressTest,
          ),
          _ToolButton(
            icon: Icons.delete_sweep_outlined,
            label: 'Alles löschen (rückgängig machbar)',
            onTap: _c.clearAll,
          ),
        ],
      ),
    );
  }

  Widget _statusPanel() {
    const style = TextStyle(
        color: MfColors.textMuted, fontSize: 12, height: 1.5);
    return _Panel(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: ListenableBuilder(
        listenable: Listenable.merge(
            [_c.scene, _c.camera, _monitor.live, _saveStatus]),
        builder: (context, _) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${_c.scene.aliveCount} Striche · Zoom '
              '${(_c.camera.scale * 100).round()} %',
              style: style.copyWith(color: MfColors.text),
            ),
            Text('Bildzeit ${_monitor.live.value}', style: style),
            Text(_saveStatus.value, style: style),
          ],
        ),
      ),
    );
  }
}

class _UndoIntent extends Intent {
  const _UndoIntent();
}

class _RedoIntent extends Intent {
  const _RedoIntent();
}

// --- Kleine Bausteine ---------------------------------------------------

class _Panel extends StatelessWidget {
  const _Panel({required this.child, this.padding});

  final Widget child;
  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding ?? const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: MfColors.surface.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: MfColors.border),
        boxShadow: const [
          BoxShadow(color: Color(0x55000000), blurRadius: 24, offset: Offset(0, 8)),
        ],
      ),
      child: child,
    );
  }
}

class _ToolButton extends StatelessWidget {
  const _ToolButton({
    required this.icon,
    required this.label,
    this.onTap,
    this.selected = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Tooltip(
      message: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: selected
                ? MfColors.accent.withValues(alpha: 0.18)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            icon,
            size: 20,
            color: !enabled
                ? MfColors.textMuted.withValues(alpha: 0.35)
                : selected
                    ? MfColors.accent
                    : MfColors.text,
          ),
        ),
      ),
    );
  }
}

class _ColorDot extends StatelessWidget {
  const _ColorDot(
      {required this.color, required this.selected, required this.onTap});

  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 32,
        height: 40,
        alignment: Alignment.center,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          width: selected ? 22 : 18,
          height: selected ? 22 : 18,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(
              color: selected ? MfColors.accent : MfColors.border,
              width: selected ? 2.5 : 1,
            ),
          ),
        ),
      ),
    );
  }
}

class _WidthDot extends StatelessWidget {
  const _WidthDot(
      {required this.width, required this.selected, required this.onTap});

  final double width;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 30,
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected
              ? MfColors.accent.withValues(alpha: 0.18)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Container(
          width: width * 2.4,
          height: width * 2.4,
          decoration: BoxDecoration(
            color: selected ? MfColors.accent : MfColors.text,
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 24,
      margin: const EdgeInsets.symmetric(horizontal: 6),
      color: MfColors.border,
    );
  }
}
