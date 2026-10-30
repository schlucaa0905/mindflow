import 'dart:async';

import 'package:flutter/widgets.dart';

import '../storage/ink_store.dart';
import 'ink_controller.dart';

/// Lädt die Handschrift eines Objekts und speichert sie automatisch.
///
/// - Speichert 0,8 s nach der letzten Änderung.
/// - Speichert sofort, wenn die App in den Hintergrund geht.
/// - Speichert beim Schließen ([close]).
class InkSession with WidgetsBindingObserver {
  InkSession({required this.controller, required this.store, this.onSaved});

  final InkController controller;
  final InkStore store;
  final VoidCallback? onSaved;

  final ValueNotifier<String> status = ValueNotifier('Lade …');
  bool loaded = false;
  bool _closed = false;
  int _savedRevision = 0;
  Timer? _timer;
  bool _saving = false;

  Future<void> start() async {
    WidgetsBinding.instance.addObserver(this);
    controller.scene.addListener(_schedule);
    try {
      final strokes = await store.load();
      if (_closed) return;
      controller.scene.replaceAll(strokes);
      _setStatus('Gespeichert');
    } on FormatException catch (e) {
      _setStatus('Datei beschädigt und beiseitegelegt (${e.message})');
    } catch (e) {
      _setStatus('Laden fehlgeschlagen: $e');
    }
    _savedRevision = controller.scene.revision;
    loaded = true;
  }

  void _setStatus(String s) {
    if (!_closed) status.value = s;
  }

  void _schedule() {
    if (!loaded || controller.scene.revision == _savedRevision) return;
    _setStatus('Ungespeichert');
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 800), saveNow);
  }

  Future<void> saveNow() async {
    if (!loaded) return;
    if (_saving) {
      _timer?.cancel();
      _timer = Timer(const Duration(milliseconds: 300), saveNow);
      return;
    }
    final rev = controller.scene.revision;
    if (rev == _savedRevision) return;
    _saving = true;
    try {
      await store.save(controller.scene.strokes);
      _savedRevision = rev;
      _setStatus('Gespeichert');
      onSaved?.call();
    } catch (e) {
      _setStatus('Speichern fehlgeschlagen: $e');
    } finally {
      _saving = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _timer?.cancel();
      saveNow();
    }
  }

  /// Speichert ein letztes Mal und meldet sich ab.
  Future<void> close() async {
    WidgetsBinding.instance.removeObserver(this);
    controller.scene.removeListener(_schedule);
    _timer?.cancel();
    final pending = saveNow();
    _closed = true;
    await pending;
  }
}
