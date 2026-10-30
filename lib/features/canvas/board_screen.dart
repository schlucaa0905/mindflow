import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/services.dart';
import '../../app/theme.dart';
import '../../data/models.dart';
import '../../ink/camera.dart';
import '../../ink/ink_canvas_view.dart';
import '../../ink/ink_controller.dart';
import '../../ink/ink_surface.dart';
import '../../ui/widgets.dart';

/// Die vier Arbeitsmodi des Canvas.
enum BoardMode {
  write('Schreiben', Icons.edit_outlined,
      'Mit Stift oder Maus schreiben und zeichnen.'),
  select('Auswählen', Icons.near_me_outlined,
      'Karten antippen und ziehen. Doppeltippen: Text bearbeiten. '
          'Doppeltippen auf leere Fläche: neue Karte.'),
  connect('Verbinden', Icons.timeline,
      'Von einer Karte zur anderen ziehen. Nochmal verbinden löst die Verbindung.'),
  navigate('Navigieren', Icons.open_with,
      'Fläche verschieben und zoomen, ohne etwas zu verändern.');

  const BoardMode(this.label, this.icon, this.hint);
  final String label;
  final IconData icon;
  final String hint;
}

/// Ein geöffneter Infinite Canvas: Handschrift + Karten + Verbindungen.
class BoardScreen extends StatefulWidget {
  const BoardScreen({super.key, required this.boardId, this.focusNodeId});

  final String boardId;

  /// Karte, die beim Öffnen gezeigt werden soll (z. B. aus der Suche).
  final String? focusNodeId;

  @override
  State<BoardScreen> createState() => _BoardScreenState();
}

class _BoardScreenState extends State<BoardScreen> {
  late AppServices _s;
  MfObject? _board;
  List<CanvasNode> _nodes = [];
  List<CanvasEdge> _edges = [];
  BoardMode _mode = BoardMode.select;
  String? _selected;
  InkController? _ink;
  Size _viewSize = Size.zero;
  final GlobalKey _layerKey = GlobalKey();
  bool _focused = false;

  // Verbinden
  String? _connectFrom;
  Offset? _connectWorld;

