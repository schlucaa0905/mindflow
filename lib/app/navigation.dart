import 'package:flutter/material.dart';

import '../data/models.dart';
import 'services.dart';
import '../features/common/object_picker.dart';
import '../features/canvas/board_screen.dart';
import '../features/documents/document_screen.dart';
import '../features/knowledge/knowledge_entry_screen.dart';
import '../features/notebook/notebook_screen.dart';

/// Seite für ein Objekt (Notizbuch, PDF, Canvas, Wissen …) oder null.
Route<void>? routeFor(MfObject o, {String? focusNodeId}) {
  final p = screenFor(o, focusNodeId: focusNodeId);
  return p == null ? null : MaterialPageRoute<void>(builder: (_) => p);
}

/// Bildschirm für ein Objekt (auch für die geteilte Ansicht).
Widget? screenFor(MfObject o, {String? focusNodeId}) {
  Widget? page;
  switch (o.type) {
    case ObjectType.notebook:
      page = NotebookScreen(notebookId: o.id);
    case ObjectType.page:
      final parent = o.parentId;
      if (parent != null) {
        page = NotebookScreen(notebookId: parent, initialPageId: o.id);
      }
    case ObjectType.board:
      page = BoardScreen(boardId: o.id, focusNodeId: focusNodeId);
    case ObjectType.document:
      page = DocumentScreen(documentId: o.id);
    case ObjectType.knowledge:
      page = KnowledgeEntryScreen(entryId: o.id);
    case ObjectType.flashcard:
      final entryId = o.parentId;
      if (entryId != null) page = KnowledgeEntryScreen(entryId: entryId);
  }
  return page;
}

/// Zweiten Inhalt wählen und neben [left] öffnen.
Future<void> openSplitWith(BuildContext context, MfObject left) async {
  final right = await pickObject(context,
      title: 'Daneben öffnen …',
      types: {
        ObjectType.notebook,
        ObjectType.page,
        ObjectType.document,
        ObjectType.board,
        ObjectType.knowledge,
      },
      exclude: {left.id});
  if (right == null || !context.mounted) return;
  await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => SplitScreen(left: left, right: right)));
}

/// Zwei Inhalte nebeneinander (wie Goodnotes): Trennlinie verschiebbar,
/// Griff in der Mitte zum Tauschen oder Schließen einer Seite.
class SplitScreen extends StatefulWidget {
  const SplitScreen({super.key, required this.left, required this.right});

  final MfObject left;
  final MfObject right;

  @override
  State<SplitScreen> createState() => _SplitScreenState();
}

class _SplitScreenState extends State<SplitScreen> {
  late MfObject _a = widget.left, _b = widget.right;
  double _f = 0.5;

  Widget _pane(MfObject o, double width) => SizedBox(
        width: width,
        child: ClipRect(
          child: MediaQuery(
            // Jede Hälfte richtet ihre Leisten nach ihrer eigenen Breite.
            data: MediaQuery.of(context).copyWith(
                size: Size(width, MediaQuery.of(context).size.height)),
            child: KeyedSubtree(
                key: ValueKey(o.id), child: screenFor(o) ?? const SizedBox()),
          ),
        ),
      );

  void _keepOnly(MfObject o) {
    final r = routeFor(o);
    if (r != null) Navigator.of(context).pushReplacement(r);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: LayoutBuilder(builder: (context, box) {
        const bar = 14.0;
        final w = box.maxWidth - bar;
        return Row(children: [
          _pane(_a, w * _f),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragUpdate: (d) => setState(() => _f =
                (_f + d.delta.dx / w).clamp(0.25, 0.75).toDouble()),
            child: Container(
              width: bar,
              color: Colors.black,
              alignment: Alignment.center,
              child: PopupMenuButton<String>(
                tooltip: 'Geteilte Ansicht',
                padding: EdgeInsets.zero,
                icon: Container(
                  width: 6,
                  height: 46,
                  decoration: BoxDecoration(
                    color: Colors.white70,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                onSelected: (v) {
                  switch (v) {
                    case 'swap':
                      setState(() {
                        final t = _a;
                        _a = _b;
                        _b = t;
                      });
                    case 'left':
                      _keepOnly(_a);
                    case 'right':
                      _keepOnly(_b);
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'swap', child: Text('Seiten tauschen')),
                  PopupMenuItem(value: 'left', child: Text('Nur links behalten')),
                  PopupMenuItem(
                      value: 'right', child: Text('Nur rechts behalten')),
                ],
              ),
            ),
          ),
          _pane(_b, w * (1 - _f)),
        ]);
      }),
    );
  }
}

/// Tab-ID: Seiten gehören zu ihrem Notizbuch; Wissen hat keine Tabs.
String? tabIdFor(MfObject o) => switch (o.type) {
      ObjectType.notebook || ObjectType.board || ObjectType.document => o.id,
      ObjectType.page => o.parentId,
      _ => null,
    };

/// Öffnet ein beliebiges Objekt an der richtigen Stelle (über die stabile
/// ID – Name oder Ort sind egal) und merkt es sich als Tab.
Future<void> openObject(BuildContext context, MfObject o,
    {String? focusNodeId, bool replace = false}) {
  final route = routeFor(o, focusNodeId: focusNodeId);
  if (route == null) return Future.value();
  final tab = tabIdFor(o);
  final s = Services.maybeOf(context);
  if (tab != null && s != null && !s.tabs.value.contains(tab)) {
    s.tabs.value = [...s.tabs.value, tab];
  }
  final nav = Navigator.of(context);
  return replace ? nav.pushReplacement(route) : nav.push(route);
}
