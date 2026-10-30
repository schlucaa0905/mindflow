import 'ink_scene.dart';
import 'stroke.dart';

/// Eine rückgängig machbare Aktion.
sealed class InkAction {
  void apply(InkScene scene);
  void revert(InkScene scene);
}

/// Striche wurden hinzugefügt. Rückgängig = als gelöscht markieren.
class AddStrokes extends InkAction {
  AddStrokes(this.strokes);
  final List<Stroke> strokes;

  @override
  void apply(InkScene scene) => scene.setDeleted(strokes, false);
  @override
  void revert(InkScene scene) => scene.setDeleted(strokes, true);
}

/// Striche wurden radiert. Rückgängig = wiederherstellen.
class EraseStrokes extends InkAction {
  EraseStrokes(this.strokes);
  final List<Stroke> strokes;

  @override
  void apply(InkScene scene) => scene.setDeleted(strokes, true);
  @override
  void revert(InkScene scene) => scene.setDeleted(strokes, false);
}

/// Striche wurden durch andere ersetzt (verschieben, umfärben,
/// teilweise radieren). Rückgängig = Originale zurück, Ersatz weg.
class ReplaceStrokes extends InkAction {
  ReplaceStrokes({required this.removed, required this.added});
  final List<Stroke> removed;
  final List<Stroke> added;

  @override
  void apply(InkScene scene) {
    scene.setDeleted(removed, true);
    scene.setDeleted(added, false);
  }

  @override
  void revert(InkScene scene) {
    scene.setDeleted(added, true);
    scene.setDeleted(removed, false);
  }
}

class InkHistory {
  static const int limit = 300;

  final List<InkAction> _undo = [];
  final List<InkAction> _redo = [];

  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;

  /// Speichert eine bereits ausgeführte Aktion.
  void push(InkAction action) {
    _undo.add(action);
    if (_undo.length > limit) _undo.removeAt(0);
    _redo.clear();
  }

  bool undo(InkScene scene) {
    if (_undo.isEmpty) return false;
    final a = _undo.removeLast()..revert(scene);
    _redo.add(a);
    return true;
  }

  bool redo(InkScene scene) {
    if (_redo.isEmpty) return false;
    final a = _redo.removeLast()..apply(scene);
    _undo.add(a);
    return true;
  }

  void clear() {
    _undo.clear();
    _redo.clear();
  }
}
