import 'dart:math' as math;

import 'recording_models.dart';

/// Only fresh, precise GPS can confirm a 10-second stationary interval.
/// Missing GPS, poor fixes, implausible jumps and confirmed movement reset it.
class RunAutoPause {
  static const stationaryMs = 10000;
  RunInput? _anchor, _previous;
  int _fixes = 0;

  void reset() {
    _anchor = _previous = null;
    _fixes = 0;
  }

  bool add(RunInput input) {
    if (!input.good || input.accuracyM! > 15) {
      reset();
      return false;
    }
    final previous = _previous;
    final interval = previous == null
        ? null
        : input.elapsedMs - previous.elapsedMs;
    final moving =
        input.speedMps != null &&
        input.speedAccuracyMps != null &&
        input.speedAccuracyMps! <= 1 &&
        input.speedMps! >= .5;
    if (moving ||
        interval != null &&
            (interval <= 0 ||
                interval > 10000 ||
                previous!.distanceTo(input) > interval / 1000 * 12)) {
      reset();
      return false;
    }
    _previous = input;
    final anchor = _anchor;
    final radius = anchor == null
        ? 0.0
        : math.min(
            4.0,
            math.max(2.0, (anchor.accuracyM! + input.accuracyM!) / 4),
          );
    if (anchor == null || anchor.distanceTo(input) > radius) {
      _anchor = input;
      _fixes = 1;
      return false;
    }
    _fixes++;
    return _fixes >= 3 && input.elapsedMs - anchor.elapsedMs >= stationaryMs;
  }
}