  // Doppeltippen auf leere Fläche
  DateTime? _lastBgTap;
  Offset? _lastBgTapWorld;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_board != null) return;
    _s = Services.of(context);
    _board = _s.objects.get(widget.boardId);
    _s.objects.markOpened(widget.boardId);
    _nodes = _s.canvas.nodes(widget.boardId);
    _edges = _s.canvas.edges(widget.boardId);
    if (widget.focusNodeId != null) _selected = widget.focusNodeId;
  }

  CanvasNode? _node(String id) {
    for (final n in _nodes) {
      if (n.id == id) return n;
    }
    return null;
  }

  void _setMode(BoardMode m) {
    _ink?.setDrawingEnabled(m == BoardMode.write);
    setState(() {
      _mode = m;
      if (m == BoardMode.write || m == BoardMode.navigate) _selected = null;
    });
  }

  void _changed() => _s.objects.touch(widget.boardId);

  // --- Karten -----------------------------------------------------------

  Future<void> _addCard([Offset? worldCenter]) async {
    final cam = _ink?.camera;
    if (cam == null) return;
    final center = worldCenter ??
        cam.toWorld(Offset(_viewSize.width / 2, _viewSize.height / 2)) +
            Offset((_nodes.length % 5) * 18.0, (_nodes.length % 5) * 18.0);
    final n = _s.canvas.createNode(widget.boardId,
        x: center.dx - 110, y: center.dy - 55);
    _changed();
    setState(() {
      _nodes.add(n);
      _selected = n.id;
      if (_mode != BoardMode.select) _mode = BoardMode.select;
    });
    _ink?.setDrawingEnabled(false);
    await _editNode(n);
  }

  Future<void> _editNode(CanvasNode n) async {
    final text = await askText(context,
        title: 'Karte bearbeiten',
        initial: n.text,
        hint: 'Thema, Gedanke, Stichpunkte …',
        multiline: true);
    if (text == null) return;
    n.text = text.trim();
    n.h = _heightFor(n.text, n.w);
    _s.canvas.updateNode(n);
    _changed();
    setState(() {});
  }

  /// Passt die Kartenhöhe an den Text an.
  double _heightFor(String text, double width) {
    final tp = TextPainter(
      text: TextSpan(text: text.isEmpty ? ' ' : text, style: _NodeCard.textStyle),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: width - 28);
    return math.min(420, math.max(72, tp.height + 30));
  }

  void _deleteSelected() {
    final id = _selected;
    if (id == null) return;
    final node = _node(id);
    if (node == null) return;
    _s.canvas.deleteNode(id);
    _changed();
    setState(() {
      _nodes.removeWhere((n) => n.id == id);
      _edges.removeWhere((e) => e.fromId == id || e.toId == id);
      _selected = null;
    });
  }

  // --- Gesten auf Karten ------------------------------------------------

  Offset? _toWorld(Offset global) {
    final box = _layerKey.currentContext?.findRenderObject() as RenderBox?;
    final cam = _ink?.camera;
    if (box == null || cam == null) return null;
    return cam.toWorld(box.globalToLocal(global));
  }

  void _panStart(CanvasNode n, DragStartDetails d) {
    setState(() => _selected = n.id);
    if (_mode == BoardMode.connect) {
      _connectFrom = n.id;
      _connectWorld = _toWorld(d.globalPosition);
    }
  }

  void _panUpdate(CanvasNode n, DragUpdateDetails d) {
    final cam = _ink?.camera;
    if (cam == null) return;
    setState(() {
      if (_mode == BoardMode.select) {
        n.x += d.delta.dx / cam.scale;
        n.y += d.delta.dy / cam.scale;
      } else if (_mode == BoardMode.connect) {
        _connectWorld = _toWorld(d.globalPosition);
      }
    });
  }

  void _panEnd(CanvasNode n) {
    if (_mode == BoardMode.select) {
      _s.canvas.updateNode(n);
      _changed();
      return;
    }
    if (_mode != BoardMode.connect) return;
    final from = _connectFrom, at = _connectWorld;
    setState(() {
      _connectFrom = null;
      _connectWorld = null;
    });
    if (from == null || at == null) return;
    CanvasNode? target;
    for (final m in _nodes.reversed) {
      if (m.id != from && Rect.fromLTWH(m.x, m.y, m.w, m.h).contains(at)) {
        target = m;
        break;
      }
    }
    if (target == null) return;
    final edge = _s.canvas.createEdge(widget.boardId, from, target.id);
    if (edge != null) {
      setState(() => _edges.add(edge));
    } else {
      // Gab es schon – dann lösen wir sie.
      final t = target.id;
      final existing = _edges.where((e) =>
          (e.fromId == from && e.toId == t) ||
          (e.fromId == t && e.toId == from));
      for (final e in existing.toList()) {
        _s.canvas.deleteEdge(e.id);
      }
      setState(() => _edges.removeWhere((e) =>
          (e.fromId == from && e.toId == t) ||
          (e.fromId == t && e.toId == from)));
    }
    _changed();
  }

  void _onBackgroundTap(Offset world) {
    final now = DateTime.now();
    final isDouble = _lastBgTap != null &&
        now.difference(_lastBgTap!) < const Duration(milliseconds: 380) &&
        _lastBgTapWorld != null &&
        (_lastBgTapWorld! - world).distance * (_ink?.camera.scale ?? 1) < 24;
    _lastBgTap = now;
    _lastBgTapWorld = world;
    if (isDouble && _mode == BoardMode.select) {
      _lastBgTap = null;
      _addCard(world);
      return;
    }
    if (_selected != null) setState(() => _selected = null);
  }

  // --- Oberfläche -------------------------------------------------------

  Future<void> _rename() async {
    final t = await askText(context,
        title: 'Canvas umbenennen', initial: _board!.title);
    if (t == null || t.trim().isEmpty) return;
    _s.objects.rename(widget.boardId, t.trim());
    setState(() => _board = _s.objects.get(widget.boardId));
  }

  Widget _overlay(BuildContext context, InkController c, PaperStyle paper) {
    return LayoutBuilder(builder: (context, constraints) {
      _viewSize = constraints.biggest;
      if (!_focused && widget.focusNodeId != null) {
        _focused = true;
        final n = _node(widget.focusNodeId!);
        if (n != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            c.camera.lookAt(Offset(n.x + n.w / 2, n.y + n.h / 2), 1.0, _viewSize);
          });
        }
      }
      final interactive =
          _mode == BoardMode.select || _mode == BoardMode.connect;
      return ListenableBuilder(
        listenable: c.camera,
        builder: (context, _) {
          final cam = c.camera;
          final visible = cam.visibleWorldRect(_viewSize).inflate(60);
          final byId = {for (final n in _nodes) n.id: n};
          return IgnorePointer(
            ignoring: !interactive,
            child: Stack(
              key: _layerKey,
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(
                      painter: _EdgePainter(
                        camera: cam,
                        nodes: byId,
                        edges: _edges,
                        color: context.mf.accent,
                        pendingFrom: _connectFrom == null
                            ? null
                            : byId[_connectFrom!],
                        pendingTo: _connectWorld,
                      ),
                    ),
                  ),
                ),
                for (final n in _nodes)
                  if (Rect.fromLTWH(n.x, n.y, n.w, n.h).overlaps(visible))
                    _positionedNode(n, cam, paper),
              ],
            ),
          );
        },
      );
    });
  }

  Widget _positionedNode(CanvasNode n, Camera cam, PaperStyle paper) {
    final p = cam.toScreen(Offset(n.x, n.y));
    final s = cam.scale;
    return Positioned(
      key: ValueKey(n.id),
      left: p.dx,
      top: p.dy,
      width: n.w * s,
      height: n.h * s,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => _selected = n.id),
        onDoubleTap:
            _mode == BoardMode.select ? () => _editNode(n) : null,
        onPanStart: (d) => _panStart(n, d),
        onPanUpdate: (d) => _panUpdate(n, d),
        onPanEnd: (_) => _panEnd(n),
        child: FittedBox(
          fit: BoxFit.fill,
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: n.w,
            height: n.h,
            child: _NodeCard(
              node: n,
              paper: paper,
              selected: n.id == _selected,
              accent: context.mf.accent,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final board = _board;
    if (board == null) {
      return const Scaffold(body: Center(child: Text('Canvas nicht gefunden')));
    }
    final paper = PaperStyle.of(board.paper);
    final mf = context.mf;
    final hasSelection = _selected != null && _mode != BoardMode.write;

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.delete): _deleteSelected,
        const SingleActivator(LogicalKeyboardKey.backspace): _deleteSelected,
      },
      // Fokus liegt auf der Schreibfläche; Tasten, die sie nicht braucht
      // (z. B. Entf ohne Lasso-Auswahl), kommen hier an.
      child: Focus(
        child: Scaffold(
          backgroundColor: paper.sheet,
          body: Stack(
            children: [
              Positioned.fill(
                child: InkSurface(
                  inkId: board.id,
                  paper: board.paper,
                  toolbarInsets: const EdgeInsets.fromLTRB(12, 64, 12, 76),
                  showInkTools: _mode == BoardMode.write,
                  onSaved: _changed,
                  onControllerReady: (c) {
                    _ink = c;
                    c.setDrawingEnabled(_mode == BoardMode.write);
                  },
                  onBackgroundTap: _onBackgroundTap,
                  backgroundBuilder: (camera) =>
                      DotGridPainter(camera, paper.line, fill: paper.sheet),
                  overlayBuilder: (context, c) => _overlay(context, c, paper),
                  toolbarLeading: [
                    for (final m in BoardMode.values)
                      ToolButton(
                        icon: m.icon,
                        label: m.label,
                        selected: _mode == m,
                        onTap: () => _setMode(m),
                      ),
                  ],
                  toolbarTrailing: [
                    ToolButton(
                      icon: Icons.add_box_outlined,
                      label: 'Neue Karte',
                      onTap: () => _addCard(),
                    ),
                    if (hasSelection) ...[
                      ToolButton(
                        icon: Icons.notes,
                        label: 'Text bearbeiten',
                        onTap: () {
                          final n = _node(_selected!);
                          if (n != null) _editNode(n);
                        },
                      ),
                      ToolButton(
                        icon: Icons.delete_outline,
                        label: 'Karte löschen',
                        danger: true,
                        onTap: _deleteSelected,
                      ),
                    ],
                  ],
                ),
              ),
              // Kopfzeile
              Positioned(
                top: 0,
                left: 0,
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                    child: FloatingPanel(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ToolButton(
                            icon: Icons.arrow_back,
                            label: 'Zurück',
                            onTap: () => Navigator.of(context).maybePop(),
                          ),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 260),
                            child: InkWell(
                              onTap: _rename,
                              borderRadius: BorderRadius.circular(8),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 10),
                                child: Text(board.displayTitle,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        color: mf.text)),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              // Hinweis zum aktuellen Modus
              Positioned(
                bottom: 16,
                left: 16,
                right: 16,
                child: SafeArea(
                  top: false,
                  child: Center(
                    child: FloatingPanel(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(_mode.icon, size: 16, color: mf.accent),
                          const SizedBox(width: 10),
                          Flexible(
                            child: Text(_mode.hint,
                                style: TextStyle(
                                    fontSize: 13, color: mf.textMuted)),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Aussehen einer Karte.
class _NodeCard extends StatelessWidget {
  const _NodeCard({
    required this.node,
    required this.paper,
    required this.selected,
    required this.accent,
  });

  final CanvasNode node;
  final PaperStyle paper;
  final bool selected;
  final Color accent;

  static const textStyle = TextStyle(fontSize: 15, height: 1.35);

  @override
  Widget build(BuildContext context) {
    final darkPaper = paper.sheet.computeLuminance() < 0.3;
    final bg = darkPaper ? const Color(0xFF26262F) : Colors.white;
    final fg = darkPaper ? const Color(0xFFEDEDF2) : const Color(0xFF1C1C22);
    final empty = node.text.isEmpty;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: selected ? accent : paper.line,
          width: selected ? 2 : 1,
        ),
        boxShadow: const [
          BoxShadow(
              color: Color(0x26000000), blurRadius: 12, offset: Offset(0, 4)),
        ],
      ),
      child: Text(
        empty ? 'Doppeltippen zum Schreiben' : node.text,
        overflow: TextOverflow.fade,
        style: textStyle.copyWith(
          color: empty ? fg.withValues(alpha: 0.4) : fg,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

/// Zeichnet die Verbindungslinien zwischen Karten.
class _EdgePainter extends CustomPainter {
  _EdgePainter({
    required this.camera,
    required this.nodes,
    required this.edges,
    required this.color,
    this.pendingFrom,
    this.pendingTo,
  });

  final Camera camera;
  final Map<String, CanvasNode> nodes;
  final List<CanvasEdge> edges;
  final Color color;
  final CanvasNode? pendingFrom;
  final Offset? pendingTo;

  Rect _screenRect(CanvasNode n) {
    final p = camera.toScreen(Offset(n.x, n.y));
    return Rect.fromLTWH(p.dx, p.dy, n.w * camera.scale, n.h * camera.scale);
  }

  /// Punkt am Rand von [r] in Richtung [toward].
  static Offset _edgePoint(Rect r, Offset toward) {
    final c = r.center;
    final d = toward - c;
    if (d == Offset.zero) return c;
    final tx = d.dx == 0 ? double.infinity : (r.width / 2) / d.dx.abs();
    final ty = d.dy == 0 ? double.infinity : (r.height / 2) / d.dy.abs();
    final t = math.min(1.0, math.min(tx, ty));
    return c + d * t;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()
      ..color = color.withValues(alpha: 0.75)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    final dot = Paint()..color = color;

    for (final e in edges) {
      final a = nodes[e.fromId], b = nodes[e.toId];
      if (a == null || b == null) continue;
      final ra = _screenRect(a), rb = _screenRect(b);
      final p1 = _edgePoint(ra, rb.center);
      final p2 = _edgePoint(rb, ra.center);
      canvas.drawLine(p1, p2, line);
      canvas.drawCircle(p1, 3.5, dot);
      canvas.drawCircle(p2, 3.5, dot);
    }

    if (pendingFrom != null && pendingTo != null) {
      final to = camera.toScreen(pendingTo!);
      final from = _edgePoint(_screenRect(pendingFrom!), to);
      canvas.drawLine(
          from,
          to,
          Paint()
            ..color = color.withValues(alpha: 0.5)
            ..strokeWidth = 2
            ..strokeCap = StrokeCap.round);
      canvas.drawCircle(to, 5, dot);
    }
  }

  @override
  bool shouldRepaint(_EdgePainter old) => true;
}
