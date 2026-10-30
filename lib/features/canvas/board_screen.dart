import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/navigation.dart';
import '../../app/services.dart';
import '../../app/theme.dart';
import '../../data/models.dart';
import '../../ink/camera.dart';
import '../../ink/ink_canvas_view.dart';
import '../../ink/ink_controller.dart';
import '../../ink/ink_surface.dart';
import '../../ui/clean_menu.dart';
import '../../ui/color_picker.dart';
import '../../ui/editor_bar.dart';
import '../../ui/widgets.dart';
import '../common/create_dialogs.dart';
import '../common/object_info.dart';
import '../common/object_picker.dart';
import '../notebook/notebook_screen.dart';
import 'card_view.dart';
import 'edge_painter.dart';
import 'minimap.dart';

/// Die vier Arbeitsmodi des Canvas.
enum BoardMode {
  write('Schreiben', Icons.edit_outlined,
      'Mit Stift oder Maus schreiben und zeichnen. „T“ in der Leiste: Text.'),
  select('Auswählen', Icons.near_me_outlined,
      'Doppeltippen auf die Fläche: neue Karte · Doppeltippen auf eine Karte: '
          'schreiben · „+“ am Rand: verbundene Karte'),
  connect('Verbinden', Icons.timeline,
      'Von Karte zu Karte ziehen. Ins Leere ziehen: neue verbundene Karte. '
          'Verbindung antippen: Pfeil, Text, Farbe.'),
  navigate('Navigieren', Icons.open_with,
      'Fläche verschieben und zoomen, ohne etwas zu verändern.');

  const BoardMode(this.label, this.icon, this.hint);
  final String label;
  final IconData icon;
  final String hint;
}

/// Ein Stand aller Karten und Verbindungen (für Rückgängig).
class _Snapshot {
  _Snapshot(List<CanvasNode> nodes, List<CanvasEdge> edges)
      : nodes = [for (final n in nodes) n.copy()],
        edges = [for (final e in edges) e.copy()];

  final List<CanvasNode> nodes;
  final List<CanvasEdge> edges;
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
  String? _selectedEdge;
  InkController? _ink;
  Size _viewSize = Size.zero;
  final GlobalKey _layerKey = GlobalKey();
  bool _focused = false;
  bool _dragging = false;

  // Direkt-Bearbeitung einer Karte
  String? _editing;
  final TextEditingController _editCtrl = TextEditingController();
  final FocusNode _editFocus = FocusNode(debugLabel: 'card-editor');

  // Rückgängig für Karten (die Handschrift hat ihr eigenes)
  final List<_Snapshot> _undo = [];
  final List<_Snapshot> _redo = [];

  /// Kopierte Karten – gilt über alle Canvas-Flächen hinweg.
  static List<CanvasNode> _clipboard = const [];

  // Verbinden
  String? _connectFrom;
  Offset? _connectWorld;

  // Doppeltippen auf leere Fläche
  DateTime? _lastBgTap;
  Offset? _lastBgTapWorld;

