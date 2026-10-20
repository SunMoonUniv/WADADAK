import 'dart:math' as math;

import 'recording_models.dart';
import 'run_lap.dart';

/// PACE_V3 rejects isolated speed-inconsistent fixes; PACE_V2 stays replayable.
class MotionPace {
  static bool usesMotion(String? version) =>
      version == 'PACE_V2' || version == 'PACE_V3';
  bool _balanced = false;
  RunInput? _suspect;
  RunInput? _rawPrevious;
  double distanceM = 0;
  int _stoppedMs = 0;
  int? _stationarySince;
  RunInput? _previous;
  final List<RunInput> _pending = [];
  final List<_Travel> _recent = [];
  final List<RunTravel> travels = [];
  final List<RunTimeSpan> stops = [];
  final List<List<RunInput>> segments = [];
  List<RunInput>? _segment;
  bool paused = false, ended = false;
  bool get stationary => _stationarySince != null;

  void add(RunInput p) {
    if (ended) return;
    if (p.kind == RunKind.start) _balanced = p.reason == 'PACE_V3';
    if (!_balanced ||
        p.kind == RunKind.start ||
        p.kind == RunKind.cadence ||
        p.kind == RunKind.barometer ||
        p.kind == RunKind.segmentEnd) {
      _accept(p);
      return;
    }
    if (p.kind != RunKind.gps || paused) {
      // An unconfirmed outlier is never joined across a recording boundary.
      _suspect = null;
      _rawPrevious = null;
      _accept(p);
      return;
    }
    // Hard GPS boundaries use consecutive RAW fixes, before soft outlier removal.
    // A removed point must never hide a >12m/s jump or a missing interval.
    final rawPrevious = _rawPrevious;
    _rawPrevious = p.good && p.accuracyM! <= 15 ? p : null;
    final dt = rawPrevious == null ? null : p.elapsedMs - rawPrevious.elapsedMs;
    if (!p.good ||
        p.accuracyM! > 15 ||
        (dt != null &&
            (dt <= 0 ||
                dt > 10000 ||
                rawPrevious!.distanceTo(p) * 1000 / dt > 12))) {
      _suspect = null;
      _closeStop(_previous?.elapsedMs);
      _resetWindow();
      _accept(p);
      return;
    }
    final suspect = _suspect;
    _suspect = null;
    if (suspect != null) {
      if (_previous != null && _isolated(_previous!, suspect, p)) {
        _accept(p);
        return;
      }
      _accept(suspect);
    }
    if (_previous != null && _suspectLeg(_previous!, p)) {
      _suspect = p;
      return;
    }
    _accept(p);
  }

  bool _suspectLeg(RunInput a, RunInput b) {
    final dt = b.elapsedMs - a.elapsedMs;
    if (!a.good ||
        !b.good ||
        a.accuracyM! > 15 ||
        b.accuracyM! > 15 ||
        dt <= 0 ||
        dt > 3000 ||
        !_reliableSpeed(a) ||
        !_reliableSpeed(b)) {
      return false;
    }
    final expected =
        (a.speedMps! +
            b.speedMps! +
            a.speedAccuracyMps! +
            b.speedAccuracyMps!) *
        .5 *
        dt /
        1000;
    return a.distanceTo(b) >
        expected + math.max(6, a.accuracyM! + b.accuracyM!);
  }

  bool _isolated(RunInput a, RunInput b, RunInput c) {
    if (!_suspectLeg(b, c) || !c.good || !_reliableSpeed(c)) return false;
    final dt = c.elapsedMs - a.elapsedMs;
    final direct = a.distanceTo(c);
    final expected =
        (a.speedMps! +
            c.speedMps! +
            a.speedAccuracyMps! +
            c.speedAccuracyMps!) *
        .5 *
        dt /
        1000;
    return direct <= expected + math.max(6, a.accuracyM! + c.accuracyM!) &&
        a.distanceTo(b) + b.distanceTo(c) - direct >
            math.max(8, a.accuracyM! + b.accuracyM! + c.accuracyM!);
  }

