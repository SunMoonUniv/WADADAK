import 'dart:math' as math;

class RunCadenceSample {
  const RunCadenceSample(this.endMs, this.durationMs, this.steps);
  final int endMs, durationMs, steps;
  int get startMs => endMs - durationMs;
}

/// Counts measured steps over sensor coverage; absent samples never become zero steps.
class RunCadenceCalculator {
  int steps = 0, coverageMs = 0;
  int _lastEnd = 0;
  final List<RunCadenceSample> _recent = [];
  void add(int elapsedMs, int count, int durationMs) {
    if (durationMs <= 0 ||
        durationMs > 10000 ||
        count < 0 ||
        count * 1000 > durationMs * 5 ||
        elapsedMs - durationMs < _lastEnd) {
      return;
    }
    _lastEnd = elapsedMs;
    steps += count;
    coverageMs += durationMs;
    _recent.add(RunCadenceSample(elapsedMs, durationMs, count));
    _recent.removeWhere((s) => s.endMs <= elapsedMs - 10000);
  }

  double? get average => coverageMs > 0 ? steps * 60000 / coverageMs : null;
  double? current(int ms) {
    if (_recent.isEmpty || ms - _lastEnd > 10000) return null;
    var count = 0.0, duration = 0;
    for (final s in _recent) {
      final overlap = s.endMs - math.max(s.startMs, _lastEnd - 10000);
      if (overlap <= 0) continue;
      count += s.steps * overlap / s.durationMs;
      duration += overlap.toInt();
    }
    return duration >= 3000 ? count * 60000 / duration : null;
  }
}