  static const _grid = 20.0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_board != null) return;
    _s = Services.of(context);
    _board = _s.objects.get(widget.boardId);
    _s.objects.markOpened(widget.boardId);
    _load();
    if (widget.focusNodeId != null) _selected = widget.focusNodeId;
  }

  @override
  void dispose() {
    _saveEditing();
    _editCtrl.dispose();
    _editFocus.dispose();
    super.dispose();
  }

  void _load() {
    _nodes = _s.canvas.nodes(widget.boardId);
    _edges = _s.canvas.edges(widget.boardId);
  }

  bool get _snap => _board?.data['snap'] == true;

  CanvasNode? _node(String? id) {
    if (id == null) return null;
    for (final n in _nodes) {
      if (n.id == id) return n;
    }
    return null;
  }

  CanvasEdge? _edge(String? id) {
    if (id == null) return null;
    for (final e in _edges) {
      if (e.id == id) return e;
    }
    return null;
  }

  void _changed() => _s.objects.touch(widget.boardId);

  // --- Rückgängig ---------------------------------------------------------

  /// Merkt sich den Stand vor einer Änderung.
  void _record() {
    _undo.add(_Snapshot(_nodes, _edges));
    if (_undo.length > 80) _undo.removeAt(0);
    _redo.clear();
  }

  void _restore(_Snapshot snap) {
    _s.canvas.restoreState(widget.boardId, snap.nodes, snap.edges);
    _changed();
    setState(() {
      _editing = null;
      _selectedEdge = null;
      _load();
      if (_node(_selected) == null) _selected = null;
    });
  }

  void _undoCards() {
    _finishEditing();
    if (_undo.isEmpty) return;
    _redo.add(_Snapshot(_nodes, _edges));
    _restore(_undo.removeLast());
  }

  void _redoCards() {
    _finishEditing();
    if (_redo.isEmpty) return;
    _undo.add(_Snapshot(_nodes, _edges));
    _restore(_redo.removeLast());
  }

  // --- Modus --------------------------------------------------------------

  void _setMode(BoardMode m) {
    _finishEditing();
    _ink?.setDrawingEnabled(m == BoardMode.write);
    setState(() {
      _mode = m;
      if (m == BoardMode.write || m == BoardMode.navigate) {
        _selected = null;
        _selectedEdge = null;
      }
    });
  }

  void _select(String? id) {
    if (id != _editing) _finishEditing();
    setState(() {
      _selected = id;
      _selectedEdge = null;
    });
  }

  // --- Karten anlegen -----------------------------------------------------

  Offset _viewCenter() {
    final cam = _ink?.camera;
    if (cam == null || _viewSize.isEmpty) return Offset.zero;
    return cam.toWorld(Offset(_viewSize.width / 2, _viewSize.height / 2));
  }

  static Size _defaultSize(CardKind k) => switch (k) {
        CardKind.card => const Size(240, 96),
        CardKind.sticky => const Size(200, 200),
        CardKind.heading => const Size(360, 56),
        CardKind.pill => const Size(200, 56),
        CardKind.circle => const Size(200, 200),
      };

  double _snapV(double v) => _snap ? (v / _grid).roundToDouble() * _grid : v;

  CanvasNode _createCard({
    required Offset center,
    CardKind kind = CardKind.card,
    int? color,
    CardTextSize? size,
    String text = '',
  }) {
    final sz = _defaultSize(kind);
    final data = <String, dynamic>{
      'kind': kind.name,
      'z': _nodes.isEmpty ? 0.0 : _nodes.last.z + 1,
      if (size != null) 'size': size.name,
    };
    final n = _s.canvas.createNode(
      widget.boardId,
      x: _snapV(center.dx - sz.width / 2),
      y: _snapV(center.dy - sz.height / 2),
      w: sz.width,
      h: sz.height,
      text: text,
      color: color,
      data: data,
    );
    n.h = math.max(sz.height, measureCardHeight(n));
    _s.canvas.updateNode(n);
    return n;
  }

  Future<void> _addCard({Offset? at, CardKind kind = CardKind.card}) async {
    _record();
    final center = at ??
        _viewCenter() +
            Offset((_nodes.length % 5) * 22.0, (_nodes.length % 5) * 22.0);
    final n = _createCard(center: center, kind: kind);
    _changed();
    _ink?.setDrawingEnabled(false);
    setState(() {
      _nodes.add(n);
      _selected = n.id;
      _selectedEdge = null;
      if (_mode == BoardMode.write || _mode == BoardMode.navigate) {
        _mode = BoardMode.select;
      }
    });
    _startEditing(n);
  }

  /// „+“ am Rand: neue Karte in diese Richtung, gleich verbunden.
  void _quickAdd(CanvasNode from, Offset dir) {
    _record();
    final kind = from.kind == CardKind.heading || from.kind == CardKind.circle
        ? CardKind.card
        : from.kind;
    final sz = _defaultSize(kind);
    const gap = 90.0;
    final c = from.rect.center +
        Offset(dir.dx * (from.w / 2 + gap + sz.width / 2),
            dir.dy * (from.h / 2 + gap + sz.height / 2));
    final n = _createCard(
      center: _freeSpot(c, sz, dir),
      kind: kind,
      color: from.color,
    );
    final e = _s.canvas.createEdge(widget.boardId, from.id, n.id,
        data: {'arrow': EdgeArrow.end.name});
    _changed();
    setState(() {
      _nodes.add(n);
      if (e != null) _edges.add(e);
      _selected = n.id;
      _selectedEdge = null;
    });
    _startEditing(n);
    _ensureVisible(n);
  }

  /// Schiebt eine neue Karte weiter, bis sie keine andere überdeckt.
  Offset _freeSpot(Offset center, Size sz, Offset dir) {
    var c = center;
    final step = dir.dx != 0
        ? Offset(0, sz.height + 24)
        : Offset(sz.width + 24, 0);
    for (var i = 0; i < 12; i++) {
      final r = Rect.fromCenter(center: c, width: sz.width, height: sz.height)
          .inflate(12);
      if (!_nodes.any((n) => n.rect.overlaps(r))) return c;
      c += step;
    }
    return c;
  }

  void _ensureVisible(CanvasNode n) {
    final cam = _ink?.camera;
    if (cam == null || _viewSize.isEmpty) return;
    final view = cam.visibleWorldRect(_viewSize).deflate(40 / cam.scale);
    if (view.contains(n.rect.topLeft) && view.contains(n.rect.bottomRight)) {
      return;
    }
    cam.lookAt(n.rect.center, cam.scale, _viewSize);
  }

  /// Verweis auf ein anderes Objekt (Wissenseintrag, PDF, Notizbuch …).
  Future<void> _addReference() async {
    _finishEditing();
    final o = await pickObject(context,
        title: 'Was soll auf den Canvas?', exclude: {widget.boardId});
    if (o == null || !mounted) return;
    _record();
    final n = _createCard(
        center: _viewCenter() +
            Offset((_nodes.length % 5) * 22.0, (_nodes.length % 5) * 22.0),
        text: describeTitle(_s.objects, o));
    n.refObjectId = o.id;
    n.h = 84;
    _s.canvas.updateNode(n);
    _s.objects.linkOnce(o.id, widget.boardId, type: 'canvas');
    _changed();
    _ink?.setDrawingEnabled(false);
    setState(() {
      _nodes.add(n);
      _selected = n.id;
      _mode = BoardMode.select;
    });
  }

  // --- Direkt-Bearbeitung -------------------------------------------------

  void _startEditing(CanvasNode n) {
    if (n.refObjectId != null) return;
    if (_editing == n.id) return;
    _finishEditing();
    _record();
    _editCtrl.text = n.text;
    _editCtrl.selection = TextSelection.collapsed(offset: n.text.length);
    setState(() {
      _editing = n.id;
      _selected = n.id;
      _selectedEdge = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _editing == n.id) _editFocus.requestFocus();
    });
  }

  void _onEditChanged(String v) {
    final n = _node(_editing);
    if (n == null) return;
    setState(() {
      n.text = v;
      _fitHeight(n);
    });
    _s.canvas.updateNode(n);
  }

  void _fitHeight(CanvasNode n) {
    final need = measureCardHeight(n);
    n.h = n.fixedHeight ? math.max(n.h, need) : need;
  }

  void _saveEditing() {
    final n = _node(_editing);
    if (n == null) return;
    n.text = _editCtrl.text.trimRight();
    _fitHeight(n);
    _s.canvas.updateNode(n);
  }

  void _finishEditing() {
    if (_editing == null) return;
    _saveEditing();
    _changed();
    _editFocus.unfocus(
          disposition: UnfocusDisposition.previouslyFocusedChild);
    if (mounted) setState(() => _editing = null);
  }

  // --- Karten ändern ------------------------------------------------------

  void _update(CanvasNode n, void Function() change, {bool refit = true}) {
    _record();
    setState(() {
      change();
      if (refit) _fitHeight(n);
    });
    _s.canvas.updateNode(n);
    _changed();
  }

  void _setKind(CanvasNode n, CardKind k) {
    _update(n, () {
      final wasAuto = !n.fixedHeight;
      n.kind = k;
      n.data.remove('center');
      n.data.remove('size');
      final sz = _defaultSize(k);
      final c = n.rect.center;
      n.w = sz.width;
      if (k == CardKind.circle || k == CardKind.sticky) {
        n.h = sz.height;
        n.fixedHeight = false;
      } else if (wasAuto) {
        n.h = sz.height;
      }
      n.x = c.dx - n.w / 2;
      n.y = c.dy - sz.height / 2;
    });
  }

  void _toggleTask(CanvasNode n, int line) =>
      _update(n, () => n.text = CardLine.toggle(n.text, line));

  void _duplicate(CanvasNode n) {
    _record();
    final copy = n.copy(id: _s.canvas.newId(), dx: 32, dy: 32)
      ..z = _nodes.last.z + 1;
    _s.canvas.insertNode(copy);
    _changed();
    setState(() {
      _nodes.add(copy);
      _selected = copy.id;
    });
  }

  void _copy(CanvasNode n) {
    _clipboard = [n.copy()];
    ScaffoldMessenger.maybeOf(context)?.hideCurrentSnackBar();
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(const SnackBar(
        duration: Duration(seconds: 2),
        content: Text('Karte kopiert – Strg/⌘ + V fügt sie ein, '
            'auch auf einem anderen Canvas.')));
  }

  void _paste() {
    if (_clipboard.isEmpty) return;
    _record();
    final c = _viewCenter();
    final added = <CanvasNode>[];
    for (final src in _clipboard) {
      final n = src.copy(
          id: _s.canvas.newId(),
          dx: c.dx - src.rect.center.dx,
          dy: c.dy - src.rect.center.dy);
      final moved = CanvasNode(
        id: n.id,
        boardId: widget.boardId,
        x: n.x,
        y: n.y,
        w: n.w,
        h: n.h,
        text: n.text,
        color: n.color,
        refObjectId: n.refObjectId,
        data: n.data,
      )..z = (_nodes.isEmpty ? 0.0 : _nodes.last.z) + 1 + added.length;
      _s.canvas.insertNode(moved);
      added.add(moved);
    }
    _changed();
    if (_mode != BoardMode.select) _setMode(BoardMode.select);
    setState(() {
      _nodes.addAll(added);
      _selected = added.last.id;
    });
  }

  void _toFront(CanvasNode n) {
    _update(n, () {
      n.z = (_nodes.isEmpty ? 0.0 : _nodes.map((m) => m.z).reduce(math.max)) + 1;
      _nodes
        ..remove(n)
        ..add(n);
    }, refit: false);
  }

  void _toBack(CanvasNode n) {
    _update(n, () {
      n.z = (_nodes.isEmpty ? 0.0 : _nodes.map((m) => m.z).reduce(math.min)) - 1;
      _nodes
        ..remove(n)
        ..insert(0, n);
    }, refit: false);
  }

  void _deleteSelected() {
    final edge = _edge(_selectedEdge);
    if (edge != null) {
      _deleteEdge(edge);
      return;
    }
    final node = _node(_selected);
    if (node == null) return;
    _record();
    if (_editing == node.id) {
      _editFocus.unfocus(
          disposition: UnfocusDisposition.previouslyFocusedChild);
      _editing = null;
    }
    _s.canvas.deleteNode(node.id);
    _changed();
    setState(() {
      _nodes.removeWhere((n) => n.id == node.id);
      _edges.removeWhere((e) => e.fromId == node.id || e.toId == node.id);
      _selected = null;
    });
    ScaffoldMessenger.maybeOf(context)?.hideCurrentSnackBar();
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
      content: const Text('Karte gelöscht'),
      action: SnackBarAction(label: 'Rückgängig', onPressed: _undoCards),
    ));
  }

  /// Karte in einen Wissenseintrag verwandeln (bleibt als Verweis liegen).
  Future<void> _toKnowledge(CanvasNode n) async {
    _finishEditing();
    final lines = n.text.trim().split('\n');
    final title = lines.first.replaceFirst(RegExp(r'^\[( |x|X)\]\s?'), '').trim();
    if (title.isEmpty) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(const SnackBar(
          content: Text('Schreib zuerst etwas auf die Karte.')));
      return;
    }
    final entry = _s.objects.create(
      type: ObjectType.knowledge,
      title: title,
      data: {
        'body': lines.skip(1).join('\n').trim(),
        'tags': <String>[],
      },
    );
    _s.objects.linkOnce(entry.id, widget.boardId, type: 'canvas');
    _update(n, () {
      n.refObjectId = entry.id;
      n.text = title;
      n.h = math.max(84.0, n.h);
    }, refit: false);
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
      content: Text('Wissenseintrag „$title“ erstellt'),
      action: SnackBarAction(
          label: 'Öffnen', onPressed: () => openObject(context, entry)),
    ));
  }

  Future<void> _linkObject(CanvasNode n) async {
    final o = await pickObject(context,
        title: 'Karte verknüpfen mit …', exclude: {widget.boardId});
    if (o == null || !mounted) return;
    _s.objects.linkOnce(o.id, widget.boardId, type: 'canvas');
    _update(n, () {
      n.refObjectId = o.id;
      n.text = describeTitle(_s.objects, o);
      n.h = math.max(84.0, n.h);
    }, refit: false);
  }

  /// Doppeltippen: Verweis-Karten öffnen ihr Ziel, normale Karten den Text.
  Future<void> _openNode(CanvasNode n) async {
    final ref = n.refObjectId;
    if (ref != null) {
      final o = _s.objects.get(ref);
      if (o != null && o.deletedAt == null) {
        await openObject(context, o);
        if (mounted) setState(() {}); // Titel könnte sich geändert haben
        return;
      }
    }
    _startEditing(n);
  }

  // --- Verbindungen -------------------------------------------------------

  void _connect(String from, Offset at) {
    CanvasNode? target;
    for (final m in _nodes.reversed) {
      if (m.id != from && m.rect.inflate(6).contains(at)) {
        target = m;
        break;
      }
    }
    final source = _node(from);
    if (source == null) return;
    _record();
    if (target == null) {
      // Ins Leere gezogen: neue Karte dort, gleich verbunden.
      final n = _createCard(
          center: at,
          kind: source.kind == CardKind.heading || source.kind == CardKind.circle
              ? CardKind.card
              : source.kind,
          color: source.color);
      final e = _s.canvas.createEdge(widget.boardId, from, n.id,
          data: {'arrow': EdgeArrow.end.name});
      _changed();
      setState(() {
        _nodes.add(n);
        if (e != null) _edges.add(e);
        _selected = n.id;
      });
      _startEditing(n);
      return;
    }
    final t = target;
    final edge = _s.canvas.createEdge(widget.boardId, from, t.id,
        data: {'arrow': EdgeArrow.end.name});
    if (edge != null) {
      setState(() {
        _edges.add(edge);
        _selectedEdge = edge.id;
        _selected = null;
      });
      // Verweisen beide Karten auf Objekte, werden auch diese verknüpft.
      final a = source.refObjectId, b = t.refObjectId;
      if (a != null && b != null) _s.objects.linkOnce(a, b, type: 'canvas');
    } else {
      // Gab es schon – dann lösen wir sie.
      bool same(CanvasEdge e) =>
          (e.fromId == from && e.toId == t.id) ||
          (e.fromId == t.id && e.toId == from);
      for (final e in _edges.where(same).toList()) {
        _s.canvas.deleteEdge(e.id);
      }
      setState(() => _edges.removeWhere(same));
    }
    _changed();
  }

  void _updateEdge(CanvasEdge e, void Function() change) {
    _record();
    setState(change);
    _s.canvas.updateEdge(e);
    _changed();
  }

  void _deleteEdge(CanvasEdge e) {
    _record();
    _s.canvas.deleteEdge(e.id);
    _changed();
    setState(() {
      _edges.removeWhere((x) => x.id == e.id);
      _selectedEdge = null;
    });
  }

  Future<void> _editEdgeLabel(CanvasEdge e) async {
    final text = await askText(context,
        title: 'Beschriftung der Verbindung',
        initial: e.label ?? '',
        hint: 'z. B. „gehört zu“, „führt zu“, „Beispiel“');
    if (text == null || !mounted) return;
    _updateEdge(e, () => e.label = text.trim().isEmpty ? null : text.trim());
  }

  void _reverseEdge(CanvasEdge e) {
    _record();
    _s.canvas.deleteEdge(e.id);
    final again = _s.canvas.createEdge(widget.boardId, e.toId, e.fromId,
        data: Map<String, dynamic>.of(e.data));
    if (again != null) {
      again.label = e.label;
      _s.canvas.updateEdge(again);
    }
    _changed();
    setState(() {
      _edges.removeWhere((x) => x.id == e.id);
      if (again != null) {
        _edges.add(again);
        _selectedEdge = again.id;
      } else {
        _selectedEdge = null;
      }
    });
  }

  // --- Gesten -------------------------------------------------------------

  Offset? _toWorld(Offset global) {
    final box = _layerKey.currentContext?.findRenderObject() as RenderBox?;
    final cam = _ink?.camera;
    if (box == null || cam == null) return null;
    return cam.toWorld(box.globalToLocal(global));
  }

  void _panStart(CanvasNode n, DragStartDetails d) {
    if (_editing != null && _editing != n.id) _finishEditing();
    if (_mode == BoardMode.select) _record();
    setState(() {
      _selected = n.id;
      _selectedEdge = null;
      _dragging = true;
      if (_mode == BoardMode.connect) {
        _connectFrom = n.id;
        _connectWorld = _toWorld(d.globalPosition);
      }
    });
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
    setState(() => _dragging = false);
    if (_mode == BoardMode.select) {
      setState(() {
        n.x = _snapV(n.x);
        n.y = _snapV(n.y);
      });
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
    if (from != null && at != null) _connect(from, at);
  }

  // Verbinden über die „+“-Griffe (auch im Auswahlmodus)
  void _handleDragStart(CanvasNode n, DragStartDetails d) {
    _finishEditing();
    setState(() {
      _connectFrom = n.id;
      _connectWorld = _toWorld(d.globalPosition);
      _dragging = true;
    });
  }

  void _handleDragUpdate(DragUpdateDetails d) =>
      setState(() => _connectWorld = _toWorld(d.globalPosition));

  void _handleDragEnd() {
    final from = _connectFrom, at = _connectWorld;
    setState(() {
      _connectFrom = null;
      _connectWorld = null;
      _dragging = false;
    });
    if (from == null || at == null) return;
    final src = _node(from);
    // Kaum bewegt: das war ein Tippen auf „+“.
    if (src != null && src.rect.inflate(30).contains(at)) return;
    _connect(from, at);
  }

  // Größe ändern (Griff unten rechts)
  void _resizeStart() {
    _record();
    setState(() => _dragging = true);
  }

  void _resizeUpdate(CanvasNode n, DragUpdateDetails d) {
    final cam = _ink?.camera;
    if (cam == null) return;
    setState(() {
      n.w = math.max(80.0, n.w + d.delta.dx / cam.scale);
      n.h = math.max(44.0, n.h + d.delta.dy / cam.scale);
      n.fixedHeight = true;
    });
  }

  void _resizeEnd(CanvasNode n) {
    setState(() {
      _dragging = false;
      n.w = _snap ? math.max(_grid * 4, _snapV(n.w)) : n.w;
      n.h = math.max(n.h, measureCardHeight(n));
    });
    _s.canvas.updateNode(n);
    _changed();
  }

  void _onBackgroundTap(Offset world) {
    if (_editing != null) {
      _finishEditing();
      return;
    }
    final cam = _ink?.camera;
    if (cam != null &&
        (_mode == BoardMode.select || _mode == BoardMode.connect)) {
      final hit = hitEdge(cam.toScreen(world), cam,
          {for (final n in _nodes) n.id: n}, _edges);
      if (hit != null) {
        setState(() {
          _selectedEdge = hit.id;
          _selected = null;
        });
        return;
      }
    }
    final now = DateTime.now();
    final isDouble = _lastBgTap != null &&
        now.difference(_lastBgTap!) < const Duration(milliseconds: 380) &&
        _lastBgTapWorld != null &&
        (_lastBgTapWorld! - world).distance * (cam?.scale ?? 1) < 24;
    _lastBgTap = now;
    _lastBgTapWorld = world;
    if (isDouble && _mode == BoardMode.select) {
      _lastBgTap = null;
      _addCard(at: world);
      return;
    }
    if (_selected != null || _selectedEdge != null) {
      setState(() {
        _selected = null;
        _selectedEdge = null;
      });
    }
  }

  // --- Tastatur -----------------------------------------------------------

  bool get _typing {
    final f = FocusManager.instance.primaryFocus;
    return f != null &&
        f.context?.findAncestorStateOfType<EditableTextState>() != null;
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = e.logicalKey;
    if (_typing) {
      if (key == LogicalKeyboardKey.escape && _editing != null) {
        _finishEditing();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    if (_mode == BoardMode.write) return KeyEventResult.ignored;
    final hw = HardwareKeyboard.instance;
    final ctrl = hw.isControlPressed || hw.isMetaPressed;
    final n = _node(_selected);
    if (ctrl) {
      if (key == LogicalKeyboardKey.keyZ) {
        hw.isShiftPressed ? _redoCards() : _undoCards();
      } else if (key == LogicalKeyboardKey.keyY) {
        _redoCards();
      } else if (key == LogicalKeyboardKey.keyC && n != null) {
        _copy(n);
      } else if (key == LogicalKeyboardKey.keyX && n != null) {
        _copy(n);
        _deleteSelected();
      } else if (key == LogicalKeyboardKey.keyV) {
        _paste();
      } else if (key == LogicalKeyboardKey.keyD && n != null) {
        _duplicate(n);
      } else {
        return KeyEventResult.ignored;
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.delete ||
        key == LogicalKeyboardKey.backspace) {
      _deleteSelected();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape) {
      _select(null);
      return KeyEventResult.handled;
    }
    if (n == null) return KeyEventResult.ignored;
    if (key == LogicalKeyboardKey.enter) {
      _openNode(n);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.tab) {
      _quickAdd(n, hw.isShiftPressed ? const Offset(0, 1) : const Offset(1, 0));
      return KeyEventResult.handled;
    }
    final step = hw.isShiftPressed ? 1.0 : (_snap ? _grid : 10.0);
    final move = {
      LogicalKeyboardKey.arrowLeft: Offset(-step, 0),
      LogicalKeyboardKey.arrowRight: Offset(step, 0),
      LogicalKeyboardKey.arrowUp: Offset(0, -step),
      LogicalKeyboardKey.arrowDown: Offset(0, step),
    }[key];
    if (move != null) {
      _update(n, () {
        n.x += move.dx;
        n.y += move.dy;
      }, refit: false);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  // --- Oberfläche ---------------------------------------------------------

  GlobalKey<InkSurfaceState> _surfaceKey = GlobalKey();

  /// Titel und Hintergrund ändern (auch nachträglich).
  Future<void> _rename() async {
    _finishEditing();
    await _surfaceKey.currentState?.flush();
    if (!mounted) return;
    final before = _board!;
    await editBoard(context, before);
    if (!mounted) return;
    final after = _s.objects.get(widget.boardId);
    setState(() {
      _board = after;
      if (after != null && after.paper != before.paper) {
        _surfaceKey = GlobalKey();
      }
    });
  }

  void _toggleSnap() {
    final b = _s.objects.get(widget.boardId);
    if (b == null) return;
    _s.objects.setData(b.id, {...b.data, 'snap': !_snap});
    setState(() => _board = _s.objects.get(widget.boardId));
  }

  ({IconData icon, String type, String title})? _refInfo(CanvasNode n) {
    final id = n.refObjectId;
    if (id == null) return null;
    final o = _s.objects.get(id);
    if (o == null || o.deletedAt != null) {
      return (icon: Icons.link_off, type: 'Nicht mehr vorhanden', title: n.text);
    }
    return (
      icon: iconFor(o.type),
      type: typeLabel(o.type),
      title: describeTitle(_s.objects, o),
    );
  }

  Widget _overlay(BuildContext context, InkController c, PaperStyle paper) {
    return LayoutBuilder(builder: (context, constraints) {
      _viewSize = constraints.biggest;
      if (!_focused && widget.focusNodeId != null) {
        _focused = true;
        final n = _node(widget.focusNodeId!);
        if (n != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            c.camera.lookAt(n.rect.center, 1.0, _viewSize);
          });
        }
      }
      final interactive =
          _mode == BoardMode.select || _mode == BoardMode.connect;
      final mf = context.mf;
      return ListenableBuilder(
        listenable: c.camera,
        builder: (context, _) {
          final cam = c.camera;
          final visible = cam.visibleWorldRect(_viewSize).inflate(80);
          final byId = {for (final n in _nodes) n.id: n};
          final sel = interactive ? _node(_selected) : null;
          final selEdge = interactive ? _edge(_selectedEdge) : null;
          return IgnorePointer(
            ignoring: !interactive,
            child: Stack(
              key: _layerKey,
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(
                      painter: EdgePainter(
                        camera: cam,
                        nodes: byId,
                        edges: _edges,
                        accent: mf.accent,
                        labelFill: paper.sheet,
                        labelText: paper.sheet.computeLuminance() < 0.3
                            ? const Color(0xFFF2F2F7)
                            : const Color(0xFF16161D),
                        selectedEdge: _selectedEdge,
                        pendingFrom:
                            _connectFrom == null ? null : byId[_connectFrom!],
                        pendingTo: _connectWorld,
                      ),
                    ),
                  ),
                ),
                for (final n in _nodes)
                  if (n.rect.overlaps(visible)) _positionedNode(n, cam, paper),
                if (sel != null && !_dragging) ..._handles(sel, cam),
                if (sel != null && !_dragging)
                  _cardToolbar(context, sel, cam),
                if (selEdge != null) _edgeToolbar(context, selEdge, cam, byId),
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
    final editing = _editing == n.id;
    final colors = CardColors.of(n, paper);
    final selectMode = _mode == BoardMode.select;
    return Positioned(
      key: ValueKey(n.id),
      left: p.dx,
      top: p.dy,
      width: n.w * s,
      height: n.h * s,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: editing ? null : () => _select(n.id),
        onDoubleTap: selectMode && !editing ? () => _openNode(n) : null,
        onPanStart: editing ? null : (d) => _panStart(n, d),
        onPanUpdate: editing ? null : (d) => _panUpdate(n, d),
        onPanEnd: editing ? null : (_) => _panEnd(n),
        child: FittedBox(
          fit: BoxFit.fill,
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: n.w,
            height: n.h,
            child: CanvasCardView(
              node: n,
              paper: paper,
              selected: n.id == _selected && _mode != BoardMode.write,
              reference: _refInfo(n),
              onToggleTask: selectMode ? (i) => _toggleTask(n, i) : null,
              editor: editing
                  ? TextField(
                      controller: _editCtrl,
                      focusNode: _editFocus,
                      maxLines: null,
                      textAlign:
                          n.centered ? TextAlign.center : TextAlign.left,
                      style: cardTextStyle(n, colors.text),
                      cursorColor: context.mf.accent,
                      keyboardType: TextInputType.multiline,
                      textCapitalization: TextCapitalization.sentences,
                      onTapOutside: (_) {},
                      onChanged: _onEditChanged,
                      decoration: InputDecoration.collapsed(
                        hintText: 'Schreib los …',
                        hintStyle: cardTextStyle(
                            n, colors.text.withValues(alpha: 0.4)),
                      ),
                    )
                  : null,
            ),
          ),
        ),
      ),
    );
  }

  /// „+“-Griffe an allen vier Seiten und der Größen-Griff unten rechts.
  List<Widget> _handles(CanvasNode n, Camera cam) {
    final r = screenRectOf(n, cam);
    final mf = context.mf;
    Widget plus(Offset center, Offset dir, String tip) => Positioned(
          left: center.dx - 15,
          top: center.dy - 15,
          child: Tooltip(
            message: tip,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _quickAdd(n, dir),
              onPanStart: (d) => _handleDragStart(n, d),
              onPanUpdate: _handleDragUpdate,
              onPanEnd: (_) => _handleDragEnd(),
              child: Container(
                width: 30,
                height: 30,
                alignment: Alignment.center,
                child: Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    gradient: mf.gradient,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 1.5),
                    boxShadow: [BoxShadow(color: mf.glow, blurRadius: 10)],
                  ),
                  child: const Icon(Icons.add_rounded,
                      size: 15, color: Colors.white),
                ),
              ),
            ),
          ),
        );
    const off = 20.0;
    return [
      plus(Offset(r.right + off, r.center.dy), const Offset(1, 0),
          'Verbundene Karte rechts (Tab) – oder ziehen'),
      plus(Offset(r.center.dx, r.bottom + off), const Offset(0, 1),
          'Verbundene Karte darunter – oder ziehen'),
      plus(Offset(r.left - off, r.center.dy), const Offset(-1, 0),
          'Verbundene Karte links – oder ziehen'),
      plus(Offset(r.center.dx, r.top - off), const Offset(0, -1),
          'Verbundene Karte darüber – oder ziehen'),
      Positioned(
        left: r.right - 13,
        top: r.bottom - 13,
        child: Tooltip(
          message: 'Größe ändern',
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanStart: (_) => _resizeStart(),
            onPanUpdate: (d) => _resizeUpdate(n, d),
            onPanEnd: (_) => _resizeEnd(n),
            child: MouseRegion(
              cursor: SystemMouseCursors.resizeDownRight,
              child: SizedBox(
                width: 26,
                height: 26,
                child: Center(
                  child: Container(
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: mf.accent, width: 2),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ];
  }

  /// Schwebende Leiste über der gewählten Karte.
  Widget _cardToolbar(BuildContext context, CanvasNode n, Camera cam) {
    final r = screenRectOf(n, cam);
    final isRef = n.refObjectId != null;
    final editing = _editing == n.id;
    final items = <Widget>[
      if (!isRef)
        _TbButton(
          icon: editing ? Icons.check_rounded : Icons.edit_rounded,
          tooltip: editing ? 'Fertig (Esc)' : 'Schreiben (Enter)',
          active: editing,
          onTap: editing ? _finishEditing : () => _startEditing(n),
        )
      else
        _TbButton(
          icon: Icons.open_in_new_rounded,
          tooltip: 'Öffnen',
          onTap: () => _openNode(n),
        ),
      _ColorButton(
        color: n.color,
        onPick: (c) => _update(n, () => n.color = c, refit: false),
      ),
      CleanMenuButton(
        tooltip: 'Kartenart',
        trigger: _TbIcon(icon: _kindIcon(n.kind)),
        entries: [
          for (final k in CardKind.values)
            CleanMenuEntry(k.name, k.label,
                icon: _kindIcon(k), subtitle: k.hint, checked: n.kind == k),
        ],
        onSelected: (v) => _setKind(
            n, CardKind.values.firstWhere((k) => k.name == v)),
      ),
      if (!isRef) ...[
        CleanMenuButton(
          tooltip: 'Schriftgröße',
          trigger: const _TbIcon(icon: Icons.format_size_rounded),
          entries: [
            for (final t in CardTextSize.values)
              CleanMenuEntry(t.name, 'Größe ${t.label}',
                  icon: Icons.text_fields_rounded, checked: n.textSize == t),
          ],
          onSelected: (v) => _update(n,
              () => n.textSize = CardTextSize.values.firstWhere((t) => t.name == v)),
        ),
        _TbButton(
          icon: Icons.format_bold_rounded,
          tooltip: 'Fett',
          active: n.bold,
          onTap: () => _update(n, () => n.bold = !n.bold),
        ),
        _TbButton(
          icon: n.centered
              ? Icons.format_align_center_rounded
              : Icons.format_align_left_rounded,
          tooltip: n.centered ? 'Linksbündig' : 'Zentriert',
          onTap: () => _update(n, () => n.centered = !n.centered),
        ),
        _TbButton(
          icon: Icons.checklist_rounded,
          tooltip: 'Als Aufgabenliste (abhaken)',
          active: CardLine.hasTasks(n.text),
          onTap: () {
            final wasEditing = editing;
            if (wasEditing) _finishEditing();
            _update(n, () => n.text = CardLine.toggleAll(n.text));
          },
        ),
      ],
      const _TbDivider(),
      _TbButton(
        icon: Icons.copy_all_rounded,
        tooltip: 'Duplizieren (Strg/⌘ + D)',
        onTap: () => _duplicate(n),
      ),
      CleanMenuButton(
        tooltip: 'Mehr',
        trigger: const _TbIcon(icon: Icons.more_horiz_rounded),
        entries: [
          const CleanMenuEntry('copy', 'Kopieren',
              icon: Icons.content_copy_rounded,
              subtitle: 'Auch auf anderen Canvas einfügbar'),
          if (!isRef)
            const CleanMenuEntry('knowledge', 'Als Wissenseintrag',
                icon: Icons.hub_outlined,
                subtitle: 'Karte wird zum Verweis darauf'),
          CleanMenuEntry('link', isRef ? 'Anderes Ziel wählen' : 'Verknüpfen mit …',
              icon: Icons.add_link_rounded),
          if (isRef)
            const CleanMenuEntry('unlink', 'Verweis lösen',
                icon: Icons.link_off_rounded),
          const CleanMenuEntry.divider(),
          const CleanMenuEntry('front', 'Nach vorne',
              icon: Icons.flip_to_front_rounded),
          const CleanMenuEntry('back', 'Nach hinten',
              icon: Icons.flip_to_back_rounded),
          if (n.fixedHeight)
            const CleanMenuEntry('auto', 'Höhe automatisch',
                icon: Icons.height_rounded),
          const CleanMenuEntry.divider(),
          const CleanMenuEntry('delete', 'Löschen',
              icon: Icons.delete_outline, destructive: true),
        ],
        onSelected: (v) {
          switch (v) {
            case 'copy':
              _copy(n);
            case 'knowledge':
              _toKnowledge(n);
            case 'link':
              _linkObject(n);
            case 'unlink':
              _update(n, () => n.refObjectId = null);
            case 'front':
              _toFront(n);
            case 'back':
              _toBack(n);
            case 'auto':
              _update(n, () => n.fixedHeight = false);
            case 'delete':
              _deleteSelected();
          }
        },
      ),
    ];
    return _FloatingBar(
      anchor: r,
      view: _viewSize,
      children: items,
    );
  }

  Widget _edgeToolbar(BuildContext context, CanvasEdge e, Camera cam,
      Map<String, CanvasNode> byId) {
    final a = byId[e.fromId], b = byId[e.toId];
    if (a == null || b == null) return const SizedBox.shrink();
    final mid = EdgeGeometry.between(screenRectOf(a, cam), screenRectOf(b, cam))
        .middle;
    return _FloatingBar(
      anchor: Rect.fromCenter(center: mid, width: 2, height: 2),
      view: _viewSize,
      children: [
        CleanMenuButton(
          tooltip: 'Pfeil',
          trigger: _TbIcon(icon: _arrowIcon(e.arrow)),
          entries: [
            for (final arrow in EdgeArrow.values)
              CleanMenuEntry(arrow.name, arrow.label,
                  icon: _arrowIcon(arrow), checked: e.arrow == arrow),
          ],
          onSelected: (v) => _updateEdge(
              e, () => e.arrow = EdgeArrow.values.firstWhere((x) => x.name == v)),
        ),
        _TbButton(
          icon: Icons.more_horiz_rounded,
          tooltip: e.dashed ? 'Durchgezogen' : 'Gestrichelt',
          active: e.dashed,
          onTap: () => _updateEdge(e, () => e.dashed = !e.dashed),
        ),
        _ColorButton(
          color: e.color,
          onPick: (c) => _updateEdge(e, () => e.color = c),
        ),
        _TbButton(
          icon: Icons.short_text_rounded,
          tooltip: 'Beschriften',
          active: (e.label ?? '').isNotEmpty,
          onTap: () => _editEdgeLabel(e),
        ),
        _TbButton(
          icon: Icons.swap_horiz_rounded,
          tooltip: 'Richtung umdrehen',
          onTap: () => _reverseEdge(e),
        ),
        const _TbDivider(),
        _TbButton(
          icon: Icons.delete_outline_rounded,
          tooltip: 'Verbindung löschen',
          danger: true,
          onTap: () => _deleteEdge(e),
        ),
      ],
    );
  }

  static IconData _kindIcon(CardKind k) => switch (k) {
        CardKind.card => Icons.crop_landscape_rounded,
        CardKind.sticky => Icons.sticky_note_2_outlined,
        CardKind.heading => Icons.title_rounded,
        CardKind.pill => Icons.smart_button_outlined,
        CardKind.circle => Icons.circle_outlined,
      };

  static IconData _arrowIcon(EdgeArrow a) => switch (a) {
        EdgeArrow.none => Icons.horizontal_rule_rounded,
        EdgeArrow.end => Icons.arrow_right_alt_rounded,
        EdgeArrow.both => Icons.sync_alt_rounded,
      };

  Widget _nav(BuildContext context, InkController c) {
    final board = _board!;
    final write = _mode == BoardMode.write;
    return EditorNavBar(
      icon: Icons.bubble_chart_rounded,
      title: board.displayTitle,
      subtitle: '${_nodes.length} ${_nodes.length == 1 ? 'Karte' : 'Karten'}',
      onTitleTap: _rename,
      center: _ModeSwitch(mode: _mode, onChanged: _setMode),
      actions: [
        NavGroup(children: [
          CleanMenuButton(
            tooltip: 'Neue Karte',
            icon: Icons.add_box_outlined,
            entries: [
              for (final k in CardKind.values)
                CleanMenuEntry(k.name, k.label,
                    icon: _kindIcon(k), subtitle: k.hint),
              const CleanMenuEntry.divider(),
              const CleanMenuEntry('ref', 'Verweis einfügen',
                  icon: Icons.add_link_rounded,
                  subtitle: 'Wissen, PDF, Notizbuch, Seite'),
              if (_clipboard.isNotEmpty)
                const CleanMenuEntry('paste', 'Karte einfügen',
                    icon: Icons.content_paste_rounded),
            ],
            onSelected: (v) {
              if (v == 'ref') {
                _addReference();
              } else if (v == 'paste') {
                _paste();
              } else {
                _addCard(kind: CardKind.values.firstWhere((k) => k.name == v));
              }
            },
          ),
        ]),
        NavGroup(children: [
          if (write)
            UndoRedoButtons(controller: c)
          else ...[
            NavIconButton(
              icon: Icons.undo_rounded,
              tooltip: 'Rückgängig (Strg/⌘ + Z)',
              onTap: _undo.isEmpty ? null : _undoCards,
            ),
            NavIconButton(
              icon: Icons.redo_rounded,
              tooltip: 'Wiederholen',
              onTap: _redo.isEmpty ? null : _redoCards,
            ),
          ],
        ]),
        NavGroup(children: [
          ZoomPill(
              camera: c.camera, onFit: _fitAll, fitLabel: 'Alles zeigen'),
        ]),
        if (write) StylusToggle(controller: c),
        EditorMoreMenu(
          entries: [
            const CleanMenuEntry('fit', 'Alles zeigen',
                icon: Icons.fit_screen_outlined),
            CleanMenuEntry('snap', 'Am Raster ausrichten',
                icon: Icons.grid_4x4_rounded, checked: _snap),
            const CleanMenuEntry.divider(),
            const CleanMenuEntry('settings', 'Titel & Hintergrund',
                icon: Icons.palette_outlined),
            const CleanMenuEntry('help', 'Tastenkürzel',
                icon: Icons.keyboard_outlined),
          ],
          onSelected: (v) async {
            switch (v) {
              case 'fit':
                _fitAll();
              case 'snap':
                _toggleSnap();
              case 'settings':
                await _rename();
              case 'help':
                await _showShortcuts();
            }
          },
        ),
      ],
    );
  }

  Future<void> _showShortcuts() => showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Tastenkürzel auf dem Canvas'),
          content: const SizedBox(
            width: 440,
            child: Text(
              'Enter – Karte beschreiben bzw. Verweis öffnen\n'
              'Esc – Schreiben beenden / Auswahl aufheben\n'
              'Tab – verbundene Karte rechts (Umschalt + Tab: darunter)\n'
              'Pfeiltasten – Karte verschieben (Umschalt: fein)\n'
              'Entf – Karte oder Verbindung löschen\n'
              'Strg/⌘ + Z / Y – rückgängig / wiederholen\n'
              'Strg/⌘ + C / X / V – kopieren / ausschneiden / einfügen\n'
              'Strg/⌘ + D – duplizieren\n\n'
              'Im Schreiben-Modus: P Stift, H Textmarker, E Radierer, '
              'L Lasso, S Formen, T Text, R Laser.',
              style: TextStyle(height: 1.6),
            ),
          ),
          actions: [
            FilledButton(
                onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
          ],
        ),
      );

  /// Zoomt so, dass alle Karten und Striche zu sehen sind.
  void _fitAll() {
    final c = _ink;
    if (c == null || _viewSize.isEmpty) return;
    final r = CanvasMinimap.contentBounds(c, _nodes);
    if (r == null) {
      c.camera.reset();
      return;
    }
    final sx = _viewSize.width / (r.width + 120);
    final sy = _viewSize.height / (r.height + 160);
    c.camera.lookAt(r.center, math.min(sx, sy), _viewSize);
  }

  @override
  Widget build(BuildContext context) {
    final board = _board;
    if (board == null) {
      return const Scaffold(body: Center(child: Text('Canvas nicht gefunden')));
    }
    final paper = PaperStyle.of(board.paper);
    final mf = context.mf;
    final showHint = _selected == null && _selectedEdge == null;

    return Focus(
      onKeyEvent: _onKey,
      child: Scaffold(
        backgroundColor: paper.sheet,
        body: Stack(
          children: [
            Positioned.fill(
              child: InkSurface(
                key: _surfaceKey,
                inkId: board.id,
                paper: board.paper,
                showInkTools: _mode == BoardMode.write,
                navBar: _nav,
                onSaved: _changed,
                onControllerReady: (c) {
                  _ink = c;
                  c.setDrawingEnabled(_mode == BoardMode.write);
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) setState(() {});
                  });
                },
                onBackgroundTap: _onBackgroundTap,
                backgroundBuilder: (camera) =>
                    DotGridPainter(camera, paper.line, fill: paper.sheet),
                overlayBuilder: (context, c) => _overlay(context, c, paper),
              ),
            ),
            if (_ink != null)
              Positioned(
                right: 16,
                bottom: 72,
                child: SafeArea(
                  top: false,
                  left: false,
                  child: CanvasMinimap(controller: _ink!, nodes: _nodes),
                ),
              ),
            if (_ink != null)
              Positioned(
                left: 16,
                right: 16,
                bottom: 72,
                child: SafeArea(
                  top: false,
                  child: ListenableBuilder(
                    listenable: _ink!.camera,
                    builder: (context, _) {
                      final c = _ink!;
                      final content = CanvasMinimap.contentBounds(c, _nodes);
                      final view = c.camera.viewport;
                      if (content == null ||
                          view.isEmpty ||
                          c.camera.visibleWorldRect(view).overlaps(content)) {
                        return const SizedBox.shrink();
                      }
                      return Center(
                        child: FilledButton.icon(
                          onPressed: _fitAll,
                          icon: const Icon(Icons.my_location, size: 18),
                          label: const Text('Zu deinen Inhalten'),
                        ),
                      );
                    },
                  ),
                ),
              ),
            if (showHint)
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
    );
  }
}

/// Schwebende Leiste, die über (oder unter) einem Bereich sitzt und
/// immer im Bild bleibt.
class _FloatingBar extends StatelessWidget {
  const _FloatingBar(
      {required this.anchor, required this.view, required this.children});

  final Rect anchor;
  final Size view;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    const h = 48.0;
    final maxW = math.max(160.0, view.width - 24);
    var top = anchor.top - h - 34;
    if (top < 8) top = anchor.bottom + 34;
    top = top.clamp(8.0, math.max(8.0, view.height - h - 8)).toDouble();
    final centerX = anchor.center.dx;
    return Positioned(
      top: top,
      left: 0,
      right: 0,
      child: Align(
        alignment: Alignment(
            view.width <= 0
                ? 0
                : ((centerX / view.width) * 2 - 1).clamp(-1.0, 1.0).toDouble(),
            0),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxW),
          child: FloatingPanel(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(mainAxisSize: MainAxisSize.min, children: children),
            ),
          ),
        ),
      ),
    );
  }
}

class _TbIcon extends StatelessWidget {
  const _TbIcon({required this.icon});
  final IconData icon;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 38,
        height: 38,
        child: Icon(icon, size: 19, color: context.mf.text),
      );
}