  void _accept(RunInput p) {
    if (ended) return;
    if (p.kind != RunKind.gps) {
      if (p.kind == RunKind.start ||
          p.kind == RunKind.cadence ||
          p.kind == RunKind.barometer ||
          p.kind == RunKind.segmentEnd) {
        return;
      }
      // Unknown GPS time must never be subtracted as stationary time.
      _closeStop(p.kind == RunKind.gap ? _previous?.elapsedMs : p.elapsedMs);
      _resetWindow();
      if (p.kind == RunKind.pause) paused = true;
      if (p.kind == RunKind.resume) paused = false;
      if (p.kind == RunKind.end) ended = true;
      return;
    }
    if (paused) return;
    if (!p.good || p.accuracyM! > 15) {
      _closeStop(_previous?.elapsedMs);
      _resetWindow();
      return;
    }
    final previous = _previous;
    if (previous != null) {
      final dt = p.elapsedMs - previous.elapsedMs;
      if (dt <= 0 || dt > 10000 || previous.distanceTo(p) / (dt / 1000) > 12) {
        _closeStop(previous.elapsedMs);
        _resetWindow();
      }
    }
    _previous = p;
    if (_pending.isEmpty) {
      _pending.add(p);
      return;
    }
    _pending.add(p);
    final anchor = _pending.first;
    final span = p.elapsedMs - anchor.elapsedMs;
    final displacement = anchor.distanceTo(p);
    var path = 0.0;
    for (var i = 1; i < _pending.length; i++) {
      path += _pending[i - 1].distanceTo(_pending[i]);
    }
    final lastThree = _pending.length >= 3
        ? _pending.sublist(_pending.length - 3)
        : const <RunInput>[];
    final speedEvidence =
        lastThree.length == 3 &&
        lastThree.every((f) => _reliableSpeed(f) && f.speedMps! >= .3);
    final speedSaysStopped =
        lastThree.length == 3 &&
        lastThree.every((f) => _reliableSpeed(f) && f.speedMps! <= .2);
    final threshold = speedEvidence
        ? 3.0
        : math.max(5.0, anchor.accuracyM! + p.accuracyM!);
    final coherent = path > 0 && displacement / path >= .7;
    if (_pending.length >= 3 &&
        span >= 2000 &&
        anchor.accuracyM! <= 15 &&
        p.accuracyM! <= 15 &&
        !speedSaysStopped &&
        (speedEvidence
            ? path + .001 >= threshold
            : displacement + .001 >= threshold && coherent)) {
      _closeStop(anchor.elapsedMs);
      _segment ??= _newSegment(anchor);
      for (var i = 1; i < _pending.length; i++) {
        final a = _pending[i - 1], b = _pending[i];
        final d = a.distanceTo(b);
        distanceM += d;
        travels.add(RunTravel(a.elapsedMs, b.elapsedMs, d));
        _recent.add(_Travel(a.elapsedMs, b.elapsedMs, d));
        _segment!.add(b);
      }
      _pending.clear();
      _pending.add(p);
      _recent.removeWhere((t) => t.end <= p.elapsedMs - 10000);
      return;
    }
    final radius = math.max(3.0, math.min(6.0, anchor.accuracyM!));
    final confined = _pending.every(
      (f) => f.accuracyM! <= 15 && anchor.distanceTo(f) <= radius,
    );
    final speedSaysMoving =
        lastThree.any((f) => _reliableSpeed(f) && f.speedMps! >= .3) ||
        (!speedSaysStopped &&
            span >= 2000 &&
            displacement >= math.max(1.5, radius * .5) &&
            coherent &&
            displacement / (span / 1000) >= .3);
    if (_pending.length >= 3 && span >= 5000 && confined && !speedSaysMoving) {
      _stationarySince ??= anchor.elapsedMs;
      _segment = null;
      _recent.clear();
      _pending.clear();
      _pending.add(p);
    } else if (span > 10000 || _pending.length > 30) {
      // Ambiguous drift is neither proven movement nor proven rest.
      _closeStop(anchor.elapsedMs);
      _resetWindow();
      _previous = p;
      _pending.add(p);
    }
  }

  bool _reliableSpeed(RunInput p) =>
      p.speedMps != null &&
      p.speedAccuracyMps != null &&
      p.speedMps!.isFinite &&
      p.speedMps! >= 0 &&
      p.speedMps! <= 12 &&
      p.speedAccuracyMps!.isFinite &&
      p.speedAccuracyMps! > 0 &&
      p.speedAccuracyMps! <= .5;

  List<RunInput> _newSegment(RunInput anchor) {
    final segment = <RunInput>[anchor];
    segments.add(segment);
    return segment;
  }

  void _closeStop(int? ms) {
    if (_stationarySince != null && ms != null) {
      final knownEnd = _previous == null
          ? ms
          : math.min(ms, _previous!.elapsedMs + 10000);
      _stoppedMs += math.max(0, knownEnd - _stationarySince!);
      if (knownEnd > _stationarySince!) {
        stops.add(RunTimeSpan(_stationarySince!, knownEnd));
      }
    }
    _stationarySince = null;
  }

  void _resetWindow() {
    _pending.clear();
    _recent.clear();
    _previous = null;
    _segment = null;
  }

  int stoppedBefore(int ms) {
    var result = stops.fold<int>(0, (sum, s) => sum + s.before(ms));
    if (_stationarySince != null) {
      final end = _previous == null
          ? ms
          : math.min(ms, _previous!.elapsedMs + 10000);
      result += math.max(0, math.min(ms, end) - _stationarySince!);
    }
    return result;
  }

  int movingMs(int ms, int activeMs) {
    final lastFix = _previous?.elapsedMs;
    // A confirmed stop continues while fixes are fresh; a GPS outage is unknown.
    final stopEnd = lastFix == null ? ms : math.min(ms, lastFix + 10000);
    final ongoing = _stationarySince == null
        ? 0
        : math.max(0, stopEnd - _stationarySince!);
    return (activeMs - _stoppedMs - ongoing).clamp(0, activeMs);
  }

  double? currentPace(int ms) {
    if (paused ||
        ended ||
        stationary ||
        _previous == null ||
        ms - _previous!.elapsedMs > 10000) {
      return null;
    }
    final end = _previous!.elapsedMs;
    final from = end - 10000;
    var duration = 0.0, distance = 0.0;
    for (final t in _recent) {
      final overlap = t.end - math.max(from, t.start);
      if (overlap <= 0) continue;
      duration += overlap;
      distance += t.distance * overlap / (t.end - t.start);
    }
    return duration >= 3000 && distance >= 3 ? duration / distance : null;
  }
}

class _Travel {
  const _Travel(this.start, this.end, this.distance);
  final int start, end;
  final double distance;
}
