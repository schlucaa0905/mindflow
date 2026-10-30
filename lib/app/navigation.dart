import 'package:flutter/material.dart';

import '../data/models.dart';
import '../features/canvas/board_screen.dart';
import '../features/documents/document_screen.dart';
import '../features/knowledge/knowledge_entry_screen.dart';
import '../features/notebook/notebook_screen.dart';

/// Öffnet ein beliebiges Objekt an der richtigen Stelle.
/// Funktioniert nur über die stabile ID – Name oder Ort sind egal.
Future<void> openObject(BuildContext context, MfObject o,
    {String? focusNodeId}) {
  final nav = Navigator.of(context);
  switch (o.type) {
    case ObjectType.notebook:
      return nav.push(MaterialPageRoute<void>(
          builder: (_) => NotebookScreen(notebookId: o.id)));
    case ObjectType.page:
      final parent = o.parentId;
      if (parent == null) return Future.value();
      return nav.push(MaterialPageRoute<void>(
          builder: (_) =>
              NotebookScreen(notebookId: parent, initialPageId: o.id)));
    case ObjectType.board:
      return nav.push(MaterialPageRoute<void>(
          builder: (_) => BoardScreen(boardId: o.id, focusNodeId: focusNodeId)));
    case ObjectType.document:
      return nav.push(MaterialPageRoute<void>(
          builder: (_) => DocumentScreen(documentId: o.id)));
    case ObjectType.knowledge:
      return nav.push(MaterialPageRoute<void>(
          builder: (_) => KnowledgeEntryScreen(entryId: o.id)));
    case ObjectType.flashcard:
      return Future.value();
  }
}