class _TbButton extends StatelessWidget {
  const _TbButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.active = false,
    this.danger = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool active;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final mf = context.mf;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: active ? mf.accentSoft : null,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon,
              size: 19,
              color: danger ? mf.danger : (active ? mf.accent : mf.text)),
        ),
      ),
    );
  }
}

class _TbDivider extends StatelessWidget {
  const _TbDivider();

  @override
  Widget build(BuildContext context) => Container(
        width: 1,
        height: 22,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        color: context.mf.border,
      );
}

/// Farbknopf mit Palette (Kartenfarben + eigene Farbe + neutral).
class _ColorButton extends StatefulWidget {
  const _ColorButton({required this.color, required this.onPick});

  final int? color;
  final ValueChanged<int?> onPick;

  @override
  State<_ColorButton> createState() => _ColorButtonState();
}

class _ColorButtonState extends State<_ColorButton> {
  final MenuController _menu = MenuController();

  @override
  Widget build(BuildContext context) {
    final mf = context.mf;
    final current = widget.color;
    Widget dot(int? c) {
      final selected = c == current;
      return GestureDetector(
        onTap: () {
          _menu.close();
          widget.onPick(c);
        },
        child: Container(
          width: 34,
          height: 34,
          margin: const EdgeInsets.all(3),
          padding: EdgeInsets.all(selected ? 3 : 0),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
                color: selected ? mf.accent : Colors.transparent, width: 2),
          ),
          child: Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: c == null ? mf.surfaceRaised : Color(c),
              border: Border.all(color: mf.border),
            ),
            child: c == null
                ? Icon(Icons.format_color_reset_outlined,
                    size: 15, color: mf.textMuted)
                : null,
          ),
        ),
      );
    }

    return MenuAnchor(
      controller: _menu,
      alignmentOffset: const Offset(0, 6),
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(mf.surface),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        padding: const WidgetStatePropertyAll(EdgeInsets.all(10)),
        shape: WidgetStatePropertyAll(RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: mf.border.withValues(alpha: 0.7)),
        )),
      ),
      menuChildren: [
        SizedBox(
          width: 210,
          child: Wrap(
            children: [
              dot(null),
              for (final c in kCardColors) dot(c),
              GestureDetector(
                onTap: () async {
                  _menu.close();
                  final picked = await pickColor(
                      context, Color(current ?? kCardColors.first));
                  if (picked != null) widget.onPick(picked.toARGB32());
                },
                child: Container(
                  width: 34,
                  height: 34,
                  margin: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: SweepGradient(colors: [
                      mf.accent,
                      mf.accent2,
                      const Color(0xFF22C55E),
                      const Color(0xFFFACC15),
                      const Color(0xFFEF4444),
                      mf.accent,
                    ]),
                  ),
                  child: const Icon(Icons.add, size: 16, color: Colors.white),
                ),
              ),
            ],
          ),
        ),
      ],
      builder: (context, ctrl, _) => Tooltip(
        message: 'Farbe',
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => ctrl.isOpen ? ctrl.close() : ctrl.open(),
          child: SizedBox(
            width: 38,
            height: 38,
            child: Center(
              child: Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: current == null ? mf.surfaceRaised : Color(current),
                  border: Border.all(color: mf.text.withValues(alpha: 0.4)),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Moderner Umschalter für die vier Canvas-Modi.
class _ModeSwitch extends StatelessWidget {
  const _ModeSwitch({required this.mode, required this.onChanged});

  final BoardMode mode;
  final ValueChanged<BoardMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final mf = context.mf;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: mf.surfaceRaised,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: mf.glassEdge),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final m in BoardMode.values)
            Tooltip(
              message: m.label,
              child: GestureDetector(
                onTap: () => onChanged(m),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  height: 32,
                  padding: EdgeInsets.symmetric(horizontal: mode == m ? 12 : 10),
                  decoration: BoxDecoration(
                    gradient: mode == m ? mf.gradient : null,
                    borderRadius: BorderRadius.circular(11),
                    boxShadow: mode == m
                        ? [BoxShadow(color: mf.glow, blurRadius: 12, spreadRadius: -4)]
                        : null,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(m.icon,
                          size: 17, color: mode == m ? Colors.white : mf.text),
                      if (mode == m) ...[
                        const SizedBox(width: 6),
                        Text(m.label,
                            style: const TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                                color: Colors.white)),
                      ],
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
