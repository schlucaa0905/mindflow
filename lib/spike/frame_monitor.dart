import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

/// Ergebnis einer Messung.
class FrameReport {
  FrameReport({
    required this.frames,
    required this.seconds,
    required this.avgMs,
    required this.worstMs,
    required this.slowShare,
  });

  final int frames;
  final double seconds;
  final double avgMs;
  final double worstMs;

  /// Anteil der Bilder, die länger als 16,7 ms (60 Bilder/s) gebraucht haben.
  final double slowShare;

  double get fps => seconds > 0 ? frames / seconds : 0;

  bool get passes => avgMs <= 12 && slowShare <= 0.05;
}

/// Misst echte Bildzeiten über die Flutter-Engine (Bauen + Zeichnen).
/// Aussagekräftig nur im Profil- oder Release-Modus, nicht im Debug-Modus.
class FrameMonitor {
  final ValueNotifier<String> live = ValueNotifier('–');
  final List<double> _recording = [];
  bool _recordingActive = false;
  DateTime? _recordStart;

  void start() => SchedulerBinding.instance.addTimingsCallback(_onTimings);
  void stop() => SchedulerBinding.instance.removeTimingsCallback(_onTimings);

  void beginRecording() {
    _recording.clear();
    _recordingActive = true;
    _recordStart = DateTime.now();
  }

  FrameReport endRecording() {
    _recordingActive = false;
    final secs = _recordStart == null
        ? 0.0
        : DateTime.now().difference(_recordStart!).inMilliseconds / 1000;
    final n = _recording.length;
    final avg = n == 0 ? 0.0 : _recording.reduce((a, b) => a + b) / n;
    final worst = n == 0 ? 0.0 : _recording.reduce(math.max);
    final slow = n == 0 ? 0.0 : _recording.where((t) => t > 16.7).length / n;
    return FrameReport(
        frames: n, seconds: secs, avgMs: avg, worstMs: worst, slowShare: slow);
  }

  void _onTimings(List<FrameTiming> timings) {
    if (timings.isEmpty) return;
    var sum = 0.0, worst = 0.0;
    for (final t in timings) {
      final ms = _workMs(t);
      sum += ms;
      worst = math.max(worst, ms);
      if (_recordingActive) _recording.add(ms);
    }
    live.value =
        'Ø ${(sum / timings.length).toStringAsFixed(1)} ms · max ${worst.toStringAsFixed(1)} ms';
  }

  /// Bauen und Zeichnen laufen parallel in getrennten Threads – das
  /// langsamere von beiden begrenzt die Bildrate.
  static double _workMs(FrameTiming t) =>
      math.max(t.buildDuration.inMicroseconds, t.rasterDuration.inMicroseconds) /
      1000;

  void dispose() {
    stop();
    live.dispose();
  }
}
